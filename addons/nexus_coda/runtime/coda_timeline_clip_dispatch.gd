@tool
class_name CodaTimelineClipDispatch
extends RefCounted

const CodaVoiceFaderScript := preload("res://addons/nexus_coda/runtime/coda_voice_fader.gd")
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
	}


func prime_overlapping_voices(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline, at_seconds: float
) -> void:
	var has_solo: bool = CodaRuntimeTimelineLayoutScript.timeline_has_solo(timeline)
	var fired: Dictionary = d.get("fired_clip_ids", {}).duplicate()
	for track in timeline.tracks:
		if not CodaRuntimeTimelineLayoutScript.track_is_audible(track, has_solo):
			continue
		if CodaTimelineSegmentDriverScript.is_segments_track(track):
			continue
		for clip in track.clips:
			if clip.audio_path.is_empty() or clip.duration_seconds <= 0.0:
				continue
			if not clip_starts_before_timeline_end(clip, timeline):
				continue
			if fired.has(clip.id):
				continue
			var clip_end: float = audible_clip_end(clip, timeline)
			if at_seconds < clip.start_seconds or at_seconds >= clip_end:
				continue
			var into_clip: float = at_seconds - clip.start_seconds
			var entry: Dictionary = clip_lane_entry(track, clip, into_clip, clip_end)
			if _lane_voice.spawn_lane_voice(handle, d, entry):
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
	for track in timeline.tracks:
		if not CodaRuntimeTimelineLayoutScript.track_is_audible(track, has_solo):
			continue
		if CodaTimelineSegmentDriverScript.is_segments_track(track):
			continue
		for clip in track.clips:
			if clip.audio_path.is_empty() or clip.duration_seconds <= 0.0:
				continue
			if not clip_starts_before_timeline_end(clip, timeline):
				continue
			if fired.has(clip.id):
				continue
			var spent: Dictionary = d.get("spent_clip_ids", {})
			if spent.has(clip.id):
				continue
			var clip_end: float = audible_clip_end(clip, timeline)
			if clip_end <= from_seconds or clip.start_seconds >= to_seconds:
				continue
			var crosses_start: bool = (
				clip.start_seconds >= from_seconds and clip.start_seconds < to_seconds
			)
			var overlaps_unfired: bool = clip.start_seconds < from_seconds and clip_end > from_seconds
			if not crosses_start and not overlaps_unfired:
				continue
			var into_clip: float = maxf(0.0, from_seconds - clip.start_seconds)
			var entry: Dictionary = clip_lane_entry(track, clip, into_clip, clip_end)
			if _lane_voice.spawn_lane_voice(handle, d, entry):
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


func refresh_voice_output_levels(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline
) -> void:
	var voices: Dictionary = d.get("voices", {})
	if voices.is_empty():
		return
	var has_solo: bool = CodaRuntimeTimelineLayoutScript.timeline_has_solo(timeline)
	var override_db: float = float(handle.params.get("volume_db", 0.0))
	for sound_key in voices.keys():
		var p: AudioStreamPlayer = voices[sound_key] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			continue
		var clip_id: String = str(sound_key)
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
