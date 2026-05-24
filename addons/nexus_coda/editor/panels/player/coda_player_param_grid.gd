@tool
class_name CodaPlayerParamGrid
extends VBoxContainer

signal param_value_changed(param_id: String, value: Variant)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

var _empty_label: Label
var _params_host: VBoxContainer


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_empty_label = Label.new()
	_empty_label.text = "Event has no parameters."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_empty_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(_empty_label)

	_params_host = VBoxContainer.new()
	_params_host.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_params_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_params_host)


func rebuild_for_event(event: CodaBrowserNode) -> void:
	for c in _params_host.get_children():
		c.queue_free()
	if event == null:
		_empty_label.visible = false
		return
	if event.event_parameters.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false
	for param in event.event_parameters:
		_append_param_row(param)


func _append_param_row(param: CodaEventParameter) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)

	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(140, 0)
	name_label.text = param.param_name
	name_label.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	name_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	row.add_child(name_label)

	match param.param_type:
		CodaEventParameter.ParamType.FLOAT, CodaEventParameter.ParamType.INT:
			var lo_hi: Vector2 = _resolve_param_range(param)
			var slider := HSlider.new()
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.min_value = lo_hi.x
			slider.max_value = lo_hi.y
			if param.param_type == CodaEventParameter.ParamType.INT:
				slider.step = 1.0
			else:
				slider.step = max(0.001, (lo_hi.y - lo_hi.x) / 200.0)
			var initial: float = clampf(
				CodaEventParameter.to_float_value(param.default_value), lo_hi.x, lo_hi.y
			)
			slider.value = initial
			row.add_child(slider)
			var value_label := Label.new()
			value_label.text = _fmt_param_value(param, initial)
			value_label.custom_minimum_size = Vector2(60, 0)
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value_label.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)
			value_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
			row.add_child(value_label)
			slider.value_changed.connect(_make_param_slider_handler(param.id, value_label, param))
		CodaEventParameter.ParamType.BOOL:
			var cb := CheckBox.new()
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cb.button_pressed = bool(param.default_value)
			row.add_child(cb)
			cb.toggled.connect(_make_param_bool_handler(param.id))
		CodaEventParameter.ParamType.STRING:
			var line := LineEdit.new()
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.text = str(param.default_value)
			line.placeholder_text = "Value"
			row.add_child(line)
			line.text_changed.connect(_make_param_string_handler(param.id))

	_params_host.add_child(row)


static func _resolve_param_range(param: CodaEventParameter) -> Vector2:
	var lo: float = 0.0
	var hi: float = 1.0
	if param.min_value != null and typeof(param.min_value) in [TYPE_FLOAT, TYPE_INT]:
		lo = float(param.min_value)
	if param.max_value != null and typeof(param.max_value) in [TYPE_FLOAT, TYPE_INT]:
		hi = float(param.max_value)
	else:
		hi = max(lo + 1.0, CodaEventParameter.to_float_value(param.default_value) + 1.0)
	if hi <= lo:
		hi = lo + 1.0
	return Vector2(lo, hi)


func _make_param_slider_handler(
	param_id: String, value_label: Label, param: CodaEventParameter
) -> Callable:
	return func(v: float) -> void:
		if value_label != null and is_instance_valid(value_label):
			value_label.text = _fmt_param_value(param, v)
		param_value_changed.emit(param_id, v)


func _make_param_bool_handler(param_id: String) -> Callable:
	return func(on: bool) -> void:
		param_value_changed.emit(param_id, on)


func _make_param_string_handler(param_id: String) -> Callable:
	return func(text: String) -> void:
		param_value_changed.emit(param_id, text)


static func _fmt_param_value(param: CodaEventParameter, v: float) -> String:
	var unit_suffix: String = ""
	if not param.unit_hint.is_empty():
		unit_suffix = " " + param.unit_hint
	if param.param_type == CodaEventParameter.ParamType.INT:
		return "%d%s" % [int(round(v)), unit_suffix]
	return "%.2f%s" % [v, unit_suffix]
