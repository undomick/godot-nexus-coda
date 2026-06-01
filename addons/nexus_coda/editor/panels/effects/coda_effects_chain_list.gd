@tool
class_name CodaEffectsChainList
extends VBoxContainer

## Vertical drop target for effect-card reorder (insert caret while dragging).

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

const DND_TYPE := &"coda_effect_card"

signal effect_drop_requested(effect_id: String, insert_before: int)


class InsertLineOverlay extends Control:
	var _list: CodaEffectsChainList

	func _init(list: CodaEffectsChainList) -> void:
		_list = list
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		z_index = 100
		set_as_top_level(true)

	func _process(_delta: float) -> void:
		if _list == null or not is_instance_valid(_list):
			return
		var active: bool = _list._is_effect_drag_active()
		visible = active
		if not active:
			return
		global_position = _list.global_position
		size = _list.size
		queue_redraw()

	func _draw() -> void:
		if _list == null:
			return
		var ly: float = _list.get_local_mouse_position().y
		var ix: int = _list._insert_before_index_from_local_y(ly)
		var line_y: float = _list._line_y_for_insert_index(ix)
		if line_y < 0.0:
			return
		var col: Color = Tokens.ACCENT
		col.a = 1.0
		var x0: float = 4.0
		var x1: float = maxf(x0 + 1.0, size.x - 4.0)
		draw_line(Vector2(x0, line_y), Vector2(x1, line_y), col, 3.0)


var _insert_line: InsertLineOverlay = null
var _ready_done: bool = false


func _ready() -> void:
	if _ready_done:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	_insert_line = InsertLineOverlay.new(self)
	add_child(_insert_line)
	set_process(true)
	_ready_done = true


func _process(_delta: float) -> void:
	if _insert_line != null and is_instance_valid(_insert_line):
		_insert_line.queue_redraw()


func keep_insert_line_on_top() -> void:
	if _insert_line != null and is_instance_valid(_insert_line) and _insert_line.get_parent() == self:
		move_child(_insert_line, get_child_count() - 1)


static func is_effect_drag_data(data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and String(data.get("type", "")) == DND_TYPE


func _is_effect_drag_active() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	return is_effect_drag_data(vp.gui_get_drag_data())


func _effect_cards() -> Array:
	var out: Array = []
	for c in get_children():
		if c is PanelContainer:
			out.append(c)
	return out


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return is_effect_drag_data(data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	drop_effect_at_local_y(data, at_position.y)


func drop_effect_at_local_y(data: Variant, local_y: float) -> void:
	if not is_effect_drag_data(data):
		return
	var effect_id: String = String((data as Dictionary).get("effect_id", ""))
	if effect_id.is_empty():
		return
	var ix: int = _insert_before_index_from_local_y(local_y)
	effect_drop_requested.emit(effect_id, ix)


func _insert_before_index_from_local_y(ly: float) -> int:
	var cards: Array = _effect_cards()
	if cards.is_empty():
		return 0
	for i in cards.size():
		var c: Control = cards[i] as Control
		var bounds: Rect2 = _card_bounds_in_list(c)
		var mid_y: float = bounds.position.y + bounds.size.y * 0.5
		if ly < mid_y:
			return i
	return cards.size()


func _line_y_for_insert_index(insert_before: int) -> float:
	var cards: Array = _effect_cards()
	if cards.is_empty():
		return -1.0
	if insert_before <= 0:
		var first: Control = cards[0] as Control
		return _card_bounds_in_list(first).position.y
	if insert_before >= cards.size():
		var last: Control = cards[cards.size() - 1] as Control
		var lb: Rect2 = _card_bounds_in_list(last)
		return lb.position.y + lb.size.y
	var prev: Control = cards[insert_before - 1] as Control
	var next: Control = cards[insert_before] as Control
	var pb: Rect2 = _card_bounds_in_list(prev)
	var nb: Rect2 = _card_bounds_in_list(next)
	var gap_top: float = pb.position.y + pb.size.y
	var gap_bottom: float = nb.position.y
	return gap_top + (gap_bottom - gap_top) * 0.5


func _card_bounds_in_list(card: Control) -> Rect2:
	if card == null or not is_instance_valid(card):
		return Rect2()
	var top_left: Vector2 = card.position
	if is_inside_tree() and card.is_inside_tree():
		var gpos: Vector2 = card.get_global_rect().position
		top_left = get_global_transform_with_canvas().affine_inverse() * gpos
	var h: float = card.size.y
	if h < 1.0:
		h = card.get_minimum_size().y
	return Rect2(top_left.x, top_left.y, card.size.x, h)
