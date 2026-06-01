@tool
class_name CodaEditorMenuActions
extends RefCounted

## Build menu, theme, sample project, and command-palette action registry.

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaBankExportScript := preload("res://addons/nexus_coda/domain/io/coda_bank_export.gd")
const CodaDesignTokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaSampleProjectScript := preload(
	"res://addons/nexus_coda/editor/samples/coda_sample_project.gd"
)

const BID_NEW_BANK := 200
const BID_VALIDATE_BANKS := 201
const BID_EXPORT_BANK_BASE := 300

const HID_OPEN_SAMPLE := 400
const HID_SHORTCUTS := 401
const HID_TOGGLE_THEME_MODE := 402
const HID_PICK_ACCENT := 403
const HID_COMMAND_PALETTE := 404

var session: CodaEditorProjectSession = null
var plugin: EditorPlugin = null
var file_dialogs: CodaEditorFileDialogs = null
var host: Node = null

var dock_host: CodaDockHost = null
var player_panel: CodaPlayerPanel = null
var browser_panel: Control = null

var on_apply_theme: Callable = Callable()
var on_notify: Callable = Callable()
var on_open_command_palette: Callable = Callable()
var on_open_shortcut_sheet: Callable = Callable()
var on_layout_save: Callable = Callable()
var on_layout_load: Callable = Callable()
var on_layout_clear: Callable = Callable()
var on_layout_reset: Callable = Callable()
var on_select_event: Callable = Callable()

var _color_picker_dialog: AcceptDialog = null
var _project_theme: Theme = null


func get_project_theme() -> Theme:
	return _project_theme


func rebuild_build_menu(build_menu: PopupMenu) -> void:
	if build_menu == null:
		return
	build_menu.clear()
	build_menu.add_item("New Bank…", BID_NEW_BANK)
	build_menu.add_item("Validate All Banks", BID_VALIDATE_BANKS)
	build_menu.add_separator()
	var st: CodaState = session.get_state() if session != null else null
	if st == null or st.banks.is_empty():
		build_menu.add_item("(no banks defined)", -1)
		build_menu.set_item_disabled(build_menu.item_count - 1, true)
		return
	for i in st.banks.size():
		build_menu.add_item("Export “%s”…" % st.banks[i].bank_name, BID_EXPORT_BANK_BASE + i)


func rebuild_help_menu(help_menu: PopupMenu) -> void:
	if help_menu == null:
		return
	help_menu.clear()
	help_menu.add_item("Command Palette…", HID_COMMAND_PALETTE)
	help_menu.add_item("Keyboard Shortcuts…", HID_SHORTCUTS)
	help_menu.add_separator()
	help_menu.add_item("Open Sample Project", HID_OPEN_SAMPLE)
	help_menu.add_separator()
	var st: CodaState = session.get_state() if session != null else null
	var mode_label: String = "Switch to Light Theme"
	if st != null and st.theme_mode == "light":
		mode_label = "Switch to Dark Theme"
	help_menu.add_item(mode_label, HID_TOGGLE_THEME_MODE)
	help_menu.add_item("Pick Accent Color…", HID_PICK_ACCENT)


func on_build_id_pressed(id: int) -> void:
	match id:
		BID_NEW_BANK:
			action_new_bank()
		BID_VALIDATE_BANKS:
			action_validate_banks()
		_:
			if id >= BID_EXPORT_BANK_BASE:
				await action_export_bank_async(id - BID_EXPORT_BANK_BASE)


func on_help_id_pressed(id: int) -> void:
	match id:
		HID_COMMAND_PALETTE:
			if on_open_command_palette.is_valid():
				on_open_command_palette.call()
		HID_SHORTCUTS:
			if on_open_shortcut_sheet.is_valid():
				on_open_shortcut_sheet.call()
		HID_OPEN_SAMPLE:
			await action_open_sample_async()
		HID_TOGGLE_THEME_MODE:
			action_toggle_theme_mode()
		HID_PICK_ACCENT:
			action_pick_accent_color()
		_:
			pass


func action_new_bank() -> void:
	var st: CodaState = session.get_state() if session != null else null
	if st == null:
		return
	var b: CodaBank = st.add_bank("Bank %d" % (st.banks.size() + 1))
	NexusCodaLog.info("bank", 'Created bank "%s"' % b.bank_name)


func action_validate_banks() -> void:
	var st: CodaState = session.get_state() if session != null else null
	if st == null:
		return
	if st.banks.is_empty():
		_notify("No banks defined.", false)
		return
	var problems_total: int = 0
	for b in st.banks:
		var problems: PackedStringArray = CodaBankExportScript.validate_bank(st, b)
		if problems.is_empty():
			NexusCodaLog.info("bank", '"%s" passes validation.' % b.bank_name)
			continue
		problems_total += problems.size()
		for p in problems:
			NexusCodaLog.warn("bank", '"%s": %s' % [b.bank_name, p])
	_notify(
		"Validation finished: %d issue(s) — see Log panel." % problems_total,
		false
	)


func action_export_bank_async(bank_index: int) -> void:
	var st: CodaState = session.get_state() if session != null else null
	if st == null:
		return
	if bank_index < 0 or bank_index >= st.banks.size():
		return
	var bank: CodaBank = st.banks[bank_index]
	var problems: PackedStringArray = CodaBankExportScript.validate_bank(st, bank)
	if not problems.is_empty():
		for p in problems:
			NexusCodaLog.warn("bank_export", '"%s": %s' % [bank.bank_name, p])
		_notify(
			'Bank "%s" has %d validation issue(s) — fix in Log panel before exporting.'
			% [bank.bank_name, problems.size()],
			false
		)
		return
	var p: String = await _pick_bank_save_path(bank.bank_name)
	if p.is_empty():
		return
	if p.get_extension().to_lower() != CodaBankExportScript.FORMAT_EXTENSION:
		p = "%s.%s" % [p, CodaBankExportScript.FORMAT_EXTENSION]
	var err: String = CodaBankExportScript.write_to_path(st, bank, p)
	if not err.is_empty():
		_notify(err, true)
		return
	_notify('Exported bank "%s" to %s' % [bank.bank_name, p], false)


func pick_audio_bus_layout_export_path_async() -> String:
	if plugin == null or file_dialogs == null:
		return ""
	var base: Control = plugin.get_editor_interface().get_base_control()
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
	var path: String = await file_dialogs.pick_editor_file_path(dlg)
	dlg.queue_free()
	return path


func complete_audio_bus_layout_export(saved_path: String, err: Error) -> void:
	if err != OK:
		_notify("Could not export bus layout (%s)." % error_string(err), true)
		return
	if saved_path.is_empty():
		_notify("Bus layout export finished without a path.", true)
		return
	_notify('Exported bus layout to "%s"' % saved_path, false)
	if session != null and session.on_refresh_filesystem.is_valid():
		session.on_refresh_filesystem.call(saved_path)


func action_open_sample_async() -> void:
	if session == null:
		return
	session.autosave_for_navigation()
	var sample: CodaState = CodaSampleProjectScript.build()
	session.apply_loaded_state(sample)
	session.current_path = ""
	session.dirty = true
	session.emit_title_update()
	apply_theme_appearance(sample.theme_mode, sample.accent_color)
	NexusCodaLog.info(
		"sample",
		"Opened onboarding sample. Drag your own audio onto the SOUND nodes to hear it."
	)


func action_toggle_theme_mode() -> void:
	var st: CodaState = session.get_state() if session != null else null
	if st == null:
		return
	var next_mode: String = "light" if st.theme_mode == "dark" else "dark"
	st.set_theme_appearance(next_mode, st.accent_color)
	apply_theme_appearance(st.theme_mode, st.accent_color)


func action_pick_accent_color() -> void:
	var st: CodaState = session.get_state() if session != null else null
	if st == null or host == null:
		return
	if _color_picker_dialog != null and is_instance_valid(_color_picker_dialog):
		_color_picker_dialog.queue_free()
	_color_picker_dialog = AcceptDialog.new()
	_color_picker_dialog.title = "Pick Accent Color"
	host.add_child(_color_picker_dialog)
	var picker := ColorPicker.new()
	picker.color = st.accent_color
	picker.edit_alpha = false
	_color_picker_dialog.add_child(picker)
	picker.color_changed.connect(
		func(c: Color) -> void:
			st.set_theme_appearance(st.theme_mode, c)
			apply_theme_appearance(st.theme_mode, c)
	)
	_color_picker_dialog.popup_centered_ratio(0.4)


func apply_theme_appearance(theme_mode: String, accent: Color) -> void:
	_project_theme = CodaDesignTokens.make_project_theme(theme_mode, accent)
	if on_apply_theme.is_valid():
		on_apply_theme.call(_project_theme)


func collect_palette_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dm: CodaDockManager = dock_host.dock_manager if dock_host != null else null

	out.append({"title": "New Project", "subtitle": "Ctrl+N", "category": "File",
		"callable": Callable(session, "action_new_async") if session != null else Callable()})
	out.append({"title": "Open Project…", "subtitle": "Ctrl+O", "category": "File",
		"callable": Callable(session, "action_open_async") if session != null else Callable()})
	out.append({"title": "Save", "subtitle": "Ctrl+S", "category": "File",
		"callable": Callable(session, "action_save_async") if session != null else Callable()})
	out.append({"title": "Save As…", "subtitle": "Ctrl+Shift+S", "category": "File",
		"callable": Callable(session, "action_save_as_async") if session != null else Callable()})
	out.append({"title": "Close Window", "subtitle": "", "category": "File",
		"callable": Callable(session, "action_close_window_async") if session != null else Callable()})

	if dm != null:
		var panels: Array = [
			[&"browser", "Toggle Browser Panel"],
			[&"graph", "Toggle Graph Panel"],
			[&"timeline", "Toggle Timeline Panel"],
			[&"inspector", "Toggle Inspector Panel"],
			[&"player", "Toggle Player Panel"],
			[&"mixer", "Toggle Mixer Panel"],
			[&"log", "Toggle Log Panel"],
		]
		for entry_v in panels:
			var arr: Array = entry_v as Array
			var pid: StringName = arr[0]
			var title: String = arr[1]
			out.append({"title": title, "subtitle": "", "category": "View",
				"callable": Callable(dm, "toggle_panel").bind(pid)})
		out.append({"title": "Save Layout", "subtitle": "", "category": "View",
			"callable": on_layout_save})
		out.append({"title": "Load Saved Layout", "subtitle": "", "category": "View",
			"callable": on_layout_load})
		out.append({"title": "Clear Saved Layout", "subtitle": "", "category": "View",
			"callable": on_layout_clear})
		out.append({"title": "Reset Layout", "subtitle": "", "category": "View",
			"callable": on_layout_reset})

	if player_panel != null:
		out.append({"title": "Player: Play Selection", "subtitle": "", "category": "Player",
			"callable": Callable(player_panel, "play_current_selection")})
		out.append({"title": "Player: Stop", "subtitle": "", "category": "Player",
			"callable": Callable(player_panel, "stop_current_voice")})
		out.append({"title": "Player: Pin / Unpin Selection", "subtitle": "", "category": "Player",
			"callable": Callable(player_panel, "toggle_pin")})

	out.append({"title": "Create New Bank", "subtitle": "", "category": "Build",
		"callable": Callable(self, "action_new_bank")})
	out.append({"title": "Validate All Banks", "subtitle": "", "category": "Build",
		"callable": Callable(self, "action_validate_banks")})

	out.append({"title": "Open Sample Project", "subtitle": "", "category": "Help",
		"callable": Callable(self, "action_open_sample_async")})
	out.append({"title": "Keyboard Shortcuts", "subtitle": "F1", "category": "Help",
		"callable": on_open_shortcut_sheet})
	out.append({"title": "Toggle Theme Mode", "subtitle": "Light/Dark", "category": "Theme",
		"callable": Callable(self, "action_toggle_theme_mode")})
	out.append({"title": "Pick Accent Color…", "subtitle": "", "category": "Theme",
		"callable": Callable(self, "action_pick_accent_color")})

	var st: CodaState = session.get_state() if session != null else null
	if st != null and browser_panel != null:
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
				"callable": on_select_event.bind(event_id) if on_select_event.is_valid() else Callable(),
			})
	return out


func teardown() -> void:
	if _color_picker_dialog != null and is_instance_valid(_color_picker_dialog):
		_color_picker_dialog.free()
	_color_picker_dialog = null
	_project_theme = null
	session = null
	plugin = null
	file_dialogs = null
	host = null
	dock_host = null
	player_panel = null
	browser_panel = null
	on_apply_theme = Callable()
	on_notify = Callable()
	on_open_command_palette = Callable()
	on_open_shortcut_sheet = Callable()
	on_select_event = Callable()


func _pick_bank_save_path(suggest_name: String) -> String:
	if plugin == null or file_dialogs == null:
		return ""
	var base: Control = plugin.get_editor_interface().get_base_control()
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
	var path: String = await file_dialogs.pick_editor_file_path(dlg)
	dlg.queue_free()
	return path


func _collect_event_paths(folder: CodaBrowserNode, prefix: String, out: Array[Dictionary]) -> void:
	for child in folder.children:
		var path: String = "%s/%s" % [prefix, child.name] if not prefix.is_empty() else child.name
		if child.kind == CodaBrowserNode.Kind.EVENT:
			out.append({"id": child.id, "path": path})
		elif child.is_folder():
			_collect_event_paths(child, path, out)


func _notify(message: String, is_error: bool) -> void:
	if on_notify.is_valid():
		on_notify.call(message, is_error)
