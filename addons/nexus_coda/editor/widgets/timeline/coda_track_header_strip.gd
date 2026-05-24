@tool
extends PanelContainer

## Audacity-style track header: name row + overflow menu, volume row with M/S.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaTimelineTrackDragHandleScript := preload(
	"res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_track_drag_handle.gd"
)

const _CTX_RENAME := 1001
const _CTX_DUPLICATE := 1002
const _CTX_DELETE := 1003
const _CTX_SEP_A := 1004
const _CTX_MOVE_UP := 1011
const _CTX_MOVE_DOWN := 1012
const _CTX_MOVE_TOP := 1013
const _CTX_MOVE_BOTTOM := 1014
const _CTX_SEP_B := 1020
const _CTX_COLOR_DEFAULT := 1030
const _CTX_COLOR_CUSTOM := 1031
const _CTX_SEP_C := 1040
const _CTX_RESET_VOL := 1050
const _CTX_SEP_D := 1060
const _CTX_SHOW_FX := 1070
const _CTX_BUS_BASE := 2000

signal track_action_requested(track_id: String, action: StringName, extra: Variant)

var track_index: int = 0
var on_drop: Callable = Callable()

var _track: CodaTimelineTrack = null
var _track_index: int = 0
var _row_h: int = 32
var _timeline_panel: Node = null
var _select_group: ButtonGroup = null
var _selected: bool = false
var _row: HBoxContainer

var _name_edit: LineEdit
var _mute_btn: Button
var _solo_btn: Button
var _volume_slider: HSlider
var _accent_bar: Panel
var _menu_btn: Button
var _context_menu: PopupMenu
var _move_submenu: PopupMenu
var _color_submenu: PopupMenu
var _bus_submenu: PopupMenu
var _color_dialog: ColorPicker
var _color_picker_dialog: AcceptDialog


func _init() -> void:
	clip_contents = true
	_apply_panel_style(false)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	return (data as Dictionary).has("coda_timeline_track_drag")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var d: Dictionary = data as Dictionary
	var from_i: int = int(d.get("coda_timeline_track_drag", -1))
	if from_i < 0 or from_i == track_index:
		return
	if on_drop.is_valid():
		on_drop.call(from_i, track_index)


func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	_apply_panel_style(selected)


func _apply_panel_style(selected: bool) -> void:
	if selected:
		var bg: Color = Tokens.SURFACE_RAISED.lerp(Tokens.ACCENT, 0.10)
		add_theme_stylebox_override(
			&"panel",
			Tokens.make_panel_stylebox(bg, Tokens.ACCENT, Tokens.RADIUS_SM, 2)
		)
	else:
		add_theme_stylebox_override(
			&"panel",
			Tokens.make_panel_stylebox(Tokens.SURFACE_RAISED, Tokens.SURFACE_BORDER, Tokens.RADIUS_SM)
		)


func build_ui(
	track: CodaTimelineTrack,
	p_track_index: int,
	row_height: int,
	timeline_panel: Node,
	select_group: ButtonGroup,
	selected_index: int
) -> void:
	_track = track
	_track_index = p_track_index
	_row_h = row_height
	_timeline_panel = timeline_panel
	_select_group = select_group
	track_index = p_track_index
	if timeline_panel != null:
		on_drop = Callable(timeline_panel, "reorder_tracks_drag_drop")

	for c in get_children():
		c.queue_free()

	custom_minimum_size = Vector2(0, row_height)
	custom_maximum_size = Vector2(4000, row_height)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.size_flags_vertical = Control.SIZE_FILL
	add_child(_row)

	var drag_grip := CodaTimelineTrackDragHandleScript.new()
	drag_grip.track_index = p_track_index
	drag_grip.timeline_panel = timeline_panel
	drag_grip.custom_minimum_size = Vector2(20, row_height)
	drag_grip.size_flags_vertical = Control.SIZE_FILL
	_row.add_child(drag_grip)

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_FILL
	body.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_row.add_child(body)

	_accent_bar = Panel.new()
	_accent_bar.custom_minimum_size = Vector2(3, 0)
	_accent_bar.size_flags_vertical = Control.SIZE_FILL
	body.add_child(_accent_bar)

	var main_col := VBoxContainer.new()
	main_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_col.size_flags_vertical = Control.SIZE_FILL
	main_col.add_theme_constant_override(&"separation", 2)
	body.add_child(main_col)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	top_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main_col.add_child(top_row)

	var sel_btn := Button.new()
	sel_btn.toggle_mode = true
	sel_btn.button_group = select_group
	sel_btn.button_pressed = p_track_index == selected_index
	sel_btn.text = str(p_track_index + 1)
	sel_btn.custom_minimum_size = Vector2(22, 22)
	sel_btn.tooltip_text = "Select track · Hold LMB and drag vertically to reorder"
	sel_btn.button_down.connect(
		func() -> void:
			if timeline_panel != null and timeline_panel.has_method(&"on_track_row_grip_pressed"):
				timeline_panel.on_track_row_grip_pressed(p_track_index)
	)
	sel_btn.toggled.connect(
		func(on: bool) -> void:
			if on and timeline_panel != null and timeline_panel.has_method(&"_set_selected_track_index"):
				timeline_panel._set_selected_track_index(p_track_index, true)
	)
	top_row.add_child(sel_btn)

	_name_edit = LineEdit.new()
	_name_edit.text = track.track_name
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_name_edit.custom_minimum_size = Vector2(0, 22)
	_name_edit.custom_maximum_size = Vector2(100000, 30)
	_name_edit.clip_contents = true
	_name_edit.placeholder_text = "Track name"
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_exited.connect(_on_name_focus_exited)
	top_row.add_child(_name_edit)

	_menu_btn = Button.new()
	_menu_btn.text = "⋯"
	_menu_btn.focus_mode = Control.FOCUS_NONE
	_menu_btn.custom_minimum_size = Vector2(28, 22)
	_menu_btn.tooltip_text = "Track menu"
	_menu_btn.pressed.connect(_on_menu_pressed)
	top_row.add_child(_menu_btn)

	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	bot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main_col.add_child(bot_row)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = -60.0
	_volume_slider.max_value = 6.0
	_volume_slider.step = 0.5
	_volume_slider.value = track.volume_db
	_volume_slider.custom_minimum_size = Vector2(48, 22)
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume_slider.focus_mode = Control.FOCUS_NONE
	_volume_slider.tooltip_text = "Track volume (dB)"
	_volume_slider.value_changed.connect(_on_volume_changed)
	bot_row.add_child(_volume_slider)

	_mute_btn = Button.new()
	_mute_btn.toggle_mode = true
	_mute_btn.text = "M"
	_mute_btn.custom_minimum_size = Vector2(22, 22)
	_mute_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mute_btn.tooltip_text = "Mute this track in editor preview"
	_mute_btn.button_pressed = track.mute
	_mute_btn.toggled.connect(_on_mute_toggled)
	bot_row.add_child(_mute_btn)

	_solo_btn = Button.new()
	_solo_btn.toggle_mode = true
	_solo_btn.text = "S"
	_solo_btn.custom_minimum_size = Vector2(22, 22)
	_solo_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_solo_btn.tooltip_text = "Solo this track in editor preview"
	_solo_btn.button_pressed = track.solo
	_solo_btn.toggled.connect(_on_solo_toggled)
	bot_row.add_child(_solo_btn)

	_build_menus()
	_apply_track_color_accent()
	set_selected(p_track_index == selected_index)


func set_bus_submenu_entries(entries: Array) -> void:
	# Each entry: PackedStringArray [0]=bus_id, [1]=label, or Dictionary id/label
	if _bus_submenu == null:
		return
	_bus_submenu.clear()
	for i in entries.size():
		var bus_id: String = ""
		var lbl: String = ""
		var row: Variant = entries[i]
		if row is Dictionary:
			bus_id = str((row as Dictionary).get("id", ""))
			lbl = str((row as Dictionary).get("label", ""))
		elif row is PackedStringArray:
			var psa: PackedStringArray = row
			if psa.size() >= 2:
				bus_id = str(psa[0])
				lbl = str(psa[1])
		if bus_id.is_empty():
			continue
		var mid: int = _CTX_BUS_BASE + i
		_bus_submenu.add_item(lbl if not lbl.is_empty() else bus_id, mid)
		var ix: int = _bus_submenu.get_item_index(mid)
		if ix >= 0:
			_bus_submenu.set_item_metadata(ix, bus_id)


func sync_from_track() -> void:
	if _track == null:
		return
	# Only touch widget state when it actually diverges so we never interrupt a slider drag
	# or a focused LineEdit edit.
	if _name_edit != null and not _name_edit.has_focus() and _name_edit.text != _track.track_name:
		_name_edit.text = _track.track_name
	if _mute_btn != null and _mute_btn.button_pressed != _track.mute:
		_mute_btn.set_pressed_no_signal(_track.mute)
	if _solo_btn != null and _solo_btn.button_pressed != _track.solo:
		_solo_btn.set_pressed_no_signal(_track.solo)
	if _volume_slider != null and not is_equal_approx(_volume_slider.value, _track.volume_db):
		_volume_slider.set_value_no_signal(_track.volume_db)
	_apply_track_color_accent()


func _apply_track_color_accent() -> void:
	if _accent_bar == null or _track == null:
		return
	var sb := StyleBoxFlat.new()
	if _track.color.a <= 0.001:
		sb.bg_color = Tokens.ACCENT_DIM
	else:
		sb.bg_color = _track.color
	sb.set_corner_radius_all(2)
	_accent_bar.add_theme_stylebox_override(&"panel", sb)


func _build_menus() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.name = "TrackHeaderCtx"

	_move_submenu = PopupMenu.new()
	_move_submenu.name = "TrackHeaderMoveSub"
	_move_submenu.add_item("Up", _CTX_MOVE_UP)
	_move_submenu.add_item("Down", _CTX_MOVE_DOWN)
	_move_submenu.add_item("To top", _CTX_MOVE_TOP)
	_move_submenu.add_item("To bottom", _CTX_MOVE_BOTTOM)
	_move_submenu.id_pressed.connect(_on_move_submenu_id_pressed)
	_context_menu.add_child(_move_submenu)

	_color_submenu = PopupMenu.new()
	_color_submenu.name = "TrackHeaderColorSub"
	_color_submenu.add_item("Use theme accent", _CTX_COLOR_DEFAULT)
	_color_submenu.add_item("Pick color…", _CTX_COLOR_CUSTOM)
	_color_submenu.id_pressed.connect(_on_color_submenu_id_pressed)
	_context_menu.add_child(_color_submenu)

	_bus_submenu = PopupMenu.new()
	_bus_submenu.name = "TrackHeaderBusSub"
	_bus_submenu.id_pressed.connect(_on_bus_submenu_id_pressed)
	_context_menu.add_child(_bus_submenu)

	_context_menu.add_item("Rename", _CTX_RENAME)
	_context_menu.add_item("Duplicate", _CTX_DUPLICATE)
	_context_menu.add_item("Delete", _CTX_DELETE)
	_context_menu.add_separator()
	_context_menu.add_submenu_item("Move track", _move_submenu.name)
	_context_menu.add_submenu_item("Track color", _color_submenu.name)
	_context_menu.add_separator()
	_context_menu.add_submenu_item("Output bus", _bus_submenu.name)
	_context_menu.add_item("Reset volume", _CTX_RESET_VOL)
	_context_menu.add_separator()
	_context_menu.add_item("Show track effects…", _CTX_SHOW_FX)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	_color_picker_dialog = AcceptDialog.new()
	_color_picker_dialog.title = "Track color"
	_color_picker_dialog.ok_button_text = "Apply"
	_color_picker_dialog.size = Vector2i(320, 360)
	_color_dialog = ColorPicker.new()
	_color_dialog.color = (
		_track.color if _track != null and _track.color.a > 0.001 else Tokens.ACCENT
	)
	_color_picker_dialog.add_child(_color_dialog)
	_color_picker_dialog.confirmed.connect(_on_color_picker_confirmed)
	add_child(_color_picker_dialog)


func _on_color_picker_confirmed() -> void:
	if _track == null:
		return
	track_action_requested.emit(_track.id, &"set_color", _color_dialog.color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not _is_track_select_interactive_at(get_global_mouse_position()):
				_select_track_from_header()


func _select_track_from_header() -> void:
	if _timeline_panel == null or not _timeline_panel.has_method(&"_set_selected_track_index"):
		return
	_timeline_panel._set_selected_track_index(_track_index, true)


func _is_track_select_interactive_at(global_pos: Vector2) -> bool:
	for c in _track_select_interactive_controls():
		if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(global_pos):
			return true
	return false


func _track_select_interactive_controls() -> Array[Control]:
	var out: Array[Control] = []
	if _name_edit != null:
		out.append(_name_edit)
	if _menu_btn != null:
		out.append(_menu_btn)
	if _mute_btn != null:
		out.append(_mute_btn)
	if _solo_btn != null:
		out.append(_solo_btn)
	if _volume_slider != null:
		out.append(_volume_slider)
	if _row != null and _row.get_child_count() > 0:
		var drag_grip: Control = _row.get_child(0) as Control
		if drag_grip != null:
			out.append(drag_grip)
	return out


func _on_menu_pressed() -> void:
	if _track == null:
		return
	var gp: Vector2 = _menu_btn.get_global_rect().position + Vector2(0, _menu_btn.size.y)
	_context_menu.popup(Rect2i(Vector2i(int(gp.x), int(gp.y)), Vector2i(1, 1)))


func _on_context_menu_id_pressed(id: int) -> void:
	if _track == null:
		return
	match id:
		_CTX_RENAME:
			_name_edit.grab_focus()
			_name_edit.select_all()
		_CTX_DUPLICATE:
			track_action_requested.emit(_track.id, &"duplicate", _track_index)
		_CTX_DELETE:
			track_action_requested.emit(_track.id, &"delete", _track_index)
		_CTX_RESET_VOL:
			track_action_requested.emit(_track.id, &"reset_volume", _track_index)
		_CTX_SHOW_FX:
			track_action_requested.emit(_track.id, &"show_track_effects", _track_index)
		_:
			pass


func _on_move_submenu_id_pressed(id: int) -> void:
	if _track == null:
		return
	match id:
		_CTX_MOVE_UP:
			track_action_requested.emit(_track.id, &"move_up", _track_index)
		_CTX_MOVE_DOWN:
			track_action_requested.emit(_track.id, &"move_down", _track_index)
		_CTX_MOVE_TOP:
			track_action_requested.emit(_track.id, &"move_top", _track_index)
		_CTX_MOVE_BOTTOM:
			track_action_requested.emit(_track.id, &"move_bottom", _track_index)
		_:
			pass


func _on_color_submenu_id_pressed(id: int) -> void:
	if _track == null:
		return
	if id == _CTX_COLOR_DEFAULT:
		track_action_requested.emit(_track.id, &"set_color", Color.TRANSPARENT)
	elif id == _CTX_COLOR_CUSTOM:
		if _color_picker_dialog != null:
			if _track.color.a > 0.001:
				_color_dialog.color = _track.color
			_color_picker_dialog.popup_centered()


func _on_bus_submenu_id_pressed(id: int) -> void:
	if _track == null or _bus_submenu == null:
		return
	if id < _CTX_BUS_BASE:
		return
	var idx: int = _bus_submenu.get_item_index(id)
	if idx < 0:
		return
	var meta: Variant = _bus_submenu.get_item_metadata(idx)
	track_action_requested.emit(_track.id, &"set_output_bus", str(meta))


func _on_name_submitted(tn: String) -> void:
	if _track == null:
		return
	_track.track_name = tn
	_emit_timeline_dirty()


func _on_name_focus_exited() -> void:
	if _track == null or _name_edit == null:
		return
	if _track.track_name != _name_edit.text:
		_track.track_name = _name_edit.text
		_emit_timeline_dirty()


func _on_mute_toggled(on: bool) -> void:
	if _track == null:
		return
	_track.mute = on
	_emit_timeline_dirty()


func _on_solo_toggled(on: bool) -> void:
	if _track == null:
		return
	_track.solo = on
	_emit_timeline_dirty()


func _on_volume_changed(v: float) -> void:
	if _track == null:
		return
	_track.volume_db = v
	_emit_timeline_dirty()


func _emit_timeline_dirty() -> void:
	if _timeline_panel != null and _timeline_panel.has_method(&"_notify_timeline_changed"):
		_timeline_panel._notify_timeline_changed()
