class_name CodaState
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


func _events_visual_list(parent: CodaBrowserNode) -> Array[CodaBrowserNode]:
	var out: Array[CodaBrowserNode] = []
	for c in parent.children:
		out.append(c)
	return out


func _events_child_visual_index(parent: CodaBrowserNode, child_id: String) -> int:
	var visual: Array[CodaBrowserNode] = _events_visual_list(parent)
	for i in range(visual.size()):
		if visual[i].id == child_id:
			return i
	return visual.size()


func _events_into_folder_insert_index(dest_parent: CodaBrowserNode, moving: CodaBrowserNode) -> int:
	var visual: Array[CodaBrowserNode] = _events_visual_list(dest_parent)
	if moving.is_folder():
		var idx: int = 0
		for c in visual:
			if c.is_folder():
				idx += 1
			else:
				break
		return idx
	return visual.size()


func _validate_events_move_into(moving: CodaBrowserNode, dest_parent: CodaBrowserNode) -> bool:
	if not moving.is_folder():
		return true
	# Folder cannot be dropped into itself: take_child_by_id removes it first, then re-insert fails.
	if moving.id == dest_parent.id:
		return false
	return moving.find_by_id(dest_parent.id) == null


func _apply_visual_order_folders_first(parent: CodaBrowserNode, visual: Array[CodaBrowserNode]) -> void:
	var folders: Array[CodaBrowserNode] = []
	var rest: Array[CodaBrowserNode] = []
	for c in visual:
		if c.is_folder():
			folders.append(c)
		else:
			rest.append(c)
	parent.children.clear()
	parent.children.append_array(folders)
	parent.children.append_array(rest)


func _events_insert_at_visual_index(parent: CodaBrowserNode, moving: CodaBrowserNode, visual_index: int) -> void:
	var visual: Array[CodaBrowserNode] = _events_visual_list(parent)
	var idx: int = clampi(visual_index, 0, visual.size())
	visual.insert(idx, moving)
	_apply_visual_order_folders_first(parent, visual)


func move_events_drop(moving_id: String, target_id: String, section: int) -> bool:
	if moving_id == events_root.id:
		return false
	var moving_node: CodaBrowserNode = events_root.find_by_id(moving_id)
	if moving_node == null:
		return false
	if target_id.is_empty():
		if not _validate_events_move_into(moving_node, events_root):
			return false
		var taken_root: CodaBrowserNode = events_root.take_child_by_id(moving_id)
		if taken_root == null:
			return false
		var v_end: int = _events_visual_list(events_root).size()
		_events_insert_at_visual_index(events_root, taken_root, v_end)
		structure_changed.emit()
		return true
	var target_node: CodaBrowserNode = events_root.find_by_id(target_id)
	if target_node == null:
		return false
	if moving_id == target_id:
		return false
	var dest_parent_id: String = ""
	var mode: String = ""
	if section == 0 and target_node.is_folder():
		dest_parent_id = target_node.id
		mode = "into_folder"
	elif section == 0 and not target_node.is_folder():
		var p: CodaBrowserNode = events_parent_of(target_id)
		if p == null:
			return false
		dest_parent_id = p.id
		mode = "before_child"
	elif section == -1:
		var p2: CodaBrowserNode = events_parent_of(target_id)
		if p2 == null:
			return false
		dest_parent_id = p2.id
		mode = "before_child"
	elif section == 1:
		var p3: CodaBrowserNode = events_parent_of(target_id)
		if p3 == null:
			return false
		dest_parent_id = p3.id
		mode = "after_child"
	else:
		return false
	var dest_parent_chk: CodaBrowserNode = events_root.find_by_id(dest_parent_id)
	if dest_parent_chk == null or not dest_parent_chk.is_folder():
		return false
	if not _validate_events_move_into(moving_node, dest_parent_chk):
		return false
	var taken: CodaBrowserNode = events_root.take_child_by_id(moving_id)
	if taken == null:
		return false
	var dest_for_insert: CodaBrowserNode
	if mode == "into_folder":
		dest_for_insert = target_node
	else:
		dest_for_insert = events_root.find_by_id(dest_parent_id)
		if dest_for_insert == null:
			return false
	var vidx: int = 0
	match mode:
		"into_folder":
			vidx = _events_into_folder_insert_index(dest_for_insert, taken)
		"before_child":
			vidx = _events_child_visual_index(dest_for_insert, target_id)
		"after_child":
			vidx = _events_child_visual_index(dest_for_insert, target_id) + 1
		_:
			return false
	_events_insert_at_visual_index(dest_for_insert, taken, vidx)
	structure_changed.emit()
	return true


func move_assets_drop(moving_id: String, target_id: String, section: int) -> bool:
	if moving_id == assets_root.id:
		return false
	var moving_node_a: CodaBrowserNode = assets_root.find_by_id(moving_id)
	if moving_node_a == null:
		return false
	if target_id.is_empty():
		if not _validate_events_move_into(moving_node_a, assets_root):
			return false
		var taken_ar: CodaBrowserNode = assets_root.take_child_by_id(moving_id)
		if taken_ar == null:
			return false
		var v_end_a: int = _events_visual_list(assets_root).size()
		_events_insert_at_visual_index(assets_root, taken_ar, v_end_a)
		structure_changed.emit()
		return true
	var target_node_a: CodaBrowserNode = assets_root.find_by_id(target_id)
	if target_node_a == null:
		return false
	if moving_id == target_id:
		return false
	var dest_parent_id_a: String = ""
	var mode_a: String = ""
	if section == 0 and target_node_a.is_folder():
		dest_parent_id_a = target_node_a.id
		mode_a = "into_folder"
	elif section == 0 and not target_node_a.is_folder():
		var pa: CodaBrowserNode = assets_parent_of(target_id)
		if pa == null:
			return false
		dest_parent_id_a = pa.id
		mode_a = "before_child"
	elif section == -1:
		var pa2: CodaBrowserNode = assets_parent_of(target_id)
		if pa2 == null:
			return false
		dest_parent_id_a = pa2.id
		mode_a = "before_child"
	elif section == 1:
		var pa3: CodaBrowserNode = assets_parent_of(target_id)
		if pa3 == null:
			return false
		dest_parent_id_a = pa3.id
		mode_a = "after_child"
	else:
		return false
	var dest_parent_chk_a: CodaBrowserNode = assets_root.find_by_id(dest_parent_id_a)
	if dest_parent_chk_a == null or not dest_parent_chk_a.is_folder():
		return false
	if not _validate_events_move_into(moving_node_a, dest_parent_chk_a):
		return false
	var taken_a: CodaBrowserNode = assets_root.take_child_by_id(moving_id)
	if taken_a == null:
		return false
	var dest_for_insert_a: CodaBrowserNode
	if mode_a == "into_folder":
		dest_for_insert_a = target_node_a
	else:
		dest_for_insert_a = assets_root.find_by_id(dest_parent_id_a)
		if dest_for_insert_a == null:
			return false
	var vidx_a: int = 0
	match mode_a:
		"into_folder":
			vidx_a = _events_into_folder_insert_index(dest_for_insert_a, taken_a)
		"before_child":
			vidx_a = _events_child_visual_index(dest_for_insert_a, target_id)
		"after_child":
			vidx_a = _events_child_visual_index(dest_for_insert_a, target_id) + 1
		_:
			return false
	_events_insert_at_visual_index(dest_for_insert_a, taken_a, vidx_a)
	structure_changed.emit()
	return true


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
