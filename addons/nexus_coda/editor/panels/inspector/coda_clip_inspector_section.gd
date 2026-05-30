@tool
class_name CodaClipInspectorSection
extends VBoxContainer

## Timeline clip properties: fade, volume, pitch.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaTimelineCommandsScript := preload(
	"res://addons/nexus_coda/editor/panels/timeline/coda_timeline_commands.gd"
)

signal clip_properties_changed
signal clip_fade_edit_started
signal clip_fade_edit_committed

var _project: CodaState = null
var _event_id: String = ""
var _clip_id: String = ""
var _suppress_writeback: bool = false
var _fade_inspector_edit_active: bool = false
var _fade_spins: Array[SpinBox] = []

var _fade_in_spin: SpinBox
var _fade_out_spin: SpinBox
var _fade_in_curve_spin: SpinBox
var _fade_out_curve_spin: SpinBox
var _volume_spin: SpinBox
var _pitch_spin: SpinBox


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)


func _ready() -> void:
	_fade_in_spin = _add_labeled_spin("Fade In (s)", 0.0, 600.0, 0.01, 3)
	_fade_out_spin = _add_labeled_spin("Fade Out (s)", 0.0, 600.0, 0.01, 3)
	_fade_in_curve_spin = _add_labeled_spin("Fade In Curve", 0.0, 1.0, 0.01, 2)
	_fade_out_curve_spin = _add_labeled_spin("Fade Out Curve", 0.0, 1.0, 0.01, 2)
	_volume_spin = _add_labeled_spin("Volume (dB)", -80.0, 24.0, 0.1, 1)
	_pitch_spin = _add_labeled_spin("Pitch", 0.01, 4.0, 0.01, 2)

	_fade_in_spin.value_changed.connect(_on_fade_in_changed)
	_fade_out_spin.value_changed.connect(_on_fade_out_changed)
	_fade_in_curve_spin.value_changed.connect(_on_fade_in_curve_changed)
	_fade_out_curve_spin.value_changed.connect(_on_fade_out_curve_changed)
	_volume_spin.value_changed.connect(_on_volume_changed)
	_pitch_spin.value_changed.connect(_on_pitch_changed)
	_fade_spins = [_fade_in_spin, _fade_out_spin, _fade_in_curve_spin, _fade_out_curve_spin]
	for spin in _fade_spins:
		spin.get_line_edit().gui_input.connect(_on_fade_spin_gui_input)
		spin.get_line_edit().focus_exited.connect(_on_fade_spin_focus_exited)


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.project_dirty.is_connected(_sync_from_clip):
			_project.project_dirty.disconnect(_sync_from_clip)
	_project = project
	if _project != null:
		_project.project_dirty.connect(_sync_from_clip)
	if not _clip_id.is_empty():
		_sync_from_clip()


func set_clip_context(event_id: String, clip_id: String) -> void:
	_event_id = event_id.strip_edges()
	_clip_id = clip_id.strip_edges()
	_sync_from_clip()


func _add_labeled_spin(
	label_text: String, min_v: float, max_v: float, step: float, decimals: int
) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(108, 0)
	label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.custom_minimum_size = Vector2(0, 28)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.rounded = decimals <= 0
	if decimals > 0:
		spin.custom_arrow_step = step
	row.add_child(spin)
	return spin


func _resolve_clip() -> CodaTimelineClip:
	if _project == null or _event_id.is_empty() or _clip_id.is_empty():
		return null
	var node: CodaBrowserNode = _project.events_root.find_by_id(_event_id)
	if node == null or node.event_timeline == null:
		return null
	var info: Dictionary = node.event_timeline.find_clip(_clip_id)
	if info.is_empty():
		return null
	return info.get("clip") as CodaTimelineClip


func _resolve_timeline() -> CodaEventTimeline:
	if _project == null or _event_id.is_empty():
		return null
	var node: CodaBrowserNode = _project.events_root.find_by_id(_event_id)
	if node == null:
		return null
	return node.event_timeline


func _sync_from_clip() -> void:
	var clip: CodaTimelineClip = _resolve_clip()
	if clip == null:
		return
	_suppress_writeback = true
	_fade_in_spin.value = clip.fade_in_seconds
	_fade_out_spin.value = clip.fade_out_seconds
	_fade_in_curve_spin.value = clip.fade_in_curve
	_fade_out_curve_spin.value = clip.fade_out_curve
	_volume_spin.value = clip.volume_db
	_pitch_spin.value = clip.pitch_scale
	_suppress_writeback = false


func _on_fade_in_changed(v: float) -> void:
	if _suppress_writeback:
		return
	_apply_fades(v, _fade_out_spin.value, -1.0, -1.0)


func _on_fade_out_changed(v: float) -> void:
	if _suppress_writeback:
		return
	_apply_fades(_fade_in_spin.value, v, -1.0, -1.0)


func _on_fade_in_curve_changed(v: float) -> void:
	if _suppress_writeback:
		return
	_apply_fades(_fade_in_spin.value, _fade_out_spin.value, v, -1.0)


func _on_fade_out_curve_changed(v: float) -> void:
	if _suppress_writeback:
		return
	_apply_fades(_fade_in_spin.value, _fade_out_spin.value, -1.0, v)


func _on_fade_spin_gui_input(event: InputEvent) -> void:
	if _suppress_writeback:
		return
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _fade_inspector_edit_active:
		return
	_fade_inspector_edit_active = true
	clip_fade_edit_started.emit()


func _on_fade_spin_focus_exited() -> void:
	if not _fade_inspector_edit_active:
		return
	if _any_fade_spin_focused():
		return
	_fade_inspector_edit_active = false
	clip_fade_edit_committed.emit()


func _any_fade_spin_focused() -> bool:
	for spin in _fade_spins:
		if spin.get_line_edit().has_focus():
			return true
	return false


func _apply_fades(
	fade_in: float, fade_out: float, fade_in_curve: float, fade_out_curve: float
) -> void:
	var timeline: CodaEventTimeline = _resolve_timeline()
	if timeline == null:
		return
	CodaTimelineCommandsScript.set_clip_fades(
		timeline, _clip_id, fade_in, fade_out, fade_in_curve, fade_out_curve
	)
	if _project != null:
		_project.project_dirty.emit()
	clip_properties_changed.emit()
	_sync_from_clip()


func _on_volume_changed(v: float) -> void:
	if _suppress_writeback:
		return
	var timeline: CodaEventTimeline = _resolve_timeline()
	if timeline == null:
		return
	CodaTimelineCommandsScript.set_clip_volume_db(timeline, _clip_id, v)
	if _project != null:
		_project.project_dirty.emit()
	clip_properties_changed.emit()


func _on_pitch_changed(v: float) -> void:
	if _suppress_writeback:
		return
	var timeline: CodaEventTimeline = _resolve_timeline()
	if timeline == null:
		return
	CodaTimelineCommandsScript.set_clip_pitch_scale(timeline, _clip_id, v)
	if _project != null:
		_project.project_dirty.emit()
	clip_properties_changed.emit()
