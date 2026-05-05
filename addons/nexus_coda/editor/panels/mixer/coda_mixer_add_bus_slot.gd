@tool
class_name CodaMixerAddBusSlot
extends Control

## Placeholder-sized like a bus strip. Click adds a new bus under Master.

signal add_bus_requested

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _plus_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(104, 120)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

	_plus_label = Label.new()
	_plus_label.text = "+"
	_plus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plus_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_plus_label.add_theme_font_size_override(&"font_size", 28)
	_plus_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_plus_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plus_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_plus_label)

	tooltip_text = "Add a bus under Master"


func _draw() -> void:
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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			add_bus_requested.emit()
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
