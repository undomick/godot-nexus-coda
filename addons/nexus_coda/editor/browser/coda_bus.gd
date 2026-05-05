@tool
class_name CodaBus
extends RefCounted

## A virtual bus owned by the Coda project. The runtime mirrors these into Godot's
## AudioServer buses (one Godot bus per CodaBus, parented appropriately) so voices route correctly.

var id: String
var bus_name: String = "Bus"
var volume_db: float = 0.0
var mute: bool = false
var solo: bool = false
var bypass: bool = false
## If empty, routing uses the tree parent (same as Godot layout from nesting). Otherwise sends to this bus id (must be a strict ancestor toward Master).
var send_target_id: String = ""
var children: Array[CodaBus] = []


func _init(p_name: String = "Bus") -> void:
	id = _generate_id()
	bus_name = p_name


static func _generate_id() -> String:
	return "b_%d_%d" % [Time.get_ticks_usec(), randi()]


## Walks this bus and all descendants, returning a flat list (root first, depth-first).
func collect_flat(into: Array[CodaBus] = []) -> Array[CodaBus]:
	into.append(self)
	for c in children:
		c.collect_flat(into)
	return into


func find_by_id(target_id: String) -> CodaBus:
	if id == target_id:
		return self
	for c in children:
		var f: CodaBus = c.find_by_id(target_id)
		if f != null:
			return f
	return null


func find_by_name(target_name: String) -> CodaBus:
	if String(bus_name).strip_edges() == target_name.strip_edges():
		return self
	for c in children:
		var f: CodaBus = c.find_by_name(target_name)
		if f != null:
			return f
	return null


func remove_child_by_id(target_id: String) -> bool:
	for i in range(children.size()):
		if children[i].id == target_id:
			children.remove_at(i)
			return true
		if children[i].remove_child_by_id(target_id):
			return true
	return false


func clone_keep_id() -> CodaBus:
	var b: CodaBus = CodaBus.new(bus_name)
	b.id = id
	b.volume_db = volume_db
	b.mute = mute
	b.solo = solo
	b.bypass = bypass
	b.send_target_id = send_target_id
	for c in children:
		b.children.append(c.clone_keep_id())
	return b


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": bus_name,
		"volume_db": volume_db,
		"mute": mute,
		"solo": solo,
		"bypass": bypass,
		"send_target_id": send_target_id,
		"children": children.map(func(c: CodaBus) -> Dictionary: return c.to_dictionary()),
	}


static func from_dictionary(data: Dictionary) -> CodaBus:
	var b: CodaBus = CodaBus.new(str(data.get("name", "Bus")))
	var stored_id: String = str(data.get("id", "")).strip_edges()
	if not stored_id.is_empty():
		b.id = stored_id
	b.volume_db = float(data.get("volume_db", 0.0))
	b.mute = bool(data.get("mute", false))
	b.solo = bool(data.get("solo", false))
	b.bypass = bool(data.get("bypass", false))
	b.send_target_id = str(data.get("send_target_id", ""))
	for c_raw in data.get("children", []) as Array:
		if c_raw is Dictionary:
			b.children.append(CodaBus.from_dictionary(c_raw))
	return b


static func make_default_master() -> CodaBus:
	var master := CodaBus.new("Master")
	var sfx := CodaBus.new("SFX")
	var music := CodaBus.new("Music")
	var ui := CodaBus.new("UI")
	var voice := CodaBus.new("Voice")
	master.children.append(sfx)
	master.children.append(music)
	master.children.append(ui)
	master.children.append(voice)
	return master
