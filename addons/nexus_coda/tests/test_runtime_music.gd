extends RefCounted
class_name TestRuntimeMusic

const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaTestRuntimeScript := preload("res://addons/nexus_coda/tests/helpers/coda_test_runtime.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_set_parameter_segment_notify()
	failed += _test_notify_music_state_changed()
	return failed


static func _make_runtime() -> CodaRuntime:
	var runtime: CodaRuntime = CodaRuntimeScript.new()
	runtime._ready()
	return runtime


static func _test_set_parameter_segment_notify() -> int:
	var runtime: CodaRuntime = _make_runtime()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle.event_node = ev
	handle.param_values = {}
	var d: Dictionary = {"timeline": ev.event_timeline, "active_segment_id": ""}
	runtime._timeline_dispatchers[handle] = d
	runtime.set_parameter(handle, "intensity", 0.9)
	if str(d.get("active_segment_id", "")) != "":
		push_error("intensity set_parameter should not trigger segment change")
		runtime.queue_free()
		return 1
	runtime.set_parameter(handle, "music_state", 1)
	if str(d.get("active_segment_id", "")) != "tense":
		push_error("music_state set_parameter should trigger segment change")
		runtime.queue_free()
		return 1
	runtime.queue_free()
	return 0


static func _test_notify_music_state_changed() -> int:
	var runtime: CodaRuntime = _make_runtime()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle.event_node = ev
	handle.param_values = {"music_state": 1}
	var d: Dictionary = {"timeline": ev.event_timeline, "active_segment_id": ""}
	runtime._timeline_dispatchers[handle] = d
	runtime.notify_music_state_changed(handle)
	if str(d.get("active_segment_id", "")) != "tense":
		push_error("notify_music_state_changed should apply segment for music_state=1")
		runtime.queue_free()
		return 1
	runtime.queue_free()
	return 0
