@tool
extends Window

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaProjectIo := preload("res://addons/nexus_coda/domain/io/coda_project_io.gd")
const CodaDesignTokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
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
const CodaEditorPreviewControllerScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_preview_controller.gd"
)
const CodaEditorShortcutRouterScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_shortcut_router.gd"
)
const CodaEditorSelectionRouterScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_selection_router.gd"
)
const CodaInspectorSelectionScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_inspector_selection.gd"
)
const CodaEditorAuthoringFocusScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_authoring_focus.gd"
)
const CodaEditorLayoutStoreScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_layout_store.gd"
)
const CodaEditorTransportScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_transport.gd"
)
const CodaEditorFileDialogsScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_file_dialogs.gd"
)
const CodaEditorProjectSessionScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_project_session.gd"
)
const CodaEditorMenuActionsScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_menu_actions.gd"
)
const CodaEditorLayoutPersistenceScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_layout_persistence.gd"
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
var _project_theme: Theme

var _browser_panel: Control
var _graph_panel: CodaEventGraphPanel
var _inspector_panel: CodaInspectorPanel
var _mixer_panel: CodaMixerPanel
var _log_panel: CodaLogPanel
var _player_panel: CodaPlayerPanel
var _timeline_panel: CodaTimelinePanel
var _inspector_selection: CodaInspectorSelection
var _inspector_subject_locked_by: StringName = &""

var _file_dialogs: CodaEditorFileDialogs
var _project_session: CodaEditorProjectSession
var _menu_actions: CodaEditorMenuActions
var _layout_persistence: CodaEditorLayoutPersistence

const UNSAVED_LAYER_NODEPATH := NodePath("UnsavedPromptLayer")

var _restore_autosave_on_start: bool = true

var _teardown_done: bool = false
var _fs_asset_import_boot_attempts: int = 0
var _selection_router: CodaEditorSelectionRouter
var _authoring_focus: CodaEditorAuthoringFocus
var _editor_transport: CodaEditorTransport
var _preview_controller: CodaEditorPreviewController
var _pool_exhausted_slot: Callable = Callable()
var _playhead_sync_slot: Callable = Callable()
var _focused_panel_id: StringName = &""


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


func set_restore_autosave_on_start(enabled: bool) -> void:
	_restore_autosave_on_start = enabled


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
	var k: InputEventKey = event as InputEventKey
	var handled: bool = CodaEditorShortcutRouterScript.match_and_route(k, {
		&"open_command_palette": Callable(self, &"_open_command_palette"),
		&"open_shortcut_sheet": Callable(self, &"_open_shortcut_sheet"),
		&"new_project": Callable(self, &"_session_new_async"),
		&"open_project": Callable(self, &"_session_open_async"),
		&"save_project": Callable(self, &"_session_save_async"),
		&"save_project_as": Callable(self, &"_session_save_as_async"),
		&"browser_rename": Callable(self, &"_shortcut_browser_rename"),
		&"timeline_delete": Callable(self, &"_shortcut_timeline_delete"),
		&"browser_delete": Callable(self, &"_shortcut_browser_delete"),
		&"focus_browser": func() -> void: _focus_panel(PANEL_BROWSER),
		&"focus_graph": func() -> void: _focus_panel(PANEL_GRAPH),
		&"focus_timeline": func() -> void: _focus_panel(PANEL_TIMELINE),
		&"focus_mixer": func() -> void: _focus_panel(PANEL_MIXER),
		&"focus_player": func() -> void: _focus_panel(PANEL_PLAYER),
		&"focus_inspector": func() -> void: _focus_panel(PANEL_INSPECTOR),
	})
	if handled:
		get_viewport().set_input_as_handled()


func _shortcut_browser_rename() -> bool:
	if _browser_panel != null and _browser_panel.has_method(&"request_browser_rename"):
		return _browser_panel.request_browser_rename()
	return false


func _shortcut_timeline_delete() -> bool:
	if _timeline_panel != null and _timeline_panel.has_method(&"request_timeline_delete"):
		return bool(_timeline_panel.call(&"request_timeline_delete"))
	return false


func _shortcut_browser_delete() -> bool:
	if _browser_panel != null and _browser_panel.has_method(&"request_browser_delete"):
		return _browser_panel.request_browser_delete()
	return false


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

	_selection_router = CodaEditorSelectionRouterScript.new()
	_selection_router.dock_manager = dm
	_selection_router.browser_panel = _browser_panel
	_selection_router.mixer_panel = _mixer_panel
	_selection_router.on_inspector_selection = Callable(self, &"_on_router_inspector_selection")

	_inspector_selection = CodaInspectorSelectionScript.new()

	_editor_transport = CodaEditorTransportScript.new()
	_editor_transport.player_panel = _player_panel
	_editor_transport.timeline_panel = _timeline_panel

	_authoring_focus = CodaEditorAuthoringFocusScript.new()
	_authoring_focus.dock_manager = dm
	_authoring_focus.graph_panel = _graph_panel
	_authoring_focus.timeline_panel = _timeline_panel

	_preview_controller = CodaEditorPreviewControllerScript.new()
	_preview_controller.bind_host(self)
	_preview_controller.bind_panels(_timeline_panel, _player_panel)
	_pool_exhausted_slot = Callable(self, &"_on_runtime_voice_pool_exhausted")
	_preview_controller.set_pool_exhausted_handler(_pool_exhausted_slot)

	_setup_shell_helpers()

	_wire_browser_to_others()
	_wire_inspector_selection()
	_wire_runtime_to_panels()
	call_deferred(&"_session_initial_bind")
	call_deferred(&"_layout_load_if_present")


func _setup_shell_helpers() -> void:
	_file_dialogs = CodaEditorFileDialogsScript.new()
	_file_dialogs.setup(self, _plugin)

	_project_session = CodaEditorProjectSessionScript.new()
	_project_session.plugin = _plugin
	_project_session.file_dialogs = _file_dialogs
	_project_session.browser_panel = _browser_panel
	_project_session.graph_panel = _graph_panel
	_project_session.inspector_panel = _inspector_panel
	_project_session.player_panel = _player_panel
	_project_session.timeline_panel = _timeline_panel
	_project_session.mixer_panel = _mixer_panel
	_project_session.inspector_selection = _inspector_selection
	_project_session.on_apply_theme = Callable(self, &"_apply_theme_appearance")
	_project_session.on_push_runtime = Callable(self, &"_push_project_to_runtime")
	_project_session.on_apply_inspector = Callable(self, &"_apply_inspector_selection")
	_project_session.on_update_title = Callable(self, &"_on_session_title_changed")
	_project_session.on_notify = Callable(self, &"_editor_notify")
	_project_session.on_spawn_new_window = Callable(_plugin, &"spawn_new_coda_editor_window") if _plugin != null else Callable()
	_project_session.on_request_close = Callable(self, &"queue_free")
	_project_session.on_refresh_filesystem = Callable(self, &"_refresh_editor_filesystem_after_save")

	_layout_persistence = CodaEditorLayoutPersistenceScript.new()
	_layout_persistence.setup(self, _plugin, _dock_host)

	_menu_actions = CodaEditorMenuActionsScript.new()
	_menu_actions.session = _project_session
	_menu_actions.plugin = _plugin
	_menu_actions.file_dialogs = _file_dialogs
	_menu_actions.host = self
	_menu_actions.dock_host = _dock_host
	_menu_actions.player_panel = _player_panel
	_menu_actions.browser_panel = _browser_panel
	_menu_actions.on_apply_theme = Callable(self, &"_apply_root_theme")
	_menu_actions.on_notify = Callable(self, &"_editor_notify")
	_menu_actions.on_open_command_palette = Callable(self, &"_open_command_palette")
	_menu_actions.on_open_shortcut_sheet = Callable(self, &"_open_shortcut_sheet")
	_menu_actions.on_layout_save = Callable(_layout_persistence, &"save_custom_layout")
	_menu_actions.on_layout_load = Callable(_layout_persistence, &"load_custom_layout")
	_menu_actions.on_layout_clear = Callable(_layout_persistence, &"clear_custom_layout")
	_menu_actions.on_layout_reset = Callable(_layout_persistence, &"reset_to_factory_layout")
	_menu_actions.on_select_event = Callable(self, &"_select_event_by_id")


func _on_build_menu_about_to_popup() -> void:
	if _menu_actions != null:
		_menu_actions.rebuild_build_menu(_build_menu)


func _on_help_menu_about_to_popup() -> void:
	if _menu_actions != null:
		_menu_actions.rebuild_help_menu(_help_menu)


func _on_recent_menu_about_to_popup() -> void:
	if _project_session != null and _recent_menu != null:
		_project_session.fill_recent_menu(_recent_menu)


func _session_initial_bind() -> void:
	if _project_session != null:
		_project_session.initial_bind(_restore_autosave_on_start)
	_refresh_view_menu_check_marks()


func _session_new_async() -> void:
	if _project_session != null:
		await _project_session.action_new_async()


func _session_open_async() -> void:
	if _project_session != null:
		await _project_session.action_open_async()


func _session_save_async() -> void:
	if _project_session != null:
		await _project_session.action_save_async()


func _session_save_as_async() -> void:
	if _project_session != null:
		await _project_session.action_save_as_async()


func _session_close_async() -> void:
	if _project_session != null:
		await _project_session.action_close_window_async()


func _on_session_title_changed(path: String, dirty: bool) -> void:
	var doc_name: String = "Untitled"
	if not path.is_empty():
		doc_name = path.get_file()
	title = "Nexus Coda - %s%s" % [doc_name, " *" if dirty else ""]
	if _status_bar != null:
		_status_bar.set_project_state(path, dirty)


func _apply_root_theme(theme: Theme) -> void:
	_project_theme = theme
	var root: Control = $RootVBox
	if root != null:
		root.theme = _project_theme


func _layout_load_if_present() -> void:
	if _layout_persistence != null:
		_layout_persistence.load_custom_layout_if_present()


func _current_state() -> Variant:
	if _project_session != null:
		return _project_session.get_state()
	return null


func _wire_browser_to_others() -> void:
	if _browser_panel == null:
		return
	if _browser_panel.has_signal(&"event_selection_changed"):
		var inspector_event_slot := Callable(self, &"_on_browser_event_selection_for_inspector")
		if not _browser_panel.event_selection_changed.is_connected(inspector_event_slot):
			_browser_panel.event_selection_changed.connect(inspector_event_slot)
		var graph_slot := Callable(_graph_panel, &"on_browser_event_selected")
		var player_slot := Callable(_player_panel, &"on_browser_event_selected")
		var timeline_slot := Callable(_timeline_panel, &"on_browser_event_selected")
		if not _browser_panel.event_selection_changed.is_connected(graph_slot):
			_browser_panel.event_selection_changed.connect(graph_slot)
		if not _browser_panel.event_selection_changed.is_connected(player_slot):
			_browser_panel.event_selection_changed.connect(player_slot)
		if not _browser_panel.event_selection_changed.is_connected(timeline_slot):
			_browser_panel.event_selection_changed.connect(timeline_slot)
	if _browser_panel.has_signal(&"asset_selection_changed"):
		var inspector_asset_slot := Callable(self, &"_on_browser_asset_selection_for_inspector")
		if not _browser_panel.asset_selection_changed.is_connected(inspector_asset_slot):
			_browser_panel.asset_selection_changed.connect(inspector_asset_slot)
	if _browser_panel.has_signal(&"external_selection_requested"):
		var route_slot := Callable(self, &"_on_browser_external_selection_requested")
		if not _browser_panel.external_selection_requested.is_connected(route_slot):
			_browser_panel.external_selection_requested.connect(route_slot)
	_wire_browser_authoring_signals()
	if _plugin != null and _browser_panel.has_method(&"set_editor_plugin"):
		_browser_panel.set_editor_plugin(_plugin)
	if _inspector_panel != null:
		_inspector_panel.attach_browser_panel(_browser_panel)
		if _inspector_panel.has_signal(&"authoring_mode_changed"):
			var mode_slot := Callable(self, &"_on_inspector_authoring_mode_changed")
			if not _inspector_panel.authoring_mode_changed.is_connected(mode_slot):
				_inspector_panel.authoring_mode_changed.connect(mode_slot)
		if _inspector_panel.has_signal(&"event_output_bus_changed"):
			var bus_slot := Callable(_preview_controller, &"on_event_output_bus_changed")
			if not _inspector_panel.event_output_bus_changed.is_connected(bus_slot):
				_inspector_panel.event_output_bus_changed.connect(bus_slot)
	if _player_panel != null:
		_player_panel.attach_browser_panel(_browser_panel)
	if _graph_panel != null and _browser_panel.has_method(&"get_project"):
		_graph_panel.attach_project(_browser_panel.get_project())


func _wire_inspector_selection() -> void:
	if _timeline_panel != null:
		if not _timeline_panel.track_selection_changed.is_connected(
				_on_timeline_track_selection_for_inspector
		):
			_timeline_panel.track_selection_changed.connect(
				_on_timeline_track_selection_for_inspector
			)
		if not _timeline_panel.clip_selection_changed.is_connected(
				_on_timeline_clip_selection_for_inspector
		):
			_timeline_panel.clip_selection_changed.connect(
				_on_timeline_clip_selection_for_inspector
			)
		if not _timeline_panel.track_effects_focus_requested.is_connected(
				_on_track_effects_focus_requested
		):
			_timeline_panel.track_effects_focus_requested.connect(_on_track_effects_focus_requested)
	if _inspector_panel != null and _timeline_panel != null:
		if _inspector_panel.has_method(&"wire_timeline_preview_debounce"):
			_inspector_panel.wire_timeline_preview_debounce(_timeline_panel)
	if _mixer_panel != null:
		if not _mixer_panel.bus_user_selected.is_connected(_on_mixer_bus_selection_for_inspector):
			_mixer_panel.bus_user_selected.connect(_on_mixer_bus_selection_for_inspector)


func _inspector_project() -> CodaState:
	if _browser_panel != null and _browser_panel.has_method(&"get_project"):
		return _browser_panel.get_project() as CodaState
	return null


func _on_router_inspector_selection(
	subject: CodaInspectorSelection.Subject, payload: Dictionary = {}
) -> void:
	var lock_source: StringName = &"browser"
	match subject:
		CodaInspectorSelection.Subject.MIXER_BUS:
			lock_source = &"mixer"
		CodaInspectorSelection.Subject.TIMELINE_TRACK, CodaInspectorSelection.Subject.TIMELINE_CLIP:
			lock_source = &"timeline"
	_apply_inspector_selection(subject, payload, lock_source)


func _apply_inspector_selection(
	subject: CodaInspectorSelection.Subject,
	payload: Dictionary = {},
	lock_source: StringName = &""
) -> void:
	if _inspector_selection == null or _inspector_panel == null:
		return
	if lock_source != &"":
		_inspector_subject_locked_by = lock_source
	_inspector_selection.project = _inspector_project()
	var view_state: Dictionary = _inspector_selection.apply(subject, payload)
	_inspector_panel.apply_view_state(view_state)


func _on_browser_event_selection_for_inspector(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn != null and bn.kind == CodaBrowserNode.Kind.EVENT:
		_inspector_subject_locked_by = &"browser"
	call_deferred(&"_finish_browser_event_inspector", node)


func _finish_browser_event_inspector(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_inspector_subject_locked_by = &""
		_apply_inspector_selection(CodaInspectorSelection.Subject.EMPTY)
		return
	_apply_inspector_selection(
		CodaInspectorSelection.Subject.BROWSER_EVENT, {"node": bn}, &"browser"
	)


func _apply_timeline_inspector_subselection(event_id: String) -> void:
	if _timeline_panel == null or event_id.is_empty():
		return
	var clip_id: String = _timeline_panel.get_selected_clip_id()
	if not clip_id.is_empty():
		_apply_inspector_selection(
			CodaInspectorSelection.Subject.TIMELINE_CLIP,
			{
				"event_id": event_id,
				"clip_id": clip_id,
				"track_id": _timeline_panel.get_selected_track_id(),
			},
			&"timeline"
		)
		return
	var track_id: String = _timeline_panel.get_selected_track_id()
	if not track_id.is_empty():
		_apply_inspector_selection(
			CodaInspectorSelection.Subject.TIMELINE_TRACK,
			{"event_id": event_id, "track_id": track_id},
			&"timeline"
		)


func _on_browser_asset_selection_for_inspector(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null:
		_inspector_subject_locked_by = &""
		_apply_inspector_selection(CodaInspectorSelection.Subject.EMPTY)
		return
	_inspector_subject_locked_by = &"browser"
	_apply_inspector_selection(CodaInspectorSelection.Subject.BROWSER_ASSET, {"node": bn})


func _fallback_timeline_inspector(event_id: String) -> void:
	if _inspector_subject_locked_by == &"browser":
		if _browser_panel != null and _browser_panel.has_method(&"get_project"):
			var st: CodaState = _browser_panel.get_project() as CodaState
			if st != null and not event_id.is_empty():
				var ev: CodaBrowserNode = st.events_root.find_by_id(event_id)
				if ev != null:
					_apply_inspector_selection(
						CodaInspectorSelection.Subject.BROWSER_EVENT, {"node": ev}
					)
					return
		_apply_inspector_selection(CodaInspectorSelection.Subject.EMPTY)
		return
	if _timeline_panel != null:
		var track_id: String = _timeline_panel.get_selected_track_id()
		if not track_id.is_empty() and not event_id.is_empty():
			_apply_inspector_selection(
				CodaInspectorSelection.Subject.TIMELINE_TRACK,
				{"event_id": event_id, "track_id": track_id},
				&"timeline"
			)
			return
	_apply_inspector_selection(CodaInspectorSelection.Subject.EMPTY)


func _on_timeline_track_selection_for_inspector(event_id: String, track_id: String) -> void:
	if track_id.is_empty():
		_fallback_timeline_inspector(event_id)
		return
	_apply_inspector_selection(
		CodaInspectorSelection.Subject.TIMELINE_TRACK,
		{"event_id": event_id, "track_id": track_id},
		&"timeline"
	)


func _on_timeline_clip_selection_for_inspector(event_id: String, clip_id: String) -> void:
	if clip_id.is_empty():
		_fallback_timeline_inspector(event_id)
		return
	var track_id: String = ""
	if _timeline_panel != null:
		track_id = _timeline_panel.get_selected_track_id()
	_apply_inspector_selection(
		CodaInspectorSelection.Subject.TIMELINE_CLIP,
		{"event_id": event_id, "clip_id": clip_id, "track_id": track_id},
		&"timeline"
	)


func _on_mixer_bus_selection_for_inspector(bus_id: String) -> void:
	if bus_id.is_empty():
		_apply_inspector_selection(CodaInspectorSelection.Subject.EMPTY)
		return
	_apply_inspector_selection(
		CodaInspectorSelection.Subject.MIXER_BUS, {"bus_id": bus_id}, &"mixer"
	)


func _on_track_effects_focus_requested(_track_id: String) -> void:
	if _dock_host == null or _dock_host.dock_manager == null:
		return
	var dm: CodaDockManager = _dock_host.dock_manager
	dm.show_panel(PANEL_INSPECTOR)
	if _inspector_panel != null and _inspector_panel.has_method(&"scroll_to_track_effects"):
		_inspector_panel.scroll_to_track_effects()


func _on_browser_external_selection_requested(
	target_panel_id: StringName, kind: StringName, payload: Variant
) -> void:
	if _selection_router != null:
		_selection_router.route(target_panel_id, kind, payload)


func _wire_browser_authoring_signals() -> void:
	if _events_tab_from_browser() == null:
		return
	var events_tab: CodaEventsTab = _events_tab_from_browser()
	if not events_tab.event_authoring_open_requested.is_connected(_on_event_authoring_open_requested):
		events_tab.event_authoring_open_requested.connect(_on_event_authoring_open_requested)
	if not events_tab.event_open_graph_requested.is_connected(_on_event_open_graph_requested):
		events_tab.event_open_graph_requested.connect(_on_event_open_graph_requested)
	if not events_tab.event_open_timeline_requested.is_connected(_on_event_open_timeline_requested):
		events_tab.event_open_timeline_requested.connect(_on_event_open_timeline_requested)


func _events_tab_from_browser() -> CodaEventsTab:
	if _browser_panel == null or not _browser_panel.has_method(&"get_events_tab"):
		return null
	return _browser_panel.get_events_tab() as CodaEventsTab


func _on_event_authoring_open_requested(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or _authoring_focus == null:
		return
	_authoring_focus.focus_for_event(bn)


func _on_event_open_graph_requested(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or _authoring_focus == null:
		return
	_authoring_focus.open_graph_for_event(bn)


func _on_event_open_timeline_requested(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or _authoring_focus == null:
		return
	_authoring_focus.open_timeline_for_event(bn)


func _on_inspector_authoring_mode_changed(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or _authoring_focus == null:
		return
	_authoring_focus.focus_for_event(bn)


func _focus_panel(panel_id: StringName) -> void:
	if _dock_host == null or _dock_host.dock_manager == null:
		return
	_dock_host.dock_manager.show_panel(panel_id)
	_focused_panel_id = panel_id
	if _status_bar != null and _status_bar.has_method(&"set_panel_hint"):
		_status_bar.set_panel_hint(panel_id)


func _wire_runtime_to_panels() -> void:
	var rt: CodaRuntime = _preview_controller.ensure_runtime()
	if rt == null:
		return
	if _graph_panel != null:
		_graph_panel.attach_runtime(rt)
	if _player_panel != null:
		_player_panel.attach_runtime(rt)
		if _player_panel.has_signal(&"playhead_changed") and _editor_transport != null:
			_playhead_sync_slot = Callable(_editor_transport, &"sync_playhead_seconds")
			if not _player_panel.playhead_changed.is_connected(_playhead_sync_slot):
				_player_panel.playhead_changed.connect(_playhead_sync_slot)
	if _timeline_panel != null and _timeline_panel.has_method(&"attach_runtime"):
		_timeline_panel.attach_runtime(rt)
	if _mixer_panel != null:
		_mixer_panel.attach_runtime(rt)
		_mixer_panel.attach_bus_layout_export(
			Callable(self, &"pick_audio_bus_layout_export_path_async"),
			Callable(self, &"complete_audio_bus_layout_export")
		)
	_preview_controller.wire_pool_exhausted_signal()


func _on_runtime_voice_pool_exhausted(_context: Dictionary) -> void:
	pass


func _ensure_editor_runtime() -> void:
	_preview_controller.ensure_runtime()


func _dispose_editor_runtime() -> void:
	_preview_controller.dispose_runtime()


func on_gameplay_play_started() -> void:
	_preview_controller.on_gameplay_play_started()


func on_gameplay_play_stopped() -> void:
	_push_project_to_runtime(_current_state())


func _unwire_runtime_from_panels() -> void:
	if (
		_player_panel != null
		and is_instance_valid(_player_panel)
		and _playhead_sync_slot.is_valid()
		and _player_panel.playhead_changed.is_connected(_playhead_sync_slot)
	):
		_player_panel.playhead_changed.disconnect(_playhead_sync_slot)
	_playhead_sync_slot = Callable()
	_preview_controller.stop_panel_previews()
	_preview_controller.stop_runtime_voices()
	if _project_session != null:
		_project_session.bind_project_signals(null)


func _push_project_to_runtime(state: Variant) -> void:
	if state == null:
		return
	_preview_controller.push_project(state)


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
	_help_menu.add_item("Command Palette...", HID_COMMAND_PALETTE)
	_help_menu.add_item("Keyboard Shortcuts...", HID_SHORTCUTS)
	_file_menu.id_pressed.connect(_on_file_id_pressed)
	_view_menu.id_pressed.connect(_on_view_id_pressed)
	_view_menu.about_to_popup.connect(_refresh_view_menu_check_marks)
	_build_menu.id_pressed.connect(_on_build_id_pressed)
	_build_menu.about_to_popup.connect(_on_build_menu_about_to_popup)
	_help_menu.id_pressed.connect(_on_help_id_pressed)
	_help_menu.about_to_popup.connect(_on_help_menu_about_to_popup)
	_recent_menu.id_pressed.connect(_on_recent_id_pressed)
	_recent_menu.about_to_popup.connect(_on_recent_menu_about_to_popup)


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


func _on_build_id_pressed(id: int) -> void:
	if _menu_actions != null:
		await _menu_actions.on_build_id_pressed(id)


func pick_audio_bus_layout_export_path_async() -> String:
	if _menu_actions != null:
		return await _menu_actions.pick_audio_bus_layout_export_path_async()
	return ""


func complete_audio_bus_layout_export(saved_path: String, err: Error) -> void:
	if _menu_actions != null:
		_menu_actions.complete_audio_bus_layout_export(saved_path, err)


func _on_help_id_pressed(id: int) -> void:
	if _menu_actions != null:
		await _menu_actions.on_help_id_pressed(id)


func _apply_theme_appearance(theme_mode: String, accent: Color) -> void:
	if _menu_actions != null:
		_menu_actions.apply_theme_appearance(theme_mode, accent)
	_apply_root_theme(_menu_actions.get_project_theme() if _menu_actions != null else null)


func _open_command_palette() -> void:
	if _command_palette == null:
		return
	if _menu_actions != null:
		_command_palette.set_entries(_menu_actions.collect_palette_entries())
	_command_palette.open()


func _open_shortcut_sheet() -> void:
	if _shortcut_sheet == null:
		return
	_shortcut_sheet.open()


func _select_event_by_id(event_id: String) -> void:
	if _browser_panel == null:
		return
	if _browser_panel.has_method(&"select_event_by_id"):
		_browser_panel.select_event_by_id(event_id)
	elif _browser_panel.has_method(&"focus_event"):
		_browser_panel.focus_event(event_id)
	else:
		NexusCodaLog.info("palette", "Event id=%s - open the Browser to select it." % event_id)


func _on_view_id_pressed(id: int) -> void:
	if _dock_host == null or _dock_host.dock_manager == null:
		return
	var dm: CodaDockManager = _dock_host.dock_manager
	match id:
		VID_SAVE_LAYOUT:
			if _layout_persistence != null:
				_layout_persistence.save_custom_layout()
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
			if _layout_persistence != null:
				_layout_persistence.load_custom_layout()
		VID_CLEAR_SAVED_LAYOUT:
			if _layout_persistence != null:
				_layout_persistence.clear_custom_layout()
		VID_RESET_LAYOUT:
			if _layout_persistence != null:
				_layout_persistence.reset_to_factory_layout()
		_:
			pass
	_refresh_view_menu_check_marks()


func _on_layout_changed() -> void:
	if _layout_persistence != null:
		_layout_persistence.on_layout_changed()


func _deferred_layout_autosave() -> void:
	if _layout_persistence != null:
		_layout_persistence.run_deferred_autosave()


func _on_panel_visibility_changed(_panel_id: StringName, _is_visible: bool) -> void:
	_refresh_view_menu_check_marks()


func _on_file_id_pressed(id: int) -> void:
	match id:
		MID_NEW:
			await _session_new_async()
		MID_OPEN:
			await _session_open_async()
		MID_CLOSE:
			await _session_close_async()
		MID_SAVE:
			await _session_save_async()
		MID_SAVE_AS:
			await _session_save_as_async()
		_:
			pass


func _on_recent_id_pressed(id: int) -> void:
	if _project_session == null:
		return
	var path: String = _project_session.recent_path_for_menu_id(id)
	if path.is_empty():
		return
	await _project_session.open_path_after_confirm_async(path)


func _editor_notify(message: String, is_error: bool = false) -> void:
	if is_error:
		NexusCodaLog.error("project_io", message)
		OS.alert(message, "Nexus Coda")
	else:
		NexusCodaLog.info("project_io", message)


func _refresh_editor_filesystem_after_save(path: String) -> void:
	if _plugin == null:
		return
	var fs: EditorFileSystem = _plugin.get_editor_interface().get_resource_filesystem()
	if fs == null:
		return
	if path.begins_with("res://"):
		if fs.has_method(&"update_file"):
			fs.update_file(path)
		var ext: String = path.get_extension().to_lower()
		if ext != "tres" and ext != "res" and fs.has_method(&"reimport_files"):
			fs.reimport_files(PackedStringArray([path]))
	elif fs.has_method(&"scan"):
		fs.call_deferred(&"scan")


func _on_close_requested() -> void:
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
	if _project_session != null:
		_project_session.autosave_if_dirty()
	_teardown_done = true

	_unwire_runtime_from_panels()

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
	if _menu_actions != null:
		_menu_actions.teardown()
	_menu_actions = null

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
	_dispose_editor_runtime()
