class_name CodaProjectState
extends RefCounted

signal structure_changed

var events_root: CodaBrowserNode
var assets_root: CodaBrowserNode


func _init() -> void:
	clear_to_empty_project()


func clear_to_empty_project() -> void:
	events_root = CodaBrowserNode.new("Events", CodaBrowserNode.Kind.FOLDER)
	assets_root = CodaBrowserNode.new("Assets", CodaBrowserNode.Kind.FOLDER)
	structure_changed.emit()


func find_node_anywhere(target_id: String) -> CodaBrowserNode:
	var e: CodaBrowserNode = events_root.find_by_id(target_id)
	if e != null:
		return e
	return assets_root.find_by_id(target_id)


func parent_of(target_id: String) -> CodaBrowserNode:
	var p: CodaBrowserNode = _parent_recursive(events_root, target_id)
	if p != null:
		return p
	return _parent_recursive(assets_root, target_id)


func _parent_recursive(parent: CodaBrowserNode, target_id: String) -> CodaBrowserNode:
	for child in parent.children:
		if child.id == target_id:
			return parent
		var deeper: CodaBrowserNode = _parent_recursive(child, target_id)
		if deeper != null:
			return deeper
	return null


func events_parent_of(target_id: String) -> CodaBrowserNode:
	return _parent_recursive(events_root, target_id)


func assets_parent_of(target_id: String) -> CodaBrowserNode:
	return _parent_recursive(assets_root, target_id)


func add_events_folder(parent_id: String, folder_name: String = "New Folder") -> CodaBrowserNode:
	var parent: CodaBrowserNode = events_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var folder := CodaBrowserNode.new(folder_name, CodaBrowserNode.Kind.FOLDER)
	parent.insert_child_sorted(folder)
	structure_changed.emit()
	return folder


func add_events_event(parent_id: String, event_name: String = "New Event") -> CodaBrowserNode:
	var parent: CodaBrowserNode = events_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var ev := CodaBrowserNode.new(event_name, CodaBrowserNode.Kind.EVENT)
	parent.insert_child_sorted(ev)
	structure_changed.emit()
	return ev


func add_assets_folder(parent_id: String, folder_name: String = "New Folder") -> CodaBrowserNode:
	var parent: CodaBrowserNode = assets_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var folder := CodaBrowserNode.new(folder_name, CodaBrowserNode.Kind.FOLDER)
	parent.insert_child_sorted(folder)
	structure_changed.emit()
	return folder


func add_asset_placeholder(parent_id: String, asset_name: String = "New Asset") -> CodaBrowserNode:
	var parent: CodaBrowserNode = assets_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var asset := CodaBrowserNode.new(asset_name, CodaBrowserNode.Kind.ASSET)
	parent.insert_child_sorted(asset)
	structure_changed.emit()
	return asset


func rename_node(target_id: String, new_name: String) -> bool:
	var node: CodaBrowserNode = find_node_anywhere(target_id)
	if node == null or node == events_root or node == assets_root:
		return false
	node.name = new_name.strip_edges()
	if node.name.is_empty():
		node.name = "Untitled"
	structure_changed.emit()
	return true


func delete_node(target_id: String) -> bool:
	if events_root.remove_child_by_id(target_id):
		structure_changed.emit()
		return true
	if assets_root.remove_child_by_id(target_id):
		structure_changed.emit()
		return true
	return false


func to_dictionary() -> Dictionary:
	return {
		"version": 1,
		"events": events_root.to_dictionary(),
		"assets": assets_root.to_dictionary(),
	}


func load_from_dictionary(data: Dictionary) -> void:
	var ev: Variant = data.get("events", {})
	if ev is Dictionary:
		events_root = CodaBrowserNode.from_dictionary(ev)
	else:
		events_root = CodaBrowserNode.new("Events", CodaBrowserNode.Kind.FOLDER)
	var as_: Variant = data.get("assets", {})
	if as_ is Dictionary:
		assets_root = CodaBrowserNode.from_dictionary(as_)
	else:
		assets_root = CodaBrowserNode.new("Assets", CodaBrowserNode.Kind.FOLDER)
	structure_changed.emit()
