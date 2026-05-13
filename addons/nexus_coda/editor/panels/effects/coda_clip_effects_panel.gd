@tool
class_name CodaClipEffectsPanel
extends VBoxContainer

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const ChainScript := preload("res://addons/nexus_coda/editor/panels/effects/coda_effects_chain_view.gd")

var _project: CodaState = null
var _timeline: CodaTimelinePanel = null
var _empty: Label
var _chain: CodaEffectsChainView
var _event_id: String = ""
var _clip_id: String = ""


func _ready() -> void:
	name = "Clip FX"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)

	_empty = Label.new()
	_empty.text = "Select a clip on the timeline."
	_empty.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_empty)

	_chain = ChainScript.new()
	_chain.visible = false
	_chain.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chain.set_footer_text(
		"Clip chains are saved with the event; runtime clip DSP routing is planned as a later phase."
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


func attach_timeline_panel(panel: CodaTimelinePanel) -> void:
	if _timeline != null and is_instance_valid(_timeline):
		if _timeline.clip_selection_changed.is_connected(_on_clip_selection_changed):
			_timeline.clip_selection_changed.disconnect(_on_clip_selection_changed)
	_timeline = panel
	if _timeline != null:
		_timeline.clip_selection_changed.connect(_on_clip_selection_changed)
	_refresh()


func _on_clip_selection_changed(event_id: String, clip_id: String) -> void:
	_event_id = event_id
	_clip_id = clip_id
	_refresh()


func _resolve_clip() -> CodaTimelineClip:
	if _project == null or _event_id.is_empty() or _clip_id.is_empty():
		return null
	var node: CodaBrowserNode = _project.events_root.find_by_id(_event_id)
	if node == null or node.kind != CodaBrowserNode.Kind.EVENT or node.event_timeline == null:
		return null
	var info: Dictionary = node.event_timeline.find_clip(_clip_id)
	if info.is_empty():
		return null
	return info.get("clip") as CodaTimelineClip


func _refresh() -> void:
	var clip: CodaTimelineClip = _resolve_clip()
	if clip == null or _clip_id.is_empty():
		_empty.visible = true
		_chain.visible = false
		return
	_empty.visible = false
	_chain.visible = true
	var label: String = clip.audio_path.get_file() if not clip.audio_path.is_empty() else "Clip"
	_chain.set_chain_title("Clip: %s" % label)
	_chain.bind_effects_array(clip.effects)


func _on_chain_add(effect_type: int) -> void:
	if _project == null:
		return
	_project.add_clip_effect(_event_id, _clip_id, effect_type as CodaTrackEffect.Type)


func _on_chain_remove(effect_id: String) -> void:
	if _project == null:
		return
	_project.remove_clip_effect(_event_id, _clip_id, effect_id)


func _on_chain_move(from_i: int, to_i: int) -> void:
	if _project == null:
		return
	_project.move_clip_effect(_event_id, _clip_id, from_i, to_i)


func _on_chain_param(effect_id: String, key: String, value: float) -> void:
	if _project == null:
		return
	_project.set_clip_effect_params(_event_id, _clip_id, effect_id, {key: value})


func _on_chain_bypass(effect_id: String, on: bool) -> void:
	if _project == null:
		return
	_project.set_clip_effect_bypass(_event_id, _clip_id, effect_id, on)
