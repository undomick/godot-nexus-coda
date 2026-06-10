extends RefCounted
class_name TestRuntimeMusic

const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaTestRuntimeScript := preload("res://addons/nexus_coda/tests/helpers/coda_test_runtime.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaPlayOptionsScript := preload("res://addons/nexus_coda/domain/coda_play_options.gd")
const CodaTimelineDispatcherScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_dispatcher.gd"
)
const CodaTimelineLaneVoiceScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_lane_voice.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_track.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)


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


class CountingLaneVoice extends CodaTimelineLaneVoiceScript:
	var spawned_clip_ids: Array[String] = []

	func spawn_lane_voice(handle: CodaEventHandle, d: Dictionary, entry: Dictionary) -> bool:
		var clip_id: String = String(entry.get("sound_id", ""))
		if clip_id.is_empty():
			return false
		spawned_clip_ids.append(clip_id)
		var voices: Dictionary = d.get("voices", {})
		voices[clip_id] = AudioStreamPlayer.new()
		d["voices"] = voices
		return true


static func run() -> int:
	var failed: int = 0
	failed += _test_route_event_params_preserves_rtpc()
	failed += _test_set_parameter_segment_notify()
	failed += _test_global_parameter_music_state_segment()
	failed += _test_notify_music_state_changed()
	failed += _test_stop_all_finalizes_plan_resume_handles()
	failed += _test_segment_change_keeps_active_on_spawn_failure()
	failed += _test_timeline_start_uses_music_state_not_cursor_prime()
	failed += _test_graph_stop_fade_blocks_plan_advance()
	failed += _test_graph_stop_fade_defers_voice_finished()
	failed += _test_timeline_seek_while_paused_updates_cursor_only()
	failed += _test_timeline_fade_keeps_dispatcher_until_playing_voices_finish()
	failed += _test_graph_pause_reserves_pooled_player()
	failed += _test_graph_stop_after_pause_releases_pool_slot()
	failed += _test_loop_backward_wrap_does_not_fire_future_clips()
	return failed


static func _test_route_event_params_preserves_rtpc() -> int:
	var routed: Dictionary = CodaPlayOptionsScript.route_event_params({
		"loop": true,
		"timeline_cursor_start": 2.0,
		"music_state": 1,
		"intensity": 0.8,
		"_coda_exclusive_preview": true,
		"_coda_voice_bus": "Music",
	})
	if not bool(routed.get("loop", false)):
		push_error("route_event_params should keep loop play option")
		return 1
	if absf(float(routed.get("timeline_cursor_start", -1.0)) - 2.0) > 0.001:
		push_error("route_event_params should keep timeline_cursor_start")
		return 1
	if int(routed.get("music_state", -1)) != 1:
		push_error("route_event_params should preserve music_state RTPC")
		return 1
	if absf(float(routed.get("intensity", -1.0)) - 0.8) > 0.001:
		push_error("route_event_params should preserve intensity RTPC")
		return 1
	if not bool(routed.get("_coda_exclusive_preview", false)):
		push_error("route_event_params should keep routed _coda_ play options")
		return 1
	if String(routed.get("_coda_voice_bus", "")) != "Music":
		push_error("route_event_params should keep voice bus play option")
		return 1
	return 0


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


static func _test_global_parameter_music_state_segment() -> int:
	var runtime: SegmentSpawnTestRuntime = _make_runtime()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle._alive = true
	handle.event_node = ev
	handle.param_values = {}
	var d: Dictionary = {"timeline": ev.event_timeline, "active_segment_id": ""}
	runtime._timeline_dispatchers[handle] = d
	runtime.set_global_parameter("music_state", 1)
	runtime._parameter_pipeline.apply_global_parameters()
	if str(d.get("active_segment_id", "")) != "tense":
		push_error("music_state set_global_parameter should trigger segment change")
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


static func _test_timeline_fade_keeps_dispatcher_until_playing_voices_finish() -> int:
	var runtime: CodaRuntime = _make_runtime()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle._alive = true
	handle.event_node = ev
	var playing: AudioStreamPlayer = AudioStreamPlayer.new()
	runtime.add_child(playing)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100.0
	playing.stream = stream
	playing.play()
	if not playing.playing:
		# Headless generator playback may not enter the playing state; skip fade teardown check.
		runtime.stop_all()
		runtime.free()
		return 0
	var stopped: AudioStreamPlayer = AudioStreamPlayer.new()
	runtime.add_child(stopped)
	var d: Dictionary = {
		"timeline": ev.event_timeline,
		"voices": {"stem_a": stopped, "stem_b": playing},
	}
	runtime._timeline_dispatchers[handle] = d
	runtime._timeline_dispatcher.finalize_handle(handle, 500)
	if not runtime._timeline_dispatchers.has(handle):
		push_error("timeline fade must not tear down while a playing voice is still fading")
		runtime.stop_all()
		runtime.free()
		return 1
	if not is_instance_valid(playing):
		push_error("timeline fade must not hard-stop the still-playing voice immediately")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
	return 0


static func _test_graph_pause_reserves_pooled_player() -> int:
	var runtime: CodaRuntime = _make_runtime()
	runtime.stop_all()
	var pool: CodaVoicePool = runtime.runtime_pool()
	if pool == null:
		push_error("graph pause test needs a voice pool")
		runtime.free()
		return 1
	pool._ensure_pool_size()
	var player: AudioStreamPlayer = pool.acquire()
	if player == null:
		push_error("graph pause test needs a free pooled player")
		runtime.free()
		return 1
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100.0
	player.stream = stream
	runtime.runtime_begin_player_voice(player)
	player.play()
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle._alive = true
	handle._bind_player(player)
	var pk: int = player.get_instance_id()
	runtime._active_handles[pk] = handle
	runtime._graph_playback.pause_graph_preview(handle)
	if not player.has_meta(&"_coda_graph_paused"):
		push_error("graph pause should reserve the pooled player")
		runtime.stop_all()
		runtime.free()
		return 1
	var other: AudioStreamPlayer = runtime.runtime_pool().acquire()
	if other == player:
		push_error("graph pause must not return the paused player from the voice pool")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime._graph_playback.resume_graph_preview(handle)
	if player.stream_paused:
		push_error("graph resume should clear stream_paused")
		runtime.stop_all()
		runtime.free()
		return 1
	if runtime._active_handles.get(pk, null) != handle:
		push_error("graph resume should restore active_handles mapping")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
	return 0


static func _test_graph_stop_after_pause_releases_pool_slot() -> int:
	var runtime: CodaRuntime = _make_runtime()
	runtime.stop_all()
	var pool: CodaVoicePool = runtime.runtime_pool()
	if pool == null:
		push_error("graph stop-after-pause test needs a voice pool")
		runtime.free()
		return 1
	pool._ensure_pool_size()
	var player: AudioStreamPlayer = pool.acquire()
	if player == null:
		push_error("graph stop-after-pause test needs a free pooled player")
		runtime.free()
		return 1
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100.0
	player.stream = stream
	runtime.runtime_begin_player_voice(player)
	player.play()
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle._alive = true
	handle._bind_player(player)
	runtime._active_handles[player.get_instance_id()] = handle
	runtime._graph_playback.pause_graph_preview(handle)
	runtime.stop(handle)
	if player.has_meta(&"_coda_graph_paused"):
		push_error("stop after graph pause must clear _coda_graph_paused")
		runtime.stop_all()
		runtime.free()
		return 1
	for p in pool._players:
		if p.has_meta(&"_coda_graph_paused"):
			push_error("stop after graph pause must not leave stale _coda_graph_paused on pool players")
			runtime.stop_all()
			runtime.free()
			return 1
	var reclaimed: AudioStreamPlayer = pool.acquire()
	if reclaimed == null:
		push_error("pool must return a player after stop following graph pause")
		runtime.stop_all()
		runtime.free()
		return 1
	runtime.stop_all()
	runtime.free()
	return 0


static func _test_loop_backward_wrap_does_not_fire_future_clips() -> int:
	var runtime: SegmentSpawnTestRuntime = _make_runtime()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	runtime.set_project(state)
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var timeline = ev.event_timeline
	timeline.loop_enabled = true
	timeline.loop_start_seconds = 0.0
	timeline.loop_end_seconds = 10.0
	timeline.length_seconds = 10.0
	var lane: CodaTimelineTrack = CodaTimelineTrackScript.new()
	lane.track_name = "SFX"
	var long_clip: CodaTimelineClip = CodaTimelineClipScript.new()
	long_clip.start_seconds = 0.0
	long_clip.duration_seconds = 20.0
	long_clip.audio_path = "res://fake.ogg"
	var future_clip: CodaTimelineClip = CodaTimelineClipScript.new()
	future_clip.start_seconds = 8.0
	future_clip.duration_seconds = 1.0
	future_clip.audio_path = "res://fake.ogg"
	lane.clips.append(long_clip)
	lane.clips.append(future_clip)
	timeline.tracks.append(lane)
	timeline.invalidate_clip_index()
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle._alive = true
	handle.loop = true
	handle.event_node = ev
	handle.timeline_cursor_seconds = 9.5
	handle.timeline_length_seconds = 10.0
	handle.param_values = {}
	handle.param_values_smoothed = {}
	var d: Dictionary = {
		"timeline": timeline,
		"voices": {},
		"fired_clip_ids": {},
		"fired_marker_ids": {},
		"spent_clip_ids": {},
		"loop_override_start": -1.0,
		"loop_override_end": -1.0,
	}
	runtime._timeline_dispatchers[handle] = d
	var counting_voice: CountingLaneVoice = CountingLaneVoice.new()
	counting_voice.setup(runtime, null)
	var dispatcher: CodaTimelineDispatcher = CodaTimelineDispatcherScript.new()
	dispatcher.setup(runtime, null, null)
	dispatcher._lane_voice = counting_voice
	dispatcher._clip_dispatch.setup(runtime, counting_voice)
	runtime._timeline_dispatcher = dispatcher
	dispatcher.tick_dispatchers(1.0)
	if absf(handle.timeline_cursor_seconds - 0.5) > 0.001:
		push_error(
			"loop wrap should land at 0.5, got %s" % handle.timeline_cursor_seconds
		)
		runtime.stop_all()
		runtime.free()
		return 1
	for spawned_id in counting_voice.spawned_clip_ids:
		if spawned_id == future_clip.id:
			push_error("backward loop wrap must not spawn clip starting at 8s when landing at 0.5")
			runtime.stop_all()
			runtime.free()
			return 1
	runtime.stop_all()
	runtime.free()
	return 0


static func _test_timeline_seek_while_paused_updates_cursor_only() -> int:
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
		push_error("paused timeline should consume pending seek")
		runtime.stop_all()
		runtime.free()
		return 1
	if abs(handle.timeline_cursor_seconds - 12.0) > 0.001:
		push_error(
			"paused timeline seek should move cursor without repriming, got %s"
			% handle.timeline_cursor_seconds
		)
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
