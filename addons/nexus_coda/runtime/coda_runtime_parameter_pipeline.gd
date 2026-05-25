@tool
class_name CodaRuntimeParameterPipeline
extends RefCounted

## Parameter smoothing, globals, and per-voice modulation for CodaRuntime.

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
		var param_id: String = resolve_param_id(event, k)
		if not param_id.is_empty():
			values[param_id] = CodaEventParameter.to_float_value(val)
		else:
			values[k] = CodaEventParameter.to_float_value(val)
	return values


func resolve_param_id(event: CodaBrowserNode, name_or_id: String) -> String:
	if event == null:
		return ""
	for p in event.event_parameters:
		if p.id == name_or_id:
			return p.id
	var lookup: String = name_or_id.to_lower()
	for p in event.event_parameters:
		if String(p.param_name).strip_edges().to_lower() == lookup:
			return p.id
	return ""


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
			var gkey: String = String(gname)
			apply_parameter_without_segment_notify(th, gkey, _global_params[gkey])
			_runtime.notify_global_param_applied(th, gkey)


func apply_parameter_without_segment_notify(
	handle: CodaEventHandle, name_or_id: String, value: Variant
) -> void:
	if handle == null:
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null:
		handle.param_values[name_or_id] = value
		return
	var param_id: String = resolve_param_id(event, name_or_id)
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


func modulation_voice_levels(
	handle: CodaEventHandle, sound_id: String, base_volume_db: float, base_pitch_scale: float
) -> Dictionary:
	var voice_volume_db: float = base_volume_db
	var voice_pitch: float = base_pitch_scale
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event != null and not event.event_modulations.is_empty():
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
	voice_volume_db = volume_db_with_blend(voice_volume_db, handle.blend_weight)
	return {"volume_db": voice_volume_db, "pitch_scale": max(0.05, voice_pitch)}


func apply_modulations(handle: CodaEventHandle) -> void:
	if handle._player == null or not is_instance_valid(handle._player):
		return
	var levels: Dictionary = modulation_voice_levels(
		handle,
		handle.current_sound_id,
		handle.base_volume_db,
		handle.base_pitch_scale,
	)
	handle._player.volume_db = float(levels.get("volume_db", handle.base_volume_db))
	handle._player.pitch_scale = float(levels.get("pitch_scale", handle.base_pitch_scale))


static func volume_db_with_blend(base_db: float, blend_weight: float) -> float:
	if blend_weight < 1.0 and blend_weight > 0.0:
		return base_db + linear_to_db(blend_weight)
	if blend_weight <= 0.0:
		return -80.0
	return base_db


static func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * (log(linear) / log(10.0))
