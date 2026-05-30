@tool
class_name CodaEffectDragPreview
extends Control

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _label: Label


func _init(p_text: String) -> void:
	custom_minimum_size = Vector2(220, 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.text = p_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_label.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


func _draw() -> void:
	var fill := Tokens.SURFACE_RAISED
	fill.a = 0.22
	draw_rect(Rect2(Vector2.ZERO, size), fill, true)
	var col: Color = Tokens.ACCENT
	col.a = 0.85
	var border := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	draw_rect(border, col, false, 1.25)
