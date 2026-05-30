class_name CodaMixerStore
extends RefCounted

var _state: CodaState


func _init(state: CodaState) -> void:
	_state = state


func update_bus_volume(bus_id: String, volume_db: float) -> void:
	var b: CodaBus = _state.bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.volume_db = volume_db
	_state.project_dirty.emit()


func update_bus_mute(bus_id: String, mute: bool) -> void:
	var b: CodaBus = _state.bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.mute = mute
	_state.project_dirty.emit()


func update_bus_solo(bus_id: String, solo: bool) -> void:
	var b: CodaBus = _state.bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.solo = solo
	_state.project_dirty.emit()


func update_bus_bypass(bus_id: String, bypass: bool) -> void:
	var b: CodaBus = _state.bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.bypass = bypass
	_state.project_dirty.emit()


func update_bus_send_target(bus_id: String, target_bus_id: String) -> void:
	var b: CodaBus = _state.bus_root.find_by_id(bus_id)
	if b == null or b.id == _state.bus_root.id:
		return
	var tid: String = String(target_bus_id).strip_edges()
	if not tid.is_empty():
		var t: CodaBus = _state.bus_root.find_by_id(tid)
		if t == null:
			return
		if not _bus_is_strict_ancestor(tid, bus_id):
			return
	b.send_target_id = tid
	_state.structure_changed.emit()


func move_bus_before_in_tree(drag_bus_id: String, before_bus_id: String) -> bool:
	if _state.bus_root == null or drag_bus_id == _state.bus_root.id:
		return false
	if before_bus_id == _state.bus_root.id:
		return false
	var drag_b: CodaBus = _state.bus_root.find_by_id(drag_bus_id)
	var before_b: CodaBus = _state.bus_root.find_by_id(before_bus_id)
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
	_state.structure_changed.emit()
	return true


func move_bus_after_in_tree(drag_bus_id: String, after_bus_id: String) -> bool:
	if _state.bus_root == null or drag_bus_id == _state.bus_root.id:
		return false
	var drag_b: CodaBus = _state.bus_root.find_by_id(drag_bus_id)
	var after_b: CodaBus = _state.bus_root.find_by_id(after_bus_id)
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
	_state.structure_changed.emit()
	return true


func parent_bus_of(child_bus_id: String) -> CodaBus:
	return _parent_bus_find(_state.bus_root, child_bus_id)


func add_child_bus(parent_id: String, bus_name: String = "Bus") -> CodaBus:
	var p: CodaBus = _state.bus_root.find_by_id(parent_id)
	if p == null:
		return null
	var b: CodaBus = CodaBus.new(bus_name)
	p.children.append(b)
	_state.structure_changed.emit()
	return b


func remove_bus(bus_id: String) -> bool:
	if _state.bus_root != null and bus_id == _state.bus_root.id:
		return false
	if not _state.bus_root.remove_child_by_id(bus_id):
		return false
	_sanitize_send_targets_after_bus_removed(bus_id)
	_state.structure_changed.emit()
	return true


func add_bus_after(after_bus_id: String, bus_name: String = "Bus") -> CodaBus:
	if _state.bus_root == null:
		return null
	var after_b: CodaBus = _state.bus_root.find_by_id(after_bus_id)
	if after_b == null:
		return null
	var p: CodaBus = parent_bus_of(after_bus_id)
	if p == null:
		return add_child_bus(_state.bus_root.id, bus_name)
	var idx: int = p.children.find(after_b)
	if idx < 0:
		return null
	var b: CodaBus = CodaBus.new(bus_name)
	p.children.insert(idx + 1, b)
	_state.structure_changed.emit()
	return b


func duplicate_bus(bus_id: String) -> CodaBus:
	if _state.bus_root == null or bus_id == _state.bus_root.id:
		return null
	var src: CodaBus = _state.bus_root.find_by_id(bus_id)
	if src == null:
		return null
	var p: CodaBus = parent_bus_of(bus_id)
	if p == null:
		return null
	var idx: int = p.children.find(src)
	if idx < 0:
		return null
	var dup: CodaBus = _clone_bus_new_ids(src)
	_assign_unique_bus_names_for_subtree(dup)
	p.children.insert(idx + 1, dup)
	_state.structure_changed.emit()
	return dup


func reset_bus_volume(bus_id: String) -> void:
	if _state.bus_root == null:
		return
	var b: CodaBus = _state.bus_root.find_by_id(bus_id)
	if b == null:
		return
	b.volume_db = 0.0
	_state.project_dirty.emit()


func rename_bus(bus_id: String, new_name: String) -> bool:
	var b: CodaBus = _state.bus_root.find_by_id(bus_id)
	if b == null:
		return false
	var trimmed: String = new_name.strip_edges()
	if trimmed.is_empty():
		trimmed = "Bus"
	b.bus_name = trimmed
	if _bus_name_used_elsewhere(bus_id, trimmed):
		var taken: Dictionary = {}
		for existing in _state.bus_root.collect_flat():
			if existing.id != bus_id:
				taken[_normalized_bus_name(existing.bus_name)] = true
		_assign_unique_bus_names_recursive(b, taken)
	_state.structure_changed.emit()
	return true


func add_snapshot(p_name: String = "Snapshot") -> CodaSnapshot:
	var s: CodaSnapshot = CodaSnapshot.new(p_name)
	for b in _state.bus_root.collect_flat():
		s.bus_overrides[b.id] = {
			"volume_db": b.volume_db,
			"mute": b.mute,
			"solo": b.solo,
			"bypass": b.bypass,
			"send_target_id": b.send_target_id,
		}
	_state.snapshots.append(s)
	_state.project_dirty.emit()
	return s


func remove_snapshot(snapshot_id: String) -> bool:
	for i in range(_state.snapshots.size() - 1, -1, -1):
		if _state.snapshots[i].id == snapshot_id:
			_state.snapshots.remove_at(i)
			_state.project_dirty.emit()
			return true
	return false


func rename_snapshot(snapshot_id: String, new_name: String) -> bool:
	for s in _state.snapshots:
		if s.id == snapshot_id:
			var trimmed: String = new_name.strip_edges()
			if trimmed.is_empty():
				trimmed = "Snapshot"
			s.snapshot_name = trimmed
			_state.project_dirty.emit()
			return true
	return false


func find_snapshot_by_id(snapshot_id: String) -> CodaSnapshot:
	for s in _state.snapshots:
		if s.id == snapshot_id:
			return s
	return null


func find_snapshot_by_name(p_name: String) -> CodaSnapshot:
	var trimmed: String = p_name.strip_edges()
	for s in _state.snapshots:
		if s.snapshot_name == trimmed:
			return s
	return null


func apply_snapshot(snapshot_id: String) -> bool:
	var s: CodaSnapshot = find_snapshot_by_id(snapshot_id)
	if s == null:
		return false
	for bus_id in s.bus_overrides.keys():
		var b: CodaBus = _state.bus_root.find_by_id(bus_id)
		if b == null:
			continue
		var entry: Dictionary = s.bus_overrides[bus_id]
		b.volume_db = float(entry.get("volume_db", b.volume_db))
		b.mute = bool(entry.get("mute", b.mute))
		b.solo = bool(entry.get("solo", b.solo))
		b.bypass = bool(entry.get("bypass", b.bypass))
		b.send_target_id = str(entry.get("send_target_id", b.send_target_id))
	_state.project_dirty.emit()
	return true


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


func _sanitize_send_targets_after_bus_removed(removed_bus_id: String) -> void:
	var rid: String = String(removed_bus_id).strip_edges()
	if rid.is_empty() or _state.bus_root == null:
		return
	for b in _state.bus_root.collect_flat([]):
		if String(b.send_target_id).strip_edges() == rid:
			b.send_target_id = ""


func _assign_unique_bus_names_for_subtree(bus: CodaBus) -> void:
	if _state.bus_root == null or bus == null:
		return
	var taken: Dictionary = {}
	for existing in _state.bus_root.collect_flat():
		taken[_normalized_bus_name(existing.bus_name)] = true
	_assign_unique_bus_names_recursive(bus, taken)


func _assign_unique_bus_names_recursive(bus: CodaBus, taken: Dictionary) -> void:
	var base: String = String(bus.bus_name).strip_edges()
	if base.is_empty():
		base = "Bus"
	var candidate: String = base
	if taken.has(_normalized_bus_name(candidate)):
		var n: int = 2
		while true:
			candidate = "%s (%d)" % [base, n]
			if not taken.has(_normalized_bus_name(candidate)):
				break
			n += 1
	bus.bus_name = candidate
	taken[_normalized_bus_name(candidate)] = true
	for child in bus.children:
		_assign_unique_bus_names_recursive(child, taken)


func _normalized_bus_name(name: String) -> String:
	return String(name).strip_edges().to_lower()


func _bus_name_used_elsewhere(bus_id: String, name: String) -> bool:
	if _state.bus_root == null:
		return false
	var norm: String = _normalized_bus_name(name)
	for existing in _state.bus_root.collect_flat():
		if existing.id == bus_id:
			continue
		if _normalized_bus_name(existing.bus_name) == norm:
			return true
	return false


func _clone_bus_new_ids(src: CodaBus) -> CodaBus:
	var id_remap: Dictionary = {}
	var dup: CodaBus = _clone_bus_new_ids_build(src, id_remap)
	_remap_send_targets_in_subtree(dup, id_remap)
	return dup


func _clone_bus_new_ids_build(src: CodaBus, id_remap: Dictionary) -> CodaBus:
	var b: CodaBus = CodaBus.new(src.bus_name)
	id_remap[src.id] = b.id
	b.volume_db = src.volume_db
	b.mute = src.mute
	b.solo = src.solo
	b.bypass = src.bypass
	b.send_target_id = src.send_target_id
	for e in src.effects:
		b.effects.append(e.clone_new_id())
	for c in src.children:
		b.children.append(_clone_bus_new_ids_build(c, id_remap))
	return b


func _remap_send_targets_in_subtree(root: CodaBus, id_remap: Dictionary) -> void:
	if root == null or id_remap.is_empty():
		return
	for b in root.collect_flat([]):
		var tid: String = String(b.send_target_id).strip_edges()
		if tid.is_empty():
			continue
		if id_remap.has(tid):
			b.send_target_id = id_remap[tid]
