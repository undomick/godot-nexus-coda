extends RefCounted
class_name TestTransitionPolicy

const CodaMusicTransitionPolicyScript := preload(
	"res://addons/nexus_coda/runtime/coda_music_transition_policy.gd"
)
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_defaults()
	failed += _test_timeline_cursor()
	return failed


static func _test_defaults() -> int:
	var policy := CodaMusicTransitionPolicyScript.default_policy()
	if policy.event_crossfade_ms != 2000:
		push_error("default event crossfade should be 2000")
		return 1
	if policy.segment_crossfade_ms != 500:
		push_error("default segment crossfade should be 500")
		return 1
	if policy.max_stingers != 4:
		push_error("max_stingers stub should be 4")
		return 1
	return 0


static func _test_timeline_cursor() -> int:
	var policy := CodaMusicTransitionPolicyScript.default_policy()
	policy.clock_source = CodaMusicTransitionPolicyScript.ClockSource.TIMELINE_CURSOR
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle.timeline_cursor_seconds = 3.5
	if abs(policy.get_music_cursor_seconds(handle) - 3.5) > 0.001:
		push_error("timeline cursor should come from handle")
		return 1
	return 0
