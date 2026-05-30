@tool
class_name CodaTimelineSegmentDriver
extends RefCounted

## Segment-track voice switching when a music-state parameter changes.

const CodaTimelineSchedulerScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_scheduler.gd"
)

const SEGMENTS_TRACK_NAME := "Segments"
const DEFAULT_PARAM_NAMES: PackedStringArray = ["music_state", "segment", "music_intensity"]


static func segments_track(timeline: CodaEventTimeline) -> CodaTimelineTrack:
	if timeline == null:
		return null
	for tr in timeline.tracks:
		if is_segments_track(tr):
			return tr
	return null


static func is_segments_track(track: CodaTimelineTrack) -> bool:
	return track != null and str(track.track_name).to_lower() == SEGMENTS_TRACK_NAME.to_lower()


static func resolve_segment_id(
	timeline: CodaEventTimeline, param_name: String, param_value: Variant
) -> String:
	var tr: CodaTimelineTrack = segments_track(timeline)
	if tr == null or tr.clips.is_empty():
		return ""
	var clips: Array = tr.clips.duplicate()
	clips.sort_custom(
		func(a, b) -> bool: return float(a.start_seconds) < float(b.start_seconds)
	)
	var lookup: String = str(param_value)
	for c in clips:
		if not c.segment_id.is_empty() and c.segment_id == lookup:
			return c.segment_id
	if typeof(param_value) == TYPE_INT or typeof(param_value) == TYPE_FLOAT:
		var idx: int = int(param_value)
		if idx >= 0 and idx < clips.size():
			var chosen: CodaTimelineClip = clips[idx] as CodaTimelineClip
			if not chosen.segment_id.is_empty():
				return chosen.segment_id
			return chosen.id
	return ""


static func find_clip_for_segment(timeline: CodaEventTimeline, segment_id: String) -> Dictionary:
	if segment_id.is_empty() or timeline == null:
		return {}
	var tr: CodaTimelineTrack = segments_track(timeline)
	if tr == null:
		return {}
	for c in tr.clips:
		if c.segment_id == segment_id or (c.segment_id.is_empty() and c.id == segment_id):
			return {"track": tr, "clip": c}
	return {}


static func should_drive_param(param_name: String, event: CodaBrowserNode = null) -> bool:
	var lookup: String = param_name.strip_edges().to_lower()
	if event != null:
		var custom: String = str(event.event_music_segment_param).strip_edges().to_lower()
		if not custom.is_empty():
			return lookup == custom
	for n in DEFAULT_PARAM_NAMES:
		if lookup == n:
			return true
	return false


static func _sync_segment_clip_dispatch_state(
	d: Dictionary, timeline: CodaEventTimeline, active_clip_id: String
) -> void:
	var seg_tr: CodaTimelineTrack = segments_track(timeline)
	if seg_tr == null or active_clip_id.is_empty():
		return
	var fired: Dictionary = d.get("fired_clip_ids", {})
	var spent: Dictionary = d.get("spent_clip_ids", {})
	for sc in seg_tr.clips:
		if sc.id == active_clip_id:
			fired[sc.id] = true
			spent.erase(sc.id)
		else:
			spent[sc.id] = true
			fired.erase(sc.id)
	d["fired_clip_ids"] = fired
	d["spent_clip_ids"] = spent


func apply_segment_change(
	runtime: CodaRuntime,
	handle: CodaEventHandle,
	d: Dictionary,
	segment_id: String,
	crossfade_ms: int = 500
) -> void:
	if runtime == null or handle == null or segment_id.is_empty():
		return
	var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
	if timeline == null:
		return
	var info: Dictionary = find_clip_for_segment(timeline, segment_id)
	if info.is_empty():
		return
	var current: String = str(d.get("active_segment_id", ""))
	if current == segment_id and _segment_voice_is_live(d, timeline, segment_id):
		return
	if current == segment_id:
		crossfade_ms = 0
	var tr: CodaTimelineTrack = info.get("track", null) as CodaTimelineTrack
	var clip: CodaTimelineClip = info.get("clip", null) as CodaTimelineClip
	if tr == null or clip == null:
		return
	if not _spawn_segment_voice(runtime, handle, d, timeline, tr, clip, crossfade_ms):
		return
	d["active_segment_id"] = segment_id
	_fade_out_other_segment_voices(runtime, handle, d, timeline, tr, clip.id, crossfade_ms)
	_sync_segment_clip_dispatch_state(d, timeline, clip.id)


static func _segment_voice_is_live(
	d: Dictionary, timeline: CodaEventTimeline, segment_id: String
) -> bool:
	var info: Dictionary = find_clip_for_segment(timeline, segment_id)
	if info.is_empty():
		return false
	var clip: CodaTimelineClip = info.get("clip", null) as CodaTimelineClip
	if clip == null:
		return false
	var voices: Dictionary = d.get("voices", {})
	var p: AudioStreamPlayer = voices.get(clip.id, null) as AudioStreamPlayer
	return p != null and is_instance_valid(p)


static func _fallback_segment_entry(tr: CodaTimelineTrack, clip: CodaTimelineClip) -> Dictionary:
	return {
		"audio_path": clip.audio_path,
		"volume_db": clip.volume_db + tr.volume_db,
		"pitch_scale": clip.pitch_scale,
		"loop": false,
		"sound_id": clip.id,
		"blend_weight": 1.0,
		"stream_offset_seconds": clip.offset_seconds,
		"duration_seconds": clip.duration_seconds,
		"track_id": tr.id,
		"clip_id": clip.id,
		"fade_in_seconds": clip.fade_in_seconds,
		"fade_out_seconds": clip.fade_out_seconds,
		"track_output_bus_id": tr.output_bus_id,
		"track_wet_sends": tr.wet_sends,
		"timeline_clip_end_seconds": clip.end_seconds(),
	}


func _spawn_segment_voice(
	runtime: CodaRuntime,
	handle: CodaEventHandle,
	d: Dictionary,
	timeline: CodaEventTimeline,
	tr: CodaTimelineTrack,
	clip: CodaTimelineClip,
	crossfade_ms: int,
) -> bool:
	var planned: Array = CodaTimelineSchedulerScript.plan(
		timeline, handle.param_values, handle.timeline_cursor_seconds, -1.0
	)
	for e in planned:
		if String(e.get("clip_id", "")) == clip.id:
			return runtime.spawn_timeline_segment_voice(handle, d, e, crossfade_ms)
	return runtime.spawn_timeline_segment_voice(
		handle, d, _fallback_segment_entry(tr, clip), crossfade_ms
	)


func _fade_out_other_segment_voices(
	runtime: CodaRuntime,
	handle: CodaEventHandle,
	d: Dictionary,
	timeline: CodaEventTimeline,
	seg_tr: CodaTimelineTrack,
	active_clip_id: String,
	crossfade_ms: int,
) -> void:
	var segment_ids: Dictionary = {}
	for sc in seg_tr.clips:
		segment_ids[sc.id] = true
	var voices: Dictionary = d.get("voices", {})
	for key in voices.keys():
		var clip_id: String = str(key)
		if clip_id == active_clip_id or not segment_ids.has(clip_id):
			continue
		var p: AudioStreamPlayer = voices[key] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			continue
		runtime.fade_out_timeline_voice(
			p,
			crossfade_ms,
			func() -> void:
				_on_segment_voice_faded_out(runtime, d, clip_id)
		)


func _on_segment_voice_faded_out(
	runtime: CodaRuntime, d: Dictionary, clip_id: String
) -> void:
	runtime.retire_timeline_voice(d, clip_id)
	var spent: Dictionary = d.get("spent_clip_ids", {})
	spent[clip_id] = true
	d["spent_clip_ids"] = spent
	var fired: Dictionary = d.get("fired_clip_ids", {})
	fired.erase(clip_id)
	d["fired_clip_ids"] = fired
