@tool
extends Node

## Routes gameplay signals to Coda actions via CodaGameSyncRule entries on the loaded project.

const CodaGameSyncContextScript := preload(
	"res://addons/nexus_coda/runtime/coda_game_sync_context.gd"
)
const CodaGameSyncDispatcherScript := preload(
	"res://addons/nexus_coda/runtime/coda_game_sync_dispatcher.gd"
)

var _runtime: CodaRuntime = null
var _music: CodaMusicDirector = null
var _ctx: CodaGameSyncContext = null
var _rules: Array[CodaGameSyncRule] = []
var _signal_connections: Array[Dictionary] = []


func bind_runtime(runtime: CodaRuntime, music_director: CodaMusicDirector = null) -> void:
	_runtime = runtime
	_music = music_director
	_ctx = CodaGameSyncContextScript.from_bridge(runtime, music_director)
	_connect_project_loaded()


func _ready() -> void:
	call_deferred(&"_auto_bind")


func _auto_bind() -> void:
	if _runtime != null:
		return
	var coda: Node = get_node_or_null("/root/Coda")
	if coda is CodaRuntime:
		bind_runtime(coda as CodaRuntime, get_node_or_null("/root/CodaMusic") as CodaMusicDirector)


func _connect_project_loaded() -> void:
	if _runtime == null:
		return
	if not _runtime.project_loaded.is_connected(_on_project_loaded):
		_runtime.project_loaded.connect(_on_project_loaded)
	var state: CodaProject = _runtime.get_project()
	if state != null:
		bind_from_project(state)


func _on_project_loaded(state: CodaProject) -> void:
	bind_from_project(state)


func bind_rules(rules: Array) -> void:
	_rules.clear()
	for r in rules:
		if r is CodaGameSyncRule:
			_rules.append(r as CodaGameSyncRule)


func bind_from_project(project: CodaProject) -> void:
	if project == null:
		_rules.clear()
		return
	bind_rules(project.game_sync_rules)


func bind_from_loaded_project() -> void:
	if _runtime == null:
		return
	bind_from_project(_runtime.get_project())


func emit_game_signal(signal_name: String, payload: Dictionary = {}) -> void:
	var key: String = signal_name.strip_edges()
	if key.is_empty() or _ctx == null:
		return
	for rule in _rules:
		if not CodaGameSyncDispatcherScript.rule_matches(rule, key, payload):
			continue
		CodaGameSyncDispatcherScript.dispatch(rule, payload, _ctx)


func connect_game_signals(root: Node) -> void:
	disconnect_game_signals()
	if root == null:
		return
	_connect_node_signals_recursive(root)


func connect_game_signals_from(root: Node) -> void:
	connect_game_signals(root)


func emit_from_area(signal_name: String, body: Node, extra: Dictionary = {}) -> void:
	var payload: Dictionary = extra.duplicate(true)
	if body != null:
		payload["body"] = body.name
		if body.is_inside_tree():
			payload["body_path"] = str(body.get_path())
		else:
			payload["body_path"] = body.name
	emit_game_signal(signal_name, payload)


func disconnect_game_signals() -> void:
	for entry in _signal_connections:
		var source: Object = entry.get("source", null) as Object
		var sig: StringName = entry.get("signal", &"")
		var cb: Callable = entry.get("callable", Callable())
		if source != null and cb.is_valid() and source.is_connected(sig, cb):
			source.disconnect(sig, cb)
	_signal_connections.clear()


func _exit_tree() -> void:
	disconnect_game_signals()
	if _runtime != null and is_instance_valid(_runtime) and _runtime.project_loaded.is_connected(_on_project_loaded):
		_runtime.project_loaded.disconnect(_on_project_loaded)
	_runtime = null
	_music = null
	_ctx = null
	_rules.clear()


func _connect_node_signals_recursive(node: Node) -> void:
	for sig_info in node.get_signal_list():
		var sig_name: String = String(sig_info.get("name", ""))
		if sig_name.is_empty() or sig_name.begins_with("_"):
			continue
		if not _rules_want_signal(sig_name):
			continue
		var cb: Callable = _make_game_signal_callback(sig_name)
		if node.is_connected(sig_name, cb):
			continue
		node.connect(sig_name, cb)
		_signal_connections.append(
			{"source": node, "signal": StringName(sig_name), "callable": cb}
		)
	for child in node.get_children():
		_connect_node_signals_recursive(child)


func _rules_want_signal(signal_name: String) -> bool:
	for rule in _rules:
		if rule.enabled and rule.signal_name == signal_name:
			return true
	return false


func _make_game_signal_callback(signal_name: String) -> Callable:
	# Capture the name per connection; Callable.bind would shift signal args.
	var captured_name: String = signal_name
	return func(arg0: Variant = null) -> void:
		emit_game_signal(captured_name, payload_from_signal_arg(arg0))


static func payload_from_signal_arg(arg0: Variant) -> Dictionary:
	if arg0 is Dictionary:
		return arg0 as Dictionary
	if arg0 != null:
		return {"value": arg0}
	return {}
