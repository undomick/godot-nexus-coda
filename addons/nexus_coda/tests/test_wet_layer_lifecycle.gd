extends RefCounted
class_name TestWetLayerLifecycle

const CodaVoiceWetLayersScript := preload("res://addons/nexus_coda/runtime/coda_voice_wet_layers.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaTimelineClipDispatchScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_clip_dispatch.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_track.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_event_timeline.gd"
)
const CodaBrowserNodeScript := preload("res://addons/nexus_coda/domain/coda_browser_node.gd")
const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaRuntimeParameterPipelineScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_parameter_pipeline.gd"
)
const CodaTimelineDispatcherScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_dispatcher.gd"
)
const CodaBusSendScript := preload("res://addons/nexus_coda/domain/coda_bus_send.gd")
const CodaBusScript := preload("res://addons/nexus_coda/domain/coda_bus.gd")
const CodaProjectScript := preload("res://addons/nexus_coda/domain/coda_project.gd")
const CodaTrackEffectScript := preload(
	"res://addons/nexus_coda/domain/effects/coda_track_effect.gd"
)
const CodaBusSendRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_bus_send_runtime.gd")
const CodaPooledVoiceLifecycleScript := preload(
	"res://addons/nexus_coda/runtime/coda_pooled_voice_lifecycle.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_detach_dry_player_teardowns_wet_layers()
	failed += _test_teardown_wet_layers_for_prefix()
	failed += _test_stop_graph_wet_layers_clears_handle()
	failed += _test_clip_id_from_wet_voice_key()
	failed += _test_refresh_voice_output_levels_syncs_wet_layers()
	failed += _test_refresh_preserves_wet_send_offset()
	failed += _test_wet_volume_silence_when_send_disabled()
	failed += _test_restart_wet_layers_for_prefix()
	failed += _test_teardown_graph_wet_layers_for_dry()
	failed += _test_stop_graph_wet_layers_clears_by_dry_map()
	failed += _test_refresh_graph_wet_layers_for_dry_rtpc()
	failed += _test_build_wet_voice_layers_reserves_muted_send_layers()
	failed += _test_count_timeline_wet_layers()
	failed += _test_multi_send_rtpc_maps_wet_layers_by_spawn_index()
	failed += _test_ensure_timeline_wet_layers_no_thrash_when_send_not_spawnable()
	failed += _test_ensure_timeline_wet_layers_teardown_when_sends_cleared()
	return failed


static func _test_detach_dry_player_teardowns_wet_layers() -> int:
	var dry: AudioStreamPlayer = AudioStreamPlayer.new()
	var wet: AudioStreamPlayer = AudioStreamPlayer.new()
	var d: Dictionary = {"voices": {"clip_a": dry, "clip_a_wet_0": wet, "clip_b": null}}
	var dispatchers: Dictionary = {null: d}
	CodaPooledVoiceLifecycleScript.detach_player_from_timeline_dispatchers(
		dry, dispatchers, {}, {}, Callable(), Callable()
	)
	var voices: Dictionary = d.get("voices", {})
	if voices.has("clip_a") or voices.has("clip_a_wet_0"):
		push_error("detaching dry timeline player should tear down wet layer keys")
		return 1
	if not voices.has("clip_b"):
		push_error("detach should only remove voices bound to the detached player")
		return 1
	return 0


static func _test_teardown_wet_layers_for_prefix() -> int:
	var d: Dictionary = {"voices": {"clip_a": null, "clip_a_wet_0": null, "clip_a_wet_1": null, "clip_b": null}}
	CodaVoiceWetLayersScript.teardown_wet_layers_for_prefix(d, "clip_a")
	var voices: Dictionary = d.get("voices", {})
	if voices.has("clip_a_wet_0") or voices.has("clip_a_wet_1"):
		push_error("teardown_wet_layers_for_prefix should remove wet voice keys")
		return 1
	if not voices.has("clip_a") or not voices.has("clip_b"):
		push_error("teardown_wet_layers_for_prefix should keep dry voice keys")
		return 1
	return 0


static func _test_stop_graph_wet_layers_clears_handle() -> int:
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.params["_coda_wet_players"] = [null, null]
	CodaVoiceWetLayersScript.stop_graph_wet_layers(handle)
	var wet_players: Array = handle.params.get("_coda_wet_players", ["missing"])
	if not wet_players.is_empty():
		push_error("stop_graph_wet_layers should clear _coda_wet_players")
		return 1
	return 0


static func _test_clip_id_from_wet_voice_key() -> int:
	if CodaTimelineClipDispatchScript.clip_id_from_wet_voice_key("clip_a_wet_0") != "clip_a":
		push_error("clip_id_from_wet_voice_key should strip wet suffix")
		return 1
	if CodaTimelineClipDispatchScript.clip_id_from_wet_voice_key("clip_a") != "":
		push_error("clip_id_from_wet_voice_key should reject dry keys")
		return 1
	return 0


static func _test_refresh_voice_output_levels_syncs_wet_layers() -> int:
	var timeline: CodaEventTimeline = CodaEventTimelineScript.new()
	timeline.length_seconds = 10.0
	var track: CodaTimelineTrack = CodaTimelineTrackScript.new()
	track.mute = true
	var clip: CodaTimelineClip = CodaTimelineClipScript.new()
	clip.id = "clip_a"
	clip.start_seconds = 0.0
	clip.duration_seconds = 5.0
	track.clips.append(clip)
	timeline.tracks.append(track)
	var ev: CodaBrowserNode = CodaBrowserNodeScript.new()
	ev.event_timeline = timeline
	var runtime: CodaRuntime = CodaRuntimeScript.new()
	runtime._parameter_pipeline = CodaRuntimeParameterPipelineScript.new()
	runtime._parameter_pipeline.setup(runtime)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle._alive = true
	handle.event_node = ev
	var dry: AudioStreamPlayer = AudioStreamPlayer.new()
	var wet: AudioStreamPlayer = AudioStreamPlayer.new()
	dry.volume_db = 0.0
	wet.volume_db = 0.0
	var d: Dictionary = {"timeline": timeline, "voices": {"clip_a": dry, "clip_a_wet_0": wet}}
	var dispatcher: CodaTimelineDispatcher = CodaTimelineDispatcherScript.new()
	dispatcher.setup(runtime, null, null)
	dispatcher._clip_dispatch.refresh_voice_output_levels(handle, d, timeline)
	if abs(dry.volume_db - (-80.0)) > 0.05:
		push_error("muted track should silence dry voice")
		runtime.free()
		return 1
	if wet.volume_db > -79.0:
		push_error("muted track should silence wet send layers, got %s" % wet.volume_db)
		runtime.free()
		return 1
	runtime.free()
	return 0


static func _make_return_bus_tree() -> CodaBus:
	var master: CodaBus = CodaBusScript.make_default_master()
	var ret: CodaBus = CodaBusScript.new("Reverb Return")
	ret.bus_kind = CodaBus.BusKind.RETURN
	var reverb: CodaTrackEffect = CodaTrackEffectScript.new()
	reverb.type = CodaTrackEffect.Type.REVERB
	ret.effects.append(reverb)
	master.children.append(ret)
	return master


static func _test_refresh_preserves_wet_send_offset() -> int:
	var bus_root: CodaBus = _make_return_bus_tree()
	var ret: CodaBus = bus_root.children[bus_root.children.size() - 1]
	_ensure_audio_bus(ret.bus_name)
	var timeline: CodaEventTimeline = CodaEventTimelineScript.new()
	timeline.length_seconds = 10.0
	var track: CodaTimelineTrack = CodaTimelineTrackScript.new()
	var send: CodaBusSend = CodaBusSendScript.new()
	send.target_bus_id = ret.id
	send.level = 0.25
	track.wet_sends.append(send)
	var clip: CodaTimelineClip = CodaTimelineClipScript.new()
	clip.id = "clip_a"
	clip.start_seconds = 0.0
	clip.duration_seconds = 5.0
	track.clips.append(clip)
	timeline.tracks.append(track)
	var ev: CodaBrowserNode = CodaBrowserNodeScript.new()
	ev.event_timeline = timeline
	var project: CodaProject = CodaProjectScript.new()
	project.bus_root = bus_root
	var runtime: CodaRuntime = CodaRuntimeScript.new()
	runtime._project = project
	runtime._parameter_pipeline = CodaRuntimeParameterPipelineScript.new()
	runtime._parameter_pipeline.setup(runtime)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle._alive = true
	handle.event_node = ev
	handle.param_values_smoothed = {}
	var dry: AudioStreamPlayer = AudioStreamPlayer.new()
	var wet: AudioStreamPlayer = AudioStreamPlayer.new()
	dry.volume_db = 0.0
	var expected_wet_db: float = CodaBusSendRuntimeScript.linear_to_db(0.25)
	wet.volume_db = expected_wet_db
	var d: Dictionary = {"timeline": timeline, "voices": {"clip_a": dry, "clip_a_wet_0": wet}}
	var dispatcher: CodaTimelineDispatcher = CodaTimelineDispatcherScript.new()
	dispatcher.setup(runtime, null, null)
	dispatcher._clip_dispatch.refresh_voice_output_levels(handle, d, timeline)
	if abs(dry.volume_db - 0.0) > 0.05:
		push_error("unmuted dry voice should stay at 0 dB, got %s" % dry.volume_db)
		runtime.free()
		return 1
	if abs(wet.volume_db - expected_wet_db) > 0.05:
		push_error(
			"refresh should preserve wet send offset, expected %s got %s"
			% [expected_wet_db, wet.volume_db]
		)
		runtime.free()
		return 1
	runtime.free()
	return 0


static func _test_wet_volume_silence_when_send_disabled() -> int:
	var bus_root: CodaBus = _make_return_bus_tree()
	var ret: CodaBus = bus_root.children[bus_root.children.size() - 1]
	_ensure_audio_bus(ret.bus_name)
	var send: CodaBusSend = CodaBusSendScript.new()
	send.target_bus_id = ret.id
	send.level = 0.5
	send.parameter_id = "wet_amount"
	var merged: Array[CodaBusSend] = [send]
	var id_map: Dictionary = {ret.id: ret.bus_name}
	var muted_db: float = CodaVoiceWetLayersScript.wet_volume_db_for_layer(
		0.0, 0, merged, bus_root, {"wet_amount": 0.0}, id_map
	)
	if muted_db > -79.0:
		push_error("disabled RTPC send should silence wet layer, got %s" % muted_db)
		return 1
	var timeline: CodaEventTimeline = CodaEventTimelineScript.new()
	timeline.length_seconds = 10.0
	var track: CodaTimelineTrack = CodaTimelineTrackScript.new()
	track.wet_sends.append(send)
	var clip: CodaTimelineClip = CodaTimelineClipScript.new()
	clip.id = "clip_a"
	clip.start_seconds = 0.0
	clip.duration_seconds = 5.0
	track.clips.append(clip)
	timeline.tracks.append(track)
	var ev: CodaBrowserNode = CodaBrowserNodeScript.new()
	ev.event_timeline = timeline
	var project: CodaProject = CodaProjectScript.new()
	project.bus_root = bus_root
	var runtime: CodaRuntime = CodaRuntimeScript.new()
	runtime._project = project
	runtime._parameter_pipeline = CodaRuntimeParameterPipelineScript.new()
	runtime._parameter_pipeline.setup(runtime)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle._alive = true
	handle.event_node = ev
	handle.param_values_smoothed = {"wet_amount": 0.0}
	var dry: AudioStreamPlayer = AudioStreamPlayer.new()
	var wet: AudioStreamPlayer = AudioStreamPlayer.new()
	dry.volume_db = 0.0
	wet.volume_db = 0.0
	var d: Dictionary = {"timeline": timeline, "voices": {"clip_a": dry, "clip_a_wet_0": wet}}
	var dispatcher: CodaTimelineDispatcher = CodaTimelineDispatcherScript.new()
	dispatcher.setup(runtime, null, null)
	dispatcher._clip_dispatch.refresh_voice_output_levels(handle, d, timeline)
	if wet.volume_db > -79.0:
		push_error("refresh should silence wet layer when RTPC disables send, got %s" % wet.volume_db)
		runtime.free()
		return 1
	runtime.free()
	return 0


static func _test_restart_wet_layers_for_prefix() -> int:
	var wet: AudioStreamPlayer = AudioStreamPlayer.new()
	var d: Dictionary = {"voices": {"clip_a_wet_0": wet, "clip_b_wet_0": AudioStreamPlayer.new()}}
	CodaVoiceWetLayersScript.restart_wet_layers_for_prefix(d, "clip_a", 1.5, true)
	var paused: bool = wet.stream_paused
	if not paused:
		push_error("restart_wet_layers_for_prefix should sync stream_paused from dry")
		return 1
	return 0


static func _test_teardown_graph_wet_layers_for_dry() -> int:
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	var dry_a: AudioStreamPlayer = AudioStreamPlayer.new()
	var dry_b: AudioStreamPlayer = AudioStreamPlayer.new()
	var wet_a: AudioStreamPlayer = AudioStreamPlayer.new()
	var wet_b: AudioStreamPlayer = AudioStreamPlayer.new()
	handle.params["_coda_graph_wet_by_dry"] = {
		str(dry_a.get_instance_id()): [wet_a],
		str(dry_b.get_instance_id()): [wet_b],
	}
	handle.params["_coda_wet_players"] = [wet_a, wet_b]
	CodaVoiceWetLayersScript.teardown_graph_wet_layers_for_dry(handle, dry_a)
	var by_dry: Dictionary = handle.params.get("_coda_graph_wet_by_dry", {})
	if by_dry.has(str(dry_a.get_instance_id())):
		push_error("teardown_graph_wet_layers_for_dry should remove the dry voice mapping")
		return 1
	if not by_dry.has(str(dry_b.get_instance_id())):
		push_error("teardown_graph_wet_layers_for_dry should keep other dry wet layers")
		return 1
	var remaining: Array = handle.params.get("_coda_wet_players", [])
	if remaining.size() != 1 or remaining[0] != wet_b:
		push_error("teardown_graph_wet_layers_for_dry should rebuild _coda_wet_players")
		return 1
	return 0


static func _test_stop_graph_wet_layers_clears_by_dry_map() -> int:
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.params["_coda_graph_wet_by_dry"] = {"1": [AudioStreamPlayer.new()]}
	handle.params["_coda_wet_players"] = handle.params["_coda_graph_wet_by_dry"]["1"]
	CodaVoiceWetLayersScript.stop_graph_wet_layers(handle)
	if handle.params.has("_coda_graph_wet_by_dry"):
		push_error("stop_graph_wet_layers should clear _coda_graph_wet_by_dry")
		return 1
	return 0


static func _test_refresh_graph_wet_layers_for_dry_rtpc() -> int:
	var bus_root: CodaBus = _make_return_bus_tree()
	var ret: CodaBus = bus_root.children[bus_root.children.size() - 1]
	_ensure_audio_bus(ret.bus_name)
	var send: CodaBusSend = CodaBusSendScript.new()
	send.target_bus_id = ret.id
	send.level = 1.0
	send.parameter_id = "wet_amount"
	var ev: CodaBrowserNode = CodaBrowserNodeScript.new()
	ev.event_wet_sends.append(send)
	var project: CodaProject = CodaProjectScript.new()
	project.bus_root = bus_root
	var runtime: CodaRuntime = CodaRuntimeScript.new()
	runtime._project = project
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.event_node = ev
	handle.param_values_smoothed = {"wet_amount": 0.5}
	var dry: AudioStreamPlayer = AudioStreamPlayer.new()
	dry.volume_db = 0.0
	var wet: AudioStreamPlayer = AudioStreamPlayer.new()
	handle.params["_coda_graph_wet_by_dry"] = {str(dry.get_instance_id()): [wet]}
	handle.params["_coda_wet_players"] = [wet]
	CodaVoiceWetLayersScript.refresh_graph_wet_layers_for_dry(
		runtime, handle, dry, handle.param_values_smoothed
	)
	var expected_half_db: float = CodaBusSendRuntimeScript.linear_to_db(0.5)
	if abs(wet.volume_db - expected_half_db) > 0.05:
		push_error(
			"graph wet refresh should apply RTPC send level, expected %s got %s"
			% [expected_half_db, wet.volume_db]
		)
		runtime.free()
		return 1
	handle.param_values_smoothed["wet_amount"] = 0.0
	CodaVoiceWetLayersScript.refresh_graph_wet_layers_for_dry(
		runtime, handle, dry, handle.param_values_smoothed
	)
	if wet.volume_db > -79.0:
		push_error("graph wet refresh should silence wet layer when RTPC disables send")
		runtime.free()
		return 1
	runtime.free()
	return 0


static func _ensure_audio_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)


static func _test_build_wet_voice_layers_reserves_muted_send_layers() -> int:
	var bus_root: CodaBus = _make_return_bus_tree()
	var ret: CodaBus = bus_root.children[bus_root.children.size() - 1]
	_ensure_audio_bus(ret.bus_name)
	var send: CodaBusSend = CodaBusSendScript.new()
	send.target_bus_id = ret.id
	send.level = 1.0
	send.parameter_id = "wet_amount"
	var layers: Array = CodaBusSendRuntimeScript.build_wet_voice_layers(
		[send],
		bus_root,
		{ret.id: ret.bus_name},
		{"wet_amount": 0.0},
		0.0
	)
	if layers.is_empty():
		push_error("disabled RTPC send should still reserve a wet voice layer for later refresh")
		return 1
	var muted_db: float = float(layers[0].get("volume_db", 0.0))
	if muted_db > -79.0:
		push_error("muted RTPC send layer should spawn near silence, got %s" % muted_db)
		return 1
	return 0


static func _test_count_timeline_wet_layers() -> int:
	var voices: Dictionary = {"clip_a": null, "clip_a_wet_0": null, "clip_a_wet_1": null}
	if CodaVoiceWetLayersScript.count_timeline_wet_layers(voices, "clip_a") != 2:
		push_error("count_timeline_wet_layers should count contiguous wet suffix keys")
		return 1
	if CodaVoiceWetLayersScript.count_timeline_wet_layers(voices, "clip_b") != 0:
		push_error("count_timeline_wet_layers should return 0 for missing prefix")
		return 1
	return 0


static func _make_dual_return_bus_tree() -> Dictionary:
	var master: CodaBus = CodaBusScript.make_default_master()
	var reverb_ret: CodaBus = CodaBusScript.new("Reverb Return")
	reverb_ret.bus_kind = CodaBus.BusKind.RETURN
	var reverb: CodaTrackEffect = CodaTrackEffectScript.new()
	reverb.type = CodaTrackEffect.Type.REVERB
	reverb_ret.effects.append(reverb)
	var delay_ret: CodaBus = CodaBusScript.new("Delay Return")
	delay_ret.bus_kind = CodaBus.BusKind.RETURN
	var delay: CodaTrackEffect = CodaTrackEffectScript.new()
	delay.type = CodaTrackEffect.Type.DELAY
	delay_ret.effects.append(delay)
	master.children.append(reverb_ret)
	master.children.append(delay_ret)
	return {"bus_root": master, "reverb": reverb_ret, "delay": delay_ret}


static func _test_multi_send_rtpc_maps_wet_layers_by_spawn_index() -> int:
	var buses: Dictionary = _make_dual_return_bus_tree()
	var bus_root: CodaBus = buses["bus_root"]
	var reverb_ret: CodaBus = buses["reverb"]
	var delay_ret: CodaBus = buses["delay"]
	_ensure_audio_bus(reverb_ret.bus_name)
	_ensure_audio_bus(delay_ret.bus_name)
	var muted_send: CodaBusSend = CodaBusSendScript.new()
	muted_send.target_bus_id = reverb_ret.id
	muted_send.level = 1.0
	muted_send.parameter_id = "reverb_amount"
	var active_send: CodaBusSend = CodaBusSendScript.new()
	active_send.target_bus_id = delay_ret.id
	active_send.level = 0.5
	var merged: Array[CodaBusSend] = [muted_send, active_send]
	var param_values: Dictionary = {"reverb_amount": 0.0}
	var id_map: Dictionary = {reverb_ret.id: reverb_ret.bus_name, delay_ret.id: delay_ret.bus_name}
	var muted_db: float = CodaVoiceWetLayersScript.wet_volume_db_for_layer(
		0.0, 0, merged, bus_root, param_values, id_map
	)
	var active_db: float = CodaVoiceWetLayersScript.wet_volume_db_for_layer(
		0.0, 1, merged, bus_root, param_values, id_map
	)
	if muted_db > -79.0:
		push_error("first wet layer should stay muted when its RTPC send is off, got %s" % muted_db)
		return 1
	var expected_active_db: float = CodaBusSendRuntimeScript.linear_to_db(0.5)
	if abs(active_db - expected_active_db) > 0.05:
		push_error(
			"second wet layer should use the active send level, expected %s got %s"
			% [expected_active_db, active_db]
		)
		return 1
	return 0


static func _test_ensure_timeline_wet_layers_no_thrash_when_send_not_spawnable() -> int:
	var master: CodaBus = CodaBusScript.make_default_master()
	var missing_ret: CodaBus = CodaBusScript.new("Thrashing Missing Return")
	missing_ret.bus_kind = CodaBus.BusKind.RETURN
	var missing_fx: CodaTrackEffect = CodaTrackEffectScript.new()
	missing_fx.type = CodaTrackEffect.Type.REVERB
	missing_ret.effects.append(missing_fx)
	var mirrored_ret: CodaBus = CodaBusScript.new("Thrashing Mirrored Return")
	mirrored_ret.bus_kind = CodaBus.BusKind.RETURN
	var mirrored_fx: CodaTrackEffect = CodaTrackEffectScript.new()
	mirrored_fx.type = CodaTrackEffect.Type.DELAY
	mirrored_ret.effects.append(mirrored_fx)
	master.children.append(missing_ret)
	master.children.append(mirrored_ret)
	var bus_root: CodaBus = master
	_ensure_audio_bus(mirrored_ret.bus_name)
	var first_send: CodaBusSend = CodaBusSendScript.new()
	first_send.target_bus_id = missing_ret.id
	first_send.level = 1.0
	var second_send: CodaBusSend = CodaBusSendScript.new()
	second_send.target_bus_id = mirrored_ret.id
	second_send.level = 0.5
	var merged: Array[CodaBusSend] = [first_send, second_send]
	var project: CodaProject = CodaProjectScript.new()
	project.bus_root = bus_root
	var runtime: CodaRuntime = CodaRuntimeScript.new()
	runtime._project = project
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	var dry: AudioStreamPlayer = AudioStreamPlayer.new()
	var wet: AudioStreamPlayer = AudioStreamPlayer.new()
	var d: Dictionary = {"voices": {"clip_a": dry, "clip_a_wet_0": wet}}
	var wet_id: int = wet.get_instance_id()
	CodaVoiceWetLayersScript.ensure_timeline_wet_layers(
		runtime, handle, d, dry, "clip_a", merged, {}
	)
	CodaVoiceWetLayersScript.ensure_timeline_wet_layers(
		runtime, handle, d, dry, "clip_a", merged, {}
	)
	var voices: Dictionary = d.get("voices", {})
	var kept: AudioStreamPlayer = voices.get("clip_a_wet_0", null) as AudioStreamPlayer
	if kept == null or kept.get_instance_id() != wet_id:
		push_error("ensure_timeline_wet_layers should not respawn existing wet layers every refresh")
		runtime.free()
		return 1
	runtime.free()
	return 0


static func _test_ensure_timeline_wet_layers_teardown_when_sends_cleared() -> int:
	var runtime: CodaRuntime = CodaRuntimeScript.new()
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	var dry: AudioStreamPlayer = AudioStreamPlayer.new()
	var wet: AudioStreamPlayer = AudioStreamPlayer.new()
	var d: Dictionary = {"voices": {"clip_a": dry, "clip_a_wet_0": wet, "clip_a_wet_1": wet}}
	var empty_sends: Array[CodaBusSend] = []
	CodaVoiceWetLayersScript.ensure_timeline_wet_layers(
		runtime, handle, d, dry, "clip_a", empty_sends, {}
	)
	var voices: Dictionary = d.get("voices", {})
	if voices.has("clip_a_wet_0") or voices.has("clip_a_wet_1"):
		push_error("ensure_timeline_wet_layers should tear down wet layers when sends are cleared")
		runtime.free()
		return 1
	if not voices.has("clip_a"):
		push_error("clearing wet sends should keep the dry timeline voice")
		runtime.free()
		return 1
	runtime.free()
	return 0
