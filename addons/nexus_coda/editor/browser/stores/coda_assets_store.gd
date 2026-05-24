class_name CodaAssetsStore
extends RefCounted

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaBrowserTreeDropScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_tree_drop.gd"
)

var _state: CodaState
var _events_store: CodaEventsStore


func _init(state: CodaState, events_store: CodaEventsStore) -> void:
	_state = state
	_events_store = events_store


func assets_parent_of(target_id: String) -> CodaBrowserNode:
	return _parent_recursive(_state.assets_root, target_id)


func add_assets_folder(parent_id: String, folder_name: String = "New Folder") -> CodaBrowserNode:
	var parent: CodaBrowserNode = _state.assets_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var folder := CodaBrowserNode.new(folder_name, CodaBrowserNode.Kind.FOLDER)
	parent.insert_child_sorted(folder)
	_state.structure_changed.emit()
	return folder


func add_asset_placeholder(parent_id: String, asset_name: String = "New Asset") -> CodaBrowserNode:
	var parent: CodaBrowserNode = _state.assets_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var asset := CodaBrowserNode.new(asset_name, CodaBrowserNode.Kind.ASSET)
	parent.insert_child_sorted(asset)
	_state.structure_changed.emit()
	return asset


func resolve_assets_drop_parent_id(target_id: String, section: int) -> String:
	if target_id.is_empty():
		return _state.assets_root.id
	var target_node_a: CodaBrowserNode = _state.assets_root.find_by_id(target_id)
	if target_node_a == null:
		return ""
	if (section == 0 or section == 2) and target_node_a.is_folder():
		return target_node_a.id
	if section == 0 and not target_node_a.is_folder():
		var pa: CodaBrowserNode = assets_parent_of(target_id)
		if pa == null:
			return ""
		return pa.id
	if section == -1:
		var pa2: CodaBrowserNode = assets_parent_of(target_id)
		if pa2 == null:
			return ""
		return pa2.id
	if section == 1:
		var pa3: CodaBrowserNode = assets_parent_of(target_id)
		if pa3 == null:
			return ""
		return pa3.id
	if section == -100:
		if target_node_a.is_folder():
			return target_node_a.id
		var pfb: CodaBrowserNode = assets_parent_of(target_id)
		if pfb != null:
			return pfb.id
		return _state.assets_root.id
	return ""


func import_assets_from_res_paths(target_folder_id: String, files: Variant) -> void:
	var parent: CodaBrowserNode = _state.assets_root.find_by_id(target_folder_id)
	if parent == null or not parent.is_folder():
		return
	var paths: Array[String] = []
	if files is PackedStringArray:
		for x in files as PackedStringArray:
			paths.append(str(x).strip_edges())
	elif files is Array:
		for x in files as Array:
			paths.append(str(x).strip_edges())
	else:
		return
	var changed: bool = false
	for raw in paths:
		if raw.is_empty() or not raw.begins_with("res://"):
			continue
		if _import_one_res_path_under_assets_parent(parent, raw):
			changed = true
	if changed:
		_state.structure_changed.emit()


func move_assets_drop(moving_id: String, target_id: String, section: int) -> bool:
	if CodaBrowserTreeDropScript.move_drop(
		_state.assets_root,
		_state.assets_root.id,
		moving_id,
		target_id,
		section,
		Callable(self, &"assets_parent_of"),
		Callable(_events_store, &"_validate_events_move_into"),
		Callable(_events_store, &"_events_visual_list"),
		Callable(_events_store, &"_events_insert_at_visual_index"),
		Callable(_events_store, &"_events_into_folder_insert_index"),
		Callable(_events_store, &"_events_child_visual_index")
	):
		_state.structure_changed.emit()
		return true
	return false


func _parent_recursive(parent: CodaBrowserNode, target_id: String) -> CodaBrowserNode:
	for child in parent.children:
		if child.id == target_id:
			return parent
		var deeper: CodaBrowserNode = _parent_recursive(child, target_id)
		if deeper != null:
			return deeper
	return null


func _import_one_res_path_under_assets_parent(coda_parent: CodaBrowserNode, res_path: String) -> bool:
	var p: String = res_path.strip_edges()
	if not p.begins_with("res://"):
		return false
	if _res_path_is_importable_directory(p):
		_import_res_folder_mirrored_under(coda_parent, p)
		return true
	if FileAccess.file_exists(p) and _is_importable_audio_res_path(p):
		return _add_res_audio_asset_if_new(coda_parent, p)
	return false


func _res_path_is_importable_directory(p: String) -> bool:
	var normalized: String = p.strip_edges().trim_suffix("/")
	var da: DirAccess = DirAccess.open(normalized)
	return da != null


func _is_importable_audio_res_path(res_file: String) -> bool:
	return _audio_extension_allowed(String(res_file.get_extension()))


func _audio_extension_allowed(ext: String) -> bool:
	match String(ext).to_lower():
		"wav", "ogg", "oga", "mp3", "flac":
			return true
		_:
			return false


func _assets_parent_has_child_with_source(p_folder: CodaBrowserNode, source_path: String) -> bool:
	for c in p_folder.children:
		if c.kind == CodaBrowserNode.Kind.ASSET and c.asset_source_path == source_path:
			return true
	return false


func _add_res_audio_asset_if_new(p_folder: CodaBrowserNode, res_file: String) -> bool:
	if _assets_parent_has_child_with_source(p_folder, res_file):
		NexusCodaLog.debug("browser", "skip duplicate asset import: %s" % res_file)
		return false
	if not _is_importable_audio_res_path(res_file):
		return false
	var display_name: String = res_file.get_file().get_basename()
	var asset := CodaBrowserNode.new(display_name, CodaBrowserNode.Kind.ASSET)
	asset.asset_source_path = res_file
	p_folder.insert_child_sorted(asset)
	return true


func _get_or_create_child_folder(p_parent: CodaBrowserNode, folder_name: String) -> CodaBrowserNode:
	for c in p_parent.children:
		if c.is_folder() and c.name == folder_name:
			return c
	var folder := CodaBrowserNode.new(folder_name, CodaBrowserNode.Kind.FOLDER)
	p_parent.insert_child_sorted(folder)
	return folder


func _import_res_folder_mirrored_under(coda_target: CodaBrowserNode, res_dir: String) -> void:
	var normalized: String = res_dir.strip_edges().trim_suffix("/")
	var base: String = normalized.get_file()
	if base.is_empty():
		return
	var mirror_root: CodaBrowserNode = _get_or_create_child_folder(coda_target, base)
	_import_res_directory_contents_into(normalized, mirror_root)


func _import_res_directory_contents_into(source_res_dir: String, coda_parent: CodaBrowserNode) -> void:
	var da: DirAccess = DirAccess.open(source_res_dir.strip_edges().trim_suffix("/"))
	if da == null:
		return
	for dir_name in da.get_directories():
		if dir_name == "." or dir_name == ".." or dir_name.begins_with("."):
			continue
		var sub_path: String = source_res_dir.strip_edges().trim_suffix("/").path_join(dir_name)
		var sub_folder: CodaBrowserNode = _get_or_create_child_folder(coda_parent, dir_name)
		_import_res_directory_contents_into(sub_path, sub_folder)
	for file_name in da.get_files():
		if file_name.begins_with("."):
			continue
		var fp: String = source_res_dir.strip_edges().trim_suffix("/").path_join(file_name)
		_add_res_audio_asset_if_new(coda_parent, fp)
