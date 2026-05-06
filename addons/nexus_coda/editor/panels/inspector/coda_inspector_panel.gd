@tool
class_name CodaInspectorPanel
extends VBoxContainer

## Stacked-section inspector for the currently selected browser node.
## Layout:
##   - Header (event name)
##   - Parameters section
##   - Modulation section
##   - Banks section
##   - Output placeholder (bus routing lives in the Mixer)
##
## Transport (Play / Stop / Loop / Pause / time / meter) lives in the dedicated
## Player panel. Inspector no longer owns playback state.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")
const CodaSectionHeaderScript := preload("res://addons/nexus_coda/editor/theme/coda_section_header.gd")
const CodaParametersSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_parameters_section.gd"
)
const CodaModulationSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_modulation_section.gd"
)
const CodaBanksSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_banks_section.gd"
)

var _browser_panel: Control = null
var _project: CodaState = null
var _empty_state: CodaEmptyState
var _scroll: ScrollContainer
var _content: VBoxContainer
var _header: CodaSectionHeader
var _authoring_mode_row: HBoxContainer
var _authoring_mode_picker: OptionButton
var _parameters_section: CodaParametersSection
var _modulation_section: CodaModulationSection
var _banks_section: CodaBanksSection
var _output_placeholder: Label
var _selected_node: CodaBrowserNode = null
var _suppress_authoring_mode_writeback: bool = false


func _ready() -> void:
	name = "Inspector"
	add_theme_constant_override(&"separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_empty_state = CodaEmptyStateScript.new()
	_empty_state.title_text = "No selection"
	_empty_state.body_text = "Pick an event in the Browser to see its properties."
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_empty_state)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.visible = false
	add_child(_scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", Tokens.SPACING_LG)
	margin.add_theme_constant_override(&"margin_top", Tokens.SPACING_MD)
	margin.add_theme_constant_override(&"margin_right", Tokens.SPACING_LG)
	margin.add_theme_constant_override(&"margin_bottom", Tokens.SPACING_LG)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", Tokens.SPACING_MD)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_content)

	_header = CodaSectionHeaderScript.new()
	_header.heading = "Event"
	_content.add_child(_header)

	_authoring_mode_row = HBoxContainer.new()
	_authoring_mode_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_content.add_child(_authoring_mode_row)
	var authoring_mode_label := Label.new()
	authoring_mode_label.text = "Authoring Mode"
	authoring_mode_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	authoring_mode_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_authoring_mode_row.add_child(authoring_mode_label)
	_authoring_mode_picker = OptionButton.new()
	_authoring_mode_picker.add_item("Graph", CodaBrowserNode.AuthoringMode.GRAPH)
	_authoring_mode_picker.add_item("Timeline", CodaBrowserNode.AuthoringMode.TIMELINE)
	_authoring_mode_picker.tooltip_text = (
		"Choose how this event is authored: Graph for branching/sequencing, Timeline for "
		+ "track-based clips."
	)
	_authoring_mode_picker.item_selected.connect(_on_authoring_mode_picked)
	_authoring_mode_row.add_child(_authoring_mode_picker)

	_parameters_section = CodaParametersSectionScript.new()
	_content.add_child(_parameters_section)

	_content.add_child(HSeparator.new())

	_modulation_section = CodaModulationSectionScript.new()
	_content.add_child(_modulation_section)

	_content.add_child(HSeparator.new())

	_banks_section = CodaBanksSectionScript.new()
	_content.add_child(_banks_section)

	_content.add_child(HSeparator.new())

	var out_header := CodaSectionHeaderScript.new()
	out_header.heading = "Output"
	_content.add_child(out_header)

	_output_placeholder = Label.new()
	_output_placeholder.text = "Bus routing is configurable in the Mixer panel."
	_output_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output_placeholder.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_output_placeholder.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_output_placeholder.tooltip_text = (
		"Use the Mixer panel to define buses, then assign each event to one — events without a "
		+ "bus play on Master."
	)
	_content.add_child(_output_placeholder)

	tooltip_text = "Inspector — properties of the event selected in the Browser."


func attach_browser_panel(browser_panel: Control) -> void:
	_browser_panel = browser_panel
	if _browser_panel != null and _browser_panel.has_method(&"get_project"):
		attach_project(_browser_panel.get_project())


func attach_project(project: CodaState) -> void:
	_project = project
	if _parameters_section != null:
		_parameters_section.attach_project(project)
	if _modulation_section != null:
		_modulation_section.attach_project(project)
	if _banks_section != null:
		_banks_section.attach_project(project)


func on_browser_event_selected(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_node = null
		_show_empty()
		if _parameters_section != null:
			_parameters_section.set_event(null)
		if _modulation_section != null:
			_modulation_section.set_event(null)
		if _banks_section != null:
			_banks_section.set_event(null)
		return
	_selected_node = bn
	_header.heading = bn.name
	_show_event()
	_sync_authoring_mode_picker(bn)
	if _parameters_section != null:
		_parameters_section.set_event(bn)
	if _modulation_section != null:
		_modulation_section.set_event(bn)
	if _banks_section != null:
		_banks_section.set_event(bn)


func _sync_authoring_mode_picker(node: CodaBrowserNode) -> void:
	if _authoring_mode_picker == null:
		return
	_suppress_authoring_mode_writeback = true
	for i in _authoring_mode_picker.item_count:
		if _authoring_mode_picker.get_item_id(i) == int(node.event_authoring_mode):
			_authoring_mode_picker.select(i)
			break
	_suppress_authoring_mode_writeback = false


func _on_authoring_mode_picked(idx: int) -> void:
	if _suppress_authoring_mode_writeback or _selected_node == null or _project == null:
		return
	var mode_id: int = _authoring_mode_picker.get_item_id(idx)
	var err: String = _project.set_event_authoring_mode(_selected_node.id, mode_id)
	if not err.is_empty():
		push_warning("Coda: " + err)


func _show_empty() -> void:
	if _empty_state != null:
		_empty_state.visible = true
	if _scroll != null:
		_scroll.visible = false


func _show_event() -> void:
	if _empty_state != null:
		_empty_state.visible = false
	if _scroll != null:
		_scroll.visible = true
