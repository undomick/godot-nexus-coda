@tool
extends Control

## Left grip: press here then release on another row to reorder tracks (no Godot DnD target issues).

var track_index: int = 0
var timeline_panel: Node = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Reorder: hold LMB, move vertically, release on target row (same as track number)"


func _gui_input(event: InputEvent) -> void:
	if timeline_panel == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if timeline_panel.has_method(&"on_track_row_grip_pressed"):
				timeline_panel.on_track_row_grip_pressed(track_index)
			accept_event()
