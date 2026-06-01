extends RefCounted
class_name CodaSetupCommon

## Shared runtime setup helpers for Coda nodes.
## Kept as small, explicit functions so bootstrap/setup nodes stay readable.


static func get_coda_runtime() -> CodaRuntime:
	var coda: Node = Engine.get_main_loop().root.get_node_or_null("Coda")
	if coda is CodaRuntime:
		return coda as CodaRuntime
	return null


static func load_banks(runtime: CodaRuntime, bank_paths: Array[String], context: String) -> void:
	if runtime == null:
		push_warning("%s: Coda autoload not found." % context)
		return
	if bank_paths.is_empty():
		push_warning("%s: No bank_paths set. Export a .coda_bank and assign it in the inspector." % context)
		return

	for path in bank_paths:
		var p: String = path.strip_edges()
		if p.is_empty():
			continue
		var bank_id: String = runtime.load_bank(p)
		if bank_id.is_empty():
			push_warning('%s: failed to load bank "%s".' % [context, p])


static func connect_game_sync(auto_connect_game_sync: bool, owner: Node, game_sync_root: NodePath) -> void:
	if not auto_connect_game_sync:
		return
	if owner == null or owner.get_tree() == null:
		return

	var bridge: Node = owner.get_node_or_null("/root/CodaGameBridge")
	if bridge == null:
		return
	var root: Node = _resolve_game_sync_root(owner, game_sync_root)
	if root == null:
		return

	if bridge.has_method(&"connect_game_signals_from"):
		bridge.call(&"connect_game_signals_from", root)
	elif bridge.has_method(&"connect_game_signals"):
		bridge.call(&"connect_game_signals", root)


static func _resolve_game_sync_root(owner: Node, game_sync_root: NodePath) -> Node:
	if owner == null:
		return null
	if not game_sync_root.is_empty() and owner.has_node(game_sync_root):
		return owner.get_node(game_sync_root)
	if owner.get_tree() != null:
		return owner.get_tree().current_scene
	return null

