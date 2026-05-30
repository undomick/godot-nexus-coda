@tool
class_name CodaBusSend
extends RefCounted

## Wet send from a mix bus, event, or track to a return bus (parallel path, not a bus link).

var id: String
## Target return bus id ([CodaBus.id] with [member CodaBus.bus_kind] RETURN).
var target_bus_id: String = ""
## Send amount 0..1 (post-fader unless [member pre_fader]).
var level: float = 0.0
var pre_fader: bool = false
## Optional event parameter id; when set, effective level = level * param_value (0..1).
var parameter_id: String = ""


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "bsnd_%d_%d" % [Time.get_ticks_usec(), randi()]


func clone_keep_id() -> CodaBusSend:
	var s := CodaBusSend.new()
	s.id = id
	s.target_bus_id = target_bus_id
	s.level = level
	s.pre_fader = pre_fader
	s.parameter_id = parameter_id
	return s


func clone_new_id() -> CodaBusSend:
	var s := clone_keep_id()
	s.id = _generate_id()
	return s


func to_dictionary() -> Dictionary:
	var d: Dictionary = {
		"id": id,
		"target_bus_id": target_bus_id,
		"level": level,
		"pre_fader": pre_fader,
	}
	if not parameter_id.is_empty():
		d["parameter_id"] = parameter_id
	return d


static func from_dictionary(data: Dictionary) -> CodaBusSend:
	var s := CodaBusSend.new()
	var stored_id: String = str(data.get("id", "")).strip_edges()
	if not stored_id.is_empty():
		s.id = stored_id
	s.target_bus_id = str(data.get("target_bus_id", "")).strip_edges()
	s.level = clampf(float(data.get("level", 0.0)), 0.0, 1.0)
	s.pre_fader = bool(data.get("pre_fader", false))
	s.parameter_id = str(data.get("parameter_id", "")).strip_edges()
	return s


static func sends_from_array(raw: Array) -> Array[CodaBusSend]:
	var out: Array[CodaBusSend] = []
	for item in raw:
		if item is CodaBusSend:
			out.append(item)
		elif item is Dictionary:
			out.append(CodaBusSend.from_dictionary(item))
	return out


static func sends_to_array(sends: Array[CodaBusSend]) -> Array:
	return sends.map(func(s: CodaBusSend) -> Dictionary: return s.to_dictionary())
