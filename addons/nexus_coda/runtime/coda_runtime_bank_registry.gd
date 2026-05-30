@tool
class_name CodaRuntimeBankRegistry
extends RefCounted

const CodaBankExportScript := preload("res://addons/nexus_coda/domain/io/coda_bank_export.gd")
const CodaBrowserNodeScript := preload("res://addons/nexus_coda/domain/coda_browser_node.gd")
const CodaBusScript := preload("res://addons/nexus_coda/domain/coda_bus.gd")

var _runtime: CodaRuntime = null
var _loaded_banks: Dictionary = {}


func setup(runtime: CodaRuntime) -> void:
	_runtime = runtime


func clear() -> void:
	_loaded_banks.clear()


func get_loaded_banks() -> Dictionary:
	return _loaded_banks


func loaded_bank_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _loaded_banks.keys():
		out.append(String(k))
	return out


func resolve_event(event_path: String) -> Dictionary:
	var p: String = event_path.strip_edges()
	if p.begins_with("events/"):
		p = p.substr(7)
	# Later load_bank wins on duplicate paths (reverse iteration).
	var bank_ids: Array = _loaded_banks.keys()
	for i in range(bank_ids.size() - 1, -1, -1):
		var bank_id: String = String(bank_ids[i])
		var entry: Dictionary = _loaded_banks[bank_id]
		var by_path: Dictionary = entry.get("events_by_path", {})
		if by_path.has(p):
			return {"node": by_path[p] as CodaBrowserNode, "bank_id": bank_id}
	return {"node": null, "bank_id": ""}


func load_bank(path: String) -> String:
	var manifest_raw: Variant = CodaBankExportScript.read_manifest_from_path(path)
	if manifest_raw is String:
		_runtime.runtime_warn(str(manifest_raw))
		return ""
	var manifest: Dictionary = manifest_raw
	var bank_id: String = str(manifest.get("bank_id", ""))
	if bank_id.is_empty():
		_runtime.runtime_warn("bank file has no bank_id")
		return ""
	var events_by_path: Dictionary = {}
	for event_raw in manifest.get("events", []) as Array:
		if not (event_raw is Dictionary):
			continue
		var event_dict: Dictionary = event_raw
		var event_path: String = str(event_dict.get("__path", ""))
		var node: CodaBrowserNode = CodaBrowserNodeScript.from_dictionary(event_dict)
		if node == null or event_path.is_empty():
			continue
		events_by_path[event_path] = node
	var bank_bus_root: CodaBus = null
	var buses_raw: Variant = manifest.get("buses", null)
	if buses_raw is Dictionary:
		bank_bus_root = CodaBusScript.from_dictionary(buses_raw as Dictionary)
	# Re-assign existing bank_id so it moves to the end of insertion order.
	if _loaded_banks.has(bank_id):
		stop_voices_for_bank(bank_id)
		_loaded_banks.erase(bank_id)
	_loaded_banks[bank_id] = {
		"bank_name": str(manifest.get("bank_name", "Bank")),
		"events_by_path": events_by_path,
		"bus_root": bank_bus_root,
	}
	_runtime.get_bus_sync().apply_loaded_bank_buses()
	return bank_id


func unload_bank(bank_id: String) -> bool:
	if not _loaded_banks.has(bank_id):
		return false
	stop_voices_for_bank(bank_id)
	_loaded_banks.erase(bank_id)
	_runtime.get_bus_sync().apply_loaded_bank_buses()
	return true


func stop_voices_for_bank(bank_id: String) -> void:
	if bank_id.is_empty():
		return
	var seen: Dictionary = {}
	for item in _runtime.collect_runtime_handles():
		var h: CodaEventHandle = item as CodaEventHandle
		if h == null or seen.has(h):
			continue
		if h.source_bank_id != bank_id:
			continue
		seen[h] = true
		_runtime.stop(h)
