@tool
class_name CodaTreeBrowserTab
extends CodaBrowserTab

## Shared implementation for tree-based browser tabs (Events, Assets).
## Renders a folder/leaf tree from a CodaBrowserNode root, owns a per-tab filter,
## hosts a quick-action bar provided by subclasses, and wires drag/drop, rename
## and delete identically for both variants.
##
## Subclasses tweak only what differs:
##   - which root in CodaState to read (events_root vs assets_root)
##   - the leaf icon for non-folder children
##   - the labels of the quick-action and context-menu items

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaBrowserTreeScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_tree.gd"
)
const BrowserContextMenuScript := preload(
	"res://addons/nexus_coda/editor/browser_context_menu.gd"
)
const BrowserFolderIcons := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_folder_icons.gd"
)

const FOLDER_ICON_DISPLAY_MAX := 16

var _is_events_panel: bool = true
var _project: CodaState = null

var _quick_actions: HBoxContainer
var _filter_edit: LineEdit
var _tree: CodaBrowserTree
var _browser_ctx: BrowserContextMenu

var _rename_dialog: AcceptDialog
var _rename_field: LineEdit
var _rename_target_id: String = ""

var _delete_dialog: ConfirmationDialog
var _delete_target_id: String = ""

var _rebuild_queued: bool = false


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_XS)


func configure(is_events_panel: bool) -> void:
	_is_events_panel = is_events_panel


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_quick_actions = HBoxContainer.new()
	_quick_actions.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_quick_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_quick_actions)
	_build_quick_actions(_quick_actions)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter..."
	_filter_edit.clear_button_enabled = true
	_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_edit.text_changed.connect(_on_filter_changed)
	add_child(_filter_edit)

	_tree = CodaBrowserTreeScript.new()
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.allow_rmb_select = true
	_tree.add_theme_constant_override(&"icon_max_width", FOLDER_ICON_DISPLAY_MAX)
	add_child(_tree)

	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_activated)
	_tree.item_edited.connect(_on_item_edited)
	_tree.rename_committed.connect(_on_tree_rename_committed)
	_tree.item_collapsed.connect(_on_tree_item_collapsed)
	_tree.gui_input.connect(_on_tree_gui_input)

	_browser_ctx = BrowserContextMenuScript.new()
	add_child(_browser_ctx)
	_browser_ctx.attach_popups_to(self)
	_browser_ctx.context_action.connect(_on_browser_context_action)

	_setup_rename_dialog()
	_setup_delete_dialog()

	if _project != null:
		_apply_project_to_tree()
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
		_apply_project_to_tree()
		_queue_rebuild()


func apply_filter(_text: String) -> void:
	# Filter is per-tab and locally owned; the public hook lets the host clear it.
	if _filter_edit != null and _filter_edit.text != _text:
		_filter_edit.text = _text


func pulse_selection_to_editor() -> void:
	_emit_selection()


func select_by_id(target_id: String) -> bool:
	if target_id.is_empty() or _tree == null:
		return false
	var root_item: TreeItem = _tree.get_root()
	if root_item == null:
		return false
	var found: TreeItem = _find_tree_item_by_node_id(root_item, target_id)
	if found == null:
		return false
	found.select(0)
	_tree.scroll_to_item(found)
	_emit_selection()
	return true


# ---------- Subclass hooks ----------

## Subclasses populate the quick-action bar (e.g. events: New Event + New Folder).
func _build_quick_actions(_host: HBoxContainer) -> void:
	pass


## Returns the root CodaBrowserNode this tab renders. Default routing uses _is_events_panel.
func _get_root_node() -> CodaBrowserNode:
	if _project == null:
		return null
	return _project.events_root if _is_events_panel else _project.assets_root


## Subclasses can override to point context menu / quick action "create leaf" calls
## at a different state mutator (e.g. import dialog for assets vs direct add).
func _create_leaf(target_folder_id: String) -> void:
	if _project == null:
		return
	if _is_events_panel:
		_project.add_events_event(target_folder_id, "New Event")
	else:
		_project.add_asset_placeholder(target_folder_id, "New Asset")


func _create_folder(target_folder_id: String) -> void:
	if _project == null:
		return
	if _is_events_panel:
		_project.add_events_folder(target_folder_id, "New Folder")
	else:
		_project.add_assets_folder(target_folder_id, "New Folder")


func _selection_category() -> StringName:
	return CATEGORY_EVENT if _is_events_panel else CATEGORY_ASSET


# ---------- Internals ----------

func _apply_project_to_tree() -> void:
	if _tree == null or _project == null:
		return
	_tree.configure(_project, _is_events_panel)


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
	var prev_sel: String = ""
	if _tree != null:
		var sel_item: TreeItem = _tree.get_selected()
		if sel_item != null:
			prev_sel = str(sel_item.get_metadata(0))
	_rebuild_queued = false
	_rebuild_tree()
	if not prev_sel.is_empty():
		_select_tree_item_by_node_id(prev_sel)
		_emit_selection()


func _rebuild_tree() -> void:
	if _tree == null or _project == null:
		return
	_tree.clear()
	var root: CodaBrowserNode = _get_root_node()
	if root == null:
		return
	var root_item: TreeItem = _tree.create_item()
	root_item.set_metadata(0, root.id)
	var fl: String = _filter_text_lower()
	for child in root.children:
		_build_tree_branch(root_item, child, fl)


func _build_tree_branch(parent_item: TreeItem, node: CodaBrowserNode, filter_lower: String) -> void:
	if not _branch_visible(node, filter_lower):
		return
	var item := _tree.create_item(parent_item)
	item.set_text(0, node.name)
	item.set_metadata(0, node.id)
	item.set_editable(0, false)
	if node.is_folder():
		item.set_collapsed(false)
		_apply_folder_item_icon(item, node)
	elif _is_events_panel and node.kind == CodaBrowserNode.Kind.EVENT:
		item.set_icon(0, BrowserFolderIcons.get_event_leaf_texture())
	else:
		item.set_icon(0, null)
	for child in node.children:
		_build_tree_branch(item, child, filter_lower)


func _branch_visible(node: CodaBrowserNode, filter_lower: String) -> bool:
	if filter_lower.is_empty():
		return true
	if node.name.to_lower().contains(filter_lower):
		return true
	for c in node.children:
		if _branch_visible(c, filter_lower):
			return true
	return false


func _folder_contains_leaf_kind(node: CodaBrowserNode, kind: CodaBrowserNode.Kind) -> bool:
	for c in node.children:
		if c.kind == kind:
			return true
		if c.is_folder() and _folder_contains_leaf_kind(c, kind):
			return true
	return false


func _apply_folder_item_icon(item: TreeItem, folder: CodaBrowserNode) -> void:
	var leaf_kind: CodaBrowserNode.Kind = (
		CodaBrowserNode.Kind.EVENT if _is_events_panel else CodaBrowserNode.Kind.ASSET
	)
	var filled: bool = _folder_contains_leaf_kind(folder, leaf_kind)
	var tex: Texture2D = BrowserFolderIcons.get_folder_texture(item.collapsed, filled)
	item.set_icon(0, tex)


func _refresh_folder_item_icon(item: TreeItem) -> void:
	if _project == null:
		return
	var nid: String = str(item.get_metadata(0))
	var node: CodaBrowserNode = _project.find_node_anywhere(nid)
	if node != null and node.is_folder():
		_apply_folder_item_icon(item, node)


func _select_tree_item_by_node_id(target_id: String) -> void:
	if _tree == null:
		return
	var root_item: TreeItem = _tree.get_root()
	if root_item == null:
		return
	var found: TreeItem = _find_tree_item_by_node_id(root_item, target_id)
	if found != null:
		found.select(0)
		_tree.scroll_to_item(found)


func _find_tree_item_by_node_id(item: TreeItem, target_id: String) -> TreeItem:
	if str(item.get_metadata(0)) == target_id:
		return item
	var child: TreeItem = item.get_first_child()
	while child != null:
		var deeper: TreeItem = _find_tree_item_by_node_id(child, target_id)
		if deeper != null:
			return deeper
		child = child.get_next()
	return null


# ---------- Selection routing ----------

func _on_item_selected() -> void:
	if not _emit_selection():
		call_deferred(&"_deferred_emit_selection")


func _deferred_emit_selection() -> void:
	_emit_selection()


func _emit_selection() -> bool:
	if _tree == null or _project == null:
		return false
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return false
	var nid: String = str(item.get_metadata(0))
	var node: CodaBrowserNode = _project.find_node_anywhere(nid)
	if node == null:
		return false
	if node.kind == CodaBrowserNode.Kind.EVENT:
		NexusCodaLog.debug(
			"browser",
			'emit selection ("%s" id=%s)' % [node.name, node.id],
		)
	selection_emitted.emit(_selection_category(), node)
	return true


func _on_item_activated() -> void:
	if _tree != null:
		_tree.begin_rename_selected_if_allowed()


func _on_item_edited() -> void:
	if _tree != null:
		_tree.commit_edited_if_rename(_tree.get_edited(), _tree.get_edited_column())


func _on_tree_rename_committed(node_id: String, new_name: String) -> void:
	if _project != null:
		_project.rename_node(node_id, new_name)


func _on_tree_item_collapsed(item: TreeItem) -> void:
	_refresh_folder_item_icon(item)


func _on_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return
	if _project == null or _tree == null:
		return
	var local_pos: Vector2 = _tree.get_local_mouse_position()
	var item: TreeItem = _tree.get_item_at_position(local_pos)
	var root: CodaBrowserNode = _get_root_node()
	if root == null:
		return
	var nid: String
	var allow_rd: bool
	if item != null:
		nid = str(item.get_metadata(0))
		item.select(0)
		_tree.scroll_to_item(item)
		var n: CodaBrowserNode = _project.find_node_anywhere(nid)
		allow_rd = n != null and n != root
	else:
		nid = root.id
		allow_rd = false
	var gp := Vector2i(_tree.get_global_mouse_position())
	if _is_events_panel:
		_browser_ctx.open_events_at(gp, nid, allow_rd)
	else:
		_browser_ctx.open_assets_at(gp, nid, allow_rd)
	_tree.accept_event()


# ---------- Quick actions / context menu ----------

func _quick_action_target_folder_id() -> String:
	if _tree == null or _project == null:
		return ""
	var root: CodaBrowserNode = _get_root_node()
	if root == null:
		return ""
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return root.id
	return _ctx_target_folder_id(str(item.get_metadata(0)))


func _ctx_target_folder_id(clicked_node_id: String) -> String:
	if _project == null:
		return ""
	var root: CodaBrowserNode = _get_root_node()
	if root == null:
		return ""
	var node: CodaBrowserNode = _project.find_node_anywhere(clicked_node_id)
	if node == null:
		return root.id
	if node.is_folder():
		return node.id
	var parent: CodaBrowserNode = (
		_project.events_parent_of(node.id)
		if _is_events_panel
		else _project.assets_parent_of(node.id)
	)
	if parent != null:
		return parent.id
	return root.id


func _on_browser_context_action(is_events: bool, action_id: int, clicked_node_id: String) -> void:
	# The menu is dispatched per-tab, so action correctness only depends on this tab's role.
	if is_events != _is_events_panel:
		return
	var folder_id: String = _ctx_target_folder_id(clicked_node_id)
	match action_id:
		BrowserContextMenu.ID_NEW_FOLDER:
			_create_folder(folder_id)
		BrowserContextMenu.ID_NEW_LEAF:
			_create_leaf(folder_id)
		BrowserContextMenu.ID_RENAME:
			_open_rename(clicked_node_id)
		BrowserContextMenu.ID_DELETE:
			_open_delete(clicked_node_id)


# ---------- Rename / delete dialogs ----------

func _open_rename(node_id: String) -> void:
	if _project == null:
		return
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
	if _project != null:
		_project.rename_node(_rename_target_id, _rename_field.text)


func _open_delete(node_id: String) -> void:
	if _project == null:
		return
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
	if _project != null:
		_project.delete_node(_delete_target_id)
