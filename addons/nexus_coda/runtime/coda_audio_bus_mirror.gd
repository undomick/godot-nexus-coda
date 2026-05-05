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
		_sync_bus_recursive(child, "Master", map)
	# Apply solo logic at the end (any bus marked solo silences others on the same level via mute).
	_apply_solo_visibility(bus_root)
	return map


static func _apply_master_settings(master: CodaBus) -> void:
	var idx: int = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, master.volume_db)
		AudioServer.set_bus_mute(idx, master.mute)


static func _sync_bus_recursive(bus: CodaBus, parent_name: String, map: Dictionary) -> void:
	var name: String = String(bus.bus_name).strip_edges()
	if name.is_empty():
		name = "Bus"
	var idx: int = AudioServer.get_bus_index(name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, parent_name)
	AudioServer.set_bus_volume_db(idx, bus.volume_db)
	AudioServer.set_bus_mute(idx, bus.mute)
	map[bus.id] = name
	for child in bus.children:
		_sync_bus_recursive(child, name, map)


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
