@tool
extends Window

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaProjectIo := preload("res://addons/nexus_coda/editor/coda_project_io.gd")
const CodaBankExportScript := preload("res://addons/nexus_coda/editor/io/coda_bank_export.gd")
const CodaDesignTokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaSampleProjectScript := preload(
	"res://addons/nexus_coda/editor/samples/coda_sample_project.gd"
)
const CodaCommandPaletteScript := preload(
	"res://addons/nexus_coda/editor/panels/palette/coda_command_palette.gd"
)
const CodaShortcutSheetScript := preload(
	"res://addons/nexus_coda/editor/panels/help/coda_shortcut_sheet.gd"
)
const CodaStatusBarScript := preload(
	"res://addons/nexus_coda/editor/panels/statusbar/coda_status_bar.gd"
)
const CodaDockHostScript := preload("res://addons/nexus_coda/editor/layout/coda_dock_host.gd")
const CodaDockManagerScript := preload("res://addons/nexus_coda/editor/layout/coda_dock_manager.gd")
const CodaDockPanelInfoScript := preload("res://addons/nexus_coda/editor/layout/coda_dock_panel_base.gd")
const BrowserPanelScene := preload("res://addons/nexus_coda/editor/coda_browser_panel.tscn")
const InspectorPanelScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_inspector_panel.gd"
)
const GraphPanelScript := preload(
	"res://addons/nexus_coda/editor/panels/graph/coda_event_graph_panel.gd"
)
const MixerPanelScript := preload(
	"res://addons/nexus_coda/editor/panels/mixer/coda_mixer_panel.gd"
)
const LogPanelScript := preload(
	"res://addons/nexus_coda/editor/panels/log/coda_log_panel.gd"
)
const PlayerPanelScript := preload(
	"res://addons/nexus_coda/editor/panels/player/coda_player_panel.gd"
)
const TimelinePanelScript := preload(
	"res://addons/nexus_coda/editor/panels/timeline/coda_timeline_panel.gd"
)

const PANEL_BROWSER := &"browser"
const PANEL_GRAPH := &"graph"
const PANEL_INSPECTOR := &"inspector"
const PANEL_MIXER := &"mixer"
const PANEL_LOG := &"log"
const PANEL_PLAYER := &"player"
const PANEL_TIMELINE := &"timeline"

const MID_NEW := 1
const MID_OPEN := 2
const MID_CLOSE := 3
const MID_SAVE := 4
const MID_SAVE_AS := 5

const VID_RESET_LAYOUT := 100
const VID_SAVE_LAYOUT := 101
const VID_LOAD_LAYOUT := 102
const VID_CLEAR_SAVED_LAYOUT := 103
const VID_TOGGLE_BROWSER := 110
const VID_TOGGLE_GRAPH := 111
const VID_TOGGLE_INSPECTOR := 112
const VID_TOGGLE_MIXER := 113
const VID_TOGGLE_LOG := 114
const VID_TOGGLE_PLAYER := 115
const VID_TOGGLE_TIMELINE := 116

const BID_NEW_BANK := 200
const BID_VALIDATE_BANKS := 201
const BID_EXPORT_BANK_BASE := 300  ## offset by bank index

const HID_OPEN_SAMPLE := 400
const HID_SHORTCUTS := 401
const HID_TOGGLE_THEME_MODE := 402
const HID_PICK_ACCENT := 403
const HID_COMMAND_PALETTE := 404

const RECENT_ID_BASE := 1000

const CUSTOM_LAYOUT_SUBDIR := "nexus_coda"
const CUSTOM_LAYOUT_FILENAME := "custom_layout.json"
const CUSTOM_LAYOUT_PREFS_FILENAME := "layout_prefs.json"
const CUSTOM_LAYOUT_PREFS_KEY := "preferred_layout"
const CUSTOM_LAYOUT_PREF_FACTORY := "factory"
const CUSTOM_LAYOUT_PREF_CUSTOM := "custom"

@onready var _menu_bar: MenuBar = $RootVBox/MenuBar
@onready var _dock_host: CodaDockHost = $RootVBox/RootMargin/DockHost

var _plugin: EditorPlugin

var _file_menu: PopupMenu
var _view_menu: PopupMenu
var _build_menu: PopupMenu
var _help_menu: PopupMenu
var _recent_menu: PopupMenu

var _command_palette: CodaCommandPalette
var _shortcut_sheet: CodaShortcutSheet
var _status_bar: CodaStatusBar
var _color_picker_dialog: AcceptDialog
var _project_theme: Theme

var _browser_panel: Control
var _graph_panel: CodaEventGraphPanel
var _inspector_panel: CodaInspectorPanel
var _mixer_panel: CodaMixerPanel
var _log_panel: CodaLogPanel
var _player_panel: CodaPlayerPanel
var _timeline_panel: CodaTimelinePanel

var _current_path: String = ""
var _dirty: bool = false
var _suppress_dirty: bool = false
var _project_signal_source: CodaState = null

var _recent_paths_snapshot: PackedStringArray = []

var _choice_result: int = 0

const UNSAVED_LAYER_NODEPATH := NodePath("UnsavedPromptLayer")

## If EditorFileDialog returns no path (editor bug / signal issue), we still write JSON here so work is not lost.
const FALLBACK_SAVE_RES_PATH := "res://nexus_coda_projects/untitled.ncoda"

var _file_dialog_pick_result: String = ""
var _file_dialog_pick_complete: bool = false
var _teardown_done: bool = false
var _fs_asset_import_boot_attempts: int = 0


## Imports the given `res://` paths into the Coda assets tree (same rules as in-editor DnD),
## shows the Browser panel, and switches to the Assets tab. Does not change files on disk.
func import_fs_paths_into_assets(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	if _browser_panel == null:
		if _fs_asset_import_boot_attempts < 16:
			_fs_asset_import_boot_attempts += 1
			call_deferred(&"import_fs_paths_into_assets", paths)
		else:
			_fs_asset_import_boot_attempts = 0
			NexusCodaLog.warn("editor_window", "Send to Coda Assets: browser panel not ready.")
		return
	_fs_asset_import_boot_attempts = 0
	if _dock_host != null and _dock_host.dock_manager != null:
		_dock_host.dock_manager.show_panel(PANEL_BROWSER)
	if _browser_panel.has_method(&"focus_assets_tab"):
		_browser_panel.call(&"focus_assets_tab")
	if _browser_panel.has_method(&"get_project"):
		var st: Variant = _browser_panel.get_project()
		if st is CodaState:
			var state: CodaState = st as CodaState
			state.import_assets_from_res_paths(state.assets_root.id, paths)


func setup_editor_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _ready() -> void:
	close_requested.connect(_on_close_requested)
	_build_menus()
	_install_status_bar()
	_install_overlays()
	if _dock_host.is_node_ready():
		call_deferred(&"_register_panels")
	else:
		_dock_host.panels_ready.connect(_register_panels, CONNECT_ONE_SHOT)


func _install_status_bar() -> void:
	if _status_bar != null:
		return
	_status_bar = CodaStatusBarScript.new()
	_status_bar.name = "StatusBar"
	# Sit beneath the dock host so it stays visible regardless of docked panels.
	var root: Node = $RootVBox
	if root != null:
		root.add_child(_status_bar)


func _install_overlays() -> void:
	_command_palette = CodaCommandPaletteScript.new()
	_command_palette.name = "CommandPalette"
	_command_palette.visible = false
	add_child(_command_palette)

	_shortcut_sheet = CodaShortcutSheetScript.new()
	_shortcut_sheet.name = "ShortcutSheet"
	_shortcut_sheet.visible = false
	add_child(_shortcut_sheet)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k: InputEventKey = event
	if not k.pressed or k.echo:
		return
	# Ctrl+P opens the command palette; F1 opens the shortcut sheet.
	if k.keycode == KEY_P and k.ctrl_pressed and not k.alt_pressed and not k.shift_pressed:
		_open_command_palette()
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_F1:
		_open_shortcut_sheet()
		get_viewport().set_input_as_handled()


func _register_panels() -> void:
	var dm: CodaDockManager = _dock_host.dock_manager
	if dm == null:
		NexusCodaLog.warn("editor_window", "dock manager missing; cannot register panels")
		return

	_browser_panel = BrowserPanelScene.instantiate() as Control
	_graph_panel = GraphPanelScript.new()
	_inspector_panel = InspectorPanelScript.new()
	_mixer_panel = MixerPanelScript.new()
	_log_panel = LogPanelScript.new()
	_player_panel = PlayerPanelScript.new()
	_timeline_panel = TimelinePanelScript.new()

	dm.register_panel(CodaDockPanelInfoScript.make(
		PANEL_BROWSER, "Browser", CodaDockHostScript.ZONE_LEFT, _browser_panel
	))
	dm.register_panel(CodaDockPanelInfoScript.make(
		PANEL_GRAPH, "Graph", CodaDockHostScript.ZONE_CENTER, _graph_panel
	))
	dm.register_panel(CodaDockPanelInfoScript.make(
		PANEL_TIMELINE, "Timeline", CodaDockHostScript.ZONE_CENTER, _timeline_panel
	))
	dm.register_panel(CodaDockPanelInfoScript.make(
		PANEL_INSPECTOR, "Inspector", CodaDockHostScript.ZONE_RIGHT, _inspector_panel
	))
	dm.register_panel(CodaDockPanelInfoScript.make(
		PANEL_PLAYER, "Player", CodaDockHostScript.ZONE_BOTTOM_LEFT, _player_panel
	))
	dm.register_panel(CodaDockPanelInfoScript.make(
		PANEL_MIXER, "Mixer", CodaDockHostScript.ZONE_BOTTOM, _mixer_panel
	))
	dm.register_panel(CodaDockPanelInfoScript.make(
		PANEL_LOG, "Log", CodaDockHostScript.ZONE_BOTTOM, _log_panel, null, false
	))

	dm.panel_visibility_changed.connect(_on_panel_visibility_changed)
	dm.layout_changed.connect(_on_layout_changed)

	_wire_browser_to_others()
	_wire_runtime_to_panels()
	call_deferred(&"_initial_bind")
	call_deferred(&"_load_custom_layout_if_present")


func _wire_browser_to_others() -> void:
	if _browser_panel == null:
		return
	if _browser_panel.has_signal(&"event_selection_changed"):
		var inspector_slot := Callable(_inspector_panel, &"on_browser_event_selected")
		var graph_slot := Callable(_graph_panel, &"on_browser_event_selected")
		var player_slot := Callable(_player_panel, &"on_browser_event_selected")
		var timeline_slot := Callable(_timeline_panel, &"on_browser_event_selected")
		if not _browser_panel.event_selection_changed.is_connected(inspector_slot):
			_browser_panel.event_selection_changed.connect(inspector_slot)
		if not _browser_panel.event_selection_changed.is_connected(graph_slot):
			_browser_panel.event_selection_changed.connect(graph_slot)
		if not _browser_panel.event_selection_changed.is_connected(player_slot):
			_browser_panel.event_selection_changed.connect(player_slot)
		if not _browser_panel.event_selection_changed.is_connected(timeline_slot):
			_browser_panel.event_selection_changed.connect(timeline_slot)
	if _browser_panel.has_signal(&"external_selection_requested"):
		var route_slot := Callable(self, &"_on_browser_external_selection_requested")
		if not _browser_panel.external_selection_requested.is_connected(route_slot):
			_browser_panel.external_selection_requested.connect(route_slot)
	if _inspector_panel != null:
		_inspector_panel.attach_browser_panel(_browser_panel)
	if _player_panel != null:
		_player_panel.attach_browser_panel(_browser_panel)
	if _graph_panel != null and _browser_panel.has_method(&"get_project"):
		_graph_panel.attach_project(_browser_panel.get_project())


## Routes selection events from non-events tabs (Buses → Mixer, Banks → Inspector, etc.)
## to the right dock panel. For Game Syncs, the source event is also pre-selected so the
## Inspector lands on the correct sections.
func _on_browser_external_selection_requested(
	target_panel_id: StringName, kind: StringName, payload: Variant
) -> void:
	if _dock_host == null or _dock_host.dock_manager == null:
		return
	var dm: CodaDockManager = _dock_host.dock_manager
	if kind == &"game_sync" and payload is Dictionary:
		var event_id: String = str((payload as Dictionary).get("event_id", ""))
		if not event_id.is_empty() and _browser_panel != null \
				and _browser_panel.has_method(&"select_event_by_id"):
			_browser_panel.select_event_by_id(event_id)
	dm.show_panel(target_panel_id)
	NexusCodaLog.debug(
		"browser_routing",
		"Routed %s selection to %s panel" % [String(kind), String(target_panel_id)],
	)


func _wire_runtime_to_panels() -> void:
	if _plugin == null or not _plugin.has_method(&"get_editor_runtime"):
		return
	var rt: CodaRuntime = _plugin.get_editor_runtime() as CodaRuntime
	if rt == null:
		return
	if _graph_panel != null:
		_graph_panel.attach_runtime(rt)
	if _player_panel != null:
		_player_panel.attach_runtime(rt)
	if _timeline_panel != null and _timeline_panel.has_method(&"attach_runtime"):
		_timeline_panel.attach_runtime(rt)
	if _mixer_panel != null:
		_mixer_panel.attach_runtime(rt)
		_mixer_panel.attach_bus_layout_export(
			Callable(self, &"pick_audio_bus_layout_export_path_async"),
			Callable(self, &"complete_audio_bus_layout_export")
		)


func _initial_bind() -> void:
	if _browser_panel != null and _browser_panel.has_method(&"get_project"):
		var st: Variant = _browser_panel.get_project()
		_bind_project_signals(st)
		_push_project_to_runtime(st)
		if _graph_panel != null and st is CodaState:
			_graph_panel.attach_project(st as CodaState)
		if _inspector_panel != null and st is CodaState:
			_inspector_panel.attach_project(st as CodaState)
		if _mixer_panel != null and st is CodaState:
			_mixer_panel.attach_project(st as CodaState)
		if _player_panel != null and st is CodaState:
			_player_panel.attach_project(st as CodaState)
		if _timeline_panel != null and st is CodaState:
			_timeline_panel.attach_project(st as CodaState)
	if _browser_panel != null and _browser_panel.has_method(&"pulse_events_selection_to_editor"):
		_browser_panel.pulse_events_selection_to_editor()
	_update_title()
	_refresh_view_menu_check_marks()
	var st0: CodaState = _current_state() as CodaState
	if st0 != null:
		_apply_theme_appearance(st0.theme_mode, st0.accent_color)


func _push_project_to_runtime(state: Variant) -> void:
	if _plugin == null or not _plugin.has_method(&"get_editor_runtime"):
		return
	var rt: CodaRuntime = _plugin.get_editor_runtime() as CodaRuntime
	if rt != null:
		rt.set_project(state)


func _build_menus() -> void:
	_file_menu = PopupMenu.new()
	_file_menu.name = "File"
	_menu_bar.add_child(_file_menu)

	_view_menu = PopupMenu.new()
	_view_menu.name = "View"
	_menu_bar.add_child(_view_menu)

	_build_menu = PopupMenu.new()
	_build_menu.name = "Build"
	_menu_bar.add_child(_build_menu)

	_help_menu = PopupMenu.new()
	_help_menu.name = "Help"
	_menu_bar.add_child(_help_menu)

	_recent_menu = PopupMenu.new()
	_recent_menu.name = "NexusCodaRecentSub"
	_file_menu.add_child(_recent_menu)

	_rebuild_file_menu_items()
	_rebuild_view_menu_items()
	_rebuild_help_menu_items()
	_file_menu.id_pressed.connect(_on_file_id_pressed)
	_view_menu.id_pressed.connect(_on_view_id_pressed)
	_view_menu.about_to_popup.connect(_refresh_view_menu_check_marks)
	_build_menu.id_pressed.connect(_on_build_id_pressed)
	_build_menu.about_to_popup.connect(_rebuild_build_menu_items)
	_help_menu.id_pressed.connect(_on_help_id_pressed)
	_help_menu.about_to_popup.connect(_rebuild_help_menu_items)
	_recent_menu.id_pressed.connect(_on_recent_id_pressed)
	_recent_menu.about_to_popup.connect(_fill_recent_menu)
	_rebuild_build_menu_items()


func _rebuild_file_menu_items() -> void:
	_file_menu.clear()
	_file_menu.add_item("New", MID_NEW)
	_file_menu.add_item("Open", MID_OPEN)
	_file_menu.add_separator()
	_file_menu.add_submenu_item("Open Recent", "NexusCodaRecentSub")
	_file_menu.add_separator()
	_file_menu.add_item("Close", MID_CLOSE)
	_file_menu.add_separator()
	_file_menu.add_item("Save", MID_SAVE)
	_file_menu.add_item("Save As...", MID_SAVE_AS)


func _rebuild_view_menu_items() -> void:
	_view_menu.clear()
	_view_menu.add_check_item("Show Browser", VID_TOGGLE_BROWSER)
	_view_menu.add_check_item("Show Graph", VID_TOGGLE_GRAPH)
	_view_menu.add_check_item("Show Timeline", VID_TOGGLE_TIMELINE)
	_view_menu.add_check_item("Show Inspector", VID_TOGGLE_INSPECTOR)
	_view_menu.add_check_item("Show Player", VID_TOGGLE_PLAYER)
	_view_menu.add_check_item("Show Mixer", VID_TOGGLE_MIXER)
	_view_menu.add_check_item("Show Log", VID_TOGGLE_LOG)
	_view_menu.add_separator()
	_view_menu.add_item("Save Layout", VID_SAVE_LAYOUT)
	_view_menu.add_item("Load Saved Layout", VID_LOAD_LAYOUT)
	_view_menu.add_item("Clear Saved Layout", VID_CLEAR_SAVED_LAYOUT)
	_view_menu.add_separator()
	_view_menu.add_item("Reset Layout", VID_RESET_LAYOUT)


func _refresh_view_menu_check_marks() -> void:
	if _view_menu == null or _dock_host == null or _dock_host.dock_manager == null:
		return
	var dm: CodaDockManager = _dock_host.dock_manager
	_set_check(VID_TOGGLE_BROWSER, dm.is_panel_visible(PANEL_BROWSER))
	_set_check(VID_TOGGLE_GRAPH, dm.is_panel_visible(PANEL_GRAPH))
	_set_check(VID_TOGGLE_TIMELINE, dm.is_panel_visible(PANEL_TIMELINE))
	_set_check(VID_TOGGLE_INSPECTOR, dm.is_panel_visible(PANEL_INSPECTOR))
	_set_check(VID_TOGGLE_PLAYER, dm.is_panel_visible(PANEL_PLAYER))
	_set_check(VID_TOGGLE_MIXER, dm.is_panel_visible(PANEL_MIXER))
	_set_check(VID_TOGGLE_LOG, dm.is_panel_visible(PANEL_LOG))


func _set_check(item_id: int, checked: bool) -> void:
	var idx: int = _view_menu.get_item_index(item_id)
	if idx >= 0:
		_view_menu.set_item_checked(idx, checked)


func _rebuild_build_menu_items() -> void:
	if _build_menu == null:
		return
	_build_menu.clear()
	_build_menu.add_item("New Bank…", BID_NEW_BANK)
	_build_menu.add_item("Validate All Banks", BID_VALIDATE_BANKS)
	_build_menu.add_separator()
	var st: Variant = _current_state()
	if st == null or (st as CodaState).banks.is_empty():
		_build_menu.add_item("(no banks defined)", -1)
		_build_menu.set_item_disabled(_build_menu.item_count - 1, true)
		return
	var state: CodaState = st as CodaState
	for i in state.banks.size():
		_build_menu.add_item("Export “%s”…" % state.banks[i].bank_name, BID_EXPORT_BANK_BASE + i)


func _current_state() -> Variant:
	if _browser_panel != null and _browser_panel.has_method(&"get_project"):
		return _browser_panel.get_project()
	return null


func _on_build_id_pressed(id: int) -> void:
	match id:
		BID_NEW_BANK:
			_action_new_bank()
		BID_VALIDATE_BANKS:
			_action_validate_banks()
		_:
			if id >= BID_EXPORT_BANK_BASE:
				await _action_export_bank_async(id - BID_EXPORT_BANK_BASE)


func _action_new_bank() -> void:
	var st: Variant = _current_state()
	if st == null:
		return
	var state: CodaState = st as CodaState
	var b: CodaBank = state.add_bank("Bank %d" % (state.banks.size() + 1))
	NexusCodaLog.info("bank", 'Created bank "%s"' % b.bank_name)


func _action_validate_banks() -> void:
	var st: Variant = _current_state()
	if st == null:
		return
	var state: CodaState = st as CodaState
	if state.banks.is_empty():
		_editor_notify("No banks defined.", false)
		return
	var problems_total: int = 0
	for b in state.banks:
		var problems: PackedStringArray = CodaBankExportScript.validate_bank(state, b)
		if problems.is_empty():
			NexusCodaLog.info("bank", '"%s" passes validation.' % b.bank_name)
			continue
		problems_total += problems.size()
		for p in problems:
			NexusCodaLog.warn("bank", '"%s": %s' % [b.bank_name, p])
	_editor_notify(
		"Validation finished: %d issue(s) — see Log panel." % problems_total,
		problems_total > 0
	)


func _action_export_bank_async(bank_index: int) -> void:
	var st: Variant = _current_state()
	if st == null:
		return
	var state: CodaState = st as CodaState
	if bank_index < 0 or bank_index >= state.banks.size():
		return
	var bank: CodaBank = state.banks[bank_index]
	var problems: PackedStringArray = CodaBankExportScript.validate_bank(state, bank)
	if not problems.is_empty():
		for p in problems:
			NexusCodaLog.warn("bank_export", '"%s": %s' % [bank.bank_name, p])
		_editor_notify(
			'Bank "%s" has %d validation issue(s) — fix in Log panel before exporting.'
			% [bank.bank_name, problems.size()],
			true
		)
		return
	var p: String = await _pick_bank_save_path(bank.bank_name)
	if p.is_empty():
		return
	if p.get_extension().to_lower() != CodaBankExportScript.FORMAT_EXTENSION:
		p = "%s.%s" % [p, CodaBankExportScript.FORMAT_EXTENSION]
	var err: String = CodaBankExportScript.write_to_path(state, bank, p)
	if not err.is_empty():
		_editor_notify(err, true)
		return
	_editor_notify('Exported bank "%s" to %s' % [bank.bank_name, p], false)


func _pick_bank_save_path(suggest_name: String) -> String:
	if _plugin == null:
		return ""
	var base: Control = _plugin.get_editor_interface().get_base_control()
	var dlg := EditorFileDialog.new()
	dlg.use_native_dialog = false
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dlg.title = "Export Nexus Coda Bank"
	dlg.clear_filters()
	dlg.add_filter(CodaBankExportScript.FORMAT_FILTER)
	dlg.current_dir = "res://"
	dlg.current_file = "%s.%s" % [
		suggest_name.strip_edges().replace(" ", "_").to_lower(),
		CodaBankExportScript.FORMAT_EXTENSION,
	]
	base.add_child(dlg)
	var path: String = await _await_editor_file_path(dlg)
	dlg.queue_free()
	return path


## Save dialog for [AudioBusLayout] — user picks filename and folder (not tied to [code]default_bus_layout.tres[/code]).
func pick_audio_bus_layout_export_path_async() -> String:
	if _plugin == null:
		return ""
	var base: Control = _plugin.get_editor_interface().get_base_control()
	var dlg := EditorFileDialog.new()
	dlg.use_native_dialog = false
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dlg.title = "Export Audio Bus Layout"
	dlg.clear_filters()
	dlg.add_filter("*.tres ; Godot AudioBusLayout")
	dlg.current_dir = "res://"
	dlg.current_file = "bus_layout.tres"
	base.add_child(dlg)
	var path: String = await _await_editor_file_path(dlg)
	dlg.queue_free()
	return path


func complete_audio_bus_layout_export(saved_path: String, err: Error) -> void:
	if err != OK:
		_editor_notify("Could not export bus layout (%s)." % error_string(err), true)
		return
	if saved_path.is_empty():
		_editor_notify("Bus layout export finished without a path.", true)
		return
	_editor_notify('Exported bus layout to "%s"' % saved_path, false)
	_refresh_editor_filesystem_after_save(saved_path)


func _rebuild_help_menu_items() -> void:
	if _help_menu == null:
		return
	_help_menu.clear()
	_help_menu.add_item("Command Palette…", HID_COMMAND_PALETTE)
	_help_menu.add_item("Keyboard Shortcuts…", HID_SHORTCUTS)
	_help_menu.add_separator()
	_help_menu.add_item("Open Sample Project", HID_OPEN_SAMPLE)
	_help_menu.add_separator()
	var st: CodaState = _current_state() as CodaState
	var mode_label: String = "Switch to Light Theme"
	if st != null and st.theme_mode == "light":
		mode_label = "Switch to Dark Theme"
	_help_menu.add_item(mode_label, HID_TOGGLE_THEME_MODE)
	_help_menu.add_item("Pick Accent Color…", HID_PICK_ACCENT)


func _on_help_id_pressed(id: int) -> void:
	match id:
		HID_COMMAND_PALETTE:
			_open_command_palette()
		HID_SHORTCUTS:
			_open_shortcut_sheet()
		HID_OPEN_SAMPLE:
			await _action_open_sample_async()
		HID_TOGGLE_THEME_MODE:
			_action_toggle_theme_mode()
		HID_PICK_ACCENT:
			_action_pick_accent_color()
		_:
			pass


func _action_open_sample_async() -> void:
	var ok: bool = await _confirm_unsaved_async()
	if not ok:
		return
	var sample: CodaState = CodaSampleProjectScript.build()
	_apply_loaded_state(sample)
	_current_path = ""
	_dirty = true
	_update_title()
	_apply_theme_appearance(sample.theme_mode, sample.accent_color)
	NexusCodaLog.info(
		"sample",
		"Opened onboarding sample. Drag your own audio onto the SOUND nodes to hear it."
	)


func _action_toggle_theme_mode() -> void:
	var st: CodaState = _current_state() as CodaState
	if st == null:
		return
	var next_mode: String = "light" if st.theme_mode == "dark" else "dark"
	st.set_theme_appearance(next_mode, st.accent_color)
	_apply_theme_appearance(st.theme_mode, st.accent_color)


func _action_pick_accent_color() -> void:
	var st: CodaState = _current_state() as CodaState
	if st == null:
		return
	if _color_picker_dialog != null and is_instance_valid(_color_picker_dialog):
		_color_picker_dialog.queue_free()
	_color_picker_dialog = AcceptDialog.new()
	_color_picker_dialog.title = "Pick Accent Color"
	add_child(_color_picker_dialog)
	var picker := ColorPicker.new()
	picker.color = st.accent_color
	picker.edit_alpha = false
	_color_picker_dialog.add_child(picker)
	picker.color_changed.connect(
		func(c: Color) -> void:
			st.set_theme_appearance(st.theme_mode, c)
			_apply_theme_appearance(st.theme_mode, c)
	)
	_color_picker_dialog.popup_centered_ratio(0.4)


func _apply_theme_appearance(theme_mode: String, accent: Color) -> void:
	_project_theme = CodaDesignTokens.make_project_theme(theme_mode, accent)
	# Window inherits Theme via the root control.
	var root: Control = $RootVBox
	if root != null:
		root.theme = _project_theme


func _open_command_palette() -> void:
	if _command_palette == null:
		return
	_command_palette.set_entries(_collect_palette_entries())
	_command_palette.open()


func _open_shortcut_sheet() -> void:
	if _shortcut_sheet == null:
		return
	_shortcut_sheet.open()


func _collect_palette_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dm: CodaDockManager = _dock_host.dock_manager if _dock_host != null else null

	# File actions.
	out.append({"title": "New Project", "subtitle": "Ctrl+N", "category": "File",
		"callable": Callable(self, "_action_new_async")})
	out.append({"title": "Open Project…", "subtitle": "Ctrl+O", "category": "File",
		"callable": Callable(self, "_action_open_async")})
	out.append({"title": "Save", "subtitle": "Ctrl+S", "category": "File",
		"callable": Callable(self, "_action_save_async")})
	out.append({"title": "Save As…", "subtitle": "Ctrl+Shift+S", "category": "File",
		"callable": Callable(self, "_action_save_as_async")})
	out.append({"title": "Close Window", "subtitle": "", "category": "File",
		"callable": Callable(self, "_action_close_window_async")})

	# View toggles.
	if dm != null:
		var panels: Array = [
			[PANEL_BROWSER, "Toggle Browser Panel"],
			[PANEL_GRAPH, "Toggle Graph Panel"],
			[PANEL_TIMELINE, "Toggle Timeline Panel"],
			[PANEL_INSPECTOR, "Toggle Inspector Panel"],
			[PANEL_PLAYER, "Toggle Player Panel"],
			[PANEL_MIXER, "Toggle Mixer Panel"],
			[PANEL_LOG, "Toggle Log Panel"],
		]
		for entry_v in panels:
			var arr: Array = entry_v as Array
			var pid: StringName = arr[0]
			var title: String = arr[1]
			out.append({"title": title, "subtitle": "", "category": "View",
				"callable": Callable(dm, "toggle_panel").bind(pid)})
		out.append({"title": "Save Layout", "subtitle": "", "category": "View",
			"callable": Callable(self, "_save_custom_layout")})
		out.append({"title": "Load Saved Layout", "subtitle": "", "category": "View",
			"callable": Callable(self, "_load_custom_layout")})
		out.append({"title": "Clear Saved Layout", "subtitle": "", "category": "View",
			"callable": Callable(self, "_clear_custom_layout")})
		out.append({"title": "Reset Layout", "subtitle": "", "category": "View",
			"callable": Callable(self, "_reset_to_factory_layout")})

	# Player transport.
	if _player_panel != null:
		out.append({"title": "Player: Play Selection", "subtitle": "", "category": "Player",
			"callable": Callable(_player_panel, "play_current_selection")})
		out.append({"title": "Player: Stop", "subtitle": "", "category": "Player",
			"callable": Callable(_player_panel, "stop_current_voice")})
		out.append({"title": "Player: Pin / Unpin Selection", "subtitle": "", "category": "Player",
			"callable": Callable(_player_panel, "toggle_pin")})

	# Build/banks.
	out.append({"title": "Create New Bank", "subtitle": "", "category": "Build",
		"callable": Callable(self, "_action_new_bank")})
	out.append({"title": "Validate All Banks", "subtitle": "", "category": "Build",
		"callable": Callable(self, "_action_validate_banks")})

	# Help / theme.
	out.append({"title": "Open Sample Project", "subtitle": "", "category": "Help",
		"callable": Callable(self, "_action_open_sample_async")})
	out.append({"title": "Keyboard Shortcuts", "subtitle": "F1", "category": "Help",
		"callable": Callable(self, "_open_shortcut_sheet")})
	out.append({"title": "Toggle Theme Mode", "subtitle": "Light/Dark", "category": "Theme",
		"callable": Callable(self, "_action_toggle_theme_mode")})
	out.append({"title": "Pick Accent Color…", "subtitle": "", "category": "Theme",
		"callable": Callable(self, "_action_pick_accent_color")})

	# Event navigation: jump to event in browser/graph.
	var st: CodaState = _current_state() as CodaState
	if st != null and _browser_panel != null:
		var paths: Array[Dictionary] = []
		_collect_event_paths(st.events_root, "", paths)
		for p in paths:
			var event_id: String = str(p.get("id", ""))
			var path: String = str(p.get("path", ""))
			if event_id.is_empty():
				continue
			out.append({
				"title": path,
				"subtitle": "Open in browser",
				"category": "Event",
				"callable": Callable(self, "_select_event_by_id").bind(event_id),
			})
	return out


func _collect_event_paths(folder: CodaBrowserNode, prefix: String, out: Array[Dictionary]) -> void:
	for child in folder.children:
		var path: String = "%s/%s" % [prefix, child.name] if not prefix.is_empty() else child.name
		if child.kind == CodaBrowserNode.Kind.EVENT:
			out.append({"id": child.id, "path": path})
		elif child.is_folder():
			_collect_event_paths(child, path, out)


func _select_event_by_id(event_id: String) -> void:
	if _browser_panel == null:
		return
	if _browser_panel.has_method(&"select_event_by_id"):
		_browser_panel.select_event_by_id(event_id)
	elif _browser_panel.has_method(&"focus_event"):
		_browser_panel.focus_event(event_id)
	else:
		NexusCodaLog.info("palette", "Event id=%s — open the Browser to select it." % event_id)


func _on_view_id_pressed(id: int) -> void:
	if _dock_host == null or _dock_host.dock_manager == null:
		return
	var dm: CodaDockManager = _dock_host.dock_manager
	match id:
		VID_SAVE_LAYOUT:
			_save_custom_layout()
		VID_TOGGLE_BROWSER:
			dm.toggle_panel(PANEL_BROWSER)
		VID_TOGGLE_GRAPH:
			dm.toggle_panel(PANEL_GRAPH)
		VID_TOGGLE_TIMELINE:
			dm.toggle_panel(PANEL_TIMELINE)
		VID_TOGGLE_INSPECTOR:
			dm.toggle_panel(PANEL_INSPECTOR)
		VID_TOGGLE_PLAYER:
			dm.toggle_panel(PANEL_PLAYER)
		VID_TOGGLE_MIXER:
			dm.toggle_panel(PANEL_MIXER)
		VID_TOGGLE_LOG:
			dm.toggle_panel(PANEL_LOG)
		VID_LOAD_LAYOUT:
			_load_custom_layout()
		VID_CLEAR_SAVED_LAYOUT:
			_clear_custom_layout()
		VID_RESET_LAYOUT:
			_reset_to_factory_layout()
		_:
			pass
	_refresh_view_menu_check_marks()


func _reset_to_factory_layout() -> void:
	if _dock_host == null or _dock_host.dock_manager == null:
		return
	_set_preferred_layout(CUSTOM_LAYOUT_PREF_FACTORY)
	_dock_host.dock_manager.reset_to_default_layout()


func _on_layout_changed() -> void:
	# Intentionally no autosave: user chooses when to persist custom layout.
	pass


func _custom_layout_store_path() -> String:
	if _plugin == null:
		return ""
	var cache: String = _plugin.get_editor_interface().get_editor_paths().get_cache_dir()
	if cache.is_empty():
		return ""
	return cache.path_join(CUSTOM_LAYOUT_SUBDIR).path_join(CUSTOM_LAYOUT_FILENAME)


func _layout_prefs_store_path() -> String:
	if _plugin == null:
		return ""
	var cache: String = _plugin.get_editor_interface().get_editor_paths().get_cache_dir()
	if cache.is_empty():
		return ""
	return cache.path_join(CUSTOM_LAYOUT_SUBDIR).path_join(CUSTOM_LAYOUT_PREFS_FILENAME)


func _get_preferred_layout() -> String:
	var p: String = _layout_prefs_store_path()
	if p.is_empty() or not FileAccess.file_exists(p):
		return CUSTOM_LAYOUT_PREF_CUSTOM  # Back-compat: custom layout file existing used to imply preference.
	var text: String = FileAccess.get_file_as_string(p)
	if text.is_empty():
		return CUSTOM_LAYOUT_PREF_CUSTOM
	var json := JSON.new()
	if json.parse(text) != OK:
		return CUSTOM_LAYOUT_PREF_CUSTOM
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return CUSTOM_LAYOUT_PREF_CUSTOM
	var pref: String = str((root as Dictionary).get(CUSTOM_LAYOUT_PREFS_KEY, CUSTOM_LAYOUT_PREF_CUSTOM))
	return pref if pref in [CUSTOM_LAYOUT_PREF_FACTORY, CUSTOM_LAYOUT_PREF_CUSTOM] else CUSTOM_LAYOUT_PREF_CUSTOM


func _set_preferred_layout(pref: String) -> void:
	var p: String = _layout_prefs_store_path()
	if p.is_empty():
		return
	var dir_path: String = p.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(dir_path)
	var payload := {
		"version": 1,
		CUSTOM_LAYOUT_PREFS_KEY: pref,
	}
	var text: String = JSON.stringify(payload, "  ")
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	if f.has_method(&"flush"):
		f.flush()
	f.close()


func _save_custom_layout() -> void:
	if _dock_host == null or _dock_host.dock_manager == null:
		return
	var path: String = _custom_layout_store_path()
	if path.is_empty():
		return
	var dir_path: String = path.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(dir_path)
	var dm: CodaDockManager = _dock_host.dock_manager
	var payload := {
		"version": 1,
		"layout": dm.get_layout_state(),
	}
	var text: String = JSON.stringify(payload, "  ")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		NexusCodaLog.warn("layout", "Could not save custom layout (%s)" % str(FileAccess.get_open_error()))
		return
	f.store_string(text)
	if f.has_method(&"flush"):
		f.flush()
	f.close()
	_set_preferred_layout(CUSTOM_LAYOUT_PREF_CUSTOM)
	NexusCodaLog.info("layout", "Saved custom layout.")


func _load_custom_layout_if_present() -> void:
	var path: String = _custom_layout_store_path()
	if _get_preferred_layout() != CUSTOM_LAYOUT_PREF_CUSTOM:
		return
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	_load_custom_layout()


func _load_custom_layout() -> void:
	if _dock_host == null or _dock_host.dock_manager == null:
		return
	var path: String = _custom_layout_store_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		NexusCodaLog.info("layout", "No saved custom layout found.")
		return
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		NexusCodaLog.warn("layout", "Saved custom layout is invalid JSON.")
		return
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return
	var layout: Variant = (root as Dictionary).get("layout", null)
	if typeof(layout) != TYPE_DICTIONARY:
		return
	_dock_host.dock_manager.apply_layout_state(layout as Dictionary)
	_set_preferred_layout(CUSTOM_LAYOUT_PREF_CUSTOM)
	NexusCodaLog.info("layout", "Loaded custom layout.")


func _clear_custom_layout() -> void:
	var path: String = _custom_layout_store_path()
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		var err: Error = DirAccess.remove_absolute(path)
		if err != OK:
			NexusCodaLog.warn("layout", "Could not remove saved custom layout (%s)" % error_string(err))
			return
	_set_preferred_layout(CUSTOM_LAYOUT_PREF_FACTORY)
	NexusCodaLog.info("layout", "Cleared saved custom layout.")


func _on_panel_visibility_changed(_panel_id: StringName, _is_visible: bool) -> void:
	_refresh_view_menu_check_marks()


func _fill_recent_menu() -> void:
	CodaProjectIo.prune_missing_recent_paths(_plugin)
	_recent_menu.clear()
	_recent_paths_snapshot = CodaProjectIo.read_recent_paths(_plugin)
	if _recent_paths_snapshot.is_empty():
		_recent_menu.add_item("(No recent projects)", RECENT_ID_BASE)
		_recent_menu.set_item_disabled(_recent_menu.item_count - 1, true)
		return
	for i in _recent_paths_snapshot.size():
		var label: String = _recent_paths_snapshot[i]
		if label.length() > 72:
			label = "…" + label.substr(label.length() - 71, 71)
		_recent_menu.add_item(label, RECENT_ID_BASE + i)


func _on_file_id_pressed(id: int) -> void:
	match id:
		MID_NEW:
			await _action_new_async()
		MID_OPEN:
			await _action_open_async()
		MID_CLOSE:
			await _action_close_window_async()
		MID_SAVE:
			await _action_save_async()
		MID_SAVE_AS:
			await _action_save_as_async()
		_:
			pass


func _on_recent_id_pressed(id: int) -> void:
	var idx: int = id - RECENT_ID_BASE
	if idx < 0 or idx >= _recent_paths_snapshot.size():
		return
	var path: String = _recent_paths_snapshot[idx]
	await _open_path_after_confirm_async(path)


## One ephemeral dialog per call so multiple Nexus windows never share signals or state.
func _pick_file_via_editor_dialog(save_mode: bool, suggested_file: String = "") -> String:
	if _plugin == null:
		return ""
	var base: Control = _plugin.get_editor_interface().get_base_control()
	var dlg := EditorFileDialog.new()
	# Windows native file dialog is known to skip file_selected (Godot #94154); use Godot UI dialog.
	dlg.use_native_dialog = false
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.file_mode = (
		EditorFileDialog.FILE_MODE_SAVE_FILE
		if save_mode
		else EditorFileDialog.FILE_MODE_OPEN_FILE
	)
	dlg.title = (
		"Save Nexus Coda Project As" if save_mode else "Open Nexus Coda Project"
	)
	dlg.clear_filters()
	dlg.add_filter(CodaProjectIo.FORMAT_FILTER)
	dlg.current_dir = "res://"
	if save_mode and not suggested_file.is_empty():
		dlg.current_file = suggested_file
	base.add_child(dlg)
	var path: String = await _await_editor_file_path(dlg)
	dlg.queue_free()
	return path


func _bind_project_signals(state: Variant) -> void:
	if _project_signal_source != null and is_instance_valid(_project_signal_source):
		if _project_signal_source.structure_changed.is_connected(_on_project_structure_changed):
			_project_signal_source.structure_changed.disconnect(_on_project_structure_changed)
		if _project_signal_source.project_dirty.is_connected(_on_project_structure_changed):
			_project_signal_source.project_dirty.disconnect(_on_project_structure_changed)
	_project_signal_source = null
	if state == null:
		return
	var st: CodaState = state as CodaState
	if st == null:
		return
	_project_signal_source = st
	st.structure_changed.connect(_on_project_structure_changed)
	st.project_dirty.connect(_on_project_structure_changed)


func _on_project_structure_changed() -> void:
	if _suppress_dirty:
		return
	_dirty = true
	_update_title()


func _update_title() -> void:
	var doc_name: String = "Untitled"
	if not _current_path.is_empty():
		doc_name = _current_path.get_file()
	title = "Nexus Coda — %s%s" % [doc_name, " *" if _dirty else ""]
	if _status_bar != null:
		_status_bar.set_project_state(_current_path, _dirty)


func _load_empty_project() -> void:
	_suppress_dirty = true
	var st: CodaState = CodaStateScript.new()
	st.clear_to_empty_project()
	_apply_state_to_panels(st)
	_suppress_dirty = false


func _apply_loaded_state(st: CodaState) -> void:
	_suppress_dirty = true
	_apply_state_to_panels(st)
	_suppress_dirty = false


func _apply_state_to_panels(st: CodaState) -> void:
	if _browser_panel != null and _browser_panel.has_method(&"set_project"):
		_browser_panel.set_project(st)
	_bind_project_signals(st)
	_push_project_to_runtime(st)
	if _graph_panel != null:
		_graph_panel.attach_project(st)
		_graph_panel.on_browser_event_selected(null)
	if _inspector_panel != null:
		_inspector_panel.attach_project(st)
		_inspector_panel.on_browser_event_selected(null)
	if _player_panel != null:
		_player_panel.attach_project(st)
		_player_panel.on_browser_event_selected(null)
	if _timeline_panel != null:
		_timeline_panel.attach_project(st)
		_timeline_panel.on_browser_event_selected(null)
	if _mixer_panel != null:
		_mixer_panel.attach_project(st)
	if _browser_panel != null and _browser_panel.has_method(&"pulse_events_selection_to_editor"):
		_browser_panel.pulse_events_selection_to_editor()
	if st != null:
		_apply_theme_appearance(st.theme_mode, st.accent_color)


func _action_new_async() -> void:
	if _plugin != null and _plugin.has_method(&"spawn_new_coda_editor_window"):
		_plugin.spawn_new_coda_editor_window()
		NexusCodaLog.info("project_io", "Opened new Nexus Coda editor instance")
	else:
		NexusCodaLog.warn("project_io", "Cannot spawn editor (plugin missing spawn_new_coda_editor_window)")


func _action_close_window_async() -> void:
	var ok: bool = await _confirm_unsaved_async()
	if not ok:
		return
	NexusCodaLog.info("project_io", "Closing Nexus Coda editor instance")
	queue_free()


func _action_open_async() -> void:
	var ok: bool = await _confirm_unsaved_async()
	if not ok:
		return
	var p: String = await _pick_file_via_editor_dialog(false)
	if not p.is_empty():
		_open_path_internal(p)


func _open_path_after_confirm_async(path: String) -> void:
	var ok: bool = await _confirm_unsaved_async()
	if not ok:
		return
	_open_path_internal(path)


func _open_path_internal(path: String) -> void:
	var loaded: Variant = CodaProjectIo.load_state_from_path(path)
	if loaded is String:
		if str(loaded) == CodaProjectIo.ERR_FILE_MISSING:
			CodaProjectIo.remove_recent_path(_plugin, path)
		_editor_notify(loaded, true)
		return
	var st: CodaState = loaded as CodaState
	if st == null:
		NexusCodaLog.error("project_io", "Could not load project.")
		return
	_apply_loaded_state(st)
	_current_path = path
	_dirty = false
	CodaProjectIo.remember_opened_path(_plugin, path)
	_update_title()
	NexusCodaLog.info("project_io", 'Opened "%s"' % path)


func _action_save_async() -> void:
	if _current_path.is_empty():
		await _action_save_as_async()
		return
	await _save_to_current_path_async()


func _action_save_as_async() -> void:
	var suggest := ""
	if not _current_path.is_empty():
		suggest = _current_path.get_file()
	var p: String = await _pick_file_via_editor_dialog(true, suggest)
	if p.is_empty():
		NexusCodaLog.warn(
			"project_io",
			"Save dialog returned no path; saving to fallback %s" % FALLBACK_SAVE_RES_PATH
		)
		OS.alert(
			(
				"The save dialog did not return a file path (known issue with some Godot/editor builds).\n"
				+ "Saving to:\n%s"
			)
			% FALLBACK_SAVE_RES_PATH,
			"Nexus Coda"
		)
		p = FALLBACK_SAVE_RES_PATH
	if p.get_extension().to_lower() != CodaProjectIo.FORMAT_EXTENSION:
		p = "%s.%s" % [p, CodaProjectIo.FORMAT_EXTENSION]
	var err_msg: String = _write_and_finish_save(p)
	if not err_msg.is_empty():
		_editor_notify(err_msg, true)


func _save_to_current_path_async() -> void:
	var err_msg: String = _write_and_finish_save(_current_path)
	if not err_msg.is_empty():
		_editor_notify(err_msg, true)


func _write_and_finish_save(path: String) -> String:
	var st: Variant = _browser_panel.get_project() if _browser_panel.has_method(&"get_project") else null
	if st == null:
		return "No project state."
	var msg: String = CodaProjectIo.save_to_path(st as CodaState, path)
	if not msg.is_empty():
		return msg
	_current_path = path
	_dirty = false
	CodaProjectIo.remember_opened_path(_plugin, path)
	_update_title()
	NexusCodaLog.info("project_io", 'Saved "%s"' % path)
	_refresh_editor_filesystem_after_save(path)
	return ""


func _refresh_editor_filesystem_after_save(path: String) -> void:
	if _plugin == null:
		return
	var fs: EditorFileSystem = _plugin.get_editor_interface().get_resource_filesystem()
	if fs == null:
		return
	# Newly created res:// files are not known to EditorFileSystem until update_file/scan.
	# Native .tres/.res written via ResourceSaver are not imported assets — reimport_files then
	# errors with "importer for type '' not found" (see bus layout export, etc.).
	if path.begins_with("res://"):
		if fs.has_method(&"update_file"):
			fs.update_file(path)
		var ext: String = path.get_extension().to_lower()
		if ext != "tres" and ext != "res" and fs.has_method(&"reimport_files"):
			fs.reimport_files(PackedStringArray([path]))
	elif fs.has_method(&"scan"):
		fs.call_deferred(&"scan")


func _await_editor_file_path(dlg: EditorFileDialog) -> String:
	_file_dialog_pick_result = ""
	_file_dialog_pick_complete = false

	dlg.file_selected.connect(_on_editor_file_dialog_file_selected, CONNECT_ONE_SHOT)
	dlg.files_selected.connect(_on_editor_file_dialog_files_selected, CONNECT_ONE_SHOT)
	dlg.canceled.connect(_on_editor_file_dialog_canceled, CONNECT_ONE_SHOT)

	dlg.popup_centered_ratio(0.85)
	while not _file_dialog_pick_complete and is_instance_valid(dlg):
		await get_tree().process_frame

	if not _file_dialog_pick_result.is_empty():
		return _file_dialog_pick_result
	var cp: Variant = dlg.get("current_path")
	if cp != null:
		var s: String = str(cp).strip_edges()
		if not s.is_empty():
			return s
	return ""


func _on_editor_file_dialog_file_selected(path: String) -> void:
	if not path.is_empty():
		_file_dialog_pick_result = path
	_file_dialog_pick_complete = true


func _on_editor_file_dialog_files_selected(paths: PackedStringArray) -> void:
	if _file_dialog_pick_complete:
		return
	if paths.size() > 0:
		_file_dialog_pick_result = str(paths[0])
	_file_dialog_pick_complete = true


func _on_editor_file_dialog_canceled() -> void:
	if _file_dialog_pick_complete:
		return
	_file_dialog_pick_complete = true


func _editor_notify(message: String, is_error: bool = false) -> void:
	if is_error:
		NexusCodaLog.error("project_io", message)
		OS.alert(message, "Nexus Coda")
	else:
		NexusCodaLog.info("project_io", message)


func _confirm_unsaved_async() -> bool:
	if not _dirty:
		return true
	_choice_result = 0
	await _run_three_button_prompt_async(
		"Save changes to the current project?",
		"Save",
		"Don't Save",
		"Cancel"
	)
	var r: int = _choice_result
	if r == 0:
		return false
	if r == 2:
		return true
	if r == 1:
		await _action_save_async()
		if _dirty:
			return false
		return true
	return false


func _run_three_button_prompt_async(
	line: String, save_txt: String, discard_txt: String, cancel_txt: String
) -> void:
	if has_node(UNSAVED_LAYER_NODEPATH):
		get_node(UNSAVED_LAYER_NODEPATH).queue_free()

	var layer := CanvasLayer.new()
	layer.name = "UnsavedPromptLayer"
	layer.layer = 128
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.08, 0.1, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)

	var title := Label.new()
	title.text = "Nexus Coda"
	vb.add_child(title)

	var lbl := Label.new()
	lbl.text = line
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)

	var b_cancel := Button.new()
	b_cancel.text = cancel_txt
	var b_disc := Button.new()
	b_disc.text = discard_txt
	var b_save := Button.new()
	b_save.text = save_txt

	hb.add_child(b_cancel)
	hb.add_child(b_disc)
	hb.add_child(b_save)

	var finished := false
	var apply_pick := func(result: int) -> void:
		_choice_result = result
		finished = true
		if is_instance_valid(layer):
			layer.queue_free()
	var pick: Callable = Callable(apply_pick)

	b_save.pressed.connect(func(): pick.call(1))
	b_disc.pressed.connect(func(): pick.call(2))
	b_cancel.pressed.connect(func(): pick.call(0))

	while not finished and is_instance_valid(layer):
		await get_tree().process_frame


func _on_close_requested() -> void:
	if _dirty:
		var ok: bool = await _confirm_unsaved_async()
		if not ok:
			return
	_teardown_before_close()
	queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_teardown_before_close()
		if has_node(UNSAVED_LAYER_NODEPATH):
			get_node(UNSAVED_LAYER_NODEPATH).queue_free()


func _teardown_before_close() -> void:
	if _teardown_done:
		return
	_teardown_done = true

	# Detach docked panels so their controls don't keep references alive through TabContainer internals.
	if _dock_host != null and _dock_host.dock_manager != null:
		var dm: CodaDockManager = _dock_host.dock_manager
		var state: Dictionary = dm.get_layout_state()
		for zone_id_s in state.keys():
			var zone := dm.get_zone(StringName(str(zone_id_s)))
			if zone == null:
				continue
			for ctrl in zone.panel_controls():
				if ctrl != null and ctrl.get_parent() != null:
					ctrl.get_parent().remove_child(ctrl)

	# Free overlays explicitly (they may create internal fonts/textures/RIDs).
	if _command_palette != null and is_instance_valid(_command_palette):
		_command_palette.queue_free()
	_command_palette = null
	if _shortcut_sheet != null and is_instance_valid(_shortcut_sheet):
		_shortcut_sheet.queue_free()
	_shortcut_sheet = null
	if _status_bar != null and is_instance_valid(_status_bar):
		_status_bar.queue_free()
	_status_bar = null
	if _color_picker_dialog != null and is_instance_valid(_color_picker_dialog):
		_color_picker_dialog.queue_free()
	_color_picker_dialog = null

	# Free panels explicitly (they are re-created on next open anyway).
	if _browser_panel != null and is_instance_valid(_browser_panel):
		_browser_panel.queue_free()
	_browser_panel = null
	if _graph_panel != null and is_instance_valid(_graph_panel):
		_graph_panel.queue_free()
	_graph_panel = null
	if _inspector_panel != null and is_instance_valid(_inspector_panel):
		_inspector_panel.queue_free()
	_inspector_panel = null
	if _player_panel != null and is_instance_valid(_player_panel):
		_player_panel.stop_current_voice()
		_player_panel.queue_free()
	_player_panel = null
	if _timeline_panel != null and is_instance_valid(_timeline_panel):
		_timeline_panel.queue_free()
	_timeline_panel = null
	if _mixer_panel != null and is_instance_valid(_mixer_panel):
		_mixer_panel.queue_free()
	_mixer_panel = null
	if _log_panel != null and is_instance_valid(_log_panel):
		_log_panel.queue_free()
	_log_panel = null
