class_name CodaEventParameter
extends RefCounted

## MVP event authoring uses GDScript-only parameter descriptors (no C++ core yet).
## Optional later: migrate schema to GDExtension for shared runtime/editor logic.

enum ParamType { FLOAT = 0, INT = 1, BOOL = 2 }

var id: String
var param_name: String = "Parameter"
var param_type: ParamType = ParamType.FLOAT
var default_value: Variant = 0.0
## Optional bounds for float/int (null = unset).
var min_value: Variant = null
var max_value: Variant = null
var unit_hint: String = ""


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "%s_%d_%d" % [str(Time.get_ticks_usec()), randi(), randi()]


func duplicate_parameter() -> CodaEventParameter:
	var p := CodaEventParameter.new()
	p.id = _generate_id()
	p.param_name = param_name
	p.param_type = param_type
	p.default_value = default_value
	p.min_value = min_value
	p.max_value = max_value
	p.unit_hint = unit_hint
	return p


func clone_keep_id() -> CodaEventParameter:
	var p := CodaEventParameter.new()
	p.id = id
	p.param_name = param_name
	p.param_type = param_type
	p.default_value = default_value
	p.min_value = min_value
	p.max_value = max_value
	p.unit_hint = unit_hint
	return p


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": param_name,
		"param_type": int(param_type),
		"default": default_value,
		"min": min_value,
		"max": max_value,
		"unit": unit_hint,
	}


static func from_dictionary(data: Dictionary) -> CodaEventParameter:
	var p := CodaEventParameter.new()
	var sid: Variant = data.get("id", "")
	if str(sid).is_empty():
		p.id = _generate_id()
	else:
		p.id = str(sid)
	p.param_name = str(data.get("name", "Parameter"))
	var t: int = int(data.get("param_type", ParamType.FLOAT))
	match t:
		ParamType.FLOAT, ParamType.INT, ParamType.BOOL:
			p.param_type = t as ParamType
		_:
			p.param_type = ParamType.FLOAT
	p.default_value = data.get("default", _default_for_type(p.param_type))
	p.min_value = data.get("min", null)
	p.max_value = data.get("max", null)
	p.unit_hint = str(data.get("unit", ""))
	return p


static func _default_for_type(t: ParamType) -> Variant:
	match t:
		ParamType.FLOAT:
			return 0.0
		ParamType.INT:
			return 0
		ParamType.BOOL:
			return false
	return null


static func validate_list(parameters: Array[CodaEventParameter]) -> String:
	var seen: Dictionary = {}
	for p in parameters:
		var n: String = p.param_name.strip_edges()
		if n.is_empty():
			return "Parameter names cannot be empty."
		var key: String = n.to_lower()
		if seen.has(key):
			return 'Duplicate parameter name: "%s"' % n
		seen[key] = true
	return ""
