@tool
class_name CodaEffectsChainList
extends VBoxContainer

## Vertical drop target for effect-card reorder (insert caret while dragging).

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

const DND_TYPE := &"coda_effect_card"

signal effect_drop_requested(effect_id: String, insert_before: int)


class DragShield extends Control:
	var _list: CodaEffectsChainList
	var _mouse_y: float = 0.0

	func _init(list: CodaEffectsChainList) -> void:
		_list = list
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		visible = false
		z_index = 1000
		set_as_top_level(true)

	func set_mouse_y(y: float) -> void:
		_mouse_y = y

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			_mouse_y = (event as InputEventMouseMotion).position.y
			queue_redraw()
		accept_event()

	func _draw() -> void:
		if _list == null or not _list._drop_line_active or not _list._is_effect_drag_active():
			return
		var ix: int = _list._insert_before_index_from_local_y(_mouse_y)
		var line_y: float = _list._line_y_for_insert_index(ix)
		if line_y < 0.0:
			return
		var x0: float = 4.0
		var x1: float = maxf(x0 + 1.0, size.x - 4.0)
		draw_line(Vector2(x0, line_y), Vector2(x1, line_y), Tokens.ACCENT, 2.0)


var _drop_line_active: bool = false
var _shield: DragShield = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shield = DragShield.new(self)
	add_child(_shield)
	set_process(true)


func _process(_delta: float) -> void:
	var active := _is_effect_drag_active()
	if active != _drop_line_active:
		_drop_line_active = active
		if _shield != null:
			_shield.visible = active
			if active:
				_shield.global_position = global_position
				_shield.size = size
				_shield.set_mouse_y(get_local_mouse_position().y)
			_shield.queue_redraw()
	elif active and _shield != null:
		_shield.global_position = global_position
		_shield.size = size
		_shield.set_mouse_y(get_local_mouse_position().y)
		_shield.queue_redraw()


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


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	drop_effect_at_local_y(data, get_local_mouse_position().y)


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
		var mid_y: float = c.position.y + c.size.y * 0.5
		if ly < mid_y:
			return i
	return cards.size()


func _line_y_for_insert_index(insert_before: int) -> float:
	var cards: Array = _effect_cards()
	if cards.is_empty():
		return -1.0
	if insert_before <= 0:
		return (cards[0] as Control).position.y + 1.0
	if insert_before >= cards.size():
		var last: Control = cards[cards.size() - 1] as Control
		return last.position.y + last.size.y + 2.0
	var tgt: Control = cards[insert_before] as Control
	return tgt.position.y + 1.0
