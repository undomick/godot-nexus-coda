@tool
class_name CodaBrowserTreeModel
extends RefCounted

const BrowserFolderIcons := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_folder_icons.gd"
)


func rebuild_tree(
	tree: Tree,
	root: CodaBrowserNode,
	filter_lower: String,
	is_events_panel: bool
) -> void:
	if tree == null or root == null:
		return
	tree.clear()
	var root_item: TreeItem = tree.create_item()
	root_item.set_metadata(0, root.id)
	for child in root.children:
		build_tree_branch(tree, root_item, child, filter_lower, is_events_panel)


func build_tree_branch(
	tree: Tree,
	parent_item: TreeItem,
	node: CodaBrowserNode,
	filter_lower: String,
	is_events_panel: bool
) -> void:
	if not branch_visible(node, filter_lower):
		return
	var item := tree.create_item(parent_item)
	item.set_text(0, node.name)
	item.set_metadata(0, node.id)
	item.set_editable(0, false)
	if node.is_folder():
		item.set_collapsed(false)
		apply_folder_item_icon(item, node, is_events_panel)
	elif is_events_panel and node.kind == CodaBrowserNode.Kind.EVENT:
		item.set_icon(0, BrowserFolderIcons.get_event_leaf_texture())
	else:
		item.set_icon(0, null)
	for child in node.children:
		build_tree_branch(tree, item, child, filter_lower, is_events_panel)


static func branch_visible(node: CodaBrowserNode, filter_lower: String) -> bool:
	if filter_lower.is_empty():
		return true
	if node.name.to_lower().contains(filter_lower):
		return true
	for c in node.children:
		if branch_visible(c, filter_lower):
			return true
	return false


static func folder_contains_leaf_kind(node: CodaBrowserNode, kind: CodaBrowserNode.Kind) -> bool:
	for c in node.children:
		if c.kind == kind:
			return true
		if c.is_folder() and folder_contains_leaf_kind(c, kind):
			return true
	return false


func apply_folder_item_icon(
	item: TreeItem, folder: CodaBrowserNode, is_events_panel: bool
) -> void:
	var leaf_kind: CodaBrowserNode.Kind = (
		CodaBrowserNode.Kind.EVENT if is_events_panel else CodaBrowserNode.Kind.ASSET
	)
	var filled: bool = folder_contains_leaf_kind(folder, leaf_kind)
	var tex: Texture2D = BrowserFolderIcons.get_folder_texture(item.collapsed, filled)
	item.set_icon(0, tex)


func refresh_folder_item_icon(
	item: TreeItem, project: CodaState, is_events_panel: bool
) -> void:
	if project == null or item == null:
		return
	var nid: String = str(item.get_metadata(0))
	var node: CodaBrowserNode = project.find_node_anywhere(nid)
	if node != null and node.is_folder():
		apply_folder_item_icon(item, node, is_events_panel)


static func find_tree_item_by_node_id(item: TreeItem, target_id: String) -> TreeItem:
	if str(item.get_metadata(0)) == target_id:
		return item
	var child: TreeItem = item.get_first_child()
	while child != null:
		var deeper: TreeItem = find_tree_item_by_node_id(child, target_id)
		if deeper != null:
			return deeper
		child = child.get_next()
	return null


func select_tree_item_by_node_id(tree: Tree, target_id: String) -> void:
	if tree == null or target_id.is_empty():
		return
	var root_item: TreeItem = tree.get_root()
	if root_item == null:
		return
	var found: TreeItem = find_tree_item_by_node_id(root_item, target_id)
	if found != null:
		found.select(0)
		tree.scroll_to_item(found)
