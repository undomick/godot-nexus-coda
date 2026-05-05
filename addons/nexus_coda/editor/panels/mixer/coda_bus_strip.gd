@tool
class_name CodaBusStrip
extends PanelContainer

## Vertical strip for one CodaBus: name + fader + dB readout + mute/solo + peak meter.

signal volume_changed(bus_id: String, volume_db: float)
signal mute_toggled(bus_id: String, mute: bool)
signal solo_toggled(bus_id: String, solo: bool)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaAudioBusMirrorScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_mirror.gd")

var _bus: CodaBus = null
var _name_label: Label
var _fader: VSlider
var _db_label: Label
var _mute_btn: CheckButton
var _solo_btn: CheckButton
var _meter_l: ProgressBar
var _meter_r: ProgressBar
var _godot_bus_name: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(96, 240)
	add_theme_stylebox_override(
		&"panel",
		Tokens.make_panel_stylebox(Tokens.SURFACE_RAISED, Tokens.SURFACE_BORDER, Tokens.RADIUS_SM)
	)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	add_child(col)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_name_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	col.add_child(_name_label)

	var meter_row := HBoxContainer.new()
	meter_row.add_theme_constant_override(&"separation", 2)
	meter_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(meter_row)

	_meter_l = _make_meter()
	_meter_r = _make_meter()
	meter_row.add_child(_meter_l)
	meter_row.add_child(_meter_r)

	var fader_row := HBoxContainer.new()
	fader_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fader_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fader_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(fader_row)

	_fader = VSlider.new()
	_fader.min_value = -60.0
	_fader.max_value = 12.0
	_fader.step = 0.1
	_fader.value = 0.0
	_fader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fader.custom_minimum_size = Vector2(24, 140)
	_fader.value_changed.connect(_on_fader_changed)
	fader_row.add_child(_fader)

	_db_label = Label.new()
	_db_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_db_label.text = "0.0 dB"
	_db_label.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)
	_db_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	col.add_child(_db_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	col.add_child(btn_row)

	_mute_btn = CheckButton.new()
	_mute_btn.text = "M"
	_mute_btn.tooltip_text = "Mute"
	_mute_btn.toggled.connect(_on_mute_toggled)
	btn_row.add_child(_mute_btn)

	_solo_btn = CheckButton.new()
	_solo_btn.text = "S"
	_solo_btn.tooltip_text = "Solo"
	_solo_btn.toggled.connect(_on_solo_toggled)
	btn_row.add_child(_solo_btn)


func _make_meter() -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.step = 0.001
	pb.value = 0.0
	pb.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	pb.custom_minimum_size = Vector2(7, 140)
	return pb


func bind(bus: CodaBus, godot_bus_name: String) -> void:
	_bus = bus
	_godot_bus_name = godot_bus_name
	_name_label.text = bus.bus_name
	_fader.set_value_no_signal(bus.volume_db)
	_db_label.text = "%+0.1f dB" % bus.volume_db
	_mute_btn.set_pressed_no_signal(bus.mute)
	_solo_btn.set_pressed_no_signal(bus.solo)


func update_meter() -> void:
	if _bus == null or _godot_bus_name.is_empty():
		return
	var peaks: Vector2 = CodaAudioBusMirrorScript.peak_db_for_bus(_godot_bus_name)
	_meter_l.value = _peak_db_to_meter(peaks.x)
	_meter_r.value = _peak_db_to_meter(peaks.y)


func _peak_db_to_meter(db: float) -> float:
	if db <= -80.0:
		return 0.0
	# Map [-60..0] dB to [0..1] (clamped) so the strip looks lively but doesn't pin to top.
	var t: float = clampf((db + 60.0) / 60.0, 0.0, 1.0)
	return t


func _on_fader_changed(v: float) -> void:
	if _bus == null:
		return
	_db_label.text = "%+0.1f dB" % v
	volume_changed.emit(_bus.id, v)


func _on_mute_toggled(state: bool) -> void:
	if _bus == null:
		return
	mute_toggled.emit(_bus.id, state)


func _on_solo_toggled(state: bool) -> void:
	if _bus == null:
		return
	solo_toggled.emit(_bus.id, state)
