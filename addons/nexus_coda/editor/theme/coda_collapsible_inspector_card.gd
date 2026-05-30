@tool
class_name CodaCollapsibleInspectorCard
extends PanelContainer

## Bordered inspector block with a fold toggle, title/subtitle header, and a body slot.

signal toggled(expanded: bool)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var expanded: bool = true:
	get:
		return _expanded
	set(value):
		if _expanded == value:
			return
		_expanded = value
		_apply_expanded()

var _expanded: bool = true
var _fold_button: Button
var _title_label: Label
var _subtitle_label: Label
var _body: VBoxContainer
var _title_block: VBoxContainer


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_apply_panel_style()


func _ready() -> void:
	if get_child_count() == 0:
		_build_ui()
	_apply_expanded()


func get_body() -> VBoxContainer:
	if _body == null:
		_build_ui()
	return _body


func set_header(title: String, subtitle: String = "") -> void:
	if _title_label == null:
		_build_ui()
	_title_label.text = title
	_subtitle_label.text = subtitle
	_subtitle_label.visible = not subtitle.is_empty()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_top", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_right", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_bottom", Tokens.SPACING_SM)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header_row)

	_fold_button = Button.new()
	_fold_button.text = "\u25BC"
	_fold_button.flat = true
	_fold_button.focus_mode = Control.FOCUS_NONE
	_fold_button.custom_minimum_size = Vector2(22, 22)
	_fold_button.pressed.connect(_on_toggle_pressed)
	header_row.add_child(_fold_button)

	_title_block = VBoxContainer.new()
	_title_block.add_theme_constant_override(&"separation", 0)
	_title_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_block.gui_input.connect(_on_title_block_gui_input)
	header_row.add_child(_title_block)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override(&"font_size", Tokens.FONT_HEADING_SIZE)
	_title_label.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_block.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_subtitle_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_block.add_child(_subtitle_label)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_body)


func _on_toggle_pressed() -> void:
	expanded = not expanded
	toggled.emit(expanded)


func _on_title_block_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_on_toggle_pressed()


func _apply_expanded() -> void:
	if _fold_button != null:
		_fold_button.text = "\u25B6" if not _expanded else "\u25BC"
	if _body != null:
		_body.visible = _expanded


func _apply_panel_style() -> void:
	var bg: Color = Tokens.SURFACE_RAISED.lerp(Tokens.ACCENT, 0.08)
	add_theme_stylebox_override(
		&"panel",
		Tokens.make_panel_stylebox(bg, Tokens.ACCENT, Tokens.RADIUS_SM, 2)
	)
