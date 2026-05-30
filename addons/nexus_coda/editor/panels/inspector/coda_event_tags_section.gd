@tool
class_name CodaEventTagsSection
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
var _tags_edit: LineEdit


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_header = SectionHeaderScript.new()
	_header.heading = "Tags"
	add_child(_header)

	_hint = Label.new()
	_hint.text = "Editor-only labels. Filter the browser with #tag (e.g. #ui)."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_hint.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(_hint)

	_tags_edit = LineEdit.new()
	_tags_edit.placeholder_text = "ui, combat, ambient"
	_tags_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tags_edit.text_changed.connect(_on_tags_changed)
	add_child(_tags_edit)


func attach_project(project: CodaState) -> void:
	_project = project


func set_event(event: Variant) -> void:
	var bn := event as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
		_suppress_writeback = true
		_tags_edit.text = ""
		_suppress_writeback = false
		return
	if _selected_event != null and bn.id == _selected_event.id:
		_selected_event = bn
		return
	_selected_event = bn
	_suppress_writeback = true
	_tags_edit.text = ", ".join(bn.event_tags)
	_suppress_writeback = false


func _on_tags_changed(new_text: String) -> void:
	if _suppress_writeback or _project == null or _selected_event == null:
		return
	var tags: PackedStringArray = PackedStringArray()
	for part in new_text.split(",", false):
		var t: String = CodaBrowserNode.normalize_tag(part)
		if not t.is_empty():
			tags.append(t)
	_project.set_event_tags(_selected_event.id, tags)
