@tool
class_name CodaRuntimeBusSync
extends RefCounted

## AudioServer bus mirroring and coda-bus id resolution extracted from [CodaRuntime].

const CodaAudioBusMirrorScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_mirror.gd")
const CodaAudioBusSyncGateScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd")

var _runtime: CodaRuntime = null
var _bus_id_to_godot_name: Dictionary = {}


func setup(runtime: CodaRuntime) -> void:
	_runtime = runtime


func sync_buses(param_values: Dictionary = {}) -> void:
	var project: CodaProject = _runtime.get_project()
	if project == null or project.bus_root == null:
		rebuild_bus_id_map_from_loaded_banks()
		return
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(_bus_sync_caller()):
		_bus_id_to_godot_name = CodaAudioBusMirrorScript.build_id_map(project.bus_root)
		return
	_bus_id_to_godot_name = CodaAudioBusMirrorScript.sync_to_audio_server(
		project.bus_root, false, project.vcas, param_values
	)


## Bank-only gameplay may load multiple .coda_bank files. Merge each manifest bus tree into
## AudioServer and union id→name maps so earlier banks keep routing after later loads/unloads.
func apply_loaded_bank_buses() -> void:
	var project: CodaProject = _runtime.get_project()
	if project != null:
		sync_buses()
	else:
		rebuild_bus_id_map_from_loaded_banks()
		return
	if _runtime.get_loaded_banks().is_empty():
		return
	for bank_id in _runtime.get_loaded_banks().keys():
		var entry: Dictionary = _runtime.get_loaded_banks()[bank_id]
		var root: Variant = entry.get("bus_root", null)
		if root is CodaBus:
			if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(_bus_sync_caller()):
				continue
			var partial: Dictionary = CodaAudioBusMirrorScript.sync_to_audio_server(
				root as CodaBus, false
			)
			for cid in partial.keys():
				_bus_id_to_godot_name[cid] = partial[cid]


func rebuild_bus_id_map_from_loaded_banks() -> void:
	_bus_id_to_godot_name.clear()
	if _runtime.get_loaded_banks().is_empty():
		return
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.GameplayAutoload
	):
		return
	for bank_id in _runtime.get_loaded_banks().keys():
		var entry: Dictionary = _runtime.get_loaded_banks()[bank_id]
		var root: Variant = entry.get("bus_root", null)
		if root is CodaBus:
			var partial: Dictionary = CodaAudioBusMirrorScript.sync_to_audio_server(
				root as CodaBus, false
			)
			for cid in partial.keys():
				_bus_id_to_godot_name[cid] = partial[cid]


func resolve_bus_name_for_event(event: CodaBrowserNode) -> String:
	if event == null:
		return _runtime.bus_name
	var bus_id: String = String(event.event_output_bus_id).strip_edges()
	if bus_id.is_empty():
		return _runtime.bus_name
	var mapped: String = resolve_godot_bus_name_for_coda_bus_id(bus_id)
	if mapped.is_empty():
		return _runtime.bus_name
	return mapped


func get_bus_id_map() -> Dictionary:
	return _bus_id_to_godot_name.duplicate()


func resolve_godot_bus_name_for_coda_bus_id(coda_bus_id: String) -> String:
	var tid: String = String(coda_bus_id).strip_edges()
	if tid.is_empty():
		return ""
	var v: Variant = _bus_id_to_godot_name.get(tid, null)
	if v != null:
		return String(v)
	return _godot_name_from_project_bus_id(tid)


func _godot_name_from_project_bus_id(coda_bus_id: String) -> String:
	var project: CodaProject = _runtime.get_project()
	if project == null or project.bus_root == null:
		return ""
	var bus: CodaBus = project.bus_root.find_by_id(coda_bus_id)
	if bus == null:
		return ""
	return CodaAudioBusMirrorScript.godot_bus_name_for(bus, project.bus_root)


func _bus_sync_caller() -> int:
	if _runtime.is_editor_preview:
		return CodaAudioBusSyncGateScript.SyncCaller.EditorPreview
	return CodaAudioBusSyncGateScript.SyncCaller.GameplayAutoload
