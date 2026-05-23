@tool
class_name CodaBankInspectorSection
extends VBoxContainer

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const SectionHeaderScript := preload("res://addons/nexus_coda/editor/theme/coda_section_header.gd")

var _project: CodaState = null
var _bank: CodaBank = null
var _name_edit: LineEdit
var _events_host: VBoxContainer
var _empty_events_label: Label
var _hint: Label
var _suppress_name_commit: bool = false
var _suppress_event_toggle: bool = false


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := SectionHeaderScript.new()
	header.heading = "Bank"
	add_child(header)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Bank name"
	_name_edit.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_bank_name())
	_name_edit.focus_exited.connect(_commit_bank_name)
	add_child(_name_edit)
	_events_host = VBoxContainer.new()
	_events_host.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_events_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_events_host.custom_minimum_size = Vector2(0, 120)
	add_child(_events_host)
	_empty_events_label = Label.new()
	_empty_events_label.text = "No events in project."
	_empty_events_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_events_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_empty_events_label.visible = false
	add_child(_empty_events_label)
	_hint = Label.new()
	_hint.text = "Use Build → Export Bank to publish this bank."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	add_child(_hint)


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_on_structure_changed):
			_project.structure_changed.disconnect(_on_structure_changed)
	_project = project
	if _project != null:
		if not _project.structure_changed.is_connected(_on_structure_changed):
			_project.structure_changed.connect(_on_structure_changed)
	_refresh()


func set_bank(bank_id: String) -> void:
	_bank = null
	if _project != null and not bank_id.is_empty():
		_bank = _project.find_bank_by_id(bank_id)
	_refresh()


func _on_structure_changed() -> void:
	_refresh()


func _refresh() -> void:
	for c in _events_host.get_children():
		c.queue_free()
	if _bank == null:
		visible = false
		return
	visible = true
	_suppress_name_commit = true
	_name_edit.text = _bank.bank_name
	_suppress_name_commit = false
	var events: Array[CodaBrowserNode] = _collect_project_events()
	_empty_events_label.visible = events.is_empty()
	for ev in events:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
		_events_host.add_child(row)
		var cb := CheckBox.new()
		cb.text = ev.name
		cb.button_pressed = _bank.contains_event(ev.id)
		cb.toggled.connect(_make_toggle_handler(ev.id))
		row.add_child(cb)


func _collect_project_events() -> Array[CodaBrowserNode]:
	var out: Array[CodaBrowserNode] = []
	if _project == null or _project.events_root == null:
		return out
	_walk_events(_project.events_root, out)
	return out


func _walk_events(node: CodaBrowserNode, out: Array[CodaBrowserNode]) -> void:
	if node.kind == CodaBrowserNode.Kind.EVENT:
		out.append(node)
	for child in node.children:
		_walk_events(child, out)


func _make_toggle_handler(event_id: String) -> Callable:
	return func(state: bool) -> void:
		if _suppress_event_toggle or _project == null or _bank == null:
			return
		if state:
			_project.add_event_to_bank(_bank.id, event_id)
		else:
			_project.remove_event_from_bank(_bank.id, event_id)


func _commit_bank_name() -> void:
	if _suppress_name_commit or _project == null or _bank == null:
		return
	var trimmed: String = _name_edit.text.strip_edges()
	if trimmed == _bank.bank_name:
		return
	_project.rename_bank(_bank.id, trimmed)
