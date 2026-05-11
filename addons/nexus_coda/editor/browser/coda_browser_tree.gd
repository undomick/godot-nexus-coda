@tool
class_name CodaBrowserTree
extends Tree

## Tree for Coda browser with drag-and-drop and inline rename (panel wires rename to project).

signal rename_committed(node_id: String, new_name: String)

const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")

var _project = CodaStateScript.new()
var _use_events: bool = true


func configure(project: Variant, use_events: bool) -> void:
	if project != null:
		_project = project
	_use_events = use_events
	# Must stay disabled while idle: permanent drop_mode_flags makes Tree treat every hover as a drop target
	# and starts drag-unfold timers (folders open on mouse-over). Set flags only in _can_drop_data during drag.
	drop_mode_flags = DROP_MODE_DISABLED


func _get_drag_data(at_position: Vector2) -> Variant:
	var item: TreeItem = get_item_at_position(at_position)
	if item == null:
		return null
	var nid: String = str(item.get_metadata(0))
	if _is_roots_id(nid):
		return null
	set_drag_preview(_make_drag_preview(item.get_text(0)))
	var pack: Dictionary = {"coda_browser_drag": true, "node_id": nid}
	if not _use_events:
		var node: CodaBrowserNode = _project.find_node_anywhere(nid)
		if node != null and node.kind == CodaBrowserNode.Kind.ASSET:
			var ap: String = node.asset_source_path.strip_edges()
			if ap.begins_with("res://"):
				pack["coda_asset_source_path"] = ap
	return pack


func _make_drag_preview(label_text: String) -> Control:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_color_override("font_color", get_theme_color("font_color", "Tree"))
	return lbl


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	drop_mode_flags = DROP_MODE_ON_ITEM | DROP_MODE_INBETWEEN
	if data is Dictionary and data.get("coda_browser_drag", false) == true:
		return true
	if (
		not _use_events
		and data is Dictionary
		and _filesystem_drag_files(data as Dictionary).size() > 0
	):
		return true
	drop_mode_flags = DROP_MODE_DISABLED
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	var d: Dictionary = data as Dictionary
	if d.get("coda_browser_drag", false) == true:
		var moving_id: String = str(d.get("node_id", ""))
		if moving_id.is_empty():
			return
		var target_item: TreeItem = get_item_at_position(at_position)
		var section: int = get_drop_section_at_position(at_position)
		var target_id: String = ""
		if target_item != null:
			target_id = str(target_item.get_metadata(0))
		if _use_events:
			_project.move_events_drop(moving_id, target_id, section)
		else:
			_project.move_assets_drop(moving_id, target_id, section)
		return
	if not _use_events:
		var file_list: Array = _filesystem_drag_files(d)
		if file_list.is_empty():
			return
		var target_item_fs: TreeItem = get_item_at_position(at_position)
		var section_fs: int = get_drop_section_at_position(at_position)
		var target_id_fs: String = ""
		if target_item_fs != null:
			target_id_fs = str(target_item_fs.get_metadata(0))
		var folder_id: String = _project.resolve_assets_drop_parent_id(target_id_fs, section_fs)
		if folder_id.is_empty():
			return
		_project.import_assets_from_res_paths(folder_id, file_list)


func _filesystem_drag_files(d: Dictionary) -> Array:
	var t: String = str(d.get("type", ""))
	if not t.is_empty() and t != "files" and t != "files_and_dirs":
		return []
	var raw: Variant = d.get("files", null)
	var out: Array = []
	if raw is PackedStringArray:
		for p in raw as PackedStringArray:
			var s: String = str(p).strip_edges()
			if s.begins_with("res://"):
				out.append(s)
	elif raw is Array:
		for p in raw as Array:
			var s2: String = str(p).strip_edges()
			if s2.begins_with("res://"):
				out.append(s2)
	return out


func _is_roots_id(nid: String) -> bool:
	if _use_events:
		return nid == _project.events_root.id
	return nid == _project.assets_root.id


func begin_rename_selected_if_allowed() -> void:
	var item: TreeItem = get_selected()
	if item == null:
		return
	var nid: String = str(item.get_metadata(0))
	if _is_roots_id(nid):
		return
	item.set_editable(0, true)
	edit_selected(true)


func commit_edited_if_rename(item: TreeItem, column: int) -> void:
	if column != 0 or item == null:
		return
	item.set_editable(0, false)
	var nid: String = str(item.get_metadata(0))
	if _is_roots_id(nid):
		return
	var new_name: String = item.get_text(0)
	rename_committed.emit(nid, new_name)
