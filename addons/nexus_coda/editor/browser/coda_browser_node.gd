class_name CodaBrowserNode
extends RefCounted

enum Kind { FOLDER, EVENT, ASSET }

var id: String
var name: String
var kind: Kind = Kind.FOLDER
## Physical source path for imported assets (Kind.ASSET); empty for synthesized entries.
var asset_source_path: String = ""
## Kind.EVENT: authoring schema version for forward compatibility.
var event_def_version: int = 1
## Kind.EVENT: designer-defined parameters (gameplay will set these at runtime later).
var event_parameters: Array[CodaEventParameter] = []
## Kind.EVENT: res:// paths to AudioStream resources (no banks in MVP).
var event_audio_paths: PackedStringArray = PackedStringArray()
var children: Array[CodaBrowserNode] = []


func _init(p_name: String = "Node", p_kind: Kind = Kind.FOLDER) -> void:
	id = _generate_id()
	name = p_name
	kind = p_kind


static func _generate_id() -> String:
	return "%s_%d_%d" % [str(Time.get_ticks_usec()), randi(), randi()]


func is_folder() -> bool:
	return kind == Kind.FOLDER


func find_by_id(target_id: String) -> CodaBrowserNode:
	if id == target_id:
		return self
	for child in children:
		var found: CodaBrowserNode = child.find_by_id(target_id)
		if found != null:
			return found
	return null


func remove_child_by_id(target_id: String) -> bool:
	for i in range(children.size()):
		if children[i].id == target_id:
			children.remove_at(i)
			return true
		if children[i].remove_child_by_id(target_id):
			return true
	return false


func take_child_by_id(target_id: String) -> CodaBrowserNode:
	for i in range(children.size()):
		if children[i].id == target_id:
			var taken: CodaBrowserNode = children[i]
			children.remove_at(i)
			return taken
		var deeper: CodaBrowserNode = children[i].take_child_by_id(target_id)
		if deeper != null:
			return deeper
	return null


func insert_child_sorted(node: CodaBrowserNode) -> void:
	children.append(node)
	children.sort_custom(func(a: CodaBrowserNode, b: CodaBrowserNode) -> bool:
		if a.is_folder() != b.is_folder():
			return a.is_folder()
		return a.name.nocasecmp_to(b.name) < 0
	)


func to_dictionary() -> Dictionary:
	var d: Dictionary = {
		"id": id,
		"name": name,
		"kind": kind,
		"asset_source_path": asset_source_path,
		"children": children.map(func(c: CodaBrowserNode) -> Dictionary: return c.to_dictionary()),
	}
	if kind == Kind.EVENT:
		d["event_def_version"] = event_def_version
		d["event_parameters"] = event_parameters.map(
			func(p: CodaEventParameter) -> Dictionary: return p.to_dictionary()
		)
		d["event_audio_paths"] = Array(event_audio_paths)
	return d


static func from_dictionary(data: Dictionary) -> CodaBrowserNode:
	var k_raw: int = int(data.get("kind", Kind.FOLDER))
	var k: Kind = Kind.FOLDER
	match k_raw:
		Kind.FOLDER:
			k = Kind.FOLDER
		Kind.EVENT:
			k = Kind.EVENT
		Kind.ASSET:
			k = Kind.ASSET
		_:
			k = Kind.FOLDER
	var node := CodaBrowserNode.new(str(data.get("name", "Node")), k)
	var stored_id: Variant = data.get("id", "")
	if str(stored_id).is_empty():
		node.id = _generate_id()
	else:
		node.id = str(stored_id)
	node.asset_source_path = str(data.get("asset_source_path", ""))
	if k == Kind.EVENT:
		node.event_def_version = int(data.get("event_def_version", 1))
		node.event_parameters.clear()
		for pd in data.get("event_parameters", []) as Array:
			if pd is Dictionary:
				node.event_parameters.append(CodaEventParameter.from_dictionary(pd))
		node.event_audio_paths.clear()
		var paths_raw: Variant = data.get("event_audio_paths", [])
		if paths_raw is Array:
			for s in paths_raw:
				node.event_audio_paths.append(str(s))
	for child_data in data.get("children", []) as Array:
		if child_data is Dictionary:
			node.children.append(from_dictionary(child_data))
	return node
