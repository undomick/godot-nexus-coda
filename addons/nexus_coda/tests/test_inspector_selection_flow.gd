extends RefCounted

const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_event_timeline.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)
const CodaInspectorSelectionScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_inspector_selection.gd"
)
const CodaInspectorEffectsSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_inspector_effects_section.gd"
)
const CodaEffectsChainBindingScript := preload(
	"res://addons/nexus_coda/editor/panels/effects/coda_effects_chain_binding.gd"
)
const CodaEffectsChainViewScript := preload(
	"res://addons/nexus_coda/editor/panels/effects/coda_effects_chain_view.gd"
)
const CodaEffectsChainListScript := preload(
	"res://addons/nexus_coda/editor/panels/effects/coda_effects_chain_list.gd"
)
const CodaTrackEffectScript := preload(
	"res://addons/nexus_coda/domain/effects/coda_track_effect.gd"
)


static func run_all() -> int:
	var failed: int = 0
	failed += _test_browser_event_overrides_timeline_track()
	failed += _test_same_event_browser_pulse_preserves_timeline_track()
	failed += _test_refresh_keeps_clip_subject()
	failed += _test_refresh_keeps_bus_subject()
	failed += _test_add_track_effect_via_section_chain()
	failed += _test_add_clip_effect_via_section_chain()
	failed += _test_mutation_target_survives_empty_binding_scope()
	failed += _test_track_effect_remove_rebinds_cards()
	failed += _test_track_effect_move_reorders_data()
	failed += _test_effect_chain_survives_double_ready()
	failed += _test_effect_drop_via_list_reorders()
	return failed


static func _make_timeline_event() -> Dictionary:
	var state: CodaState = CodaStateScript.new()
	var ev := CodaBrowserNode.new("flow_ev", CodaBrowserNode.Kind.EVENT)
	ev.event_authoring_mode = CodaBrowserNode.AuthoringMode.TIMELINE
	ev.event_timeline = CodaEventTimelineScript.make_default()
	var track: CodaTimelineTrack = ev.event_timeline.tracks[0]
	var clip: CodaTimelineClip = CodaTimelineClipScript.new()
	track.clips.append(clip)
	state.events_root.children.append(ev)
	return {"state": state, "event": ev, "track": track, "clip": clip}


static func _test_browser_event_overrides_timeline_track() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var track: CodaTimelineTrack = pack["track"] as CodaTimelineTrack

	var sel := CodaInspectorSelectionScript.new()
	sel.project = state
	sel.apply(
		CodaInspectorSelectionScript.Subject.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	var event_state: Dictionary = sel.apply(
		CodaInspectorSelectionScript.Subject.BROWSER_EVENT, {"node": ev}
	)
	if not bool(event_state.get("show_event_stack", false)):
		push_error("browser event should show event stack after timeline track")
		return 1
	if bool(event_state.get("show_context_banner", false)):
		push_error("browser event should not show timeline banner")
		return 1
	if int(event_state.get("fx_scope", 0)) != CodaInspectorEffectsSectionScript.FxScope.NONE:
		push_error("browser event should clear fx scope")
		return 1
	return 0


static func _test_same_event_browser_pulse_preserves_timeline_track() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var track: CodaTimelineTrack = pack["track"] as CodaTimelineTrack

	var sel := CodaInspectorSelectionScript.new()
	sel.project = state
	sel.apply(
		CodaInspectorSelectionScript.Subject.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	# Simulates structure_changed refresh while timeline track is the active subject.
	var track_state: Dictionary = sel.apply(
		CodaInspectorSelectionScript.Subject.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	if int(track_state.get("fx_scope", 0)) != CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK:
		push_error("timeline track fx scope lost on refresh")
		return 1
	state.add_track_effect(ev.id, track.id, CodaTrackEffect.Type.GAIN)
	if track.effects.is_empty():
		push_error("track effect not stored after add")
		return 1
	return 0


static func _test_refresh_keeps_clip_subject() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var track: CodaTimelineTrack = pack["track"] as CodaTimelineTrack
	var clip: CodaTimelineClip = pack["clip"] as CodaTimelineClip

	var sel := CodaInspectorSelectionScript.new()
	sel.project = state
	sel.apply(
		CodaInspectorSelectionScript.Subject.TIMELINE_CLIP,
		{"event_id": ev.id, "clip_id": clip.id, "track_id": track.id}
	)
	state.add_track_effect(ev.id, track.id, CodaTrackEffect.Type.GAIN)
	state.structure_changed.emit()
	var refreshed: Dictionary = sel.apply(
		CodaInspectorSelectionScript.Subject.TIMELINE_CLIP,
		{
			"event_id": sel.event_id,
			"clip_id": sel.clip_id,
			"track_id": sel.track_id,
		}
	)
	if int(refreshed.get("fx_scope", 0)) != CodaInspectorEffectsSectionScript.FxScope.TIMELINE_CLIP:
		push_error("structure refresh should keep clip fx scope")
		return 1
	return 0


static func _test_refresh_keeps_bus_subject() -> int:
	var state: CodaState = CodaStateScript.new()
	var bus: CodaBus = state.bus_root

	var sel := CodaInspectorSelectionScript.new()
	sel.project = state
	sel.apply(CodaInspectorSelectionScript.Subject.MIXER_BUS, {"bus_id": bus.id})
	state.add_bus_effect(bus.id, CodaTrackEffect.Type.GAIN)
	state.structure_changed.emit()
	var refreshed: Dictionary = sel.apply(
		CodaInspectorSelectionScript.Subject.MIXER_BUS,
		{"bus_id": sel.bus_id}
	)
	if int(refreshed.get("fx_scope", 0)) != CodaInspectorEffectsSectionScript.FxScope.BUS:
		push_error("structure refresh should keep bus fx scope")
		return 1
	return 0


static func _test_add_track_effect_via_section_chain() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var track: CodaTimelineTrack = pack["track"] as CodaTimelineTrack

	var section = CodaInspectorEffectsSectionScript.new()
	section._ready()
	section.attach_project(state)
	section.set_fx_scope(
		CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	var chain: CodaEffectsChainView = section.get_track_chain_control() as CodaEffectsChainView
	chain.effect_add_requested.emit(CodaTrackEffect.Type.GAIN)
	if track.effects.is_empty():
		push_error("track effect add via section chain failed")
		return 1
	chain.bind_effects_array(track.effects)
	if chain.get_effect_card_count() != 1:
		push_error("track chain should show one effect card")
		return 1
	return 0


static func _test_add_clip_effect_via_section_chain() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var clip: CodaTimelineClip = pack["clip"] as CodaTimelineClip

	var section = CodaInspectorEffectsSectionScript.new()
	section._ready()
	section.attach_project(state)
	section.set_fx_scope(
		CodaInspectorEffectsSectionScript.FxScope.TIMELINE_CLIP,
		{"event_id": ev.id, "clip_id": clip.id}
	)
	var clip_chain: CodaEffectsChainView = section.get_active_chain_control() as CodaEffectsChainView
	if clip_chain == null:
		push_error("clip chain missing for section add test")
		return 1
	clip_chain.effect_add_requested.emit(CodaTrackEffect.Type.GAIN)
	if clip.effects.is_empty():
		push_error("clip effect add via section chain failed")
		return 1
	clip_chain.bind_effects_array(clip.effects)
	if clip_chain.get_effect_card_count() != 1:
		push_error("clip chain should show one effect card")
		return 1
	return 0


static func _test_mutation_target_survives_empty_binding_scope() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var track: CodaTimelineTrack = pack["track"] as CodaTimelineTrack

	var section = CodaInspectorEffectsSectionScript.new()
	section._ready()
	section.attach_project(state)
	section.set_fx_scope(
		CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	var target: Dictionary = section.get_active_mutation_target()
	if str(target.get("scope", "")) != "track":
		push_error("mutation target scope missing")
		return 1
	if str(target.get("track_id", "")) != track.id:
		push_error("mutation target track id missing")
		return 1
	return 0


static func _test_track_effect_remove_rebinds_cards() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var track: CodaTimelineTrack = pack["track"] as CodaTimelineTrack

	var section = CodaInspectorEffectsSectionScript.new()
	section._ready()
	section.attach_project(state)
	section.set_fx_scope(
		CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	var chain: CodaEffectsChainView = section.get_track_chain_control() as CodaEffectsChainView
	state.add_track_effect(ev.id, track.id, CodaTrackEffect.Type.GAIN)
	if chain.get_effect_card_count() != 1:
		push_error("track chain should show one card after add")
		return 1
	var effect_id: String = track.effects[0].id
	chain.effect_remove_requested.emit(effect_id)
	if not track.effects.is_empty():
		push_error("track effect should be removed from data")
		return 1
	if chain.get_effect_card_count() != 0:
		push_error("track chain should show no cards after remove")
		return 1
	return 0


static func _test_track_effect_move_reorders_data() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var track: CodaTimelineTrack = pack["track"] as CodaTimelineTrack

	var section = CodaInspectorEffectsSectionScript.new()
	section._ready()
	section.attach_project(state)
	section.set_fx_scope(
		CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	var chain: CodaEffectsChainView = section.get_track_chain_control() as CodaEffectsChainView
	state.add_track_effect(ev.id, track.id, CodaTrackEffect.Type.GAIN)
	state.add_track_effect(ev.id, track.id, CodaTrackEffect.Type.COMPRESSOR)
	if chain.get_effect_card_count() != 2:
		push_error("track chain should show two cards")
		return 1
	var second_id: String = track.effects[1].id
	chain.effect_move_requested.emit(1, 0)
	if track.effects[0].id != second_id:
		push_error("track effect move should reorder data")
		return 1
	if chain.get_effect_card_count() != 2:
		push_error("track chain should still show two cards after move")
		return 1
	return 0


static func _test_effect_chain_survives_double_ready() -> int:
	var view: CodaEffectsChainView = CodaEffectsChainViewScript.new()
	view._ready()
	view._ready()
	if view.get_child_count() != 3:
		push_error("double _ready should not duplicate chain chrome (header, list, footer)")
		return 1
	var effects: Array[CodaTrackEffect] = []
	var eff: CodaTrackEffect = CodaTrackEffectScript.new()
	effects.append(eff)
	view.bind_effects_array(effects)
	if view.get_effect_card_count() != 1:
		push_error("effect card missing after bind")
		return 1
	var list: CodaEffectsChainList = _chain_list_from_view(view)
	if list == null:
		push_error("effects chain list missing")
		return 1
	var empty_hints: int = 0
	for child in list.get_children():
		if child is Label and not (child is PanelContainer):
			empty_hints += 1
	if empty_hints > 1:
		push_error("expected at most one empty-state label in list")
		return 1
	return 0


static func _test_effect_drop_via_list_reorders() -> int:
	var pack: Dictionary = _make_timeline_event()
	var state: CodaState = pack["state"] as CodaState
	var ev: CodaBrowserNode = pack["event"] as CodaBrowserNode
	var track: CodaTimelineTrack = pack["track"] as CodaTimelineTrack

	var section = CodaInspectorEffectsSectionScript.new()
	section._ready()
	section.attach_project(state)
	section.set_fx_scope(
		CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	state.add_track_effect(ev.id, track.id, CodaTrackEffect.Type.GAIN)
	state.add_track_effect(ev.id, track.id, CodaTrackEffect.Type.COMPRESSOR)
	var chain: CodaEffectsChainView = section.get_track_chain_control() as CodaEffectsChainView
	var list: CodaEffectsChainList = _chain_list_from_view(chain)
	if list == null:
		push_error("list missing for drop test")
		return 1
	var second_id: String = track.effects[1].id
	list.drop_effect_at_local_y(
		{"type": CodaEffectsChainListScript.DND_TYPE, "effect_id": second_id},
		0.0
	)
	if track.effects[0].id != second_id:
		push_error("drop should move effect to start of chain")
		return 1
	return 0


static func _chain_list_from_view(view: CodaEffectsChainView) -> CodaEffectsChainList:
	for child in view.get_children():
		if child is CodaEffectsChainList:
			return child as CodaEffectsChainList
	return null
