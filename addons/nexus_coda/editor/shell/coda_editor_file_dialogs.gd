@tool
class_name CodaEditorFileDialogs
extends RefCounted

## Async EditorFileDialog and generic three-button prompts for the Nexus Coda editor window.

const CodaProjectIo := preload("res://addons/nexus_coda/editor/coda_project_io.gd")

const UNSAVED_LAYER_NODEPATH := NodePath("UnsavedPromptLayer")

var _host: Node
var _plugin: EditorPlugin

var _file_dialog_pick_result: String = ""
var _file_dialog_pick_complete: bool = false
var _file_dialog_user_canceled: bool = false
var _choice_result: int = 0


func setup(host: Node, plugin: EditorPlugin) -> void:
	_host = host
	_plugin = plugin


func pick_project_file(save_mode: bool, suggested_file: String = "") -> String:
	if _plugin == null or _host == null:
		return ""
	var base: Control = _plugin.get_editor_interface().get_base_control()
	var dlg := EditorFileDialog.new()
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
	var path: String = await await_editor_file_path(dlg)
	dlg.queue_free()
	return path


func pick_editor_file_path(dlg: EditorFileDialog) -> String:
	return await await_editor_file_path(dlg)


func await_editor_file_path(dlg: EditorFileDialog) -> String:
	_file_dialog_pick_result = ""
	_file_dialog_pick_complete = false
	_file_dialog_user_canceled = false

	dlg.file_selected.connect(_on_file_selected, CONNECT_ONE_SHOT)
	dlg.files_selected.connect(_on_files_selected, CONNECT_ONE_SHOT)
	dlg.canceled.connect(_on_canceled, CONNECT_ONE_SHOT)

	dlg.popup_centered_ratio(0.85)
	while not _file_dialog_pick_complete and is_instance_valid(dlg):
		await _host.get_tree().process_frame

	if not _file_dialog_pick_result.is_empty():
		return _file_dialog_pick_result
	if _file_dialog_user_canceled:
		return ""
	var cp: Variant = dlg.get("current_path")
	if cp != null:
		var s: String = str(cp).strip_edges()
		if not s.is_empty():
			return s
	return ""


func run_three_button_prompt(
	line: String, save_txt: String, discard_txt: String, cancel_txt: String
) -> int:
	if _host == null:
		return 0
	if _host.has_node(UNSAVED_LAYER_NODEPATH):
		_host.get_node(UNSAVED_LAYER_NODEPATH).queue_free()

	var layer := CanvasLayer.new()
	layer.name = "UnsavedPromptLayer"
	layer.layer = 128
	_host.add_child(layer)

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
		await _host.get_tree().process_frame

	return _choice_result


func _on_file_selected(path: String) -> void:
	if not path.is_empty():
		_file_dialog_pick_result = path
	_file_dialog_pick_complete = true


func _on_files_selected(paths: PackedStringArray) -> void:
	if _file_dialog_pick_complete:
		return
	if paths.size() > 0:
		_file_dialog_pick_result = str(paths[0])
	_file_dialog_pick_complete = true


func _on_canceled() -> void:
	if _file_dialog_pick_complete:
		return
	_file_dialog_user_canceled = true
	_file_dialog_pick_complete = true
