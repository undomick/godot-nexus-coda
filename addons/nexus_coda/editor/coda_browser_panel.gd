@tool
extends VBoxContainer

signal event_selection_changed(node: CodaBrowserNode)
signal asset_selection_changed(node: CodaBrowserNode)

const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const BrowserContextMenuScript := preload("res://addons/nexus_coda/editor/browser_context_menu.gd")

@onready var _filter_edit: LineEdit = %FilterBar
@onready var _tabs: TabContainer = %BrowserTabContainer
@onready var _events_tree: Tree = %EventsTree
@onready var _assets_tree: Tree = %AssetsTree

var _project = CodaStateScript.new()
var _browser_ctx: BrowserContextMenu

var _rename_dialog: AcceptDialog
var _rename_field: LineEdit
var _rename_target_id: String = ""

var _delete_dialog: ConfirmationDialog
var _delete_target_id: String = ""


func _ready() -> void:
	_browser_ctx = BrowserContextMenuScript.new()
	add_child(_browser_ctx)
	_browser_ctx.attach_popups_to(self)
	_browser_ctx.context_action.connect(_on_browser_context_action)

	_project.structure_changed.connect(_on_project_structure_changed)
	_filter_edit.text_changed.connect(_on_filter_changed)
	_events_tree.hide_root = true
	_assets_tree.hide_root = true
	_events_tree.allow_rmb_select = true
	_assets_tree.allow_rmb_select = true
	_events_tree.item_selected.connect(_on_events_item_selected)
	_assets_tree.item_selected.connect(_on_assets_item_selected)
	_events_tree.gui_input.connect(_on_events_tree_gui_input)
	_assets_tree.gui_input.connect(_on_assets_tree_gui_input)

	_setup_rename_dialog()
	_setup_delete_dialog()
	_rebuild_both_trees()


func get_project():
	return _project


func set_project(project: Variant) -> void:
	if project == null:
		return
	if _project.structure_changed.is_connected(_on_project_structure_changed):
		_project.structure_changed.disconnect(_on_project_structure_changed)
	_project = project
	_project.structure_changed.connect(_on_project_structure_changed)
	_rebuild_both_trees()


func _on_project_structure_changed() -> void:
	_rebuild_both_trees()


func _on_filter_changed(_new_text: String) -> void:
	_rebuild_both_trees()


func _filter_text() -> String:
	return _filter_edit.text.strip_edges()


func _branch_visible(node: CodaBrowserNode, filter_lower: String) -> bool:
	if filter_lower.is_empty():
		return true
	if node.name.to_lower().contains(filter_lower):
		return true
	for c in node.children:
		if _branch_visible(c, filter_lower):
			return true
	return false


func _build_tree_branch(tree: Tree, parent_item: TreeItem, node: CodaBrowserNode, filter_lower: String) -> void:
	if not _branch_visible(node, filter_lower):
		return
	var item := tree.create_item(parent_item)
	item.set_text(0, node.name)
	item.set_metadata(0, node.id)
	if node.is_folder():
		item.set_collapsed(false)
	for child in node.children:
		_build_tree_branch(tree, item, child, filter_lower)


func _rebuild_events_tree() -> void:
	_events_tree.clear()
	var root_item: TreeItem = _events_tree.create_item()
	root_item.set_metadata(0, _project.events_root.id)
	var fl := _filter_text().to_lower()
	for child in _project.events_root.children:
		_build_tree_branch(_events_tree, root_item, child, fl)


func _rebuild_assets_tree() -> void:
	_assets_tree.clear()
	var root_item: TreeItem = _assets_tree.create_item()
	root_item.set_metadata(0, _project.assets_root.id)
	var fl := _filter_text().to_lower()
	for child in _project.assets_root.children:
		_build_tree_branch(_assets_tree, root_item, child, fl)


func _rebuild_both_trees() -> void:
	_rebuild_events_tree()
	_rebuild_assets_tree()


func _on_events_item_selected() -> void:
	var item: TreeItem = _events_tree.get_selected()
	if item == null:
		return
	var nid: String = str(item.get_metadata(0))
	var node: CodaBrowserNode = _project.find_node_anywhere(nid)
	if node != null:
		event_selection_changed.emit(node)


func _on_assets_item_selected() -> void:
	var item: TreeItem = _assets_tree.get_selected()
	if item == null:
		return
	var nid: String = str(item.get_metadata(0))
	var node: CodaBrowserNode = _project.find_node_anywhere(nid)
	if node != null:
		asset_selection_changed.emit(node)


func _on_events_tree_gui_input(event: InputEvent) -> void:
	_handle_tree_rmb(event, _events_tree)


func _on_assets_tree_gui_input(event: InputEvent) -> void:
	_handle_tree_rmb(event, _assets_tree)


## TabContainer only accepts its direct children (tab pages) in get_tab_idx_from_control; Events tree may sit under Events/Panel/VBox/Tree.
func _tab_page_for_descendant(node: Node) -> Control:
	var n: Node = node
	while n != null:
		var par: Node = n.get_parent()
		if par == _tabs:
			return n as Control
		n = par
	return null


func _handle_tree_rmb(event: InputEvent, tree: Tree) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	var events_page: Control = _tab_page_for_descendant(_events_tree)
	if events_page == null:
		return
	var events_tab_idx: int = _tabs.get_tab_idx_from_control(events_page)
	if events_tab_idx < 0:
		return
	var on_events_tab: bool = _tabs.current_tab == events_tab_idx
	var expected_tree: Tree = _events_tree if on_events_tab else _assets_tree
	if tree != expected_tree:
		return
	var is_events_panel: bool = on_events_tab
	var root_id: String = _project.events_root.id if is_events_panel else _project.assets_root.id
	var local_pos: Vector2 = tree.get_local_mouse_position()
	var item: TreeItem = tree.get_item_at_position(local_pos)
	var nid: String
	var allow_rd: bool
	if item != null:
		nid = str(item.get_metadata(0))
		item.select(0)
		tree.scroll_to_item(item)
		var n: CodaBrowserNode = _project.find_node_anywhere(nid)
		if is_events_panel:
			allow_rd = n != null and n != _project.events_root
		else:
			allow_rd = n != null and n != _project.assets_root
	else:
		nid = root_id
		allow_rd = false
	var gp := Vector2i(tree.get_global_mouse_position())
	if is_events_panel:
		_browser_ctx.open_events_at(gp, nid, allow_rd)
	else:
		_browser_ctx.open_assets_at(gp, nid, allow_rd)
	tree.accept_event()


func _ctx_target_folder_id(clicked_node_id: String, is_events: bool) -> String:
	var node: CodaBrowserNode = _project.find_node_anywhere(clicked_node_id)
	if node == null:
		return _project.events_root.id if is_events else _project.assets_root.id
	if node.is_folder():
		return node.id
	var parent: CodaBrowserNode = (
		_project.events_parent_of(node.id) if is_events else _project.assets_parent_of(node.id)
	)
	if parent != null:
		return parent.id
	return _project.events_root.id if is_events else _project.assets_root.id


func _on_browser_context_action(is_events: bool, action_id: int, clicked_node_id: String) -> void:
	var folder_id: String = _ctx_target_folder_id(clicked_node_id, is_events)
	match action_id:
		BrowserContextMenu.ID_NEW_FOLDER:
			if is_events:
				_project.add_events_folder(folder_id, "New Folder")
			else:
				_project.add_assets_folder(folder_id, "New Folder")
		BrowserContextMenu.ID_NEW_LEAF:
			if is_events:
				_project.add_events_event(folder_id, "New Event")
			else:
				_project.add_asset_placeholder(folder_id, "New Asset")
		BrowserContextMenu.ID_RENAME:
			_open_rename(clicked_node_id)
		BrowserContextMenu.ID_DELETE:
			_open_delete(clicked_node_id)


func _open_rename(node_id: String) -> void:
	var node: CodaBrowserNode = _project.find_node_anywhere(node_id)
	if node == null:
		return
	if node == _project.events_root or node == _project.assets_root:
		return
	_rename_target_id = node_id
	_rename_field.text = node.name
	_rename_dialog.popup_centered()


func _setup_rename_dialog() -> void:
	_rename_dialog = AcceptDialog.new()
	_rename_dialog.title = "Rename"
	_rename_dialog.dialog_autowrap = true
	_rename_field = LineEdit.new()
	_rename_field.custom_minimum_size = Vector2(280, 0)
	_rename_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.add_child(_rename_field)
	_rename_dialog.add_child(margin)
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	_rename_dialog.about_to_popup.connect(
		func() -> void: _rename_field.call_deferred(&"grab_focus")
	)
	_rename_field.text_submitted.connect(
		func(_t: String) -> void:
			_on_rename_confirmed()
			_rename_dialog.hide()
	)
	add_child(_rename_dialog)


func _on_rename_confirmed() -> void:
	var new_name: String = _rename_field.text
	_project.rename_node(_rename_target_id, new_name)


func _open_delete(node_id: String) -> void:
	var node: CodaBrowserNode = _project.find_node_anywhere(node_id)
	if node == null:
		return
	if node == _project.events_root or node == _project.assets_root:
		return
	_delete_target_id = node_id
	_delete_dialog.dialog_text = 'Delete "%s"?' % node.name
	_delete_dialog.popup_centered()


func _setup_delete_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Delete"
	_delete_dialog.ok_button_text = "Delete"
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)


func _on_delete_confirmed() -> void:
	_project.delete_node(_delete_target_id)
