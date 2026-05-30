@tool
class_name CodaEventNotesSection
extends VBoxContainer

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const SectionHeaderScript := preload(
	"res://addons/nexus_coda/editor/theme/coda_section_header.gd"
)

var _project: CodaState = null
var _selected_event: CodaBrowserNode = null
var _suppress_writeback: bool = false

var _header: CodaSectionHeader
var _hint: Label
var _notes_edit: TextEdit


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_header = SectionHeaderScript.new()
	_header.heading = "Notes"
	add_child(_header)

	_hint = Label.new()
	_hint.text = "Editor-only documentation for this event."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_hint.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(_hint)

	_notes_edit = TextEdit.new()
	_notes_edit.placeholder_text = "Design notes, TODOs, context for the team..."
	_notes_edit.custom_minimum_size = Vector2(0, 72)
	_notes_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_edit.text_changed.connect(_on_notes_changed)
	add_child(_notes_edit)


func attach_project(project: CodaState) -> void:
	_project = project


func set_event(event: Variant) -> void:
	var bn := event as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
		_suppress_writeback = true
		_notes_edit.text = ""
		_suppress_writeback = false
		return
	if _selected_event != null and bn.id == _selected_event.id:
		_selected_event = bn
		return
	_selected_event = bn
	_suppress_writeback = true
	_notes_edit.text = bn.event_notes
	_suppress_writeback = false


func _on_notes_changed() -> void:
	if _suppress_writeback or _project == null or _selected_event == null:
		return
	_project.set_event_notes(_selected_event.id, _notes_edit.text)
