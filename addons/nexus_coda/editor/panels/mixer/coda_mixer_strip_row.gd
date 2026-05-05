@tool
extends HBoxContainer
class_name CodaMixerStripRow

## Holds bus strips + add placeholder; handles drag/drop reorder and draw insert caret.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

const DND_TYPE := &"coda_bus_strip"

var _mixer_panel: Node = null
var _drop_line_active: bool = false


func setup(mixer_panel: Node) -> void:
	_mixer_panel = mixer_panel
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)


func _process(_delta: float) -> void:
	var active := _is_drag_from_mixer()
	if active != _drop_line_active:
		_drop_line_active = active
		queue_redraw()
	elif active:
		queue_redraw()


func _is_drag_from_mixer() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var d: Variant = vp.gui_get_drag_data()
	if typeof(d) != TYPE_DICTIONARY:
		return false
	return String(d.get("type", "")) == DND_TYPE


func _draw() -> void:
	if not _drop_line_active or not _is_drag_from_mixer():
		return
	var lx: float = get_local_mouse_position().x
	var ix: int = _flat_insert_before_index_from_local_x(lx)
	var line_x: float = _line_x_for_insert_index(ix)
	if line_x < 0.0:
		return
	var y0: float = 4.0
	var y1: float = maxf(y0 + 1.0, size.y - 4.0)
	draw_line(Vector2(line_x, y0), Vector2(line_x, y1), Tokens.ACCENT, 2.0)


func _flat_insert_before_index_from_local_x(lx: float) -> int:
	var strips: Array = []
	for c in get_children():
		if c is CodaBusStrip:
			strips.append(c)
		elif c.has_signal(&"add_bus_requested"):
			break
	if strips.is_empty():
		return 1
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
		return -1.0
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
