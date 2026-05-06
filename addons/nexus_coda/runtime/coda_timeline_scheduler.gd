@tool
extends RefCounted
class_name CodaTimelineScheduler

## Resolves a [code]CodaEventTimeline[/code] into a flat list of plan entries the runtime
## can dispatch over time. The format mirrors [code]coda_graph_scheduler.gd[/code]:
##   { "audio_path", "volume_db", "pitch_scale", "loop", "sound_id", "blend_weight" }
## plus the timeline-specific extras:
##   { "start_offset_seconds": time after [code]t_from[/code] when the voice should fire,
##     "stream_offset_seconds": where to seek into the source audio,
##     "duration_seconds": how long the voice should keep playing (clipped to t_to if set),
##     "track_id": String, "clip_id": String,
##     "fade_in_seconds": float, "fade_out_seconds": float }
##
## The scheduler is purely time-based and ignores [code]tempo_bpm[/code]; the bars/beats grid
## is an editor-only concept in the MVP.

## Returns ordered plan entries for the time window [code][t_from, t_to)[/code].
##
## - [code]t_to <= 0[/code] disables the upper bound (used when starting a voice without a
##   pre-known end). Loop handling is done by the runtime, not the scheduler.
## - [code]param_values[/code] is reserved for future per-clip conditions (e.g. switch tracks
##   on parameter values); MVP simply ignores it but the signature mirrors the graph scheduler.
static func plan(
	timeline: CodaEventTimeline,
	param_values: Dictionary = {},
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

	var has_solo: bool = false
	for t in timeline.tracks:
		if t.solo:
			has_solo = true
			break

	for track in timeline.tracks:
		if track.mute:
			continue
		if has_solo and not track.solo:
			continue
		for clip in track.clips:
			var entry: Dictionary = _entry_for_clip(track, clip, t_from, window_end)
			if entry.is_empty():
				continue
			out.append(entry)

	out.sort_custom(_compare_entries_by_offset)
	return out


static func _entry_for_clip(
	track: CodaTimelineTrack,
	clip: CodaTimelineClip,
	t_from: float,
	t_to: float,
) -> Dictionary:
	if clip.audio_path.is_empty() or clip.duration_seconds <= 0.0:
		return {}
	var clip_start: float = clip.start_seconds
	var clip_end: float = clip.end_seconds()
	if clip_end <= t_from or clip_start >= t_to:
		return {}
	var window_start: float = maxf(clip_start, t_from)
	var window_end: float = minf(clip_end, t_to)
	var duration: float = window_end - window_start
	if duration <= 0.0:
		return {}
	var stream_offset: float = clip.offset_seconds + maxf(0.0, t_from - clip_start)
	var start_offset: float = maxf(0.0, clip_start - t_from)
	var combined_volume_db: float = clip.volume_db + track.volume_db
	return {
		"audio_path": clip.audio_path,
		"volume_db": combined_volume_db,
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
	}


static func _compare_entries_by_offset(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("start_offset_seconds", 0.0)) < float(b.get("start_offset_seconds", 0.0))
