@tool
class_name CodaInspectorContextBanner
extends PanelContainer

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _title: Label
var _subtitle: Label
var _properties_slot: VBoxContainer
var _properties_content: Control = null


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_style(false)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", Tokens.SPACING_MD)
	margin.add_theme_constant_override(&"margin_top", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_right", Tokens.SPACING_MD)
	margin.add_theme_constant_override(&"margin_bottom", Tokens.SPACING_SM)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", Tokens.FONT_HEADING_SIZE)
	_title.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	col.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_subtitle.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_subtitle)
	_properties_slot = VBoxContainer.new()
	_properties_slot.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_properties_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_properties_slot.visible = false
	col.add_child(_properties_slot)
	visible = false


func set_properties_content(content: Control) -> void:
	if _properties_content != null and is_instance_valid(_properties_content):
		if _properties_content.get_parent() == _properties_slot:
			_properties_slot.remove_child(_properties_content)
	_properties_content = content
	if _properties_slot == null:
		return
	for child in _properties_slot.get_children():
		_properties_slot.remove_child(child)
	if content != null and is_instance_valid(content):
		_properties_slot.add_child(content)
		_properties_slot.visible = true
	else:
		_properties_slot.visible = false


func set_context(title: String, subtitle: String, highlighted: bool) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_apply_style(highlighted)
	visible = highlighted and not title.is_empty()


func _apply_style(highlighted: bool) -> void:
	if highlighted:
		var bg: Color = Tokens.SURFACE_RAISED.lerp(Tokens.ACCENT, 0.10)
		add_theme_stylebox_override(
			&"panel",
			Tokens.make_panel_stylebox(bg, Tokens.ACCENT, Tokens.RADIUS_SM, 2)
		)
	else:
		add_theme_stylebox_override(
			&"panel",
			Tokens.make_panel_stylebox(Tokens.SURFACE_RAISED, Tokens.SURFACE_BORDER, Tokens.RADIUS_SM)
		)
