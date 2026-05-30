@tool
class_name CodaEventGraph
extends RefCounted

## Audio behaviour graph for a single CodaBrowserNode (event).
## Owns nodes + edges, exposes mutation primitives, validation, and (de)serialization.

signal changed

const CodaEventGraphNodeDataScript := preload(
	"res://addons/nexus_coda/domain/coda_event_graph_node_data.gd"
)
const CodaEventGraphEdgeScript := preload(
	"res://addons/nexus_coda/domain/coda_event_graph_edge.gd"
)

const SCHEMA_VERSION := 1

var nodes: Array[CodaEventGraphNodeData] = []
var edges: Array[CodaEventGraphEdge] = []


func _init() -> void:
	pass


func add_node(node: CodaEventGraphNodeData) -> void:
	if node == null:
		return
	nodes.append(node)
	changed.emit()


func remove_node(node_id: String) -> bool:
	var removed_any: bool = false
	for i in range(nodes.size() - 1, -1, -1):
		if nodes[i].id == node_id:
			nodes.remove_at(i)
			removed_any = true
			break
	if removed_any:
		# Cascade-delete edges touching the removed node.
		for i in range(edges.size() - 1, -1, -1):
			var e: CodaEventGraphEdge = edges[i]
			if e.from_node_id == node_id or e.to_node_id == node_id:
				edges.remove_at(i)
		changed.emit()
	return removed_any


func find_node(node_id: String) -> CodaEventGraphNodeData:
	for n in nodes:
		if n.id == node_id:
			return n
	return null


func node_count_of_kind(kind: int) -> int:
	var c: int = 0
	for n in nodes:
		if int(n.kind) == kind:
			c += 1
	return c


func find_first_of_kind(kind: int) -> CodaEventGraphNodeData:
	for n in nodes:
		if int(n.kind) == kind:
			return n
	return null


func add_edge(from_id: String, to_id: String, from_port: int = 0, to_port: int = 0) -> bool:
	if from_id.is_empty() or to_id.is_empty() or from_id == to_id:
		return false
	var from_node: CodaEventGraphNodeData = find_node(from_id)
	var to_node: CodaEventGraphNodeData = find_node(to_id)
	if from_node == null or to_node == null:
		return false
	if not from_node.has_audio_out():
		return false
	if not to_node.has_audio_in():
		return false
	# Avoid duplicates.
	for e in edges:
		if e.from_node_id == from_id and e.to_node_id == to_id and e.from_port == from_port and e.to_port == to_port:
			return false
	if _would_create_cycle(from_id, to_id):
		return false
	edges.append(CodaEventGraphEdgeScript.new(from_id, to_id, from_port, to_port))
	changed.emit()
	return true


func remove_edge(from_id: String, to_id: String, from_port: int = 0, to_port: int = 0) -> bool:
	for i in range(edges.size() - 1, -1, -1):
		var e: CodaEventGraphEdge = edges[i]
		if e.from_node_id == from_id and e.to_node_id == to_id and e.from_port == from_port and e.to_port == to_port:
			edges.remove_at(i)
			changed.emit()
			return true
	return false


func get_outgoing_edges(node_id: String) -> Array[CodaEventGraphEdge]:
	var out: Array[CodaEventGraphEdge] = []
	for e in edges:
		if e.from_node_id == node_id:
			out.append(e)
	return out


func get_children(node_id: String) -> Array[CodaEventGraphNodeData]:
	var out: Array[CodaEventGraphNodeData] = []
	for e in edges:
		if e.from_node_id == node_id:
			var child: CodaEventGraphNodeData = find_node(e.to_node_id)
			if child != null:
				out.append(child)
	return out


func _would_create_cycle(from_id: String, to_id: String) -> bool:
	# Adding (from → to) is a cycle iff `to` already reaches `from` in the current graph.
	var stack: Array = [to_id]
	var seen: Dictionary = {}
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if cur == from_id:
			return true
		if seen.has(cur):
			continue
		seen[cur] = true
		for e in edges:
			if e.from_node_id == cur and not seen.has(e.to_node_id):
				stack.append(e.to_node_id)
	return false


## Returns the trigger node, ensuring exactly one exists (creates one if missing).
func ensure_trigger_node() -> CodaEventGraphNodeData:
	var trig: CodaEventGraphNodeData = find_first_of_kind(CodaEventGraphNodeDataScript.Kind.TRIGGER)
	if trig != null:
		return trig
	trig = CodaEventGraphNodeDataScript.new(CodaEventGraphNodeDataScript.Kind.TRIGGER)
	trig.graph_position = Vector2(40, 80)
	add_node(trig)
	return trig


## Validation: empty string on success, otherwise an English error message.
func validate() -> String:
	if node_count_of_kind(CodaEventGraphNodeDataScript.Kind.TRIGGER) != 1:
		return "Graph must contain exactly one Trigger node."
	for e in edges:
		var f: CodaEventGraphNodeData = find_node(e.from_node_id)
		var t: CodaEventGraphNodeData = find_node(e.to_node_id)
		if f == null or t == null:
			return "Graph contains a dangling connection."
	return ""


func to_dictionary() -> Dictionary:
	var nodes_arr: Array = []
	for n in nodes:
		nodes_arr.append(n.to_dictionary())
	var edges_arr: Array = []
	for e in edges:
		edges_arr.append(e.to_dictionary())
	return {
		"version": SCHEMA_VERSION,
		"nodes": nodes_arr,
		"edges": edges_arr,
	}


static func from_dictionary(data: Dictionary) -> CodaEventGraph:
	var g: CodaEventGraph = CodaEventGraph.new()
	for n_raw in data.get("nodes", []) as Array:
		if n_raw is Dictionary:
			g.nodes.append(CodaEventGraphNodeDataScript.from_dictionary(n_raw))
	for e_raw in data.get("edges", []) as Array:
		if e_raw is Dictionary:
			g.edges.append(CodaEventGraphEdgeScript.from_dictionary(e_raw))
	return g


## Builds the canonical default graph for a freshly-converted event with N audio paths.
## Layout: TRIGGER → RANDOM → SOUND[0..N-1] (single SOUND if only one path).
static func from_legacy_audio_paths(audio_paths: PackedStringArray) -> CodaEventGraph:
	var g: CodaEventGraph = CodaEventGraph.new()
	var trigger: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.TRIGGER
	)
	trigger.graph_position = Vector2(40, 80)
	g.nodes.append(trigger)
	if audio_paths.size() == 0:
		return g
	if audio_paths.size() == 1:
		var s: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
			CodaEventGraphNodeDataScript.Kind.SOUND
		)
		s.graph_position = Vector2(280, 80)
		s.properties["audio_path"] = String(audio_paths[0])
		g.nodes.append(s)
		g.edges.append(CodaEventGraphEdgeScript.new(trigger.id, s.id))
		return g
	var rnd: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.RANDOM
	)
	rnd.graph_position = Vector2(280, 80)
	g.nodes.append(rnd)
	g.edges.append(CodaEventGraphEdgeScript.new(trigger.id, rnd.id))
	var y: float = 0.0
	for i in audio_paths.size():
		var s2: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
			CodaEventGraphNodeDataScript.Kind.SOUND
		)
		s2.graph_position = Vector2(560, y)
		s2.properties["audio_path"] = String(audio_paths[i])
		g.nodes.append(s2)
		g.edges.append(CodaEventGraphEdgeScript.new(rnd.id, s2.id))
		y += 110.0
	return g
