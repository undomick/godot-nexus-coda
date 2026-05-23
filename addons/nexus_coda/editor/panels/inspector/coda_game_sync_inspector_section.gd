@tool
class_name CodaGameSyncInspectorSection
extends VBoxContainer

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const SectionHeaderScript := preload("res://addons/nexus_coda/editor/theme/coda_section_header.gd")

var _project: CodaState = null
var _rule: CodaGameSyncRule = null
var _signal_edit: LineEdit
var _action_picker: OptionButton
var _target_edit: LineEdit
var _fade_spin: SpinBox
var _enabled_check: CheckBox


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := SectionHeaderScript.new()
	header.heading = "Game Sync Rule"
	add_child(header)
	_signal_edit = _add_row("Signal", LineEdit.new())
	_signal_edit.text_changed.connect(func(_t: String) -> void: _write_rule())
	_action_picker = OptionButton.new()
	_action_picker.add_item("Set Music", CodaGameSyncRule.Action.SET_MUSIC)
	_action_picker.add_item("Stop Music", CodaGameSyncRule.Action.STOP_MUSIC)
	_action_picker.add_item("Play Event", CodaGameSyncRule.Action.PLAY_EVENT)
	_action_picker.add_item("Set Parameter", CodaGameSyncRule.Action.SET_PARAMETER)
	_action_picker.add_item("Apply Snapshot", CodaGameSyncRule.Action.APPLY_SNAPSHOT)
	_action_picker.item_selected.connect(func(_i: int) -> void: _write_rule())
	add_child(_make_row("Action", _action_picker))
	_target_edit = _add_row("Target", LineEdit.new())
	_target_edit.text_changed.connect(func(_t: String) -> void: _write_rule())
	_fade_spin = SpinBox.new()
	_fade_spin.min_value = 0.0
	_fade_spin.max_value = 60000.0
	_fade_spin.step = 50.0
	_fade_spin.value_changed.connect(func(_v: float) -> void: _write_rule())
	add_child(_make_row("Fade (ms)", _fade_spin))
	_enabled_check = CheckBox.new()
	_enabled_check.text = "Enabled"
	_enabled_check.toggled.connect(func(_v: bool) -> void: _write_rule())
	add_child(_enabled_check)
	var cond := LineEdit.new()
	cond.editable = false
	cond.placeholder_text = "Coming soon"
	cond.tooltip_text = "Expression-based conditions are planned for a later phase."
	add_child(_make_row("Condition", cond))
	var trans := LineEdit.new()
	trans.editable = false
	trans.placeholder_text = "Coming soon"
	trans.tooltip_text = "Transition matrix ids are planned for a later phase."
	add_child(_make_row("Transition", trans))


func attach_project(project: CodaState) -> void:
	_project = project


func set_rule_payload(payload: Dictionary) -> void:
	var rule_id: String = str(payload.get("item_id", ""))
	_rule = null
	if _project != null and not rule_id.is_empty():
		for r in _project.game_sync_rules:
			if r.id == rule_id:
				_rule = r
				break
	_refresh_fields()


func _refresh_fields() -> void:
	if _rule == null:
		visible = false
		return
	visible = true
	_signal_edit.text = _rule.signal_name
	_target_edit.text = _rule.target_event_path
	_fade_spin.set_value_no_signal(float(_rule.fade_ms))
	_enabled_check.set_pressed_no_signal(_rule.enabled)
	for i in _action_picker.item_count:
		if _action_picker.get_item_id(i) == int(_rule.action):
			_action_picker.select(i)
			break


func _write_rule() -> void:
	if _rule == null or _project == null:
		return
	_rule.signal_name = _signal_edit.text.strip_edges()
	_rule.target_event_path = _target_edit.text.strip_edges()
	_rule.fade_ms = int(_fade_spin.value)
	_rule.enabled = _enabled_check.button_pressed
	_rule.action = _action_picker.get_selected_id() as CodaGameSyncRule.Action
	_project.project_dirty.emit()


func _add_row(label_text: String, control: Control) -> Control:
	add_child(_make_row(label_text, control))
	return control


func _make_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(120, 0)
	lbl.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row
