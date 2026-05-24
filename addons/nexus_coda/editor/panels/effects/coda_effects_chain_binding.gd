@tool
class_name CodaEffectsChainBinding
extends RefCounted

var _project: CodaState = null
var _chain: CodaEffectsChainView = null
var _scope: StringName = &""
var _event_id: String = ""
var _track_id: String = ""
var _clip_id: String = ""
var _bus_id: String = ""
var _mutation_target_provider: Callable = Callable()


func bind_chain(chain: CodaEffectsChainView, project: CodaState) -> void:
	_disconnect_chain()
	_chain = chain
	_project = project
	if _chain == null:
		return
	_chain.effect_add_requested.connect(_on_add)
	_chain.effect_remove_requested.connect(_on_remove)
	_chain.effect_move_requested.connect(_on_move)
	_chain.effect_param_changed.connect(_on_param)
	_chain.effect_bypass_changed.connect(_on_bypass)


func set_mutation_target_provider(provider: Callable) -> void:
	_mutation_target_provider = provider


func set_track_context(event_id: String, track_id: String) -> void:
	_scope = &"track"
	_event_id = event_id
	_track_id = track_id
	_clip_id = ""
	_bus_id = ""


func set_clip_context(event_id: String, clip_id: String) -> void:
	_scope = &"clip"
	_event_id = event_id
	_clip_id = clip_id
	_track_id = ""
	_bus_id = ""


func set_bus_context(bus_id: String) -> void:
	_scope = &"bus"
	_bus_id = bus_id
	_event_id = ""
	_track_id = ""
	_clip_id = ""


func clear_context() -> void:
	_scope = &""
	_event_id = ""
	_track_id = ""
	_clip_id = ""
	_bus_id = ""


static func resolve_track(
	project: CodaState, event_id: String, track_id: String
) -> CodaTimelineTrack:
	if project == null or event_id.is_empty() or track_id.is_empty():
		return null
	var node: CodaBrowserNode = project.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT or node.event_timeline == null:
		return null
	return node.event_timeline.find_track(track_id)


static func resolve_clip(
	project: CodaState, event_id: String, clip_id: String
) -> CodaTimelineClip:
	if project == null or event_id.is_empty() or clip_id.is_empty():
		return null
	var node: CodaBrowserNode = project.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT or node.event_timeline == null:
		return null
	var info: Dictionary = node.event_timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	return info.get("clip") as CodaTimelineClip


static func resolve_bus(project: CodaState, bus_id: String) -> CodaBus:
	if project == null or project.bus_root == null or bus_id.is_empty():
		return null
	return project.bus_root.find_by_id(bus_id)


func _disconnect_chain() -> void:
	if _chain == null or not is_instance_valid(_chain):
		return
	if _chain.effect_add_requested.is_connected(_on_add):
		_chain.effect_add_requested.disconnect(_on_add)
	if _chain.effect_remove_requested.is_connected(_on_remove):
		_chain.effect_remove_requested.disconnect(_on_remove)
	if _chain.effect_move_requested.is_connected(_on_move):
		_chain.effect_move_requested.disconnect(_on_move)
	if _chain.effect_param_changed.is_connected(_on_param):
		_chain.effect_param_changed.disconnect(_on_param)
	if _chain.effect_bypass_changed.is_connected(_on_bypass):
		_chain.effect_bypass_changed.disconnect(_on_bypass)


func _resolve_mutation_target() -> Dictionary:
	if _mutation_target_provider.is_valid():
		var provided: Variant = _mutation_target_provider.call()
		if provided is Dictionary and not (provided as Dictionary).is_empty():
			return provided as Dictionary
	if _scope.is_empty():
		return {}
	return {
		"scope": _scope,
		"event_id": _event_id,
		"track_id": _track_id,
		"clip_id": _clip_id,
		"bus_id": _bus_id,
	}


func _on_add(effect_type: int) -> void:
	if _project == null:
		return
	var target: Dictionary = _resolve_mutation_target()
	var scope: StringName = target.get("scope", _scope) as StringName
	match scope:
		&"track":
			_project.add_track_effect(
				str(target.get("event_id", _event_id)),
				str(target.get("track_id", _track_id)),
				effect_type as CodaTrackEffect.Type
			)
		&"clip":
			_project.add_clip_effect(
				str(target.get("event_id", _event_id)),
				str(target.get("clip_id", _clip_id)),
				effect_type as CodaTrackEffect.Type
			)
		&"bus":
			_project.add_bus_effect(
				str(target.get("bus_id", _bus_id)),
				effect_type as CodaTrackEffect.Type
			)
		_:
			push_warning(
				"Coda: effect add ignored (no active FX target — scope=%s)" % String(scope)
			)


func _on_remove(effect_id: String) -> void:
	if _project == null:
		return
	var target: Dictionary = _resolve_mutation_target()
	var scope: StringName = target.get("scope", _scope) as StringName
	match scope:
		&"track":
			_project.remove_track_effect(
				str(target.get("event_id", _event_id)),
				str(target.get("track_id", _track_id)),
				effect_id
			)
		&"clip":
			_project.remove_clip_effect(
				str(target.get("event_id", _event_id)),
				str(target.get("clip_id", _clip_id)),
				effect_id
			)
		&"bus":
			_project.remove_bus_effect(str(target.get("bus_id", _bus_id)), effect_id)


func _on_move(from_i: int, to_i: int) -> void:
	if _project == null:
		return
	var target: Dictionary = _resolve_mutation_target()
	var scope: StringName = target.get("scope", _scope) as StringName
	match scope:
		&"track":
			_project.move_track_effect(
				str(target.get("event_id", _event_id)),
				str(target.get("track_id", _track_id)),
				from_i,
				to_i
			)
		&"clip":
			_project.move_clip_effect(
				str(target.get("event_id", _event_id)),
				str(target.get("clip_id", _clip_id)),
				from_i,
				to_i
			)
		&"bus":
			_project.move_bus_effect(str(target.get("bus_id", _bus_id)), from_i, to_i)


func _on_param(effect_id: String, key: String, value: float) -> void:
	if _project == null:
		return
	var payload: Dictionary = {key: value}
	var target: Dictionary = _resolve_mutation_target()
	var scope: StringName = target.get("scope", _scope) as StringName
	match scope:
		&"track":
			_project.set_track_effect_params(
				str(target.get("event_id", _event_id)),
				str(target.get("track_id", _track_id)),
				effect_id,
				payload
			)
		&"clip":
			_project.set_clip_effect_params(
				str(target.get("event_id", _event_id)),
				str(target.get("clip_id", _clip_id)),
				effect_id,
				payload
			)
		&"bus":
			_project.set_bus_effect_params(
				str(target.get("bus_id", _bus_id)), effect_id, payload
			)


func _on_bypass(effect_id: String, on: bool) -> void:
	if _project == null:
		return
	var target: Dictionary = _resolve_mutation_target()
	var scope: StringName = target.get("scope", _scope) as StringName
	match scope:
		&"track":
			_project.set_track_effect_bypass(
				str(target.get("event_id", _event_id)),
				str(target.get("track_id", _track_id)),
				effect_id,
				on
			)
		&"clip":
			_project.set_clip_effect_bypass(
				str(target.get("event_id", _event_id)),
				str(target.get("clip_id", _clip_id)),
				effect_id,
				on
			)
		&"bus":
			_project.set_bus_effect_bypass(
				str(target.get("bus_id", _bus_id)), effect_id, on
			)
