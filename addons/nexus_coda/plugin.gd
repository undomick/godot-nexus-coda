@tool
extends EditorPlugin

const EDITOR_WINDOW_SCENE := preload("res://addons/nexus_coda/editor/nexus_coda_editor_window.tscn")
const EDITOR_WINDOW_SCRIPT := preload("res://addons/nexus_coda/editor/nexus_coda_editor_window.gd")

const TOOLS_SUBMENU_NAME := "Nexus Coda"
const MENU_OPEN_EDITOR := 0

var _tools_menu: PopupMenu
var _editor_window: Window


func _enter_tree() -> void:
	_tools_menu = PopupMenu.new()
	_tools_menu.name = "NexusCodaToolsMenu"
	_tools_menu.add_item("Open Editor", MENU_OPEN_EDITOR)
	_tools_menu.id_pressed.connect(_on_tools_menu_id_pressed)
	# PopupMenu must have no parent when passed to add_tool_submenu_item (engine requirement).
	add_tool_submenu_item(TOOLS_SUBMENU_NAME, _tools_menu)


func _exit_tree() -> void:
	if _editor_window != null and is_instance_valid(_editor_window):
		_editor_window.queue_free()
		_editor_window = null
	remove_tool_menu_item(TOOLS_SUBMENU_NAME)
	if _tools_menu != null and is_instance_valid(_tools_menu):
		_tools_menu.queue_free()
		_tools_menu = null


func _on_tools_menu_id_pressed(id: int) -> void:
	if id != MENU_OPEN_EDITOR:
		return
	_open_or_focus_editor_window()


func _open_or_focus_editor_window() -> void:
	var base := get_editor_interface().get_base_control()
	if _editor_window == null or not is_instance_valid(_editor_window):
		_editor_window = EDITOR_WINDOW_SCENE.instantiate() as Window
		# Attach at runtime so the scene file does not reference the script; avoids Scene Dock null-focus when opening the script from the FileSystem (Window-root scenes).
		_editor_window.set_script(EDITOR_WINDOW_SCRIPT)
		# Window::set_force_native fails while is_visible() && !is_in_edited_scene_root() (editor plugins are not "edited scene").
		_editor_window.visible = false
		_editor_window.force_native = true
		_editor_window.maximize_disabled = false
		_editor_window.minimize_disabled = false
		base.add_child(_editor_window)
		var host_window: Window = base.get_window()
		if host_window != null:
			_editor_window.current_screen = host_window.current_screen
		_editor_window.popup_centered_ratio(0.6)
	else:
		if not _editor_window.visible:
			var host_window: Window = base.get_window()
			if host_window != null:
				_editor_window.current_screen = host_window.current_screen
			_editor_window.show()
		_editor_window.grab_focus()
