@tool
class_name CodaSampleProject
extends RefCounted

## Constructs a small onboarding project entirely in memory:
##   - "Music" bus group with two children
##   - Three sample events: ui/click (single sound), ambience/forest (random),
##     gameplay/ducking_demo (blend driven by a parameter)
##   - One snapshot ("Quiet") that lowers SFX
##   - One bank ("Demo") containing all events
##
## Audio paths are deliberately left blank so the user picks their own assets;
## the project still parses, opens cleanly, and demonstrates every panel.

const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaBrowserNodeScript := preload("res://addons/nexus_coda/editor/browser/coda_browser_node.gd")
const CodaEventParameterScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_event_parameter.gd"
)
const CodaEventGraphScript := preload("res://addons/nexus_coda/editor/browser/coda_event_graph.gd")
const CodaEventGraphNodeDataScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_event_graph_node_data.gd"
)
const CodaEventGraphEdgeScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_event_graph_edge.gd"
)
const CodaModulationScript := preload("res://addons/nexus_coda/editor/browser/coda_modulation.gd")
const CodaBusScript := preload("res://addons/nexus_coda/editor/browser/coda_bus.gd")
const CodaSnapshotScript := preload("res://addons/nexus_coda/editor/browser/coda_snapshot.gd")
const CodaBankScript := preload("res://addons/nexus_coda/editor/browser/coda_bank.gd")


static func build() -> CodaState:
	var state: CodaState = CodaStateScript.new()
	state.clear_to_empty_project()
	_seed_bus_tree(state)
	var ui_event: CodaBrowserNode = _seed_ui_event(state)
	var amb_event: CodaBrowserNode = _seed_ambience_event(state)
	var duck_event: CodaBrowserNode = _seed_ducking_event(state)
	_seed_snapshot(state)
	_seed_bank(state, [ui_event, amb_event, duck_event])
	return state


static func _seed_bus_tree(state: CodaState) -> void:
	# Master/SFX/Music/UI/Voice already exist via make_default_master(); add the leaves.
	var sfx: CodaBus = state.bus_root.find_by_name("SFX")
	var music: CodaBus = state.bus_root.find_by_name("Music")
	if sfx != null:
		state.add_child_bus(sfx.id, "Footsteps")
		state.add_child_bus(sfx.id, "Ambience")
	if music != null:
		state.add_child_bus(music.id, "Stems")


static func _ensure_event_under(
	state: CodaState, folder_path: PackedStringArray, event_name: String
) -> CodaBrowserNode:
	var parent_id: String = state.events_root.id
	for segment in folder_path:
		var found_id: String = ""
		for child in state.events_root.find_by_id(parent_id).children:
			if child.is_folder() and child.name == segment:
				found_id = child.id
				break
		if found_id.is_empty():
			var folder: CodaBrowserNode = state.add_events_folder(parent_id, segment)
			parent_id = folder.id
		else:
			parent_id = found_id
	return state.add_events_event(parent_id, event_name)


static func _seed_ui_event(state: CodaState) -> CodaBrowserNode:
	var ev: CodaBrowserNode = _ensure_event_under(state, ["ui"], "click")
	ev.event_graph = CodaEventGraphScript.new()
	var trig: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.TRIGGER
	)
	trig.graph_position = Vector2(40, 60)
	ev.event_graph.add_node(trig)
	var snd: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.SOUND
	)
	snd.graph_position = Vector2(280, 60)
	snd.properties["audio_path"] = ""
	snd.properties["volume_db"] = -3.0
	ev.event_graph.add_node(snd)
	ev.event_graph.add_edge(trig.id, snd.id)
	var ui_bus: CodaBus = state.bus_root.find_by_name("UI")
	if ui_bus != null:
		ev.event_output_bus_id = ui_bus.id
	return ev


static func _seed_ambience_event(state: CodaState) -> CodaBrowserNode:
	var ev: CodaBrowserNode = _ensure_event_under(state, ["ambience"], "forest")
	ev.event_graph = CodaEventGraphScript.new()
	var trig: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.TRIGGER
	)
	trig.graph_position = Vector2(40, 60)
	ev.event_graph.add_node(trig)
	var rnd: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.RANDOM
	)
	rnd.graph_position = Vector2(280, 60)
	ev.event_graph.add_node(rnd)
	ev.event_graph.add_edge(trig.id, rnd.id)
	for i in 3:
		var snd: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
			CodaEventGraphNodeDataScript.Kind.SOUND
		)
		snd.graph_position = Vector2(560, 60 + 110.0 * i)
		snd.properties["audio_path"] = ""
		snd.properties["volume_db"] = -6.0
		snd.properties["loop"] = false
		ev.event_graph.add_node(snd)
		ev.event_graph.add_edge(rnd.id, snd.id)
	var amb_bus: CodaBus = state.bus_root.find_by_name("Ambience")
	if amb_bus != null:
		ev.event_output_bus_id = amb_bus.id
	return ev


static func _seed_ducking_event(state: CodaState) -> CodaBrowserNode:
	var ev: CodaBrowserNode = _ensure_event_under(state, ["gameplay"], "ducking_demo")
	var intensity := CodaEventParameterScript.new()
	intensity.param_name = "intensity"
	intensity.param_type = CodaEventParameterScript.ParamType.FLOAT
	intensity.default_value = 0.0
	intensity.min_value = 0.0
	intensity.max_value = 1.0
	intensity.smoothing_ms = 60.0
	intensity.unit_hint = ""
	ev.event_parameters.append(intensity)

	ev.event_graph = CodaEventGraphScript.new()
	var trig: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.TRIGGER
	)
	trig.graph_position = Vector2(40, 60)
	ev.event_graph.add_node(trig)

	var blend: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.BLEND
	)
	blend.graph_position = Vector2(280, 60)
	blend.properties["parameter_id"] = intensity.id
	ev.event_graph.add_node(blend)
	ev.event_graph.add_edge(trig.id, blend.id)

	var calm: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.SOUND
	)
	calm.graph_position = Vector2(560, 0)
	calm.properties["audio_path"] = ""
	calm.properties["volume_db"] = -4.0
	ev.event_graph.add_node(calm)
	ev.event_graph.add_edge(blend.id, calm.id)

	var loud: CodaEventGraphNodeData = CodaEventGraphNodeDataScript.new(
		CodaEventGraphNodeDataScript.Kind.SOUND
	)
	loud.graph_position = Vector2(560, 140)
	loud.properties["audio_path"] = ""
	loud.properties["volume_db"] = 0.0
	ev.event_graph.add_node(loud)
	ev.event_graph.add_edge(blend.id, loud.id)

	var mod: CodaModulation = CodaModulationScript.new()
	mod.source_param_id = intensity.id
	mod.target_node_id = loud.id
	mod.target_property = CodaModulationScript.TargetProperty.SOUND_VOLUME_DB
	mod.range_in_min = 0.0
	mod.range_in_max = 1.0
	mod.range_out_min = -12.0
	mod.range_out_max = 0.0
	ev.event_modulations.append(mod)

	var music_bus: CodaBus = state.bus_root.find_by_name("Music")
	if music_bus != null:
		ev.event_output_bus_id = music_bus.id
	return ev


static func _seed_snapshot(state: CodaState) -> void:
	var snap: CodaSnapshot = state.add_snapshot("Quiet")
	snap.blend_ms = 250
	var sfx_bus: CodaBus = state.bus_root.find_by_name("SFX")
	if sfx_bus != null:
		snap.bus_overrides[sfx_bus.id] = {"volume_db": -12.0, "mute": false}
	var music_bus: CodaBus = state.bus_root.find_by_name("Music")
	if music_bus != null:
		snap.bus_overrides[music_bus.id] = {"volume_db": -6.0, "mute": false}


static func _seed_bank(state: CodaState, events: Array) -> void:
	var bank: CodaBank = state.add_bank("Demo")
	for ev_variant in events:
		var ev: CodaBrowserNode = ev_variant as CodaBrowserNode
		if ev != null:
			bank.add_event_id(ev.id)
