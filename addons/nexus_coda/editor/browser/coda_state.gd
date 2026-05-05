class_name CodaState
extends RefCounted

signal structure_changed
## Bus volume/mute/bypass and other non-structural edits; marks unsaved state without forcing full UI rebuilds.
signal project_dirty

var events_root: CodaBrowserNode
var assets_root: CodaBrowserNode
var bus_root: CodaBus
var snapshots: Array[CodaSnapshot] = []
var banks: Array[CodaBank] = []

## Project-level appearance metadata. Phase 7: editor window applies these on load.
## `theme_mode` is "dark" or "light"; `accent_color` overrides the default Coda accent.
var theme_mode: String = "dark"
var accent_color: Color = Color(0.42, 0.74, 1.00, 1.0)


func _init() -> void:
	clear_to_empty_project()


func clear_to_empty_project() -> void:
	events_root = CodaBrowserNode.new("Events", CodaBrowserNode.Kind.FOLDER)
	assets_root = CodaBrowserNode.new("Assets", CodaBrowserNode.Kind.FOLDER)
	bus_root = CodaBus.make_default_master()
	snapshots.clear()
	banks.clear()
	theme_mode = "dark"
	accent_color = Color(0.42, 0.74, 1.00, 1.0)
	structure_changed.emit()


func set_theme_appearance(p_theme_mode: String, p_accent_color: Color) -> void:
	var normalized: String = p_theme_mode.strip_edges().to_lower()
	if normalized != "light" and normalized != "dark":
		normalized = "dark"
	theme_mode = normalized
	accent_color = p_accent_color
	structure_changed.emit()


func find_node_anywhere(target_id: String) -> CodaBrowserNode:
	var e: CodaBrowserNode = events_root.find_by_id(target_id)
	if e != null:
		return e
	return assets_root.find_by_id(target_id)


func parent_of(target_id: String) -> CodaBrowserNode:
	var p: CodaBrowserNode = _parent_recursive(events_root, target_id)
	if p != null:
		return p
	return _parent_recursive(assets_root, target_id)


func _parent_recursive(parent: CodaBrowserNode, target_id: String) -> CodaBrowserNode:
	for child in parent.children:
		if child.id == target_id:
			return parent
		var deeper: CodaBrowserNode = _parent_recursive(child, target_id)
		if deeper != null:
			return deeper
	return null


func events_parent_of(target_id: String) -> CodaBrowserNode:
	return _parent_recursive(events_root, target_id)


func assets_parent_of(target_id: String) -> CodaBrowserNode:
	return _parent_recursive(assets_root, target_id)


func add_events_folder(parent_id: String, folder_name: String = "New Folder") -> CodaBrowserNode:
	var parent: CodaBrowserNode = events_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var folder := CodaBrowserNode.new(folder_name, CodaBrowserNode.Kind.FOLDER)
	parent.insert_child_sorted(folder)
	structure_changed.emit()
	return folder


func add_events_event(parent_id: String, event_name: String = "New Event") -> CodaBrowserNode:
	var parent: CodaBrowserNode = events_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var ev := CodaBrowserNode.new(event_name, CodaBrowserNode.Kind.EVENT)
	parent.insert_child_sorted(ev)
	structure_changed.emit()
	return ev


func add_assets_folder(parent_id: String, folder_name: String = "New Folder") -> CodaBrowserNode:
	var parent: CodaBrowserNode = assets_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var folder := CodaBrowserNode.new(folder_name, CodaBrowserNode.Kind.FOLDER)
	parent.insert_child_sorted(folder)
	structure_changed.emit()
	return folder


func add_asset_placeholder(parent_id: String, asset_name: String = "New Asset") -> CodaBrowserNode:
	var parent: CodaBrowserNode = assets_root.find_by_id(parent_id)
	if parent == null or not parent.is_folder():
		return null
	var asset := CodaBrowserNode.new(asset_name, CodaBrowserNode.Kind.ASSET)
	parent.insert_child_sorted(asset)
	structure_changed.emit()
	return asset


## Returns empty string on success, otherwise an English error message for the UI.
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
	var node: CodaBrowserNode = events_root.find_by_id(event_id)
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
	structure_changed.emit()
	return ""


## Replaces the parameter list of an event without touching the graph. Phase 4 will use this from the inspector.
func set_event_parameters(event_id: String, parameters: Array[CodaEventParameter]) -> String:
	var err_msg: String = CodaEventParameter.validate_list(parameters)
	if not err_msg.is_empty():
		return err_msg
	var node: CodaBrowserNode = events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	node.event_parameters.clear()
	for p in parameters:
		node.event_parameters.append(p.clone_keep_id())
	structure_changed.emit()
	return ""


## Notifies the project that the event graph for `event_id` has been mutated externally.
## Returns empty string on success, otherwise an English error message.
func notify_event_graph_changed(event_id: String) -> String:
	var node: CodaBrowserNode = events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	if node.event_graph == null:
		return "Event has no graph."
	var err: String = node.event_graph.validate()
	structure_changed.emit()
	return err


## Replaces the modulation list for an event.
func set_event_modulations(event_id: String, modulations: Array[CodaModulation]) -> String:
	var node: CodaBrowserNode = events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return "Not an event in the events tree."
	node.event_modulations.clear()
	for m in modulations:
		node.event_modulations.append(m.clone_keep_id())
	structure_changed.emit()
	return ""


func _validate_event_audio_paths(paths: PackedStringArray) -> String:
	for p in paths:
		var s: String = str(p).strip_edges()
		if s.is_empty():
			continue
		if not s.begins_with("res://"):
			return 'Audio paths must start with res:// ("%s")' % s
	return ""


func rename_node(target_id: String, new_name: String) -> bool:
	var node: CodaBrowserNode = find_node_anywhere(target_id)
	if node == null or node == events_root or node == assets_root:
		return false
	node.name = new_name.strip_edges()
	if node.name.is_empty():
		node.name = "Untitled"
	structure_changed.emit()
	return true


func delete_node(target_id: String) -> bool:
	if events_root.remove_child_by_id(target_id):
		structure_changed.emit()
		return true
	if assets_root.remove_child_by_id(target_id):
		structure_changed.emit()
		return true
	return false


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
	# Folder cannot be dropped into itself: take_child_by_id removes it first, then re-insert fails.
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


func move_events_drop(moving_id: String, target_id: String, section: int) -> bool:
	if moving_id == events_root.id:
		return false
	var moving_node: CodaBrowserNode = events_root.find_by_id(moving_id)
	if moving_node == null:
		return false
	if target_id.is_empty():
		if not _validate_events_move_into(moving_node, events_root):
			return false
		var taken_root: CodaBrowserNode = events_root.take_child_by_id(moving_id)
		if taken_root == null:
			return false
		var v_end: int = _events_visual_list(events_root).size()
		_events_insert_at_visual_index(events_root, taken_root, v_end)
		structure_changed.emit()
		return true
	var target_node: CodaBrowserNode = events_root.find_by_id(target_id)
	if target_node == null:
		return false
	if moving_id == target_id:
		return false
	var dest_parent_id: String = ""
	var mode: String = ""
	if section == 0 and target_node.is_folder():
		dest_parent_id = target_node.id
		mode = "into_folder"
	elif section == 0 and not target_node.is_folder():
		var p: CodaBrowserNode = events_parent_of(target_id)
		if p == null:
			return false
		dest_parent_id = p.id
		mode = "before_child"
	elif section == -1:
		var p2: CodaBrowserNode = events_parent_of(target_id)
		if p2 == null:
			return false
		dest_parent_id = p2.id
		mode = "before_child"
	elif section == 1:
		var p3: CodaBrowserNode = events_parent_of(target_id)
		if p3 == null:
			return false
		dest_parent_id = p3.id
		mode = "after_child"
	else:
		return false
	var dest_parent_chk: CodaBrowserNode = events_root.find_by_id(dest_parent_id)
	if dest_parent_chk == null or not dest_parent_chk.is_folder():
		return false
	if not _validate_events_move_into(moving_node, dest_parent_chk):
		return false
	var taken: CodaBrowserNode = events_root.take_child_by_id(moving_id)
	if taken == null:
		return false
	var dest_for_insert: CodaBrowserNode
	if mode == "into_folder":
		dest_for_insert = target_node
	else:
		dest_for_insert = events_root.find_by_id(dest_parent_id)
		if dest_for_insert == null:
			return false
	var vidx: int = 0
	match mode:
		"into_folder":
			vidx = _events_into_folder_insert_index(dest_for_insert, taken)
		"before_child":
			vidx = _events_child_visual_index(dest_for_insert, target_id)
		"after_child":
			vidx = _events_child_visual_index(dest_for_insert, target_id) + 1
		_:
			return false
	_events_insert_at_visual_index(dest_for_insert, taken, vidx)
	structure_changed.emit()
	return true


func move_assets_drop(moving_id: String, target_id: String, section: int) -> bool:
	if moving_id == assets_root.id:
		return false
	var moving_node_a: CodaBrowserNode = assets_root.find_by_id(moving_id)
	if moving_node_a == null:
		return false
	if target_id.is_empty():
		if not _validate_events_move_into(moving_node_a, assets_root):
			return false
		var taken_ar: CodaBrowserNode = assets_root.take_child_by_id(moving_id)
		if taken_ar == null:
			return false
		var v_end_a: int = _events_visual_list(assets_root).size()
		_events_insert_at_visual_index(assets_root, taken_ar, v_end_a)
		structure_changed.emit()
		return true
	var target_node_a: CodaBrowserNode = assets_root.find_by_id(target_id)
	if target_node_a == null:
		return false
	if moving_id == target_id:
		return false
	var dest_parent_id_a: String = ""
	var mode_a: String = ""
	if section == 0 and target_node_a.is_folder():
		dest_parent_id_a = target_node_a.id
		mode_a = "into_folder"
	elif section == 0 and not target_node_a.is_folder():
		var pa: CodaBrowserNode = assets_parent_of(target_id)
		if pa == null:
			return false
		dest_parent_id_a = pa.id
		mode_a = "before_child"
	elif section == -1:
		var pa2: CodaBrowserNode = assets_parent_of(target_id)
		if pa2 == null:
			return false
		dest_parent_id_a = pa2.id
		mode_a = "before_child"
	elif section == 1:
		var pa3: CodaBrowserNode = assets_parent_of(target_id)
		if pa3 == null:
			return false
		dest_parent_id_a = pa3.id
		mode_a = "after_child"
	else:
		return false
	var dest_parent_chk_a: CodaBrowserNode = assets_root.find_by_id(dest_parent_id_a)
	if dest_parent_chk_a == null or not dest_parent_chk_a.is_folder():
		return false
	if not _validate_events_move_into(moving_node_a, dest_parent_chk_a):
		return false
	var taken_a: CodaBrowserNode = assets_root.take_child_by_id(moving_id)
	if taken_a == null:
		return false
	var dest_for_insert_a: CodaBrowserNode
	if mode_a == "into_folder":
		dest_for_insert_a = target_node_a
	else:
		dest_for_insert_a = assets_root.find_by_id(dest_parent_id_a)
		if dest_for_insert_a == null:
			return false
	var vidx_a: int = 0
	match mode_a:
		"into_folder":
			vidx_a = _events_into_folder_insert_index(dest_for_insert_a, taken_a)
		"before_child":
			vidx_a = _events_child_visual_index(dest_for_insert_a, target_id)
		"after_child":
			vidx_a = _events_child_visual_index(dest_for_insert_a, target_id) + 1
		_:
			return false
	_events_insert_at_visual_index(dest_for_insert_a, taken_a, vidx_a)
	structure_changed.emit()
	return true


## Bus mutation API.
## Tree/layout changes emit `structure_changed`; parameter-only edits emit `project_dirty` to avoid
## synchronous mixer strip rebuilds during control signal handlers (LineEdit, etc.).
func update_bus_volume(bus_id: String, volume_db: float) -> void:
	var b: CodaBus = bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.volume_db = volume_db
	project_dirty.emit()


func update_bus_mute(bus_id: String, mute: bool) -> void:
	var b: CodaBus = bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.mute = mute
	project_dirty.emit()


func update_bus_solo(bus_id: String, solo: bool) -> void:
	var b: CodaBus = bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.solo = solo
	structure_changed.emit()


func update_bus_bypass(bus_id: String, bypass: bool) -> void:
	var b: CodaBus = bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.bypass = bypass
	project_dirty.emit()


func update_bus_send_target(bus_id: String, target_bus_id: String) -> void:
	var b: CodaBus = bus_root.find_by_id(bus_id)
	if b == null or b.id == bus_root.id:
		return
	var tid: String = String(target_bus_id).strip_edges()
	if not tid.is_empty():
		var t: CodaBus = bus_root.find_by_id(tid)
		if t == null:
			return
		if not _bus_is_strict_ancestor(tid, bus_id):
			return
	b.send_target_id = tid
	structure_changed.emit()


## Reparent/move `drag_bus_id` so it appears before `before_bus_id` in depth-first order (same parent chain rules as the mixer strips).
func move_bus_before_in_tree(drag_bus_id: String, before_bus_id: String) -> bool:
	if bus_root == null or drag_bus_id == bus_root.id:
		return false
	if before_bus_id == bus_root.id:
		return false
	var drag_b: CodaBus = bus_root.find_by_id(drag_bus_id)
	var before_b: CodaBus = bus_root.find_by_id(before_bus_id)
	if drag_b == null or before_b == null:
		return false
	if _bus_subtree_contains(drag_b, before_bus_id):
		return false
	var p_drag: CodaBus = parent_bus_of(drag_bus_id)
	if p_drag == null:
		return false
	var i_drag: int = p_drag.children.find(drag_b)
	if i_drag < 0:
		return false
	var p_before: CodaBus = parent_bus_of(before_bus_id)
	if p_before == null:
		return false
	var i_before: int = p_before.children.find(before_b)
	if i_before < 0:
		return false
	p_drag.children.remove_at(i_drag)
	if p_drag == p_before and i_drag < i_before:
		i_before -= 1
	p_before.children.insert(i_before, drag_b)
	structure_changed.emit()
	return true


## Place `drag_bus_id` immediately after `after_bus_id` among siblings.
func move_bus_after_in_tree(drag_bus_id: String, after_bus_id: String) -> bool:
	if bus_root == null or drag_bus_id == bus_root.id:
		return false
	var drag_b: CodaBus = bus_root.find_by_id(drag_bus_id)
	var after_b: CodaBus = bus_root.find_by_id(after_bus_id)
	if drag_b == null or after_b == null:
		return false
	if _bus_subtree_contains(drag_b, after_bus_id):
		return false
	var p_drag: CodaBus = parent_bus_of(drag_bus_id)
	if p_drag == null:
		return false
	var i_drag: int = p_drag.children.find(drag_b)
	if i_drag < 0:
		return false
	var p_after: CodaBus = parent_bus_of(after_bus_id)
	if p_after == null:
		return false
	var i_after: int = p_after.children.find(after_b)
	if i_after < 0:
		return false
	p_drag.children.remove_at(i_drag)
	if p_drag == p_after and i_drag <= i_after:
		i_after -= 1
	p_after.children.insert(i_after + 1, drag_b)
	structure_changed.emit()
	return true


func parent_bus_of(child_bus_id: String) -> CodaBus:
	return _parent_bus_find(bus_root, child_bus_id)


func _parent_bus_find(root: CodaBus, child_id: String) -> CodaBus:
	if root.id == child_id:
		return null
	for c in root.children:
		if c.id == child_id:
			return root
		var p: CodaBus = _parent_bus_find(c, child_id)
		if p != null:
			return p
	return null


func _bus_subtree_contains(root: CodaBus, target_id: String) -> bool:
	if root.id == target_id:
		return true
	for c in root.children:
		if _bus_subtree_contains(c, target_id):
			return true
	return false


func _bus_is_strict_ancestor(ancestor_id: String, descendant_id: String) -> bool:
	var cur_id: String = descendant_id
	while true:
		var p: CodaBus = parent_bus_of(cur_id)
		if p == null:
			return false
		if p.id == ancestor_id:
			return true
		cur_id = p.id
	return false


func add_child_bus(parent_id: String, bus_name: String = "Bus") -> CodaBus:
	var p: CodaBus = bus_root.find_by_id(parent_id)
	if p == null:
		return null
	var b: CodaBus = CodaBus.new(bus_name)
	p.children.append(b)
	structure_changed.emit()
	return b


func remove_bus(bus_id: String) -> bool:
	if bus_root != null and bus_id == bus_root.id:
		return false  ## Master bus cannot be removed.
	if bus_root.remove_child_by_id(bus_id):
		structure_changed.emit()
		return true
	return false


func rename_bus(bus_id: String, new_name: String) -> bool:
	var b: CodaBus = bus_root.find_by_id(bus_id)
	if b == null:
		return false
	var trimmed: String = new_name.strip_edges()
	if trimmed.is_empty():
		trimmed = "Bus"
	b.bus_name = trimmed
	structure_changed.emit()
	return true


func add_snapshot(p_name: String = "Snapshot") -> CodaSnapshot:
	var s: CodaSnapshot = CodaSnapshot.new(p_name)
	# Pre-fill with current bus values so apply() roundtrips back to current state by default.
	for b in bus_root.collect_flat():
		s.bus_overrides[b.id] = {
			"volume_db": b.volume_db,
			"mute": b.mute,
			"solo": b.solo,
			"bypass": b.bypass,
			"send_target_id": b.send_target_id,
		}
	snapshots.append(s)
	structure_changed.emit()
	return s


func remove_snapshot(snapshot_id: String) -> bool:
	for i in range(snapshots.size() - 1, -1, -1):
		if snapshots[i].id == snapshot_id:
			snapshots.remove_at(i)
			structure_changed.emit()
			return true
	return false


func rename_snapshot(snapshot_id: String, new_name: String) -> bool:
	for s in snapshots:
		if s.id == snapshot_id:
			var trimmed: String = new_name.strip_edges()
			if trimmed.is_empty():
				trimmed = "Snapshot"
			s.snapshot_name = trimmed
			structure_changed.emit()
			return true
	return false


func find_snapshot_by_id(snapshot_id: String) -> CodaSnapshot:
	for s in snapshots:
		if s.id == snapshot_id:
			return s
	return null


func find_snapshot_by_name(p_name: String) -> CodaSnapshot:
	var trimmed: String = p_name.strip_edges()
	for s in snapshots:
		if s.snapshot_name == trimmed:
			return s
	return null


## Apply a snapshot to the live bus tree (overwrites volume_db/mute for listed buses).
## Phase 5 MVP: instant. Returns true on success.
func apply_snapshot(snapshot_id: String) -> bool:
	var s: CodaSnapshot = find_snapshot_by_id(snapshot_id)
	if s == null:
		return false
	for bus_id in s.bus_overrides.keys():
		var b: CodaBus = bus_root.find_by_id(bus_id)
		if b == null:
			continue
		var entry: Dictionary = s.bus_overrides[bus_id]
		b.volume_db = float(entry.get("volume_db", b.volume_db))
		b.mute = bool(entry.get("mute", b.mute))
		b.solo = bool(entry.get("solo", b.solo))
		b.bypass = bool(entry.get("bypass", b.bypass))
		b.send_target_id = str(entry.get("send_target_id", b.send_target_id))
	structure_changed.emit()
	return true


## Bank mutation API.
func add_bank(p_name: String = "Bank") -> CodaBank:
	var b: CodaBank = CodaBank.new(p_name)
	banks.append(b)
	structure_changed.emit()
	return b


func remove_bank(bank_id: String) -> bool:
	for i in range(banks.size() - 1, -1, -1):
		if banks[i].id == bank_id:
			banks.remove_at(i)
			structure_changed.emit()
			return true
	return false


func rename_bank(bank_id: String, new_name: String) -> bool:
	for b in banks:
		if b.id == bank_id:
			var trimmed: String = new_name.strip_edges()
			if trimmed.is_empty():
				trimmed = "Bank"
			b.bank_name = trimmed
			structure_changed.emit()
			return true
	return false


func find_bank_by_id(bank_id: String) -> CodaBank:
	for b in banks:
		if b.id == bank_id:
			return b
	return null


func banks_containing_event(event_id: String) -> Array[CodaBank]:
	var out: Array[CodaBank] = []
	for b in banks:
		if b.contains_event(event_id):
			out.append(b)
	return out


func add_event_to_bank(bank_id: String, event_id: String) -> bool:
	var b: CodaBank = find_bank_by_id(bank_id)
	if b == null:
		return false
	if not b.add_event_id(event_id):
		return false
	structure_changed.emit()
	return true


func remove_event_from_bank(bank_id: String, event_id: String) -> bool:
	var b: CodaBank = find_bank_by_id(bank_id)
	if b == null:
		return false
	if not b.remove_event_id(event_id):
		return false
	structure_changed.emit()
	return true


func to_dictionary() -> Dictionary:
	var snaps_arr: Array = []
	for s in snapshots:
		snaps_arr.append(s.to_dictionary())
	var banks_arr: Array = []
	for b in banks:
		banks_arr.append(b.to_dictionary())
	return {
		"version": 4,
		"events": events_root.to_dictionary(),
		"assets": assets_root.to_dictionary(),
		"buses": bus_root.to_dictionary() if bus_root != null else CodaBus.make_default_master().to_dictionary(),
		"snapshots": snaps_arr,
		"banks": banks_arr,
		"appearance": {
			"theme_mode": theme_mode,
			"accent_color": [accent_color.r, accent_color.g, accent_color.b, accent_color.a],
		},
	}


func load_from_dictionary(data: Dictionary) -> void:
	var ev: Variant = data.get("events", {})
	if ev is Dictionary:
		events_root = CodaBrowserNode.from_dictionary(ev)
	else:
		events_root = CodaBrowserNode.new("Events", CodaBrowserNode.Kind.FOLDER)
	var as_: Variant = data.get("assets", {})
	if as_ is Dictionary:
		assets_root = CodaBrowserNode.from_dictionary(as_)
	else:
		assets_root = CodaBrowserNode.new("Assets", CodaBrowserNode.Kind.FOLDER)
	var buses_raw: Variant = data.get("buses", null)
	if buses_raw is Dictionary:
		bus_root = CodaBus.from_dictionary(buses_raw)
	else:
		bus_root = CodaBus.make_default_master()
	snapshots.clear()
	for s_raw in data.get("snapshots", []) as Array:
		if s_raw is Dictionary:
			snapshots.append(CodaSnapshot.from_dictionary(s_raw))
	banks.clear()
	for b_raw in data.get("banks", []) as Array:
		if b_raw is Dictionary:
			banks.append(CodaBank.from_dictionary(b_raw))
	theme_mode = "dark"
	accent_color = Color(0.42, 0.74, 1.00, 1.0)
	var appearance_raw: Variant = data.get("appearance", null)
	if appearance_raw is Dictionary:
		var ap: Dictionary = appearance_raw
		var mode_raw: String = str(ap.get("theme_mode", "dark")).to_lower()
		if mode_raw == "light" or mode_raw == "dark":
			theme_mode = mode_raw
		var ac_raw: Variant = ap.get("accent_color", null)
		if ac_raw is Array and (ac_raw as Array).size() >= 3:
			var ac_arr: Array = ac_raw
			accent_color = Color(
				float(ac_arr[0]),
				float(ac_arr[1]),
				float(ac_arr[2]),
				float(ac_arr[3]) if ac_arr.size() >= 4 else 1.0
			)
	structure_changed.emit()
