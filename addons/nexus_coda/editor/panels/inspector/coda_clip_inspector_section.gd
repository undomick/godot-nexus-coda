@tool
class_name CodaClipInspectorSection
extends VBoxContainer

## Timeline clip properties in a collapsible card: fade, volume, pitch.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CollapsibleCardScript := preload(
	"res://addons/nexus_coda/editor/theme/coda_collapsible_inspector_card.gd"
)
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

var _card: CodaCollapsibleInspectorCard
var _params_host: VBoxContainer
var _fade_rows: Array[Dictionary] = []

var _fade_in_row: Dictionary = {}
var _fade_out_row: Dictionary = {}
var _fade_in_curve_row: Dictionary = {}
var _fade_out_curve_row: Dictionary = {}
var _volume_row: Dictionary = {}
var _pitch_row: Dictionary = {}


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_card = CollapsibleCardScript.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(_card)


func _ready() -> void:
	_params_host = _card.get_body()
	_fade_in_row = _add_float_param(
		"Fade In (%)", 0.0, 100.0, 0.1, 1, _on_fade_in_changed, true
	)
	_fade_out_row = _add_float_param(
		"Fade Out (%)", 0.0, 100.0, 0.1, 1, _on_fade_out_changed, true
	)
	_fade_in_curve_row = _add_float_param(
		"Fade In Curve", 0.0, 1.0, 0.01, 2, _on_fade_in_curve_changed, true
	)
	_fade_out_curve_row = _add_float_param(
		"Fade Out Curve", 0.0, 1.0, 0.01, 2, _on_fade_out_curve_changed, true
	)
	_volume_row = _add_float_param(
		"Volume (dB)", -80.0, 24.0, 0.1, 1, _on_volume_changed, false
	)
	_pitch_row = _add_float_param(
		"Pitch", 0.01, 4.0, 0.01, 2, _on_pitch_changed, false
	)
	_fade_rows = [
		_fade_in_row,
		_fade_out_row,
		_fade_in_curve_row,
		_fade_out_curve_row,
	]
	if not _clip_id.is_empty():
		_sync_from_clip()


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
	_update_header()
	_sync_from_clip()


func _add_float_param(
	label_text: String,
	min_v: float,
	max_v: float,
	step: float,
	decimals: int,
	on_changed: Callable,
	track_fade_edit: bool
) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_params_host.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(96, 0)
	label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = maxf(0.001, step)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_stretch_ratio = 1.0
	row.add_child(slider)

	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(52, 0)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_END
	edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(edit)

	var binding := {
		"slider": slider,
		"edit": edit,
		"min": min_v,
		"max": max_v,
		"decimals": decimals,
		"suppress": false,
	}

	var apply_value := func(raw: Variant) -> void:
		if bool(binding.suppress):
			return
		var v: float = clampf(float(raw), min_v, max_v)
		binding.suppress = true
		slider.value = v
		edit.text = _format_value(v, decimals)
		binding.suppress = false
		if not _suppress_writeback:
			on_changed.call(v)

	slider.value_changed.connect(func(v: float) -> void: apply_value.call(v))
	edit.text_submitted.connect(func(t: String) -> void: apply_value.call(_parse_value(t, slider.value)))
	edit.focus_exited.connect(func() -> void: apply_value.call(_parse_value(edit.text, slider.value)))

	if track_fade_edit:
		slider.gui_input.connect(_on_fade_control_gui_input)
		edit.gui_input.connect(_on_fade_control_gui_input)
		edit.focus_exited.connect(_on_fade_edit_focus_exited)

	return binding


func _set_row_value(row: Dictionary, value: float) -> void:
	if row.is_empty():
		return
	row.suppress = true
	var slider: HSlider = row.slider as HSlider
	var edit: LineEdit = row.edit as LineEdit
	var decimals: int = int(row.decimals)
	slider.value = clampf(value, float(row.min), float(row.max))
	edit.text = _format_value(slider.value, decimals)
	row.suppress = false


func _row_value(row: Dictionary) -> float:
	if row.is_empty():
		return 0.0
	return float((row.slider as HSlider).value)


func _update_header() -> void:
	var clip: CodaTimelineClip = _resolve_clip()
	if clip == null:
		_card.set_header("Clip", "")
		return
	var clip_label: String = (
		clip.audio_path.get_file() if not clip.audio_path.is_empty() else "Clip"
	)
	var track_name: String = ""
	var info: Dictionary = _resolve_clip_info()
	var track: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
	if track != null:
		track_name = track.track_name
	var event_name: String = ""
	if _project != null and not _event_id.is_empty():
		var ev: CodaBrowserNode = _project.events_root.find_by_id(_event_id)
		if ev != null:
			event_name = ev.name
	var crumbs: PackedStringArray = PackedStringArray()
	if not track_name.is_empty():
		crumbs.append(track_name)
	if not event_name.is_empty():
		crumbs.append(event_name)
	_card.set_header("Clip: %s" % clip_label, " · ".join(crumbs))


func _resolve_clip_info() -> Dictionary:
	if _project == null or _event_id.is_empty() or _clip_id.is_empty():
		return {}
	var node: CodaBrowserNode = _project.events_root.find_by_id(_event_id)
	if node == null or node.event_timeline == null:
		return {}
	return node.event_timeline.find_clip(_clip_id) as Dictionary


func _resolve_clip() -> CodaTimelineClip:
	var info: Dictionary = _resolve_clip_info()
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
	_update_header()
	_suppress_writeback = true
	var duration: float = maxf(0.0, clip.duration_seconds)
	_update_fade_slider_limits(duration, clip.fade_in_seconds, clip.fade_out_seconds)
	_set_row_value(_fade_in_row, _fade_seconds_to_percent(clip.fade_in_seconds, duration))
	_set_row_value(_fade_out_row, _fade_seconds_to_percent(clip.fade_out_seconds, duration))
	_set_row_value(_fade_in_curve_row, clip.fade_in_curve)
	_set_row_value(_fade_out_curve_row, clip.fade_out_curve)
	_set_row_value(_volume_row, clip.volume_db)
	_set_row_value(_pitch_row, clip.pitch_scale)
	_suppress_writeback = false


func _update_fade_slider_limits(
	duration: float, fade_in_seconds: float, fade_out_seconds: float
) -> void:
	if _fade_in_row.is_empty() or _fade_out_row.is_empty():
		return
	var max_in_pct: float = _fade_seconds_to_percent(
		maxf(0.0, duration - fade_out_seconds), duration
	)
	var max_out_pct: float = _fade_seconds_to_percent(
		maxf(0.0, duration - fade_in_seconds), duration
	)
	var fade_in_slider: HSlider = _fade_in_row.slider as HSlider
	var fade_out_slider: HSlider = _fade_out_row.slider as HSlider
	fade_in_slider.max_value = maxf(0.0, max_in_pct)
	fade_out_slider.max_value = maxf(0.0, max_out_pct)
	_fade_in_row.max = fade_in_slider.max_value
	_fade_out_row.max = fade_out_slider.max_value


static func _fade_seconds_to_percent(seconds: float, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(seconds / duration * 100.0, 0.0, 100.0)


static func _fade_percent_to_seconds(percent: float, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(percent / 100.0 * duration, 0.0, duration)


func _on_fade_in_changed(_v: float) -> void:
	_apply_fades(-1.0, -1.0, -1.0, -1.0)


func _on_fade_out_changed(_v: float) -> void:
	_apply_fades(-1.0, -1.0, -1.0, -1.0)


func _on_fade_in_curve_changed(_v: float) -> void:
	_apply_fades(-1.0, -1.0, -1.0, -1.0)


func _on_fade_out_curve_changed(_v: float) -> void:
	_apply_fades(-1.0, -1.0, -1.0, -1.0)


func _on_fade_control_gui_input(event: InputEvent) -> void:
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


func _on_fade_edit_focus_exited() -> void:
	if not _fade_inspector_edit_active:
		return
	if _any_fade_edit_focused():
		return
	_fade_inspector_edit_active = false
	clip_fade_edit_committed.emit()


func _any_fade_edit_focused() -> bool:
	for row in _fade_rows:
		var edit: LineEdit = row.get("edit") as LineEdit
		if edit != null and edit.has_focus():
			return true
	for row in _fade_rows:
		var slider: HSlider = row.get("slider") as HSlider
		if slider != null and slider.has_focus():
			return true
	return false


func _apply_fades(
	fade_in: float, fade_out: float, fade_in_curve: float, fade_out_curve: float
) -> void:
	var timeline: CodaEventTimeline = _resolve_timeline()
	var clip: CodaTimelineClip = _resolve_clip()
	if timeline == null or clip == null:
		return
	var duration: float = maxf(0.0, clip.duration_seconds)
	var fin: float
	var fout: float
	if fade_in < 0.0:
		fin = _fade_percent_to_seconds(_row_value(_fade_in_row), duration)
	else:
		fin = fade_in
	if fade_out < 0.0:
		fout = _fade_percent_to_seconds(_row_value(_fade_out_row), duration)
	else:
		fout = fade_out
	var fic: float = _row_value(_fade_in_curve_row) if fade_in_curve < 0.0 else fade_in_curve
	var foc: float = _row_value(_fade_out_curve_row) if fade_out_curve < 0.0 else fade_out_curve
	CodaTimelineCommandsScript.set_clip_fades(timeline, _clip_id, fin, fout, fic, foc)
	if _project != null:
		_project.project_dirty.emit()
	clip_properties_changed.emit()
	_sync_from_clip()


func _on_volume_changed(v: float) -> void:
	var timeline: CodaEventTimeline = _resolve_timeline()
	if timeline == null:
		return
	CodaTimelineCommandsScript.set_clip_volume_db(timeline, _clip_id, v)
	if _project != null:
		_project.project_dirty.emit()
	clip_properties_changed.emit()


func _on_pitch_changed(v: float) -> void:
	var timeline: CodaEventTimeline = _resolve_timeline()
	if timeline == null:
		return
	CodaTimelineCommandsScript.set_clip_pitch_scale(timeline, _clip_id, v)
	if _project != null:
		_project.project_dirty.emit()
	clip_properties_changed.emit()


static func _format_value(value: float, decimals: int) -> String:
	if decimals <= 0:
		return str(int(round(value)))
	return ("%0.*f" % [decimals, value])


static func _parse_value(text: String, fallback: float) -> float:
	var t: String = text.strip_edges()
	if t.is_empty():
		return fallback
	if t.is_valid_float():
		return float(t)
	return fallback
