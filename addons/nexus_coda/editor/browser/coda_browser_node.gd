class_name CodaBrowserNode
extends RefCounted

enum Kind { FOLDER, EVENT, ASSET }

## Authoring model that the runtime should use to schedule this event.
## GRAPH = node-graph (default; Phase 3+); TIMELINE = per-event timeline (Phase C+).
enum AuthoringMode { GRAPH = 0, TIMELINE = 1 }

const CodaEventGraphScript := preload("res://addons/nexus_coda/editor/browser/coda_event_graph.gd")
const CodaModulationScript := preload("res://addons/nexus_coda/editor/browser/coda_modulation.gd")
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_event_timeline.gd"
)
const CodaEventParameterScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_event_parameter.gd"
)

var id: String
var name: String
var kind: Kind = Kind.FOLDER
## Physical source path for imported assets (Kind.ASSET); empty for synthesized entries.
var asset_source_path: String = ""
## Kind.EVENT: authoring schema version for forward compatibility.
## v1: flat event_audio_paths list. v2: event_graph node-graph (Phase 3). v3: event_timeline alt-mode (Phase C).
var event_def_version: int = 3
## Kind.EVENT: which model should the runtime use to schedule this event.
var event_authoring_mode: AuthoringMode = AuthoringMode.GRAPH
## Kind.EVENT: designer-defined parameters (gameplay will set these at runtime later).
var event_parameters: Array[CodaEventParameter] = []
## Kind.EVENT: legacy flat list, kept for backwards-compatible reads. Phase 3 always migrates to event_graph on load.
var event_audio_paths: PackedStringArray = PackedStringArray()
## Kind.EVENT: node graph driving playback (Phase 3+).
var event_graph: CodaEventGraph = null
## Kind.EVENT: alternative timeline-based authoring model (Phase C+). Lazy: created when authoring_mode flips.
var event_timeline: CodaEventTimeline = null
## Kind.EVENT: modulation rules from parameters to graph node properties (Phase 4+).
var event_modulations: Array[CodaModulation] = []
## Kind.EVENT: id of the CodaBus this event routes to. Empty = master.
var event_output_bus_id: String = ""
## Kind.EVENT: parameter name that drives segment switches on the Segments track. Empty = default list.
var event_music_segment_param: String = ""
var children: Array[CodaBrowserNode] = []


func _init(p_name: String = "Node", p_kind: Kind = Kind.FOLDER) -> void:
	id = _generate_id()
	name = p_name
	kind = p_kind
	if kind == Kind.EVENT:
		event_graph = CodaEventGraphScript.new()
		event_graph.ensure_trigger_node()


static func _generate_id() -> String:
	return "%s_%d_%d" % [str(Time.get_ticks_usec()), randi(), randi()]


## Deep-copied events must not reuse ids (banks, runtime, and find_by_id assume uniqueness).
func assign_fresh_ids_for_duplicate() -> void:
	if kind != Kind.EVENT:
		return
	id = _generate_id()
	var param_remap: Dictionary = {}
	for p in event_parameters:
		var old_param_id: String = p.id
		p.id = CodaEventParameterScript._generate_id()
		param_remap[old_param_id] = p.id
	var graph_remap: Dictionary = {}
	if event_graph != null:
		graph_remap = event_graph.regenerate_node_ids()
	if event_timeline != null:
		event_timeline.regenerate_owned_ids()
	for m in event_modulations:
		m.id = CodaModulationScript._generate_id()
		if param_remap.has(m.source_param_id):
			m.source_param_id = param_remap[m.source_param_id]
		if graph_remap.has(m.target_node_id):
			m.target_node_id = graph_remap[m.target_node_id]


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
		d["event_authoring_mode"] = int(event_authoring_mode)
		d["event_parameters"] = event_parameters.map(
			func(p: CodaEventParameter) -> Dictionary: return p.to_dictionary()
		)
		# Persist legacy field for forward-compat tools and as a fallback if the graph is absent on read.
		d["event_audio_paths"] = Array(event_audio_paths)
		if event_graph != null:
			d["event_graph"] = event_graph.to_dictionary()
		if event_timeline != null:
			d["event_timeline"] = event_timeline.to_dictionary()
		d["event_modulations"] = event_modulations.map(
			func(m: CodaModulation) -> Dictionary: return m.to_dictionary()
		)
		d["event_output_bus_id"] = event_output_bus_id
		if not event_music_segment_param.is_empty():
			d["event_music_segment_param"] = event_music_segment_param
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
		var mode_raw: int = int(data.get("event_authoring_mode", AuthoringMode.GRAPH))
		match mode_raw:
			AuthoringMode.GRAPH, AuthoringMode.TIMELINE:
				node.event_authoring_mode = mode_raw as AuthoringMode
			_:
				node.event_authoring_mode = AuthoringMode.GRAPH
		node.event_parameters.clear()
		for pd in data.get("event_parameters", []) as Array:
			if pd is Dictionary:
				node.event_parameters.append(CodaEventParameter.from_dictionary(pd))
		node.event_audio_paths.clear()
		var paths_raw: Variant = data.get("event_audio_paths", [])
		if paths_raw is Array:
			for s in paths_raw:
				node.event_audio_paths.append(str(s))
		var graph_raw: Variant = data.get("event_graph", null)
		if graph_raw is Dictionary:
			node.event_graph = CodaEventGraphScript.from_dictionary(graph_raw)
		else:
			# Migration v1 → v2: synthesize a default graph from the flat audio path list.
			node.event_graph = CodaEventGraphScript.from_legacy_audio_paths(node.event_audio_paths)
		if node.event_graph != null:
			node.event_graph.ensure_trigger_node()
		var timeline_raw: Variant = data.get("event_timeline", null)
		if timeline_raw is Dictionary:
			node.event_timeline = CodaEventTimelineScript.from_dictionary(timeline_raw)
		else:
			node.event_timeline = null
		node.event_modulations.clear()
		for md in data.get("event_modulations", []) as Array:
			if md is Dictionary:
				node.event_modulations.append(CodaModulationScript.from_dictionary(md))
		node.event_output_bus_id = str(data.get("event_output_bus_id", "")).strip_edges()
		node.event_music_segment_param = str(data.get("event_music_segment_param", "")).strip_edges()
		node.event_def_version = max(node.event_def_version, 3)
	for child_data in data.get("children", []) as Array:
		if child_data is Dictionary:
			node.children.append(from_dictionary(child_data))
	return node
