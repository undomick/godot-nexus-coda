@tool
class_name CodaTimelineToolbar
extends RefCounted

## Timeline toolbar controls — builds into a parent [HBoxContainer] and emits action signals.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

signal add_clip_pressed
signal split_clip_pressed
signal add_marker_pressed
signal snap_picked(mode: int)
signal bpm_changed(value: float)
signal loop_toggled(on: bool)
signal length_changed(value: float)
signal fit_length_pressed
signal zoom_fit_pressed
signal track_row_height_changed(value: float)
signal switch_mode_pressed

var root: HBoxContainer
var add_clip_btn: Button
var split_clip_btn: Button
var add_marker_btn: Button
var snap_picker: OptionButton
var bpm_spin: SpinBox
var loop_toggle: CheckBox
var length_spin: SpinBox
var fit_length_btn: Button
var zoom_fit_btn: Button
var track_row_spin: SpinBox
var switch_mode_btn: Button

var _suppress_writeback: bool = false
var _suppress_track_row_spin: bool = false


func build(parent: Control) -> HBoxContainer:
	root = HBoxContainer.new()
	root.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	parent.add_child(root)

	add_clip_btn = Button.new()
	add_clip_btn.text = "+ Clip"
	add_clip_btn.tooltip_text = (
		"Add an empty clip on the selected track (highlighted lane / track header) at the playhead"
	)
	add_clip_btn.pressed.connect(func() -> void: add_clip_pressed.emit())
	root.add_child(add_clip_btn)

	split_clip_btn = Button.new()
	split_clip_btn.text = "Split"
	split_clip_btn.tooltip_text = (
		"Split the selected clip at the playhead (clip must be selected; playhead inside clip)"
	)
	split_clip_btn.pressed.connect(func() -> void: split_clip_pressed.emit())
	root.add_child(split_clip_btn)

	add_marker_btn = Button.new()
	add_marker_btn.text = "+ Marker"
	add_marker_btn.tooltip_text = "Add a marker at the current playhead"
	add_marker_btn.pressed.connect(func() -> void: add_marker_pressed.emit())
	root.add_child(add_marker_btn)

	root.add_child(VSeparator.new())

	var snap_label := Label.new()
	snap_label.text = "Snap:"
	snap_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	snap_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	root.add_child(snap_label)

	snap_picker = OptionButton.new()
	snap_picker.add_item("None", CodaTimelineView.SnapMode.NONE)
	snap_picker.add_item("0.1 s", CodaTimelineView.SnapMode.TENTHS)
	snap_picker.add_item("Bars/Beats", CodaTimelineView.SnapMode.BARS_BEATS)
	snap_picker.item_selected.connect(_on_snap_picked)
	root.add_child(snap_picker)

	var bpm_label := Label.new()
	bpm_label.text = "BPM:"
	bpm_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	bpm_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	root.add_child(bpm_label)

	bpm_spin = SpinBox.new()
	bpm_spin.min_value = 0.0
	bpm_spin.max_value = 999.0
	bpm_spin.step = 1.0
	bpm_spin.tooltip_text = "0 disables the bars/beats grid"
	bpm_spin.value_changed.connect(_on_bpm_changed)
	root.add_child(bpm_spin)

	loop_toggle = CheckBox.new()
	loop_toggle.text = "Loop"
	loop_toggle.tooltip_text = "Enable the loop region inside the timeline"
	loop_toggle.toggled.connect(_on_loop_toggled)
	root.add_child(loop_toggle)

	root.add_child(VSeparator.new())

	var len_lbl := Label.new()
	len_lbl.text = "Length (s):"
	len_lbl.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	len_lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	root.add_child(len_lbl)

	length_spin = SpinBox.new()
	length_spin.min_value = 0.5
	length_spin.max_value = 3600.0
	length_spin.step = 0.5
	length_spin.tooltip_text = "Timeline length in seconds (session end). Clips cannot extend past this."
	length_spin.value_changed.connect(_on_length_changed)
	root.add_child(length_spin)

	fit_length_btn = Button.new()
	fit_length_btn.text = "Fit length"
	fit_length_btn.tooltip_text = "Set length to the end of the last clip/marker (plus a small margin)"
	fit_length_btn.pressed.connect(func() -> void: fit_length_pressed.emit())
	root.add_child(fit_length_btn)

	zoom_fit_btn = Button.new()
	zoom_fit_btn.text = "Zoom to fit"
	zoom_fit_btn.tooltip_text = "Zoom the timeline view so the full session length fits horizontally"
	zoom_fit_btn.pressed.connect(func() -> void: zoom_fit_pressed.emit())
	root.add_child(zoom_fit_btn)

	root.add_child(VSeparator.new())

	var row_h_lbl := Label.new()
	row_h_lbl.text = "Row px:"
	row_h_lbl.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	row_h_lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	root.add_child(row_h_lbl)

	track_row_spin = SpinBox.new()
	track_row_spin.min_value = CodaTimelineView.MIN_TRACK_ROW_HEIGHT
	track_row_spin.max_value = CodaTimelineView.MAX_TRACK_ROW_HEIGHT
	track_row_spin.step = 2.0
	track_row_spin.value = CodaTimelineView.DEFAULT_TRACK_ROW_HEIGHT
	track_row_spin.tooltip_text = (
		"Pixel height of each track row (header + lane), like a DAW track height control"
	)
	track_row_spin.value_changed.connect(_on_track_row_height_changed)
	root.add_child(track_row_spin)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	switch_mode_btn = Button.new()
	switch_mode_btn.text = "Switch to Graph"
	switch_mode_btn.tooltip_text = "Use the Event-Graph authoring model instead of the timeline"
	switch_mode_btn.pressed.connect(func() -> void: switch_mode_pressed.emit())
	root.add_child(switch_mode_btn)

	return root


func sync_from_timeline(timeline: CodaEventTimeline, snap_mode: int) -> void:
	if timeline == null:
		return
	_suppress_writeback = true
	loop_toggle.button_pressed = timeline.loop_enabled
	bpm_spin.value = timeline.tempo_bpm
	length_spin.value = timeline.length_seconds
	for i in snap_picker.item_count:
		if snap_picker.get_item_id(i) == snap_mode:
			snap_picker.select(i)
			break
	_suppress_writeback = false


func sync_length_spin(value: float) -> void:
	_suppress_writeback = true
	length_spin.value = value
	_suppress_writeback = false


func sync_track_row_spin_to_view(view: CodaTimelineView) -> void:
	if view == null:
		return
	_suppress_track_row_spin = true
	track_row_spin.min_value = CodaTimelineView.MIN_TRACK_ROW_HEIGHT
	track_row_spin.max_value = CodaTimelineView.MAX_TRACK_ROW_HEIGHT
	track_row_spin.value = view.get_track_row_height()
	_suppress_track_row_spin = false


func consume_track_row_height_change(value: float) -> bool:
	if _suppress_track_row_spin:
		return false
	track_row_height_changed.emit(value)
	return true


func _on_snap_picked(idx: int) -> void:
	if _suppress_writeback:
		return
	snap_picked.emit(snap_picker.get_item_id(idx))


func _on_bpm_changed(v: float) -> void:
	if _suppress_writeback:
		return
	bpm_changed.emit(v)


func _on_loop_toggled(on: bool) -> void:
	if _suppress_writeback:
		return
	loop_toggled.emit(on)


func _on_length_changed(value: float) -> void:
	if _suppress_writeback:
		return
	length_changed.emit(value)


func _on_track_row_height_changed(v: float) -> void:
	consume_track_row_height_change(v)
