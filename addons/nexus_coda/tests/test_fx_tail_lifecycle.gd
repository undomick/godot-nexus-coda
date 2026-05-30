extends RefCounted
class_name TestFxTailLifecycle

const CodaVoiceTeardownPolicyScript := preload(
	"res://addons/nexus_coda/runtime/coda_voice_teardown_policy.gd"
)
const CodaTimelineClipDispatchScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_clip_dispatch.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_event_timeline.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_track.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_teardown_policy_modes()
	failed += _test_audible_clip_end_respects_timeline_length()
	failed += _test_clip_spatial_index_active_at()
	failed += _test_clip_spatial_index_range()
	return failed


static func _test_teardown_policy_modes() -> int:
	if CodaVoiceTeardownPolicyScript.mode_for_layout_resync() != CodaVoiceTeardownPolicyScript.Mode.DRY_WITH_TAIL:
		push_error("layout resync should use dry-with-tail policy")
		return 1
	if CodaVoiceTeardownPolicyScript.mode_for_preview_pause() != CodaVoiceTeardownPolicyScript.Mode.DRY_WITH_TAIL:
		push_error("preview pause should use dry-with-tail policy")
		return 1
	if CodaVoiceTeardownPolicyScript.mode_for_stop_all() != CodaVoiceTeardownPolicyScript.Mode.DRY_WITH_TAIL:
		push_error("stop_all should use dry-with-tail policy")
		return 1
	if CodaVoiceTeardownPolicyScript.mode_for_seek() != CodaVoiceTeardownPolicyScript.Mode.IMMEDIATE:
		push_error("seek should use immediate teardown policy")
		return 1
	return 0


static func _test_audible_clip_end_respects_timeline_length() -> int:
	var clip := CodaTimelineClipScript.new()
	clip.start_seconds = 1.0
	clip.duration_seconds = 10.0
	var timeline := CodaEventTimelineScript.new()
	timeline.length_seconds = 5.0
	var end: float = CodaTimelineClipDispatchScript.audible_clip_end(clip, timeline)
	if abs(end - 5.0) > 0.001:
		push_error("audible clip end should clamp to timeline length")
		return 1
	return 0


static func _test_clip_spatial_index_active_at() -> int:
	var timeline := CodaEventTimelineScript.new()
	timeline.length_seconds = 8.0
	var track := CodaTimelineTrackScript.new()
	var clip_a := CodaTimelineClipScript.new()
	clip_a.start_seconds = 0.0
	clip_a.duration_seconds = 2.0
	var clip_b := CodaTimelineClipScript.new()
	clip_b.start_seconds = 3.0
	clip_b.duration_seconds = 2.0
	track.clips = [clip_a, clip_b]
	timeline.tracks = [track]
	var active: Array = timeline.clips_active_at(1.0)
	if active.size() != 1:
		push_error("clips_active_at should return one overlapping clip")
		return 1
	return 0


static func _test_clip_spatial_index_range() -> int:
	var timeline := CodaEventTimelineScript.new()
	timeline.length_seconds = 10.0
	var track := CodaTimelineTrackScript.new()
	var clip_a := CodaTimelineClipScript.new()
	clip_a.start_seconds = 0.0
	clip_a.duration_seconds = 1.0
	var clip_b := CodaTimelineClipScript.new()
	clip_b.start_seconds = 5.0
	clip_b.duration_seconds = 1.0
	track.clips = [clip_a, clip_b]
	timeline.tracks = [track]
	var hits: Array = timeline.clips_overlapping_range(0.5, 6.0)
	if hits.size() != 2:
		push_error("clips_overlapping_range should return both clips in window")
		return 1
	return 0
