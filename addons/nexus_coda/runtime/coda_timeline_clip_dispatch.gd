@tool
class_name CodaTimelineClipDispatch
extends RefCounted

const CodaVoiceFaderScript := preload("res://addons/nexus_coda/runtime/coda_voice_fader.gd")
const CodaVoiceWetLayersScript := preload("res://addons/nexus_coda/runtime/coda_voice_wet_layers.gd")
const CodaTimelineSegmentDriverScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_segment_driver.gd"
)
const CodaRuntimeTimelineLayoutScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_timeline_layout.gd"
)


var _runtime: CodaRuntime = null
var _lane_voice: CodaTimelineLaneVoice = null


func setup(runtime: CodaRuntime, lane_voice: CodaTimelineLaneVoice) -> void:
	_runtime = runtime
	_lane_voice = lane_voice


static func reset_bookkeeping(d: Dictionary) -> void:
	d["fired_clip_ids"] = {}
	d["fired_marker_ids"] = {}
	d["spent_clip_ids"] = {}


static func audible_clip_end(clip: CodaTimelineClip, timeline: CodaEventTimeline) -> float:
	if clip == null:
		return 0.0
	var end: float = clip.start_seconds + clip.duration_seconds
	if timeline == null:
		return end
	return minf(end, timeline.length_seconds)


static func clip_starts_before_timeline_end(clip: CodaTimelineClip, timeline: CodaEventTimeline) -> bool:
	if clip == null or timeline == null:
		return false
	return clip.start_seconds < timeline.length_seconds - 0.0001


static func clip_lane_entry(
	track: CodaTimelineTrack, clip: CodaTimelineClip, into_clip: float, clip_end: float
) -> Dictionary:
	return {
		"audio_path": clip.audio_path,
		"volume_db": clip.volume_db + track.volume_db,
		"pitch_scale": clip.pitch_scale,
		"sound_id": clip.id,
		"track_id": track.id,
		"stream_offset_seconds": clip.offset_seconds + into_clip,
		"duration_seconds": clip.duration_seconds - into_clip,
		"timeline_clip_end_seconds": clip_end,
		"clip_effects": clip.effects,
		"track_effects": track.effects,
		"track_output_bus_id": track.output_bus_id,
		"track_wet_sends": track.wet_sends,
	}


func prime_overlapping_voices(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline, at_seconds: float
) -> void:
	var has_solo: bool = CodaRuntimeTimelineLayoutScript.timeline_has_solo(timeline)
	var fired: Dictionary = d.get("fired_clip_ids", {}).duplicate()
	for entry in timeline.clips_active_at(at_seconds):
		var track: CodaTimelineTrack = entry.get("track", null) as CodaTimelineTrack
		var clip: CodaTimelineClip = entry.get("clip", null) as CodaTimelineClip
		if track == null or clip == null:
			continue
		if not CodaRuntimeTimelineLayoutScript.track_is_audible(track, has_solo):
			continue
		if CodaTimelineSegmentDriverScript.is_segments_track(track):
			continue
		if clip.audio_path.is_empty() or clip.duration_seconds <= 0.0:
			continue
		if not clip_starts_before_timeline_end(clip, timeline):
			continue
		if fired.has(clip.id):
			continue
		var clip_end: float = audible_clip_end(clip, timeline)
		var into_clip: float = at_seconds - clip.start_seconds
		var lane_entry: Dictionary = clip_lane_entry(track, clip, into_clip, clip_end)
		if _lane_voice.spawn_lane_voice(handle, d, lane_entry):
			fired[clip.id] = true
			refresh_voice_output_levels(handle, d, timeline)
	d["fired_clip_ids"] = fired


func fire_clips_in_range(
	handle: CodaEventHandle,
	d: Dictionary,
	timeline: CodaEventTimeline,
	from_seconds: float,
	to_seconds: float,
) -> void:
	if to_seconds <= from_seconds:
		return
	var has_solo: bool = CodaRuntimeTimelineLayoutScript.timeline_has_solo(timeline)
	var fired: Dictionary = d.get("fired_clip_ids", {})
	var spent: Dictionary = d.get("spent_clip_ids", {})
	for entry in timeline.clips_overlapping_range(from_seconds, to_seconds):
		var track: CodaTimelineTrack = entry.get("track", null) as CodaTimelineTrack
		var clip: CodaTimelineClip = entry.get("clip", null) as CodaTimelineClip
		if track == null or clip == null:
			continue
		if not CodaRuntimeTimelineLayoutScript.track_is_audible(track, has_solo):
			continue
		if CodaTimelineSegmentDriverScript.is_segments_track(track):
			continue
		if clip.audio_path.is_empty() or clip.duration_seconds <= 0.0:
			continue
		if not clip_starts_before_timeline_end(clip, timeline):
			continue
		if fired.has(clip.id):
			continue
		if spent.has(clip.id):
			continue
		var clip_end: float = audible_clip_end(clip, timeline)
		var crosses_start: bool = (
			clip.start_seconds >= from_seconds and clip.start_seconds < to_seconds
		)
		var overlaps_unfired: bool = clip.start_seconds < from_seconds and clip_end > from_seconds
		if not crosses_start and not overlaps_unfired:
			continue
		var into_clip: float = maxf(0.0, from_seconds - clip.start_seconds)
		var lane_entry: Dictionary = clip_lane_entry(track, clip, into_clip, clip_end)
		if _lane_voice.spawn_lane_voice(handle, d, lane_entry):
			fired[clip.id] = true
			refresh_voice_output_levels(handle, d, timeline)
	d["fired_clip_ids"] = fired


func heal_orphaned_fired_clips(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline, at_seconds: float
) -> void:
	var fired: Dictionary = d.get("fired_clip_ids", {})
	if fired.is_empty():
		return
	var voices: Dictionary = d.get("voices", {})
	var has_solo: bool = CodaRuntimeTimelineLayoutScript.timeline_has_solo(timeline)
	var healed: bool = false
	for track in timeline.tracks:
		if not CodaRuntimeTimelineLayoutScript.track_is_audible(track, has_solo):
			continue
		if CodaTimelineSegmentDriverScript.is_segments_track(track):
			continue
		for clip in track.clips:
			if not fired.has(clip.id):
				continue
			var spent: Dictionary = d.get("spent_clip_ids", {})
			if spent.has(clip.id):
				continue
			if voices.has(clip.id):
				continue
			if not clip_starts_before_timeline_end(clip, timeline):
				continue
			var clip_end: float = audible_clip_end(clip, timeline)
			if at_seconds < clip.start_seconds or at_seconds >= clip_end:
				continue
			fired.erase(clip.id)
			healed = true
	if healed:
		d["fired_clip_ids"] = fired


static func clip_id_from_wet_voice_key(voice_key: String) -> String:
	var key_str: String = str(voice_key)
	var wet_pos: int = key_str.rfind("_wet_")
	if wet_pos < 0:
		return ""
	return key_str.substr(0, wet_pos)


static func wet_index_from_wet_voice_key(voice_key: String) -> int:
	var key_str: String = str(voice_key)
	var wet_pos: int = key_str.rfind("_wet_")
	if wet_pos < 0:
		return -1
	var idx_str: String = key_str.substr(wet_pos + 5)
	if not idx_str.is_valid_int():
		return -1
	return int(idx_str)


func refresh_voice_output_levels(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline
) -> void:
	var voices: Dictionary = d.get("voices", {})
	if voices.is_empty():
		return
	var has_solo: bool = CodaRuntimeTimelineLayoutScript.timeline_has_solo(timeline)
	var override_db: float = float(handle.params.get("volume_db", 0.0))
	var wet_levels: Dictionary = {}
	for sound_key in voices.keys():
		var key_str: String = str(sound_key)
		if key_str.contains("_wet_"):
			continue
		var p: AudioStreamPlayer = voices[sound_key] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			continue
		var clip_id: String = key_str
		var info: Dictionary = timeline.find_clip(clip_id)
		if info.is_empty():
			continue
		var tr: CodaTimelineTrack = info.get("track", null) as CodaTimelineTrack
		var cl: CodaTimelineClip = info.get("clip", null) as CodaTimelineClip
		if tr == null or cl == null:
			continue
		if tr.mute or (has_solo and not tr.solo):
			p.volume_db = -80.0
		else:
			var base_db: float = float(cl.volume_db + tr.volume_db) + override_db
			var audible_end: float = audible_clip_end(cl, timeline)
			var include_fade_out: bool = true
			if p.has_meta(&"_coda_fx_tail_seconds"):
				include_fade_out = float(p.get_meta(&"_coda_fx_tail_seconds", 0.0)) <= 0.0
			base_db += CodaVoiceFaderScript.clip_fade_db_offset(
				cl, handle.timeline_cursor_seconds, audible_end, include_fade_out
			)
			var levels: Dictionary = _runtime.get_parameter_pipeline().modulation_voice_levels(
				handle, clip_id, base_db, float(cl.pitch_scale)
			)
			p.volume_db = float(levels.get("volume_db", base_db))
			p.pitch_scale = float(levels.get("pitch_scale", float(cl.pitch_scale)))
		var event_sends: Array[CodaBusSend] = []
		if handle.event_node is CodaBrowserNode:
			event_sends = (handle.event_node as CodaBrowserNode).event_wet_sends
		var merged_sends: Array[CodaBusSend] = CodaVoiceWetLayersScript.merge_sends(
			event_sends, tr.wet_sends
		)
		wet_levels[clip_id] = {
			"volume_db": p.volume_db,
			"pitch_scale": p.pitch_scale,
			"merged_sends": merged_sends,
		}
	var bus_root: CodaBus = _runtime.get_playback_bus_root()
	var param_values: Dictionary = handle.param_values_smoothed
	for sound_key in voices.keys():
		var key_str: String = str(sound_key)
		if not key_str.contains("_wet_"):
			continue
		var clip_id: String = clip_id_from_wet_voice_key(key_str)
		if clip_id.is_empty() or not wet_levels.has(clip_id):
			continue
		var p: AudioStreamPlayer = voices[sound_key] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			continue
		var levels: Dictionary = wet_levels[clip_id]
		var dry_db: float = float(levels.get("volume_db", 0.0))
		var merged: Array = levels.get("merged_sends", [])
		var wet_idx: int = wet_index_from_wet_voice_key(key_str)
		p.volume_db = CodaVoiceWetLayersScript.wet_volume_db_for_layer(
			dry_db, wet_idx, merged, bus_root, param_values
		)
		p.pitch_scale = float(levels.get("pitch_scale", 1.0))
