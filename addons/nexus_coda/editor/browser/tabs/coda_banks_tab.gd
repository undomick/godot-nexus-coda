@tool
class_name CodaBanksTab
extends CodaBrowserTab

## Banks tab — flat list of CodaState.banks.
## Quick actions: New Bank, Validate (delegates to the editor window).
## Selection emits `selection_emitted(CATEGORY_BANK, bank_id)`; the host routes
## the request to the Inspector so the Banks section can edit the selected bank.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _project: CodaState = null
var _filter_edit: LineEdit
var _list: ItemList
var _add_button: Button
var _delete_button: Button
var _rebuild_queued: bool = false


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_XS)


func get_tab_title() -> String:
	return "Banks"


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var qa := HBoxContainer.new()
	qa.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	qa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(qa)

	_add_button = Button.new()
	_add_button.text = "+ Bank"
	_add_button.tooltip_text = "Create a new bank"
	_add_button.pressed.connect(_on_add_pressed)
	qa.add_child(_add_button)

	_delete_button = Button.new()
	_delete_button.text = "−"
	_delete_button.tooltip_text = "Remove the selected bank"
	_delete_button.disabled = true
	_delete_button.pressed.connect(_on_delete_pressed)
	qa.add_child(_delete_button)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter..."
	_filter_edit.clear_button_enabled = true
	_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_edit.text_changed.connect(_on_filter_changed)
	add_child(_filter_edit)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	_list.item_selected.connect(_on_item_selected)
	_list.empty_clicked.connect(_on_empty_clicked)
	add_child(_list)

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
	if _list != null:
		_queue_rebuild()


func apply_filter(text: String) -> void:
	if _filter_edit != null and _filter_edit.text != text:
		_filter_edit.text = text


func pulse_selection_to_editor() -> void:
	_emit_selection()


func select_by_id(target_id: String) -> bool:
	if _list == null or target_id.is_empty() or _project == null:
		return false
	for i in _list.item_count:
		if str(_list.get_item_metadata(i)) == target_id:
			_list.select(i)
			_list.ensure_current_is_visible()
			_emit_selection()
			return true
	return false


# ---------- Internals ----------

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
	var prev: String = _selected_bank_id()
	_rebuild_queued = false
	_rebuild_list()
	if not prev.is_empty():
		select_by_id(prev)


func _rebuild_list() -> void:
	if _list == null or _project == null:
		return
	_list.clear()
	var fl: String = _filter_text_lower()
	for b in _project.banks:
		if not fl.is_empty() and not String(b.bank_name).to_lower().contains(fl):
			continue
		var label: String = "%s  (%d events)" % [b.bank_name, b.event_ids.size()]
		var idx: int = _list.add_item(label)
		_list.set_item_metadata(idx, b.id)
		_list.set_item_tooltip(idx, "Edit in Inspector → Banks section")
	_update_delete_button_state()


func _selected_bank_id() -> String:
	if _list == null:
		return ""
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.is_empty():
		return ""
	return str(_list.get_item_metadata(sel[0]))


func _on_item_selected(_idx: int) -> void:
	_update_delete_button_state()
	_emit_selection()


func _on_empty_clicked(_pos: Vector2, _btn: int) -> void:
	if _list != null:
		_list.deselect_all()
	_update_delete_button_state()


func _update_delete_button_state() -> void:
	if _delete_button == null:
		return
	_delete_button.disabled = _selected_bank_id().is_empty()


func _emit_selection() -> bool:
	var bid: String = _selected_bank_id()
	if bid.is_empty():
		return false
	selection_emitted.emit(CATEGORY_BANK, bid)
	return true


# ---------- Quick actions ----------

func _on_add_pressed() -> void:
	if _project == null:
		return
	var b: CodaBank = _project.add_bank("Bank %d" % (_project.banks.size() + 1))
	# Re-emit selection so the inspector focuses the freshly created bank.
	if b != null:
		call_deferred(&"select_by_id", b.id)


func _on_delete_pressed() -> void:
	if _project == null:
		return
	var bid: String = _selected_bank_id()
	if bid.is_empty():
		return
	_project.remove_bank(bid)
