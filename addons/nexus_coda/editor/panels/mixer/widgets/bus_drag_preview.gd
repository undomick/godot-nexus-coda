@tool
class_name BusDragPreview
extends Control

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _label: Label


func _init(p_text: String) -> void:
	custom_minimum_size = Vector2(104, 120)
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
	fill.a = 0.2
	draw_rect(Rect2(Vector2.ZERO, size), fill, true)
	var col: Color = Tokens.SURFACE_BORDER
	var margin := 2.0
	var rect := Rect2(Vector2(margin, margin), size - Vector2(margin * 2.0, margin * 2.0))
	var dash: float = 5.0
	var gap: float = 4.0
	var w: float = 1.25
	_draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), col, dash, gap, w)
	_draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, col, dash, gap, w)
	_draw_dashed_line(rect.end, Vector2(rect.position.x, rect.end.y), col, dash, gap, w)
	_draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.position, col, dash, gap, w)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, dash: float, gap: float, width: float) -> void:
	var full: Vector2 = to - from
	var total_len: float = full.length()
	if total_len <= 0.001:
		return
	var dir: Vector2 = full / total_len
	var t: float = 0.0
	while t < total_len:
		var a: Vector2 = from + dir * t
		var seg: float = minf(dash, total_len - t)
		var b: Vector2 = a + dir * seg
		draw_line(a, b, color, width)
		t += dash + gap
