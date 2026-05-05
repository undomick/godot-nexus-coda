@tool
class_name CodaSnapshot
extends RefCounted

## Snapshot of mixer state. Only buses listed in `bus_overrides` are touched on apply()
## (so partial snapshots are possible). Apply blends from current state to the snapshot
## values over `blend_ms` (Phase 5 MVP: instant; Phase 7 may add an interpolated apply).

var id: String
var snapshot_name: String = "Snapshot"
var blend_ms: int = 0
## Map of bus_id (String) -> { "volume_db": float, "mute": bool }
var bus_overrides: Dictionary = {}


func _init(p_name: String = "Snapshot") -> void:
	id = _generate_id()
	snapshot_name = p_name


static func _generate_id() -> String:
	return "snap_%d_%d" % [Time.get_ticks_usec(), randi()]


func clone_keep_id() -> CodaSnapshot:
	var s: CodaSnapshot = CodaSnapshot.new(snapshot_name)
	s.id = id
	s.blend_ms = blend_ms
	for bus_id in bus_overrides.keys():
		s.bus_overrides[bus_id] = (bus_overrides[bus_id] as Dictionary).duplicate(true)
	return s


func to_dictionary() -> Dictionary:
	var entries: Array = []
	for bus_id in bus_overrides.keys():
		entries.append({
			"bus_id": bus_id,
			"volume_db": float((bus_overrides[bus_id] as Dictionary).get("volume_db", 0.0)),
			"mute": bool((bus_overrides[bus_id] as Dictionary).get("mute", false)),
		})
	return {
		"id": id,
		"name": snapshot_name,
		"blend_ms": blend_ms,
		"overrides": entries,
	}


static func from_dictionary(data: Dictionary) -> CodaSnapshot:
	var s: CodaSnapshot = CodaSnapshot.new(str(data.get("name", "Snapshot")))
	var sid: String = str(data.get("id", "")).strip_edges()
	if not sid.is_empty():
		s.id = sid
	s.blend_ms = int(data.get("blend_ms", 0))
	for entry_raw in data.get("overrides", []) as Array:
		if not (entry_raw is Dictionary):
			continue
		var entry: Dictionary = entry_raw
		var bus_id: String = str(entry.get("bus_id", ""))
		if bus_id.is_empty():
			continue
		s.bus_overrides[bus_id] = {
			"volume_db": float(entry.get("volume_db", 0.0)),
			"mute": bool(entry.get("mute", false)),
		}
	return s
