@tool
extends RefCounted
class_name CodaAudioBusMirror

## Mirrors the project's CodaBus tree into Godot's AudioServer buses.
## Each CodaBus becomes a Godot bus named after the bus_name; the mirror sets volume/mute,
## parents children to their Coda parent's mirrored bus, and remembers a mapping bus_id → godot_index.
##
## Buses are matched by **name**. Renames in Coda must remove the old Godot bus or the old name stays behind.
##
## Optional pruning: when [param prune_unclaimed_buses] is [code]true[/code], non-master AudioServer buses
## whose names are not in the current Coda tree are removed before sync (editor mixer / export cleanup).
## The runtime keeps this [code]false[/code] by default so shipped games keep their project-wide bus layout.

const CodaProjectIo := preload("res://addons/nexus_coda/editor/coda_project_io.gd")
const CodaEffectCatalogScript := preload(
	"res://addons/nexus_coda/editor/browser/effects/coda_effect_catalog.gd"
)
const CodaFxBusHelperScript := preload("res://addons/nexus_coda/runtime/coda_fx_bus_helper.gd")

## Returns dictionary { coda_bus_id (String) -> godot_bus_name (String) }.
## Pass [code]prune_unclaimed_buses = true[/code] from editor-only callers that own the whole bus list.
static func sync_to_audio_server(
	bus_root: CodaBus, prune_unclaimed_buses: bool = false
) -> Dictionary:
	var map: Dictionary = {}
	if bus_root == null:
		return map
	var claimed: Dictionary = _claimed_godot_names(bus_root)
	if prune_unclaimed_buses:
		_prune_unclaimed_buses(claimed)
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


static func _claimed_godot_names(bus_root: CodaBus) -> Dictionary:
	var claimed: Dictionary = {}
	var flat: Array[CodaBus] = bus_root.collect_flat([])
	for b in flat:
		claimed[_godot_name_for_coda_bus(b, bus_root)] = true
	return claimed


## Removes AudioServer buses whose names are not in [param claimed], except index 0 ([code]Master[/code]).
## After [method AudioServer.remove_bus], another bus may occupy the same index — adjust [code]i[/code] instead of only decrementing.
static func _prune_unclaimed_buses(claimed: Dictionary) -> void:
	var i: int = AudioServer.get_bus_count() - 1
	while i >= 1:
		if i >= AudioServer.get_bus_count():
			i = AudioServer.get_bus_count() - 1
			continue
		var nm: String = AudioServer.get_bus_name(i)
		if CodaFxBusHelperScript.is_helper_bus(nm):
			continue
		if not claimed.has(nm):
			AudioServer.remove_bus(i)
			i = mini(i, AudioServer.get_bus_count() - 1)
		else:
			i -= 1


static func _apply_master_settings(master: CodaBus) -> void:
	var idx: int = AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, master.volume_db)
		AudioServer.set_bus_mute(idx, master.mute)
		AudioServer.set_bus_bypass_effects(idx, master.bypass)
	_apply_coda_bus_effects_to_godot_bus(idx, master)


static func _clear_godot_bus_effects(bus_idx: int) -> void:
	if bus_idx < 0:
		return
	var n: int = AudioServer.get_bus_effect_count(bus_idx)
	for i in range(n - 1, -1, -1):
		AudioServer.remove_bus_effect(bus_idx, i)


static func _apply_coda_bus_effects_to_godot_bus(bus_idx: int, bus: CodaBus) -> void:
	if bus_idx < 0 or bus == null:
		return
	_clear_godot_bus_effects(bus_idx)
	for eff in bus.effects:
		var ae: AudioEffect = CodaEffectCatalogScript.build_audio_effect_from_slot(eff)
		AudioServer.add_bus_effect(bus_idx, ae)
		var slot: int = AudioServer.get_bus_effect_count(bus_idx) - 1
		# Godot exposes per-slot bypass as the inverse "enabled" flag.
		AudioServer.set_bus_effect_enabled(bus_idx, slot, not eff.bypass)


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
	var gidx: int = AudioServer.get_bus_index(name)
	_apply_coda_bus_effects_to_godot_bus(gidx, bus)
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


## Builds an [AudioBusLayout] that contains **only** buses from the Coda [param bus_root] tree (same as the mixer).
## Avoids dumping unrelated [AudioServer] buses left over in the editor ("New Bus", old experiments, etc.).
static func bus_layout_from_coda_tree(bus_root: CodaBus) -> AudioBusLayout:
	var layout := AudioBusLayout.new()
	if bus_root == null:
		return layout
	var flat: Array[CodaBus] = bus_root.collect_flat([])
	for i in flat.size():
		var b: CodaBus = flat[i]
		var gname: String = _godot_name_for_coda_bus(b, bus_root)
		var parent: CodaBus = _parent_of(bus_root, b.id)
		var tree_parent_name: String = "Master"
		if parent != null:
			tree_parent_name = _godot_name_for_coda_bus(parent, bus_root)
		var send_nm: String = _resolve_send_name(b, tree_parent_name, bus_root)
		if b.id == bus_root.id:
			send_nm = ""
		layout.set_indexed(NodePath("bus/%d/name" % i), gname)
		layout.set_indexed(NodePath("bus/%d/solo" % i), b.solo)
		layout.set_indexed(NodePath("bus/%d/mute" % i), b.mute)
		layout.set_indexed(NodePath("bus/%d/bypass_fx" % i), b.bypass)
		layout.set_indexed(NodePath("bus/%d/volume_db" % i), b.volume_db)
		layout.set_indexed(NodePath("bus/%d/send" % i), send_nm)
	return layout


## Saves the Coda mixer bus tree as [AudioBusLayout]. [param bus_root] is required. [param path] may be
## [code]res://[/code], [code]user://[/code], or an absolute path; extension is normalized to [code].tres[/code]
## when missing or not a resource extension. Call [method sync_to_audio_server] with pruning enabled before export so routing matches
## the live mixer; saved **names and levels** still come from [param bus_root].
static func save_current_audio_bus_layout(path: String, bus_root: CodaBus) -> Dictionary:
	var p: String = _normalize_bus_layout_save_path(path)
	if p.is_empty():
		return {"error": ERR_INVALID_PARAMETER, "path": ""}
	if bus_root == null:
		return {"error": ERR_INVALID_PARAMETER, "path": p}
	var layout: AudioBusLayout = bus_layout_from_coda_tree(bus_root)
	var abs_path: String = CodaProjectIo.to_physical_path(p)
	if not abs_path.is_empty():
		var base_dir: String = abs_path.get_base_dir()
		if not base_dir.is_empty():
			var mk: Error = DirAccess.make_dir_recursive_absolute(base_dir)
			if mk != OK:
				return {"error": mk, "path": p}
	var err: Error = ResourceSaver.save(layout, p)
	return {"error": err, "path": p}


static func _normalize_bus_layout_save_path(path: String) -> String:
	var p: String = str(path).strip_edges().replace("\\", "/")
	if p.is_empty():
		return ""
	var ext: String = p.get_extension().to_lower()
	if ext.is_empty():
		return p + ".tres"
	if ext != "tres" and ext != "res":
		return p.get_basename() + ".tres"
	return p


static func peak_db_for_bus(godot_bus_name: String) -> Vector2:
	var idx: int = AudioServer.get_bus_index(godot_bus_name)
	if idx < 0:
		return Vector2(-80.0, -80.0)
	# Two channels for stereo. Mono will report the same value on both.
	return Vector2(AudioServer.get_bus_peak_volume_left_db(idx, 0), AudioServer.get_bus_peak_volume_right_db(idx, 0))
