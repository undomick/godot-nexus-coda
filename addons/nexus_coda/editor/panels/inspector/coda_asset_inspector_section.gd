@tool
class_name CodaAssetInspectorSection
extends VBoxContainer

## Read-only summary for a folder or asset node from the Assets browser tab.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaSectionHeaderScript := preload(
	"res://addons/nexus_coda/editor/theme/coda_section_header.gd"
)

var _section_header: CodaSectionHeader
var _body: Label
var _path_label: Label
var _path_value: LineEdit
var _duration_row: HBoxContainer
var _duration_label: Label
var _duration_value: Label


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)


func _ready() -> void:
	_section_header = CodaSectionHeaderScript.new()
	_section_header.heading = "Asset"
	add_child(_section_header)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_body.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	add_child(_body)

	var path_row := HBoxContainer.new()
	path_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	add_child(path_row)
	_path_label = Label.new()
	_path_label.text = "Source"
	_path_label.custom_minimum_size = Vector2(72, 0)
	_path_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_path_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	path_row.add_child(_path_label)
	_path_value = LineEdit.new()
	_path_value.editable = false
	_path_value.select_all_on_focus = true
	_path_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(_path_value)

	_duration_row = HBoxContainer.new()
	_duration_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	add_child(_duration_row)
	_duration_label = Label.new()
	_duration_label.text = "Length"
	_duration_label.custom_minimum_size = Vector2(72, 0)
	_duration_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_duration_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_duration_row.add_child(_duration_label)
	_duration_value = Label.new()
	_duration_value.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_duration_value.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_duration_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_duration_row.add_child(_duration_value)


func set_node(node: CodaBrowserNode) -> void:
	if _body == null:
		if node != null:
			call_deferred(&"set_node", node)
		return
	if node == null:
		visible = false
		return
	visible = true
	if node.kind == CodaBrowserNode.Kind.ASSET:
		_section_header.heading = "Asset"
		_body.text = "Imported audio entry. Drag from the Assets tree into the timeline."
		_path_label.visible = true
		_path_value.visible = true
		_duration_row.visible = true
		var p: String = node.asset_source_path.strip_edges()
		_path_value.text = p if not p.is_empty() else "(no file path)"
		_duration_value.text = _format_stream_length(p)
	elif node.is_folder():
		_section_header.heading = "Folder"
		_body.text = "Organize assets here. Select an audio asset leaf to see file details."
		_path_label.visible = false
		_path_value.visible = false
		_duration_row.visible = false
	else:
		visible = false


func _format_stream_length(res_path: String) -> String:
	if res_path.is_empty() or not res_path.begins_with("res://"):
		return "—"
	if not ResourceLoader.exists(res_path):
		return "(not imported / missing)"
	var res: Resource = ResourceLoader.load(res_path)
	if res is AudioStream:
		var len_s: float = (res as AudioStream).get_length()
		if len_s > 0.0:
			return "%.2f s" % len_s
	return "—"
