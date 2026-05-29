@tool
extends Node
class_name CodaProjectBootstrap

## Loads exported banks on scene start and optionally wires Game Sync rules to a subtree.

@export var bank_paths: Array[String] = []
@export var auto_connect_game_sync: bool = true
@export var game_sync_root: NodePath


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var runtime: CodaRuntime = _runtime()
	if runtime == null:
		push_warning("CodaProjectBootstrap: Coda autoload not found.")
		return
	for path in bank_paths:
		var p: String = path.strip_edges()
		if p.is_empty():
			continue
		var bank_id: String = runtime.load_bank(p)
		if bank_id.is_empty():
			push_warning('CodaProjectBootstrap: failed to load bank "%s".' % p)
	if not auto_connect_game_sync:
		return
	var bridge: Node = get_node_or_null("/root/CodaGameBridge")
	if bridge == null:
		return
	var root: Node = _game_sync_root_node()
	if root == null:
		return
	if bridge.has_method(&"connect_game_signals_from"):
		bridge.call(&"connect_game_signals_from", root)
	elif bridge.has_method(&"connect_game_signals"):
		bridge.call(&"connect_game_signals", root)


func _game_sync_root_node() -> Node:
	if not game_sync_root.is_empty() and has_node(game_sync_root):
		return get_node(game_sync_root)
	return get_tree().current_scene


static func _runtime() -> CodaRuntime:
	var coda: Node = Engine.get_main_loop().root.get_node_or_null("Coda")
	if coda is CodaRuntime:
		return coda as CodaRuntime
	return null
