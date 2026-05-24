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
const CodaBrowserTreeModelScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_tree_model.gd"
)

const FOLDER_ICON_DISPLAY_MAX := 16

signal event_authoring_open_requested(node: Variant)
signal event_open_graph_requested(node: Variant)
signal event_open_timeline_requested(node: Variant)

var _is_events_panel: bool = true
var _project: CodaState = null
var _editor_plugin_ref: EditorPlugin = null


func set_editor_plugin_ref(plugin: EditorPlugin) -> void:
	_editor_plugin_ref = plugin

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
var _suppress_tree_selection_emit: bool = false
var _tree_model: CodaBrowserTreeModel = CodaBrowserTreeModelScript.new()


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
	var found: TreeItem = CodaBrowserTreeModel.find_tree_item_by_node_id(root_item, target_id)
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
		_suppress_tree_selection_emit = true
		var root_item: TreeItem = _tree.get_root() if _tree != null else null
		var found: TreeItem = null
		if root_item != null:
			found = CodaBrowserTreeModel.find_tree_item_by_node_id(root_item, prev_sel)
		if found != null:
			found.select(0)
			_tree.scroll_to_item(found)
		else:
			if _tree != null:
				_tree.deselect_all()
			# Deleted/moved nodes are gone from the tree — clear authoring panels so edits
			# are not applied to orphaned CodaBrowserNode refs (lost on save).
			selection_emitted.emit(_selection_category(), null)
		_suppress_tree_selection_emit = false
	# Do not re-emit selection here when the node still exists — structure-only edits
	# (e.g. FX add) would pulse event_selection_changed and knock the Inspector out of
	# timeline track/clip context.


func _rebuild_tree() -> void:
	if _tree == null or _project == null:
		return
	var root: CodaBrowserNode = _get_root_node()
	if root == null:
		_tree.clear()
		return
	_tree_model.rebuild_tree(_tree, root, _filter_text_lower(), _is_events_panel)


func _select_tree_item_by_node_id(target_id: String) -> void:
	_tree_model.select_tree_item_by_node_id(_tree, target_id)


func _refresh_folder_item_icon(item: TreeItem) -> void:
	_tree_model.refresh_folder_item_icon(item, _project, _is_events_panel)


# ---------- Selection routing ----------

func _on_item_selected() -> void:
	if _suppress_tree_selection_emit:
		return
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
	if _tree == null or _project == null:
		return
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var nid: String = str(item.get_metadata(0))
	var node: CodaBrowserNode = _project.find_node_anywhere(nid)
	if node == null:
		return
	if _is_events_panel and node.kind == CodaBrowserNode.Kind.EVENT:
		event_authoring_open_requested.emit(node)
		return
	if _tree != null:
		_tree.begin_rename_selected_if_allowed()


func request_rename_selected() -> bool:
	if _tree == null or _project == null:
		return false
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return false
	var nid: String = str(item.get_metadata(0))
	_open_rename(nid)
	return true


func request_delete_selected() -> bool:
	if _tree == null or _project == null:
		return false
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return false
	var nid: String = str(item.get_metadata(0))
	_open_delete(nid)
	return true


func _selected_event_node() -> CodaBrowserNode:
	if _tree == null or _project == null:
		return null
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return null
	var node: CodaBrowserNode = _project.find_node_anywhere(str(item.get_metadata(0)))
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return null
	return node


func open_selected_in_authoring_view() -> bool:
	var node: CodaBrowserNode = _selected_event_node()
	if node == null:
		return false
	event_authoring_open_requested.emit(node)
	return true


func open_selected_in_graph() -> bool:
	var node: CodaBrowserNode = _selected_event_node()
	if node == null:
		return false
	event_open_graph_requested.emit(node)
	return true


func open_selected_in_timeline() -> bool:
	var node: CodaBrowserNode = _selected_event_node()
	if node == null:
		return false
	event_open_timeline_requested.emit(node)
	return true


func duplicate_selected() -> bool:
	if not _is_events_panel or _project == null:
		return false
	var node: CodaBrowserNode = _selected_event_node()
	if node == null:
		return false
	var copy: CodaBrowserNode = _project.duplicate_events_node(node.id)
	if copy == null:
		return false
	select_by_id(copy.id)
	return true


func reveal_selected_in_filesystem(plugin: EditorPlugin) -> bool:
	if _is_events_panel or _project == null or plugin == null:
		return false
	var item: TreeItem = _tree.get_selected() if _tree != null else null
	if item == null:
		return false
	var node: CodaBrowserNode = _project.find_node_anywhere(str(item.get_metadata(0)))
	if node == null or node.kind != CodaBrowserNode.Kind.ASSET:
		return false
	var path: String = str(node.asset_source_path).strip_edges()
	if path.is_empty() or not path.begins_with("res://"):
		return false
	plugin.get_editor_interface().get_resource_filesystem().update_file(path)
	plugin.get_editor_interface().call_deferred(&"select_file", path)
	return true


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
		BrowserContextMenu.ID_DUPLICATE:
			if _is_events_panel:
				duplicate_selected()
		BrowserContextMenu.ID_OPEN_GRAPH:
			if _is_events_panel:
				open_selected_in_graph()
		BrowserContextMenu.ID_OPEN_TIMELINE:
			if _is_events_panel:
				open_selected_in_timeline()
		BrowserContextMenu.ID_REVEAL_FS:
			if not _is_events_panel:
				reveal_selected_in_filesystem(_editor_plugin_ref)


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
