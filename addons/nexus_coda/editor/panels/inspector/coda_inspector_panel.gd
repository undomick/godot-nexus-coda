@tool
class_name CodaInspectorPanel
extends VBoxContainer

signal authoring_mode_changed(node: Variant)
signal event_output_bus_changed(node: Variant)

## Stacked-section inspector for the currently selected browser node.
## Layout:
##   - Header (event or asset name)
##   - Event stack: authoring, parameters, modulation, banks, output
##   - Asset stack: folder / asset summary when the Assets tab selects a node
##
## Transport (Play / Stop / Loop / Pause / time / meter) lives in the dedicated
## Player panel. Inspector no longer owns playback state.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")
const CodaSectionHeaderScript := preload("res://addons/nexus_coda/editor/theme/coda_section_header.gd")
const CodaParametersSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_parameters_section.gd"
)
const CodaEventTagsSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_event_tags_section.gd"
)
const CodaEventNotesSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_event_notes_section.gd"
)
const CodaEventPropertiesSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_event_properties_section.gd"
)
const CodaModulationSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_modulation_section.gd"
)
const CodaBanksSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_banks_section.gd"
)
const CodaAssetInspectorSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_asset_inspector_section.gd"
)
const CodaGameSyncInspectorSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_game_sync_inspector_section.gd"
)
const CodaBankInspectorSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_bank_inspector_section.gd"
)
const CodaInspectorEffectsSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_inspector_effects_section.gd"
)
const CodaClipInspectorSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_clip_inspector_section.gd"
)
const CodaInspectorContextBannerScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_inspector_context_banner.gd"
)
const CodaInspectorSelectionScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_inspector_selection.gd"
)

var _browser_panel: Control = null
var _project: CodaState = null
var _empty_state: CodaEmptyState
var _scroll: ScrollContainer
var _content: VBoxContainer
var _context_banner: CodaInspectorContextBanner
var _header: CodaSectionHeader
var _event_stack: VBoxContainer
var _authoring_mode_row: HBoxContainer
var _authoring_mode_picker: OptionButton
var _parameters_section: CodaParametersSection
var _tags_section: CodaEventTagsSection
var _notes_section: CodaEventNotesSection
var _properties_section: CodaEventPropertiesSection
var _modulation_section: CodaModulationSection
var _banks_section: CodaBanksSection
var _output_placeholder: Label
var _output_bus_picker: OptionButton
var _asset_section: CodaAssetInspectorSection
var _game_sync_section: CodaGameSyncInspectorSection
var _bank_section: CodaBankInspectorSection
var _fx_section: CodaInspectorEffectsSection
var _clip_section: CodaClipInspectorSection
var _selected_node: CodaBrowserNode = null
var _suppress_authoring_mode_writeback: bool = false


func _ready() -> void:
	name = "Inspector"
	add_theme_constant_override(&"separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_empty_state = CodaEmptyStateScript.new()
	_empty_state.title_text = "No selection"
	_empty_state.body_text = (
		"Pick an event, asset, timeline clip or track, or mixer bus to see its properties."
	)
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

	_context_banner = CodaInspectorContextBannerScript.new()
	_content.add_child(_context_banner)

	_header = CodaSectionHeaderScript.new()
	_header.heading = "Event"
	_content.add_child(_header)

	_event_stack = VBoxContainer.new()
	_event_stack.add_theme_constant_override(&"separation", Tokens.SPACING_MD)
	_event_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_event_stack)

	_authoring_mode_row = HBoxContainer.new()
	_authoring_mode_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_event_stack.add_child(_authoring_mode_row)
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
	_event_stack.add_child(_parameters_section)

	_properties_section = CodaEventPropertiesSectionScript.new()
	_event_stack.add_child(_properties_section)

	_tags_section = CodaEventTagsSectionScript.new()
	_event_stack.add_child(_tags_section)

	_notes_section = CodaEventNotesSectionScript.new()
	_event_stack.add_child(_notes_section)

	_event_stack.add_child(HSeparator.new())

	_modulation_section = CodaModulationSectionScript.new()
	_event_stack.add_child(_modulation_section)

	_event_stack.add_child(HSeparator.new())

	_banks_section = CodaBanksSectionScript.new()
	_event_stack.add_child(_banks_section)

	_event_stack.add_child(HSeparator.new())

	var out_header := CodaSectionHeaderScript.new()
	out_header.heading = "Output"
	_event_stack.add_child(out_header)

	_output_placeholder = Label.new()
	_output_placeholder.text = "Bus routing is configurable in the Mixer panel."
	_output_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output_placeholder.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_output_placeholder.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_output_placeholder.visible = false
	_event_stack.add_child(_output_placeholder)

	_output_bus_picker = OptionButton.new()
	_output_bus_picker.tooltip_text = "Output bus for this event. Empty uses Master."
	_output_bus_picker.item_selected.connect(_on_output_bus_picked)
	_event_stack.add_child(_output_bus_picker)

	_clip_section = CodaClipInspectorSectionScript.new()
	_clip_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip_section.visible = true

	_fx_section = CodaInspectorEffectsSectionScript.new()
	_fx_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_fx_section)

	_asset_section = CodaAssetInspectorSectionScript.new()
	_asset_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asset_section.visible = false
	_content.add_child(_asset_section)

	_game_sync_section = CodaGameSyncInspectorSectionScript.new()
	_game_sync_section.visible = false
	_game_sync_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_game_sync_section)

	_bank_section = CodaBankInspectorSectionScript.new()
	_bank_section.visible = false
	_bank_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_bank_section)

	tooltip_text = "Inspector — properties of the selection in the Browser."


func attach_browser_panel(browser_panel: Control) -> void:
	_browser_panel = browser_panel
	if _browser_panel != null and _browser_panel.has_method(&"get_project"):
		attach_project(_browser_panel.get_project())


func attach_project(project: CodaState) -> void:
	_project = project
	if _parameters_section != null:
		_parameters_section.attach_project(project)
	if _properties_section != null:
		_properties_section.attach_project(project)
	if _tags_section != null:
		_tags_section.attach_project(project)
	if _notes_section != null:
		_notes_section.attach_project(project)
	if _modulation_section != null:
		_modulation_section.attach_project(project)
	if _banks_section != null:
		_banks_section.attach_project(project)
	if _game_sync_section != null:
		_game_sync_section.attach_project(project)
	if _bank_section != null:
		_bank_section.attach_project(project)
	if _fx_section != null:
		_fx_section.attach_project(project)
	if _clip_section != null:
		_clip_section.attach_project(project)


func apply_view_state(state: Dictionary) -> void:
	var subject: int = int(state.get("subject", CodaInspectorSelectionScript.Subject.EMPTY))
	if subject == CodaInspectorSelectionScript.Subject.EMPTY:
		_show_empty()
		return

	_empty_state.visible = false
	_scroll.visible = true

	var show_banner: bool = bool(state.get("show_context_banner", false))
	if _context_banner != null:
		_context_banner.set_context(
			str(state.get("title", "")),
			str(state.get("subtitle", "")),
			show_banner
		)

	var show_event_stack: bool = bool(state.get("show_event_stack", false))
	var show_asset: bool = bool(state.get("show_asset", false))
	var show_bank: bool = bool(state.get("show_bank", false))
	var show_game_sync: bool = bool(state.get("show_game_sync", false))
	var show_clip: bool = bool(state.get("show_clip", false))

	_header.visible = show_event_stack or show_asset
	if show_event_stack or show_asset:
		_header.heading = str(state.get("title", ""))

	if _event_stack != null:
		_event_stack.visible = show_event_stack
	if show_event_stack:
		var bn: CodaBrowserNode = state.get("browser_node") as CodaBrowserNode
		_selected_node = bn
		_sync_authoring_mode_picker(bn)
		_refresh_output_bus_picker(bn)
		if _parameters_section != null:
			_parameters_section.set_event(bn)
		if _properties_section != null:
			_properties_section.set_event(bn)
		if _tags_section != null:
			_tags_section.set_event(bn)
		if _notes_section != null:
			_notes_section.set_event(bn)
		if _modulation_section != null:
			_modulation_section.set_event(bn)
		if _banks_section != null:
			_banks_section.set_event(bn)
	else:
		if _parameters_section != null:
			_parameters_section.set_event(null)
		if _properties_section != null:
			_properties_section.set_event(null)
		if _tags_section != null:
			_tags_section.set_event(null)
		if _notes_section != null:
			_notes_section.set_event(null)
		if _modulation_section != null:
			_modulation_section.set_event(null)
		if _banks_section != null:
			_banks_section.set_event(null)

	if _asset_section != null:
		_asset_section.visible = show_asset
		if show_asset:
			_selected_node = state.get("browser_node") as CodaBrowserNode
			_asset_section.set_node(_selected_node)

	if _bank_section != null:
		_bank_section.visible = show_bank
		if show_bank:
			_bank_section.set_bank(str(state.get("bank_id", "")))

	if _game_sync_section != null:
		_game_sync_section.visible = show_game_sync
		if show_game_sync:
			_game_sync_section.set_rule_payload(
				(state.get("game_sync_payload", {}) as Dictionary).duplicate(true)
			)

	if _clip_section != null:
		if show_clip:
			if _context_banner != null:
				_context_banner.set_properties_content(_clip_section)
			_clip_section.set_clip_context(
				str(state.get("event_id", "")), str(state.get("clip_id", ""))
			)
		elif _context_banner != null:
			_context_banner.set_properties_content(null)

	var fx_scope: int = int(
		state.get("fx_scope", CodaInspectorEffectsSection.FxScope.NONE)
	)
	var fx_ids: Dictionary = {
		"event_id": str(state.get("event_id", "")),
		"track_id": str(state.get("track_id", "")),
		"clip_id": str(state.get("clip_id", "")),
		"bus_id": str(state.get("bus_id", "")),
	}
	set_fx_scope(fx_scope as CodaInspectorEffectsSection.FxScope, fx_ids)


func show_game_sync_rule(payload: Dictionary) -> void:
	var sel := CodaInspectorSelectionScript.new()
	sel.project = _project
	apply_view_state(sel.apply(CodaInspectorSelectionScript.Subject.BROWSER_GAME_SYNC, {"payload": payload}))


func show_bank(bank_id: String) -> void:
	var sel := CodaInspectorSelectionScript.new()
	sel.project = _project
	apply_view_state(sel.apply(CodaInspectorSelectionScript.Subject.BROWSER_BANK, {"bank_id": bank_id}))


func set_fx_scope(scope: CodaInspectorEffectsSection.FxScope, ids: Dictionary = {}) -> void:
	if _fx_section == null:
		return
	_fx_section.set_fx_scope(scope, ids)


func get_selected_event() -> CodaBrowserNode:
	if _selected_node == null or _selected_node.kind != CodaBrowserNode.Kind.EVENT:
		return null
	return _selected_node


func scroll_to_track_effects() -> void:
	if _scroll == null or _fx_section == null:
		return
	var chain: Control = _fx_section.get_active_chain_control()
	if chain != null and chain.visible:
		_scroll.ensure_control_visible(chain)


func on_browser_event_selected(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		apply_view_state({"subject": CodaInspectorSelectionScript.Subject.EMPTY})
		return
	var sel := CodaInspectorSelectionScript.new()
	sel.project = _project
	apply_view_state(sel.apply(CodaInspectorSelectionScript.Subject.BROWSER_EVENT, {"node": bn}))


func on_browser_asset_selected(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null:
		apply_view_state({"subject": CodaInspectorSelectionScript.Subject.EMPTY})
		return
	var sel := CodaInspectorSelectionScript.new()
	sel.project = _project
	apply_view_state(sel.apply(CodaInspectorSelectionScript.Subject.BROWSER_ASSET, {"node": bn}))


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
		return
	authoring_mode_changed.emit(_selected_node)


func _refresh_output_bus_picker(node: CodaBrowserNode) -> void:
	if _output_bus_picker == null:
		return
	_output_bus_picker.clear()
	_output_bus_picker.add_item("Master (default)", 0)
	var select_idx: int = 0
	if _project != null and _project.bus_root != null:
		var flat: Array[CodaBus] = _project.bus_root.collect_flat([])
		for i in flat.size():
			var b: CodaBus = flat[i]
			_output_bus_picker.add_item(b.bus_name, i + 1)
			_output_bus_picker.set_item_metadata(i + 1, b.id)
			if b.id == node.event_output_bus_id:
				select_idx = i + 1
	_output_bus_picker.select(select_idx)


func _on_output_bus_picked(idx: int) -> void:
	if _selected_node == null or _project == null:
		return
	if idx <= 0:
		_selected_node.event_output_bus_id = ""
	else:
		_selected_node.event_output_bus_id = str(_output_bus_picker.get_item_metadata(idx))
	_project.project_dirty.emit()
	event_output_bus_changed.emit(_selected_node)


func _show_empty() -> void:
	_selected_node = null
	if _context_banner != null:
		_context_banner.set_context("", "", false)
	if _event_stack != null:
		_event_stack.visible = false
	if _asset_section != null:
		_asset_section.visible = false
	if _game_sync_section != null:
		_game_sync_section.visible = false
	if _bank_section != null:
		_bank_section.visible = false
	if _clip_section != null and _context_banner != null:
		_context_banner.set_properties_content(null)
	if _header != null:
		_header.visible = false
	set_fx_scope(CodaInspectorEffectsSection.FxScope.NONE)
	if _parameters_section != null:
		_parameters_section.set_event(null)
	if _modulation_section != null:
		_modulation_section.set_event(null)
	if _banks_section != null:
		_banks_section.set_event(null)
	if _empty_state != null:
		_empty_state.visible = true
	if _scroll != null:
		_scroll.visible = false


func wire_timeline_preview_debounce(timeline_panel: CodaTimelinePanel) -> void:
	if _clip_section == null or timeline_panel == null:
		return
	var begin := Callable(timeline_panel, &"begin_timeline_edit_interaction")
	var commit := Callable(timeline_panel, &"commit_timeline_edit_interaction")
	var notify := Callable(timeline_panel, &"_notify_timeline_changed")
	if not _clip_section.clip_fade_edit_started.is_connected(begin):
		_clip_section.clip_fade_edit_started.connect(begin)
	if not _clip_section.clip_fade_edit_committed.is_connected(commit):
		_clip_section.clip_fade_edit_committed.connect(commit)
	if not _clip_section.clip_properties_changed.is_connected(notify):
		_clip_section.clip_properties_changed.connect(notify)
