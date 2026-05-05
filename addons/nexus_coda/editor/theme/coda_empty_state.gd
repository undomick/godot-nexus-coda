@tool
class_name CodaEmptyState
extends PanelContainer

## Centered call-to-action shown by panels when there is nothing meaningful to display yet.
## Self-explanatory by design: title + helper text + optional primary action.

signal action_triggered

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

@export var title_text: String = "Nothing here yet":
	set(value):
		title_text = value
		_apply_title()
@export var body_text: String = "":
	set(value):
		body_text = value
		_apply_body()
@export var action_text: String = "":
	set(value):
		action_text = value
		_apply_action()
@export var icon: Texture2D = null:
	set(value):
		icon = value
		_apply_icon()

var _icon_rect: TextureRect
var _title_label: Label
var _body_label: Label
var _action_button: Button


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	add_theme_stylebox_override(&"panel", Tokens.make_panel_stylebox(Tokens.SURFACE_BG, Tokens.SURFACE_BORDER, Tokens.RADIUS_SM, 0))
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	box.custom_minimum_size = Vector2(280, 0)
	center.add_child(box)

	_icon_rect = TextureRect.new()
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.custom_minimum_size = Vector2(40, 40)
	_icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon_rect.modulate = Tokens.TEXT_SECONDARY
	_icon_rect.visible = false
	box.add_child(_icon_rect)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override(&"font_size", Tokens.FONT_HEADING_SIZE)
	_title_label.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	box.add_child(_title_label)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_label.add_theme_font_size_override(&"font_size", Tokens.FONT_BODY_SIZE)
	_body_label.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)
	box.add_child(_body_label)

	_action_button = Button.new()
	_action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_action_button.visible = false
	_action_button.pressed.connect(_on_action_pressed)
	box.add_child(_action_button)

	_apply_title()
	_apply_body()
	_apply_action()
	_apply_icon()


func _apply_title() -> void:
	if _title_label != null:
		_title_label.text = title_text


func _apply_body() -> void:
	if _body_label != null:
		_body_label.text = body_text
		_body_label.visible = not body_text.is_empty()


func _apply_action() -> void:
	if _action_button == null:
		return
	_action_button.text = action_text
	_action_button.visible = not action_text.is_empty()


func _apply_icon() -> void:
	if _icon_rect == null:
		return
	_icon_rect.texture = icon
	_icon_rect.visible = icon != null


func _on_action_pressed() -> void:
	action_triggered.emit()
