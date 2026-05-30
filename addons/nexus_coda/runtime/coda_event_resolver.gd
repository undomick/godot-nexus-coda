@tool
extends RefCounted
class_name CodaEventResolver

## Translates string event paths (e.g. "ui/click" or "events/ui/click") into CodaBrowserNode events.

const CodaBrowserNodeScript := preload("res://addons/nexus_coda/domain/coda_browser_node.gd")

const ROOT_PREFIX := "events/"


static func resolve(project: CodaProject, raw_path: String) -> CodaBrowserNode:
	if project == null or project.events_root == null:
		return null
	var path: String = raw_path.strip_edges()
	if path.is_empty():
		return null
	if path.begins_with(ROOT_PREFIX):
		path = path.substr(ROOT_PREFIX.length())
	var parts: PackedStringArray = path.split("/", false)
	var current: CodaBrowserNode = project.events_root
	for part_raw in parts:
		var part: String = String(part_raw).strip_edges()
		if part.is_empty():
			continue
		var found: CodaBrowserNode = null
		for c in current.children:
			if String(c.name) == part:
				found = c
				break
		if found == null:
			return null
		current = found
	if current == project.events_root:
		return null
	if current.kind != CodaBrowserNode.Kind.EVENT:
		return null
	return current


## Reverse lookup: build "folder/sub/event" from an event id.
static func path_for_event_id(project: CodaProject, event_id: String) -> String:
	if project == null or event_id.is_empty():
		return ""
	var trail: PackedStringArray = []
	if _walk_for_id(project.events_root, event_id, trail):
		return "/".join(trail)
	return ""


static func _walk_for_id(node: CodaBrowserNode, target_id: String, trail: PackedStringArray) -> bool:
	for c in node.children:
		trail.append(c.name)
		if c.id == target_id:
			return true
		if _walk_for_id(c, target_id, trail):
			return true
		trail.remove_at(trail.size() - 1)
	return false
