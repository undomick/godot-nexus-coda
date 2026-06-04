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
	var send: CodaBusSend = CodaBusSendScript.new()
	send.target_bus_id = ret.id
	send.level = 0.5
	send.parameter_id = "wet_amount"
	var merged: Array[CodaBusSend] = [send]
	var muted_db: float = CodaVoiceWetLayersScript.wet_volume_db_for_layer(
		0.0, 0, merged, bus_root, {"wet_amount": 0.0}
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
