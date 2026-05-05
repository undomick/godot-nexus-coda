@tool
class_name CodaStatusBar
extends PanelContainer

## Footer below the dock host with three slots:
##   - left: focused-control help (tooltip text, fall-through hint)
##   - center: log tail (last info/warn/error)
##   - right: project state (path / dirty)
## Subscribes to NexusCodaLog so messages flow in without extra wiring.

const CodaDesignTokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")

const DEFAULT_HELP := "Hover any control for help. Press Ctrl+P to open the command palette."

var _help_label: Label
var _log_label: Label
var _project_label: Label
var _last_focused: Control = null


func _init() -> void:
	add_theme_stylebox_override(
		"panel",
		CodaDesignTokens.make_panel_stylebox(
			CodaDesignTokens.SURFACE_SUNKEN,
			CodaDesignTokens.SURFACE_BORDER,
			CodaDesignTokens.RADIUS_SM,
			1
		)
	)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", CodaDesignTokens.SPACING_LG)
	add_child(hb)

	_help_label = Label.new()
	_help_label.text = DEFAULT_HELP
	_help_label.add_theme_color_override("font_color", CodaDesignTokens.TEXT_SECONDARY)
	_help_label.add_theme_font_size_override("font_size", CodaDesignTokens.FONT_LABEL_SIZE)
	_help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_label.clip_text = true
	hb.add_child(_help_label)

	_log_label = Label.new()
	_log_label.text = ""
	_log_label.add_theme_color_override("font_color", CodaDesignTokens.TEXT_MUTED)
	_log_label.add_theme_font_size_override("font_size", CodaDesignTokens.FONT_LABEL_SIZE)
	_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.clip_text = true
	hb.add_child(_log_label)

	_project_label = Label.new()
	_project_label.text = "Untitled"
	_project_label.add_theme_color_override("font_color", CodaDesignTokens.TEXT_SECONDARY)
	_project_label.add_theme_font_size_override("font_size", CodaDesignTokens.FONT_LABEL_SIZE)
	_project_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(_project_label)


func _enter_tree() -> void:
	NexusCodaLog.subscribe(self, _on_log_event)
	if get_viewport() != null:
		get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	set_process(true)


func _exit_tree() -> void:
	NexusCodaLog.unsubscribe(self)
	if get_viewport() != null and get_viewport().gui_focus_changed.is_connected(_on_gui_focus_changed):
		get_viewport().gui_focus_changed.disconnect(_on_gui_focus_changed)


func _process(_dt: float) -> void:
	# Keep the help slot in sync with whatever the mouse is currently hovering when no
	# focus traversal happened recently; this matches the behavior most apps expect.
	if _last_focused == null or not is_instance_valid(_last_focused):
		var hovered: Control = _hovered_with_help()
		if hovered != null:
			_set_help_from_control(hovered)
		else:
			_help_label.text = DEFAULT_HELP


func _on_gui_focus_changed(c: Control) -> void:
	_last_focused = c
	_set_help_from_control(c)


func _hovered_with_help() -> Control:
	var v: Viewport = get_viewport()
	if v == null:
		return null
	var p: Vector2 = v.get_mouse_position()
	# Walk all top-level Controls is overkill; lean on Godot's hovered-on-focus and accept
	# that hover-only hints arrive on focus changes. Returning null keeps the default help.
	return null


func _set_help_from_control(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		_help_label.text = DEFAULT_HELP
		return
	var hint: String = c.tooltip_text.strip_edges()
	if hint.is_empty():
		hint = c.name if not c.name.is_empty() else DEFAULT_HELP
	_help_label.text = hint


func _on_log_event(level: int, channel: String, message: String) -> void:
	var prefix := ""
	var color: Color = CodaDesignTokens.TEXT_MUTED
	match level:
		NexusCodaLog.Level.INFO:
			prefix = "i"
			color = CodaDesignTokens.TEXT_SECONDARY
		NexusCodaLog.Level.WARN:
			prefix = "!"
			color = CodaDesignTokens.WARN
		NexusCodaLog.Level.ERROR:
			prefix = "x"
			color = CodaDesignTokens.DANGER
		_:
			prefix = "."
	_log_label.add_theme_color_override("font_color", color)
	var text: String = "%s [%s] %s" % [prefix, channel, message]
	if text.length() > 110:
		text = text.left(107) + "…"
	_log_label.text = text


func set_project_state(path: String, dirty: bool) -> void:
	var doc_name: String = "Untitled"
	if not path.is_empty():
		doc_name = path.get_file()
	if dirty:
		doc_name += " *"
	_project_label.text = doc_name
