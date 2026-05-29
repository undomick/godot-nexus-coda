@tool
class_name CodaEventTransportBar
extends HBoxContainer

## Compact transport: Play / Stop / Pause (icon buttons), Loop, optional status label.
## Drives the editor-side CodaRuntime so designers can audition events without entering Play mode.

signal play_requested
signal stop_requested
signal pause_toggled(on: bool)
signal loop_toggled(loop: bool)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

const _TRANSPORT_ICON_MAX_PX := 38
const _TRANSPORT_SECONDARY_PX := 32
const _ICON_PLAY := preload("res://addons/nexus_coda/icons/player_play.svg")
const _ICON_STOP := preload("res://addons/nexus_coda/icons/player_stop.svg")
const _ICON_PAUSE := preload("res://addons/nexus_coda/icons/player_pause.svg")

var _play_button: Button
var _stop_button: Button
var _pause_button: Button
var _loop_button: CheckBox
var _status_label: Label
var _is_playing: bool = false


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)

	_play_button = Button.new()
	_play_button.text = ""
	_play_button.icon = _ICON_PLAY
	_play_button.expand_icon = true
	_play_button.custom_minimum_size = Vector2(_TRANSPORT_ICON_MAX_PX, _TRANSPORT_ICON_MAX_PX)
	_play_button.add_theme_constant_override(&"icon_max_width", _TRANSPORT_ICON_MAX_PX)
	_play_button.self_modulate = Tokens.SUCCESS
	_play_button.tooltip_text = "Audition this event"
	_play_button.pressed.connect(_on_play_pressed)
	add_child(_play_button)

	_stop_button = Button.new()
	_stop_button.text = ""
	_stop_button.icon = _ICON_STOP
	_stop_button.expand_icon = true
	_stop_button.custom_minimum_size = Vector2(_TRANSPORT_SECONDARY_PX, _TRANSPORT_SECONDARY_PX)
	_stop_button.add_theme_constant_override(&"icon_max_width", _TRANSPORT_SECONDARY_PX)
	_stop_button.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_stop_button.disabled = true
	_stop_button.tooltip_text = "Stop preview"
	_stop_button.pressed.connect(_on_stop_pressed)
	add_child(_stop_button)

	_pause_button = Button.new()
	_pause_button.toggle_mode = true
	_pause_button.text = ""
	_pause_button.icon = _ICON_PAUSE
	_pause_button.expand_icon = true
	_pause_button.custom_minimum_size = Vector2(_TRANSPORT_SECONDARY_PX, _TRANSPORT_SECONDARY_PX)
	_pause_button.add_theme_constant_override(&"icon_max_width", _TRANSPORT_SECONDARY_PX)
	_pause_button.tooltip_text = "Pause / resume the active voice"
	_pause_button.disabled = true
	_pause_button.toggled.connect(_on_pause_toggled)
	add_child(_pause_button)

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
	if _pause_button != null:
		if not is_playing:
			_pause_button.set_pressed_no_signal(false)
			_pause_button.disabled = true
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


## Hosts that want to show their own (richer) status indicator can hide the built-in label
## without pulling apart the bar's children.
func set_status_label_visible(p_visible: bool) -> void:
	if _status_label != null:
		_status_label.visible = p_visible


func is_loop_enabled() -> bool:
	return _loop_button != null and _loop_button.button_pressed


## Preview started: allow pause; clear toggle without emitting.
func arm_pause_for_playback() -> void:
	if _pause_button == null:
		return
	_pause_button.disabled = false
	_pause_button.set_pressed_no_signal(false)


## Match pause latch to engine without emitting pause_toggled.
func set_pause_pressed_no_signal(pressed: bool) -> void:
	if _pause_button == null:
		return
	_pause_button.set_pressed_no_signal(pressed)


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_stop_pressed() -> void:
	stop_requested.emit()


func _on_loop_toggled(state: bool) -> void:
	loop_toggled.emit(state)


func _on_pause_toggled(on: bool) -> void:
	pause_toggled.emit(on)
