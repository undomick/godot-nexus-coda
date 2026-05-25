extends RefCounted
class_name TestMusicDirector

const CodaMusicDirectorScript := preload("res://addons/nexus_coda/runtime/coda_music_director.gd")
const CodaMusicTransitionPolicyScript := preload(
	"res://addons/nexus_coda/runtime/coda_music_transition_policy.gd"
)
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaTestMockRuntimeScript := preload(
	"res://addons/nexus_coda/tests/helpers/coda_test_mocks.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_same_path_only_params()
	failed += _test_new_path_stops_old()
	failed += _test_failed_play_keeps_old_music()
	failed += _test_quantized_queue_supersedes_same_slot()
	failed += _test_quantized_slot_parameter_targets_pending_play()
	failed += _test_immediate_stop_cancels_pending_quantized()
	failed += _test_immediate_set_music_cancels_pending_quantized()
	failed += _test_fade_stop_then_set_music_stops_outgoing()
	failed += _test_fade_stop_slot_exposes_outgoing_handle()
	failed += _test_fade_stop_same_path_updates_outgoing_only()
	return failed


static func _test_same_path_only_params() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h: CodaEventHandle = director.set_music("music/a", 500, "default", {"music_state": 0})
	if h == null:
		push_error("set_music should return handle")
		mock.queue_free()
		return 1
	if mock.play_calls.size() != 1:
		push_error("expected one play call")
		mock.queue_free()
		return 1
	director.set_music("music/a", 500, "default", {"music_state": 1})
	if mock.play_calls.size() != 1:
		push_error("same path should not play again")
		mock.queue_free()
		return 1
	if mock.set_parameter_calls.size() != 1:
		push_error("same path should update params")
		mock.queue_free()
		return 1
	if mock.stop_calls.size() != 0:
		push_error("same path should not stop")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_new_path_stops_old() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h1: CodaEventHandle = director.set_music("music/a", 800)
	if h1 == null:
		push_error("set_music should return handle")
		mock.queue_free()
		return 1
	director.set_music("music/b", 1200)
	if mock.stop_calls.size() != 1:
		push_error("new path should stop old handle")
		mock.queue_free()
		return 1
	if int(mock.stop_calls[0].get("fade_ms", 0)) != 1200:
		push_error("stop should use fade_ms from set_music")
		mock.queue_free()
		return 1
	if mock.play_calls.size() != 2:
		push_error("new path should play again")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_failed_play_keeps_old_music() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	mock.play_fail_paths["music/b"] = true
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h1: CodaEventHandle = director.set_music("music/a", 800)
	if h1 == null or not mock.is_alive(h1):
		push_error("set_music should start first track")
		mock.queue_free()
		return 1
	var h2: CodaEventHandle = director.set_music("music/b", 1200)
	if h2 != null:
		push_error("failed play should return null")
		mock.queue_free()
		return 1
	if mock.stop_calls.size() != 0:
		push_error("failed play must not stop outgoing music")
		mock.queue_free()
		return 1
	if not mock.is_alive(h1):
		push_error("outgoing handle should stay alive after failed play")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_quantized_queue_supersedes_same_slot() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var policy: CodaMusicTransitionPolicy = CodaMusicTransitionPolicyScript.default_policy()
	policy.quantize_to_bar = true
	mock._policy = policy
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var timeline := CodaEventTimeline.new()
	timeline.tempo_bpm = 120.0
	timeline.time_signature = Vector2i(4, 4)
	var event := CodaBrowserNode.new()
	event.kind = CodaBrowserNode.Kind.EVENT
	event.event_timeline = timeline
	var first: CodaEventHandle = CodaEventHandleScript.new()
	first._alive = true
	first.event_node = event
	first.is_timeline = true
	first.timeline_cursor_seconds = 1.5
	director._slots["default"] = {"handle": first, "event_path": "music/a"}
	director.set_music("music/a", 500, "default", {}, true)
	director.set_music("music/b", 500, "default", {}, true)
	if director._pending_quantized.size() != 1:
		push_error("quantized queue should keep only the latest request per slot")
		mock.queue_free()
		return 1
	if str(director._pending_quantized[0].get("event_path", "")) != "music/b":
		push_error("latest quantized set_music should win")
		mock.queue_free()
		return 1
	director._pending_quantized[0]["fire_at"] = 0
	director._process(0.0)
	if mock.play_calls.size() != 1:
		push_error("superseded quantized request must not play")
		mock.queue_free()
		return 1
	if mock.play_calls[0].get("path", "") != "music/b":
		push_error("processed quantized request should play the latest path")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_quantized_slot_parameter_targets_pending_play() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var policy: CodaMusicTransitionPolicy = CodaMusicTransitionPolicyScript.default_policy()
	policy.quantize_to_bar = true
	mock._policy = policy
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var timeline := CodaEventTimeline.new()
	timeline.tempo_bpm = 120.0
	timeline.time_signature = Vector2i(4, 4)
	var event := CodaBrowserNode.new()
	event.kind = CodaBrowserNode.Kind.EVENT
	event.event_timeline = timeline
	var first: CodaEventHandle = CodaEventHandleScript.new()
	first._alive = true
	first.event_node = event
	first.is_timeline = true
	first.timeline_cursor_seconds = 1.5
	director._slots["default"] = {"handle": first, "event_path": "music/a"}
	director.set_music("music/b", 500, "default", {}, true)
	if director.set_slot_parameter("default", "music_state", 2):
		push_error("set_slot_parameter should report no live apply while quantized")
		mock.queue_free()
		return 1
	if mock.set_parameter_calls.size() != 0:
		push_error("quantized slot parameters must not mutate the outgoing live handle")
		mock.queue_free()
		return 1
	if director._pending_quantized.is_empty():
		push_error("expected pending quantized set_music")
		mock.queue_free()
		return 1
	var pending_params: Dictionary = director._pending_quantized[0].get("params", {}) as Dictionary
	if int(pending_params.get("music_state", -1)) != 2:
		push_error("quantized slot parameters should merge into the pending set_music request")
		mock.queue_free()
		return 1
	director._pending_quantized[0]["fire_at"] = 0
	director._process(0.0)
	if mock.play_calls.size() != 1:
		push_error("pending set_music should play once the bar boundary fires")
		mock.queue_free()
		return 1
	var played_params: Dictionary = mock.play_calls[0].get("params", {}) as Dictionary
	if int(played_params.get("music_state", -1)) != 2:
		push_error("played music should receive queued slot parameters")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _timeline_slot_setup(director: CodaMusicDirector) -> void:
	var timeline := CodaEventTimeline.new()
	timeline.tempo_bpm = 120.0
	timeline.time_signature = Vector2i(4, 4)
	var event := CodaBrowserNode.new()
	event.kind = CodaBrowserNode.Kind.EVENT
	event.event_timeline = timeline
	var first: CodaEventHandle = CodaEventHandleScript.new()
	first._alive = true
	first.event_node = event
	first.is_timeline = true
	first.timeline_cursor_seconds = 1.5
	director._slots["default"] = {"handle": first, "event_path": "music/a"}


static func _test_immediate_stop_cancels_pending_quantized() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var policy: CodaMusicTransitionPolicy = CodaMusicTransitionPolicyScript.default_policy()
	policy.quantize_to_bar = false
	mock._policy = policy
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	_timeline_slot_setup(director)
	director.set_music("music/b", 500, "default", {}, true)
	if director._pending_quantized.is_empty():
		push_error("expected pending quantized set_music before immediate stop")
		mock.queue_free()
		return 1
	director.stop_music("default", 500, false)
	if not director._pending_quantized.is_empty():
		push_error("immediate stop_music should cancel pending quantized requests")
		mock.queue_free()
		return 1
	if mock.stop_calls.size() != 1:
		push_error("immediate stop_music should stop the live slot handle")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_immediate_set_music_cancels_pending_quantized() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var policy: CodaMusicTransitionPolicy = CodaMusicTransitionPolicyScript.default_policy()
	policy.quantize_to_bar = false
	mock._policy = policy
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	_timeline_slot_setup(director)
	director.set_music("music/b", 500, "default", {}, true)
	director.set_music("music/c", 500, "default", {}, false)
	if not director._pending_quantized.is_empty():
		push_error("immediate set_music should cancel pending quantized requests")
		mock.queue_free()
		return 1
	if mock.play_calls.size() != 1 or mock.play_calls[0].get("path", "") != "music/c":
		push_error("immediate set_music should play the new path")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_fade_stop_then_set_music_stops_outgoing() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h1: CodaEventHandle = director.set_music("music/a", 800)
	if h1 == null:
		push_error("set_music should return handle")
		mock.queue_free()
		return 1
	director.stop_music("default", 2000)
	if not mock.is_alive(h1):
		push_error("fade stop should keep outgoing handle alive until teardown")
		mock.queue_free()
		return 1
	director.set_music("music/b", 800)
	if mock.stop_calls.size() != 2:
		push_error("set_music after fade stop should stop the outgoing handle")
		mock.queue_free()
		return 1
	if mock.play_calls.size() != 2:
		push_error("set_music after fade stop should start the new path")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_fade_stop_slot_exposes_outgoing_handle() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h1: CodaEventHandle = director.set_music("music/a", 800)
	if h1 == null:
		push_error("set_music should return handle")
		mock.queue_free()
		return 1
	director.stop_music("default", 2000)
	var exposed: CodaEventHandle = director.get_slot_handle("default")
	if exposed != h1:
		push_error("fade stop should expose the outgoing slot handle")
		mock.queue_free()
		return 1
	var slot: Dictionary = director._slots.get("default", {}) as Dictionary
	if str(slot.get("event_path", "")) != "music/a":
		push_error("fade stop should retain event_path for same-track updates")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_fade_stop_same_path_updates_outgoing_only() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h1: CodaEventHandle = director.set_music("music/a", 800)
	if h1 == null:
		push_error("set_music should return handle")
		mock.queue_free()
		return 1
	director.stop_music("default", 2000)
	var h2: CodaEventHandle = director.set_music("music/a", 800, "default", {"music_state": 2})
	if h2 != h1:
		push_error("same path during fade stop should update the outgoing handle")
		mock.queue_free()
		return 1
	if mock.play_calls.size() != 1:
		push_error("same path during fade stop must not start a second voice")
		mock.queue_free()
		return 1
	if mock.set_parameter_calls.size() != 1:
		push_error("same path during fade stop should apply parameter updates")
		mock.queue_free()
		return 1
	if int(mock.set_parameter_calls[0].get("value", -1)) != 2:
		push_error("parameter update should reach the outgoing handle")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0
