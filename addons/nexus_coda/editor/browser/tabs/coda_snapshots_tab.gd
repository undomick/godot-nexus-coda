@tool
class_name CodaSnapshotsTab
extends CodaBrowserTab

## Snapshots tab — flat list of CodaState.snapshots.
## Quick action: New Snapshot.
## Double-click activates `apply_snapshot(id)` (recall to live mixer).
## Selection emits `selection_emitted(CATEGORY_SNAPSHOT, snapshot_id)` so the host can
## focus the Mixer panel.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")

var _project: CodaState = null
var _filter_edit: LineEdit
var _list: ItemList
var _add_button: Button
var _recall_button: Button
var _delete_button: Button
var _rebuild_queued: bool = false


func _init() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_XS)


func get_tab_title() -> String:
	return "Snapshots"


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var qa := HBoxContainer.new()
	qa.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	qa.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(qa)

	_add_button = Button.new()
	_add_button.text = "+ Snapshot"
	_add_button.tooltip_text = "Capture a new snapshot from the current mixer state"
	_add_button.pressed.connect(_on_add_pressed)
	qa.add_child(_add_button)

	_recall_button = Button.new()
	_recall_button.text = "Recall"
	_recall_button.tooltip_text = "Apply the selected snapshot to the live mixer"
	_recall_button.disabled = true
	_recall_button.pressed.connect(_on_recall_pressed)
	qa.add_child(_recall_button)

	_delete_button = Button.new()
	_delete_button.text = "−"
	_delete_button.tooltip_text = "Remove the selected snapshot"
	_delete_button.disabled = true
	_delete_button.pressed.connect(_on_delete_pressed)
	qa.add_child(_delete_button)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Filter..."
	_filter_edit.clear_button_enabled = true
	_filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_edit.text_changed.connect(_on_filter_changed)
	add_child(_filter_edit)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_activated)
	_list.empty_clicked.connect(_on_empty_clicked)
	add_child(_list)

	if _project != null:
		_queue_rebuild()


func attach_state(state: Variant) -> void:
	if _project != null and _project.structure_changed.is_connected(_on_project_structure_changed):
		_project.structure_changed.disconnect(_on_project_structure_changed)
	if _project != null and _project.project_dirty.is_connected(_on_project_structure_changed):
		_project.project_dirty.disconnect(_on_project_structure_changed)
	_project = null if state == null else (state as CodaState)
	if _project != null:
		_project.structure_changed.connect(_on_project_structure_changed)
		_project.project_dirty.connect(_on_project_structure_changed)
	if _list != null:
		_queue_rebuild()


func apply_filter(text: String) -> void:
	if _filter_edit != null and _filter_edit.text != text:
		_filter_edit.text = text


func pulse_selection_to_editor() -> void:
	_emit_selection()


func select_by_id(target_id: String) -> bool:
	if _list == null or target_id.is_empty():
		return false
	for i in _list.item_count:
		if str(_list.get_item_metadata(i)) == target_id:
			_list.select(i)
			_list.ensure_current_is_visible()
			_emit_selection()
			return true
	return false


# ---------- Internals ----------

func _on_project_structure_changed() -> void:
	_queue_rebuild()


func _on_filter_changed(_text: String) -> void:
	_queue_rebuild()


func _filter_text_lower() -> String:
	if _filter_edit == null:
		return ""
	return _filter_edit.text.strip_edges().to_lower()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred(&"_deferred_rebuild")


func _deferred_rebuild() -> void:
	var prev: String = _selected_id()
	_rebuild_queued = false
	_rebuild_list()
	if not prev.is_empty():
		select_by_id(prev)


func _rebuild_list() -> void:
	if _list == null or _project == null:
		return
	_list.clear()
	var fl: String = _filter_text_lower()
	for s in _project.snapshots:
		if not fl.is_empty() and not String(s.snapshot_name).to_lower().contains(fl):
			continue
		var idx: int = _list.add_item(s.snapshot_name)
		_list.set_item_metadata(idx, s.id)
		_list.set_item_tooltip(idx, "Double-click to recall (apply to live mixer)")
	_update_action_button_state()


func _selected_id() -> String:
	if _list == null:
		return ""
	var sel: PackedInt32Array = _list.get_selected_items()
	if sel.is_empty():
		return ""
	return str(_list.get_item_metadata(sel[0]))


func _on_item_selected(_idx: int) -> void:
	_update_action_button_state()
	_emit_selection()


func _on_item_activated(_idx: int) -> void:
	_apply_selected_snapshot()


func _on_empty_clicked(_pos: Vector2, _btn: int) -> void:
	if _list != null:
		_list.deselect_all()
	_update_action_button_state()


func _update_action_button_state() -> void:
	var has: bool = not _selected_id().is_empty()
	if _recall_button != null:
		_recall_button.disabled = not has
	if _delete_button != null:
		_delete_button.disabled = not has


func _emit_selection() -> bool:
	var sid: String = _selected_id()
	if sid.is_empty():
		return false
	selection_emitted.emit(CATEGORY_SNAPSHOT, sid)
	return true


# ---------- Quick actions ----------

func _on_add_pressed() -> void:
	if _project == null:
		return
	var s: CodaSnapshot = _project.add_snapshot(
		"Snapshot %d" % (_project.snapshots.size() + 1)
	)
	if s != null:
		NexusCodaLog.info("snapshots", 'Captured snapshot "%s"' % s.snapshot_name)
		call_deferred(&"select_by_id", s.id)


func _on_recall_pressed() -> void:
	_apply_selected_snapshot()


func _on_delete_pressed() -> void:
	if _project == null:
		return
	var sid: String = _selected_id()
	if sid.is_empty():
		return
	_project.remove_snapshot(sid)


func _apply_selected_snapshot() -> void:
	if _project == null:
		return
	var sid: String = _selected_id()
	if sid.is_empty():
		return
	if not _project.apply_snapshot(sid):
		NexusCodaLog.warn("snapshots", "Could not apply snapshot %s" % sid)
		return
	var snap: CodaSnapshot = _project.find_snapshot_by_id(sid)
	if snap != null:
		NexusCodaLog.info("snapshots", 'Applied snapshot "%s"' % snap.snapshot_name)
