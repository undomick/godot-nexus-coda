@tool
class_name CodaShortcutSheet
extends CanvasLayer

## Modal overlay that documents all keyboard shortcuts available in the
## Nexus Coda editor window. Static content for now; a future iteration can
## query the InputMap for project-wide actions.

const CodaDesignTokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

const SHORTCUTS := [
	{"category": "Window", "rows": [
		["Ctrl+P", "Open command palette"],
		["F1", "Open this shortcut sheet"],
		["Ctrl+N", "New project"],
		["Ctrl+O", "Open project"],
		["Ctrl+S", "Save project"],
		["Ctrl+Shift+S", "Save project as…"],
	]},
	{"category": "Browser", "rows": [
		["Enter / Double-click", "Open event in graph"],
		["F2", "Rename selected node"],
		["Delete", "Remove selected node"],
		["Drag asset onto graph", "Add SOUND node"],
	]},
	{"category": "Graph", "rows": [
		["Ctrl+Drag", "Box-select multiple nodes"],
		["Delete", "Remove selected nodes/edges"],
		["Right-click", "Context menu (palette)"],
	]},
	{"category": "Mixer", "rows": [
		["Click fader, drag", "Adjust bus volume"],
		["M", "Toggle mute on focused strip"],
		["S", "Toggle solo on focused strip"],
	]},
	{"category": "Inspector", "rows": [
		["Tab", "Cycle between fields"],
		["Esc", "Cancel rename / drop edit"],
	]},
]


signal closed

var _root: Control


func _init() -> void:
	layer = 256
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "ShortcutRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_backdrop_input)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override(
		"panel",
		CodaDesignTokens.make_panel_stylebox(
			CodaDesignTokens.SURFACE_RAISED,
			CodaDesignTokens.SURFACE_BORDER,
			CodaDesignTokens.RADIUS_LG,
			1
		)
	)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", CodaDesignTokens.SPACING_LG)
	margin.add_theme_constant_override("margin_right", CodaDesignTokens.SPACING_LG)
	margin.add_theme_constant_override("margin_top", CodaDesignTokens.SPACING_MD)
	margin.add_theme_constant_override("margin_bottom", CodaDesignTokens.SPACING_MD)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", CodaDesignTokens.SPACING_MD)
	margin.add_child(vb)

	var head := Label.new()
	head.text = "Keyboard Shortcuts"
	head.add_theme_color_override("font_color", CodaDesignTokens.TEXT_PRIMARY)
	head.add_theme_font_size_override("font_size", CodaDesignTokens.FONT_TITLE_SIZE)
	vb.add_child(head)

	for entry in SHORTCUTS:
		_add_category(vb, entry as Dictionary)

	var footer_row := HBoxContainer.new()
	footer_row.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(footer_row)
	var btn := Button.new()
	btn.text = "Close"
	btn.pressed.connect(close)
	footer_row.add_child(btn)


func _add_category(parent: VBoxContainer, entry: Dictionary) -> void:
	var heading := Label.new()
	heading.text = str(entry.get("category", ""))
	heading.add_theme_color_override("font_color", CodaDesignTokens.ACCENT)
	heading.add_theme_font_size_override("font_size", CodaDesignTokens.FONT_HEADING_SIZE)
	parent.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", CodaDesignTokens.SPACING_LG)
	grid.add_theme_constant_override("v_separation", CodaDesignTokens.SPACING_XS)
	parent.add_child(grid)

	var rows: Array = entry.get("rows", []) as Array
	for r in rows:
		var arr: Array = r as Array
		if arr.size() < 2:
			continue
		var key := Label.new()
		key.text = str(arr[0])
		key.add_theme_color_override("font_color", CodaDesignTokens.TEXT_PRIMARY)
		grid.add_child(key)

		var desc := Label.new()
		desc.text = str(arr[1])
		desc.add_theme_color_override("font_color", CodaDesignTokens.TEXT_SECONDARY)
		grid.add_child(desc)


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and visible:
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true


func close() -> void:
	visible = false
	closed.emit()
