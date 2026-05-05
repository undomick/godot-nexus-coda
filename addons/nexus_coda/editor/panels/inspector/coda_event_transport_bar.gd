@tool
class_name CodaEventTransportBar
extends HBoxContainer

## Compact transport for the inspector header: Play / Stop / Loop toggle + status indicator.
## Drives the editor-side CodaRuntime so designers can audition events without entering Play mode.

signal play_requested
signal stop_requested
signal loop_toggled(loop: bool)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _play_button: Button
var _stop_button: Button
var _loop_button: CheckBox
var _status_label: Label
var _is_playing: bool = false


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)

	_play_button = Button.new()
	_play_button.text = "Play"
	_play_button.tooltip_text = "Audition this event"
	_play_button.pressed.connect(_on_play_pressed)
	add_child(_play_button)

	_stop_button = Button.new()
	_stop_button.text = "Stop"
	_stop_button.disabled = true
	_stop_button.tooltip_text = "Stop preview"
	_stop_button.pressed.connect(_on_stop_pressed)
	add_child(_stop_button)

	_loop_button = CheckBox.new()
	_loop_button.text = "Loop"
	_loop_button.tooltip_text = "Restart on finish"
	_loop_button.toggled.connect(_on_loop_toggled)
	add_child(_loop_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	_status_label = Label.new()
	_status_label.text = "Idle"
	_status_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_status_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(_status_label)


func set_playing(is_playing: bool) -> void:
	_is_playing = is_playing
	if _stop_button != null:
		_stop_button.disabled = not is_playing
	if _status_label != null:
		_status_label.text = "Playing" if is_playing else "Idle"
		_status_label.add_theme_color_override(
			&"font_color",
			Tokens.SUCCESS if is_playing else Tokens.TEXT_MUTED
		)


func set_play_enabled(enabled: bool, hint: String = "") -> void:
	if _play_button == null:
		return
	_play_button.disabled = not enabled
	if not enabled and not hint.is_empty():
		_play_button.tooltip_text = hint
	elif enabled:
		_play_button.tooltip_text = "Audition this event"


func is_loop_enabled() -> bool:
	return _loop_button != null and _loop_button.button_pressed


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_stop_pressed() -> void:
	stop_requested.emit()


func _on_loop_toggled(state: bool) -> void:
	loop_toggled.emit(state)
