@tool
extends RefCounted
class_name CodaGraphScheduler

## One-shot event graph evaluation: trigger walk to ordered SOUND plan entries.

const NodeData := preload("res://addons/nexus_coda/editor/browser/coda_event_graph_node_data.gd")

## Returns `{ "entries": Array, "event_loop": bool }`.
static func plan(graph: CodaEventGraph, param_values: Dictionary = {}, seed: int = 0) -> Dictionary:
	if graph == null:
		return _empty_plan()
	var trigger: CodaEventGraphNodeData = graph.find_first_of_kind(NodeData.Kind.TRIGGER)
	if trigger == null:
		return _empty_plan()
	var rng := RandomNumberGenerator.new()
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	var out: Array = []
	var event_loop: bool = _walk(graph, trigger, rng, param_values, out)
	return {"entries": out, "event_loop": event_loop}


static func _empty_plan() -> Dictionary:
	return {"entries": [], "event_loop": false}


static func _walk(
	graph: CodaEventGraph,
	node: CodaEventGraphNodeData,
	rng: RandomNumberGenerator,
	param_values: Dictionary,
	out: Array
) -> bool:
	if node == null:
		return false
	var request_loop: bool = false
	match node.kind:
		NodeData.Kind.TRIGGER:
			request_loop = _walk_children(graph, node, rng, param_values, out)
		NodeData.Kind.SEQUENCE:
			request_loop = _walk_children(graph, node, rng, param_values, out)
			if bool(node.properties.get("loop", false)):
				request_loop = true
		NodeData.Kind.RANDOM:
			var children: Array = graph.get_children(node.id)
			if children.is_empty():
				return request_loop
			var chosen: CodaEventGraphNodeData = _pick_weighted(children, node, rng)
			request_loop = _walk(graph, chosen, rng, param_values, out) or request_loop
		NodeData.Kind.SWITCH:
			request_loop = _walk_switch(graph, node, rng, param_values, out) or request_loop
		NodeData.Kind.BLEND:
			request_loop = _walk_blend(graph, node, rng, param_values, out) or request_loop
		NodeData.Kind.SOUND:
			var entry: Dictionary = _sound_plan_entry(node)
			if not entry.is_empty():
				out.append(entry)
	return request_loop


static func _walk_children(
	graph: CodaEventGraph,
	node: CodaEventGraphNodeData,
	rng: RandomNumberGenerator,
	param_values: Dictionary,
	out: Array
) -> bool:
	var request_loop: bool = false
	for child in graph.get_children(node.id):
		request_loop = _walk(graph, child, rng, param_values, out) or request_loop
	return request_loop


static func _sound_plan_entry(node: CodaEventGraphNodeData) -> Dictionary:
	var path: String = String(node.properties.get("audio_path", "")).strip_edges()
	if path.is_empty():
		return {}
	return {
		"audio_path": path,
		"volume_db": float(node.properties.get("volume_db", 0.0)),
		"pitch_scale": float(node.properties.get("pitch_scale", 1.0)),
		"loop": bool(node.properties.get("loop", false)),
		"sound_id": node.id,
		"blend_weight": 1.0,
	}


static func _pick_weighted(
	children: Array,
	random_node: CodaEventGraphNodeData,
	rng: RandomNumberGenerator
) -> CodaEventGraphNodeData:
	var weights_raw: Variant = random_node.properties.get("weights", [])
	var weights: Array = weights_raw if weights_raw is Array else []
	var total: float = 0.0
	var resolved: Array = []
	for i in children.size():
		var w: float = 1.0
		if i < weights.size():
			var v: Variant = weights[i]
			if typeof(v) in [TYPE_FLOAT, TYPE_INT]:
				w = max(0.0, float(v))
		total += w
		resolved.append(w)
	if total <= 0.0:
		return children[rng.randi_range(0, children.size() - 1)] as CodaEventGraphNodeData
	var pick: float = rng.randf() * total
	var acc: float = 0.0
	for i in resolved.size():
		acc += float(resolved[i])
		if pick <= acc:
			return children[i] as CodaEventGraphNodeData
	return children[children.size() - 1] as CodaEventGraphNodeData


static func _walk_switch(
	graph: CodaEventGraph,
	node: CodaEventGraphNodeData,
	rng: RandomNumberGenerator,
	param_values: Dictionary,
	out: Array
) -> bool:
	var children: Array = graph.get_children(node.id)
	if children.is_empty():
		return false
	var param_id: String = String(node.properties.get("parameter_id", ""))
	var idx: int = _param_switch_index(param_values, param_id, children.size())
	return _walk(graph, children[idx], rng, param_values, out)


static func _walk_blend(
	graph: CodaEventGraph,
	node: CodaEventGraphNodeData,
	rng: RandomNumberGenerator,
	param_values: Dictionary,
	out: Array
) -> bool:
	var children: Array = graph.get_children(node.id)
	if children.is_empty():
		return false
	if children.size() == 1:
		return _walk(graph, children[0], rng, param_values, out)
	var param_id: String = String(node.properties.get("parameter_id", ""))
	var t: float = _param_blend_t(param_values, param_id)
	var idx_f: float = t * (children.size() - 1)
	var lo: int = int(floor(idx_f))
	var hi: int = int(ceil(idx_f))
	if lo == hi:
		return _walk(graph, children[lo], rng, param_values, out)
	var frac: float = idx_f - lo
	# Interleave branch steps so SEQUENCE children crossfade in lockstep.
	var lo_plan: Array = []
	var hi_plan: Array = []
	var lo_loop: bool = _walk(graph, children[lo], rng, param_values, lo_plan)
	var hi_loop: bool = _walk(graph, children[hi], rng, param_values, hi_plan)
	var step_count: int = maxi(lo_plan.size(), hi_plan.size())
	for step in step_count:
		if step < lo_plan.size():
			var d: Dictionary = (lo_plan[step] as Dictionary).duplicate()
			d["blend_weight"] = 1.0 - frac
			d["blend_parallel_step"] = step
			out.append(d)
		if step < hi_plan.size():
			var d2: Dictionary = (hi_plan[step] as Dictionary).duplicate()
			d2["blend_weight"] = frac
			d2["blend_parallel_step"] = step
			out.append(d2)
	return lo_loop or hi_loop


static func _param_switch_index(param_values: Dictionary, param_id: String, child_count: int) -> int:
	if param_id.is_empty() or not param_values.has(param_id):
		return 0
	var v: Variant = param_values[param_id]
	var idx: int = int(round(float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else 0.0))
	return clampi(idx, 0, child_count - 1)


static func _param_blend_t(param_values: Dictionary, param_id: String) -> float:
	if param_id.is_empty() or not param_values.has(param_id):
		return 0.0
	var v: Variant = param_values[param_id]
	return clampf(float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else 0.0, 0.0, 1.0)
