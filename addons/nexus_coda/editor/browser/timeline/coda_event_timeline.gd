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
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_track.gd"
)
const CodaTimelineMarkerScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_marker.gd"
)

const DEFAULT_LENGTH_SECONDS := 8.0

var length_seconds: float = DEFAULT_LENGTH_SECONDS
var tempo_bpm: float = 0.0
var time_signature: Vector2i = Vector2i(4, 4)
var loop_enabled: bool = false
var loop_start_seconds: float = 0.0
var loop_end_seconds: float = 0.0
var tracks: Array[CodaTimelineTrack] = []
var markers: Array[CodaTimelineMarker] = []


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
	for t in tracks:
		for c in t.clips:
			if c.id == clip_id:
				return {"track": t, "clip": c}
	return {}


func find_marker(marker_id: String) -> CodaTimelineMarker:
	for m in markers:
		if m.id == marker_id:
			return m
	return null


func remove_track(track_id: String) -> bool:
	for i in range(tracks.size()):
		if tracks[i].id == track_id:
			tracks.remove_at(i)
			return true
	return false


func remove_marker(marker_id: String) -> bool:
	for i in range(markers.size()):
		if markers[i].id == marker_id:
			markers.remove_at(i)
			return true
	return false


## Validates timeline state and returns "" if OK, or a human-readable error string.
## Mirrors the existing String-error pattern used across CodaState.set_event_*.
func validate() -> String:
	if length_seconds <= 0.0:
		return "Timeline length must be > 0 seconds."
	if loop_enabled:
		if loop_start_seconds < 0.0 or loop_end_seconds > length_seconds:
			return "Loop region must lie within [0, length]."
		if loop_end_seconds <= loop_start_seconds:
			return "Loop end must be after loop start."
	for t in tracks:
		for c in t.clips:
			if c.start_seconds < 0.0:
				return 'Clip "%s" starts before 0.' % c.id
			if c.duration_seconds < 0.0:
				return 'Clip "%s" has negative duration.' % c.id
			if c.start_seconds + c.duration_seconds > length_seconds + 0.0001:
				return 'Clip "%s" extends past the timeline length.' % c.id
			if not c.audio_path.is_empty() and ResourceLoader.exists(c.audio_path):
				var max_src: float = c.max_source_playable_seconds()
				if max_src < 1.0e9 and c.duration_seconds > max_src + 0.0001:
					return 'Clip "%s" plays longer than the source audio allows.' % c.id
			if not c.audio_path.is_empty() and not ResourceLoader.exists(c.audio_path):
				return 'Clip "%s" audio path does not exist: %s' % [c.id, c.audio_path]
	for m in markers:
		if m.time_seconds < 0.0 or m.time_seconds > length_seconds:
			return 'Marker "%s" time is outside [0, length].' % m.marker_name
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
	return n


func to_dictionary() -> Dictionary:
	return {
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
	return t
