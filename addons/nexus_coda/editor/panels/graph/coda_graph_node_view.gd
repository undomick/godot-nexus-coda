@tool
class_name CodaGraphNodeView
extends GraphNode

## Visual representation of one CodaEventGraphNodeData inside the GraphEdit.
## Properties exposed inline are kind-dependent; everything else lives in the inspector.

signal property_changed(node_id: String, property_key: String, value: Variant)
signal browse_audio_requested(node_id: String)
signal preview_sound_requested(node_id: String)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NodeData := preload("res://addons/nexus_coda/editor/browser/coda_event_graph_node_data.gd")
const AUDIO_TYPE := 0

var _data_ref: CodaEventGraphNodeData
var _model_node_id: String = ""

var _audio_path_label: Label
var _audio_browse_button: Button
var _audio_preview_button: Button
var _volume_spin: SpinBox
var _pitch_spin: SpinBox


func bind(data: CodaEventGraphNodeData) -> void:
	_data_ref = data
	_model_node_id = data.id
	title = NodeData.display_name_for_kind(data.kind)
	# GraphNode forces the size by content unless explicit min size is set.
	custom_minimum_size = Vector2(220, 0)
	# GraphEdit reads position via position_offset (snap-to-grid friendly), not position.
	position_offset = data.graph_position
	_configure_slots(data)
	_build_body(data)


func get_model_node_id() -> String:
	return _model_node_id


func _configure_slots(data: CodaEventGraphNodeData) -> void:
	# All audio slots use the same type id so connections type-check.
	clear_all_slots()
	set_slot(
		0,
		data.has_audio_in(),
		AUDIO_TYPE,
		Tokens.ACCENT,
		data.has_audio_out(),
		AUDIO_TYPE,
		Tokens.ACCENT
	)


func _build_body(data: CodaEventGraphNodeData) -> void:
	# Clear any existing children except the title (GraphNode keeps its title outside its child list).
	for child in get_children():
		remove_child(child)
		child.queue_free()
	match data.kind:
		NodeData.Kind.TRIGGER:
			_build_trigger_body()
		NodeData.Kind.SEQUENCE:
			_build_sequence_body(data)
		NodeData.Kind.RANDOM:
			_build_random_body()
		NodeData.Kind.SOUND:
			_build_sound_body(data)
		NodeData.Kind.SWITCH:
			_build_placeholder_body("Switch — Phase 4 (parameter-driven)")
		NodeData.Kind.BLEND:
			_build_placeholder_body("Blend — Phase 4 (parameter-driven)")


func _build_trigger_body() -> void:
	var lbl := Label.new()
	lbl.text = "Connect to a Sound or Container"
	lbl.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(lbl)


func _build_sequence_body(data: CodaEventGraphNodeData) -> void:
	var loop_btn := CheckBox.new()
	loop_btn.text = "Loop"
	loop_btn.button_pressed = bool(data.properties.get("loop", false))
	loop_btn.toggled.connect(_on_loop_toggled)
	add_child(loop_btn)

	var hint := Label.new()
	hint.text = "Plays children in order"
	hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	hint.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(hint)


func _build_random_body() -> void:
	var hint := Label.new()
	hint.text = "Picks one child by weight"
	hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	hint.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(hint)


func _build_sound_body(data: CodaEventGraphNodeData) -> void:
	var path_row := HBoxContainer.new()
	path_row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	path_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(path_row)

	_audio_path_label = Label.new()
	_audio_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_audio_path_label.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)
	path_row.add_child(_audio_path_label)

	_audio_browse_button = Button.new()
	_audio_browse_button.text = "…"
	_audio_browse_button.tooltip_text = "Pick audio file"
	_audio_browse_button.pressed.connect(_on_browse_pressed)
	path_row.add_child(_audio_browse_button)

	var prop_row := HBoxContainer.new()
	prop_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	add_child(prop_row)

	var vol_label := Label.new()
	vol_label.text = "Vol dB"
	vol_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	vol_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	prop_row.add_child(vol_label)

	_volume_spin = SpinBox.new()
	_volume_spin.min_value = -60.0
	_volume_spin.max_value = 12.0
	_volume_spin.step = 0.5
	_volume_spin.value = float(data.properties.get("volume_db", 0.0))
	_volume_spin.value_changed.connect(_on_volume_changed)
	_volume_spin.custom_minimum_size = Vector2(80, 0)
	prop_row.add_child(_volume_spin)

	var pitch_label := Label.new()
	pitch_label.text = "Pitch"
	pitch_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	pitch_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	prop_row.add_child(pitch_label)

	_pitch_spin = SpinBox.new()
	_pitch_spin.min_value = 0.05
	_pitch_spin.max_value = 4.0
	_pitch_spin.step = 0.05
	_pitch_spin.value = float(data.properties.get("pitch_scale", 1.0))
	_pitch_spin.value_changed.connect(_on_pitch_changed)
	_pitch_spin.custom_minimum_size = Vector2(80, 0)
	prop_row.add_child(_pitch_spin)

	var preview_row := HBoxContainer.new()
	preview_row.alignment = BoxContainer.ALIGNMENT_END
	add_child(preview_row)

	_audio_preview_button = Button.new()
	_audio_preview_button.text = "Preview"
	_audio_preview_button.pressed.connect(_on_preview_pressed)
	preview_row.add_child(_audio_preview_button)

	_refresh_audio_path_label()


func _build_placeholder_body(message: String) -> void:
	var lbl := Label.new()
	lbl.text = message
	lbl.add_theme_color_override(&"font_color", Tokens.WARN)
	lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(lbl)


func refresh_from_data() -> void:
	if _data_ref == null:
		return
	if _data_ref.kind == NodeData.Kind.SOUND:
		if _volume_spin != null:
			_volume_spin.set_value_no_signal(float(_data_ref.properties.get("volume_db", 0.0)))
		if _pitch_spin != null:
			_pitch_spin.set_value_no_signal(float(_data_ref.properties.get("pitch_scale", 1.0)))
		_refresh_audio_path_label()


func _refresh_audio_path_label() -> void:
	if _audio_path_label == null or _data_ref == null:
		return
	var p: String = String(_data_ref.properties.get("audio_path", "")).strip_edges()
	if p.is_empty():
		_audio_path_label.text = "(no file)"
		_audio_path_label.add_theme_color_override(&"font_color", Tokens.WARN)
	else:
		_audio_path_label.text = p.get_file()
		_audio_path_label.tooltip_text = p
		_audio_path_label.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)


func _on_loop_toggled(state: bool) -> void:
	property_changed.emit(_model_node_id, "loop", state)


func _on_volume_changed(v: float) -> void:
	property_changed.emit(_model_node_id, "volume_db", v)


func _on_pitch_changed(v: float) -> void:
	property_changed.emit(_model_node_id, "pitch_scale", v)


func _on_browse_pressed() -> void:
	browse_audio_requested.emit(_model_node_id)


func _on_preview_pressed() -> void:
	preview_sound_requested.emit(_model_node_id)
