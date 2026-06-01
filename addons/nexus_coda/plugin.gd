@tool
extends EditorPlugin

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const EDITOR_WINDOW_SCENE := preload("res://addons/nexus_coda/editor/nexus_coda_editor_window.tscn")
const EDITOR_WINDOW_SCRIPT := preload("res://addons/nexus_coda/editor/nexus_coda_editor_window.gd")
const NCODA_IMPORT_PLUGIN := preload("res://addons/nexus_coda/editor/import/nexus_coda_ncoda_import_plugin.gd")
const CodaFilesystemContextMenuScript := preload(
	"res://addons/nexus_coda/editor/coda_filesystem_context_menu_plugin.gd"
)
const CodaAudioBusSyncGateScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd"
)

const TOOLS_SUBMENU_NAME := "Nexus Coda"
const MENU_OPEN_EDITOR := 0

const AUTOLOAD_NAME := "Coda"
const AUTOLOAD_PATH := "res://addons/nexus_coda/runtime/coda_runtime.gd"
const AUTOLOAD_MUSIC_NAME := "CodaMusic"
const AUTOLOAD_MUSIC_PATH := "res://addons/nexus_coda/runtime/coda_music_director.gd"
const AUTOLOAD_BRIDGE_NAME := "CodaGameBridge"
const AUTOLOAD_BRIDGE_PATH := "res://addons/nexus_coda/runtime/coda_game_bridge.gd"
const LOGGER_AUTOLOAD_NAME := "CodaLogger"
const LOGGER_AUTOLOAD_PATH := "res://addons/nexus_coda/editor/coda_logger.tscn"

const CodaLoggerScript := preload("res://addons/nexus_coda/editor/coda_logger.gd")

const EXIT_LEAK_TEST_ENV := "NEXUS_CODA_EXIT_LEAK_TEST"
const EXIT_LEAK_TEST_INTERACTIVE_ENV := "NEXUS_CODA_EXIT_LEAK_TEST_INTERACTIVE"
const EXIT_LEAK_TEST_USE_AUTOSAVE_ENV := "NEXUS_CODA_EXIT_LEAK_TEST_USE_AUTOSAVE"
const EXIT_LEAK_TEST_EDITOR_WARMUP_SEC := 3.0
const EXIT_LEAK_TEST_SESSION_POLL_SEC := 0.5
const EXIT_LEAK_TEST_SESSION_MAX_POLLS := 60
const EXIT_LEAK_TEST_INTERACTIVE_SEC := 2.0

var _tools_menu: PopupMenu
var _ncoda_import_plugin: EditorImportPlugin
var _filesystem_context_menu_plugin: EditorContextMenuPlugin
var _editor_windows: Array[Window] = []
var _gameplay_was_active: bool = false
var _editor_shutdown_prepared: bool = false
var _editor_shutdown_close_hooked: bool = false


func _save_external_data() -> void:
	_prepare_for_editor_shutdown()
	_free_coda_editor_windows_if_safe()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_prepare_for_editor_shutdown()
		_free_coda_editor_windows_if_safe()


func _enter_tree() -> void:
	_editor_shutdown_prepared = false
	_bind_editor_shutdown_hooks()
	_register_logger_project_settings()
	call_deferred(&"_log_plugin_ready")
	_ncoda_import_plugin = NCODA_IMPORT_PLUGIN.new() as EditorImportPlugin
	add_import_plugin(_ncoda_import_plugin)
	_filesystem_context_menu_plugin = CodaFilesystemContextMenuScript.new() as EditorContextMenuPlugin
	_filesystem_context_menu_plugin.attach_plugin(self)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _filesystem_context_menu_plugin)
	_tools_menu = PopupMenu.new()
	_tools_menu.name = "NexusCodaToolsMenu"
	_tools_menu.add_item("Open Editor", MENU_OPEN_EDITOR)
	_tools_menu.id_pressed.connect(_on_tools_menu_id_pressed)
	_register_tool_shortcuts()
	# add_tool_submenu_item requires an unparented PopupMenu.
	add_tool_submenu_item(TOOLS_SUBMENU_NAME, _tools_menu)
	set_process(true)
	if OS.get_environment(EXIT_LEAK_TEST_ENV) == "1":
		call_deferred(&"_schedule_exit_leak_test")


func _schedule_exit_leak_test() -> void:
	var timer := get_tree().create_timer(EXIT_LEAK_TEST_EDITOR_WARMUP_SEC)
	timer.timeout.connect(_run_exit_leak_test)


func _run_exit_leak_test() -> void:
	spawn_new_coda_editor_window()
	_exit_leak_session_polls = 0
	_poll_exit_leak_test_session_ready()


var _exit_leak_session_polls: int = 0


func _poll_exit_leak_test_session_ready() -> void:
	if _exit_leak_test_session_is_ready():
		_run_exit_leak_test_interactive_phase()
		return
	_exit_leak_session_polls += 1
	if _exit_leak_session_polls >= EXIT_LEAK_TEST_SESSION_MAX_POLLS:
		NexusCodaLog.warn(
			"plugin",
			"Exit leak test: session bind timeout; quitting anyway."
		)
		_run_exit_leak_test_interactive_phase()
		return
	var timer := get_tree().create_timer(EXIT_LEAK_TEST_SESSION_POLL_SEC)
	timer.timeout.connect(_poll_exit_leak_test_session_ready)


func _exit_leak_test_session_is_ready() -> bool:
	_prune_invalid_windows()
	if _editor_windows.is_empty():
		return false
	var w: Window = _editor_windows[_editor_windows.size() - 1]
	if not is_instance_valid(w):
		return false
	if w.has_method(&"is_exit_leak_test_session_ready"):
		return bool(w.call(&"is_exit_leak_test_session_ready"))
	return false


func _run_exit_leak_test_interactive_phase() -> void:
	if OS.get_environment(EXIT_LEAK_TEST_INTERACTIVE_ENV) == "1":
		_prune_invalid_windows()
		if not _editor_windows.is_empty():
			var w: Window = _editor_windows[_editor_windows.size() - 1]
			if w.has_method(&"run_exit_leak_smoke_edits"):
				w.call(&"run_exit_leak_smoke_edits")
		var timer := get_tree().create_timer(EXIT_LEAK_TEST_INTERACTIVE_SEC)
		timer.timeout.connect(_quit_editor_after_leak_test)
		return
	_quit_editor_after_leak_test()


func _quit_editor_after_leak_test() -> void:
	_prune_invalid_windows()
	NexusCodaLog.info(
		"plugin",
		"Exit leak test: quitting Godot with %d Coda window(s) still open (not closing Coda first)."
		% _editor_windows.size()
	)
	get_tree().quit()


func _enable_plugin() -> void:
	# Per Godot docs, autoloads should be managed in enable/disable (not enter/exit) so
	# editor startup/shutdown doesn't constantly rewrite project settings.
	if _needs_autoload_register_named(LOGGER_AUTOLOAD_NAME, LOGGER_AUTOLOAD_PATH):
		add_autoload_singleton(LOGGER_AUTOLOAD_NAME, LOGGER_AUTOLOAD_PATH)
	# Only touch the settings when the entry is missing or stale.
	if _needs_autoload_register():
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	if _needs_autoload_register_named(AUTOLOAD_MUSIC_NAME, AUTOLOAD_MUSIC_PATH):
		add_autoload_singleton(AUTOLOAD_MUSIC_NAME, AUTOLOAD_MUSIC_PATH)
	if _needs_autoload_register_named(AUTOLOAD_BRIDGE_NAME, AUTOLOAD_BRIDGE_PATH):
		add_autoload_singleton(AUTOLOAD_BRIDGE_NAME, AUTOLOAD_BRIDGE_PATH)


func _disable_plugin() -> void:
	_free_autoload_instances()
	_remove_autoload_entries()


func _log_plugin_ready() -> void:
	NexusCodaLog.print_ready_banner()


func _process(_delta: float) -> void:
	var playing: bool = get_editor_interface().is_playing_scene()
	if playing == _gameplay_was_active:
		return
	_gameplay_was_active = playing
	CodaAudioBusSyncGateScript.set_gameplay_active(playing)
	if playing:
		_on_editor_play_started()
	else:
		_on_editor_play_stopped()


func _on_editor_play_started() -> void:
	_prune_invalid_windows()
	for w in _editor_windows:
		if is_instance_valid(w) and w.has_method(&"on_gameplay_play_started"):
			w.call(&"on_gameplay_play_started")


func _on_editor_play_stopped() -> void:
	_prune_invalid_windows()
	for w in _editor_windows:
		if is_instance_valid(w) and w.has_method(&"on_gameplay_play_stopped"):
			w.call(&"on_gameplay_play_stopped")


func _bind_editor_shutdown_hooks() -> void:
	if _editor_shutdown_close_hooked:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var root: Node = tree.root
	if root is Window:
		var win: Window = root as Window
		if not win.close_requested.is_connected(_on_editor_close_requested):
			win.close_requested.connect(_on_editor_close_requested)
		_editor_shutdown_close_hooked = true


func _unbind_editor_shutdown_hooks() -> void:
	if not _editor_shutdown_close_hooked:
		return
	var tree: SceneTree = get_tree()
	if tree != null:
		var root: Node = tree.root
		if root is Window:
			var win: Window = root as Window
			if win.close_requested.is_connected(_on_editor_close_requested):
				win.close_requested.disconnect(_on_editor_close_requested)
	_editor_shutdown_close_hooked = false


func _on_editor_close_requested() -> void:
	# Fires when the editor main window is closing; runs before plugin _exit_tree / ObjectDB checks.
	_prepare_for_editor_shutdown()
	_free_coda_editor_windows_if_safe()


func _prepare_for_editor_shutdown() -> void:
	if _editor_shutdown_prepared:
		return
	_editor_shutdown_prepared = true
	_prune_invalid_windows()
	for w in _editor_windows:
		if is_instance_valid(w) and w.has_method(&"_teardown_before_close"):
			w.call(&"_teardown_before_close")
	_halt_autoload_instances()


func _free_coda_editor_windows_if_safe() -> void:
	# Only while the plugin/editor tree is still stable (not during _exit_tree).
	if not is_inside_tree():
		return
	_prune_invalid_windows()
	var to_free: Array[Window] = []
	for w in _editor_windows:
		if is_instance_valid(w):
			to_free.append(w)
	_editor_windows.clear()
	for w in to_free:
		w.hide()
		if is_instance_valid(w):
			w.free()


func _exit_tree() -> void:
	set_process(false)
	CodaAudioBusSyncGateScript.set_gameplay_active(false)
	CodaAudioBusSyncGateScript.reset_for_tests()
	_prepare_for_editor_shutdown()
	_unbind_editor_shutdown_hooks()
	if _filesystem_context_menu_plugin != null:
		remove_context_menu_plugin(_filesystem_context_menu_plugin)
		# EditorContextMenuPlugin is RefCounted; do not call free().
		_filesystem_context_menu_plugin = null
	if _ncoda_import_plugin != null:
		remove_import_plugin(_ncoda_import_plugin)
		# EditorImportPlugin is RefCounted; do not call free().
		_ncoda_import_plugin = null
	_editor_windows.clear()
	if _tools_menu != null:
		if _tools_menu.id_pressed.is_connected(_on_tools_menu_id_pressed):
			_tools_menu.id_pressed.disconnect(_on_tools_menu_id_pressed)
	remove_tool_menu_item(TOOLS_SUBMENU_NAME)
	if _tools_menu != null and is_instance_valid(_tools_menu):
		_tools_menu.free()
		_tools_menu = null


func _remove_autoload_entries() -> void:
	# To avoid "Resource still in use" warnings on editor shutdown, remove the autoload
	# entries as well (ProjectSettings keeps strong references to the script resources).
	#
	# Note: This will dirty project.godot while the editor is closing. On next startup,
	# _enter_tree() will re-add the entries.
	_remove_autoload_entry(LOGGER_AUTOLOAD_NAME)
	_remove_autoload_entry(AUTOLOAD_BRIDGE_NAME)
	_remove_autoload_entry(AUTOLOAD_MUSIC_NAME)
	_remove_autoload_entry(AUTOLOAD_NAME)


func _remove_autoload_entry(name: String) -> void:
	if name.is_empty():
		return
	var key: String = "autoload/%s" % name
	if not ProjectSettings.has_setting(key):
		return
	remove_autoload_singleton(name)

func _free_autoload_instances() -> void:
	_free_autoload_instance(LOGGER_AUTOLOAD_NAME)
	_free_autoload_instance(AUTOLOAD_BRIDGE_NAME)
	_free_autoload_instance(AUTOLOAD_MUSIC_NAME)
	_free_autoload_instance(AUTOLOAD_NAME)


func _halt_autoload_instances() -> void:
	# Editor shutdown: stop work and drop project refs, but do not free()/remove /root
	# children while the tree is tearing down (causes remove_child / add_child errors).
	_halt_autoload_instance(LOGGER_AUTOLOAD_NAME)
	_halt_autoload_instance(AUTOLOAD_BRIDGE_NAME)
	_halt_autoload_instance(AUTOLOAD_MUSIC_NAME)
	_halt_autoload_instance(AUTOLOAD_NAME)


func _halt_autoload_instance(name: String) -> void:
	if name.is_empty():
		return
	var n: Node = get_node_or_null("/root/" + name)
	if n == null or not is_instance_valid(n):
		return
	if n.has_method(&"stop_all"):
		n.call(&"stop_all")
	if n.has_method(&"disconnect_game_signals"):
		n.call(&"disconnect_game_signals")
	if n.has_method(&"set_project"):
		n.call(&"set_project", null)


func _free_autoload_instance(name: String) -> void:
	if name.is_empty():
		return
	var n: Node = get_node_or_null("/root/" + name)
	if n == null or not is_instance_valid(n):
		return
	if n.has_method(&"stop_all"):
		n.call(&"stop_all")
	if n.has_method(&"disconnect_game_signals"):
		n.call(&"disconnect_game_signals")
	# `queue_free()` can be skipped during editor shutdown; free immediately so addon scripts
	# don't stay referenced after the plugin is unloaded.
	n.free()


func _register_logger_project_settings() -> void:
	const PREFIX := "nexus/coda/logger/"
	if not ProjectSettings.has_setting(PREFIX + "categories_enabled"):
		ProjectSettings.set_setting(
			PREFIX + "categories_enabled",
			CodaLoggerScript.get_default_categories_enabled_dict()
		)
	else:
		var ce: Variant = ProjectSettings.get_setting(PREFIX + "categories_enabled")
		if ce is Dictionary and (ce as Dictionary).is_empty():
			ProjectSettings.set_setting(
				PREFIX + "categories_enabled",
				CodaLoggerScript.get_default_categories_enabled_dict()
			)
	ProjectSettings.set_initial_value(
		PREFIX + "categories_enabled",
		CodaLoggerScript.get_default_categories_enabled_dict()
	)
	ProjectSettings.add_property_info({
		"name": PREFIX + "categories_enabled",
		"type": TYPE_DICTIONARY,
	})
	if not ProjectSettings.has_setting(PREFIX + "minimum_level"):
		ProjectSettings.set_setting(PREFIX + "minimum_level", CodaLoggerScript.Level.DEBUG)
	ProjectSettings.set_initial_value(PREFIX + "minimum_level", CodaLoggerScript.Level.DEBUG)
	ProjectSettings.add_property_info({
		"name": PREFIX + "minimum_level",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Debug,Info,Warn,Error",
	})
	if not ProjectSettings.has_setting(PREFIX + "output_to_debug"):
		ProjectSettings.set_setting(PREFIX + "output_to_debug", true)
	ProjectSettings.set_initial_value(PREFIX + "output_to_debug", true)
	ProjectSettings.add_property_info({
		"name": PREFIX + "output_to_debug",
		"type": TYPE_BOOL,
	})
	if not ProjectSettings.has_setting(PREFIX + "output_to_file"):
		ProjectSettings.set_setting(PREFIX + "output_to_file", false)
	ProjectSettings.set_initial_value(PREFIX + "output_to_file", false)
	ProjectSettings.add_property_info({
		"name": PREFIX + "output_to_file",
		"type": TYPE_BOOL,
	})
	if not ProjectSettings.has_setting(PREFIX + "file_path"):
		ProjectSettings.set_setting(PREFIX + "file_path", CodaLoggerScript.DEFAULT_FILE_PATH)
	ProjectSettings.set_initial_value(PREFIX + "file_path", CodaLoggerScript.DEFAULT_FILE_PATH)
	ProjectSettings.add_property_info({
		"name": PREFIX + "file_path",
		"type": TYPE_STRING,
	})


func get_editor_runtime() -> CodaRuntime:
	return null


func _needs_autoload_register() -> bool:
	return _needs_autoload_register_named(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _needs_autoload_register_named(autoload_name: String, autoload_path: String) -> bool:
	var setting: String = "autoload/%s" % autoload_name
	if not ProjectSettings.has_setting(setting):
		return true
	var current: String = String(ProjectSettings.get_setting(setting, ""))
	if current.is_empty():
		return true
	if current == "*" + autoload_path:
		return false
	if current.begins_with("*uid://"):
		var uid_text: String = current.substr(1)
		var uid_id: int = ResourceUID.text_to_id(uid_text)
		if uid_id != -1 and ResourceUID.has_id(uid_id):
			if ResourceUID.get_id_path(uid_id) == autoload_path:
				return false
		# UID cache may not be ready yet; skip re-register to avoid dirtying project.godot.
		return false
	return true


func send_fs_selection_to_coda_assets(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	_open_or_focus_editor_window()
	call_deferred(&"_import_fs_paths_when_editor_ready", paths)


func _import_fs_paths_when_editor_ready(paths: PackedStringArray) -> void:
	call_deferred(&"_import_fs_paths_into_assets", paths)


func _import_fs_paths_into_assets(paths: PackedStringArray) -> void:
	_prune_invalid_windows()
	if _editor_windows.is_empty():
		return
	var w: Window = _editor_windows[_editor_windows.size() - 1]
	if w.has_method(&"import_fs_paths_into_assets"):
		w.call(&"import_fs_paths_into_assets", paths)


func _register_tool_shortcuts() -> void:
	var sc := Shortcut.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_Y
	ev.ctrl_pressed = true
	ev.shift_pressed = true
	ev.command_or_control_autoremap = true
	sc.events = [ev]
	_tools_menu.set_item_shortcut(MENU_OPEN_EDITOR, sc, true)


func _prune_invalid_windows() -> void:
	var alive: Array[Window] = []
	for w in _editor_windows:
		if is_instance_valid(w):
			alive.append(w)
	_editor_windows = alive


func _on_tools_menu_id_pressed(id: int) -> void:
	if id != MENU_OPEN_EDITOR:
		return
	_open_or_focus_editor_window()


func spawn_new_coda_editor_window() -> void:
	_prune_invalid_windows()
	var w: Window = _create_editor_window()
	if w.has_method(&"set_restore_autosave_on_start"):
		var restore_autosave: bool = OS.get_environment(EXIT_LEAK_TEST_USE_AUTOSAVE_ENV) == "1"
		w.set_restore_autosave_on_start(restore_autosave)
	_attach_window_to_editor_host(w)
	_editor_windows.append(w)
	_show_window_on_editor(w)


func _create_editor_window() -> Window:
	var w: Window = EDITOR_WINDOW_SCENE.instantiate() as Window
	w.set_script(EDITOR_WINDOW_SCRIPT)
	if w.has_method(&"setup_editor_plugin"):
		w.setup_editor_plugin(self)
	w.visible = false
	w.force_native = true
	w.maximize_disabled = false
	w.minimize_disabled = false
	w.tree_exited.connect(_prune_invalid_windows)
	return w


func _show_window_on_editor(w: Window) -> void:
	var base: Control = get_editor_interface().get_base_control()
	var host_window: Window = base.get_window()
	if host_window != null:
		w.current_screen = host_window.current_screen
	w.popup_centered_ratio(0.6)


func _attach_window_to_editor_host(w: Window) -> void:
	var base: Control = get_editor_interface().get_base_control()
	var host: Window = base.get_window()
	if host != null:
		host.add_child(w)
	else:
		base.add_child(w)


func _open_or_focus_editor_window() -> void:
	_prune_invalid_windows()
	var base: Control = get_editor_interface().get_base_control()
	if _editor_windows.is_empty():
		var w: Window = _create_editor_window()
		_attach_window_to_editor_host(w)
		_editor_windows.append(w)
		_show_window_on_editor(w)
		return
	var last: Window = _editor_windows[_editor_windows.size() - 1]
	if not last.visible:
		var host_window: Window = base.get_window()
		if host_window != null:
			last.current_screen = host_window.current_screen
		last.show()
	last.grab_focus()
