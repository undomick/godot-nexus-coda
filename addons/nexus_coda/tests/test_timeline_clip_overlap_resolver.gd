extends RefCounted
class_name TestTimelineClipOverlapResolver

const ResolverScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip_overlap_resolver.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_event_timeline.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_track.gd"
)

const MIN_CLIP := 0.05


static func run() -> int:
	var failed: int = 0
	failed += _test_trim_end()
	failed += _test_trim_start()
	failed += _test_full_delete()
	failed += _test_middle_split()
	failed += _test_two_victims()
	failed += _test_sliver_removed()
	failed += _test_segments_track_skipped()
	failed += _test_near_start_hole_fallback()
	failed += _test_near_end_hole_fallback()
	failed += _test_middle_split_failure_keeps_left()
	return failed


static func _make_timeline_with_clips(
	aggressor_start: float,
	aggressor_dur: float,
	victim_start: float,
	victim_dur: float
) -> Dictionary:
	var timeline = CodaEventTimelineScript.make_default()
	var track = timeline.tracks[0]
	var aggressor = CodaTimelineClipScript.new()
	aggressor.start_seconds = aggressor_start
	aggressor.duration_seconds = aggressor_dur
	var victim = CodaTimelineClipScript.new()
	victim.start_seconds = victim_start
	victim.duration_seconds = victim_dur
	track.clips.append(victim)
	track.clips.append(aggressor)
	timeline.invalidate_clip_index()
	return {"timeline": timeline, "aggressor": aggressor, "victim": victim, "track": track}


static func _test_trim_end() -> int:
	var d: Dictionary = _make_timeline_with_clips(2.0, 3.0, 0.0, 4.0)
	ResolverScript.resolve_for_aggressor(d.timeline, d.aggressor.id, MIN_CLIP)
	var victim: CodaTimelineClip = d.victim
	if absf(victim.duration_seconds - 2.0) > 0.001 or absf(victim.start_seconds) > 0.001:
		push_error("trim end: victim should be [0, 2)")
		return 1
	return 0


static func _test_trim_start() -> int:
	var d: Dictionary = _make_timeline_with_clips(0.0, 3.0, 2.0, 4.0)
	ResolverScript.resolve_for_aggressor(d.timeline, d.aggressor.id, MIN_CLIP)
	var victim: CodaTimelineClip = d.victim
	if absf(victim.start_seconds - 3.0) > 0.001 or absf(victim.duration_seconds - 3.0) > 0.001:
		push_error("trim start: victim should be [3, 6)")
		return 1
	if absf(victim.offset_seconds - 1.0) > 0.001:
		push_error("trim start: offset should advance by overlap at start")
		return 1
	return 0


static func _test_full_delete() -> int:
	var d: Dictionary = _make_timeline_with_clips(0.0, 10.0, 2.0, 2.0)
	ResolverScript.resolve_for_aggressor(d.timeline, d.aggressor.id, MIN_CLIP)
	var track: CodaTimelineTrack = d.track
	if track.clips.size() != 1:
		push_error("full delete: only aggressor should remain")
		return 1
	if track.clips[0].id != d.aggressor.id:
		push_error("full delete: remaining clip should be aggressor")
		return 1
	return 0


static func _test_middle_split() -> int:
	var d: Dictionary = _make_timeline_with_clips(3.0, 2.0, 0.0, 10.0)
	ResolverScript.resolve_for_aggressor(d.timeline, d.aggressor.id, MIN_CLIP)
	var track: CodaTimelineTrack = d.track
	if track.clips.size() != 3:
		push_error("middle split: expected left, aggressor, right")
		return 1
	var left: CodaTimelineClip = track.clips[0]
	var right: CodaTimelineClip = track.clips[2]
	if absf(left.duration_seconds - 3.0) > 0.001:
		push_error("middle split: left duration")
		return 1
	if absf(right.start_seconds - 5.0) > 0.001 or absf(right.duration_seconds - 5.0) > 0.001:
		push_error("middle split: right segment")
		return 1
	return 0


static func _test_two_victims() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var track = timeline.tracks[0]
	var a = CodaTimelineClipScript.new()
	a.start_seconds = 1.0
	a.duration_seconds = 8.0
	var v1 = CodaTimelineClipScript.new()
	v1.start_seconds = 0.0
	v1.duration_seconds = 3.0
	var v2 = CodaTimelineClipScript.new()
	v2.start_seconds = 6.0
	v2.duration_seconds = 4.0
	track.clips.append(v1)
	track.clips.append(v2)
	track.clips.append(a)
	timeline.invalidate_clip_index()
	ResolverScript.resolve_for_aggressor(timeline, a.id, MIN_CLIP)
	if track.clips.size() != 3:
		push_error("two victims: expected three clips on track")
		return 1
	if absf(v1.duration_seconds - 1.0) > 0.001:
		push_error("two victims: first victim trimmed at end")
		return 1
	if absf(v2.start_seconds - 9.0) > 0.001 or absf(v2.duration_seconds - 1.0) > 0.001:
		push_error("two victims: second victim trimmed at start")
		return 1
	return 0


static func _test_sliver_removed() -> int:
	var d: Dictionary = _make_timeline_with_clips(0.02, 2.0, 0.0, 0.04)
	ResolverScript.resolve_for_aggressor(d.timeline, d.aggressor.id, MIN_CLIP)
	var track: CodaTimelineTrack = d.track
	if track.clips.size() != 1:
		push_error("sliver: victim shorter than min should be removed")
		return 1
	return 0


static func _test_near_start_hole_fallback() -> int:
	var d: Dictionary = _make_timeline_with_clips(0.005, 5.0, 0.0, 10.0)
	ResolverScript.resolve_for_aggressor(d.timeline, d.aggressor.id, MIN_CLIP)
	var victim: CodaTimelineClip = d.victim
	var expected_start: float = d.aggressor.end_seconds()
	if absf(victim.start_seconds - expected_start) > 0.001:
		push_error("near start hole: victim should be trimmed to [%s, 10)" % expected_start)
		return 1
	if absf(victim.duration_seconds - (10.0 - expected_start)) > 0.001:
		push_error("near start hole: victim duration should match trimmed tail")
		return 1
	if ResolverScript.intervals_overlap(
		d.aggressor.start_seconds,
		d.aggressor.end_seconds(),
		victim.start_seconds,
		victim.end_seconds()
	):
		push_error("near start hole: overlap should be resolved")
		return 1
	return 0


static func _test_near_end_hole_fallback() -> int:
	var d: Dictionary = _make_timeline_with_clips(9.985, 0.01, 0.0, 10.0)
	ResolverScript.resolve_for_aggressor(d.timeline, d.aggressor.id, MIN_CLIP)
	var victim: CodaTimelineClip = d.victim
	if absf(victim.duration_seconds - 9.985) > 0.001:
		push_error("near end hole: victim should be trimmed to [0, 9.985)")
		return 1
	if ResolverScript.intervals_overlap(
		d.aggressor.start_seconds,
		d.aggressor.end_seconds(),
		victim.start_seconds,
		victim.end_seconds()
	):
		push_error("near end hole: overlap should be resolved")
		return 1
	return 0


class _TimelineSplitAlwaysFails extends CodaEventTimeline:
	static func make_test() -> _TimelineSplitAlwaysFails:
		var t := _TimelineSplitAlwaysFails.new()
		t.tracks.append(CodaTimelineTrackScript.new())
		return t

	func split_clip_at_time(clip_id: String, split_seconds: float) -> String:
		return "forced split failure for test"


static func _test_middle_split_failure_keeps_left() -> int:
	var timeline: CodaEventTimeline = _TimelineSplitAlwaysFails.make_test()
	timeline.tracks[0].clips.clear()
	var track = timeline.tracks[0]
	var aggressor = CodaTimelineClipScript.new()
	aggressor.start_seconds = 3.0
	aggressor.duration_seconds = 2.0
	var victim = CodaTimelineClipScript.new()
	victim.start_seconds = 0.0
	victim.duration_seconds = 10.0
	track.clips.append(victim)
	track.clips.append(aggressor)
	timeline.invalidate_clip_index()
	ResolverScript.resolve_for_aggressor(timeline, aggressor.id, MIN_CLIP)
	if track.clips.size() != 2:
		push_error("split failure fallback: expected left segment and aggressor")
		return 1
	if absf(victim.duration_seconds - 3.0) > 0.001:
		push_error("split failure fallback: left segment should be [0, 3)")
		return 1
	if ResolverScript.intervals_overlap(
		aggressor.start_seconds,
		aggressor.end_seconds(),
		victim.start_seconds,
		victim.end_seconds()
	):
		push_error("split failure fallback: overlap should be resolved")
		return 1
	return 0


static func _test_segments_track_skipped() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var track = timeline.tracks[0]
	track.track_name = "Segments"
	var aggressor = CodaTimelineClipScript.new()
	aggressor.start_seconds = 0.0
	aggressor.duration_seconds = 5.0
	var victim = CodaTimelineClipScript.new()
	victim.start_seconds = 1.0
	victim.duration_seconds = 2.0
	track.clips.append(victim)
	track.clips.append(aggressor)
	timeline.invalidate_clip_index()
	ResolverScript.resolve_for_aggressor(timeline, aggressor.id, MIN_CLIP)
	if track.clips.size() != 2:
		push_error("segments track: overlap should not be punched")
		return 1
	return 0
