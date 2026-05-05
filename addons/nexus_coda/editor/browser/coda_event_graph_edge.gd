@tool
class_name CodaEventGraphEdge
extends RefCounted

## Directed edge from the right-side audio slot of `from_node_id` to the left-side audio slot of `to_node_id`.
## In Phase 3 there is exactly one audio slot per side per node, so the port indices are always 0.
## Phase 4+ may introduce multi-port nodes (e.g. labelled Switch branches); the schema already supports that.

var from_node_id: String
var to_node_id: String
var from_port: int = 0
var to_port: int = 0


func _init(p_from: String = "", p_to: String = "", p_from_port: int = 0, p_to_port: int = 0) -> void:
	from_node_id = p_from
	to_node_id = p_to
	from_port = p_from_port
	to_port = p_to_port


func to_dictionary() -> Dictionary:
	return {
		"from": from_node_id,
		"to": to_node_id,
		"from_port": from_port,
		"to_port": to_port,
	}


static func from_dictionary(data: Dictionary) -> CodaEventGraphEdge:
	var e: CodaEventGraphEdge = CodaEventGraphEdge.new()
	e.from_node_id = str(data.get("from", ""))
	e.to_node_id = str(data.get("to", ""))
	e.from_port = int(data.get("from_port", 0))
	e.to_port = int(data.get("to_port", 0))
	return e
