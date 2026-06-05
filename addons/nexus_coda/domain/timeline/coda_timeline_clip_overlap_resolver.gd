class_name CodaTimelineClipOverlapResolver
extends RefCounted

## Removes timeline overlap by trimming, splitting, or deleting clips under an aggressor clip.

const SEGMENTS_TRACK_NAME := "Segments"
const OVERLAP_EPSILON := 0.001
## Must match [CodaEventTimeline.MIN_SPLIT_SEGMENT_SECONDS].
const MIN_SPLIT_SEGMENT_SECONDS := 0.02


static func resolve_for_aggressor(
	timeline: CodaEventTimeline, aggressor_clip_id: String, min_clip_duration: float
) -> void:
	if timeline == null or aggressor_clip_id.is_empty():
		return
	var info: Dictionary = timeline.find_clip(aggressor_clip_id)
	if info.is_empty():
		return
	var aggressor: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	var track: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
	if aggressor == null or track == null:
		return
	if is_segments_track(track):
		return

	var victim_ids: Array[String] = []
	for clip in track.clips:
		if clip.id == aggressor_clip_id:
			continue
		if intervals_overlap(
			aggressor.start_seconds,
			aggressor.end_seconds(),
			clip.start_seconds,
			clip.end_seconds()
		):
			victim_ids.append(clip.id)

	if victim_ids.is_empty():
		return

	victim_ids.sort_custom(
		func(a: String, b: String) -> bool:
			var ia: Dictionary = timeline.find_clip(a)
			var ib: Dictionary = timeline.find_clip(b)
			var ca: CodaTimelineClip = ia.get("clip") as CodaTimelineClip
			var cb: CodaTimelineClip = ib.get("clip") as CodaTimelineClip
			if ca == null or cb == null:
				return a > b
			return ca.start_seconds > cb.start_seconds
	)

	for victim_id in victim_ids:
		_punch_victim(timeline, track, aggressor, victim_id, min_clip_duration)

	_sort_track_clips(track)
	timeline.invalidate_clip_index()


static func is_segments_track(track: CodaTimelineTrack) -> bool:
	return track != null and str(track.track_name).to_lower() == SEGMENTS_TRACK_NAME.to_lower()


static func intervals_overlap(a0: float, a1: float, b0: float, b1: float) -> bool:
	var o0: float = maxf(a0, b0)
	var o1: float = minf(a1, b1)
	return o1 > o0 + OVERLAP_EPSILON


static func _punch_victim(
	timeline: CodaEventTimeline,
	track: CodaTimelineTrack,
	aggressor: CodaTimelineClip,
	victim_id: String,
	min_clip_duration: float
) -> void:
	var info: Dictionary = timeline.find_clip(victim_id)
	if info.is_empty():
		return
	var victim: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if victim == null:
		return

	var as_sec: float = aggressor.start_seconds
	var ae_sec: float = aggressor.end_seconds()
	var vs: float = victim.start_seconds
	var ve: float = victim.end_seconds()
	var os: float = maxf(as_sec, vs)
	var oe: float = minf(ae_sec, ve)
	if oe <= os + OVERLAP_EPSILON:
		return

	if os <= vs + OVERLAP_EPSILON and oe >= ve - OVERLAP_EPSILON:
		_remove_clip_from_track(track, victim)
		return

	if os <= vs + OVERLAP_EPSILON and oe < ve - OVERLAP_EPSILON:
		_trim_victim_start(victim, oe, vs)
		if victim.duration_seconds < min_clip_duration:
			_remove_clip_from_track(track, victim)
		return

	if os > vs + OVERLAP_EPSILON and oe >= ve - OVERLAP_EPSILON:
		victim.duration_seconds = os - vs
		_finalize_trimmed_clip(victim, min_clip_duration, track)
		return

	if os > vs + OVERLAP_EPSILON and oe < ve - OVERLAP_EPSILON:
		_punch_hole_middle(timeline, track, victim, os, oe, min_clip_duration)


static func _trim_victim_start(victim: CodaTimelineClip, new_start: float, old_start: float) -> void:
	var end_t: float = victim.end_seconds()
	var delta: float = new_start - old_start
	victim.start_seconds = new_start
	victim.duration_seconds = maxf(0.0, end_t - new_start)
	victim.offset_seconds += delta
	_clamp_duration_to_source(victim)
	_clamp_fades(victim)


static func _finalize_trimmed_clip(
	clip: CodaTimelineClip, min_clip_duration: float, track: CodaTimelineTrack
) -> void:
	_clamp_duration_to_source(clip)
	_clamp_fades(clip)
	if clip.duration_seconds < min_clip_duration:
		_remove_clip_from_track(track, clip)


static func _punch_hole_middle(
	timeline: CodaEventTimeline,
	track: CodaTimelineTrack,
	victim: CodaTimelineClip,
	hole_start: float,
	hole_end: float,
	min_clip_duration: float
) -> void:
	var ve: float = victim.end_seconds()
	var vs: float = victim.start_seconds
	# Domain split rejects cuts within MIN_SPLIT of either edge; fall back to trim.
	if hole_start - vs < MIN_SPLIT_SEGMENT_SECONDS - OVERLAP_EPSILON:
		_trim_victim_start(victim, hole_end, vs)
		if victim.duration_seconds < min_clip_duration:
			_remove_clip_from_track(track, victim)
		return
	if ve - hole_end < MIN_SPLIT_SEGMENT_SECONDS - OVERLAP_EPSILON:
		victim.duration_seconds = hole_start - vs
		_finalize_trimmed_clip(victim, min_clip_duration, track)
		return
	var left_id: String = victim.id
	var err: String = timeline.split_clip_at_time(left_id, hole_start)
	if not err.is_empty():
		# Split rolled back; keep the non-overlapping prefix [vs, hole_start).
		victim.duration_seconds = hole_start - vs
		_finalize_trimmed_clip(victim, min_clip_duration, track)
		return

	var right_clip: CodaTimelineClip = _find_split_right_clip(track, hole_start, left_id, ve)
	if right_clip == null:
		# Split succeeded but the tail clip is missing; keep the non-overlapping prefix.
		victim.duration_seconds = hole_start - vs
		_finalize_trimmed_clip(victim, min_clip_duration, track)
		return

	var trim_amount: float = hole_end - hole_start
	right_clip.start_seconds = hole_end
	right_clip.duration_seconds = maxf(0.0, ve - hole_end)
	right_clip.offset_seconds += trim_amount
	_clamp_duration_to_source(right_clip)
	_clamp_fades(right_clip)

	var left_info: Dictionary = timeline.find_clip(left_id)
	var left: CodaTimelineClip = left_info.get("clip") as CodaTimelineClip
	if left != null:
		_clamp_fades(left)
		if left.duration_seconds < min_clip_duration:
			_remove_clip_from_track(track, left)
	if right_clip.duration_seconds < min_clip_duration:
		_remove_clip_from_track(track, right_clip)


static func _find_clip_starting_near(
	track: CodaTimelineTrack, start_seconds: float, exclude_id: String
) -> CodaTimelineClip:
	for clip in track.clips:
		if clip.id == exclude_id:
			continue
		if absf(clip.start_seconds - start_seconds) <= OVERLAP_EPSILON:
			return clip
	return null


## After a successful split, multiple clips may share [hole_start] when earlier victims
## were also punched on this lane. Prefer the tail whose end matches the pre-split victim.
static func _find_split_right_clip(
	track: CodaTimelineTrack,
	hole_start: float,
	left_id: String,
	original_victim_end: float,
) -> CodaTimelineClip:
	var candidates: Array[CodaTimelineClip] = []
	for clip in track.clips:
		if clip.id == left_id:
			continue
		if absf(clip.start_seconds - hole_start) <= OVERLAP_EPSILON:
			candidates.append(clip)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]
	for clip in candidates:
		if absf(clip.end_seconds() - original_victim_end) <= OVERLAP_EPSILON:
			return clip
	return candidates[0]


static func _remove_clip_from_track(track: CodaTimelineTrack, clip: CodaTimelineClip) -> void:
	var idx: int = track.clips.find(clip)
	if idx >= 0:
		track.clips.remove_at(idx)


static func _clamp_duration_to_source(clip: CodaTimelineClip) -> void:
	var max_d: float = clip.max_source_playable_seconds()
	clip.duration_seconds = clampf(clip.duration_seconds, 0.0, max_d)


static func _clamp_fades(clip: CodaTimelineClip) -> void:
	var dur: float = maxf(0.0, clip.duration_seconds)
	clip.fade_in_seconds = clampf(
		clip.fade_in_seconds, 0.0, maxf(0.0, dur - clip.fade_out_seconds)
	)
	clip.fade_out_seconds = clampf(
		clip.fade_out_seconds, 0.0, maxf(0.0, dur - clip.fade_in_seconds)
	)
	if clip.fade_in_seconds + clip.fade_out_seconds > dur:
		var scale: float = dur / maxf(0.0001, clip.fade_in_seconds + clip.fade_out_seconds)
		clip.fade_in_seconds *= scale
		clip.fade_out_seconds *= scale


static func _sort_track_clips(track: CodaTimelineTrack) -> void:
	track.clips.sort_custom(
		func(a: CodaTimelineClip, b: CodaTimelineClip) -> bool:
			return a.start_seconds < b.start_seconds
	)
