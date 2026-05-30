@tool
class_name CodaEditorProjectSession
extends RefCounted

## Project I/O, dirty state, recent paths, and panel binding for the editor window.

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaProjectIo := preload("res://addons/nexus_coda/editor/coda_project_io.gd")
const CodaProjectAutosave := preload("res://addons/nexus_coda/editor/io/coda_project_autosave.gd")
const CodaInspectorSelectionScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_inspector_selection.gd"
)

const RECENT_ID_BASE := 1000

var plugin: EditorPlugin = null
var file_dialogs: CodaEditorFileDialogs = null

var browser_panel: Control = null
var graph_panel: CodaEventGraphPanel = null
var inspector_panel: CodaInspectorPanel = null
var player_panel: CodaPlayerPanel = null
var timeline_panel: CodaTimelinePanel = null
var mixer_panel: CodaMixerPanel = null
var inspector_selection: CodaInspectorSelection = null

var on_apply_theme: Callable = Callable()
var on_push_runtime: Callable = Callable()
var on_apply_inspector: Callable = Callable()
var on_update_title: Callable = Callable()
var on_notify: Callable = Callable()
var on_spawn_new_window: Callable = Callable()
var on_request_close: Callable = Callable()
var on_refresh_filesystem: Callable = Callable()

var current_path: String = ""
var dirty: bool = false

var _suppress_dirty: bool = false
var _project_signal_source: CodaState = null
var _recent_paths_snapshot: PackedStringArray = []


func get_state() -> CodaState:
	if browser_panel != null and browser_panel.has_method(&"get_project"):
		return browser_panel.get_project() as CodaState
	return null


func bind_project_signals(state: Variant) -> void:
	if _project_signal_source != null and is_instance_valid(_project_signal_source):
		if _project_signal_source.structure_changed.is_connected(_on_structure_changed):
			_project_signal_source.structure_changed.disconnect(_on_structure_changed)
		if _project_signal_source.structure_changed.is_connected(_refresh_inspector_for_subject):
			_project_signal_source.structure_changed.disconnect(_refresh_inspector_for_subject)
		if _project_signal_source.project_dirty.is_connected(_on_structure_changed):
			_project_signal_source.project_dirty.disconnect(_on_structure_changed)
	_project_signal_source = null
	if state == null:
		return
	var st: CodaState = state as CodaState
	if st == null:
		return
	_project_signal_source = st
	st.structure_changed.connect(_on_structure_changed)
	st.structure_changed.connect(_refresh_inspector_for_subject)
	st.project_dirty.connect(_on_structure_changed)


func initial_bind(restore_autosave: bool = true) -> void:
	if restore_autosave and try_restore_from_autosave():
		return
	_suppress_dirty = true
	if browser_panel != null and browser_panel.has_method(&"get_project"):
		var st: Variant = browser_panel.get_project()
		bind_project_signals(st)
		if on_push_runtime.is_valid():
			on_push_runtime.call(st)
		if graph_panel != null and st is CodaState:
			graph_panel.attach_project(st as CodaState)
		if inspector_panel != null and st is CodaState:
			inspector_panel.attach_project(st as CodaState)
		if mixer_panel != null and st is CodaState:
			mixer_panel.attach_project(st as CodaState)
		if player_panel != null and st is CodaState:
			player_panel.attach_project(st as CodaState)
		if timeline_panel != null and st is CodaState:
			timeline_panel.attach_project(st as CodaState)
	if browser_panel != null and browser_panel.has_method(&"pulse_active_tab_selection_to_editor"):
		browser_panel.pulse_active_tab_selection_to_editor()
	dirty = false
	_suppress_dirty = false
	emit_title_update()
	var st0: CodaState = get_state()
	if st0 != null and on_apply_theme.is_valid():
		on_apply_theme.call(st0.theme_mode, st0.accent_color)


func load_empty_project() -> void:
	_suppress_dirty = true
	var st: CodaState = CodaStateScript.new()
	st.clear_to_empty_project()
	apply_state_to_panels(st)
	_suppress_dirty = false


func apply_loaded_state(st: CodaState) -> void:
	_suppress_dirty = true
	apply_state_to_panels(st)
	_suppress_dirty = false


func apply_state_to_panels(st: CodaState) -> void:
	if browser_panel != null and browser_panel.has_method(&"set_project"):
		browser_panel.set_project(st)
	bind_project_signals(st)
	if on_push_runtime.is_valid():
		on_push_runtime.call(st)
	if graph_panel != null:
		graph_panel.attach_project(st)
		graph_panel.on_browser_event_selected(null)
	if inspector_panel != null:
		inspector_panel.attach_project(st)
		if inspector_selection != null:
			inspector_selection.project = st
		if on_apply_inspector.is_valid():
			on_apply_inspector.call(CodaInspectorSelectionScript.Subject.EMPTY, {}, &"")
	if player_panel != null:
		player_panel.attach_project(st)
		player_panel.on_browser_event_selected(null)
	if timeline_panel != null:
		timeline_panel.attach_project(st)
		timeline_panel.on_browser_event_selected(null)
	if mixer_panel != null:
		mixer_panel.attach_project(st)
	if browser_panel != null and browser_panel.has_method(&"pulse_active_tab_selection_to_editor"):
		browser_panel.pulse_active_tab_selection_to_editor()
	if st != null and on_apply_theme.is_valid():
		on_apply_theme.call(st.theme_mode, st.accent_color)


func fill_recent_menu(recent_menu: PopupMenu) -> void:
	CodaProjectIo.prune_missing_recent_paths(plugin)
	recent_menu.clear()
	_recent_paths_snapshot = CodaProjectIo.read_recent_paths(plugin)
	if _recent_paths_snapshot.is_empty():
		recent_menu.add_item("(No recent projects)", RECENT_ID_BASE)
		recent_menu.set_item_disabled(recent_menu.item_count - 1, true)
		return
	for i in _recent_paths_snapshot.size():
		var label: String = _recent_paths_snapshot[i]
		if label.length() > 72:
			label = "…" + label.substr(label.length() - 71, 71)
		recent_menu.add_item(label, RECENT_ID_BASE + i)


func recent_path_for_menu_id(id: int) -> String:
	var idx: int = id - RECENT_ID_BASE
	if idx < 0 or idx >= _recent_paths_snapshot.size():
		return ""
	return _recent_paths_snapshot[idx]


func action_new_async() -> void:
	if on_spawn_new_window.is_valid():
		on_spawn_new_window.call()
		NexusCodaLog.info("project_io", "Opened new Nexus Coda editor instance")
	else:
		NexusCodaLog.warn("project_io", "Cannot spawn editor (plugin missing spawn_new_coda_editor_window)")


func action_close_window_async() -> bool:
	NexusCodaLog.info("project_io", "Closing Nexus Coda editor instance")
	if on_request_close.is_valid():
		on_request_close.call()
	return true


func action_open_async() -> void:
	autosave_for_navigation()
	var p: String = await file_dialogs.pick_project_file(false)
	if not p.is_empty():
		open_path_internal(p)


func open_path_after_confirm_async(path: String) -> void:
	autosave_for_navigation()
	open_path_internal(path)


func open_path_internal(path: String) -> void:
	var loaded: Variant = CodaProjectIo.load_state_from_path(path)
	if loaded is String:
		if str(loaded) == CodaProjectIo.ERR_FILE_MISSING:
			CodaProjectIo.remove_recent_path(plugin, path)
		_notify(str(loaded), true)
		return
	var st: CodaState = loaded as CodaState
	if st == null:
		NexusCodaLog.error("project_io", "Could not load project.")
		return
	apply_loaded_state(st)
	current_path = path
	dirty = false
	CodaProjectIo.remember_opened_path(plugin, path)
	emit_title_update()
	NexusCodaLog.info("project_io", 'Opened "%s"' % path)


func action_save_async() -> void:
	if current_path.is_empty():
		await action_save_as_async()
		return
	await save_to_current_path_async()


func action_save_as_async() -> void:
	var suggest := ""
	if not current_path.is_empty():
		suggest = current_path.get_file()
	var p: String = await file_dialogs.pick_project_file(true, suggest)
	if p.is_empty():
		NexusCodaLog.warn("project_io", "Save As cancelled: save dialog returned no path.")
		_notify(
			"Save cancelled — no file path was chosen. Use Save if the project already has a path.",
			true
		)
		return
	if p.get_extension().to_lower() != CodaProjectIo.FORMAT_EXTENSION:
		p = "%s.%s" % [p, CodaProjectIo.FORMAT_EXTENSION]
	var err_msg: String = write_and_finish_save(p)
	if not err_msg.is_empty():
		_notify(err_msg, true)


func save_to_current_path_async() -> void:
	var err_msg: String = write_and_finish_save(current_path)
	if not err_msg.is_empty():
		_notify(err_msg, true)


func write_and_finish_save(path: String) -> String:
	if browser_panel == null or not browser_panel.has_method(&"get_project"):
		return "No project state."
	var st: Variant = browser_panel.get_project()
	if st == null:
		return "No project state."
	var msg: String = CodaProjectIo.save_to_path(st as CodaState, path)
	if not msg.is_empty():
		return msg
	current_path = path
	dirty = false
	CodaProjectIo.remember_opened_path(plugin, path)
	CodaProjectAutosave.clear(plugin)
	emit_title_update()
	NexusCodaLog.info("project_io", 'Saved "%s"' % path)
	if on_refresh_filesystem.is_valid():
		on_refresh_filesystem.call(path)
	return ""


func autosave_if_dirty() -> void:
	if not dirty or plugin == null:
		return
	var st: CodaState = get_state()
	if st == null:
		return
	var err: String = CodaProjectAutosave.write(plugin, st, current_path)
	if err.is_empty():
		NexusCodaLog.info("project_io", "Autosaved session.")
	else:
		NexusCodaLog.warn("project_io", err)


func autosave_for_navigation() -> void:
	autosave_if_dirty()


func try_restore_from_autosave() -> bool:
	if plugin == null:
		return false
	var result: Dictionary = CodaProjectAutosave.resolve_restore_candidate(plugin)
	var kind: StringName = result.get("kind", CodaProjectAutosave.KIND_NONE)
	if kind == CodaProjectAutosave.KIND_NONE:
		return false
	var st: Variant = result.get("state")
	if st == null or not st is CodaState:
		return false
	apply_loaded_state(st as CodaState)
	current_path = str(result.get("source_path", "")).strip_edges()
	dirty = kind == CodaProjectAutosave.KIND_AUTOSAVE
	if not current_path.is_empty() and kind != CodaProjectAutosave.KIND_AUTOSAVE:
		CodaProjectIo.remember_opened_path(plugin, current_path)
	emit_title_update()
	var label: String = "autosave"
	if kind == CodaProjectAutosave.KIND_SOURCE:
		label = "saved file"
	elif kind == CodaProjectAutosave.KIND_RECENT:
		label = "recent project"
	NexusCodaLog.info("project_io", "Restored session from %s." % label)
	return true


func _on_structure_changed() -> void:
	if _suppress_dirty:
		return
	dirty = true
	emit_title_update()


func _refresh_inspector_for_subject() -> void:
	if _suppress_dirty or inspector_selection == null or not on_apply_inspector.is_valid():
		return
	match inspector_selection.subject:
		CodaInspectorSelectionScript.Subject.BROWSER_EVENT:
			if inspector_selection.browser_node != null:
				on_apply_inspector.call(
					CodaInspectorSelectionScript.Subject.BROWSER_EVENT,
					{"node": inspector_selection.browser_node},
					&""
				)
		CodaInspectorSelectionScript.Subject.BROWSER_ASSET:
			if inspector_selection.browser_node != null:
				on_apply_inspector.call(
					CodaInspectorSelectionScript.Subject.BROWSER_ASSET,
					{"node": inspector_selection.browser_node},
					&""
				)
		CodaInspectorSelectionScript.Subject.TIMELINE_TRACK:
			if not inspector_selection.track_id.is_empty():
				on_apply_inspector.call(
					CodaInspectorSelectionScript.Subject.TIMELINE_TRACK,
					{
						"event_id": inspector_selection.event_id,
						"track_id": inspector_selection.track_id,
					},
					&"timeline"
				)
		CodaInspectorSelectionScript.Subject.TIMELINE_CLIP:
			if not inspector_selection.clip_id.is_empty():
				on_apply_inspector.call(
					CodaInspectorSelectionScript.Subject.TIMELINE_CLIP,
					{
						"event_id": inspector_selection.event_id,
						"clip_id": inspector_selection.clip_id,
						"track_id": inspector_selection.track_id,
					},
					&"timeline"
				)
		CodaInspectorSelectionScript.Subject.MIXER_BUS:
			if not inspector_selection.bus_id.is_empty():
				on_apply_inspector.call(
					CodaInspectorSelectionScript.Subject.MIXER_BUS,
					{"bus_id": inspector_selection.bus_id},
					&"mixer"
				)
		CodaInspectorSelectionScript.Subject.BROWSER_BANK:
			if not inspector_selection.bank_id.is_empty():
				on_apply_inspector.call(
					CodaInspectorSelectionScript.Subject.BROWSER_BANK,
					{"bank_id": inspector_selection.bank_id},
					&""
				)
		CodaInspectorSelectionScript.Subject.BROWSER_GAME_SYNC:
			if not inspector_selection.game_sync_payload.is_empty():
				on_apply_inspector.call(
					CodaInspectorSelectionScript.Subject.BROWSER_GAME_SYNC,
					{"payload": inspector_selection.game_sync_payload},
					&""
				)


func emit_title_update() -> void:
	if on_update_title.is_valid():
		on_update_title.call(current_path, dirty)


func _notify(message: String, is_error: bool) -> void:
	if on_notify.is_valid():
		on_notify.call(message, is_error)
