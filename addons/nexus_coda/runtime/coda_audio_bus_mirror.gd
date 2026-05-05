@tool
extends RefCounted
class_name CodaAudioBusMirror

## Mirrors the project's CodaBus tree into Godot's AudioServer buses.
## Each CodaBus becomes a Godot bus named after the bus_name; the mirror sets volume/mute,
## parents children to their Coda parent's mirrored bus, and remembers a mapping bus_id → godot_index.
##
## We deliberately keep the user's existing AudioServer buses untouched. We only create buses
## whose name is in our claim set (prefixed with the project's master bus name when not "Master").

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")

## Returns dictionary { coda_bus_id (String) -> godot_bus_name (String) }
static func sync_to_audio_server(bus_root: CodaBus) -> Dictionary:
	var map: Dictionary = {}
	if bus_root == null:
		return map
	# Master always maps to Godot's index 0 ("Master"), regardless of the Coda bus name.
	map[bus_root.id] = "Master"
	_apply_master_settings(bus_root)
	for child in bus_root.children:
		_sync_bus_recursive(child, "Master", map, bus_root)
	# Apply solo logic at the end (any bus marked solo silences others on the same level via mute).
	_apply_solo_visibility(bus_root)
	return map


static func _parent_of(root: CodaBus, child_id: String) -> CodaBus:
	if root.id == child_id:
		return null
	for c in root.children:
		if c.id == child_id:
			return root
		var p: CodaBus = _parent_of(c, child_id)
		if p != null:
			return p
	return null


static func _is_strict_ancestor_of(bus_root: CodaBus, ancestor_id: String, descendant_id: String) -> bool:
	var cur_id: String = descendant_id
	while true:
		var p: CodaBus = _parent_of(bus_root, cur_id)
		if p == null:
			return false
		if p.id == ancestor_id:
			return true
		cur_id = p.id
	return false


static func _godot_name_for_coda_bus(b: CodaBus, bus_root: CodaBus) -> String:
	if b.id == bus_root.id:
		return "Master"
	var n: String = String(b.bus_name).strip_edges()
	if n.is_empty():
		return "Bus"
	return n


static func _resolve_send_name(
	bus: CodaBus,
	tree_parent_godot_name: String,
	bus_root: CodaBus
) -> String:
	var tid: String = String(bus.send_target_id).strip_edges()
	if not tid.is_empty():
		var t: CodaBus = bus_root.find_by_id(tid)
		if t != null and _is_strict_ancestor_of(bus_root, tid, bus.id):
			return _godot_name_for_coda_bus(t, bus_root)
	return tree_parent_godot_name


static func _apply_master_settings(master: CodaBus) -> void:
	var idx: int = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, master.volume_db)
		AudioServer.set_bus_mute(idx, master.mute)
		AudioServer.set_bus_bypass_effects(idx, master.bypass)


static func _sync_bus_recursive(bus: CodaBus, tree_parent_name: String, map: Dictionary, bus_root: CodaBus) -> void:
	var name: String = String(bus.bus_name).strip_edges()
	if name.is_empty():
		name = "Bus"
	var idx: int = AudioServer.get_bus_index(name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, name)
	var send_nm: String = _resolve_send_name(bus, tree_parent_name, bus_root)
	AudioServer.set_bus_send(idx, send_nm)
	AudioServer.set_bus_volume_db(idx, bus.volume_db)
	AudioServer.set_bus_mute(idx, bus.mute)
	AudioServer.set_bus_bypass_effects(idx, bus.bypass)
	map[bus.id] = name
	for child in bus.children:
		_sync_bus_recursive(child, name, map, bus_root)


static func _apply_solo_visibility(root: CodaBus) -> void:
	# If any sibling is soloed, mute the others. Done at each level independently.
	_apply_solo_at_level([root])
	_apply_solo_recursive(root)


static func _apply_solo_recursive(parent: CodaBus) -> void:
	if parent.children.is_empty():
		return
	_apply_solo_at_level(parent.children)
	for c in parent.children:
		_apply_solo_recursive(c)


static func _apply_solo_at_level(siblings: Array) -> void:
	var any_solo: bool = false
	for s in siblings:
		if (s as CodaBus).solo:
			any_solo = true
			break
	if not any_solo:
		return
	for s in siblings:
		var b: CodaBus = s as CodaBus
		var name: String = "Master" if b.bus_name == "Master" else String(b.bus_name).strip_edges()
		var idx: int = AudioServer.get_bus_index(name)
		if idx < 0:
			continue
		# Solo on this bus = unmute; solo elsewhere = mute (unless model already has mute=true).
		AudioServer.set_bus_mute(idx, b.mute or not b.solo)


static func peak_db_for_bus(godot_bus_name: String) -> Vector2:
	var idx: int = AudioServer.get_bus_index(godot_bus_name)
	if idx < 0:
		return Vector2(-80.0, -80.0)
	# Two channels for stereo. Mono will report the same value on both.
	return Vector2(AudioServer.get_bus_peak_volume_left_db(idx, 0), AudioServer.get_bus_peak_volume_right_db(idx, 0))
