@tool
class_name CodaRuntimeParameterPipeline
extends RefCounted

## Parameter smoothing, global parameters, and voice modulation extracted from [CodaRuntime].

const CodaModulationScript := preload("res://addons/nexus_coda/editor/browser/coda_modulation.gd")

var _runtime: CodaRuntime = null
var _global_params: Dictionary = {}
var _global_params_last: Dictionary = {}


func setup(runtime: CodaRuntime) -> void:
	_runtime = runtime


func has_global_params() -> bool:
	return not _global_params.is_empty()


func set_global_parameter(name: String, value: Variant) -> void:
	if name.is_empty():
		return
	_global_params[name] = value


func get_global_parameter(name: String, default_value: Variant = null) -> Variant:
	return _global_params.get(name, default_value)


func build_param_values(event: CodaBrowserNode, user_params: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	if event != null:
		for p in event.event_parameters:
			values[p.id] = CodaEventParameter.to_float_value(p.default_value)
	for key in user_params.keys():
		var k: String = String(key)
		if k.begins_with("_coda_"):
			continue
		var val: Variant = user_params[key]
		if event != null:
			var match_id: String = ""
			for p in event.event_parameters:
				if p.id == k:
					match_id = p.id
					break
			if match_id.is_empty():
				var lookup: String = k.to_lower()
				for p in event.event_parameters:
					if String(p.param_name).strip_edges().to_lower() == lookup:
						match_id = p.id
						break
			if not match_id.is_empty():
				values[match_id] = CodaEventParameter.to_float_value(val)
				continue
		values[k] = CodaEventParameter.to_float_value(val)
	return values


func find_event_param(event: CodaBrowserNode, param_id: String) -> CodaEventParameter:
	if event == null:
		return null
	for p in event.event_parameters:
		if p.id == param_id:
			return p
	return null


func apply_global_parameters() -> void:
	if _global_params.is_empty():
		_global_params_last.clear()
		return
	if _global_params.hash() == _global_params_last.hash():
		return
	_global_params_last = _global_params.duplicate(true)
	for h in _runtime.get_active_handles().values():
		var hh: CodaEventHandle = h as CodaEventHandle
		if hh == null or not hh._alive or hh.is_timeline:
			continue
		for gname in _global_params.keys():
			apply_parameter_without_segment_notify(hh, String(gname), _global_params[gname])
	for h in _runtime.get_timeline_dispatchers().keys():
		var th: CodaEventHandle = h as CodaEventHandle
		if th == null or not th._alive:
			continue
		for gname in _global_params.keys():
			apply_parameter_without_segment_notify(th, String(gname), _global_params[gname])


func apply_parameter_without_segment_notify(
	handle: CodaEventHandle, name_or_id: String, value: Variant
) -> void:
	if handle == null:
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null:
		handle.param_values[name_or_id] = value
		return
	var param_id: String = ""
	for p in event.event_parameters:
		if p.id == name_or_id:
			param_id = p.id
			break
	if param_id.is_empty():
		var lookup: String = name_or_id.to_lower()
		for p in event.event_parameters:
			if String(p.param_name).strip_edges().to_lower() == lookup:
				param_id = p.id
				break
	if param_id.is_empty():
		handle.param_values[name_or_id] = value
		return
	var param: CodaEventParameter = find_event_param(event, param_id)
	handle.param_values[param_id] = param.clamp_value(value) if param != null else value


func advance_smoothing(handle: CodaEventHandle, delta: float) -> void:
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null:
		handle.param_values_smoothed = handle.param_values.duplicate()
		return
	for p in event.event_parameters:
		var target: float = float(
			handle.param_values.get(p.id, CodaEventParameter.to_float_value(p.default_value))
		)
		var current: float = float(handle.param_values_smoothed.get(p.id, target))
		if p.smoothing_ms <= 0.0:
			handle.param_values_smoothed[p.id] = target
			continue
		var tau: float = max(0.001, p.smoothing_ms / 1000.0)
		var alpha: float = clampf(1.0 - exp(-delta / tau), 0.0, 1.0)
		handle.param_values_smoothed[p.id] = lerp(current, target, alpha)


func apply_modulations(handle: CodaEventHandle) -> void:
	if handle._player == null or not is_instance_valid(handle._player):
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null or event.event_modulations.is_empty():
		_apply_voice_base_with_blend(handle)
		return
	var sound_id: String = handle.current_sound_id
	var voice_volume_db: float = handle.base_volume_db
	var voice_pitch: float = handle.base_pitch_scale
	for m in event.event_modulations:
		if m.target_node_id != sound_id:
			continue
		var src_val: float = float(handle.param_values_smoothed.get(m.source_param_id, 0.0))
		var out_val: float = m.evaluate(src_val)
		match m.target_property:
			CodaModulationScript.TargetProperty.SOUND_VOLUME_DB:
				voice_volume_db += out_val
			CodaModulationScript.TargetProperty.SOUND_PITCH_SCALE:
				voice_pitch *= out_val
	if handle.blend_weight < 1.0 and handle.blend_weight > 0.0:
		voice_volume_db += linear_to_db(handle.blend_weight)
	elif handle.blend_weight <= 0.0:
		voice_volume_db = -80.0
	handle._player.volume_db = voice_volume_db
	handle._player.pitch_scale = max(0.05, voice_pitch)


func _apply_voice_base_with_blend(handle: CodaEventHandle) -> void:
	if handle._player == null or not is_instance_valid(handle._player):
		return
	var voice_volume_db: float = handle.base_volume_db
	if handle.blend_weight < 1.0 and handle.blend_weight > 0.0:
		voice_volume_db += linear_to_db(handle.blend_weight)
	elif handle.blend_weight <= 0.0:
		voice_volume_db = -80.0
	handle._player.volume_db = voice_volume_db


static func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * (log(linear) / log(10.0))
