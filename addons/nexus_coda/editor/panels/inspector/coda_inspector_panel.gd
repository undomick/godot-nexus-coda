@tool
class_name CodaInspectorPanel
extends VBoxContainer

## Stacked-section inspector for the currently selected browser node.
## Phase 3 layout:
##   - Header (event name)
##   - Transport (Play / Stop / Loop)
##   - Parameters section
##   - Output section (placeholder for Phase 5: bus picker)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")
const CodaSectionHeaderScript := preload("res://addons/nexus_coda/editor/theme/coda_section_header.gd")
const CodaEventTransportBarScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_event_transport_bar.gd"
)
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
var _transport_bar: CodaEventTransportBar
var _parameters_section: CodaParametersSection
var _modulation_section: CodaModulationSection
var _banks_section: CodaBanksSection
var _output_placeholder: Label
var _selected_node: CodaBrowserNode = null

var _runtime: CodaRuntime = null
var _active_handle: CodaEventHandle = null


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

	_transport_bar = CodaEventTransportBarScript.new()
	_transport_bar.play_requested.connect(_on_play_requested)
	_transport_bar.stop_requested.connect(_on_stop_requested)
	_transport_bar.loop_toggled.connect(_on_loop_toggled)
	_content.add_child(_transport_bar)

	_content.add_child(HSeparator.new())

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

	set_process(true)


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


func attach_runtime(runtime: CodaRuntime) -> void:
	_runtime = runtime


func on_browser_event_selected(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_node = null
		_show_empty()
		_stop_active_voice()
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
	_refresh_transport_enabled()
	if _parameters_section != null:
		_parameters_section.set_event(bn)
	if _modulation_section != null:
		_modulation_section.set_event(bn)
	if _banks_section != null:
		_banks_section.set_event(bn)


func _process(_delta: float) -> void:
	if _active_handle != null and not _active_handle.is_playing():
		_active_handle = null
		if _transport_bar != null:
			_transport_bar.set_playing(false)


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


func _refresh_transport_enabled() -> void:
	if _transport_bar == null:
		return
	if _selected_node == null:
		_transport_bar.set_play_enabled(false, "Select an event first")
		return
	if _runtime == null:
		_transport_bar.set_play_enabled(false, "Runtime not available")
		return
	# Check if the event has either a graph that produces sound or legacy audio paths.
	var has_content: bool = _selected_node.event_audio_paths.size() > 0
	if not has_content and _selected_node.event_graph != null:
		# A graph with at least one SOUND node with an audio path.
		for n in _selected_node.event_graph.nodes:
			if int(n.kind) == 5 and not String(n.properties.get("audio_path", "")).strip_edges().is_empty():
				has_content = true
				break
	if not has_content:
		_transport_bar.set_play_enabled(false, "Add a Sound node and pick an audio file in the Graph")
		return
	_transport_bar.set_play_enabled(true)


func _on_play_requested() -> void:
	if _selected_node == null or _runtime == null:
		return
	_stop_active_voice()
	var params: Dictionary = {"loop": _transport_bar.is_loop_enabled()}
	_active_handle = _runtime.play_event_node(_selected_node, params)
	if _active_handle == null:
		_transport_bar.set_playing(false)
		NexusCodaLog.warn("inspector_preview", 'Could not start preview for "%s"' % _selected_node.name)
		return
	_transport_bar.set_playing(true)
	NexusCodaLog.info("inspector_preview", 'Preview started: "%s"' % _selected_node.name)


func _on_stop_requested() -> void:
	_stop_active_voice()


func _on_loop_toggled(loop: bool) -> void:
	if _active_handle != null:
		_active_handle.loop = loop


func _stop_active_voice() -> void:
	if _active_handle != null:
		_active_handle.stop()
		_active_handle = null
	if _transport_bar != null:
		_transport_bar.set_playing(false)
