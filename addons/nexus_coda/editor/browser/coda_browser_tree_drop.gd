@tool
class_name CodaBrowserTreeDrop
extends RefCounted

## Shared drag-drop placement for Events and Assets browser trees.


static func parent_of_node(root: CodaBrowserNode, target_id: String) -> CodaBrowserNode:
	for child in root.children:
		if child.id == target_id:
			return root
		var deeper: CodaBrowserNode = parent_of_node(child, target_id)
		if deeper != null:
			return deeper
	return null


static func move_drop(
	tree_root: CodaBrowserNode,
	root_node_id: String,
	moving_id: String,
	target_id: String,
	section: int,
	parent_of: Callable,
	validate_into: Callable,
	visual_list: Callable,
	insert_at_visual: Callable,
	into_folder_index: Callable,
	child_visual_index: Callable
) -> bool:
	if moving_id == root_node_id:
		return false
	var moving_node: CodaBrowserNode = tree_root.find_by_id(moving_id)
	if moving_node == null:
		return false
	if target_id.is_empty():
		if not bool(validate_into.call(moving_node, tree_root)):
			return false
		var taken_root: CodaBrowserNode = tree_root.take_child_by_id(moving_id)
		if taken_root == null:
			return false
		var v_end: int = (visual_list.call(tree_root) as Array).size()
		insert_at_visual.call(tree_root, taken_root, v_end)
		return true
	var target_node: CodaBrowserNode = tree_root.find_by_id(target_id)
	if target_node == null:
		return false
	if moving_id == target_id:
		return false
	var dest_parent_id: String = ""
	var mode: String = ""
	if (section == 0 or section == 2) and target_node.is_folder():
		dest_parent_id = target_node.id
		mode = "into_folder"
	elif section == 0 and not target_node.is_folder():
		var p: CodaBrowserNode = parent_of.call(target_id) as CodaBrowserNode
		if p == null:
			return false
		dest_parent_id = p.id
		mode = "before_child"
	elif section == -1:
		var p2: CodaBrowserNode = parent_of.call(target_id) as CodaBrowserNode
		if p2 == null:
			return false
		dest_parent_id = p2.id
		mode = "before_child"
	elif section == 1:
		var p3: CodaBrowserNode = parent_of.call(target_id) as CodaBrowserNode
		if p3 == null:
			return false
		dest_parent_id = p3.id
		mode = "after_child"
	else:
		return false
	var dest_parent_chk: CodaBrowserNode = tree_root.find_by_id(dest_parent_id)
	if dest_parent_chk == null or not dest_parent_chk.is_folder():
		return false
	if not bool(validate_into.call(moving_node, dest_parent_chk)):
		return false
	var taken: CodaBrowserNode = tree_root.take_child_by_id(moving_id)
	if taken == null:
		return false
	var dest_for_insert: CodaBrowserNode
	if mode == "into_folder":
		dest_for_insert = target_node
	else:
		dest_for_insert = tree_root.find_by_id(dest_parent_id)
		if dest_for_insert == null:
			return false
	var vidx: int = 0
	match mode:
		"into_folder":
			vidx = int(into_folder_index.call(dest_for_insert, taken))
		"before_child":
			vidx = int(child_visual_index.call(dest_for_insert, target_id))
		"after_child":
			vidx = int(child_visual_index.call(dest_for_insert, target_id)) + 1
		_:
			return false
	insert_at_visual.call(dest_for_insert, taken, vidx)
	return true
