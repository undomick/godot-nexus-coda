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


func _init() -> void:
	var failed: int = 0
	failed += _test_layout_store()
	failed += _test_bank_rename_duplicate()
	failed += _test_event_duplicate_ids()
	failed += _test_delete_event_clears_banks()
	failed += _test_marker_ui()
	failed += _test_nan_json_save()
	failed += _test_project_serializer_roundtrip()
	failed += _test_graph_parallel_split()
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
