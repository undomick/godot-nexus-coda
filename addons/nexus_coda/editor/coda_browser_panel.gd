@tool
extends VBoxContainer

## Tab-host shell for the Browser panel.
## Each tab is a `CodaBrowserTab` (extends VBoxContainer) added as a TabContainer
## child. The host:
##   - owns the live CodaState and forwards it to every tab on attach
##   - listens to each tab's `selection_emitted` signal and translates it into
##     the panel-wide signals existing consumers (Inspector, Graph, Player) wire
##   - exposes a generic `external_selection_requested(panel_id, kind, payload)`
##     for cross-panel routing the editor window performs (e.g. show Mixer when
##     a bus is picked in the Browser).
##
## Variant signal types avoid typed-signal → Callable slot issues observed in
## EditorPlugin windows (emit fired but receiver never ran).

signal event_selection_changed(node: Variant)
signal asset_selection_changed(node: Variant)
## Emits when a tab selection conceptually belongs to another dock panel. The editor
## window listens to this and calls `dm.show_panel(...)` + selects in that panel.
signal external_selection_requested(target_panel_id: StringName, kind: StringName, payload: Variant)

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaBrowserTabScript := preload(
	"res://addons/nexus_coda/editor/browser/tabs/coda_browser_tab.gd"
)
const CodaEventsTabScript := preload(
	"res://addons/nexus_coda/editor/browser/tabs/coda_events_tab.gd"
)
const CodaAssetsTabScript := preload(
	"res://addons/nexus_coda/editor/browser/tabs/coda_assets_tab.gd"
)
const CodaBanksTabScript := preload(
	"res://addons/nexus_coda/editor/browser/tabs/coda_banks_tab.gd"
)
const CodaGameSyncsTabScript := preload(
	"res://addons/nexus_coda/editor/browser/tabs/coda_game_syncs_tab.gd"
)

@onready var _tabs: TabContainer = %BrowserTabContainer

var _project: CodaState = CodaStateScript.new()
var _events_tab: CodaEventsTab
var _assets_tab: CodaAssetsTab
var _banks_tab: CodaBanksTab
var _game_syncs_tab: CodaGameSyncsTab


func _ready() -> void:
	_register_default_tabs()
	for tab in _all_tabs():
		tab.attach_state(_project)


func get_project():
	return _project


func set_project(project: Variant) -> void:
	if project == null:
		return
	_project = project
	for tab in _all_tabs():
		tab.attach_state(_project)


## Re-emit current Events tab selection (used after layout changes / on initial bind so the
## downstream panels see a consistent snapshot regardless of programmatic selection paths).
func pulse_events_selection_to_editor() -> void:
	if _events_tab != null:
		_events_tab.pulse_selection_to_editor()


## Programmatic event selection (used by command palette).
func select_event_by_id(event_id: String) -> bool:
	if event_id.is_empty() or _events_tab == null:
		return false
	if _tabs != null and is_instance_valid(_tabs):
		var idx: int = _tabs.get_tab_idx_from_control(_events_tab)
		if idx >= 0:
			_tabs.current_tab = idx
	return _events_tab.select_by_id(event_id)


func focus_assets_tab() -> void:
	if _tabs == null or _assets_tab == null:
		return
	var idx: int = _tabs.get_tab_idx_from_control(_assets_tab)
	if idx >= 0:
		_tabs.current_tab = idx


# ---------- Tab registration ----------

func _register_default_tabs() -> void:
	if _tabs == null:
		NexusCodaLog.warn("browser", "BrowserTabContainer missing; cannot register tabs")
		return
	_events_tab = CodaEventsTabScript.new()
	_events_tab.name = "Events"
	_assets_tab = CodaAssetsTabScript.new()
	_assets_tab.name = "Assets"
	_banks_tab = CodaBanksTabScript.new()
	_banks_tab.name = "Banks"
	_game_syncs_tab = CodaGameSyncsTabScript.new()
	_game_syncs_tab.name = "GameSyncs"
	_register_tab(_events_tab)
	_register_tab(_assets_tab)
	_register_tab(_banks_tab)
	_register_tab(_game_syncs_tab)


func _register_tab(tab: CodaBrowserTab) -> void:
	if tab == null or _tabs == null:
		return
	_tabs.add_child(tab)
	var tab_idx: int = _tabs.get_tab_idx_from_control(tab)
	if tab_idx >= 0:
		_tabs.set_tab_title(tab_idx, tab.get_tab_title())
	tab.selection_emitted.connect(_on_tab_selection_emitted)


func _all_tabs() -> Array[CodaBrowserTab]:
	var out: Array[CodaBrowserTab] = []
	if _tabs == null:
		return out
	for i in _tabs.get_tab_count():
		var ctrl: Control = _tabs.get_tab_control(i) as Control
		var t: CodaBrowserTab = ctrl as CodaBrowserTab
		if t != null:
			out.append(t)
	return out


# ---------- Selection routing ----------

## Match patterns in GDScript reject function calls; an if/elif chain on plain StringName
## literals avoids any cross-class constant resolution at parse time and stays robust against
## linter cache hiccups when class_name lookups are stale.
func _on_tab_selection_emitted(category: StringName, payload: Variant) -> void:
	if category == &"event":
		event_selection_changed.emit(payload)
	elif category == &"asset":
		asset_selection_changed.emit(payload)
	elif category == &"bank":
		external_selection_requested.emit(&"inspector", category, payload)
	elif category == &"game_sync":
		external_selection_requested.emit(&"inspector", category, payload)
	else:
		NexusCodaLog.debug("browser", "Unhandled tab selection category: %s" % String(category))
