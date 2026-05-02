extends Node
class_name BrowserContextMenu

signal context_action(is_events_panel: bool, action_id: int, clicked_node_id: String)

const ID_NEW_FOLDER := 0
const ID_NEW_LEAF := 1
const ID_RENAME := 2
const ID_DELETE := 3

var _events_popup: PopupMenu
var _assets_popup: PopupMenu
var _pending_node_id: String = ""


func attach_popups_to(host: Control) -> void:
	if _events_popup != null:
		return
	_events_popup = _create_events_popup()
	_assets_popup = _create_assets_popup()
	host.add_child(_events_popup)
	host.add_child(_assets_popup)


func _create_events_popup() -> PopupMenu:
	var p := PopupMenu.new()
	p.name = "EventsContextMenu"
	p.id_pressed.connect(_on_events_id_pressed)
	p.add_item("New Folder", ID_NEW_FOLDER)
	p.add_item("New Event", ID_NEW_LEAF)
	p.add_separator()
	p.add_item("Rename", ID_RENAME)
	p.add_item("Delete", ID_DELETE)
	return p


func _create_assets_popup() -> PopupMenu:
	var p := PopupMenu.new()
	p.name = "AssetsContextMenu"
	p.id_pressed.connect(_on_assets_id_pressed)
	p.add_item("New Folder", ID_NEW_FOLDER)
	p.add_item("Import Audio File…", ID_NEW_LEAF)
	p.add_separator()
	p.add_item("Rename", ID_RENAME)
	p.add_item("Delete", ID_DELETE)
	return p


func _on_events_id_pressed(id: int) -> void:
	context_action.emit(true, id, _pending_node_id)


func _on_assets_id_pressed(id: int) -> void:
	context_action.emit(false, id, _pending_node_id)


func open_events_at(global_pos: Vector2i, clicked_node_id: String, allow_rename_and_delete: bool) -> void:
	if _events_popup == null:
		return
	_pending_node_id = clicked_node_id
	_set_rename_delete_enabled(_events_popup, allow_rename_and_delete)
	_events_popup.hide()
	_events_popup.reset_size()
	_events_popup.position = global_pos
	_events_popup.popup()


func open_assets_at(global_pos: Vector2i, clicked_node_id: String, allow_rename_and_delete: bool) -> void:
	if _assets_popup == null:
		return
	_pending_node_id = clicked_node_id
	_set_rename_delete_enabled(_assets_popup, allow_rename_and_delete)
	_assets_popup.hide()
	_assets_popup.reset_size()
	_assets_popup.position = global_pos
	_assets_popup.popup()


func _set_rename_delete_enabled(popup: PopupMenu, enabled: bool) -> void:
	var i_r: int = popup.get_item_index(ID_RENAME)
	var i_d: int = popup.get_item_index(ID_DELETE)
	if i_r >= 0:
		popup.set_item_disabled(i_r, not enabled)
	if i_d >= 0:
		popup.set_item_disabled(i_d, not enabled)
