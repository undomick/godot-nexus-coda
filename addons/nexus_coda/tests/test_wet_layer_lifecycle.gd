extends RefCounted
class_name TestWetLayerLifecycle

const CodaVoiceWetLayersScript := preload("res://addons/nexus_coda/runtime/coda_voice_wet_layers.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_teardown_wet_layers_for_prefix()
	failed += _test_stop_graph_wet_layers_clears_handle()
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
