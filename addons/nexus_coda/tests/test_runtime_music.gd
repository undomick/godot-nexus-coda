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
	failed += _test_timeline_start_uses_music_state_not_cursor_prime()
	failed += _test_graph_stop_fade_blocks_plan_advance()
	failed += _test_graph_stop_fade_defers_voice_finished()
	failed += _test_timeline_seek_ignored_while_paused()
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


static func _test_timeline_start_uses_music_state_not_cursor_prime() -> int:
	var runtime: SegmentSpawnTestRuntime = _make_runtime()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var seg_tr = ev.event_timeline.tracks.filter(
		func(tr): return tr.track_name.to_lower() == "segments"
	)
	if seg_tr.is_empty() or seg_tr[0].clips.size() < 2:
		push_error("music_state start test needs Segments track with two clips")
		runtime.stop_all()
		runtime.free()
		return 1
	var calm = seg_tr[0].clips[0]
	var tense = seg_tr[0].clips[1]
	var handle: CodaEventHandle = runtime.play("music/exploration", {"music_state": 1})
	if handle == null:
		push_error("timeline play should return a handle")
		runtime.stop_all()
		runtime.free()
		return 1
	var d: Dictionary = runtime.get_timeline_dispatchers().get(handle, {}) as Dictionary
	if str(d.get("active_segment_id", "")) != "tense":
		push_error(
			"timeline start at cursor 0 with music_state=1 should select tense, got %s"
			% str(d.get("active_segment_id", ""))
		)
		runtime.stop_all()
		runtime.free()
		return 1
	var fired: Dictionary = d.get("fired_clip_ids", {}) as Dictionary
	if fired.has(calm.id) and not fired.has(tense.id):
		push_error("Segments track must not be primed by cursor overlap")
		runtime.stop_all()
		runtime.free()
		return 1
	if not d.get("voices", {}).has(tense.id):
		push_error("tense segment voice should spawn from music_state")
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


static func _test_graph_stop_fade_blocks_plan_advance() -> int:
	var runtime: CodaRuntime = _make_runtime()
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle._alive = true
	handle.current_sound_id = "step_a"
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(player)
	handle._bind_player(player)
	handle.params["_coda_plan"] = [
		{
			"audio_path": "res://addons/nexus_coda/samples/silence.wav",
			"volume_db": 0.0,
			"pitch_scale": 1.0,
			"sound_id": "step_b",
			"blend_weight": 1.0,
		}
	]
	runtime._active_handles[player.get_instance_id()] = handle
	runtime.stop(handle, 500)
	if not handle._paused:
		push_error("graph stop with fade should pause the handle")
		runtime.stop_all()
		runtime.free()
		return 1
	if (handle.params.get("_coda_plan", []) as Array).size() != 0:
		push_error("graph stop should clear the remaining plan")
		runtime.stop_all()
		runtime.free()
		return 1
	var before_sound: String = handle.current_sound_id
	runtime._graph_playback.on_voice_finished_for_graph(player, player.get_instance_id(), false)
	if handle.current_sound_id != before_sound:
		push_error("graph stop fade should block plan advance on voice_finished")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
	return 0


static func _test_graph_stop_fade_defers_voice_finished() -> int:
	var runtime: CodaRuntime = _make_runtime()
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle._alive = true
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	runtime.add_child(player)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100.0
	player.stream = stream
	player.play()
	handle._bind_player(player)
	runtime._active_handles[player.get_instance_id()] = handle
	var finished_count: Array[int] = [0]
	runtime.voice_finished.connect(func(_h: CodaEventHandle) -> void: finished_count[0] += 1)
	runtime.stop(handle, 500)
	if int(finished_count[0]) != 0:
		push_error("graph stop fade should defer voice_finished until teardown completes")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
	return 0


static func _test_timeline_seek_ignored_while_paused() -> int:
	var runtime: CodaRuntime = _make_runtime()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle._alive = true
	handle._paused = true
	handle.event_node = ev
	handle.timeline_cursor_seconds = 0.0
	handle.timeline_length_seconds = ev.event_timeline.length_seconds
	handle.timeline_pending_seek_seconds = 12.0
	var d: Dictionary = {
		"timeline": ev.event_timeline,
		"voices": {},
		"fired_clip_ids": {},
		"fired_marker_ids": {},
		"spent_clip_ids": {},
	}
	runtime._timeline_dispatchers[handle] = d
	runtime._timeline_dispatcher.tick_dispatchers(0.0)
	if handle.timeline_pending_seek_seconds >= 0.0:
		push_error("paused timeline should consume pending seek without applying it")
		runtime.stop_all()
		runtime.free()
		return 1
	if not (d.get("voices", {}) as Dictionary).is_empty():
		push_error("paused timeline seek must not reprime voices")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
	return 0
