@tool
class_name CodaSnapshotBlender
extends RefCounted

## Interpolates [CodaSnapshot] bus volume overrides over time, then applies mute/solo at end.

var _project: CodaState = null
var _blend: Dictionary = {}
var _pending_snapshot_id: String = ""
var _sync_buses: Callable = Callable()


func setup(project: CodaState, sync_buses: Callable) -> void:
	_project = project
	_sync_buses = sync_buses


func clear() -> void:
	_blend.clear()
	_pending_snapshot_id = ""


func is_blending() -> bool:
	return not _blend.is_empty()


func apply(snapshot_id: String, blend_ms: int) -> bool:
	if _project == null:
		return false
	var snap: CodaSnapshot = _project.find_snapshot_by_id(snapshot_id)
	if snap == null:
		return false
	if blend_ms <= 0:
		if not _project.apply_snapshot(snapshot_id):
			return false
		if _sync_buses.is_valid():
			_sync_buses.call()
		return true
	_begin_blend(snapshot_id, blend_ms)
	return true


func tick(delta: float) -> void:
	if _blend.is_empty() or _project == null or _pending_snapshot_id.is_empty():
		return
	var snap: CodaSnapshot = _project.find_snapshot_by_id(_pending_snapshot_id)
	if snap == null:
		clear()
		return
	var elapsed: float = float(_blend.get("elapsed", 0.0)) + delta
	var duration: float = float(_blend.get("duration", 0.001))
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	var from_volumes: Dictionary = _blend.get("from_volumes", {}) as Dictionary
	for bus_id in snap.bus_overrides.keys():
		var b: CodaBus = _project.bus_root.find_by_id(bus_id)
		if b == null:
			continue
		var target_db: float = float((snap.bus_overrides[bus_id] as Dictionary).get("volume_db", b.volume_db))
		var start_db: float = float(from_volumes.get(bus_id, b.volume_db))
		b.volume_db = lerpf(start_db, target_db, t)
		if t >= 1.0:
			var entry: Dictionary = snap.bus_overrides[bus_id] as Dictionary
			b.mute = bool(entry.get("mute", b.mute))
			b.solo = bool(entry.get("solo", b.solo))
			b.bypass = bool(entry.get("bypass", b.bypass))
			b.send_target_id = str(entry.get("send_target_id", b.send_target_id))
	_blend["elapsed"] = elapsed
	if _sync_buses.is_valid():
		_sync_buses.call()
	if t >= 1.0:
		clear()


func _begin_blend(snapshot_id: String, blend_ms: int) -> void:
	var snap: CodaSnapshot = _project.find_snapshot_by_id(snapshot_id)
	if snap == null:
		return
	var from_volumes: Dictionary = {}
	for bus_id in snap.bus_overrides.keys():
		var b: CodaBus = _project.bus_root.find_by_id(bus_id)
		if b != null:
			from_volumes[bus_id] = b.volume_db
	_pending_snapshot_id = snapshot_id
	_blend = {
		"elapsed": 0.0,
		"duration": maxf(0.001, float(blend_ms) / 1000.0),
		"from_volumes": from_volumes,
	}
	_project.project_dirty.emit()
