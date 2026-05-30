@tool
class_name CodaVca
extends RefCounted

## Volume control layer over multiple buses (options-menu faders). Does not change routing.

var id: String
var vca_name: String = "VCA"
var volume_db: float = 0.0
var mute: bool = false
## CodaBus ids controlled by this VCA.
var controlled_bus_ids: Array[String] = []


func _init(p_name: String = "VCA") -> void:
	id = _generate_id()
	vca_name = p_name


static func _generate_id() -> String:
	return "vca_%d_%d" % [Time.get_ticks_usec(), randi()]


func clone_keep_id() -> CodaVca:
	var v := CodaVca.new(vca_name)
	v.id = id
	v.volume_db = volume_db
	v.mute = mute
	v.controlled_bus_ids.assign(controlled_bus_ids)
	return v


func clone_new_id() -> CodaVca:
	var v := clone_keep_id()
	v.id = _generate_id()
	return v


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": vca_name,
		"volume_db": volume_db,
		"mute": mute,
		"controlled_bus_ids": controlled_bus_ids.duplicate(),
	}


static func from_dictionary(data: Dictionary) -> CodaVca:
	var v := CodaVca.new(str(data.get("name", "VCA")))
	var stored_id: String = str(data.get("id", "")).strip_edges()
	if not stored_id.is_empty():
		v.id = stored_id
	v.volume_db = float(data.get("volume_db", 0.0))
	v.mute = bool(data.get("mute", false))
	for bid in data.get("controlled_bus_ids", []) as Array:
		var s: String = str(bid).strip_edges()
		if not s.is_empty():
			v.controlled_bus_ids.append(s)
	return v
