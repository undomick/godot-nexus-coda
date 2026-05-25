class_name CodaEventsStore
extends RefCounted

const CodaBrowserTreeDropScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_tree_drop.gd"
)

var _state: CodaState


func _init(state: CodaState) -> void:
	_state = state


func events_parent_of(target_id: String) -> CodaBrowserNode:
	return _parent_recursive(_state.events_root, target_id)


func add_events_folder(parent_id: String, folder_name: String = "New Folder") -> CodaBrowserNode:
	var parent: CodaBrowserNode = _state.events_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var folder := CodaBrowserNode.new(folder_name, CodaBrowserNode.Kind.FOLDER)
	parent.insert_child_sorted(folder)
	_state.structure_changed.emit()
	return folder


func add_events_event(parent_id: String, event_name: String = "New Event") -> CodaBrowserNode:
	var parent: CodaBrowserNode = _state.events_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var ev := CodaBrowserNode.new(event_name, CodaBrowserNode.Kind.EVENT)
	parent.insert_child_sorted(ev)
	_state.structure_changed.emit()
	return ev


func duplicate_events_node(node_id: String) -> CodaBrowserNode:
	var node: CodaBrowserNode = _state.events_root.find_by_id(node_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return null
	var parent: CodaBrowserNode = events_parent_of(node_id)
	if parent == null:
		return null
	var data: Dictionary = node.to_dictionary()
	var id_capture: Dictionary = _capture_event_duplicate_ids(data)
	_strip_ids_for_event_duplicate(data)
	var copy: CodaBrowserNode = CodaBrowserNode.from_dictionary(data)
	_remap_event_duplicate_references(copy, id_capture)
	copy.name = _suggest_duplicate_name(parent, node.name)
	parent.insert_child_sorted(copy)
	_state.structure_changed.emit()
	return copy


func set_event_authoring_data(
	event_id: String,
	parameters: Array[CodaEventParameter],
	audio_paths: PackedStringArray
) -> String:
	var err_msg: String = CodaEventParameter.validate_list(parameters)
	if not err_msg.is_empty():
		return err_msg
	err_msg = _validate_event_audio_paths(audio_paths)
	if not err_msg.is_empty():
		return err_msg
	var node: CodaBrowserNode = _state.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	node.event_parameters.clear()
	for p in parameters:
		node.event_parameters.append(p.clone_keep_id())
	node.event_audio_paths.clear()
	for p in audio_paths:
		var s: String = str(p).strip_edges()
		if not s.is_empty():
			node.event_audio_paths.append(s)
	_state.structure_changed.emit()
	return ""


func set_event_parameters(event_id: String, parameters: Array[CodaEventParameter]) -> String:
	var err_msg: String = CodaEventParameter.validate_list(parameters)
	if not err_msg.is_empty():
		return err_msg
	var node: CodaBrowserNode = _state.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	node.event_parameters.clear()
	for p in parameters:
		node.event_parameters.append(p.clone_keep_id())
	_state.structure_changed.emit()
	return ""


func notify_event_graph_changed(event_id: String) -> String:
	var node: CodaBrowserNode = _state.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	if node.event_graph == null:
		return "Event has no graph."
	var err: String = node.event_graph.validate()
	_state.structure_changed.emit()
	return err


func set_event_authoring_mode(event_id: String, mode: int) -> String:
	var node: CodaBrowserNode = _state.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	match mode:
		CodaBrowserNode.AuthoringMode.GRAPH:
			node.event_authoring_mode = CodaBrowserNode.AuthoringMode.GRAPH
		CodaBrowserNode.AuthoringMode.TIMELINE:
			node.event_authoring_mode = CodaBrowserNode.AuthoringMode.TIMELINE
			if node.event_timeline == null:
				node.event_timeline = CodaEventTimeline.make_default()
		_:
			return "Unknown authoring mode."
	_state.structure_changed.emit()
	return ""


func notify_event_timeline_changed(event_id: String) -> String:
	var node: CodaBrowserNode = _state.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	if node.event_timeline == null:
		return "Event has no timeline."
	var err: String = node.event_timeline.validate()
	_state.project_dirty.emit()
	return err


func set_event_modulations(event_id: String, modulations: Array[CodaModulation]) -> String:
	var node: CodaBrowserNode = _state.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	node.event_modulations.clear()
	for m in modulations:
		node.event_modulations.append(m.clone_keep_id())
	_state.structure_changed.emit()
	return ""


func move_events_drop(moving_id: String, target_id: String, section: int) -> bool:
	if CodaBrowserTreeDropScript.move_drop(
		_state.events_root,
		_state.events_root.id,
		moving_id,
		target_id,
		section,
		Callable(self, &"events_parent_of"),
		Callable(self, &"_validate_events_move_into"),
		Callable(self, &"_events_visual_list"),
		Callable(self, &"_events_insert_at_visual_index"),
		Callable(self, &"_events_into_folder_insert_index"),
		Callable(self, &"_events_child_visual_index")
	):
		_state.structure_changed.emit()
		return true
	return false


func _parent_recursive(parent: CodaBrowserNode, target_id: String) -> CodaBrowserNode:
	for child in parent.children:
		if child.id == target_id:
			return parent
		var deeper: CodaBrowserNode = _parent_recursive(child, target_id)
		if deeper != null:
			return deeper
	return null


func _capture_event_duplicate_ids(data: Dictionary) -> Dictionary:
	var out := {
		"param_ids": [],
		"graph_node_ids": [],
		"clip_ids": _capture_timeline_clip_ids_from_dict(data.get("event_timeline", null)),
	}
	for pd in data.get("event_parameters", []) as Array:
		if pd is Dictionary:
			(out["param_ids"] as Array).append(str((pd as Dictionary).get("id", "")))
	var graph_raw: Variant = data.get("event_graph", null)
	if graph_raw is Dictionary:
		for n_raw in (graph_raw as Dictionary).get("nodes", []) as Array:
			if n_raw is Dictionary:
				(out["graph_node_ids"] as Array).append(str((n_raw as Dictionary).get("id", "")))
	return out


func _strip_ids_for_event_duplicate(data: Dictionary) -> void:
	data.erase("id")
	for pd in data.get("event_parameters", []) as Array:
		if pd is Dictionary:
			(pd as Dictionary).erase("id")
	for md in data.get("event_modulations", []) as Array:
		if md is Dictionary:
			(md as Dictionary).erase("id")
	var graph_raw: Variant = data.get("event_graph", null)
	if graph_raw is Dictionary:
		var graph_d: Dictionary = graph_raw
		for n_raw in graph_d.get("nodes", []) as Array:
			if n_raw is Dictionary:
				(n_raw as Dictionary).erase("id")
	var timeline_raw: Variant = data.get("event_timeline", null)
	if timeline_raw is Dictionary:
		_strip_ids_event_timeline_dict(timeline_raw as Dictionary)


func _strip_ids_event_timeline_dict(timeline_d: Dictionary) -> void:
	for tr_raw in timeline_d.get("tracks", []) as Array:
		if not tr_raw is Dictionary:
			continue
		var tr_d: Dictionary = tr_raw
		tr_d.erase("id")
		for fx_raw in tr_d.get("effects", []) as Array:
			if fx_raw is Dictionary:
				(fx_raw as Dictionary).erase("id")
		for c_raw in tr_d.get("clips", []) as Array:
			if not c_raw is Dictionary:
				continue
			var c_d: Dictionary = c_raw
			c_d.erase("id")
			for cfx_raw in c_d.get("effects", []) as Array:
				if cfx_raw is Dictionary:
					(cfx_raw as Dictionary).erase("id")
	for m_raw in timeline_d.get("markers", []) as Array:
		if m_raw is Dictionary:
			(m_raw as Dictionary).erase("id")


func _remap_event_duplicate_references(copy: CodaBrowserNode, id_capture: Dictionary) -> void:
	var param_remap: Dictionary = {}
	var old_param_ids: Array = id_capture.get("param_ids", []) as Array
	for i in range(copy.event_parameters.size()):
		if i < old_param_ids.size():
			var old_id: String = str(old_param_ids[i])
			if not old_id.is_empty():
				param_remap[old_id] = copy.event_parameters[i].id
	var node_remap: Dictionary = {}
	if copy.event_graph != null:
		var old_node_ids: Array = id_capture.get("graph_node_ids", []) as Array
		for i in range(copy.event_graph.nodes.size()):
			if i < old_node_ids.size():
				var old_nid: String = str(old_node_ids[i])
				if not old_nid.is_empty():
					node_remap[old_nid] = copy.event_graph.nodes[i].id
		for e in copy.event_graph.edges:
			if node_remap.has(e.from_node_id):
				e.from_node_id = node_remap[e.from_node_id]
			if node_remap.has(e.to_node_id):
				e.to_node_id = node_remap[e.to_node_id]
	var clip_remap: Dictionary = {}
	if copy.event_timeline != null:
		var old_clip_ids: Array = id_capture.get("clip_ids", []) as Array
		var new_clip_ids: Array = _collect_timeline_clip_ids(copy.event_timeline)
		for i in range(mini(old_clip_ids.size(), new_clip_ids.size())):
			var old_cid: String = str(old_clip_ids[i])
			if not old_cid.is_empty():
				clip_remap[old_cid] = str(new_clip_ids[i])
	for m in copy.event_modulations:
		if param_remap.has(m.source_param_id):
			m.source_param_id = param_remap[m.source_param_id]
		if node_remap.has(m.target_node_id):
			m.target_node_id = node_remap[m.target_node_id]
		elif clip_remap.has(m.target_node_id):
			m.target_node_id = clip_remap[m.target_node_id]
	if copy.event_timeline != null:
		for mk in copy.event_timeline.markers:
			if clip_remap.has(mk.target_segment_id):
				mk.target_segment_id = clip_remap[mk.target_segment_id]
		_refresh_timeline_effect_ids(copy.event_timeline)


func _capture_timeline_clip_ids_from_dict(timeline_raw: Variant) -> Array:
	var ids: Array = []
	if not timeline_raw is Dictionary:
		return ids
	for tr_raw in (timeline_raw as Dictionary).get("tracks", []) as Array:
		if not tr_raw is Dictionary:
			continue
		for c_raw in (tr_raw as Dictionary).get("clips", []) as Array:
			if c_raw is Dictionary:
				ids.append(str((c_raw as Dictionary).get("id", "")))
	return ids


func _collect_timeline_clip_ids(timeline: CodaEventTimeline) -> Array:
	var ids: Array = []
	for tr in timeline.tracks:
		for clip in tr.clips:
			ids.append(clip.id)
	return ids


func _refresh_timeline_effect_ids(timeline: CodaEventTimeline) -> void:
	for tr in timeline.tracks:
		for i in range(tr.effects.size()):
			tr.effects[i] = tr.effects[i].clone_new_id()
		for clip in tr.clips:
			for j in range(clip.effects.size()):
				clip.effects[j] = clip.effects[j].clone_new_id()


func _suggest_duplicate_name(parent: CodaBrowserNode, base_name: String) -> String:
	var stem: String = base_name.strip_edges()
	if not stem.ends_with(" Copy"):
		stem = "%s Copy" % stem
	var candidate: String = stem
	var n: int = 2
	while _parent_has_child_name(parent, candidate):
		candidate = "%s (%d)" % [stem, n]
		n += 1
	return candidate


func _parent_has_child_name(parent: CodaBrowserNode, child_name: String) -> bool:
	for c in parent.children:
		if c.name == child_name:
			return true
	return false


func _validate_event_audio_paths(paths: PackedStringArray) -> String:
	for p in paths:
		var s: String = str(p).strip_edges()
		if s.is_empty():
			continue
		if not s.begins_with("res://"):
			return 'Audio paths must start with res:// ("%s")' % s
	return ""


func _events_visual_list(parent: CodaBrowserNode) -> Array[CodaBrowserNode]:
	var out: Array[CodaBrowserNode] = []
	for c in parent.children:
		out.append(c)
	return out


func _events_child_visual_index(parent: CodaBrowserNode, child_id: String) -> int:
	var visual: Array[CodaBrowserNode] = _events_visual_list(parent)
	for i in range(visual.size()):
		if visual[i].id == child_id:
			return i
	return visual.size()


func _events_into_folder_insert_index(dest_parent: CodaBrowserNode, moving: CodaBrowserNode) -> int:
	var visual: Array[CodaBrowserNode] = _events_visual_list(dest_parent)
	if moving.is_folder():
		var idx: int = 0
		for c in visual:
			if c.is_folder():
				idx += 1
			else:
				break
		return idx
	return visual.size()


func _validate_events_move_into(moving: CodaBrowserNode, dest_parent: CodaBrowserNode) -> bool:
	if not moving.is_folder():
		return true
	if moving.id == dest_parent.id:
		return false
	return moving.find_by_id(dest_parent.id) == null


func _apply_visual_order_folders_first(parent: CodaBrowserNode, visual: Array[CodaBrowserNode]) -> void:
	var folders: Array[CodaBrowserNode] = []
	var rest: Array[CodaBrowserNode] = []
	for c in visual:
		if c.is_folder():
			folders.append(c)
		else:
			rest.append(c)
	parent.children.clear()
	parent.children.append_array(folders)
	parent.children.append_array(rest)


func _events_insert_at_visual_index(parent: CodaBrowserNode, moving: CodaBrowserNode, visual_index: int) -> void:
	var visual: Array[CodaBrowserNode] = _events_visual_list(parent)
	var idx: int = clampi(visual_index, 0, visual.size())
	visual.insert(idx, moving)
	_apply_visual_order_folders_first(parent, visual)
