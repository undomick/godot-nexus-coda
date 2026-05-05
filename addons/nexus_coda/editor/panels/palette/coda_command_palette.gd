@tool
class_name CodaCommandPalette
extends CanvasLayer

## Quake-style command palette for Coda. Lists actions and event paths;
## fuzzy filter narrows results, Enter executes the highlighted entry.
## Entries are simple Dictionaries with `id`, `title`, `subtitle`, `category`,
## and a `callable: Callable` invoked on execute.

const CodaDesignTokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

const MAX_VISIBLE_ROWS := 12

signal closed

var _entries: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _root: Control
var _panel: PanelContainer
var _search: LineEdit
var _list: ItemList
var _hint: Label
var _consumed_input: bool = false


func _init() -> void:
	layer = 256
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "PaletteRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_backdrop_input)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(620, 0)
	_panel.add_theme_stylebox_override(
		"panel",
		CodaDesignTokens.make_panel_stylebox(
			CodaDesignTokens.SURFACE_RAISED,
			CodaDesignTokens.SURFACE_BORDER,
			CodaDesignTokens.RADIUS_LG,
			1
		)
	)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", CodaDesignTokens.SPACING_LG)
	margin.add_theme_constant_override("margin_right", CodaDesignTokens.SPACING_LG)
	margin.add_theme_constant_override("margin_top", CodaDesignTokens.SPACING_MD)
	margin.add_theme_constant_override("margin_bottom", CodaDesignTokens.SPACING_MD)
	_panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", CodaDesignTokens.SPACING_SM)
	margin.add_child(vb)

	var head := Label.new()
	head.text = "Command Palette"
	head.add_theme_color_override("font_color", CodaDesignTokens.TEXT_SECONDARY)
	head.add_theme_font_size_override("font_size", CodaDesignTokens.FONT_LABEL_SIZE)
	vb.add_child(head)

	_search = LineEdit.new()
	_search.placeholder_text = "Type to filter actions and events…"
	_search.tooltip_text = "Filters actions, navigation entries, and recent paths."
	_search.text_changed.connect(_on_filter_changed)
	_search.text_submitted.connect(_on_text_submitted)
	_search.gui_input.connect(_on_search_input)
	vb.add_child(_search)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 360)
	_list.allow_reselect = true
	_list.item_activated.connect(_on_item_activated)
	_list.gui_input.connect(_on_list_input)
	vb.add_child(_list)

	_hint = Label.new()
	_hint.text = "Enter to run · Esc to close · Up/Down to navigate"
	_hint.add_theme_color_override("font_color", CodaDesignTokens.TEXT_MUTED)
	_hint.add_theme_font_size_override("font_size", CodaDesignTokens.FONT_LABEL_SIZE)
	vb.add_child(_hint)


func set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries
	_apply_filter("")


func open() -> void:
	visible = true
	_search.text = ""
	_apply_filter("")
	_search.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


func _on_filter_changed(_text: String) -> void:
	_apply_filter(_search.text)


func _on_text_submitted(_text: String) -> void:
	_run_selected()


func _on_search_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				close()
				_consumed_input = true
			KEY_DOWN:
				_move_selection(1)
				_consumed_input = true
			KEY_UP:
				_move_selection(-1)
				_consumed_input = true
			KEY_PAGEDOWN:
				_move_selection(MAX_VISIBLE_ROWS)
				_consumed_input = true
			KEY_PAGEUP:
				_move_selection(-MAX_VISIBLE_ROWS)
				_consumed_input = true


func _on_list_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()


func _on_item_activated(_index: int) -> void:
	_run_selected()


func _move_selection(delta: int) -> void:
	if _list.item_count == 0:
		return
	var current: int = _list.get_selected_items()[0] if not _list.get_selected_items().is_empty() else 0
	var target: int = clampi(current + delta, 0, _list.item_count - 1)
	_list.select(target)
	_list.ensure_current_is_visible()


func _apply_filter(text: String) -> void:
	_filtered.clear()
	var query: String = text.strip_edges().to_lower()
	if query.is_empty():
		for e in _entries:
			_filtered.append(e)
	else:
		for e in _entries:
			if _matches_query(e, query):
				_filtered.append(e)
	_populate_list()


func _matches_query(entry: Dictionary, query: String) -> bool:
	var blob: String = "%s %s %s" % [
		str(entry.get("title", "")),
		str(entry.get("subtitle", "")),
		str(entry.get("category", "")),
	]
	blob = blob.to_lower()
	# Simple subsequence match: each character of `query` must appear in order.
	var i: int = 0
	for c in query:
		var pos: int = blob.find(c, i)
		if pos < 0:
			return false
		i = pos + 1
	return true


func _populate_list() -> void:
	_list.clear()
	for e in _filtered:
		var label: String = "%s   %s" % [
			str(e.get("category", "")).rpad(12).left(12),
			str(e.get("title", "")),
		]
		var sub: String = str(e.get("subtitle", ""))
		if not sub.is_empty():
			label += "   — %s" % sub
		_list.add_item(label)
	if _list.item_count > 0:
		_list.select(0)


func _run_selected() -> void:
	if _filtered.is_empty():
		return
	var idx_arr: PackedInt32Array = _list.get_selected_items()
	var idx: int = 0
	if not idx_arr.is_empty():
		idx = idx_arr[0]
	if idx < 0 or idx >= _filtered.size():
		return
	var entry: Dictionary = _filtered[idx]
	close()
	var cb: Variant = entry.get("callable")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()
