@tool
extends RefCounted
class_name CodaTimelineScheduler

## Plans timeline clips in a time window [t_from, t_to). Output entries match the graph
## scheduler shape plus start/stream offsets and fade times. Looping is handled by runtime.

const CodaRuntimeTimelineLayoutScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_timeline_layout.gd"
)


static func plan(
	timeline: CodaEventTimeline,
	_param_values: Dictionary = {},
	t_from: float = 0.0,
	t_to: float = -1.0,
) -> Array:
	var out: Array = []
	if timeline == null:
		return out
	if t_from < 0.0:
		t_from = 0.0
	var window_end: float = t_to
	if window_end <= 0.0 or window_end > timeline.length_seconds:
		window_end = timeline.length_seconds
	if window_end <= t_from:
		return out

	var has_solo: bool = CodaRuntimeTimelineLayoutScript.timeline_has_solo(timeline)
	for track in timeline.tracks:
		if not CodaRuntimeTimelineLayoutScript.track_is_audible(track, has_solo):
			continue
		for clip in track.clips:
			var entry: Dictionary = _entry_for_clip(track, clip, t_from, window_end, timeline)
			if not entry.is_empty():
				out.append(entry)

	out.sort_custom(_compare_entries_by_offset)
	return out


static func _entry_for_clip(
	track: CodaTimelineTrack,
	clip: CodaTimelineClip,
	t_from: float,
	t_to: float,
	timeline: CodaEventTimeline = null,
) -> Dictionary:
	if clip.audio_path.is_empty() or clip.duration_seconds <= 0.0:
		return {}
	var clip_start: float = clip.start_seconds
	var clip_end: float = clip.end_seconds()
	if timeline != null:
		clip_end = minf(clip_end, timeline.length_seconds)
	if clip_end <= t_from or clip_start >= t_to:
		return {}
	var window_start: float = maxf(clip_start, t_from)
	var window_end: float = minf(clip_end, t_to)
	var duration: float = window_end - window_start
	if duration <= 0.0:
		return {}
	var stream_offset: float = clip.offset_seconds + maxf(0.0, t_from - clip_start)
	var start_offset: float = maxf(0.0, clip_start - t_from)
	return {
		"audio_path": clip.audio_path,
		"volume_db": clip.volume_db + track.volume_db,
		"pitch_scale": clip.pitch_scale,
		"loop": false,
		"sound_id": clip.id,
		"blend_weight": 1.0,
		"start_offset_seconds": start_offset,
		"stream_offset_seconds": stream_offset,
		"duration_seconds": duration,
		"track_id": track.id,
		"clip_id": clip.id,
		"fade_in_seconds": clip.fade_in_seconds,
		"fade_out_seconds": clip.fade_out_seconds,
		"clip_effects": clip.effects,
		"track_effects": track.effects,
		"track_output_bus_id": track.output_bus_id,
		"track_wet_sends": track.wet_sends,
		"timeline_clip_end_seconds": clip_end,
	}


static func _compare_entries_by_offset(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("start_offset_seconds", 0.0)) < float(b.get("start_offset_seconds", 0.0))
