@tool
class_name CodaMixerPanel
extends VBoxContainer

## Mixer panel: bus strips with peak meters + snapshot quick-recall.
## All edits go through CodaState's bus mutation API so save flow marks dirty.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")
const CodaBusStripScript := preload("res://addons/nexus_coda/editor/panels/mixer/coda_bus_strip.gd")
const CodaAudioBusMirrorScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_mirror.gd")

const METER_REFRESH_HZ := 30.0

var _project: CodaState = null
var _runtime: CodaRuntime = null
var _empty_state: CodaEmptyState
var _toolbar: HBoxContainer
var _scroll: ScrollContainer
var _strip_row: HBoxContainer
var _snapshot_picker: OptionButton
var _add_bus_button: Button
var _strips_by_bus_id: Dictionary = {}
var _meter_accumulator: float = 0.0


func _ready() -> void:
	name = "Mixer"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)

	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	add_child(_toolbar)

	_add_bus_button = Button.new()
	_add_bus_button.text = "+ Bus"
	_add_bus_button.tooltip_text = "Add a bus to Master"
	_add_bus_button.pressed.connect(_on_add_bus_pressed)
	_toolbar.add_child(_add_bus_button)

	var sep := VSeparator.new()
	_toolbar.add_child(sep)

	var snap_label := Label.new()
	snap_label.text = "Snapshot:"
	snap_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	snap_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_toolbar.add_child(snap_label)

	_snapshot_picker = OptionButton.new()
	_snapshot_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_snapshot_picker.item_selected.connect(_on_snapshot_picked)
	_toolbar.add_child(_snapshot_picker)

	var apply_btn := Button.new()
	apply_btn.text = "Recall"
	apply_btn.tooltip_text = "Apply selected snapshot to the live mixer"
	apply_btn.pressed.connect(_on_recall_pressed)
	_toolbar.add_child(apply_btn)

	var save_btn := Button.new()
	save_btn.text = "Capture"
	save_btn.tooltip_text = "Save current mixer state as a new snapshot"
	save_btn.pressed.connect(_on_capture_pressed)
	_toolbar.add_child(save_btn)

	var del_btn := Button.new()
	del_btn.text = "−"
	del_btn.tooltip_text = "Delete selected snapshot"
	del_btn.pressed.connect(_on_delete_snapshot_pressed)
	_toolbar.add_child(del_btn)

	_empty_state = CodaEmptyStateScript.new()
	_empty_state.title_text = "Mixer ready"
	_empty_state.body_text = "Open or create a project to see its bus tree."
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_state.visible = false
	add_child(_empty_state)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_strip_row = HBoxContainer.new()
	_strip_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_strip_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_strip_row)

	set_process(true)


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.disconnect(_on_project_structure_changed)
	_project = project
	if _project != null:
		if not _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.connect(_on_project_structure_changed)
	_rebuild_strips()
	_refresh_snapshot_picker()


func attach_runtime(runtime: CodaRuntime) -> void:
	_runtime = runtime


func _on_project_structure_changed() -> void:
	# A bus was added/removed/renamed elsewhere — rebuild from scratch. Rebuild also refreshes
	# the snapshot dropdown to reflect new/removed snapshots.
	_rebuild_strips()
	_refresh_snapshot_picker()


func _process(delta: float) -> void:
	if _strips_by_bus_id.is_empty():
		return
	_meter_accumulator += delta
	if _meter_accumulator < 1.0 / METER_REFRESH_HZ:
		return
	_meter_accumulator = 0.0
	for strip in _strips_by_bus_id.values():
		(strip as CodaBusStrip).update_meter()


func _rebuild_strips() -> void:
	for c in _strip_row.get_children():
		_strip_row.remove_child(c)
		c.queue_free()
	_strips_by_bus_id.clear()
	if _project == null or _project.bus_root == null:
		_empty_state.visible = true
		_scroll.visible = false
		return
	_empty_state.visible = false
	_scroll.visible = true
	var flat: Array[CodaBus] = _project.bus_root.collect_flat([])
	# Make sure Godot's audio server has the matching buses (also returns id->name mapping).
	var name_map: Dictionary = CodaAudioBusMirrorScript.sync_to_audio_server(_project.bus_root)
	for b in flat:
		var strip := CodaBusStripScript.new()
		_strip_row.add_child(strip)
		strip.bind(b, String(name_map.get(b.id, b.bus_name)))
		strip.volume_changed.connect(_on_strip_volume_changed)
		strip.mute_toggled.connect(_on_strip_mute_toggled)
		strip.solo_toggled.connect(_on_strip_solo_toggled)
		_strips_by_bus_id[b.id] = strip


func _refresh_snapshot_picker() -> void:
	if _project == null:
		_snapshot_picker.clear()
		_snapshot_picker.add_item("(no project)")
		_snapshot_picker.set_item_disabled(0, true)
		return
	var current: int = _snapshot_picker.get_selected_id() if _snapshot_picker.item_count > 0 else -1
	_snapshot_picker.clear()
	if _project.snapshots.is_empty():
		_snapshot_picker.add_item("(no snapshots)")
		_snapshot_picker.set_item_disabled(0, true)
		return
	for i in _project.snapshots.size():
		_snapshot_picker.add_item(_project.snapshots[i].snapshot_name, i)
	if current >= 0:
		for i in _snapshot_picker.item_count:
			if _snapshot_picker.get_item_id(i) == current:
				_snapshot_picker.select(i)
				return
	_snapshot_picker.select(0)


func _on_strip_volume_changed(bus_id: String, volume_db: float) -> void:
	if _project == null:
		return
	_project.update_bus_volume(bus_id, volume_db)
	# Push to Godot bus immediately for responsive feedback.
	var idx: int = AudioServer.get_bus_index(_get_godot_bus_name(bus_id))
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, volume_db)


func _on_strip_mute_toggled(bus_id: String, mute: bool) -> void:
	if _project == null:
		return
	_project.update_bus_mute(bus_id, mute)
	var idx: int = AudioServer.get_bus_index(_get_godot_bus_name(bus_id))
	if idx >= 0:
		AudioServer.set_bus_mute(idx, mute)


func _on_strip_solo_toggled(bus_id: String, solo: bool) -> void:
	if _project == null:
		return
	_project.update_bus_solo(bus_id, solo)
	# Solo is implemented as muting siblings; let mirror sync rebuild the truth.
	CodaAudioBusMirrorScript.sync_to_audio_server(_project.bus_root)


func _get_godot_bus_name(bus_id: String) -> String:
	if _project == null or _project.bus_root == null:
		return "Master"
	var b: CodaBus = _project.bus_root.find_by_id(bus_id)
	if b == null:
		return "Master"
	return "Master" if b.bus_name == "Master" else b.bus_name


func _on_add_bus_pressed() -> void:
	if _project == null:
		return
	_project.add_child_bus(_project.bus_root.id, "Bus %d" % (_project.bus_root.children.size() + 1))


func _on_snapshot_picked(_idx: int) -> void:
	pass  # No automatic recall on selection; user must press Recall.


func _on_recall_pressed() -> void:
	if _project == null or _snapshot_picker.item_count == 0:
		return
	var sel: int = _snapshot_picker.get_selected()
	if sel < 0:
		return
	var snap_idx: int = _snapshot_picker.get_item_id(sel)
	if snap_idx < 0 or snap_idx >= _project.snapshots.size():
		return
	var s: CodaSnapshot = _project.snapshots[snap_idx]
	if not _project.apply_snapshot(s.id):
		NexusCodaLog.warn("mixer", "Could not apply snapshot %s" % s.snapshot_name)
		return
	NexusCodaLog.info("mixer", 'Applied snapshot "%s"' % s.snapshot_name)


func _on_capture_pressed() -> void:
	if _project == null:
		return
	var s: CodaSnapshot = _project.add_snapshot(
		"Snapshot %d" % (_project.snapshots.size() + 1)
	)
	NexusCodaLog.info("mixer", 'Captured snapshot "%s"' % s.snapshot_name)


func _on_delete_snapshot_pressed() -> void:
	if _project == null or _snapshot_picker.item_count == 0:
		return
	var sel: int = _snapshot_picker.get_selected()
	if sel < 0:
		return
	var snap_idx: int = _snapshot_picker.get_item_id(sel)
	if snap_idx < 0 or snap_idx >= _project.snapshots.size():
		return
	var s: CodaSnapshot = _project.snapshots[snap_idx]
	_project.remove_snapshot(s.id)
	NexusCodaLog.info("mixer", 'Removed snapshot "%s"' % s.snapshot_name)
