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


static func run() -> int:
	var failed: int = 0
	failed += _test_teardown_wet_layers_for_prefix()
	failed += _test_stop_graph_wet_layers_clears_handle()
	failed += _test_clip_id_from_wet_voice_key()
	failed += _test_refresh_voice_output_levels_syncs_wet_layers()
	return failed


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
	if abs(wet.volume_db - (-80.0)) > 0.05:
		push_error("muted track should silence wet send layers, got %s" % wet.volume_db)
		runtime.free()
		return 1
	runtime.free()
	return 0
