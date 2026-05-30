@tool
class_name CodaEventGraphNodeData
extends RefCounted

## Single node in the event graph. Kind-specific data lives in `properties` so we can grow
## without changing the on-disk schema constantly.
##
## Nodes never reference each other directly; CodaEventGraphEdge owns connections by id.

enum Kind {
	TRIGGER = 0,
	SEQUENCE = 1,
	RANDOM = 2,
	SWITCH = 3,
	BLEND = 4,
	SOUND = 5,
}

var id: String
var kind: Kind = Kind.TRIGGER
var graph_position: Vector2 = Vector2.ZERO
## Kind-specific bag (e.g. `audio_path` for SOUND, `parameter_id` for SWITCH/BLEND, `weights` for RANDOM).
var properties: Dictionary = {}


func _init(p_kind: Kind = Kind.TRIGGER) -> void:
	id = _generate_id()
	kind = p_kind
	properties = _default_properties_for_kind(kind)


static func _generate_id() -> String:
	return "n_%d_%d" % [Time.get_ticks_usec(), randi()]


static func _default_properties_for_kind(p_kind: Kind) -> Dictionary:
	match p_kind:
		Kind.TRIGGER:
			return {}
		Kind.SEQUENCE:
			return {"loop": false}
		Kind.RANDOM:
			return {"weights": [], "no_immediate_repeat": true}
		Kind.SWITCH:
			return {"parameter_id": "", "branches": []}
		Kind.BLEND:
			return {"parameter_id": "", "stops": []}
		Kind.SOUND:
			return {
				"audio_path": "",
				"volume_db": 0.0,
				"pitch_scale": 1.0,
				"loop": false,
			}
	return {}


static func display_name_for_kind(p_kind: Kind) -> String:
	match p_kind:
		Kind.TRIGGER:
			return "Trigger"
		Kind.SEQUENCE:
			return "Sequence"
		Kind.RANDOM:
			return "Random"
		Kind.SWITCH:
			return "Switch"
		Kind.BLEND:
			return "Blend"
		Kind.SOUND:
			return "Sound"
	return "Node"


## Whether this kind allows outgoing connections (i.e. has a right-side audio slot).
static func has_audio_out_for_kind(p_kind: Kind) -> bool:
	match p_kind:
		Kind.TRIGGER, Kind.SEQUENCE, Kind.RANDOM, Kind.SWITCH, Kind.BLEND:
			return true
	return false


## Whether this kind accepts an incoming audio connection (i.e. has a left-side audio slot).
static func has_audio_in_for_kind(p_kind: Kind) -> bool:
	match p_kind:
		Kind.SEQUENCE, Kind.RANDOM, Kind.SWITCH, Kind.BLEND, Kind.SOUND:
			return true
	return false


func has_audio_in() -> bool:
	return has_audio_in_for_kind(kind)


func has_audio_out() -> bool:
	return has_audio_out_for_kind(kind)


func clone_keep_id() -> CodaEventGraphNodeData:
	var n: CodaEventGraphNodeData = CodaEventGraphNodeData.new(kind)
	n.id = id
	n.kind = kind
	n.graph_position = graph_position
	n.properties = properties.duplicate(true)
	return n


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"kind": int(kind),
		"x": graph_position.x,
		"y": graph_position.y,
		"properties": properties.duplicate(true),
	}


static func from_dictionary(data: Dictionary) -> CodaEventGraphNodeData:
	var k_raw: int = int(data.get("kind", Kind.TRIGGER))
	var k: Kind = Kind.TRIGGER
	match k_raw:
		Kind.TRIGGER, Kind.SEQUENCE, Kind.RANDOM, Kind.SWITCH, Kind.BLEND, Kind.SOUND:
			k = k_raw as Kind
		_:
			k = Kind.TRIGGER
	var n: CodaEventGraphNodeData = CodaEventGraphNodeData.new(k)
	var stored_id: String = str(data.get("id", "")).strip_edges()
	if not stored_id.is_empty():
		n.id = stored_id
	n.graph_position = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	var props_raw: Variant = data.get("properties", {})
	if props_raw is Dictionary:
		# Merge stored properties on top of defaults so newly added defaults are not lost on read.
		var merged: Dictionary = _default_properties_for_kind(k)
		for key in (props_raw as Dictionary).keys():
			merged[key] = (props_raw as Dictionary)[key]
		n.properties = merged
	return n
