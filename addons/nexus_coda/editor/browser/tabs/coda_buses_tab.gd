@tool
class_name CodaBusesTab
extends CodaBrowserTab

## Buses tab — tree from CodaState.bus_root.
## Read-only navigation: selecting a bus emits `selection_emitted(CATEGORY_BUS, bus_id)`,
## which the host translates into `external_selection_requested(&"mixer", ..., bus_id)`.
## Edits (volume / mute / solo / send) live in the Mixer panel.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _project: CodaState = null
var _filter_edit: LineEdit
var _tree: Tree
var _add_bus_button: Button
var _rebuild_queued: bool = false


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_XS)


func get_tab_title() -> String:
	return "Buses"


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var qa := HBoxContainer.new()
	qa.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	qa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(qa)

	_add_bus_button = Button.new()
	_add_bus_button.text = "+ Bus"
	_add_bus_button.tooltip_text = "Add a child bus to the selected bus (or to Master)"
	_add_bus_button.pressed.connect(_on_add_bus_pressed)
	qa.add_child(_add_bus_button)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter..."
	_filter_edit.clear_button_enabled = true
	_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_edit.text_changed.connect(_on_filter_changed)
	add_child(_filter_edit)

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
	if _project != null and _project.structure_changed.is_connected(_on_project_structure_changed):
		_project.structure_changed.disconnect(_on_project_structure_changed)
	_project = null if state == null else (state as CodaState)
	if _project != null:
		_project.structure_changed.connect(_on_project_structure_changed)
	if _tree != null:
		_queue_rebuild()


func apply_filter(text: String) -> void:
	if _filter_edit != null and _filter_edit.text != text:
		_filter_edit.text = text


func pulse_selection_to_editor() -> void:
	_emit_selection()


func select_by_id(target_id: String) -> bool:
	if _tree == null or target_id.is_empty():
		return false
	var found: TreeItem = _find_item(_tree.get_root(), target_id)
	if found == null:
		return false
	found.select(0)
	_tree.scroll_to_item(found)
	_emit_selection()
	return true


# ---------- Internals ----------

func _on_project_structure_changed() -> void:
	_queue_rebuild()


func _on_filter_changed(_text: String) -> void:
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred(&"_deferred_rebuild")


func _deferred_rebuild() -> void:
	var prev: String = ""
	if _tree != null:
		var sel: TreeItem = _tree.get_selected()
		if sel != null:
			prev = str(sel.get_metadata(0))
	_rebuild_queued = false
	_rebuild_tree()
	if not prev.is_empty():
		var found: TreeItem = _find_item(_tree.get_root(), prev)
		if found != null:
			found.select(0)


func _rebuild_tree() -> void:
	if _tree == null or _project == null or _project.bus_root == null:
		return
	_tree.clear()
	var root_item: TreeItem = _tree.create_item()
	root_item.set_metadata(0, "")
	_build_branch(root_item, _project.bus_root, _filter_text_lower())


func _build_branch(parent_item: TreeItem, bus: CodaBus, filter_lower: String) -> void:
	if not _branch_visible(bus, filter_lower):
		return
	var item := _tree.create_item(parent_item)
	item.set_text(0, bus.bus_name)
	item.set_metadata(0, bus.id)
	for child in bus.children:
		_build_branch(item, child, filter_lower)


func _branch_visible(bus: CodaBus, filter_lower: String) -> bool:
	if filter_lower.is_empty():
		return true
	if String(bus.bus_name).to_lower().contains(filter_lower):
		return true
	for c in bus.children:
		if _branch_visible(c, filter_lower):
			return true
	return false


func _filter_text_lower() -> String:
	if _filter_edit == null:
		return ""
	return _filter_edit.text.strip_edges().to_lower()


func _find_item(item: TreeItem, target_id: String) -> TreeItem:
	if item == null:
		return null
	if str(item.get_metadata(0)) == target_id:
		return item
	var c: TreeItem = item.get_first_child()
	while c != null:
		var f: TreeItem = _find_item(c, target_id)
		if f != null:
			return f
		c = c.get_next()
	return null


func _on_item_selected() -> void:
	_emit_selection()


func _emit_selection() -> bool:
	if _tree == null:
		return false
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return false
	var bus_id: String = str(item.get_metadata(0))
	if bus_id.is_empty():
		return false
	selection_emitted.emit(CATEGORY_BUS, bus_id)
	return true


# ---------- Quick action ----------

func _on_add_bus_pressed() -> void:
	if _project == null or _project.bus_root == null:
		return
	var parent_id: String = _project.bus_root.id
	if _tree != null:
		var sel: TreeItem = _tree.get_selected()
		if sel != null:
			var sid: String = str(sel.get_metadata(0))
			if not sid.is_empty():
				parent_id = sid
	_project.add_child_bus(parent_id, "Bus")
