@tool
class_name CodaBanksTab
extends CodaBrowserTab

## Banks tab — flat list of CodaState.banks.
## Quick actions: New Bank, Validate (delegates to the editor window).
## Selection emits `selection_emitted(CATEGORY_BANK, bank_id)`; the host routes
## the request to the Inspector so the Banks section can edit the selected bank.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaBrowserRenameDialogScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_rename_dialog.gd"
)

const _CTX_RENAME := 1
const _CTX_DUPLICATE := 2
const _CTX_DELETE := 3

var _project: CodaState = null
var _filter_edit: LineEdit
var _list: ItemList
var _add_button: Button
var _delete_button: Button
var _rebuild_queued: bool = false
var _rename_ui: CodaBrowserRenameDialog
var _rename_target_id: String = ""
var _delete_dialog: ConfirmationDialog
var _delete_target_id: String = ""
var _context_menu: PopupMenu
var _context_bank_id: String = ""


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
	_list.gui_input.connect(_on_list_gui_input)
	add_child(_list)

	_setup_rename_dialog()
	_setup_delete_dialog()
	_setup_context_menu()
	set_process_unhandled_key_input(true)

	if _project != null:
		_queue_rebuild()


func attach_state(state: Variant) -> void:
	if state == null:
		return
	_project = CodaBrowserTab.bind_structure_changed(state, _project, _on_project_structure_changed)
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


func request_rename_selected() -> bool:
	var bid: String = _selected_bank_id()
	if bid.is_empty():
		return false
	_open_rename(bid)
	return true


func request_delete_selected() -> bool:
	var bid: String = _selected_bank_id()
	if bid.is_empty():
		return false
	_open_delete(bid)
	return true


func duplicate_selected() -> bool:
	if _project == null:
		return false
	var bid: String = _selected_bank_id()
	if bid.is_empty():
		return false
	var dup: CodaBank = _project.duplicate_bank(bid)
	if dup != null:
		call_deferred(&"select_by_id", dup.id)
		return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _list == null:
		return
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.ctrl_pressed and k.keycode == KEY_D:
			if duplicate_selected():
				get_viewport().set_input_as_handled()


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
		_list.set_item_tooltip(idx, "F2 rename · Right-click for more")
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


func _on_list_gui_input(event: InputEvent) -> void:
	if _list == null or _context_menu == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		var at: Vector2 = mb.position
		var idx: int = _list.get_item_at_position(at, true)
		if idx < 0:
			return
		_list.select(idx)
		_emit_selection()
		_context_bank_id = str(_list.get_item_metadata(idx))
		var gp: Vector2i = Vector2i(int(get_global_mouse_position().x), int(get_global_mouse_position().y))
		_context_menu.popup(Rect2i(gp, Vector2i(1, 1)))
		accept_event()


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


func _setup_rename_dialog() -> void:
	_rename_ui = CodaBrowserRenameDialogScript.create(self, "Rename Bank")
	_rename_ui.connect_confirmed(_on_rename_confirmed)
	_rename_ui.connect_text_submitted(
		func(_t: String) -> void:
			_on_rename_confirmed()
			_rename_ui.hide_dialog()
	)


func _setup_delete_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Delete Bank"
	_delete_dialog.ok_button_text = "Delete"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_dialog)


func _setup_context_menu() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Rename", _CTX_RENAME)
	_context_menu.add_item("Duplicate", _CTX_DUPLICATE)
	_context_menu.add_separator()
	_context_menu.add_item("Delete", _CTX_DELETE)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)


func _on_context_menu_id_pressed(id: int) -> void:
	var bid: String = _context_bank_id if not _context_bank_id.is_empty() else _selected_bank_id()
	if bid.is_empty():
		return
	match id:
		_CTX_RENAME:
			_open_rename(bid)
		_CTX_DUPLICATE:
			if _project != null:
				var dup: CodaBank = _project.duplicate_bank(bid)
				if dup != null:
					call_deferred(&"select_by_id", dup.id)
		_CTX_DELETE:
			_open_delete(bid)
	_context_bank_id = ""


func _open_rename(bank_id: String) -> void:
	if _project == null:
		return
	var bank: CodaBank = _project.find_bank_by_id(bank_id)
	if bank == null:
		return
	_rename_target_id = bank_id
	_rename_ui.popup_for(bank.bank_name)


func _on_rename_confirmed() -> void:
	if _project == null or _rename_target_id.is_empty():
		return
	_project.rename_bank(_rename_target_id, _rename_ui.field.text)
	call_deferred(&"select_by_id", _rename_target_id)


func _open_delete(bank_id: String) -> void:
	if _project == null:
		return
	var bank: CodaBank = _project.find_bank_by_id(bank_id)
	if bank == null:
		return
	_delete_target_id = bank_id
	_delete_dialog.dialog_text = 'Delete bank "%s"?' % bank.bank_name
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	if _project == null or _delete_target_id.is_empty():
		return
	_project.remove_bank(_delete_target_id)
	_delete_target_id = ""


# ---------- Quick actions ----------

func _on_add_pressed() -> void:
	if _project == null:
		return
	var b: CodaBank = _project.add_bank("Bank %d" % (_project.banks.size() + 1))
	if b != null:
		call_deferred(&"select_by_id", b.id)


func _on_delete_pressed() -> void:
	var bid: String = _selected_bank_id()
	if bid.is_empty():
		return
	_open_delete(bid)
