@tool
extends HBoxContainer
class_name CodaMixerStripRow

## Holds bus strips + add placeholder; handles drag/drop reorder and draw insert caret.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

const DND_TYPE := &"coda_bus_strip"

class DragShield extends Control:
	var _row: CodaMixerStripRow
	var _mouse_x: float = 0.0

	func _init(row: CodaMixerStripRow) -> void:
		_row = row
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		visible = false
		z_index = 1000
		set_as_top_level(true)

	func set_mouse_x(x: float) -> void:
		_mouse_x = x

	func _gui_input(event: InputEvent) -> void:
		# Consume everything so underlying controls don't hover/caret while dragging.
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			_mouse_x = mm.position.x
			queue_redraw()
		accept_event()

	func _draw() -> void:
		if _row == null or not _row._drop_line_active or not _row._is_drag_from_mixer():
			return
		var ix: int = _row._flat_insert_before_index_from_local_x(_mouse_x)
		var line_x: float = _row._line_x_for_insert_index(ix)
		if line_x < 0.0:
			return
		var y0: float = 4.0
		var y1: float = maxf(y0 + 1.0, size.y - 4.0)
		draw_line(Vector2(line_x, y0), Vector2(line_x, y1), Tokens.ACCENT, 2.0)

var _mixer_panel: Node = null
var _drop_line_active: bool = false
var _shield: DragShield = null


func setup(mixer_panel: Node) -> void:
	_mixer_panel = mixer_panel
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shield = DragShield.new(self)
	add_child(_shield)
	set_process(true)


func _process(_delta: float) -> void:
	var active := _is_drag_from_mixer()
	if active != _drop_line_active:
		_drop_line_active = active
		if _shield != null:
			_shield.visible = active
			if active:
				_shield.global_position = global_position
				_shield.size = size
				_shield.set_mouse_x(get_local_mouse_position().x)
			_shield.queue_redraw()
	elif active:
		if _shield != null:
			_shield.global_position = global_position
			_shield.size = size
			_shield.set_mouse_x(get_local_mouse_position().x)
			_shield.queue_redraw()


func _is_drag_from_mixer() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var d: Variant = vp.gui_get_drag_data()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	return String(d.get("type", "")) == DND_TYPE


func _draw() -> void:
	# Caret is drawn by the drag shield.
	pass


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and String(data.get("type", "")) == DND_TYPE


func _drop_data(at_position: Vector2, data: Variant) -> void:
	# Drop between strips / on gaps.
	drop_bus_at_local_x(data, at_position.x)


func _flat_insert_before_index_from_local_x(lx: float) -> int:
	var strips: Array = []
	for c in get_children():
		if c is CodaBusStrip:
			strips.append(c)
		elif c.has_signal(&"add_bus_requested"):
			break
	if strips.is_empty():
		return 0
	for i in strips.size():
		var s: Control = strips[i] as Control
		var mid_x: float = s.position.x + s.size.x * 0.5
		if lx < mid_x:
			return i
	return strips.size()


func _line_x_for_insert_index(insert_before_flat: int) -> float:
	var strips: Array = []
	for c in get_children():
		if c is CodaBusStrip:
			strips.append(c)
		elif c.has_signal(&"add_bus_requested"):
			break
	if strips.is_empty():
		return -1.0
	if insert_before_flat <= 0:
		return (strips[0] as Control).position.x + 1.0
	if insert_before_flat >= strips.size():
		var last: Control = strips[strips.size() - 1] as Control
		return last.position.x + last.size.x + 2.0
	var tgt: Control = strips[insert_before_flat] as Control
	return tgt.position.x + 1.0


## Forwarded from CodaBusStrip (strip is hit-tested on drop, not the row).
func drop_bus_at_local_x(data: Variant, local_x: float) -> void:
	if _mixer_panel == null or typeof(data) != TYPE_DICTIONARY:
		return
	var drag_id: String = String(data.get("bus_id", ""))
	var ix: int = _flat_insert_before_index_from_local_x(local_x)
	if _mixer_panel.has_method(&"on_bus_strip_drop_at_flat_index"):
		_mixer_panel.call(&"on_bus_strip_drop_at_flat_index", drag_id, ix)
