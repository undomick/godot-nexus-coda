@tool
class_name CodaTimelinePanel
extends VBoxContainer

## Per-event timeline panel — alternate authoring view to the Event-Graph.
## When the selected event's `event_authoring_mode == TIMELINE`, the panel composes
## a track-header column on the left with the reusable `CodaTimelineView` widget on
## the right; both columns use the same row metrics so they stay aligned.
## When the mode is GRAPH, the panel shows an empty state with a "Switch to Timeline"
## affordance so designers can opt in.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")
const CodaTimelineViewScript := preload(
	"res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_view.gd"
)
const CodaTrackHeaderStripScript := preload(
	"res://addons/nexus_coda/editor/widgets/timeline/coda_track_header_strip.gd"
)
const CodaTimelineMarkerUiScript := preload(
	"res://addons/nexus_coda/editor/panels/timeline/coda_timeline_marker_ui.gd"
)
const CodaTimelineViewHandlersScript := preload(
	"res://addons/nexus_coda/editor/panels/timeline/coda_timeline_view_handlers.gd"
)

const RULER_HEIGHT := CodaTimelineViewScript.RULER_HEIGHT
const TRACK_HEADER_SPLIT_MIN_PX := 120
const TRACK_HEADER_SPLIT_MAX_PX := 280
const TRACK_HEADER_SPLIT_MAX_FRACT := 0.34

signal track_effects_focus_requested(track_id: String)
signal track_selection_changed(event_id: String, track_id: String)
signal clip_selection_changed(event_id: String, clip_id: String)

var _project: CodaState = null
var _selected_event: CodaBrowserNode = null

var _toolbar_ui: CodaTimelineToolbar
var _preview: CodaTimelinePreviewBridge
var _undo_stack: Array[CodaEventTimeline] = []
var _redo_stack: Array[CodaEventTimeline] = []

var _empty_state: CodaEmptyState
var _split_root: HSplitContainer
var _track_headers_column: VBoxContainer
var _ruler_spacer: Control
var _track_headers_host: VBoxContainer
var _add_track_btn: Button
var _view: CodaTimelineView
var _validation_label: Label
var _hints_label: Label

var _selected_track_index: int = 0
var _last_track_headers_sig: String = ""
var _track_select_group: ButtonGroup
var _track_reorder_from: int = -1
var _track_drag_watch_running: bool = false
var _marker_rename_dialog_ref: Array = []
var _clip_clipboard: Dictionary = {}
var _view_handlers: CodaTimelineViewHandlers
var _timeline_edit_interaction_active: bool = false
var _timeline_preview_commit_pending: bool = false


func _ready() -> void:
	name = "Timeline"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 0)

	_toolbar_ui = CodaTimelineToolbar.new()
	_toolbar_ui.build(self)
	_wire_toolbar_signals()

	_preview = CodaTimelinePreviewBridge.new()

	_build_hints_row()
	_build_empty_state()
	_build_split_root()
	_build_validation_label()

	_preview.set_view(_view)
	_show_empty()
	set_process(true)


func get_authoring_event() -> CodaBrowserNode:
	return _selected_event


func get_timeline_view() -> CodaTimelineView:
	return _view


func get_timeline_preview() -> CodaTimelinePreviewBridge:
	return _preview


func get_selected_track_index() -> int:
	return _selected_track_index


func set_selected_track_index_value(idx: int) -> void:
	_selected_track_index = idx


func clear_track_headers_signature() -> void:
	_last_track_headers_sig = ""


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.disconnect(_on_project_structure_changed)
		if _project.project_dirty.is_connected(_on_project_project_dirty):
			_project.project_dirty.disconnect(_on_project_project_dirty)
	_project = project
	if _project != null:
		_project.structure_changed.connect(_on_project_structure_changed)
		_project.project_dirty.connect(_on_project_project_dirty)
	_refresh_view_state()


func attach_runtime(runtime: CodaRuntime) -> void:
	_preview.attach_runtime(runtime)


func get_selected_clip_id() -> String:
	if _view == null:
		return ""
	return _view.get_selected_clip_id()


func get_selected_track_id() -> String:
	if _selected_event == null or _selected_event.event_timeline == null:
		return ""
	var trs: Array[CodaTimelineTrack] = _selected_event.event_timeline.tracks
	if trs.is_empty():
		return ""
	var idx: int = clampi(_selected_track_index, 0, trs.size() - 1)
	return trs[idx].id


func grab_authoring_focus() -> void:
	if _view != null and _view.is_visible_in_tree():
		_view.grab_focus()


func is_showing_timeline_for_event(event_id: String) -> bool:
	if event_id.is_empty() or _selected_event == null or _selected_event.id != event_id:
		return false
	if _split_root == null or not _split_root.visible:
		return false
	return _selected_event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE


func stop_all_previews() -> void:
	_preview.stop_all_previews()


func set_external_playhead_seconds(seconds: float) -> void:
	_preview.set_external_playhead_seconds(seconds)


func on_browser_event_selected(node: Variant) -> void:
	var prev_event: CodaBrowserNode = _selected_event
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
	else:
		_selected_event = bn
		_selected_track_index = 0
	if prev_event != null and prev_event != _selected_event:
		_preview.stop_preview_for_event(prev_event.id)
	_last_track_headers_sig = ""
	_preview.set_selected_event(_selected_event)
	_track_reorder_from = -1
	_track_drag_watch_running = false
	_undo_stack.clear()
	_redo_stack.clear()
	if _view != null:
		_view.set_playhead(0.0)
		if prev_event != _selected_event:
			_view.clear_selection()
			if _selected_event != null:
				clip_selection_changed.emit(_selected_event.id, "")
			elif prev_event != null:
				clip_selection_changed.emit(prev_event.id, "")
	_refresh_view_state()


func _process(_delta: float) -> void:
	_preview.process_tick()


func reorder_tracks_drag_drop(from_i: int, to_i: int) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	if from_i == to_i:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	var snap: CodaEventTimeline = CodaTimelineCommands.reorder_tracks(t, from_i, to_i)
	if snap != null:
		_push_snapshot(snap)
	_selected_track_index = CodaTimelineCommands.selected_track_index_after_reorder(
		from_i, to_i, _selected_track_index
	)
	_selected_track_index = clampi(_selected_track_index, 0, max(0, t.tracks.size() - 1))
	if _view != null:
		_view.set_track_row_highlight(_selected_track_index)
	_last_track_headers_sig = ""
	_rebuild_track_headers()
	_notify_timeline_changed()
	_emit_track_selection_changed()


# ---------- UI build ----------

func _wire_toolbar_signals() -> void:
	_toolbar_ui.add_clip_pressed.connect(_on_add_clip_pressed)
	_toolbar_ui.split_clip_pressed.connect(_on_split_clip_toolbar_pressed)
	_toolbar_ui.add_marker_pressed.connect(_on_add_marker_pressed)
	_toolbar_ui.snap_picked.connect(_on_snap_picked)
	_toolbar_ui.bpm_changed.connect(_on_bpm_changed)
	_toolbar_ui.loop_toggled.connect(_on_loop_toggled)
	_toolbar_ui.length_changed.connect(_on_timeline_length_changed)
	_toolbar_ui.fit_length_pressed.connect(_on_fit_timeline_length_pressed)
	_toolbar_ui.zoom_fit_pressed.connect(_on_zoom_fit_pressed)
	_toolbar_ui.track_row_height_changed.connect(_on_track_row_height_changed)
	_toolbar_ui.switch_mode_pressed.connect(_on_switch_mode_pressed)


func _build_hints_row() -> void:
	_hints_label = Label.new()
	_hints_label.text = (
		"Wheel: zoom · Shift+wheel: scroll · MMB drag: pan · "
		+ "Space (focus here): play/pause from playhead · "
		+ "Reorder: hold LMB on left strip or track number, move vertically, release on target row"
	)
	_hints_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_hints_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE - 1)
	_hints_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hints_label)


func _build_empty_state() -> void:
	_empty_state = CodaEmptyStateScript.new()
	_empty_state.title_text = "No timeline"
	_empty_state.body_text = (
		"Pick an event in the Browser, then switch its authoring mode to Timeline to "
		+ "place clips on tracks."
	)
	_empty_state.action_text = "Switch to Timeline"
	_empty_state.action_triggered.connect(_on_empty_state_switch_pressed)
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_empty_state)


func _build_split_root() -> void:
	_track_select_group = ButtonGroup.new()
	_split_root = HSplitContainer.new()
	_split_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split_root.visible = false
	add_child(_split_root)

	_track_headers_column = VBoxContainer.new()
	_track_headers_column.custom_minimum_size = Vector2(96, 0)
	_track_headers_column.size_flags_horizontal = Control.SIZE_FILL
	_track_headers_column.add_theme_constant_override(&"separation", 0)
	_split_root.add_child(_track_headers_column)
	_split_root.split_offset = 208
	_split_root.resized.connect(_clamp_split_offset)

	_ruler_spacer = Control.new()
	_ruler_spacer.custom_minimum_size = Vector2(0, RULER_HEIGHT)
	_track_headers_column.add_child(_ruler_spacer)

	_track_headers_host = VBoxContainer.new()
	_track_headers_host.add_theme_constant_override(&"separation", 0)
	_track_headers_host.size_flags_horizontal = Control.SIZE_FILL
	_track_headers_column.add_child(_track_headers_host)

	_add_track_btn = Button.new()
	_add_track_btn.text = "+ Track"
	_add_track_btn.pressed.connect(_on_add_track_pressed)
	_track_headers_column.add_child(_add_track_btn)

	_view = CodaTimelineViewScript.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_handlers = CodaTimelineViewHandlersScript.new(self)
	_view_handlers.connect_view(_view)
	_split_root.add_child(_view)
	call_deferred("_clamp_split_offset")


func _build_validation_label() -> void:
	_validation_label = Label.new()
	_validation_label.add_theme_color_override(&"font_color", Tokens.DANGER)
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.visible = false
	add_child(_validation_label)


# ---------- State refresh ----------

func _clamp_split_offset() -> void:
	if _split_root == null:
		return
	var w: float = _split_root.size.x
	if w <= 4.0:
		return
	var max_w: float = minf(float(TRACK_HEADER_SPLIT_MAX_PX), w * TRACK_HEADER_SPLIT_MAX_FRACT)
	var min_w: float = float(TRACK_HEADER_SPLIT_MIN_PX)
	if min_w > max_w:
		min_w = max_w
	_split_root.split_offset = clampi(_split_root.split_offset, int(min_w), int(max_w))


func _on_track_row_height_changed(v: float) -> void:
	if _view == null:
		return
	_view.set_track_row_height(int(round(v)))
	_rebuild_track_headers(true)


func on_track_row_grip_pressed(track_index: int) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var n: int = _selected_event.event_timeline.tracks.size()
	if n <= 0 or _track_drag_watch_running:
		return
	_track_reorder_from = clampi(track_index, 0, n - 1)
	_track_drag_watch_running = true
	_run_track_row_drag_watch()


func _run_track_row_drag_watch() -> void:
	var from_i: int = _track_reorder_from
	while is_instance_valid(self) and visible and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		await get_tree().process_frame
	_track_drag_watch_running = false
	if not is_instance_valid(self):
		return
	var pos: Vector2 = get_global_mouse_position()
	_track_reorder_from = -1
	if from_i < 0:
		return
	var to_i: int = _track_index_at_screen_for_headers(pos)
	if to_i >= 0 and to_i != from_i:
		reorder_tracks_drag_drop(from_i, to_i)


func _track_index_at_screen_for_headers(screen_pos: Vector2) -> int:
	if _track_headers_host == null or _view == null:
		return -1
	if _selected_event == null or _selected_event.event_timeline == null:
		return -1
	var r: Rect2 = _track_headers_host.get_global_rect()
	if not r.has_point(screen_pos):
		return -1
	var local_y: float = screen_pos.y - r.position.y
	var row_h: float = float(_view.get_track_row_height())
	if row_h <= 1.0:
		return -1
	var idx: int = int(floor(local_y / row_h))
	return clampi(idx, 0, _selected_event.event_timeline.tracks.size() - 1)


func _on_project_project_dirty() -> void:
	if _selected_event == null or _split_root == null:
		return
	if _selected_event.event_authoring_mode != CodaBrowserNode.AuthoringMode.TIMELINE:
		return
	if not _split_root.visible:
		return
	_soft_refresh_timeline_after_param_edit()


func _soft_refresh_timeline_after_param_edit() -> void:
	if _selected_event == null or _view == null:
		return
	var t0: CodaEventTimeline = _selected_event.event_timeline
	if t0 == null:
		return
	_view.set_timeline(t0)
	_view.set_track_row_highlight(_selected_track_index)
	_rebuild_track_headers()
	_sync_toolbar_to_timeline()
	_update_validation()
	if _selected_event != null and not _timeline_edit_interaction_active:
		_preview.resync_preview_for_event(_selected_event.id)


func _on_project_structure_changed() -> void:
	if _selected_event == null:
		return
	_refresh_view_state()


func _refresh_view_state() -> void:
	if _selected_event == null:
		_show_empty(true)
		return
	if _selected_event.event_authoring_mode != CodaBrowserNode.AuthoringMode.TIMELINE:
		_preview.stop_preview_for_event(_selected_event.id)
		_show_empty(true, "Switch to Timeline")
		return
	if _selected_event.event_timeline == null:
		_selected_event.event_timeline = CodaEventTimeline.make_default()
	_show_timeline()


func _show_empty(reset_action_text: bool = false, action_text: String = "") -> void:
	if _empty_state != null:
		_empty_state.visible = true
		if reset_action_text:
			_empty_state.action_text = action_text
	if _split_root != null:
		_split_root.visible = false
	if _validation_label != null:
		_validation_label.visible = false
	_emit_timeline_fx_selection_cleared()


func _emit_timeline_fx_selection_cleared() -> void:
	if _selected_event == null:
		track_selection_changed.emit("", "")
		clip_selection_changed.emit("", "")
		return
	var ev_id: String = _selected_event.id
	track_selection_changed.emit(ev_id, "")
	clip_selection_changed.emit(ev_id, "")


func _show_timeline() -> void:
	if _empty_state != null:
		_empty_state.visible = false
	if _split_root != null:
		_split_root.visible = true
	var t0: CodaEventTimeline = _selected_event.event_timeline
	_selected_track_index = clampi(_selected_track_index, 0, max(0, t0.tracks.size() - 1))
	_view.set_timeline(t0)
	_view.set_track_row_highlight(_selected_track_index)
	_rebuild_track_headers()
	_sync_toolbar_to_timeline()
	_toolbar_ui.sync_track_row_spin_to_view(_view)
	_update_validation()


func _compute_track_headers_signature() -> String:
	if _selected_event == null or _selected_event.event_timeline == null:
		return ""
	var t: CodaEventTimeline = _selected_event.event_timeline
	var ids: PackedStringArray = PackedStringArray()
	for tr in t.tracks:
		ids.append("%s:%d" % [tr.id, tr.effects.size()])
	return "%d|%s|%d" % [t.tracks.size(), "|".join(ids), _selected_track_index]


func _rebuild_track_headers(force: bool = false) -> void:
	var sig: String = _compute_track_headers_signature()
	if not force and sig == _last_track_headers_sig:
		_sync_track_headers_from_data()
		return
	_last_track_headers_sig = sig
	for c in _track_headers_host.get_children():
		c.queue_free()
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	for i in _selected_event.event_timeline.tracks.size():
		var strip := _make_track_header(_selected_event.event_timeline.tracks[i], i)
		if strip != null and strip.has_method(&"set_selected"):
			strip.call(&"set_selected", i == _selected_track_index)
		_track_headers_host.add_child(strip)


func _sync_track_headers_from_data() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var tracks: Array[CodaTimelineTrack] = _selected_event.event_timeline.tracks
	var bus_entries: Array = _collect_bus_menu_entries()
	var children: Array = _track_headers_host.get_children()
	for i in mini(children.size(), tracks.size()):
		var strip: Node = children[i]
		if strip == null or not strip.has_method(&"sync_from_track"):
			continue
		strip.call(&"set_bus_submenu_entries", bus_entries)
		strip.call(&"sync_from_track")
		if strip.has_method(&"set_selected"):
			strip.call(&"set_selected", i == _selected_track_index)


func _make_track_header(track: CodaTimelineTrack, track_index: int) -> Control:
	var rh: int = _view.get_track_row_height()
	var strip := CodaTrackHeaderStripScript.new()
	strip.build_ui(track, track_index, rh, self, _track_select_group, _selected_track_index)
	strip.set_bus_submenu_entries(_collect_bus_menu_entries())
	strip.track_action_requested.connect(_on_track_header_action)
	return strip


func _collect_bus_menu_entries() -> Array:
	var out: Array = []
	out.append({"id": "", "label": "Inherit event bus"})
	if _project == null or _project.bus_root == null:
		return out
	for b in _project.bus_root.collect_flat():
		var nm: String = String(b.bus_name).strip_edges()
		if nm.is_empty():
			nm = "Bus"
		out.append({"id": b.id, "label": nm})
	return out


func _on_track_header_action(track_id: String, action: StringName, extra: Variant) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	var tr: CodaTimelineTrack = t.find_track(track_id)
	if tr == null:
		return
	match action:
		&"delete":
			_on_remove_track_pressed(track_id)
		&"duplicate":
			_duplicate_track_at_id(track_id)
		&"move_up":
			var iu: int = CodaTimelineCommands.track_index_by_id(t, track_id)
			if iu > 0:
				reorder_tracks_drag_drop(iu, iu - 1)
		&"move_down":
			var idn: int = CodaTimelineCommands.track_index_by_id(t, track_id)
			if idn >= 0 and idn < t.tracks.size() - 1:
				reorder_tracks_drag_drop(idn, idn + 1)
		&"move_top":
			var it: int = CodaTimelineCommands.track_index_by_id(t, track_id)
			if it > 0:
				reorder_tracks_drag_drop(it, 0)
		&"move_bottom":
			var ib: int = CodaTimelineCommands.track_index_by_id(t, track_id)
			var last_i: int = t.tracks.size() - 1
			if ib >= 0 and ib < last_i:
				reorder_tracks_drag_drop(ib, last_i)
		&"reset_volume":
			_apply_mutation(CodaTimelineCommands.apply_track_volume_reset(t, tr))
		&"set_output_bus":
			_apply_mutation(CodaTimelineCommands.apply_track_output_bus(t, tr, str(extra)))
		&"set_color":
			_apply_mutation(CodaTimelineCommands.apply_track_color(t, tr, extra as Color))
			if _view != null:
				_view.queue_redraw()
		&"show_track_effects":
			_set_selected_track_index(int(extra), true)
			track_effects_focus_requested.emit(track_id)
		_:
			pass


func _duplicate_track_at_id(track_id: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	var result: Dictionary = CodaTimelineCommands.duplicate_track(t, track_id)
	var snap: CodaEventTimeline = result.get("snapshot") as CodaEventTimeline
	var new_i: int = int(result.get("new_index", -1))
	if snap == null or new_i < 0:
		return
	_push_snapshot(snap)
	_selected_track_index = new_i
	if _view != null:
		_view.set_track_row_highlight(_selected_track_index)
	_last_track_headers_sig = ""
	_rebuild_track_headers()
	_notify_timeline_changed()
	_emit_track_selection_changed()


func _emit_track_selection_changed() -> void:
	if _selected_event == null:
		return
	var ev_id: String = _selected_event.id
	if _selected_event.event_timeline == null or _selected_event.event_timeline.tracks.is_empty():
		track_selection_changed.emit(ev_id, "")
		return
	var trs: Array[CodaTimelineTrack] = _selected_event.event_timeline.tracks
	var idx: int = clampi(_selected_track_index, 0, trs.size() - 1)
	track_selection_changed.emit(ev_id, trs[idx].id)



func _sync_toolbar_to_timeline() -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	_toolbar_ui.sync_from_timeline(
		_selected_event.event_timeline, int(_view.get_snap_mode())
	)


func _update_validation() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		_validation_label.visible = false
		return
	var msg: String = CodaTimelineCommands.validate(_selected_event.event_timeline)
	if msg.is_empty():
		_validation_label.visible = false
		_validation_label.text = ""
	else:
		_validation_label.text = msg
		_validation_label.visible = true


func begin_timeline_edit_interaction() -> void:
	_timeline_edit_interaction_active = true
	_timeline_preview_commit_pending = false


func commit_timeline_edit_interaction() -> void:
	_timeline_edit_interaction_active = false
	_commit_timeline_preview()
	_timeline_preview_commit_pending = false


func _commit_timeline_preview() -> void:
	if _selected_event == null:
		return
	_preview.commit_transport_for_event(_selected_event.id, _view)


func _notify_timeline_changed() -> void:
	if _project == null or _selected_event == null:
		return
	_project.notify_event_timeline_changed(_selected_event.id)
	if _timeline_edit_interaction_active:
		_timeline_preview_commit_pending = true
	else:
		_commit_timeline_preview()
	_update_validation()
	if _selected_event.event_timeline != null:
		_toolbar_ui.sync_length_spin(_selected_event.event_timeline.length_seconds)
	if _view != null:
		_view.queue_redraw()


# ---------- Toolbar handlers ----------

func _on_snap_picked(mode: int) -> void:
	if _view != null:
		_view.set_snap_mode(mode as CodaTimelineView.SnapMode)


func _on_bpm_changed(v: float) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	CodaTimelineCommands.set_bpm(_selected_event.event_timeline, v)
	_notify_timeline_changed()


func _on_loop_toggled(on: bool) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	CodaTimelineCommands.set_loop_enabled(_selected_event.event_timeline, on)
	_notify_timeline_changed()


func _on_timeline_length_changed(value: float) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var snap: CodaEventTimeline = CodaTimelineCommands.set_timeline_length(
		_selected_event.event_timeline, value
	)
	_apply_mutation(snap)


func _on_fit_timeline_length_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	_apply_mutation(
		CodaTimelineCommands.fit_timeline_length(_selected_event.event_timeline)
	)


func _on_switch_mode_pressed() -> void:
	if _project == null or _selected_event == null:
		return
	_project.set_event_authoring_mode(
		_selected_event.id, CodaBrowserNode.AuthoringMode.GRAPH
	)


func _on_empty_state_switch_pressed() -> void:
	if _project == null or _selected_event == null:
		return
	_project.set_event_authoring_mode(
		_selected_event.id, CodaBrowserNode.AuthoringMode.TIMELINE
	)


func _on_add_clip_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	_apply_mutation(
		CodaTimelineCommands.add_clip(
			_selected_event.event_timeline,
			_selected_track_index,
			_view.get_playhead()
		)
	)


func _on_add_marker_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	_apply_mutation(
		CodaTimelineCommands.add_marker(
			_selected_event.event_timeline, _view.get_playhead()
		)
	)


func _on_add_track_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	_apply_mutation(CodaTimelineCommands.add_track(_selected_event.event_timeline))


func _on_remove_track_pressed(track_id: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	var result: Dictionary = CodaTimelineCommands.remove_track(t, track_id)
	var snap: CodaEventTimeline = result.get("snapshot") as CodaEventTimeline
	if snap != null:
		_push_snapshot(snap)
	if not bool(result.get("success", false)):
		_undo_timeline()
		return
	if t.tracks.is_empty():
		_selected_track_index = 0
	else:
		_selected_track_index = clampi(_selected_track_index, 0, t.tracks.size() - 1)
	if _view != null:
		_view.set_track_row_highlight(_selected_track_index)
	_notify_timeline_changed()


func _set_selected_track_index(idx: int, track_only: bool = false) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var n: int = _selected_event.event_timeline.tracks.size()
	if n <= 0:
		return
	idx = clampi(idx, 0, n - 1)
	var track_changed: bool = _selected_track_index != idx
	if not track_changed and not track_only:
		return
	if not track_changed and track_only:
		if _view != null and not _view.get_selected_clip_id().is_empty():
			_view.clear_selection()
			_emit_track_selection_changed()
		return
	_selected_track_index = idx
	if _view != null:
		if track_changed or track_only:
			_view.clear_selection()
		_view.set_track_row_highlight(idx)
	_rebuild_track_headers()
	_emit_track_selection_changed()


func _sync_track_index_for_clip(track_idx: int) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var n: int = _selected_event.event_timeline.tracks.size()
	if n <= 0:
		return
	track_idx = clampi(track_idx, 0, n - 1)
	if _selected_track_index == track_idx:
		return
	_selected_track_index = track_idx
	if _view != null:
		_view.set_track_row_highlight(track_idx)
	_rebuild_track_headers()


func _open_marker_rename(marker_id: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var m: CodaTimelineMarker = _selected_event.event_timeline.find_marker(marker_id)
	if m == null:
		return
	CodaTimelineMarkerUiScript.open_rename_dialog(
		self,
		m,
		func(new_name: String) -> void:
			_apply_mutation(
				CodaTimelineCommands.rename_marker(_selected_event.event_timeline, m, new_name)
			),
		_marker_rename_dialog_ref
	)


func _delete_marker(marker_id: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	var result: Dictionary = CodaTimelineCommands.delete_marker(
		_selected_event.event_timeline, marker_id
	)
	var snap: CodaEventTimeline = result.get("snapshot") as CodaEventTimeline
	if snap != null:
		_push_snapshot(snap)
	if bool(result.get("success", false)):
		if _view.get_selected_marker_id() == marker_id:
			_view.clear_marker_selection()
		_notify_timeline_changed()


func _unhandled_key_input(event: InputEvent) -> void:
	if _split_root == null or not _split_root.visible:
		return
	var fo: Control = get_viewport().gui_get_focus_owner() as Control
	if fo == null or not is_ancestor_of(fo):
		return
	if fo is LineEdit or fo is TextEdit:
		return
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.ctrl_pressed and not k.alt_pressed and k.keycode == KEY_Z and not k.shift_pressed:
			_undo_timeline()
			get_viewport().set_input_as_handled()
			return
		if k.ctrl_pressed and not k.alt_pressed and (k.keycode == KEY_Y or (k.keycode == KEY_Z and k.shift_pressed)):
			_redo_timeline()
			get_viewport().set_input_as_handled()
			return
		if _view != null and not _view.get_selected_clip_id().is_empty():
			if k.ctrl_pressed and not k.alt_pressed and k.keycode == KEY_C:
				_copy_selected_clip()
				get_viewport().set_input_as_handled()
				return
			if k.ctrl_pressed and not k.alt_pressed and k.keycode == KEY_X:
				_cut_selected_clip()
				get_viewport().set_input_as_handled()
				return
		if k.ctrl_pressed and not k.alt_pressed and k.keycode == KEY_V:
			_paste_clip_at_playhead()
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_F2 and _view != null and not _view.get_selected_marker_id().is_empty():
			_open_marker_rename(_view.get_selected_marker_id())
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE:
			if request_timeline_delete():
				get_viewport().set_input_as_handled()
				return


func request_timeline_delete() -> bool:
	if _split_root == null or not _split_root.visible or _view == null:
		return false
	if _selected_event == null or _selected_event.event_timeline == null:
		return false
	if (
		not _view.get_selected_clip_id().is_empty()
		or not _view.get_selected_marker_id().is_empty()
	):
		return _try_delete_timeline_selection()
	if not _timeline_has_keyboard_focus():
		return false
	return _try_delete_timeline_selection()


func _timeline_has_keyboard_focus() -> bool:
	var fo: Control = get_viewport().gui_get_focus_owner() as Control
	if fo == null or not is_ancestor_of(fo):
		return false
	if fo is LineEdit or fo is TextEdit:
		return false
	return true


func _try_delete_timeline_selection() -> bool:
	if _view == null or _selected_event == null or _selected_event.event_timeline == null:
		return false
	var marker_id: String = _view.get_selected_marker_id()
	if not marker_id.is_empty():
		_delete_marker(marker_id)
		return true
	var clip_id: String = _view.get_selected_clip_id()
	if not clip_id.is_empty():
		_delete_selected_clip()
		return true
	var track_id: String = get_selected_track_id()
	if not track_id.is_empty():
		_on_remove_track_pressed(track_id)
		return true
	return false


func _delete_selected_clip() -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	var cid: String = _view.get_selected_clip_id()
	if cid.is_empty():
		return
	var snap: CodaEventTimeline = CodaTimelineCommands.delete_clip(
		_selected_event.event_timeline, cid
	)
	if snap == null:
		return
	_push_snapshot(snap)
	_view.clear_selection()
	clip_selection_changed.emit(_selected_event.id, "")
	_notify_timeline_changed()


func _push_snapshot(snap: CodaEventTimeline) -> void:
	CodaTimelineUndo.push_undo(_undo_stack, _redo_stack, snap)


func _apply_mutation(snap: CodaEventTimeline) -> void:
	if snap != null:
		_push_snapshot(snap)
	_notify_timeline_changed()


func _restore_timeline_from(source: CodaEventTimeline) -> void:
	if _selected_event == null or source == null:
		return
	_preview.stop_before_timeline_restore(_selected_event.id)
	_selected_event.event_timeline = source.clone_keep_ids()
	_show_timeline()
	_notify_timeline_changed()


func _undo_timeline() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var past: CodaEventTimeline = CodaTimelineUndo.pop_undo(
		_undo_stack, _redo_stack, _selected_event.event_timeline
	)
	if past == null:
		return
	_restore_timeline_from(past)


func _redo_timeline() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var fut: CodaEventTimeline = CodaTimelineUndo.pop_redo(
		_undo_stack, _redo_stack, _selected_event.event_timeline
	)
	if fut == null:
		return
	_restore_timeline_from(fut)



func _on_zoom_fit_pressed() -> void:
	if _view == null:
		return
	_view.zoom_timeline_to_fit(_view.size.x)


func _on_split_clip_toolbar_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	var cid: String = _view.get_selected_clip_id()
	if cid.is_empty():
		NexusCodaLog.warn("timeline", "Select a clip before splitting.")
		return
	_run_split_command(cid, _view.get_playhead())



func _run_split_command(clip_id: String, split_t: float) -> void:
	var result: Dictionary = CodaTimelineCommands.split_clip_at_time(
		_selected_event.event_timeline, clip_id, split_t
	)
	_apply_split_or_duplicate_result(result)


func _apply_split_or_duplicate_result(result: Dictionary) -> void:
	var snap: CodaEventTimeline = result.get("snapshot") as CodaEventTimeline
	var err: String = String(result.get("error", ""))
	if snap != null:
		_push_snapshot(snap)
	if not err.is_empty():
		_undo_timeline()
		NexusCodaLog.warn("timeline", err)
		return
	_notify_timeline_changed()



func _copy_selected_clip() -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	var cid: String = _view.get_selected_clip_id()
	if cid.is_empty():
		return
	var data: Dictionary = CodaTimelineCommands.clip_copy_data(
		_selected_event.event_timeline, cid
	)
	if data.is_empty():
		return
	_clip_clipboard = data


func _cut_selected_clip() -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	var cid: String = _view.get_selected_clip_id()
	if cid.is_empty():
		return
	var result: Dictionary = CodaTimelineCommands.cut_clip(
		_selected_event.event_timeline, cid
	)
	var data: Dictionary = result.get("data", {}) as Dictionary
	if data.is_empty():
		return
	_clip_clipboard = data
	var snap: CodaEventTimeline = result.get("snapshot") as CodaEventTimeline
	if snap != null:
		_push_snapshot(snap)
	_view.clear_selection()
	_notify_timeline_changed()


func _paste_clip_at_playhead() -> void:
	if _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	if _clip_clipboard.is_empty():
		return
	var result: Dictionary = CodaTimelineCommands.paste_clip_at_playhead(
		_selected_event.event_timeline,
		_selected_track_index,
		_view.get_playhead(),
		_clip_clipboard
	)
	var snap: CodaEventTimeline = result.get("snapshot") as CodaEventTimeline
	var err: String = String(result.get("error", ""))
	if snap != null:
		_push_snapshot(snap)
	if not err.is_empty():
		if snap != null:
			_undo_timeline()
		NexusCodaLog.warn("timeline", err)
		return
	var new_id: String = String(result.get("clip_id", ""))
	if not new_id.is_empty():
		_view.set_selected_clip(new_id)
		clip_selection_changed.emit(_selected_event.id, new_id)
	_notify_timeline_changed()
