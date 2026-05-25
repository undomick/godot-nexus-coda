extends RefCounted
class_name TestRuntimeMusic

const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaTestRuntimeScript := preload("res://addons/nexus_coda/tests/helpers/coda_test_runtime.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")


class SegmentSpawnTestRuntime extends CodaRuntime:
	var segment_spawn_ok: bool = true

	func spawn_timeline_segment_voice(
		handle: CodaEventHandle, d: Dictionary, entry: Dictionary, crossfade_ms: int = -1
	) -> bool:
		if not segment_spawn_ok:
			return false
		var clip_id: String = String(entry.get("sound_id", ""))
		if clip_id.is_empty():
			return false
		var voices: Dictionary = d.get("voices", {})
		voices[clip_id] = AudioStreamPlayer.new()
		d["voices"] = voices
		return true


static func run() -> int:
	var failed: int = 0
	failed += _test_set_parameter_segment_notify()
	failed += _test_notify_music_state_changed()
	failed += _test_stop_all_finalizes_plan_resume_handles()
	failed += _test_segment_change_keeps_active_on_spawn_failure()
	return failed


static func _make_runtime() -> SegmentSpawnTestRuntime:
	var runtime: SegmentSpawnTestRuntime = SegmentSpawnTestRuntime.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(runtime)
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
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.set_parameter(handle, "music_state", 1)
	if str(d.get("active_segment_id", "")) != "tense":
		push_error("music_state set_parameter should trigger segment change")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
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
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
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
		runtime.free()
		return 1
	if int(finished_count[0]) != 1:
		push_error("stop_all should emit finished for plan-resume handles")
		runtime.free()
		return 1
	if not runtime.get_graph_plan_resume_handles().is_empty():
		push_error("stop_all should clear plan-resume handle list")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
	return 0


static func _test_segment_change_keeps_active_on_spawn_failure() -> int:
	var runtime: SegmentSpawnTestRuntime = _make_runtime()
	runtime.segment_spawn_ok = false
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var seg_tr = ev.event_timeline.tracks.filter(
		func(tr): return tr.track_name.to_lower() == "segments"
	)
	if seg_tr.is_empty() or seg_tr[0].clips.size() < 2:
		push_error("segment spawn-failure test needs Segments track")
		runtime.stop_all()
		runtime.free()
		return 1
	var calm = seg_tr[0].clips[0]
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle.event_node = ev
	handle.param_values = {"music_state": 1}
	var d: Dictionary = {
		"timeline": ev.event_timeline,
		"fired_clip_ids": {calm.id: true},
		"spent_clip_ids": {},
		"voices": {calm.id: AudioStreamPlayer.new()},
		"active_segment_id": calm.segment_id,
	}
	runtime._timeline_dispatchers[handle] = d
	runtime.set_parameter(handle, "music_state", 1)
	if str(d.get("active_segment_id", "")) != calm.segment_id:
		push_error("failed segment spawn must keep active_segment_id")
		runtime.stop_all()
		runtime.free()
		return 1
	if d.get("voices", {}).has(seg_tr[0].clips[1].id):
		push_error("failed segment spawn must not add a new segment voice")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
	return 0
