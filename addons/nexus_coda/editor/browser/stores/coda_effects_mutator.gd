class_name CodaEffectsMutator
extends RefCounted

const CodaEffectCatalogScript := preload("res://addons/nexus_coda/domain/effects/coda_effect_catalog.gd")

enum Scope { TRACK, CLIP, BUS }

var _state: CodaState


func _init(state: CodaState) -> void:
	_state = state


func add(scope: Scope, event_id: String, target_id: String, effect_type: CodaTrackEffect.Type) -> String:
	match scope:
		Scope.TRACK:
			return _add_track_effect(event_id, target_id, effect_type)
		Scope.CLIP:
			return _add_clip_effect(event_id, target_id, effect_type)
		Scope.BUS:
			return _add_bus_effect(target_id, effect_type)
		_:
			return "Unknown effect scope."


func remove(scope: Scope, event_id: String, target_id: String, effect_id: String) -> void:
	match scope:
		Scope.TRACK:
			_remove_track_effect(event_id, target_id, effect_id)
		Scope.CLIP:
			_remove_clip_effect(event_id, target_id, effect_id)
		Scope.BUS:
			_remove_bus_effect(target_id, effect_id)


func move(scope: Scope, event_id: String, target_id: String, from_index: int, to_index: int) -> void:
	match scope:
		Scope.TRACK:
			_move_track_effect(event_id, target_id, from_index, to_index)
		Scope.CLIP:
			_move_clip_effect(event_id, target_id, from_index, to_index)
		Scope.BUS:
			_move_bus_effect(target_id, from_index, to_index)


func set_params(scope: Scope, event_id: String, target_id: String, effect_id: String, params: Dictionary) -> void:
	match scope:
		Scope.TRACK:
			_set_track_effect_params(event_id, target_id, effect_id, params)
		Scope.CLIP:
			_set_clip_effect_params(event_id, target_id, effect_id, params)
		Scope.BUS:
			_set_bus_effect_params(target_id, effect_id, params)


func set_bypass(scope: Scope, event_id: String, target_id: String, effect_id: String, on: bool) -> void:
	match scope:
		Scope.TRACK:
			_set_track_effect_bypass(event_id, target_id, effect_id, on)
		Scope.CLIP:
			_set_clip_effect_bypass(event_id, target_id, effect_id, on)
		Scope.BUS:
			_set_bus_effect_bypass(target_id, effect_id, on)


func _event_timeline_for_mutate(event_id: String) -> CodaEventTimeline:
	var node: CodaBrowserNode = _state.events_root.find_by_id(event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return null
	return node.event_timeline


func _find_track_effect(tr: CodaTimelineTrack, effect_id: String) -> CodaTrackEffect:
	for e in tr.effects:
		if e.id == effect_id:
			return e
	return null


func _find_clip_effect(clip: CodaTimelineClip, effect_id: String) -> CodaTrackEffect:
	for e in clip.effects:
		if e.id == effect_id:
			return e
	return null


func _find_bus_effect(bus: CodaBus, effect_id: String) -> CodaTrackEffect:
	for e in bus.effects:
		if e.id == effect_id:
			return e
	return null


func _add_track_effect(event_id: String, track_id: String, effect_type: CodaTrackEffect.Type) -> String:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return "No timeline for this event."
	var tr: CodaTimelineTrack = tl.find_track(track_id)
	if tr == null:
		return "Track not found."
	var e := CodaTrackEffect.new()
	e.type = effect_type
	e.params = CodaEffectCatalogScript.default_params(effect_type).duplicate(true)
	tr.effects.append(e)
	_state.structure_changed.emit()
	return ""


func _remove_track_effect(event_id: String, track_id: String, effect_id: String) -> void:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return
	var tr: CodaTimelineTrack = tl.find_track(track_id)
	if tr == null:
		return
	for i in range(tr.effects.size()):
		if tr.effects[i].id == effect_id:
			tr.effects.remove_at(i)
			_state.structure_changed.emit()
			return


func _move_track_effect(event_id: String, track_id: String, from_index: int, to_index: int) -> void:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return
	var tr: CodaTimelineTrack = tl.find_track(track_id)
	if tr == null or tr.effects.is_empty():
		return
	from_index = clampi(from_index, 0, tr.effects.size() - 1)
	to_index = clampi(to_index, 0, tr.effects.size() - 1)
	if from_index == to_index:
		return
	var e: CodaTrackEffect = tr.effects[from_index]
	tr.effects.remove_at(from_index)
	tr.effects.insert(to_index, e)
	_state.structure_changed.emit()


func _set_track_effect_params(event_id: String, track_id: String, effect_id: String, params: Dictionary) -> void:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return
	var tr: CodaTimelineTrack = tl.find_track(track_id)
	if tr == null:
		return
	var e: CodaTrackEffect = _find_track_effect(tr, effect_id)
	if e == null:
		return
	for k in params.keys():
		e.params[k] = params[k]
	_state.project_dirty.emit()


func _set_track_effect_bypass(event_id: String, track_id: String, effect_id: String, on: bool) -> void:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return
	var tr: CodaTimelineTrack = tl.find_track(track_id)
	if tr == null:
		return
	var e: CodaTrackEffect = _find_track_effect(tr, effect_id)
	if e == null:
		return
	e.bypass = on
	_state.project_dirty.emit()


func _add_clip_effect(event_id: String, clip_id: String, effect_type: CodaTrackEffect.Type) -> String:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return "No timeline for this event."
	var info: Dictionary = tl.find_clip(clip_id)
	if info.is_empty():
		return "Clip not found."
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return "Clip not found."
	var e := CodaTrackEffect.new()
	e.type = effect_type
	e.params = CodaEffectCatalogScript.default_params(effect_type).duplicate(true)
	clip.effects.append(e)
	_state.structure_changed.emit()
	return ""


func _remove_clip_effect(event_id: String, clip_id: String, effect_id: String) -> void:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return
	var info: Dictionary = tl.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return
	for i in range(clip.effects.size()):
		if clip.effects[i].id == effect_id:
			clip.effects.remove_at(i)
			_state.structure_changed.emit()
			return


func _move_clip_effect(event_id: String, clip_id: String, from_index: int, to_index: int) -> void:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return
	var info: Dictionary = tl.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null or clip.effects.is_empty():
		return
	from_index = clampi(from_index, 0, clip.effects.size() - 1)
	to_index = clampi(to_index, 0, clip.effects.size() - 1)
	if from_index == to_index:
		return
	var e: CodaTrackEffect = clip.effects[from_index]
	clip.effects.remove_at(from_index)
	clip.effects.insert(to_index, e)
	_state.structure_changed.emit()


func _set_clip_effect_params(event_id: String, clip_id: String, effect_id: String, params: Dictionary) -> void:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return
	var info: Dictionary = tl.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return
	var e: CodaTrackEffect = _find_clip_effect(clip, effect_id)
	if e == null:
		return
	for k in params.keys():
		e.params[k] = params[k]
	_state.project_dirty.emit()


func _set_clip_effect_bypass(event_id: String, clip_id: String, effect_id: String, on: bool) -> void:
	var tl: CodaEventTimeline = _event_timeline_for_mutate(event_id)
	if tl == null:
		return
	var info: Dictionary = tl.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return
	var e: CodaTrackEffect = _find_clip_effect(clip, effect_id)
	if e == null:
		return
	e.bypass = on
	_state.project_dirty.emit()


func _add_bus_effect(bus_id: String, effect_type: CodaTrackEffect.Type) -> String:
	if _state.bus_root == null:
		return "No bus tree."
	var bus: CodaBus = _state.bus_root.find_by_id(bus_id)
	if bus == null:
		return "Bus not found."
	var e := CodaTrackEffect.new()
	e.type = effect_type
	e.params = CodaEffectCatalogScript.default_params(effect_type).duplicate(true)
	bus.effects.append(e)
	_state.structure_changed.emit()
	return ""


func _remove_bus_effect(bus_id: String, effect_id: String) -> void:
	if _state.bus_root == null:
		return
	var bus: CodaBus = _state.bus_root.find_by_id(bus_id)
	if bus == null:
		return
	for i in range(bus.effects.size()):
		if bus.effects[i].id == effect_id:
			bus.effects.remove_at(i)
			_state.structure_changed.emit()
			return


func _move_bus_effect(bus_id: String, from_index: int, to_index: int) -> void:
	if _state.bus_root == null:
		return
	var bus: CodaBus = _state.bus_root.find_by_id(bus_id)
	if bus == null or bus.effects.is_empty():
		return
	from_index = clampi(from_index, 0, bus.effects.size() - 1)
	to_index = clampi(to_index, 0, bus.effects.size() - 1)
	if from_index == to_index:
		return
	var e: CodaTrackEffect = bus.effects[from_index]
	bus.effects.remove_at(from_index)
	bus.effects.insert(to_index, e)
	_state.structure_changed.emit()


func _set_bus_effect_params(bus_id: String, effect_id: String, params: Dictionary) -> void:
	if _state.bus_root == null:
		return
	var bus: CodaBus = _state.bus_root.find_by_id(bus_id)
	if bus == null:
		return
	var e: CodaTrackEffect = _find_bus_effect(bus, effect_id)
	if e == null:
		return
	for k in params.keys():
		e.params[k] = params[k]
	_state.project_dirty.emit()


func _set_bus_effect_bypass(bus_id: String, effect_id: String, on: bool) -> void:
	if _state.bus_root == null:
		return
	var bus: CodaBus = _state.bus_root.find_by_id(bus_id)
	if bus == null:
		return
	var e: CodaTrackEffect = _find_bus_effect(bus, effect_id)
	if e == null:
		return
	e.bypass = on
	_state.project_dirty.emit()
