@tool
class_name CodaEventAuthoringView
extends PanelContainer

## Event parameter + audio authoring UI. Own PackedScene for isolated refactor/styling.

var _browser_panel: Control = null
var _selected_event: CodaBrowserNode = null
var _draft_parameters: Array[CodaEventParameter] = []
var _draft_audio_paths: PackedStringArray = PackedStringArray()

@onready var _placeholder: Label = %PlaceholderLabel
@onready var _event_section: Control = %EventSection
@onready var _event_name_label: Label = %EventNameLabel
@onready var _parameters_host: VBoxContainer = %ParametersHost
@onready var _audio_list: ItemList = %AudioList
@onready var _validation_label: Label = %ValidationLabel
@onready var _add_param_button: Button = %AddParameterButton
@onready var _browse_audio_button: Button = %BrowseAudioButton
@onready var _remove_audio_button: Button = %RemoveAudioButton

var _audio_dialog: FileDialog

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")


func _ready() -> void:
	_audio_dialog = FileDialog.new()
	_audio_dialog.access = FileDialog.ACCESS_RESOURCES
	_audio_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_audio_dialog.title = "Pick Audio Resource"
	_audio_dialog.add_filter("*.wav, *.ogg, *.mp3, *.flac, *.webm", "Audio")
	_audio_dialog.file_selected.connect(_on_audio_file_picked)
	add_child(_audio_dialog)
	_add_param_button.pressed.connect(_on_add_parameter_pressed)
	_browse_audio_button.pressed.connect(_on_browse_audio_pressed)
	_remove_audio_button.pressed.connect(_on_remove_audio_pressed)
	_clear_ui()


func set_browser_panel(browser_panel: Control) -> void:
	_browser_panel = browser_panel


func _get_project():
	if _browser_panel != null and _browser_panel.has_method(&"get_project"):
		return _browser_panel.call(&"get_project")
	return null


func on_browser_event_selected(node: Variant) -> void:
	var tag := "null"
	if node != null:
		tag = "CodaBrowserNode" if node is CodaBrowserNode else str(typeof(node))
	NexusCodaLog.info("editor_panel", "on_browser_event_selected (node=%s)" % tag)
	var bn := node as CodaBrowserNode
	if bn == null:
		NexusCodaLog.debug("editor_panel", "selection cleared (null or wrong type)")
		_clear_ui()
		return
	if bn.kind != CodaBrowserNode.Kind.EVENT:
		NexusCodaLog.debug("editor_panel", 'selection not an EVENT ("%s") — clearing UI' % bn.name)
		_clear_ui()
		return
	_selected_event = bn
	NexusCodaLog.info("editor_panel", 'show authoring for EVENT "%s"' % bn.name)
	_load_drafts_from_selection()
	_refresh_event_section_visibility()
	_apply_validation_ui()


func _clear_ui() -> void:
	_selected_event = null
	_draft_parameters.clear()
	_draft_audio_paths.clear()
	_placeholder.visible = true
	_event_section.visible = false
	_clear_parameter_rows()
	_audio_list.clear()
	_validation_label.text = ""


func _refresh_event_section_visibility() -> void:
	var show_ev: bool = _selected_event != null
	_placeholder.visible = not show_ev
	_event_section.visible = show_ev
	if not show_ev:
		return
	_event_name_label.text = 'Event: "%s"' % _selected_event.name
	_rebuild_parameter_editor()
	_refresh_audio_list()


func _load_drafts_from_selection() -> void:
	_draft_parameters.clear()
	if _selected_event == null:
		return
	for p in _selected_event.event_parameters:
		_draft_parameters.append(p.clone_keep_id())
	_draft_audio_paths = _selected_event.event_audio_paths.duplicate()


func _clear_parameter_rows() -> void:
	for c in _parameters_host.get_children():
		c.queue_free()


func _rebuild_parameter_editor() -> void:
	_clear_parameter_rows()
	for i in range(_draft_parameters.size()):
		_append_parameter_row(_draft_parameters[i], i)


func _append_parameter_row(param: CodaEventParameter, index: int) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_edit := LineEdit.new()
	name_edit.text = param.param_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.placeholder_text = "Name"
	name_edit.text_changed.connect(_make_param_name_handler(index))
	var type_ob := OptionButton.new()
	type_ob.add_item("Float", CodaEventParameter.ParamType.FLOAT)
	type_ob.add_item("Int", CodaEventParameter.ParamType.INT)
	type_ob.add_item("Bool", CodaEventParameter.ParamType.BOOL)
	type_ob.add_item("String", CodaEventParameter.ParamType.STRING)
	type_ob.select(_type_option_index(param.param_type))
	type_ob.item_selected.connect(_make_type_handler(index, type_ob))
	var default_slot := HBoxContainer.new()
	default_slot.custom_minimum_size.x = 120
	var def_float := SpinBox.new()
	def_float.min_value = -1e12
	def_float.max_value = 1e12
	def_float.step = 0.01
	def_float.value = float(param.default_value) if param.param_type == CodaEventParameter.ParamType.FLOAT else 0.0
	def_float.value_changed.connect(_make_default_float_handler(index))
	var def_int := SpinBox.new()
	def_int.min_value = -2147483648
	def_int.max_value = 2147483647
	def_int.step = 1
	def_int.rounded = true
	def_int.value = int(param.default_value) if param.param_type == CodaEventParameter.ParamType.INT else 0
	def_int.value_changed.connect(_make_default_int_handler(index))
	var def_bool := CheckBox.new()
	def_bool.button_pressed = bool(param.default_value) if param.param_type == CodaEventParameter.ParamType.BOOL else false
	def_bool.toggled.connect(_make_default_bool_handler(index))
	var def_string := LineEdit.new()
	def_string.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	def_string.placeholder_text = "Default"
	def_string.text = str(param.default_value) if param.param_type == CodaEventParameter.ParamType.STRING else ""
	def_string.text_changed.connect(_make_default_string_handler(index))
	default_slot.add_child(def_float)
	default_slot.add_child(def_int)
	default_slot.add_child(def_bool)
	default_slot.add_child(def_string)
	_update_default_widgets_visibility(
		param.param_type, def_float, def_int, def_bool, def_string
	)
	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(_make_remove_param_handler(index))
	row.add_child(name_edit)
	row.add_child(type_ob)
	default_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(default_slot)
	row.add_child(remove_btn)
	_parameters_host.add_child(row)


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


func _make_param_name_handler(index: int) -> Callable:
	return func(new_text: String) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].param_name = new_text
			_push_authoring()


func _make_type_handler(index: int, type_ob: OptionButton) -> Callable:
	return func(sel_idx: int) -> void:
		if index < 0 or index >= _draft_parameters.size():
			return
		var tid: int = type_ob.get_item_id(sel_idx)
		var t: CodaEventParameter.ParamType = tid as CodaEventParameter.ParamType
		var p: CodaEventParameter = _draft_parameters[index]
		p.param_type = t
		p.default_value = CodaEventParameter._default_for_type(t)
		_rebuild_parameter_editor()
		_push_authoring()


func _make_default_float_handler(index: int) -> Callable:
	return func(v: float) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].default_value = v
			_push_authoring()


func _make_default_int_handler(index: int) -> Callable:
	return func(v: float) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].default_value = int(v)
			_push_authoring()


func _make_default_bool_handler(index: int) -> Callable:
	return func(on: bool) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].default_value = on
			_push_authoring()


func _make_default_string_handler(index: int) -> Callable:
	return func(new_text: String) -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters[index].default_value = new_text
			_push_authoring()


func _make_remove_param_handler(index: int) -> Callable:
	return func() -> void:
		if index >= 0 and index < _draft_parameters.size():
			_draft_parameters.remove_at(index)
			_rebuild_parameter_editor()
			_push_authoring()


func _on_add_parameter_pressed() -> void:
	if _selected_event == null:
		return
	var np := CodaEventParameter.new()
	np.param_name = CodaEventParameter.suggest_next_parameter_name(_draft_parameters)
	np.param_type = CodaEventParameter.ParamType.FLOAT
	np.default_value = CodaEventParameter._default_for_type(np.param_type)
	_draft_parameters.append(np)
	_rebuild_parameter_editor()
	_push_authoring()


func _refresh_audio_list() -> void:
	_audio_list.clear()
	for p in _draft_audio_paths:
		_audio_list.add_item(p)


func _on_browse_audio_pressed() -> void:
	if _selected_event == null:
		return
	_audio_dialog.popup_centered_ratio(0.5)


func _on_audio_file_picked(path: String) -> void:
	var s: String = path.strip_edges()
	if s.is_empty():
		return
	if not _draft_audio_paths.has(s):
		_draft_audio_paths.append(s)
	_refresh_audio_list()
	_push_authoring()


func _on_remove_audio_pressed() -> void:
	var sel: PackedInt32Array = _audio_list.get_selected_items()
	if sel.size() == 0:
		return
	var idx: int = int(sel[0])
	if idx >= 0 and idx < _draft_audio_paths.size():
		_draft_audio_paths.remove_at(idx)
	_refresh_audio_list()
	_push_authoring()


func _push_authoring() -> void:
	if _selected_event == null:
		return
	var proj = _get_project()
	if proj == null:
		return
	var err: String = proj.set_event_authoring_data(
		_selected_event.id,
		_draft_parameters,
		_draft_audio_paths
	)
	_apply_validation_message(err)
	if err.is_empty():
		_load_drafts_from_selection()


func _apply_validation_ui() -> void:
	_apply_validation_message("")


func _apply_validation_message(err: String) -> void:
	if err.is_empty():
		_validation_label.text = ""
		_validation_label.visible = false
	else:
		_validation_label.text = err
		_validation_label.visible = true
