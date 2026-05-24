@tool
class_name VerticalDragFader
extends Control

signal fader_value_changed(value: float)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _value: float = 0.0
var _dragging: bool = false
var _min_db: float
var _max_db: float
var _step: float


func _init(
	min_db: float,
	max_db: float,
	step: float
) -> void:
	_min_db = min_db
	_max_db = max_db
	_step = step
	custom_minimum_size = Vector2(22, 32)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	tooltip_text = "Drag vertically to adjust level"


func get_fader_value() -> float:
	return _value


func set_value_no_signal(v: float) -> void:
	_value = clampf(snapped(v, _step), _min_db, _max_db)
	queue_redraw()


func _db_from_local_y(local_y: float) -> float:
	var h: float = size.y
	if h <= 0.0:
		return _value
	var t: float = 1.0 - clampf(local_y / h, 0.0, 1.0)
	return lerpf(_min_db, _max_db, t)


func _y_center_for_db(db: float) -> float:
	var h: float = size.y
	var t: float = inverse_lerp(_min_db, _max_db, clampf(db, _min_db, _max_db))
	return (1.0 - t) * h


func _apply_from_y(local_y: float) -> void:
	var nv: float = clampf(snapped(_db_from_local_y(local_y), _step), _min_db, _max_db)
	if is_equal_approx(nv, _value):
		return
	_value = nv
	queue_redraw()
	fader_value_changed.emit(_value)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_dragging = true
			_apply_from_y(mb.position.y)
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_apply_from_y(mm.position.y)
		accept_event()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, Tokens.SURFACE_SUNKEN, true)
	draw_rect(r, Tokens.SURFACE_BORDER, false, 1.0)
	var thumb_h: float = maxf(10.0, size.y * 0.07)
	var yc: float = _y_center_for_db(_value)
	var thumb: Rect2 = Rect2(2.0, yc - thumb_h * 0.5, maxf(0.0, size.x - 4.0), thumb_h)
	draw_rect(thumb, Tokens.ACCENT_DIM, true)
