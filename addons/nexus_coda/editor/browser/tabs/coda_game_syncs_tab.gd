@tool
class_name CodaGameSyncsTab
extends CodaBrowserTab

## Game Syncs tab — parameters/modulations overview plus editable game-sync rules.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaGameSyncRuleScript := preload("res://addons/nexus_coda/editor/browser/coda_game_sync_rule.gd")

const KIND_PARAMETER := "parameter"
const KIND_MODULATION := "modulation"
const KIND_RULE := "rule"

var _project: CodaState = null
var _filter_edit: LineEdit
var _tree: Tree
var _add_rule_btn: Button
var _remove_rule_btn: Button
var _rebuild_queued: bool = false


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_XS)


func get_tab_title() -> String:
	return "Game Syncs"


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	add_child(toolbar)

	_add_rule_btn = Button.new()
	_add_rule_btn.text = "Add Rule"
	_add_rule_btn.pressed.connect(_on_add_rule_pressed)
	toolbar.add_child(_add_rule_btn)

	_remove_rule_btn = Button.new()
	_remove_rule_btn.text = "Remove Rule"
	_remove_rule_btn.pressed.connect(_on_remove_rule_pressed)
	toolbar.add_child(_remove_rule_btn)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter..."
	_filter_edit.clear_button_enabled = true
	_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_edit.text_changed.connect(_on_filter_changed)
	toolbar.add_child(_filter_edit)

	_tree = Tree.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.allow_rmb_select = false
	_tree.item_selected.connect(_on_item_selected)
	add_child(_tree)

	if _project != null:
		_queue_rebuild()


func attach_state(state: Variant) -> void:
	if state == null:
		return
	if _project != null and _project.structure_changed.is_connected(_on_project_structure_changed):
		_project.structure_changed.disconnect(_on_project_structure_changed)
	_project = state as CodaState
	if _project != null:
		_project.structure_changed.connect(_on_project_structure_changed)
	if _tree != null:
		_queue_rebuild()


func apply_filter(text: String) -> void:
	if _filter_edit != null and _filter_edit.text != text:
		_filter_edit.text = text


func pulse_selection_to_editor() -> void:
	_emit_selection()


func _on_add_rule_pressed() -> void:
	if _project == null:
		return
	var rule: CodaGameSyncRule = _project.add_game_sync_rule()
	rule.signal_name = "game_event"
	rule.action = CodaGameSyncRule.Action.SET_MUSIC
	rule.target_event_path = "music/exploration"
	_queue_rebuild()


func _on_remove_rule_pressed() -> void:
	if _project == null or _tree == null:
		return
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var payload: Variant = item.get_metadata(0)
	if not (payload is Dictionary):
		return
	if str((payload as Dictionary).get("kind", "")) != KIND_RULE:
		return
	var rule_id: String = str((payload as Dictionary).get("item_id", ""))
	if rule_id.is_empty():
		return
	_project.remove_game_sync_rule(rule_id)
	_queue_rebuild()


func _on_project_structure_changed() -> void:
	_queue_rebuild()


func _on_filter_changed(_text: String) -> void:
	_queue_rebuild()


func _filter_text_lower() -> String:
	if _filter_edit == null:
		return ""
	return _filter_edit.text.strip_edges().to_lower()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred(&"_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	_rebuild_tree()


func _rebuild_tree() -> void:
	if _tree == null or _project == null:
		return
	_tree.clear()
	var root_item: TreeItem = _tree.create_item()
	root_item.set_metadata(0, _make_payload("", "", ""))

	var rules_root: TreeItem = _tree.create_item(root_item)
	rules_root.set_text(0, "Game Sync Rules")
	rules_root.set_selectable(0, false)
	for rule in _project.game_sync_rules:
		if not _matches_filter(rule.signal_name, rule.target_event_path, _filter_text_lower()):
			continue
		var leaf: TreeItem = _tree.create_item(rules_root)
		leaf.set_text(
			0,
			"%s → %s (%s)" % [
				rule.signal_name,
				CodaGameSyncRule.action_label(rule.action),
				rule.target_event_path,
			]
		)
		leaf.set_metadata(0, _make_payload("", KIND_RULE, rule.id))
	if rules_root.get_first_child() == null:
		rules_root.set_text(0, "Game Sync Rules (none)")

	var params_root: TreeItem = _tree.create_item(root_item)
	params_root.set_text(0, "Parameters")
	params_root.set_selectable(0, false)
	_collect_event_items(_project.events_root, params_root, _filter_text_lower(), true)
	if params_root.get_first_child() == null:
		params_root.set_text(0, "Parameters (none)")

	var mods_root: TreeItem = _tree.create_item(root_item)
	mods_root.set_text(0, "Modulations")
	mods_root.set_selectable(0, false)
	_collect_event_items(_project.events_root, mods_root, _filter_text_lower(), false)
	if mods_root.get_first_child() == null:
		mods_root.set_text(0, "Modulations (none)")


func _collect_event_items(
	folder: CodaBrowserNode, parent_item: TreeItem, fl: String, is_parameters: bool
) -> void:
	for child in folder.children:
		if child.is_folder():
			_collect_event_items(child, parent_item, fl, is_parameters)
			continue
		if child.kind != CodaBrowserNode.Kind.EVENT:
			continue
		var entries: Array = child.event_parameters if is_parameters else child.event_modulations
		if entries.is_empty():
			continue
		var visible_entries: Array = []
		for entry in entries:
			var label: String = _entry_label(entry, is_parameters)
			if not _matches_filter(label, child.name, fl):
				continue
			visible_entries.append(entry)
		if visible_entries.is_empty():
			continue
		var event_item: TreeItem = _tree.create_item(parent_item)
		event_item.set_text(0, child.name)
		event_item.set_selectable(0, false)
		for entry in visible_entries:
			var leaf: TreeItem = _tree.create_item(event_item)
			leaf.set_text(0, _entry_label(entry, is_parameters))
			leaf.set_metadata(
				0,
				_make_payload(
					child.id, KIND_PARAMETER if is_parameters else KIND_MODULATION, entry.id
				)
			)


static func _entry_label(entry: Variant, is_parameters: bool) -> String:
	if is_parameters:
		var p := entry as CodaEventParameter
		if p == null:
			return "?"
		var unit: String = (" " + p.unit_hint) if not p.unit_hint.is_empty() else ""
		return "%s [%s]%s" % [p.param_name, _param_type_label(p.param_type), unit]
	var m := entry as CodaModulation
	if m == null:
		return "?"
	return CodaModulation.display_name_for_target(m.target_property)


static func _param_type_label(t: CodaEventParameter.ParamType) -> String:
	match t:
		CodaEventParameter.ParamType.FLOAT:
			return "float"
		CodaEventParameter.ParamType.INT:
			return "int"
		CodaEventParameter.ParamType.BOOL:
			return "bool"
		CodaEventParameter.ParamType.STRING:
			return "string"
	return "?"


static func _matches_filter(label: String, event_name: String, fl: String) -> bool:
	if fl.is_empty():
		return true
	if label.to_lower().contains(fl):
		return true
	if event_name.to_lower().contains(fl):
		return true
	return false


static func _make_payload(event_id: String, kind: String, item_id: String) -> Dictionary:
	return {"event_id": event_id, "kind": kind, "item_id": item_id}


func _on_item_selected() -> void:
	_emit_selection()


func _emit_selection() -> bool:
	if _tree == null:
		return false
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return false
	var payload: Variant = item.get_metadata(0)
	if not (payload is Dictionary):
		return false
	var kind: String = str((payload as Dictionary).get("kind", ""))
	var item_id: String = str((payload as Dictionary).get("item_id", ""))
	if kind == KIND_RULE:
		if item_id.is_empty():
			return false
		selection_emitted.emit(CATEGORY_GAME_SYNC, payload)
		return true
	var event_id: String = str((payload as Dictionary).get("event_id", ""))
	if event_id.is_empty() or item_id.is_empty():
		return false
	selection_emitted.emit(CATEGORY_GAME_SYNC, payload)
	return true
