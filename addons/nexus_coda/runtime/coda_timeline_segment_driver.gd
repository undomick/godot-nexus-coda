@tool
class_name CodaTimelineSegmentDriver
extends RefCounted

## Switches segment clips on a dedicated "Segments" track when a music-state parameter changes.
## Crossfades between the outgoing and incoming segment voices.

const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_clip.gd"
)
const CodaVoiceFaderScript := preload("res://addons/nexus_coda/runtime/coda_voice_fader.gd")
const CodaTimelineSchedulerScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_scheduler.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_event_timeline.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_track.gd"
)

const SEGMENTS_TRACK_NAME := "Segments"
const DEFAULT_PARAM_NAMES: PackedStringArray = ["music_state", "segment", "music_intensity"]


static func segments_track(timeline):
	if timeline == null:
		return null
	for tr in timeline.tracks:
		if is_segments_track(tr):
			return tr
	return null


static func is_segments_track(track) -> bool:
	return track != null and str(track.track_name).to_lower() == SEGMENTS_TRACK_NAME.to_lower()


static func resolve_segment_id(timeline, param_name: String, param_value: Variant) -> String:
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
			var chosen = clips[idx]
			if not chosen.segment_id.is_empty():
				return chosen.segment_id
			return chosen.id
	return ""


static func find_clip_for_segment(timeline, segment_id: String) -> Dictionary:
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


static func _sync_segment_clip_dispatch_state(d: Dictionary, timeline, active_clip_id: String) -> void:
	var seg_tr = segments_track(timeline)
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
	var timeline = d.get("timeline", null)
	if timeline == null:
		return
	var info: Dictionary = find_clip_for_segment(timeline, segment_id)
	if info.is_empty():
		return
	var current: String = str(d.get("active_segment_id", ""))
	if current == segment_id:
		return
	d["active_segment_id"] = segment_id
	var tr = info.get("track", null)
	var clip = info.get("clip", null)
	if tr == null or clip == null:
		return
	var planned: Array = CodaTimelineSchedulerScript.plan(
		timeline, handle.param_values, handle.timeline_cursor_seconds, -1.0
	)
	var spawned: bool = false
	for e in planned:
		if String(e.get("clip_id", "")) == clip.id:
			runtime.spawn_timeline_segment_voice(handle, d, e, crossfade_ms)
			spawned = true
			break
	if not spawned:
		var manual: Dictionary = {
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
			"timeline_clip_end_seconds": clip.end_seconds(),
		}
		runtime.spawn_timeline_segment_voice(handle, d, manual, crossfade_ms)
	var voices: Dictionary = d.get("voices", {})
	for key in voices.keys():
		if str(key) == clip.id:
			continue
		var p: AudioStreamPlayer = voices[key] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			continue
		var seg_tr = segments_track(timeline)
		if seg_tr == null:
			continue
		var is_segment_voice: bool = false
		for sc in seg_tr.clips:
			if sc.id == str(key):
				is_segment_voice = true
				break
		if is_segment_voice:
			var old_clip_id: String = str(key)
			runtime.fade_out_timeline_voice(
				p,
				crossfade_ms,
				func() -> void:
					runtime.retire_timeline_voice(d, old_clip_id)
					var spent: Dictionary = d.get("spent_clip_ids", {})
					spent[old_clip_id] = true
					d["spent_clip_ids"] = spent
					var fired: Dictionary = d.get("fired_clip_ids", {})
					fired.erase(old_clip_id)
					d["fired_clip_ids"] = fired
			)
	_sync_segment_clip_dispatch_state(d, timeline, clip.id)
