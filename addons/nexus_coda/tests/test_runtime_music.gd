extends RefCounted
class_name TestRuntimeMusic

const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaTestRuntimeScript := preload("res://addons/nexus_coda/tests/helpers/coda_test_runtime.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaTimelineSegmentDriverScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_segment_driver.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_set_parameter_segment_notify()
	failed += _test_notify_music_state_changed()
	failed += _test_timeline_start_segment_from_param_not_playhead()
	failed += _test_stop_all_finalizes_plan_resume_handles()
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


static func _test_timeline_start_segment_from_param_not_playhead() -> int:
	var runtime: CodaRuntime = _make_runtime()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var seg_tr = CodaTimelineSegmentDriverScript.segments_track(ev.event_timeline)
	if seg_tr == null or seg_tr.clips.size() < 2:
		push_error("segment playhead test needs Segments clips")
		runtime.queue_free()
		return 1
	# Playhead sits in the second segment region; music_state default is calm (index 0).
	var handle: CodaEventHandle = runtime.play(
		"music/exploration", {"timeline_cursor_start": 15.0}
	)
	if handle == null:
		push_error("timeline play failed for segment playhead test")
		runtime.queue_free()
		return 1
	var d: Dictionary = runtime._timeline_dispatchers[handle]
	if str(d.get("active_segment_id", "")) != "calm":
		push_error(
			"timeline start should apply music_state param (calm), not the segment clip under the playhead (tense)"
		)
		runtime.queue_free()
		return 1
	var tense_id: String = seg_tr.clips[1].id
	var fired: Dictionary = d.get("fired_clip_ids", {})
	if fired.has(tense_id):
		push_error("Segments-track clip at playhead must not be primed as a normal lane voice")
		runtime.queue_free()
		return 1
	runtime.queue_free()
	return 0


static func _test_stop_all_finalizes_plan_resume_handles() -> int:
	var runtime: CodaRuntime = _make_runtime()
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle._alive = true
	runtime.get_graph_plan_resume_handles().append(handle)
	var finished_count: Array = [0]
	handle.finished.connect(func() -> void: finished_count[0] = int(finished_count[0]) + 1)
	runtime.stop_all()
	if runtime.is_alive(handle):
		push_error("stop_all should clear plan-resume handles (is_alive still true)")
		runtime.queue_free()
		return 1
	if int(finished_count[0]) != 1:
		push_error("stop_all should emit finished for plan-resume handles")
		runtime.queue_free()
		return 1
	if not runtime.get_graph_plan_resume_handles().is_empty():
		push_error("stop_all should clear plan-resume handle list")
		runtime.queue_free()
		return 1
	runtime.queue_free()
	return 0
