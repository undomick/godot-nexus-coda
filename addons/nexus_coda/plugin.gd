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
## Menu item id (same as index for the single entry — matches Nexus Resonance tool menu pattern).
const MENU_OPEN_EDITOR := 0

## Autoload registered for gameplay code: `Coda.play("events/foo")` etc.
const AUTOLOAD_NAME := "Coda"
const AUTOLOAD_PATH := "res://addons/nexus_coda/runtime/coda_runtime.gd"
const AUTOLOAD_MUSIC_NAME := "CodaMusic"
const AUTOLOAD_MUSIC_PATH := "res://addons/nexus_coda/runtime/coda_music_director.gd"
const AUTOLOAD_BRIDGE_NAME := "CodaGameBridge"
const AUTOLOAD_BRIDGE_PATH := "res://addons/nexus_coda/runtime/coda_game_bridge.gd"

var _tools_menu: PopupMenu
var _ncoda_import_plugin: EditorImportPlugin
var _filesystem_context_menu_plugin: EditorContextMenuPlugin
## All open Nexus Coda editor windows (multiple instances supported).
var _editor_windows: Array[Window] = []
var _gameplay_was_active: bool = false


func _enter_tree() -> void:
	NexusCodaLog.print_ready_banner()
	# Re-adding the same autoload rewrites project.godot on every restart, which makes the
	# editor flag the project as dirty even when nothing meaningful changed. Only touch the
	# settings when the entry is actually missing or stale.
	if _needs_autoload_register():
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	if _needs_autoload_register_named(AUTOLOAD_MUSIC_NAME, AUTOLOAD_MUSIC_PATH):
		add_autoload_singleton(AUTOLOAD_MUSIC_NAME, AUTOLOAD_MUSIC_PATH)
	if _needs_autoload_register_named(AUTOLOAD_BRIDGE_NAME, AUTOLOAD_BRIDGE_PATH):
		add_autoload_singleton(AUTOLOAD_BRIDGE_NAME, AUTOLOAD_BRIDGE_PATH)
	_ncoda_import_plugin = NCODA_IMPORT_PLUGIN.new() as EditorImportPlugin
	add_import_plugin(_ncoda_import_plugin)
	_filesystem_context_menu_plugin = CodaFilesystemContextMenuScript.new() as EditorContextMenuPlugin
	_filesystem_context_menu_plugin.attach_plugin(self)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, _filesystem_context_menu_plugin)
	_tools_menu = PopupMenu.new()
	_tools_menu.name = "NexusCodaToolsMenu"
	_tools_menu.add_item("Open Editor", MENU_OPEN_EDITOR)
	_tools_menu.id_pressed.connect(_on_tools_menu_id_pressed)
	# Same order as references/nexus-resonance (audio_resonance_tool/.../plugin.gd): shortcuts before add_tool_submenu_item.
	_register_tool_shortcuts()
	# PopupMenu must have no parent when passed to add_tool_submenu_item (engine requirement).
	add_tool_submenu_item(TOOLS_SUBMENU_NAME, _tools_menu)
	set_process(true)


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


func _exit_tree() -> void:
	set_process(false)
	CodaAudioBusSyncGateScript.set_gameplay_active(false)
	if _filesystem_context_menu_plugin != null:
		remove_context_menu_plugin(_filesystem_context_menu_plugin)
		_filesystem_context_menu_plugin = null
	if _ncoda_import_plugin != null:
		remove_import_plugin(_ncoda_import_plugin)
		_ncoda_import_plugin = null
	_prune_invalid_windows()
	for w in _editor_windows:
		if is_instance_valid(w):
			w.queue_free()
	_editor_windows.clear()
	if _tools_menu != null:
		if _tools_menu.id_pressed.is_connected(_on_tools_menu_id_pressed):
			_tools_menu.id_pressed.disconnect(_on_tools_menu_id_pressed)
	remove_tool_menu_item(TOOLS_SUBMENU_NAME)
	if _tools_menu != null and is_instance_valid(_tools_menu):
		_tools_menu.queue_free()
		_tools_menu = null
	# Autoload entries stay in project.godot so plugin reload does not break running scenes.


func get_editor_runtime() -> CodaRuntime:
	# Each editor window owns its preview runtime; kept for legacy callers.
	return null


## Returns [code]true[/code] only when the autoload entry is missing or points to a different
## script. Idempotent in the common case (entry already correct) — see _enter_tree comment.
func _needs_autoload_register() -> bool:
	var setting: String = "autoload/%s" % AUTOLOAD_NAME
	if not ProjectSettings.has_setting(setting):
		return true
	var current: String = String(ProjectSettings.get_setting(setting, ""))
	if current.is_empty():
		return true
	# Godot stores autoloads as "*<path-or-uid>". Both the path and any uid:// form pointing
	# to our coda_runtime.gd are acceptable; only re-register when the entry has drifted.
	if current == "*" + AUTOLOAD_PATH:
		return false
	if current.begins_with("*uid://"):
		var uid_text: String = current.substr(1)
		var uid_id: int = ResourceUID.text_to_id(uid_text)
		if uid_id != -1 and ResourceUID.has_id(uid_id):
			if ResourceUID.get_id_path(uid_id) == AUTOLOAD_PATH:
				return false
		# Cannot resolve right now (UID cache not built yet); leave the entry alone — Godot
		# will fix it on its own and we avoid rewriting the project file at every restart.
		return false
	return true


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
		return false
	return true


## Called from the FileSystem dock context menu ("Send to Coda Assets").
func send_fs_selection_to_coda_assets(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	_open_or_focus_editor_window()
	call_deferred(&"_deferred_send_fs_selection_to_coda_assets", paths)


func _deferred_send_fs_selection_to_coda_assets(paths: PackedStringArray) -> void:
	# Give the window one more frame so `_register_panels` can create `_browser_panel`.
	call_deferred(&"_deferred_send_fs_selection_to_coda_assets_after_panel", paths)


func _deferred_send_fs_selection_to_coda_assets_after_panel(paths: PackedStringArray) -> void:
	_prune_invalid_windows()
	if _editor_windows.is_empty():
		return
	var w: Window = _editor_windows[_editor_windows.size() - 1]
	if w.has_method(&"import_fs_paths_into_assets"):
		w.call(&"import_fs_paths_into_assets", paths)


## Mirrors Nexus Resonance `_register_tool_shortcuts`: global shortcut on the Project → Tools entry.
## Default: Ctrl+Shift+Y (Cmd+Shift+Y on macOS).
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
	_attach_window_to_editor_host(w)
	_editor_windows.append(w)
	_show_window_on_editor(w)


func _create_editor_window() -> Window:
	var w: Window = EDITOR_WINDOW_SCENE.instantiate() as Window
	w.set_script(EDITOR_WINDOW_SCRIPT)
	if w.has_method(&"setup_editor_plugin"):
		w.setup_editor_plugin(self)
	w.visible = false
	# Native OS window (separate taskbar entry / HWND), not embedded in the Godot editor viewport.
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
