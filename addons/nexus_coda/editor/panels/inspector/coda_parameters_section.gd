@tool
class_name CodaParametersSection
extends VBoxContainer

## Inspector section for the selected event's parameter list.
## Phase 3 owns parameters only (audio is handled by the Graph panel).
## Phase 4 will extend this with bounds, units, smoothing and curve types.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const SectionHeaderScript := preload(
	"res://addons/nexus_coda/editor/theme/coda_section_header.gd"
)

var _project: CodaState = null
var _selected_event: CodaBrowserNode = null
var _draft_parameters: Array[CodaEventParameter] = []

var _header: CodaSectionHeader
var _rows_host: VBoxContainer
var _add_button: Button
var _validation_label: Label


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_header = SectionHeaderScript.new()
	_header.heading = "Set Parameters"
	add_child(_header)

	_add_button = Button.new()
	_add_button.text = "+"
	_add_button.tooltip_text = "Add parameter"
	_add_button.pressed.connect(_on_add_pressed)
	_header.add_trailing(_add_button)

	var hint := Label.new()
	hint.text = "Gameplay writes these values at runtime (switch, blend, modulation)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	hint.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(hint)

	_rows_host = VBoxContainer.new()
	_rows_host.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_rows_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rows_host)

	_validation_label = Label.new()
	_validation_label.add_theme_color_override(&"font_color", Tokens.DANGER)
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.visible = false
	add_child(_validation_label)


func attach_project(project: CodaState) -> void:
	_project = project


func set_event(event: Variant) -> void:
	var bn := event as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
		_draft_parameters.clear()
		_clear_rows()
		_validation_label.visible = false
		return
	if _selected_event != null and bn.id == _selected_event.id:
		_selected_event = bn
		return
	_selected_event = bn
	_load_drafts_from_selection()
	_rebuild_rows()
	_apply_validation_message("")


func _load_drafts_from_selection() -> void:
	_draft_parameters.clear()
	if _selected_event == null:
		return
	for p in _selected_event.event_parameters:
		_draft_parameters.append(p.clone_keep_id())


func _clear_rows() -> void:
	for c in _rows_host.get_children():
		c.queue_free()


func _rebuild_rows() -> void:
	_clear_rows()
	for i in range(_draft_parameters.size()):
		_append_row(_draft_parameters[i], i)


func _append_row(param: CodaEventParameter, index: int) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)

	var name_edit := LineEdit.new()
	name_edit.text = param.param_name
	name_edit.placeholder_text = "Name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(_make_name_handler(index))
	row.add_child(name_edit)

	var type_ob := OptionButton.new()
	type_ob.add_item("Float", CodaEventParameter.ParamType.FLOAT)
	type_ob.add_item("Int", CodaEventParameter.ParamType.INT)
	type_ob.add_item("Bool", CodaEventParameter.ParamType.BOOL)
	type_ob.add_item("String", CodaEventParameter.ParamType.STRING)
	type_ob.select(_type_option_index(param.param_type))
	type_ob.item_selected.connect(_make_type_handler(index, type_ob))
	row.add_child(type_ob)

	var default_slot := HBoxContainer.new()
	default_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(default_slot)

	var def_float := SpinBox.new()
	def_float.min_value = -1e12
	def_float.max_value = 1e12
	def_float.step = 0.01
	def_float.value = float(param.default_value) if param.param_type == CodaEventParameter.ParamType.FLOAT else 0.0
	def_float.value_changed.connect(_make_default_float_handler(index))
	default_slot.add_child(def_float)

	var def_int := SpinBox.new()
	def_int.min_value = -2147483648
	def_int.max_value = 2147483647
	def_int.step = 1
	def_int.rounded = true
	def_int.value = int(param.default_value) if param.param_type == CodaEventParameter.ParamType.INT else 0
	def_int.value_changed.connect(_make_default_int_handler(index))
	default_slot.add_child(def_int)

	var def_bool := CheckBox.new()
	def_bool.button_pressed = bool(param.default_value) if param.param_type == CodaEventParameter.ParamType.BOOL else false
	def_bool.toggled.connect(_make_default_bool_handler(index))
	default_slot.add_child(def_bool)

	var def_string := LineEdit.new()
	def_string.placeholder_text = "Default"
	def_string.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	def_string.text = str(param.default_value) if param.param_type == CodaEventParameter.ParamType.STRING else ""
	def_string.text_changed.connect(_make_default_string_handler(index))
	default_slot.add_child(def_string)

	_update_default_widgets_visibility(param.param_type, def_float, def_int, def_bool, def_string)

	var unit_edit := LineEdit.new()
	unit_edit.placeholder_text = "Unit"
	unit_edit.custom_minimum_size = Vector2(48, 0)
	unit_edit.text = param.unit_hint
	unit_edit.text_changed.connect(
		func(t: String) -> void:
			if index >= 0 and index < _draft_parameters.size():
				_draft_parameters[index].unit_hint = t
				_push_changes()
	)
	row.add_child(unit_edit)

	var smooth_spin := SpinBox.new()
	smooth_spin.min_value = 0.0
	smooth_spin.max_value = 5000.0
	smooth_spin.step = 1.0
	smooth_spin.tooltip_text = "Smoothing ms (0 = instant)"
	smooth_spin.value = param.smoothing_ms
	smooth_spin.value_changed.connect(
		func(v: float) -> void:
			if index >= 0 and index < _draft_parameters.size():
				_draft_parameters[index].smoothing_ms = v
				_push_changes()
	)
	row.add_child(smooth_spin)

	var remove_btn := Button.new()
	remove_btn.text = "−"
	remove_btn.tooltip_text = "Remove parameter"
	remove_btn.pressed.connect(_make_remove_handler(index))
	row.add_child(remove_btn)

	_rows_host.add_child(row)


func _type_option_index(t: CodaEventParameter.ParamType) -> int:
	match t:
		CodaEventParameter.ParamType.FLOAT:
			return 0
		CodaEventParameter.ParamType.INT:
			return 1
		CodaEventParameter.ParamType.BOOL:
			return 2
		CodaEventParameter.ParamType.STRING:
			return 3
	return 0


func _update_default_widgets_visibility(
	t: CodaEventParameter.ParamType,
	def_float: SpinBox,
	def_int: SpinBox,
	def_bool: CheckBox,
	def_string: LineEdit
) -> void:
	def_float.visible = t == CodaEventParameter.ParamType.FLOAT
	def_int.visible = t == CodaEventParameter.ParamType.INT
	def_bool.visible = t == CodaEventParameter.ParamType.BOOL
	def_string.visible = t == CodaEventParameter.ParamType.STRING


func _make_name_handler(index: int) -> Callable:
	return func(new_text: String) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].param_name = new_text
			_push_changes()


func _make_type_handler(index: int, type_ob: OptionButton) -> Callable:
	return func(sel_idx: int) -> void:
		if index < 0 or index >= _draft_parameters.size():
			return
		var tid: int = type_ob.get_item_id(sel_idx)
		var t: CodaEventParameter.ParamType = tid as CodaEventParameter.ParamType
		var p: CodaEventParameter = _draft_parameters[index]
		p.param_type = t
		p.default_value = CodaEventParameter._default_for_type(t)
		_rebuild_rows()
		_push_changes()


func _make_default_float_handler(index: int) -> Callable:
	return func(v: float) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].default_value = v
			_push_changes()


func _make_default_int_handler(index: int) -> Callable:
	return func(v: float) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].default_value = int(v)
			_push_changes()


func _make_default_bool_handler(index: int) -> Callable:
	return func(on: bool) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].default_value = on
			_push_changes()


func _make_default_string_handler(index: int) -> Callable:
	return func(new_text: String) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].default_value = new_text
			_push_changes()


func _make_remove_handler(index: int) -> Callable:
	return func() -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters.remove_at(index)
			_rebuild_rows()
			_push_changes()


func _on_add_pressed() -> void:
	if _selected_event == null:
		return
	var np := CodaEventParameter.new()
	np.param_name = CodaEventParameter.suggest_next_parameter_name(_draft_parameters)
	np.param_type = CodaEventParameter.ParamType.FLOAT
	np.default_value = CodaEventParameter._default_for_type(np.param_type)
	_draft_parameters.append(np)
	_rebuild_rows()
	_push_changes()


func _push_changes() -> void:
	if _project == null or _selected_event == null:
		return
	var err: String = _project.set_event_parameters(_selected_event.id, _draft_parameters)
	_apply_validation_message(err)


func _apply_validation_message(err: String) -> void:
	if _validation_label == null:
		return
	if err.is_empty():
		_validation_label.text = ""
		_validation_label.visible = false
	else:
		_validation_label.text = err
		_validation_label.visible = true
