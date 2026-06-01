@tool
class_name CodaInspectorEffectsSection
extends VBoxContainer

enum FxScope { NONE, TIMELINE_TRACK, TIMELINE_CLIP, BUS }

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const ChainScript := preload("res://addons/nexus_coda/editor/panels/effects/coda_effects_chain_view.gd")
const BindingScript := preload("res://addons/nexus_coda/editor/panels/effects/coda_effects_chain_binding.gd")

var _project: CodaState = null
var _track_chain: CodaEffectsChainView
var _clip_chain: CodaEffectsChainView
var _bus_chain: CodaEffectsChainView
var _track_panel: PanelContainer
var _clip_panel: PanelContainer
var _bus_panel: PanelContainer

var _active_scope: FxScope = FxScope.NONE
var _timeline_event_id: String = ""
var _track_id: String = ""
var _clip_id: String = ""
var _bus_id: String = ""
var _chains_ready: bool = false
var _chain_signals_connected: bool = false
var _section_ready: bool = false


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_MD)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	visible = false


func _ready() -> void:
	if _section_ready:
		return
	_section_ready = true
	var track_pack: Dictionary = _make_chain_panel(
		"Track chains are saved with the event and included in editor preview resync."
	)
	_track_panel = track_pack.get("panel") as PanelContainer
	_track_chain = track_pack.get("chain") as CodaEffectsChainView
	var clip_pack: Dictionary = _make_chain_panel(
		"Clip chains are saved with the event and included in editor preview resync."
	)
	_clip_panel = clip_pack.get("panel") as PanelContainer
	_clip_chain = clip_pack.get("chain") as CodaEffectsChainView
	var bus_pack: Dictionary = _make_chain_panel(
		"These effects mirror to Godot's AudioServer when the mixer syncs."
	)
	_bus_panel = bus_pack.get("panel") as PanelContainer
	_bus_chain = bus_pack.get("chain") as CodaEffectsChainView
	add_child(_track_panel)
	add_child(_clip_panel)
	add_child(_bus_panel)
	_track_panel.visible = false
	_clip_panel.visible = false
	_bus_panel.visible = false
	_chains_ready = true
	_connect_chain_signals_once()
	_apply_scope()


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_sync_active_chain):
			_project.structure_changed.disconnect(_sync_active_chain)
	_project = project
	if _project != null:
		_project.structure_changed.connect(_sync_active_chain)
	if _chains_ready:
		_apply_scope()


func set_fx_scope(scope: FxScope, ids: Dictionary = {}) -> void:
	var next_event_id: String = str(ids.get("event_id", ""))
	var next_track_id: String = str(ids.get("track_id", ""))
	var next_clip_id: String = str(ids.get("clip_id", ""))
	var next_bus_id: String = str(ids.get("bus_id", ""))
	var scope_changed: bool = (
		scope != _active_scope
		or next_event_id != _timeline_event_id
		or next_track_id != _track_id
		or next_clip_id != _clip_id
		or next_bus_id != _bus_id
	)
	_active_scope = scope
	_timeline_event_id = next_event_id
	_track_id = next_track_id
	_clip_id = next_clip_id
	_bus_id = next_bus_id
	if not _chains_ready:
		return
	if scope_changed:
		_apply_scope()
	else:
		_sync_active_chain()


func get_active_chain_control() -> Control:
	match _active_scope:
		FxScope.TIMELINE_TRACK:
			return _track_chain
		FxScope.TIMELINE_CLIP:
			return _clip_chain
		FxScope.BUS:
			return _bus_chain
		_:
			return null


func get_active_scope() -> FxScope:
	return _active_scope


func is_scope_panel_visible(scope: FxScope) -> bool:
	if not _chains_ready:
		return false
	match scope:
		FxScope.TIMELINE_TRACK:
			return _track_panel.visible
		FxScope.TIMELINE_CLIP:
			return _clip_panel.visible
		FxScope.BUS:
			return _bus_panel.visible
		_:
			return false


func get_track_chain_control() -> Control:
	return _track_chain


func get_active_mutation_target() -> Dictionary:
	return _snapshot_for_scope(_active_scope)


func _connect_chain_signals_once() -> void:
	if _chain_signals_connected or _track_chain == null:
		return
	_wire_chain(_track_chain, FxScope.TIMELINE_TRACK)
	_wire_chain(_clip_chain, FxScope.TIMELINE_CLIP)
	_wire_chain(_bus_chain, FxScope.BUS)
	_chain_signals_connected = true


func _wire_chain(chain: CodaEffectsChainView, scope: FxScope) -> void:
	chain.effect_add_requested.connect(
		func(effect_type: int) -> void: _on_effect_add_requested(chain, effect_type)
	)
	chain.effect_remove_requested.connect(
		func(effect_id: String) -> void: _on_effect_remove_requested(scope, effect_id)
	)
	chain.effect_move_requested.connect(
		func(from_i: int, to_i: int) -> void: _on_effect_move_requested(scope, from_i, to_i)
	)
	chain.effect_param_changed.connect(
		func(effect_id: String, key: String, value: float) -> void:
			_on_effect_param_changed(scope, effect_id, key, value)
	)
	chain.effect_bypass_changed.connect(
		func(effect_id: String, on: bool) -> void:
			_on_effect_bypass_changed(scope, effect_id, on)
	)


func _mutation_context_for_chain(chain: CodaEffectsChainView) -> Dictionary:
	var scope: FxScope = _scope_for_chain(chain)
	match scope:
		FxScope.TIMELINE_TRACK:
			if _timeline_event_id.is_empty() or _track_id.is_empty():
				return {}
			return {
				"scope": &"track",
				"event_id": _timeline_event_id,
				"track_id": _track_id,
			}
		FxScope.TIMELINE_CLIP:
			if _timeline_event_id.is_empty() or _clip_id.is_empty():
				return {}
			return {
				"scope": &"clip",
				"event_id": _timeline_event_id,
				"clip_id": _clip_id,
			}
		FxScope.BUS:
			if _bus_id.is_empty():
				return {}
			return {"scope": &"bus", "bus_id": _bus_id}
		_:
			return {}


func _snapshot_for_scope(scope: FxScope) -> Dictionary:
	match scope:
		FxScope.TIMELINE_TRACK:
			return {
				"scope": &"track",
				"event_id": _timeline_event_id,
				"track_id": _track_id,
			}
		FxScope.TIMELINE_CLIP:
			return {
				"scope": &"clip",
				"event_id": _timeline_event_id,
				"clip_id": _clip_id,
			}
		FxScope.BUS:
			return {"scope": &"bus", "bus_id": _bus_id}
		_:
			return {}


func _scope_for_chain(chain: CodaEffectsChainView) -> FxScope:
	if chain == _track_chain:
		return FxScope.TIMELINE_TRACK
	if chain == _clip_chain:
		return FxScope.TIMELINE_CLIP
	if chain == _bus_chain:
		return FxScope.BUS
	return FxScope.NONE


func _on_effect_add_requested(chain: CodaEffectsChainView, effect_type: int) -> void:
	if chain == null:
		return
	var ctx: Dictionary = _mutation_context_for_chain(chain)
	if ctx.is_empty():
		push_warning("Coda: effect add skipped (missing target context)")
		return
	_apply_effect_add(ctx, effect_type)


func _apply_effect_add(ctx: Dictionary, effect_type: int) -> void:
	if _project == null:
		return
	if ctx.is_empty():
		push_warning("Coda: effect add skipped (missing target context)")
		return
	var scope: StringName = ctx.get("scope", &"") as StringName
	match scope:
		&"track":
			var event_id: String = str(ctx.get("event_id", ""))
			var track_id: String = str(ctx.get("track_id", ""))
			if event_id.is_empty() or track_id.is_empty():
				push_warning("Coda: track effect add skipped (missing event/track id)")
				return
			var err: String = _project.add_track_effect(
				event_id, track_id, effect_type as CodaTrackEffect.Type
			)
			if not err.is_empty():
				push_warning("Coda: %s" % err)
				return
		&"clip":
			var clip_event_id: String = str(ctx.get("event_id", ""))
			var clip_id: String = str(ctx.get("clip_id", ""))
			if clip_event_id.is_empty() or clip_id.is_empty():
				push_warning("Coda: clip effect add skipped (missing event/clip id)")
				return
			var err_clip: String = _project.add_clip_effect(
				clip_event_id, clip_id, effect_type as CodaTrackEffect.Type
			)
			if not err_clip.is_empty():
				push_warning("Coda: %s" % err_clip)
				return
		&"bus":
			var bus_id: String = str(ctx.get("bus_id", ""))
			if bus_id.is_empty():
				push_warning("Coda: bus effect add skipped (missing bus id)")
				return
			var err_bus: String = _project.add_bus_effect(
				bus_id, effect_type as CodaTrackEffect.Type
			)
			if not err_bus.is_empty():
				push_warning("Coda: %s" % err_bus)
				return
		_:
			push_warning("Coda: effect add skipped (unknown scope)")
			return
	_sync_active_chain()


func _make_chain_panel(footer: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		&"panel",
		Tokens.make_panel_stylebox(Tokens.SURFACE_RAISED, Tokens.SURFACE_BORDER, Tokens.RADIUS_MD)
	)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", Tokens.SPACING_MD)
	margin.add_theme_constant_override(&"margin_top", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_right", Tokens.SPACING_MD)
	margin.add_theme_constant_override(&"margin_bottom", Tokens.SPACING_SM)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)
	var chain: CodaEffectsChainView = ChainScript.new()
	chain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain.set_footer_text(footer)
	margin.add_child(chain)
	if not chain.is_node_ready():
		chain._ready()
	return {"panel": panel, "chain": chain}


func _apply_scope() -> void:
	if not _chains_ready or _track_panel == null or _track_chain == null:
		return
	_track_panel.visible = false
	_clip_panel.visible = false
	_bus_panel.visible = false
	_track_chain.visible = false
	_clip_chain.visible = false
	_bus_chain.visible = false

	if _active_scope == FxScope.NONE:
		visible = false
		return

	visible = true
	_sync_active_chain()


func _sync_active_chain() -> void:
	if not _chains_ready or _track_panel == null or _active_scope == FxScope.NONE:
		return
	_sync_chain(_active_scope)


func _sync_chain(scope: FxScope) -> void:
	var panel: PanelContainer = null
	var chain: CodaEffectsChainView = null
	var title: String = ""
	var effects: Array[CodaTrackEffect] = []
	var source_missing: bool = false

	match scope:
		FxScope.TIMELINE_TRACK:
			panel = _track_panel
			chain = _track_chain
			var tr: CodaTimelineTrack = BindingScript.resolve_track(
				_project, _timeline_event_id, _track_id
			)
			title = "Track: %s" % (tr.track_name if tr != null else "Track")
			if tr != null:
				effects = tr.effects
			else:
				source_missing = true
		FxScope.TIMELINE_CLIP:
			panel = _clip_panel
			chain = _clip_chain
			var clip: CodaTimelineClip = BindingScript.resolve_clip(
				_project, _timeline_event_id, _clip_id
			)
			title = "Effects"
			if clip != null:
				effects = clip.effects
			else:
				source_missing = true
		FxScope.BUS:
			panel = _bus_panel
			chain = _bus_chain
			var bus: CodaBus = BindingScript.resolve_bus(_project, _bus_id)
			title = "Bus: %s" % (bus.bus_name if bus != null else "Bus")
			if bus != null:
				effects = bus.effects
			else:
				source_missing = true
		_:
			return

	if source_missing:
		_active_scope = FxScope.NONE
		_apply_scope()
		return

	_track_panel.visible = scope == FxScope.TIMELINE_TRACK
	_clip_panel.visible = scope == FxScope.TIMELINE_CLIP
	_bus_panel.visible = scope == FxScope.BUS
	_track_chain.visible = false
	_clip_chain.visible = false
	_bus_chain.visible = false

	panel.visible = true
	chain.set_chain_title(title)
	chain.bind_effects_array(effects)
	chain.visible = true


func _on_effect_remove_requested(scope: FxScope, effect_id: String) -> void:
	if _project == null or scope != _active_scope:
		return
	match scope:
		FxScope.TIMELINE_TRACK:
			_project.remove_track_effect(_timeline_event_id, _track_id, effect_id)
		FxScope.TIMELINE_CLIP:
			_project.remove_clip_effect(_timeline_event_id, _clip_id, effect_id)
		FxScope.BUS:
			_project.remove_bus_effect(_bus_id, effect_id)
	_sync_active_chain()


func _on_effect_move_requested(scope: FxScope, from_i: int, to_i: int) -> void:
	if _project == null or scope != _active_scope:
		return
	match scope:
		FxScope.TIMELINE_TRACK:
			_project.move_track_effect(_timeline_event_id, _track_id, from_i, to_i)
		FxScope.TIMELINE_CLIP:
			_project.move_clip_effect(_timeline_event_id, _clip_id, from_i, to_i)
		FxScope.BUS:
			_project.move_bus_effect(_bus_id, from_i, to_i)
	_sync_active_chain()


func _on_effect_param_changed(
	scope: FxScope, effect_id: String, key: String, value: float
) -> void:
	if _project == null or scope != _active_scope:
		return
	var payload: Dictionary = {key: value}
	match scope:
		FxScope.TIMELINE_TRACK:
			_project.set_track_effect_params(
				_timeline_event_id, _track_id, effect_id, payload
			)
		FxScope.TIMELINE_CLIP:
			_project.set_clip_effect_params(
				_timeline_event_id, _clip_id, effect_id, payload
			)
		FxScope.BUS:
			_project.set_bus_effect_params(_bus_id, effect_id, payload)


func _on_effect_bypass_changed(scope: FxScope, effect_id: String, on: bool) -> void:
	if _project == null or scope != _active_scope:
		return
	match scope:
		FxScope.TIMELINE_TRACK:
			_project.set_track_effect_bypass(_timeline_event_id, _track_id, effect_id, on)
		FxScope.TIMELINE_CLIP:
			_project.set_clip_effect_bypass(_timeline_event_id, _clip_id, effect_id, on)
		FxScope.BUS:
			_project.set_bus_effect_bypass(_bus_id, effect_id, on)
	_sync_active_chain()
