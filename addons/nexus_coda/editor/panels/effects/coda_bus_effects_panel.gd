@tool
class_name CodaBusEffectsPanel
extends VBoxContainer

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const ChainScript := preload("res://addons/nexus_coda/editor/panels/effects/coda_effects_chain_view.gd")

var _project: CodaState = null
var _mixer: CodaMixerPanel = null
var _empty: Label
var _chain: CodaEffectsChainView
var _bus_id: String = ""


func _ready() -> void:
	name = "Bus FX"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)

	_empty = Label.new()
	_empty.text = "Select a bus in the Mixer panel."
	_empty.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_empty)

	_chain = ChainScript.new()
	_chain.visible = false
	_chain.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chain.set_footer_text(
		"These effects are mirrored to Godot's AudioServer on the selected bus when the mixer syncs."
	)
	add_child(_chain)
	_chain.effect_add_requested.connect(_on_chain_add)
	_chain.effect_remove_requested.connect(_on_chain_remove)
	_chain.effect_move_requested.connect(_on_chain_move)
	_chain.effect_param_changed.connect(_on_chain_param)
	_chain.effect_bypass_changed.connect(_on_chain_bypass)


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_refresh):
			_project.structure_changed.disconnect(_refresh)
		if _project.project_dirty.is_connected(_refresh):
			_project.project_dirty.disconnect(_refresh)
	_project = project
	if _project != null:
		_project.structure_changed.connect(_refresh)
		_project.project_dirty.connect(_refresh)
	_refresh()


func attach_mixer_panel(panel: CodaMixerPanel) -> void:
	if _mixer != null and is_instance_valid(_mixer):
		if _mixer.bus_selection_changed.is_connected(_on_bus_selection_changed):
			_mixer.bus_selection_changed.disconnect(_on_bus_selection_changed)
	_mixer = panel
	if _mixer != null:
		_mixer.bus_selection_changed.connect(_on_bus_selection_changed)
	_refresh()


func _on_bus_selection_changed(bus_id: String) -> void:
	_bus_id = bus_id
	_refresh()


func _resolve_bus() -> CodaBus:
	if _project == null or _project.bus_root == null or _bus_id.is_empty():
		return null
	return _project.bus_root.find_by_id(_bus_id)


func _refresh() -> void:
	var bus: CodaBus = _resolve_bus()
	if bus == null:
		_empty.visible = true
		_chain.visible = false
		return
	_empty.visible = false
	_chain.visible = true
	_chain.set_chain_title("Bus: %s" % bus.bus_name)
	_chain.bind_effects_array(bus.effects)


func _on_chain_add(effect_type: int) -> void:
	if _project == null:
		return
	_project.add_bus_effect(_bus_id, effect_type as CodaTrackEffect.Type)


func _on_chain_remove(effect_id: String) -> void:
	if _project == null:
		return
	_project.remove_bus_effect(_bus_id, effect_id)


func _on_chain_move(from_i: int, to_i: int) -> void:
	if _project == null:
		return
	_project.move_bus_effect(_bus_id, from_i, to_i)


func _on_chain_param(effect_id: String, key: String, value: float) -> void:
	if _project == null:
		return
	_project.set_bus_effect_params(_bus_id, effect_id, {key: value})


func _on_chain_bypass(effect_id: String, on: bool) -> void:
	if _project == null:
		return
	_project.set_bus_effect_bypass(_bus_id, effect_id, on)
