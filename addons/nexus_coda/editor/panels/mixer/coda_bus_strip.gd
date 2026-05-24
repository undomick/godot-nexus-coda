@tool
class_name CodaBusStrip
extends PanelContainer

## Bus strip: name, L/R meters + fader + vertical M/S/B, dB field, send target, drag reorder.

signal volume_changed(bus_id: String, volume_db: float)
signal mute_toggled(bus_id: String, mute: bool)
signal solo_toggled(bus_id: String, solo: bool)
signal bypass_toggled(bus_id: String, bypass: bool)
signal bus_renamed(bus_id: String, new_name: String)
signal send_target_changed(bus_id: String, target_bus_id: String)
signal context_action_requested(bus_id: String, action: StringName)
signal bus_strip_selected(bus_id: String)

const DND_TYPE := &"coda_bus_strip"

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaAudioBusMirrorScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_mirror.gd")

const FADER_MIN_DB := -60.0
const FADER_MAX_DB := 12.0
const FADER_STEP := 0.1

var _bus: CodaBus = null
var _syncing_ui: bool = false
var _is_master_bus: bool = false

var _name_edit: LineEdit
var _fader: VerticalDragFader
var _db_edit: LineEdit
var _mute_btn: Button
var _solo_btn: Button
var _bypass_btn: Button
var _meter_l: ProgressBar
var _meter_r: ProgressBar
var _send_option: OptionButton
var _godot_bus_name: String = ""

const _CTX_ADD_BUS_HERE := 1
const _CTX_DUPLICATE_BUS := 2
const _CTX_DELETE_BUS := 3
const _CTX_RESET_VOLUME := 4

var _context_menu: PopupMenu
var _selected: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(104, 160)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override(
		&"panel",
		Tokens.make_panel_stylebox(Tokens.SURFACE_RAISED, Tokens.SURFACE_BORDER, Tokens.RADIUS_SM)
	)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	add_child(col)

	_name_edit = LineEdit.new()
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size = Vector2(0, 26)
	_name_edit.placeholder_text = "Bus name"
	_name_edit.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_name_edit.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_bus_name_if_needed())
	_name_edit.focus_exited.connect(_commit_bus_name_if_needed)
	_name_edit.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	col.add_child(_name_edit)

	var main_row := HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override(&"separation", 4)
	col.add_child(main_row)

	var meters_fader := HBoxContainer.new()
	meters_fader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters_fader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	meters_fader.add_theme_constant_override(&"separation", 4)
	main_row.add_child(meters_fader)

	_meter_l = _make_meter()
	_meter_r = _make_meter()
	_meter_l.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	_meter_r.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	meters_fader.add_child(_meter_l)
	meters_fader.add_child(_meter_r)

	_fader = VerticalDragFader.new(FADER_MIN_DB, FADER_MAX_DB, FADER_STEP)
	_fader.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	meters_fader.add_child(_fader)
	_fader.fader_value_changed.connect(_on_vertical_fader_changed)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	btn_col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main_row.add_child(btn_col)

	_mute_btn = _make_toggle_strip_button("M", "Mute")
	_solo_btn = _make_toggle_strip_button("S", "Solo")
	_bypass_btn = _make_toggle_strip_button("B", "Bypass bus effects")
	_mute_btn.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	_solo_btn.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	_bypass_btn.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	_mute_btn.toggled.connect(_on_mute_toggled_ui)
	_solo_btn.toggled.connect(_on_solo_toggled_ui)
	_bypass_btn.toggled.connect(_on_bypass_toggled_ui)
	btn_col.add_child(_mute_btn)
	btn_col.add_child(_solo_btn)
	btn_col.add_child(_bypass_btn)

	_db_edit = LineEdit.new()
	_db_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_db_edit.custom_minimum_size = Vector2(0, 26)
	_db_edit.placeholder_text = "dB value"
	_db_edit.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)
	_db_edit.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_db_edit.text_submitted.connect(func(_t: String) -> void: _commit_db_field())
	_db_edit.focus_exited.connect(_commit_db_field)
	_db_edit.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	col.add_child(_db_edit)

	_send_option = OptionButton.new()
	_send_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_send_option.custom_minimum_size = Vector2(0, 26)
	_send_option.tooltip_text = "Audio bus send / link target (toward Master)"
	_send_option.item_selected.connect(_on_send_item_selected)
	_send_option.set_drag_forwarding(Callable(self, "_get_drag_data"), Callable(self, "_can_drop_data"), Callable(self, "_drop_data"))
	col.add_child(_send_option)

	_context_menu = PopupMenu.new()
	_context_menu.name = "BusContextMenu"
	_context_menu.add_item("Add bus here", _CTX_ADD_BUS_HERE)
	_context_menu.add_item("Duplicate bus", _CTX_DUPLICATE_BUS)
	_context_menu.add_item("Delete bus", _CTX_DELETE_BUS)
	_context_menu.add_separator()
	_context_menu.add_item("Reset volume", _CTX_RESET_VOLUME)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _bus != null and not _is_bus_select_interactive_at(get_global_mouse_position()):
				bus_strip_selected.emit(_bus.id)
			return
		if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
			return
		if _bus == null:
			return
		_refresh_context_menu_enabled()
		var gp: Vector2 = get_global_mouse_position()
		_context_menu.popup(Rect2i(Vector2i(int(gp.x), int(gp.y)), Vector2i(1, 1)))
		accept_event()


func _get_drag_data(at_position: Vector2) -> Variant:
	if _bus == null or _is_master_bus:
		return null
	if not _is_drag_start_allowed(get_global_mouse_position()):
		return null
	var preview := BusDragPreview.new(_bus.bus_name)
	preview.custom_minimum_size = size
	set_drag_preview(preview)
	return {"type": DND_TYPE, "bus_id": _bus.id}


func _is_drag_start_allowed(global_pos: Vector2) -> bool:
	return not _is_bus_select_interactive_at(global_pos)


func _is_bus_select_interactive_at(global_pos: Vector2) -> bool:
	# Only allow strip drag from empty background / border.
	# If the pointer is over any interactive child control, do not start DnD.
	var interactive: Array[Control] = [
		_name_edit,
		_db_edit,
		_send_option,
		_fader,
		_meter_l,
		_meter_r,
		_mute_btn,
		_solo_btn,
		_bypass_btn,
	]
	for c in interactive:
		if c == null:
			continue
		if c.is_visible_in_tree() and c.get_global_rect().has_point(global_pos):
			return false
	return true


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and String(data.get("type", "")) == DND_TYPE


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var row := get_parent()
	if row == null:
		return
	var lx: float = (row as Control).get_local_mouse_position().x
	if row.has_method(&"drop_bus_at_local_x"):
		row.call(&"drop_bus_at_local_x", data, lx)


func _make_toggle_strip_button(p_text: String, p_tooltip: String) -> Button:
	var btn := Button.new()
	btn.text = p_text
	btn.tooltip_text = p_tooltip
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(28, 22)
	btn.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Tokens.SURFACE_SUNKEN
	normal.set_corner_radius_all(Tokens.RADIUS_SM)
	normal.content_margin_left = 2
	normal.content_margin_right = 2
	normal.content_margin_top = 1
	normal.content_margin_bottom = 1
	btn.add_theme_stylebox_override(&"normal", normal)
	btn.add_theme_stylebox_override(&"hover", normal.duplicate())
	var hover: StyleBoxFlat = btn.get_theme_stylebox(&"hover") as StyleBoxFlat
	if hover != null:
		hover.bg_color = Tokens.SURFACE_RAISED
	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Tokens.ACCENT_DIM
	pressed_style.border_color = Tokens.ACCENT
	pressed_style.set_border_width_all(1)
	pressed_style.set_corner_radius_all(Tokens.RADIUS_SM)
	pressed_style.content_margin_left = 2
	pressed_style.content_margin_right = 2
	pressed_style.content_margin_top = 1
	pressed_style.content_margin_bottom = 1
	btn.add_theme_stylebox_override(&"pressed", pressed_style)
	return btn


func _set_toggle_font_emphasis(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override(&"font_color", Tokens.ACCENT)
	else:
		btn.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)


func _make_meter() -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.001
	pb.value = 0.0
	pb.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	pb.custom_minimum_size = Vector2(7, 32)
	pb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return pb


func set_selected(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	if _selected:
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


func bind(
	bus: CodaBus,
	godot_bus_name: String,
	is_master_strip: bool,
	send_targets: Array[CodaBus],
	default_send_target_id: String
) -> void:
	_bus = bus
	_godot_bus_name = godot_bus_name
	_is_master_bus = is_master_strip
	_syncing_ui = true
	_name_edit.text = bus.bus_name
	_fader.set_value_no_signal(bus.volume_db)
	_set_db_field_text(bus.volume_db)
	_mute_btn.set_pressed_no_signal(bus.mute)
	_solo_btn.set_pressed_no_signal(bus.solo)
	_bypass_btn.set_pressed_no_signal(bus.bypass)
	_set_toggle_font_emphasis(_mute_btn, bus.mute)
	_set_toggle_font_emphasis(_solo_btn, bus.solo)
	_set_toggle_font_emphasis(_bypass_btn, bus.bypass)

	_send_option.clear()
	_send_option.visible = not _is_master_bus
	if not _is_master_bus:
		var want: String = String(bus.send_target_id).strip_edges()
		if want.is_empty():
			want = String(default_send_target_id).strip_edges()
		var sel_idx: int = 0
		for i in send_targets.size():
			var t: CodaBus = send_targets[i]
			var label: String = String(t.bus_name).strip_edges()
			if label.is_empty():
				label = "Bus"
			_send_option.add_item(label)
			_send_option.set_item_metadata(i, t.id)
			if t.id == want:
				sel_idx = i
		if _send_option.item_count > 0:
			_send_option.select(clampi(sel_idx, 0, _send_option.item_count - 1))

	_syncing_ui = false
	_refresh_context_menu_enabled()
	_wire_bus_selection_clicks()


func _wire_bus_selection_clicks() -> void:
	var ctrls: Array[Control] = [
		_name_edit,
		_meter_l,
		_meter_r,
		_fader,
		_db_edit,
		_send_option,
		_mute_btn,
		_solo_btn,
		_bypass_btn,
	]
	for c in ctrls:
		if c != null and not c.gui_input.is_connected(_on_bus_select_gui_input):
			c.gui_input.connect(_on_bus_select_gui_input)


func _on_bus_select_gui_input(event: InputEvent) -> void:
	if _bus == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			bus_strip_selected.emit(_bus.id)


func set_volume_no_signal(volume_db: float) -> void:
	if _fader == null or _db_edit == null:
		return
	_syncing_ui = true
	_fader.set_value_no_signal(volume_db)
	_set_db_field_text(volume_db)
	_syncing_ui = false


func _refresh_context_menu_enabled() -> void:
	if _context_menu == null:
		return
	# Disable destructive actions on Master (no parent, cannot be removed/duplicated).
	var is_master: bool = _is_master_bus
	_context_menu.set_item_disabled(_context_menu.get_item_index(_CTX_DUPLICATE_BUS), is_master)
	_context_menu.set_item_disabled(_context_menu.get_item_index(_CTX_DELETE_BUS), is_master)


func _on_context_menu_id_pressed(id: int) -> void:
	if _bus == null:
		return
	match id:
		_CTX_ADD_BUS_HERE:
			context_action_requested.emit(_bus.id, &"add_bus_here")
		_CTX_DUPLICATE_BUS:
			context_action_requested.emit(_bus.id, &"duplicate_bus")
		_CTX_DELETE_BUS:
			context_action_requested.emit(_bus.id, &"delete_bus")
		_CTX_RESET_VOLUME:
			context_action_requested.emit(_bus.id, &"reset_volume")
		_:
			pass


func _on_send_item_selected(index: int) -> void:
	if _syncing_ui or _bus == null:
		return
	if index < 0 or index >= _send_option.item_count:
		return
	var tid: String = str(_send_option.get_item_metadata(index))
	send_target_changed.emit(_bus.id, tid)


func update_meter() -> void:
	if _bus == null or _godot_bus_name.is_empty():
		return
	var peaks: Vector2 = CodaAudioBusMirrorScript.peak_db_for_bus(_godot_bus_name)
	_meter_l.value = _peak_db_to_meter(peaks.x)
	_meter_r.value = _peak_db_to_meter(peaks.y)


func _peak_db_to_meter(db: float) -> float:
	if db <= -80.0:
		return 0.0
	var t: float = clampf((db + 60.0) / 60.0, 0.0, 1.0)
	return t


func _set_db_field_text(vol_db: float) -> void:
	_db_edit.text = "%+.1f" % vol_db


func _commit_bus_name_if_needed() -> void:
	if _syncing_ui or _bus == null:
		return
	var trimmed: String = _name_edit.text.strip_edges()
	if trimmed.is_empty():
		_syncing_ui = true
		_name_edit.text = _bus.bus_name
		_syncing_ui = false
		return
	if trimmed == _bus.bus_name:
		return
	bus_renamed.emit(_bus.id, trimmed)


func _commit_db_field() -> void:
	if _syncing_ui or _bus == null:
		return
	var raw: String = _db_edit.text.strip_edges().to_lower()
	raw = raw.replace("db", "").replace(",", ".").strip_edges()
	if raw.is_empty():
		_syncing_ui = true
		_set_db_field_text(_fader.get_fader_value())
		_syncing_ui = false
		return
	var v: float = raw.to_float()
	v = clampf(snapped(v, FADER_STEP), FADER_MIN_DB, FADER_MAX_DB)
	_syncing_ui = true
	_fader.set_value_no_signal(v)
	_set_db_field_text(v)
	_syncing_ui = false
	volume_changed.emit(_bus.id, v)


func _on_vertical_fader_changed(v: float) -> void:
	if _bus == null or _syncing_ui:
		return
	_set_db_field_text(v)
	volume_changed.emit(_bus.id, v)


func _on_mute_toggled_ui(active: bool) -> void:
	if _bus == null or _syncing_ui:
		return
	_set_toggle_font_emphasis(_mute_btn, active)
	mute_toggled.emit(_bus.id, active)


func _on_solo_toggled_ui(active: bool) -> void:
	if _bus == null or _syncing_ui:
		return
	_set_toggle_font_emphasis(_solo_btn, active)
	solo_toggled.emit(_bus.id, active)


func _on_bypass_toggled_ui(active: bool) -> void:
	if _bus == null or _syncing_ui:
		return
	_set_toggle_font_emphasis(_bypass_btn, active)
	bypass_toggled.emit(_bus.id, active)
