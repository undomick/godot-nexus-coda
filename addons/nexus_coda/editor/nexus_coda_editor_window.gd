@tool
extends Window

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaProjectIo := preload("res://addons/nexus_coda/editor/coda_project_io.gd")

const MID_NEW := 1
const MID_OPEN := 2
const MID_CLOSE := 3
const MID_SAVE := 4
const MID_SAVE_AS := 5

const RECENT_ID_BASE := 1000

@onready var _menu_bar: MenuBar = $RootVBox/MenuBar
@onready var _browser_panel: Control = $RootVBox/RootMargin/CodaEditorLayout/BrowserPanel

var _plugin: EditorPlugin

var _file_menu: PopupMenu
var _recent_menu: PopupMenu

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


func setup_editor_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _ready() -> void:
	close_requested.connect(_on_close_requested)
	_build_menus()
	call_deferred(&"_initial_bind")


func _initial_bind() -> void:
	if _browser_panel != null and _browser_panel.has_method(&"get_project"):
		_bind_project_signals(_browser_panel.get_project())
	_update_title()


func _build_menus() -> void:
	_file_menu = PopupMenu.new()
	_file_menu.name = "File"
	_menu_bar.add_child(_file_menu)

	_recent_menu = PopupMenu.new()
	_recent_menu.name = "NexusCodaRecentSub"
	_file_menu.add_child(_recent_menu)

	_rebuild_file_menu_items()
	_file_menu.id_pressed.connect(_on_file_id_pressed)
	_recent_menu.id_pressed.connect(_on_recent_id_pressed)
	_recent_menu.about_to_popup.connect(_fill_recent_menu)


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
	_project_signal_source = null
	if state == null:
		return
	var st: CodaState = state as CodaState
	if st == null:
		return
	_project_signal_source = st
	st.structure_changed.connect(_on_project_structure_changed)


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


func _load_empty_project() -> void:
	_suppress_dirty = true
	var st: CodaState = CodaStateScript.new()
	st.clear_to_empty_project()
	if _browser_panel.has_method(&"set_project"):
		_browser_panel.set_project(st)
	_bind_project_signals(st)
	if _browser_panel.has_method(&"pulse_events_selection_to_editor"):
		_browser_panel.pulse_events_selection_to_editor()
	_suppress_dirty = false


func _apply_loaded_state(st: CodaState) -> void:
	_suppress_dirty = true
	if _browser_panel.has_method(&"set_project"):
		_browser_panel.set_project(st)
	_bind_project_signals(st)
	if _browser_panel.has_method(&"pulse_events_selection_to_editor"):
		_browser_panel.pulse_events_selection_to_editor()
	_suppress_dirty = false


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
	# Newly created res:// files are not known to EditorFileSystem until update_file/scan;
	# reimport_files alone fails with "Can't find file during file reimport".
	if path.begins_with("res://"):
		if fs.has_method(&"update_file"):
			fs.update_file(path)
		if fs.has_method(&"reimport_files"):
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
	queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if has_node(UNSAVED_LAYER_NODEPATH):
			get_node(UNSAVED_LAYER_NODEPATH).queue_free()
