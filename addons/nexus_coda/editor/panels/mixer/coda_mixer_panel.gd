@tool
class_name CodaMixerPanel
extends VBoxContainer

## Mixer panel: bus strips with peak meters + snapshot quick-recall.
## All edits go through CodaState's bus mutation API so save flow marks dirty.

signal bus_selection_changed(bus_id: String)
signal bus_user_selected(bus_id: String)

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")
const CodaBusStripScript := preload("res://addons/nexus_coda/editor/panels/mixer/coda_bus_strip.gd")
const CodaMixerStripRowScript := preload("res://addons/nexus_coda/editor/panels/mixer/coda_mixer_strip_row.gd")
const CodaMixerAddBusSlotScript := preload("res://addons/nexus_coda/editor/panels/mixer/coda_mixer_add_bus_slot.gd")
const CodaAudioBusMirrorScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_mirror.gd")
const CodaAudioBusSyncGateScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd"
)

const METER_REFRESH_HZ := 30.0

var _project: CodaState = null
var _runtime: CodaRuntime = null
var _empty_state: CodaEmptyState
var _toolbar: HBoxContainer
var _scroll: ScrollContainer
var _strip_row: HBoxContainer
var _snapshot_picker: OptionButton
var _pick_bus_layout_path: Callable = Callable()
var _complete_bus_layout_export: Callable = Callable()
var _strips_by_bus_id: Dictionary = {}
var _meter_accumulator: float = 0.0
var _selected_bus_id: String = ""
var _vca_picker: OptionButton
var _vca_volume: SpinBox


func _ready() -> void:
	name = "Mixer"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)

	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	add_child(_toolbar)

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

	var sep_export := VSeparator.new()
	_toolbar.add_child(sep_export)

	var export_bus_btn := Button.new()
	export_bus_btn.text = "Export Bus Layout…"
	export_bus_btn.tooltip_text = "Save this project's bus tree as a Godot AudioBusLayout .tres (only Coda buses — pick path and filename)."
	export_bus_btn.pressed.connect(_on_export_bus_layout_pressed)
	_toolbar.add_child(export_bus_btn)

	var sep_vca := VSeparator.new()
	_toolbar.add_child(sep_vca)

	var vca_label := Label.new()
	vca_label.text = "VCA:"
	vca_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_toolbar.add_child(vca_label)

	_vca_picker = OptionButton.new()
	_vca_picker.custom_minimum_size = Vector2(100, 0)
	_vca_picker.item_selected.connect(_on_vca_picked)
	_toolbar.add_child(_vca_picker)

	_vca_volume = SpinBox.new()
	_vca_volume.prefix = "dB "
	_vca_volume.min_value = -60.0
	_vca_volume.max_value = 12.0
	_vca_volume.step = 0.1
	_vca_volume.value_changed.connect(_on_vca_volume_changed)
	_toolbar.add_child(_vca_volume)

	var add_vca_btn := Button.new()
	add_vca_btn.text = "+ VCA"
	add_vca_btn.pressed.connect(_on_add_vca_pressed)
	_toolbar.add_child(add_vca_btn)

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

	_strip_row = CodaMixerStripRowScript.new()
	_strip_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_strip_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_strip_row.setup(self)
	_scroll.add_child(_strip_row)

	set_process(true)


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_on_mixer_structure_changed):
			_project.structure_changed.disconnect(_on_mixer_structure_changed)
	_project = project
	if _project != null:
		if not _project.structure_changed.is_connected(_on_mixer_structure_changed):
			_project.structure_changed.connect(_on_mixer_structure_changed)
	_rebuild_strips()
	_refresh_snapshot_picker()
	_refresh_vca_picker()


func attach_runtime(runtime: CodaRuntime) -> void:
	_runtime = runtime


func select_bus(bus_id: String) -> void:
	if bus_id.is_empty() or not _strips_by_bus_id.has(bus_id):
		return
	_selected_bus_id = bus_id
	var strip: CodaBusStrip = _strips_by_bus_id.get(bus_id, null) as CodaBusStrip
	if strip != null:
		_scroll.ensure_control_visible(strip)
	_apply_bus_selection_visual()
	bus_selection_changed.emit(bus_id)


func highlight_snapshot(snapshot_id: String) -> void:
	if _project == null or snapshot_id.is_empty():
		return
	for i in _project.snapshots.size():
		if _project.snapshots[i].id == snapshot_id:
			for j in _snapshot_picker.item_count:
				if _snapshot_picker.get_item_id(j) == i:
					_snapshot_picker.select(j)
					return


func attach_bus_layout_export(pick_path: Callable, on_complete: Callable) -> void:
	_pick_bus_layout_path = pick_path
	_complete_bus_layout_export = on_complete


func _mirror_project_buses(prune_unclaimed: bool) -> Dictionary:
	if _project == null or _project.bus_root == null:
		return {}
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.EditorMixer, prune_unclaimed
	):
		return {}
	return CodaAudioBusMirrorScript.sync_to_audio_server(
		_project.bus_root, prune_unclaimed, _project.vcas, {}
	)


func _on_mixer_structure_changed() -> void:
	# Defer so callers (controls, snapshots, etc.) are never mid–child-list mutation when we rebuild.
	# Do NOT coalesce drops: multiple emits before the deferred run must all converge into one rebuild
	# scheduled per emit, otherwise Recall can be ignored while a deferred rebuild is still queued.
	call_deferred("_deferred_mixer_rebuild")


func _deferred_mixer_rebuild() -> void:
	if not is_instance_valid(self) or _project == null:
		return
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
	var return_buses: Array[CodaBus] = _project.bus_root.collect_return_buses([])
	# Make sure Godot's audio server has the matching buses (also returns id->name mapping).
	# Do not prune non-Coda Godot buses during normal mixer editing (would delete the game's
	# native AudioServer layout). Pruning runs only before explicit bus-layout export.
	var name_map: Dictionary = _mirror_project_buses(false)
	for b in flat:
		var strip := CodaBusStripScript.new()
		_strip_row.add_child(strip)
		var is_master: bool = b.id == _project.bus_root.id
		var send_targets: Array[CodaBus] = _previous_flat_send_targets(b, flat)
		var default_send: String = ""
		var pbus: CodaBus = _project.parent_bus_of(b.id)
		if pbus != null:
			default_send = pbus.id
		strip.bind(
			b,
			String(name_map.get(b.id, b.bus_name)),
			is_master,
			send_targets,
			default_send,
			return_buses
		)
		strip.volume_changed.connect(_on_strip_volume_changed)
		strip.mute_toggled.connect(_on_strip_mute_toggled)
		strip.solo_toggled.connect(_on_strip_solo_toggled)
		strip.bypass_toggled.connect(_on_strip_bypass_toggled)
		strip.bus_renamed.connect(_on_strip_bus_renamed)
		strip.bus_link_changed.connect(_on_strip_bus_link_changed)
		strip.wet_send_level_changed.connect(_on_strip_wet_send_level_changed)
		strip.context_action_requested.connect(_on_strip_context_action_requested)
		strip.bus_strip_selected.connect(_on_bus_strip_selected)
		_strips_by_bus_id[b.id] = strip

	var add_slot := CodaMixerAddBusSlotScript.new()
	add_slot.add_bus_requested.connect(_on_add_bus_pressed)
	_strip_row.add_child(add_slot)
	_ensure_bus_selection_after_rebuild(flat)


func _ensure_bus_selection_after_rebuild(flat: Array[CodaBus]) -> void:
	if flat.is_empty() or _project == null or _project.bus_root == null:
		_selected_bus_id = ""
		_apply_bus_selection_visual()
		return
	if not _strips_by_bus_id.has(_selected_bus_id):
		_selected_bus_id = _project.bus_root.id
	_apply_bus_selection_visual()
	bus_selection_changed.emit(_selected_bus_id)


func _apply_bus_selection_visual() -> void:
	for bus_id in _strips_by_bus_id.keys():
		var strip: CodaBusStrip = _strips_by_bus_id.get(bus_id, null) as CodaBusStrip
		if strip != null:
			strip.set_selected(String(bus_id) == _selected_bus_id)


func _on_bus_strip_selected(bus_id: String) -> void:
	_selected_bus_id = bus_id
	_apply_bus_selection_visual()
	bus_selection_changed.emit(bus_id)
	bus_user_selected.emit(bus_id)


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
	_mirror_project_buses(false)


func _on_strip_bypass_toggled(bus_id: String, bypass: bool) -> void:
	if _project == null:
		return
	_project.update_bus_bypass(bus_id, bypass)
	var idx: int = AudioServer.get_bus_index(_get_godot_bus_name(bus_id))
	if idx >= 0:
		AudioServer.set_bus_bypass_effects(idx, bypass)


func _on_strip_bus_renamed(bus_id: String, new_name: String) -> void:
	if _project == null:
		return
	_project.rename_bus(bus_id, new_name)


func _previous_flat_send_targets(bus: CodaBus, flat: Array[CodaBus]) -> Array[CodaBus]:
	var out: Array[CodaBus] = []
	if _project == null or _project.bus_root == null:
		return out
	var idx: int = -1
	for i in flat.size():
		if (flat[i] as CodaBus).id == bus.id:
			idx = i
			break
	if idx <= 0:
		return out
	for i in idx:
		out.append(flat[i] as CodaBus)
	return out


func _on_strip_bus_link_changed(bus_id: String, target_bus_id: String) -> void:
	if _project == null:
		return
	_project.update_bus_send_target(bus_id, target_bus_id)
	_mirror_project_buses(false)


func _on_strip_wet_send_level_changed(bus_id: String, send_id: String, level: float) -> void:
	if _project == null:
		return
	_project.update_wet_send_level(bus_id, send_id, level)
	_mirror_project_buses(false)


func on_bus_strip_drop_at_flat_index(drag_bus_id: String, insert_before_flat: int) -> void:
	if _project == null or _project.bus_root == null:
		return
	var flat: Array[CodaBus] = _project.bus_root.collect_flat([])
	if flat.is_empty():
		return
	var ix: int = insert_before_flat
	if ix <= 0:
		ix = 1
	if drag_bus_id == _project.bus_root.id:
		return
	if ix >= flat.size():
		var last: CodaBus = flat[flat.size() - 1]
		if last.id == drag_bus_id:
			return
		_project.move_bus_after_in_tree(drag_bus_id, last.id)
	else:
		var before_b: CodaBus = flat[ix]
		if before_b.id == drag_bus_id:
			return
		_project.move_bus_before_in_tree(drag_bus_id, before_b.id)


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


func _on_strip_context_action_requested(bus_id: String, action: StringName) -> void:
	if _project == null or _project.bus_root == null:
		return
	match action:
		&"add_bus_here":
			_project.add_bus_after(bus_id, "Bus")
		&"duplicate_bus":
			_project.duplicate_bus(bus_id)
		&"delete_bus":
			_project.remove_bus(bus_id)
		&"reset_volume":
			_project.reset_bus_volume(bus_id)
			_on_strip_volume_changed(bus_id, 0.0)
			var strip: CodaBusStrip = _strips_by_bus_id.get(bus_id, null) as CodaBusStrip
			if strip != null:
				strip.set_volume_no_signal(0.0)
		&"add_return_bus":
			var ret: CodaBus = _project.add_return_bus(bus_id, "Reverb Return")
			if ret != null:
				_mirror_project_buses(false)
				_rebuild_strips()
		&"add_wet_send":
			var returns: Array[CodaBus] = _project.bus_root.collect_return_buses([])
			if returns.is_empty():
				var ret2: CodaBus = _project.add_return_bus(_project.bus_root.id, "Reverb Return")
				if ret2 != null:
					returns = [ret2]
			if not returns.is_empty():
				_project.add_wet_send(bus_id, returns[0].id, 0.25)
				_mirror_project_buses(false)
				_rebuild_strips()
		_:
			pass


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
	var applied: bool = false
	if _runtime != null and _runtime.has_method(&"apply_snapshot"):
		applied = _runtime.apply_snapshot(s.id, s.blend_ms)
	elif not _project.apply_snapshot(s.id):
		NexusCodaLog.warn("mixer", "Could not apply snapshot %s" % s.snapshot_name)
		return
	else:
		applied = true
	if not applied:
		NexusCodaLog.warn("mixer", "Could not apply snapshot %s" % s.snapshot_name)
		return
	# apply_snapshot emits structure_changed (deferred rebuild), but always push to AudioServer here
	# so Godot's live bus layout updates even if coalescing or ordering would skip a rebuild.
	# Do not prune non-Coda Godot buses during normal mixer editing (would delete the game's
	# native AudioServer layout). Pruning runs only before explicit bus-layout export.
	var name_map: Dictionary = _mirror_project_buses(false)
	_sync_strip_ui_from_project(name_map)
	NexusCodaLog.info("mixer", 'Applied snapshot "%s"' % s.snapshot_name)


func _sync_strip_ui_from_project(name_map: Dictionary) -> void:
	if _project == null or _project.bus_root == null:
		return
	var flat: Array[CodaBus] = _project.bus_root.collect_flat([])
	var return_buses: Array[CodaBus] = _project.bus_root.collect_return_buses([])
	for b in flat:
		var strip: CodaBusStrip = _strips_by_bus_id.get(b.id, null) as CodaBusStrip
		if strip == null:
			continue
		var is_master: bool = b.id == _project.bus_root.id
		var send_targets: Array[CodaBus] = _previous_flat_send_targets(b, flat)
		var default_send: String = ""
		var pbus: CodaBus = _project.parent_bus_of(b.id)
		if pbus != null:
			default_send = pbus.id
		strip.bind(
			b,
			String(name_map.get(b.id, b.bus_name)),
			is_master,
			send_targets,
			default_send,
			return_buses
		)


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


func _on_export_bus_layout_pressed() -> void:
	if _pick_bus_layout_path.is_null():
		NexusCodaLog.warn("mixer", "Bus layout export is not connected.")
		return
	if _project == null or _project.bus_root == null:
		NexusCodaLog.warn("mixer", "Open a project with buses before exporting the bus layout.")
		return
	_mirror_project_buses(true)
	var picked: Variant = await _pick_bus_layout_path.call()
	var raw_path: String = str(picked).strip_edges()
	if raw_path.is_empty():
		return
	var result: Dictionary = CodaAudioBusMirrorScript.save_current_audio_bus_layout(raw_path, _project.bus_root)
	var err: Error = result.get("error", FAILED) as Error
	var saved_path: String = str(result.get("path", ""))
	if not _complete_bus_layout_export.is_null():
		_complete_bus_layout_export.call(saved_path, err)
	elif err != OK:
		NexusCodaLog.warn("mixer", "Could not export bus layout (%s)." % error_string(err))
	else:
		NexusCodaLog.info("mixer", 'Exported bus layout to "%s"' % saved_path)


func _refresh_vca_picker() -> void:
	if _vca_picker == null:
		return
	_vca_picker.clear()
	if _project == null or _project.vcas.is_empty():
		_vca_picker.add_item("(none)")
		_vca_picker.set_item_disabled(0, true)
		if _vca_volume != null:
			_vca_volume.editable = false
		return
	for i in _project.vcas.size():
		var v: CodaVca = _project.vcas[i]
		_vca_picker.add_item(v.vca_name)
		_vca_picker.set_item_metadata(i, v.id)
	if _vca_volume != null:
		_vca_volume.editable = true
		_on_vca_picked(_vca_picker.selected)


func _on_vca_picked(_idx: int) -> void:
	if _project == null or _vca_picker == null or _vca_volume == null:
		return
	if _vca_picker.item_count == 0 or _vca_picker.get_item_text(0) == "(none)":
		return
	var sel: int = _vca_picker.selected
	if sel < 0 or sel >= _vca_picker.item_count:
		return
	var vca_id: String = str(_vca_picker.get_item_metadata(sel))
	var v: CodaVca = _project.find_vca_by_id(vca_id)
	if v == null:
		return
	_vca_volume.set_value_no_signal(v.volume_db)


func _on_vca_volume_changed(value: float) -> void:
	if _project == null or _vca_picker == null:
		return
	var vca_id: String = str(_vca_picker.get_item_metadata(_vca_picker.selected))
	if vca_id.is_empty():
		return
	_project.update_vca_volume(vca_id, float(value))
	_mirror_project_buses(false)


func _on_add_vca_pressed() -> void:
	if _project == null:
		return
	var v: CodaVca = _project.add_vca("VCA %d" % (_project.vcas.size() + 1))
	if v == null:
		return
	var flat: Array[CodaBus] = _project.bus_root.collect_flat([])
	for b in flat:
		if b.id != _project.bus_root.id and b.bus_kind == CodaBus.BusKind.MIX:
			_project.set_vca_controls_bus(v.id, b.id, true)
	_refresh_vca_picker()
	_mirror_project_buses(false)
