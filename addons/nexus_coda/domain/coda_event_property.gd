class_name CodaEventProperty
extends RefCounted

## Designer-defined read-only metadata on an event. Gameplay reads these via Coda.get_property().

enum ValueType { FLOAT = 0, INT = 1, BOOL = 2, STRING = 3 }

var id: String
var property_key: String = "Property"
var value_type: ValueType = ValueType.FLOAT
var default_value: Variant = 0.0


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "%s_%d_%d" % [str(Time.get_ticks_usec()), randi(), randi()]


static func is_valid_key(key: String) -> bool:
	var k: String = key.strip_edges()
	if k.is_empty():
		return false
	var re := RegEx.new()
	re.compile("^[a-zA-Z_][a-zA-Z0-9_]*$")
	return re.search(k) != null


func duplicate_property() -> CodaEventProperty:
	var p := CodaEventProperty.new()
	p.id = _generate_id()
	p.property_key = property_key
	p.value_type = value_type
	p.default_value = default_value
	return p


func clone_keep_id() -> CodaEventProperty:
	var p := CodaEventProperty.new()
	p.id = id
	p.property_key = property_key
	p.value_type = value_type
	p.default_value = default_value
	return p


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"key": property_key,
		"value_type": int(value_type),
		"default": default_value,
	}


static func from_dictionary(data: Dictionary) -> CodaEventProperty:
	var p := CodaEventProperty.new()
	var sid: Variant = data.get("id", "")
	if str(sid).is_empty():
		p.id = _generate_id()
	else:
		p.id = str(sid)
	p.property_key = str(data.get("key", "Property"))
	var t: int = int(data.get("value_type", ValueType.FLOAT))
	match t:
		ValueType.FLOAT, ValueType.INT, ValueType.BOOL, ValueType.STRING:
			p.value_type = t as ValueType
		_:
			p.value_type = ValueType.FLOAT
	var def_var: Variant = data.get("default", _default_for_type(p.value_type))
	p.default_value = _coerce_default_for_type(p.value_type, def_var)
	return p


static func _default_for_type(t: ValueType) -> Variant:
	match t:
		ValueType.FLOAT:
			return 0.0
		ValueType.INT:
			return 0
		ValueType.BOOL:
			return false
		ValueType.STRING:
			return ""
	return 0.0


static func _coerce_default_for_type(t: ValueType, raw: Variant) -> Variant:
	match t:
		ValueType.FLOAT:
			return float(raw) if typeof(raw) in [TYPE_FLOAT, TYPE_INT] else 0.0
		ValueType.INT:
			return int(raw) if typeof(raw) in [TYPE_FLOAT, TYPE_INT] else 0
		ValueType.BOOL:
			return bool(raw)
		ValueType.STRING:
			return str(raw)
	return raw


static func suggest_next_property_key(existing: Array[CodaEventProperty]) -> String:
	const BASE := "NewProperty"
	var used: Dictionary = {}
	for q in existing:
		used[str(q.property_key).strip_edges().to_lower()] = true
	if not used.has(BASE.to_lower()):
		return BASE
	var n := 1
	while true:
		var cand: String = "%s%d" % [BASE, n]
		if not used.has(cand.to_lower()):
			return cand
		n += 1
	return BASE


static func validate_list(properties: Array[CodaEventProperty]) -> String:
	var seen: Dictionary = {}
	for p in properties:
		var k: String = p.property_key.strip_edges()
		if k.is_empty():
			return "Property keys cannot be empty."
		if not is_valid_key(k):
			return 'Invalid property key: "%s" (use letters, digits, underscore; must start with letter or _)' % k
		var lookup: String = k.to_lower()
		if seen.has(lookup):
			return 'Duplicate property key: "%s"' % k
		seen[lookup] = true
	return ""


static func resolve_value(properties: Array[CodaEventProperty], key_or_id: String) -> Variant:
	if key_or_id.is_empty():
		return null
	for p in properties:
		if p.id == key_or_id:
			return p.default_value
	var lookup: String = key_or_id.to_lower()
	for p in properties:
		if p.property_key.strip_edges().to_lower() == lookup:
			return p.default_value
	return null
