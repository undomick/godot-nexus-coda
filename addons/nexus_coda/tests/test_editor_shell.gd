extends SceneTree

const LayoutStore := preload("res://addons/nexus_coda/editor/shell/coda_editor_layout_store.gd")
const LayoutStoreClass := preload("res://addons/nexus_coda/editor/shell/coda_editor_layout_store.gd")
const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaTimelineMarkerUiScript := preload(
	"res://addons/nexus_coda/editor/panels/timeline/coda_timeline_marker_ui.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_event_timeline.gd"
)
const CodaTimelineMarkerScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_marker.gd"
)
const CodaJsonUtilScript := preload("res://addons/nexus_coda/editor/io/coda_json_util.gd")
const CodaProjectSerializerScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_project_serializer.gd"
)
const CodaRuntimeGraphPlaybackScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_graph_playback.gd"
)
const CodaAudioBusSyncGateScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd"
)
const CodaControlSizeCompatScript := preload(
	"res://addons/nexus_coda/editor/coda_control_size_compat.gd"
)
const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaEffectsChainBindingScript := preload(
	"res://addons/nexus_coda/editor/panels/effects/coda_effects_chain_binding.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_clip.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_track.gd"
)
const CodaModulationScript := preload("res://addons/nexus_coda/editor/browser/coda_modulation.gd")
const CodaEventParameterScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_event_parameter.gd"
)
const CodaInspectorEffectsSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_inspector_effects_section.gd"
)
const CodaInspectorSelectionScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_inspector_selection.gd"
)
const CodaEffectCatalogScript := preload(
	"res://addons/nexus_coda/editor/browser/effects/coda_effect_catalog.gd"
)
const CodaTrackEffectScript := preload(
	"res://addons/nexus_coda/editor/browser/effects/coda_track_effect.gd"
)
const InspectorSelectionFlowTests := preload(
	"res://addons/nexus_coda/tests/test_inspector_selection_flow.gd"
)


func _init() -> void:
	var failed: int = 0
	failed += _test_layout_store()
	failed += _test_bank_rename_duplicate()
	failed += _test_event_duplicate_ids()
	failed += _test_event_duplicate_remaps_timeline_clip_modulations()
	failed += _test_delete_event_clears_banks()
	failed += _test_orphaned_event_edits_not_serialized()
	failed += _test_marker_ui()
	failed += _test_nan_json_save()
	failed += _test_control_max_size_compat()
	failed += _test_project_serializer_roundtrip()
	failed += _test_graph_parallel_split()
	failed += _test_bus_sync_gate_editor_blocks_autoload()
	failed += _test_bus_sync_gate_gameplay_wins()
	failed += _test_voice_pool_exhausted_signal()
	failed += _test_effects_chain_binding()
	failed += _test_inspector_fx_scope_exclusive()
	failed += _test_inspector_selection_view_state()
	failed += _test_inspector_fx_stable_on_structure_changed()
	failed += InspectorSelectionFlowTests.run_all()
	failed += _test_reverb_damping_build()
	if failed > 0:
		push_error("Editor shell tests failed (%d)" % failed)
		quit(1)
		return
	print("Editor shell tests OK")
	quit(0)


static func _test_layout_store() -> int:
	var host := preload("res://addons/nexus_coda/editor/layout/coda_dock_host.gd").new()
	var dm := preload("res://addons/nexus_coda/editor/layout/coda_dock_manager.gd").new()
	host.add_child(dm)
	var payload: Dictionary = LayoutStoreClass.build_payload(host, dm)
	if int(payload.get("version", 0)) != 2:
		push_error("layout payload version")
		return 1
	LayoutStoreClass.apply_payload(host, dm, payload)
	return 0


static func _test_bank_rename_duplicate() -> int:
	var state: CodaState = CodaStateScript.new()
	var bank: CodaBank = state.add_bank("Combat")
	if bank == null:
		push_error("add_bank failed")
		return 1
	if not state.rename_bank(bank.id, "  Combat UI  "):
		push_error("rename_bank failed")
		return 1
	if state.find_bank_by_id(bank.id).bank_name != "Combat UI":
		push_error("rename_bank trim")
		return 1
	var dup: CodaBank = state.duplicate_bank(bank.id)
	if dup == null or dup.id == bank.id:
		push_error("duplicate_bank failed")
		return 1
	if dup.event_ids.size() != bank.event_ids.size():
		push_error("duplicate_bank event membership")
		return 1
	if state.banks.size() < 2:
		push_error("duplicate_bank insert")
		return 1
	return 0


static func _test_event_duplicate_ids() -> int:
	var state: CodaState = CodaStateScript.new()
	var parent: CodaBrowserNode = state.events_root
	var ev: CodaBrowserNode = state.add_events_event(parent.id, "Footsteps")
	if ev == null:
		push_error("add_events_event failed")
		return 1
	var param := CodaEventParameter.new()
	param.param_name = "Intensity"
	ev.event_parameters.append(param)
	var sound: CodaEventGraphNodeData = CodaEventGraphNodeData.new(CodaEventGraphNodeData.Kind.SOUND)
	ev.event_graph.nodes.append(sound)
	ev.event_graph.edges.append(CodaEventGraphEdge.new(ev.event_graph.nodes[0].id, sound.id))
	var mod := CodaModulation.new()
	mod.source_param_id = param.id
	mod.target_node_id = sound.id
	ev.event_modulations.append(mod)
	var copy: CodaBrowserNode = state.duplicate_events_node(ev.id)
	if copy == null:
		push_error("duplicate_events_node failed")
		return 1
	if copy.id == ev.id:
		push_error("duplicate_events_node reused event id")
		return 1
	if copy.event_parameters.is_empty() or copy.event_parameters[0].id == param.id:
		push_error("duplicate_events_node reused parameter id")
		return 1
	if copy.event_modulations.is_empty():
		push_error("duplicate_events_node dropped modulations")
		return 1
	var mod_copy: CodaModulation = copy.event_modulations[0]
	if mod_copy.source_param_id != copy.event_parameters[0].id:
		push_error("duplicate_events_node modulation param remap")
		return 1
	if mod_copy.target_node_id == sound.id:
		push_error("duplicate_events_node modulation node remap")
		return 1
	if copy.event_graph == null or copy.event_graph.edges.is_empty():
		push_error("duplicate_events_node graph edges missing")
		return 1
	var edge: CodaEventGraphEdge = copy.event_graph.edges[0]
	if edge.from_node_id == ev.event_graph.nodes[0].id or edge.to_node_id == sound.id:
		push_error("duplicate_events_node graph edge remap")
		return 1
	return 0


static func _test_event_duplicate_remaps_timeline_clip_modulations() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev: CodaBrowserNode = state.add_events_event(state.events_root.id, "Stems")
	if ev == null:
		push_error("add_events_event failed")
		return 1
	ev.event_timeline = CodaEventTimelineScript.make_default()
	var intensity := CodaEventParameterScript.new()
	intensity.param_name = "intensity"
	ev.event_parameters.append(intensity)
	var stem_track: CodaTimelineTrack = CodaTimelineTrackScript.new()
	stem_track.track_name = "Music"
	var stem_clip: CodaTimelineClip = CodaTimelineClipScript.new()
	stem_clip.id = "stem_low"
	stem_track.clips.append(stem_clip)
	ev.event_timeline.tracks.append(stem_track)
	var mod := CodaModulationScript.new()
	mod.source_param_id = intensity.id
	mod.target_node_id = stem_clip.id
	ev.event_modulations.append(mod)
	var copy: CodaBrowserNode = state.duplicate_events_node(ev.id)
	if copy == null or copy.event_modulations.is_empty():
		push_error("duplicate_events_node failed for clip modulation")
		return 1
	var mod_copy: CodaModulation = copy.event_modulations[0]
	if mod_copy.target_node_id == stem_clip.id:
		push_error("duplicate_events_node should remap timeline clip modulation targets")
		return 1
	var copy_clip: CodaTimelineClip = copy.event_timeline.tracks[1].clips[0]
	if mod_copy.target_node_id != copy_clip.id:
		push_error("duplicate_events_node clip modulation should target duplicated clip id")
		return 1
	return 0


static func _test_delete_event_clears_banks() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev: CodaBrowserNode = state.add_events_event(state.events_root.id, "Gone")
	if ev == null:
		push_error("add_events_event failed")
		return 1
	var bank: CodaBank = state.add_bank("Test")
	if bank == null:
		push_error("add_bank failed")
		return 1
	if not state.add_event_to_bank(bank.id, ev.id):
		push_error("add_event_to_bank failed")
		return 1
	if not state.delete_node(ev.id):
		push_error("delete_node failed")
		return 1
	if state.events_root.find_by_id(ev.id) != null:
		push_error("deleted event still in tree")
		return 1
	if bank.contains_event(ev.id):
		push_error("bank still references deleted event")
		return 1
	return 0


static func _test_orphaned_event_edits_not_serialized() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev: CodaBrowserNode = state.add_events_event(state.events_root.id, "Orphan")
	if ev == null:
		push_error("orphan test setup failed")
		return 1
	if ev.event_timeline == null:
		ev.event_timeline = CodaEventTimelineScript.make_default()
	var ev_id: String = ev.id
	var timeline: CodaEventTimeline = ev.event_timeline
	if not state.delete_node(ev_id):
		push_error("delete_node failed in orphan test")
		return 1
	timeline.length_seconds = 99.0
	var data: Dictionary = CodaProjectSerializerScript.to_dictionary(state)
	if _dict_tree_contains_event_id(data.get("events", {}) as Dictionary, ev_id):
		push_error("deleted event still present in serialized project")
		return 1
	return 0


static func _dict_tree_contains_event_id(node_d: Dictionary, event_id: String) -> bool:
	if str(node_d.get("id", "")) == event_id:
		return true
	for child_raw in node_d.get("children", []) as Array:
		if child_raw is Dictionary and _dict_tree_contains_event_id(child_raw as Dictionary, event_id):
			return true
	return false


static func _test_marker_ui() -> int:
	var tl: CodaEventTimeline = CodaEventTimelineScript.new()
	var m: CodaTimelineMarker = CodaTimelineMarkerScript.new()
	m.marker_name = "Intro"
	tl.markers.append(m)
	CodaTimelineMarkerUiScript.rename_marker(m, "  Outro  ")
	if m.marker_name != "Outro":
		push_error("rename_marker trim")
		return 1
	if not CodaTimelineMarkerUiScript.delete_marker(tl, m.id):
		push_error("delete_marker failed")
		return 1
	if not tl.markers.is_empty():
		push_error("delete_marker left marker")
		return 1
	return 0


static func _test_control_max_size_compat() -> int:
	var btn := Button.new()
	CodaControlSizeCompatScript.set_custom_maximum_size(btn, Vector2(64, 32))
	if int(Engine.get_version_info().get("hex", 0)) >= 0x040700:
		var got: Variant = btn.get(&"custom_maximum_size")
		if got is Vector2 and not (got as Vector2).is_equal_approx(Vector2(64, 32)):
			push_error("custom_maximum_size setter did not apply on supported engine")
			return 1
	return 0


static func _test_nan_json_save() -> int:
	var payload: Dictionary = {"value": NAN, "nested": {"x": INF}}
	var text: String = CodaJsonUtilScript.stringify(payload, "  ")
	if text.is_empty():
		push_error("CodaJsonUtil.stringify returned empty for NaN payload")
		return 1
	if text.find("NaN") >= 0 or text.find("Infinity") >= 0:
		push_error("CodaJsonUtil.stringify left non-finite literals")
		return 1
	return 0


static func _test_project_serializer_roundtrip() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev: CodaBrowserNode = state.add_events_event(state.events_root.id, "Roundtrip")
	if ev == null:
		push_error("serializer setup event failed")
		return 1
	var data: Dictionary = CodaProjectSerializerScript.to_dictionary(state)
	var loaded: CodaState = CodaStateScript.new()
	CodaProjectSerializerScript.load_from_dictionary(loaded, data)
	var found: CodaBrowserNode = loaded.events_root.find_by_id(ev.id)
	if found == null or found.name != "Roundtrip":
		push_error("serializer roundtrip lost event")
		return 1
	return 0


static func _test_graph_parallel_split() -> int:
	var entries: Array = [
		{"blend_weight": 0.5, "blend_parallel_step": 0},
		{"blend_weight": 0.5, "blend_parallel_step": 0},
		{"blend_weight": 1.0, "blend_parallel_step": 1},
	]
	var split: Array = CodaRuntimeGraphPlaybackScript.split_parallel_entries(entries)
	if split.size() != 2:
		push_error("graph parallel split size")
		return 1
	return 0


static func _test_bus_sync_gate_editor_blocks_autoload() -> int:
	CodaAudioBusSyncGateScript.reset_for_tests()
	CodaAudioBusSyncGateScript.register_editor_preview(42)
	if CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.GameplayAutoload
	):
		push_error("autoload sync should be blocked while editor preview is registered")
		return 1
	CodaAudioBusSyncGateScript.unregister_editor_preview(42)
	return 0


static func _test_bus_sync_gate_gameplay_wins() -> int:
	CodaAudioBusSyncGateScript.reset_for_tests()
	CodaAudioBusSyncGateScript.register_editor_preview(7)
	CodaAudioBusSyncGateScript.set_gameplay_active(true)
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.GameplayAutoload
	):
		push_error("gameplay sync should be allowed during play")
		return 1
	if CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.EditorPreview
	):
		push_error("editor preview sync should be blocked during play")
		return 1
	CodaAudioBusSyncGateScript.reset_for_tests()
	return 0


static func _test_voice_pool_exhausted_signal() -> int:
	var rt: CodaRuntime = CodaRuntimeScript.new()
	var fired: Array = [false]
	rt.voice_pool_exhausted.connect(func(_ctx: Dictionary) -> void: fired[0] = true)
	rt.is_editor_preview = true
	rt.runtime_report_pool_exhausted({
		"mode": "test",
		"detail": "voice pool exhausted (test)",
		"active": 2,
		"pool_size": 2,
	})
	if not bool(fired[0]):
		push_error("voice_pool_exhausted signal not emitted")
		return 1
	return 0


static func _test_effects_chain_binding() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev := CodaBrowserNode.new("fx_test", CodaBrowserNode.Kind.EVENT)
	ev.event_authoring_mode = CodaBrowserNode.AuthoringMode.TIMELINE
	ev.event_timeline = CodaEventTimelineScript.make_default()
	var track: CodaTimelineTrack = ev.event_timeline.tracks[0]
	var clip: CodaTimelineClip = CodaTimelineClipScript.new()
	track.clips.append(clip)
	state.events_root.children.append(ev)

	var tr: CodaTimelineTrack = CodaEffectsChainBindingScript.resolve_track(
		state, ev.id, track.id
	)
	if tr == null or tr.id != track.id:
		push_error("resolve_track")
		return 1
	var cl: CodaTimelineClip = CodaEffectsChainBindingScript.resolve_clip(
		state, ev.id, clip.id
	)
	if cl == null or cl.id != clip.id:
		push_error("resolve_clip")
		return 1
	var bus: CodaBus = CodaEffectsChainBindingScript.resolve_bus(state, state.bus_root.id)
	if bus == null:
		push_error("resolve_bus")
		return 1
	var err: String = state.add_track_effect(
		ev.id, track.id, CodaTrackEffect.Type.GAIN
	)
	if not err.is_empty() or track.effects.is_empty():
		push_error("add_track_effect mutation")
		return 1
	return 0


static func _test_inspector_fx_scope_exclusive() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev := CodaBrowserNode.new("scope_test", CodaBrowserNode.Kind.EVENT)
	ev.event_authoring_mode = CodaBrowserNode.AuthoringMode.TIMELINE
	ev.event_timeline = CodaEventTimelineScript.make_default()
	var track: CodaTimelineTrack = ev.event_timeline.tracks[0]
	var clip: CodaTimelineClip = CodaTimelineClipScript.new()
	track.clips.append(clip)
	state.events_root.children.append(ev)

	var section = CodaInspectorEffectsSectionScript.new()
	section.set_fx_scope(
		CodaInspectorEffectsSectionScript.FxScope.TIMELINE_CLIP,
		{"event_id": ev.id, "clip_id": clip.id}
	)
	if section.get_active_scope() != CodaInspectorEffectsSectionScript.FxScope.TIMELINE_CLIP:
		push_error("fx scope clip active")
		return 1
	section.set_fx_scope(CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK, {
		"event_id": ev.id,
		"track_id": track.id,
	})
	if section.get_active_scope() != CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK:
		push_error("fx scope track active")
		return 1
	section.set_fx_scope(CodaInspectorEffectsSectionScript.FxScope.NONE)
	if section.get_active_scope() != CodaInspectorEffectsSectionScript.FxScope.NONE:
		push_error("fx scope none")
		return 1
	return 0


static func _test_inspector_selection_view_state() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev := CodaBrowserNode.new("sel_test", CodaBrowserNode.Kind.EVENT)
	ev.event_authoring_mode = CodaBrowserNode.AuthoringMode.TIMELINE
	ev.event_timeline = CodaEventTimelineScript.make_default()
	var track: CodaTimelineTrack = ev.event_timeline.tracks[0]
	state.events_root.children.append(ev)

	var sel := CodaInspectorSelectionScript.new()
	sel.project = state
	var event_state: Dictionary = sel.apply(
		CodaInspectorSelectionScript.Subject.BROWSER_EVENT, {"node": ev}
	)
	if not bool(event_state.get("show_event_stack", false)):
		push_error("browser event should show event stack")
		return 1
	if bool(event_state.get("show_context_banner", false)):
		push_error("browser event should not show context banner")
		return 1

	var track_state: Dictionary = sel.apply(
		CodaInspectorSelectionScript.Subject.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	if bool(track_state.get("show_event_stack", false)):
		push_error("timeline track should hide event stack")
		return 1
	if not bool(track_state.get("show_context_banner", false)):
		push_error("timeline track should show context banner")
		return 1
	if int(track_state.get("fx_scope", 0)) != CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK:
		push_error("timeline track fx scope")
		return 1
	return 0


static func _test_inspector_fx_stable_on_structure_changed() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev := CodaBrowserNode.new("fx_stable", CodaBrowserNode.Kind.EVENT)
	ev.event_authoring_mode = CodaBrowserNode.AuthoringMode.TIMELINE
	ev.event_timeline = CodaEventTimelineScript.make_default()
	var track: CodaTimelineTrack = ev.event_timeline.tracks[0]
	state.events_root.children.append(ev)

	var section = CodaInspectorEffectsSectionScript.new()
	section._ready()
	section.attach_project(state)
	section.set_fx_scope(
		CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK,
		{"event_id": ev.id, "track_id": track.id}
	)
	if not section.visible:
		push_error("fx section should be visible with track scope")
		return 1
	state.add_track_effect(ev.id, track.id, CodaTrackEffect.Type.GAIN)
	state.structure_changed.emit()
	if not section.visible:
		push_error("fx section should stay visible after structure_changed")
		return 1
	if not section.is_scope_panel_visible(CodaInspectorEffectsSectionScript.FxScope.TIMELINE_TRACK):
		push_error("track fx panel should stay visible after structure_changed")
		return 1
	section.set_fx_scope(CodaInspectorEffectsSectionScript.FxScope.NONE)
	if section.visible:
		push_error("fx section should hide when scope cleared")
		return 1
	return 0


static func _test_reverb_damping_build() -> int:
	var eff: CodaTrackEffect = CodaTrackEffectScript.new()
	eff.type = CodaTrackEffect.Type.REVERB
	eff.params = {"damp": 0.35, "room_size": 0.6}
	var ae: AudioEffect = CodaEffectCatalogScript.build_audio_effect_from_slot(eff)
	if ae == null or not (ae is AudioEffectReverb):
		push_error("reverb build failed")
		return 1
	var rev := ae as AudioEffectReverb
	if not is_equal_approx(rev.damping, 0.35):
		push_error("reverb damping alias")
		return 1
	return 0
