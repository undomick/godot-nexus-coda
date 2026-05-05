@tool
class_name CodaSectionHeader
extends Control

## Compact, collapsible-friendly section header used inside the inspector and other stacked panels.
## Renders an optional icon, a heading, and a trailing action slot that callers can fill via add_trailing().

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

@export var heading: String = "Section":
	set(value):
		heading = value
		if _label != null:
			_label.text = value

var _hbox: HBoxContainer
var _icon_rect: TextureRect
var _label: Label
var _trailing_slot: HBoxContainer


func _init() -> void:
	custom_minimum_size = Vector2(0, 24)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	_hbox = HBoxContainer.new()
	_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hbox.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	add_child(_hbox)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(16, 16)
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.modulate = Tokens.TEXT_SECONDARY
	_icon_rect.visible = false
	_hbox.add_child(_icon_rect)

	_label = Label.new()
	_label.text = heading
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_font_size_override(&"font_size", Tokens.FONT_HEADING_SIZE)
	_label.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_hbox.add_child(_label)

	_trailing_slot = HBoxContainer.new()
	_trailing_slot.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_trailing_slot.size_flags_horizontal = Control.SIZE_SHRINK_END
	_hbox.add_child(_trailing_slot)


func set_icon(texture: Texture2D) -> void:
	if _icon_rect == null:
		return
	_icon_rect.texture = texture
	_icon_rect.visible = texture != null


func add_trailing(node: Control) -> void:
	if _trailing_slot != null and node != null:
		_trailing_slot.add_child(node)


func clear_trailing() -> void:
	if _trailing_slot == null:
		return
	for child in _trailing_slot.get_children():
		_trailing_slot.remove_child(child)
		child.queue_free()
