@tool
class_name CodaEventTimeline
extends RefCounted

## Per-event timeline data — alternative authoring model to the event graph.
## The event's `event_authoring_mode` selects which model the runtime schedules.
##
## Length / loop region are seconds (linear time). `tempo_bpm > 0` enables a bars/beats
## ruler in the editor; the runtime ignores it (timeline scheduling is purely time-based
## in the MVP).

const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_track.gd"
)
const CodaTimelineMarkerScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_marker.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)

const DEFAULT_LENGTH_SECONDS := 8.0
const MIN_SPLIT_SEGMENT_SECONDS := 0.02
const UNSET_WORK_POINT := -1.0
const MIN_WORK_AREA_GAP_SECONDS := 0.01

var length_seconds: float = DEFAULT_LENGTH_SECONDS
var tempo_bpm: float = 0.0
var time_signature: Vector2i = Vector2i(4, 4)
var loop_enabled: bool = false
var loop_start_seconds: float = 0.0
var loop_end_seconds: float = 0.0
var tracks: Array[CodaTimelineTrack] = []
var markers: Array[CodaTimelineMarker] = []
## Editor work-area bounds (not serialized). -1 means unset.
var in_point_seconds: float = UNSET_WORK_POINT
var out_point_seconds: float = UNSET_WORK_POINT

var _clip_index: Dictionary = {}
var _clip_index_valid: bool = false


func _init() -> void:
	pass


static func make_default() -> CodaEventTimeline:
	var t := CodaEventTimeline.new()
	t.tracks.append(CodaTimelineTrackScript.new())
	return t


func find_track(track_id: String) -> CodaTimelineTrack:
	for t in tracks:
		if t.id == track_id:
			return t
	return null


func find_clip(clip_id: String) -> Dictionary:
	if not _clip_index_valid:
		_rebuild_clip_index()
	return _clip_index.get(clip_id, {}) as Dictionary


func invalidate_clip_index() -> void:
	_clip_index_valid = false


func _rebuild_clip_index() -> void:
	_clip_index.clear()
	for t in tracks:
		for c in t.clips:
			_clip_index[c.id] = {"track": t, "clip": c}
	_clip_index_valid = true


func find_marker(marker_id: String) -> CodaTimelineMarker:
	for m in markers:
		if m.id == marker_id:
			return m
	return null


func remove_track(track_id: String) -> bool:
	for i in range(tracks.size()):
		if tracks[i].id == track_id:
			tracks.remove_at(i)
			invalidate_clip_index()
			return true
	return false


## Reorder tracks by drag-and-drop in the editor. [from_index] is removed first, then inserted at [to_index] (0-based).
func reorder_tracks_move(from_index: int, to_index: int) -> void:
	if tracks.is_empty():
		return
	from_index = clampi(from_index, 0, tracks.size() - 1)
	to_index = clampi(to_index, 0, tracks.size() - 1)
	if from_index == to_index:
		return
	var tr: CodaTimelineTrack = tracks[from_index]
	tracks.remove_at(from_index)
	tracks.insert(clampi(to_index, 0, tracks.size()), tr)
	invalidate_clip_index()


func has_in_point() -> bool:
	return in_point_seconds >= 0.0


func has_out_point() -> bool:
	return out_point_seconds >= 0.0


func has_work_area() -> bool:
	return has_in_point() or has_out_point()


func work_area_start() -> float:
	return in_point_seconds if has_in_point() else 0.0


func work_area_end() -> float:
	return minf(out_point_seconds, length_seconds) if has_out_point() else length_seconds


func clamp_time_to_work_area(t: float) -> float:
	return clampf(t, work_area_start(), work_area_end())


func clear_in_point() -> void:
	in_point_seconds = UNSET_WORK_POINT


func clear_out_point() -> void:
	out_point_seconds = UNSET_WORK_POINT


func clamp_work_points_to_length() -> void:
	if has_in_point():
		in_point_seconds = clampf(in_point_seconds, 0.0, length_seconds)
	if has_out_point():
		out_point_seconds = clampf(out_point_seconds, 0.0, length_seconds)
	if has_in_point() and has_out_point() and out_point_seconds <= in_point_seconds:
		out_point_seconds = minf(
			length_seconds, in_point_seconds + MIN_WORK_AREA_GAP_SECONDS
		)
	if loop_enabled:
		clamp_loop_region_to_length()


func clamp_loop_region_to_length() -> void:
	if not loop_enabled:
		return
	if has_work_area():
		loop_start_seconds = work_area_start()
		loop_end_seconds = work_area_end()
		return
	loop_start_seconds = clampf(loop_start_seconds, 0.0, length_seconds)
	var min_end: float = minf(
		length_seconds, loop_start_seconds + MIN_WORK_AREA_GAP_SECONDS
	)
	loop_end_seconds = clampf(loop_end_seconds, min_end, length_seconds)
	if loop_end_seconds <= loop_start_seconds:
		loop_start_seconds = 0.0
		loop_end_seconds = length_seconds


func remove_marker(marker_id: String) -> bool:
	for i in range(markers.size()):
		if markers[i].id == marker_id:
			markers.remove_at(i)
			return true
	return false


func _sort_track_clips(track: CodaTimelineTrack) -> void:
	track.clips.sort_custom(
		func(a: CodaTimelineClip, b: CodaTimelineClip) -> bool: return a.start_seconds < b.start_seconds
	)


## Split one clip at [split_seconds] on the timeline axis. Returns "" on success.
func split_clip_at_time(clip_id: String, split_seconds: float) -> String:
	var info: Dictionary = find_clip(clip_id)
	if info.is_empty():
		return "Clip not found."
	var c: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	var tr: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
	if c == null or tr == null:
		return "Clip not found."
	var s0: float = c.start_seconds
	var end_t: float = c.start_seconds + c.duration_seconds
	if split_seconds <= s0 + MIN_SPLIT_SEGMENT_SECONDS:
		return "Split time is too close to the clip start."
	if split_seconds >= end_t - MIN_SPLIT_SEGMENT_SECONDS:
		return "Split time is too close to the clip end."
	var left_duration: float = split_seconds - s0
	var right_duration: float = end_t - split_seconds
	var saved_dur: float = c.duration_seconds
	var saved_fo: float = c.fade_out_seconds
	var right: CodaTimelineClip = CodaTimelineClipScript.new()
	right.audio_path = c.audio_path
	right.start_seconds = split_seconds
	right.duration_seconds = right_duration
	right.offset_seconds = c.offset_seconds + left_duration
	right.volume_db = c.volume_db
	right.pitch_scale = c.pitch_scale
	right.fade_in_seconds = 0.0
	right.fade_out_seconds = c.fade_out_seconds
	# Both segments must keep the same insert chain; new effect ids so undo/serialization stay consistent.
	for e in c.effects:
		right.effects.append(e.clone_new_id())
	c.duration_seconds = left_duration
	c.fade_out_seconds = 0.0
	tr.clips.append(right)
	_sort_track_clips(tr)
	invalidate_clip_index()
	var err: String = validate()
	if not err.is_empty():
		c.duration_seconds = saved_dur
		c.fade_out_seconds = saved_fo
		tr.clips.erase(right)
		_sort_track_clips(tr)
		return err
	return ""


## Place a copy after this clip (same lane). Returns "" on success.
func duplicate_clip(clip_id: String, gap_seconds: float = 0.05) -> String:
	var info: Dictionary = find_clip(clip_id)
	if info.is_empty():
		return "Clip not found."
	var c: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	var tr: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
	if c == null or tr == null:
		return "Clip not found."
	var d: Dictionary = c.to_dictionary()
	d.erase("id")
	var dup: CodaTimelineClip = CodaTimelineClipScript.from_dictionary(d)
	# New clip id only; effect entries still carried source ids from serialization. Assign
	# fresh ids so the duplicate cannot collide with the original (same invariant as split).
	for i in range(dup.effects.size()):
		dup.effects[i] = dup.effects[i].clone_new_id()
	var new_start: float = c.start_seconds + c.duration_seconds + max(0.0, gap_seconds)
	var max_src: float = dup.max_source_playable_seconds()
	dup.start_seconds = new_start
	dup.duration_seconds = minf(c.duration_seconds, max_src)
	dup.offset_seconds = c.offset_seconds
	tr.clips.append(dup)
	_sort_track_clips(tr)
	invalidate_clip_index()
	var err2: String = validate()
	if not err2.is_empty():
		tr.clips.erase(dup)
		_sort_track_clips(tr)
		return err2
	return ""


## Insert a clip copied from [data] at [start_seconds] on [track_index]. Returns result dict.
func paste_clip_at(track_index: int, start_seconds: float, data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {"error": "Nothing to paste.", "clip_id": ""}
	if tracks.is_empty():
		return {"error": "No tracks on timeline.", "clip_id": ""}
	var tr_i: int = clampi(track_index, 0, tracks.size() - 1)
	var tr: CodaTimelineTrack = tracks[tr_i]
	var d: Dictionary = data.duplicate(true)
	d.erase("id")
	var clip: CodaTimelineClip = CodaTimelineClipScript.from_dictionary(d)
	for i in range(clip.effects.size()):
		clip.effects[i] = clip.effects[i].clone_new_id()
	clip.start_seconds = maxf(0.0, start_seconds)
	var max_src: float = clip.max_source_playable_seconds()
	clip.duration_seconds = minf(clip.duration_seconds, max_src)
	if clip.duration_seconds < MIN_SPLIT_SEGMENT_SECONDS:
		return {"error": "Clip is too short to paste.", "clip_id": ""}
	tr.clips.append(clip)
	_sort_track_clips(tr)
	invalidate_clip_index()
	var err: String = validate()
	if not err.is_empty():
		tr.clips.erase(clip)
		_sort_track_clips(tr)
		return {"error": err, "clip_id": ""}
	return {"error": "", "clip_id": clip.id}


## Validates timeline state and returns "" if OK, or a human-readable error string.
## Mirrors the existing String-error pattern used across CodaState.set_event_*.
func validate() -> String:
	if length_seconds <= 0.0:
		return "Timeline length must be > 0 seconds."
	if loop_enabled:
		clamp_loop_region_to_length()
	for t in tracks:
		for c in t.clips:
			if c.start_seconds < 0.0:
				return 'Clip "%s" starts before 0.' % c.id
			if c.duration_seconds < 0.0:
				return 'Clip "%s" has negative duration.' % c.id
			if not c.audio_path.is_empty() and ResourceLoader.exists(c.audio_path):
				var max_src: float = c.max_source_playable_seconds()
				if max_src < 1.0e9 and c.duration_seconds > max_src + 0.0001:
					return 'Clip "%s" plays longer than the source audio allows.' % c.id
			if not c.audio_path.is_empty() and not ResourceLoader.exists(c.audio_path):
				return 'Clip "%s" audio path does not exist: %s' % [c.id, c.audio_path]
	for m in markers:
		if m.time_seconds < 0.0 or m.time_seconds > length_seconds:
			return 'Marker "%s" time is outside [0, length].' % m.marker_name
	if has_in_point() and (in_point_seconds < 0.0 or in_point_seconds > length_seconds):
		return "In point is outside [0, length]."
	if has_out_point() and (out_point_seconds < 0.0 or out_point_seconds > length_seconds):
		return "Out point is outside [0, length]."
	if has_in_point() and has_out_point() and out_point_seconds <= in_point_seconds:
		return "Out point must be after in point."
	return ""


func clone_keep_ids() -> CodaEventTimeline:
	var n := CodaEventTimeline.new()
	n.length_seconds = length_seconds
	n.tempo_bpm = tempo_bpm
	n.time_signature = time_signature
	n.loop_enabled = loop_enabled
	n.loop_start_seconds = loop_start_seconds
	n.loop_end_seconds = loop_end_seconds
	for t in tracks:
		n.tracks.append(t.clone_keep_id())
	for m in markers:
		n.markers.append(m.clone_keep_id())
	n.in_point_seconds = in_point_seconds
	n.out_point_seconds = out_point_seconds
	return n


## Copies authoring timeline content into an existing playback timeline (same object identity).
func overwrite_from_authoring(source: CodaEventTimeline) -> void:
	if source == null:
		return
	var snapshot := source.clone_keep_ids()
	length_seconds = snapshot.length_seconds
	tempo_bpm = snapshot.tempo_bpm
	time_signature = snapshot.time_signature
	loop_enabled = snapshot.loop_enabled
	loop_start_seconds = snapshot.loop_start_seconds
	loop_end_seconds = snapshot.loop_end_seconds
	in_point_seconds = snapshot.in_point_seconds
	out_point_seconds = snapshot.out_point_seconds
	tracks = snapshot.tracks
	markers = snapshot.markers
	invalidate_clip_index()


func to_dictionary() -> Dictionary:
	var data := {
		"length": length_seconds,
		"tempo_bpm": tempo_bpm,
		"time_sig_num": time_signature.x,
		"time_sig_den": time_signature.y,
		"loop_enabled": loop_enabled,
		"loop_start": loop_start_seconds,
		"loop_end": loop_end_seconds,
		"tracks": tracks.map(func(t: CodaTimelineTrack) -> Dictionary: return t.to_dictionary()),
		"markers": markers.map(
			func(m: CodaTimelineMarker) -> Dictionary: return m.to_dictionary()
		),
	}
	if has_in_point():
		data["in_point"] = in_point_seconds
	if has_out_point():
		data["out_point"] = out_point_seconds
	return data


static func from_dictionary(data: Dictionary) -> CodaEventTimeline:
	var t := CodaEventTimeline.new()
	t.length_seconds = max(0.001, float(data.get("length", DEFAULT_LENGTH_SECONDS)))
	t.tempo_bpm = max(0.0, float(data.get("tempo_bpm", 0.0)))
	var num: int = max(1, int(data.get("time_sig_num", 4)))
	var den: int = max(1, int(data.get("time_sig_den", 4)))
	t.time_signature = Vector2i(num, den)
	t.loop_enabled = bool(data.get("loop_enabled", false))
	t.loop_start_seconds = max(0.0, float(data.get("loop_start", 0.0)))
	t.loop_end_seconds = max(0.0, float(data.get("loop_end", 0.0)))
	for tr_raw in data.get("tracks", []) as Array:
		if tr_raw is Dictionary:
			t.tracks.append(CodaTimelineTrackScript.from_dictionary(tr_raw))
	for m_raw in data.get("markers", []) as Array:
		if m_raw is Dictionary:
			t.markers.append(CodaTimelineMarkerScript.from_dictionary(m_raw))
	if data.has("in_point"):
		t.in_point_seconds = float(data.get("in_point", UNSET_WORK_POINT))
	if data.has("out_point"):
		t.out_point_seconds = float(data.get("out_point", UNSET_WORK_POINT))
	return t
