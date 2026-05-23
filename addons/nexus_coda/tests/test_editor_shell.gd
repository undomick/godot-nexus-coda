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


func _init() -> void:
	var failed: int = 0
	failed += _test_layout_store()
	failed += _test_bank_rename_duplicate()
	failed += _test_event_duplicate_ids()
	failed += _test_marker_ui()
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
