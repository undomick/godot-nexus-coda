extends RefCounted
class_name TestRuntimeNodes

const CodaEventEmitterScript := preload(
	"res://addons/nexus_coda/runtime/nodes/coda_event_emitter.gd"
)
const CodaGameBridgeScript := preload("res://addons/nexus_coda/runtime/coda_game_bridge.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_emitter_empty_path()
	failed += _test_connect_game_signals_from_empty_tree()
	failed += _test_emit_from_area_payload_keys()
	return failed


static func _test_emitter_empty_path() -> int:
	var emitter: Node = CodaEventEmitterScript.new()
	emitter.set("event_path", "")
	var handle = emitter.call("play")
	if handle != null:
		push_error("emitter should return null for empty event_path")
		emitter.free()
		return 1
	emitter.free()
	return 0


static func _test_connect_game_signals_from_empty_tree() -> int:
	var bridge: Node = CodaGameBridgeScript.new()
	var root := Node.new()
	bridge.call("connect_game_signals_from", root)
	bridge.call("disconnect_game_signals")
	root.free()
	bridge.free()
	return 0


static func _test_emit_from_area_payload_keys() -> int:
	var bridge: Node = CodaGameBridgeScript.new()
	var body := Node.new()
	body.name = "Player"
	bridge.call("emit_from_area", "zone_entered", body, {"zone": "forest"})
	body.free()
	bridge.free()
	return 0
