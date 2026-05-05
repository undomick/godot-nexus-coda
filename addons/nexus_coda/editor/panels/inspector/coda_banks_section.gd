@tool
class_name CodaBanksSection
extends VBoxContainer

## Inspector section that lists which banks include the selected event and lets the designer
## add/remove the event from any project bank. Banks themselves are managed via Build → Banks…

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const SectionHeaderScript := preload("res://addons/nexus_coda/editor/theme/coda_section_header.gd")

var _project: CodaState = null
var _selected_event: CodaBrowserNode = null
var _header: CodaSectionHeader
var _rows_host: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_header = SectionHeaderScript.new()
	_header.heading = "Banks"
	add_child(_header)

	_empty_label = Label.new()
	_empty_label.text = "No banks defined. Use Build → New Bank to create one."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_empty_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_empty_label.visible = false
	add_child(_empty_label)

	_rows_host = VBoxContainer.new()
	_rows_host.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_rows_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rows_host)


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_on_structure_changed):
			_project.structure_changed.disconnect(_on_structure_changed)
	_project = project
	if _project != null:
		if not _project.structure_changed.is_connected(_on_structure_changed):
			_project.structure_changed.connect(_on_structure_changed)
	_rebuild_rows()


func set_event(event: Variant) -> void:
	var bn := event as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
		_rebuild_rows()
		return
	_selected_event = bn
	_rebuild_rows()


func _on_structure_changed() -> void:
	_rebuild_rows()


func _rebuild_rows() -> void:
	for c in _rows_host.get_children():
		c.queue_free()
	if _project == null or _selected_event == null:
		_empty_label.visible = false
		return
	if _project.banks.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false
	for bank in _project.banks:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
		_rows_host.add_child(row)

		var cb := CheckBox.new()
		cb.text = bank.bank_name
		cb.button_pressed = bank.contains_event(_selected_event.id)
		cb.tooltip_text = (
			"Include this event in bank \"%s\". Run Build → Export to package the bank."
			% bank.bank_name
		)
		cb.toggled.connect(_make_toggle_handler(bank.id))
		row.add_child(cb)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)

		var counter := Label.new()
		counter.text = "%d events" % bank.event_ids.size()
		counter.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
		counter.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
		row.add_child(counter)


func _make_toggle_handler(bank_id: String) -> Callable:
	return func(state: bool) -> void:
		if _project == null or _selected_event == null:
			return
		if state:
			_project.add_event_to_bank(bank_id, _selected_event.id)
		else:
			_project.remove_event_from_bank(bank_id, _selected_event.id)
