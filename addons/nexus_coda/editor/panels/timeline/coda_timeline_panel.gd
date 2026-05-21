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

const RULER_HEIGHT := CodaTimelineViewScript.RULER_HEIGHT
const MAX_TIMELINE_UNDO := 40
const TRACK_HEADER_SPLIT_MIN_PX := 120
const TRACK_HEADER_SPLIT_MAX_PX := 280
const TRACK_HEADER_SPLIT_MAX_FRACT := 0.34

signal track_effects_focus_requested(track_id: String)
signal track_selection_changed(event_id: String, track_id: String)
signal clip_selection_changed(event_id: String, clip_id: String)

var _project: CodaState = null
var _runtime: CodaRuntime = null
var _selected_event: CodaBrowserNode = null
var _live_handle: CodaEventHandle = null

var _toolbar: HBoxContainer
var _empty_state: CodaEmptyState
var _split_root: HSplitContainer
var _track_headers_column: VBoxContainer
var _ruler_spacer: Control
var _track_headers_host: VBoxContainer
var _add_track_btn: Button

var _view: CodaTimelineView

var _snap_picker: OptionButton
var _bpm_spin: SpinBox
var _loop_toggle: CheckBox
var _length_spin: SpinBox
var _fit_length_btn: Button
var _add_marker_btn: Button
var _add_clip_btn: Button
var _switch_mode_btn: Button

var _validation_label: Label

var _suppress_writeback: bool = false
var _selected_track_index: int = 0
var _last_track_headers_sig: String = ""
var _track_select_group: ButtonGroup
var _undo_stack: Array[CodaEventTimeline] = []
var _redo_stack: Array[CodaEventTimeline] = []

var _split_clip_btn: Button
var _zoom_fit_btn: Button
var _hints_label: Label
var _track_row_spin: SpinBox
var _suppress_track_row_spin: bool = false
var _track_reorder_from: int = -1
var _track_drag_watch_running: bool = false


func _ready() -> void:
	name = "Timeline"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 0)

	_build_toolbar()
	_build_hints_row()
	_build_empty_state()
	_build_split_root()
	_build_validation_label()

	_show_empty()
	set_process(true)


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
	if _runtime != null and is_instance_valid(_runtime):
		if _runtime.voice_finished.is_connected(_on_runtime_voice_finished):
			_runtime.voice_finished.disconnect(_on_runtime_voice_finished)
	_runtime = runtime
	if _runtime != null:
		_runtime.voice_finished.connect(_on_runtime_voice_finished)


func get_selected_clip_id() -> String:
	if _view == null:
		return ""
	return _view.get_selected_clip_id()


func _on_runtime_voice_finished(handle: CodaEventHandle) -> void:
	if _live_handle == handle:
		_live_handle = null
		if _view != null:
			_view.set_playhead(0.0)


func _process(_delta: float) -> void:
	if _selected_event == null or _view == null:
		return
	if _selected_event.event_authoring_mode != CodaBrowserNode.AuthoringMode.TIMELINE:
		return
	if _runtime == null:
		return
	if _live_handle == null or not is_instance_valid(_live_handle) or not _live_handle.is_playing():
		_live_handle = _runtime.get_active_timeline_handle_for_event(_selected_event.id)
	if _live_handle != null and _live_handle.is_timeline:
		if not _live_handle.is_paused():
			_view.set_playhead(_live_handle.timeline_cursor_seconds)


func on_browser_event_selected(node: Variant) -> void:
	var prev_event: CodaBrowserNode = _selected_event
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
	else:
		_selected_event = bn
		_selected_track_index = 0
	if prev_event != null and prev_event != _selected_event:
		_stop_timeline_preview_for_event_id(prev_event.id)
	_last_track_headers_sig = ""
	# Active handle becomes stale when the visible event changes; the next process tick re-resolves.
	_live_handle = null
	_track_reorder_from = -1
	_track_drag_watch_running = false
	_undo_stack.clear()
	_redo_stack.clear()
	if _view != null:
		_view.set_playhead(0.0)
	_refresh_view_state()


# ---------- UI build ----------

func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	add_child(_toolbar)

	_add_clip_btn = Button.new()
	_add_clip_btn.text = "+ Clip"
	_add_clip_btn.tooltip_text = (
		"Add an empty clip on the selected track (highlighted lane / track header) at the playhead"
	)
	_add_clip_btn.pressed.connect(_on_add_clip_pressed)
	_toolbar.add_child(_add_clip_btn)

	_split_clip_btn = Button.new()
	_split_clip_btn.text = "Split"
	_split_clip_btn.tooltip_text = (
		"Split the selected clip at the playhead (clip must be selected; playhead inside clip)"
	)
	_split_clip_btn.pressed.connect(_on_split_clip_toolbar_pressed)
	_toolbar.add_child(_split_clip_btn)

	_add_marker_btn = Button.new()
	_add_marker_btn.text = "+ Marker"
	_add_marker_btn.tooltip_text = "Add a marker at the current playhead"
	_add_marker_btn.pressed.connect(_on_add_marker_pressed)
	_toolbar.add_child(_add_marker_btn)

	_toolbar.add_child(VSeparator.new())

	var snap_label := Label.new()
	snap_label.text = "Snap:"
	snap_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	snap_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_toolbar.add_child(snap_label)

	_snap_picker = OptionButton.new()
	_snap_picker.add_item("None", CodaTimelineView.SnapMode.NONE)
	_snap_picker.add_item("0.1 s", CodaTimelineView.SnapMode.TENTHS)
	_snap_picker.add_item("Bars/Beats", CodaTimelineView.SnapMode.BARS_BEATS)
	_snap_picker.item_selected.connect(_on_snap_picked)
	_toolbar.add_child(_snap_picker)

	var bpm_label := Label.new()
	bpm_label.text = "BPM:"
	bpm_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	bpm_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_toolbar.add_child(bpm_label)

	_bpm_spin = SpinBox.new()
	_bpm_spin.min_value = 0.0
	_bpm_spin.max_value = 999.0
	_bpm_spin.step = 1.0
	_bpm_spin.tooltip_text = "0 disables the bars/beats grid"
	_bpm_spin.value_changed.connect(_on_bpm_changed)
	_toolbar.add_child(_bpm_spin)

	_loop_toggle = CheckBox.new()
	_loop_toggle.text = "Loop"
	_loop_toggle.tooltip_text = "Enable the loop region inside the timeline"
	_loop_toggle.toggled.connect(_on_loop_toggled)
	_toolbar.add_child(_loop_toggle)

	_toolbar.add_child(VSeparator.new())

	var len_lbl := Label.new()
	len_lbl.text = "Length (s):"
	len_lbl.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	len_lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_toolbar.add_child(len_lbl)

	_length_spin = SpinBox.new()
	_length_spin.min_value = 0.5
	_length_spin.max_value = 3600.0
	_length_spin.step = 0.5
	_length_spin.tooltip_text = "Timeline length in seconds (session end). Clips cannot extend past this."
	_length_spin.value_changed.connect(_on_timeline_length_spin_changed)
	_toolbar.add_child(_length_spin)

	_fit_length_btn = Button.new()
	_fit_length_btn.text = "Fit length"
	_fit_length_btn.tooltip_text = "Set length to the end of the last clip/marker (plus a small margin)"
	_fit_length_btn.pressed.connect(_on_fit_timeline_length_pressed)
	_toolbar.add_child(_fit_length_btn)

	_zoom_fit_btn = Button.new()
	_zoom_fit_btn.text = "Zoom to fit"
	_zoom_fit_btn.tooltip_text = "Zoom the timeline view so the full session length fits horizontally"
	_zoom_fit_btn.pressed.connect(_on_zoom_fit_pressed)
	_toolbar.add_child(_zoom_fit_btn)

	_toolbar.add_child(VSeparator.new())

	var row_h_lbl := Label.new()
	row_h_lbl.text = "Row px:"
	row_h_lbl.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	row_h_lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_toolbar.add_child(row_h_lbl)

	_track_row_spin = SpinBox.new()
	_track_row_spin.min_value = CodaTimelineView.MIN_TRACK_ROW_HEIGHT
	_track_row_spin.max_value = CodaTimelineView.MAX_TRACK_ROW_HEIGHT
	_track_row_spin.step = 2.0
	_track_row_spin.value = CodaTimelineView.DEFAULT_TRACK_ROW_HEIGHT
	_track_row_spin.tooltip_text = "Pixel height of each track row (header + lane), like a DAW track height control"
	_track_row_spin.value_changed.connect(_on_track_row_height_spin_changed)
	_toolbar.add_child(_track_row_spin)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(spacer)

	_switch_mode_btn = Button.new()
	_switch_mode_btn.text = "Switch to Graph"
	_switch_mode_btn.tooltip_text = "Use the Event-Graph authoring model instead of the timeline"
	_switch_mode_btn.pressed.connect(_on_switch_mode_pressed)
	_toolbar.add_child(_switch_mode_btn)


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
	_view.clip_moved.connect(_on_view_clip_moved)
	_view.clip_resized.connect(_on_view_clip_resized)
	_view.clip_delete_requested.connect(_on_view_clip_delete_requested)
	_view.browser_asset_dropped.connect(_on_view_browser_asset_dropped)
	_view.marker_changed.connect(_on_view_marker_changed)
	_view.loop_region_changed.connect(_on_view_loop_region_changed)
	_view.playhead_seek_requested.connect(_on_view_playhead_seek_requested)
	_view.marker_double_clicked.connect(_on_view_marker_double_clicked)
	_view.track_row_selected.connect(_on_view_track_row_selected)
	_view.clip_audio_assign_requested.connect(_on_view_clip_audio_assign_requested)
	_view.timeline_interaction_started.connect(_on_view_timeline_interaction_started)
	_view.clip_duplicate_requested.connect(_on_view_clip_duplicate_requested)
	_view.clip_split_at_playhead_requested.connect(_on_view_clip_split_at_playhead_requested)
	_view.audition_requested.connect(_on_view_audition_requested)
	_view.clip_selected.connect(_on_view_clip_selected_for_effects_panel)
	_view.selection_cleared.connect(_on_view_clip_selection_cleared_for_effects_panel)
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


func _sync_track_row_spin_to_view() -> void:
	if _track_row_spin == null or _view == null:
		return
	_suppress_track_row_spin = true
	_track_row_spin.min_value = CodaTimelineView.MIN_TRACK_ROW_HEIGHT
	_track_row_spin.max_value = CodaTimelineView.MAX_TRACK_ROW_HEIGHT
	_track_row_spin.value = _view.get_track_row_height()
	_suppress_track_row_spin = false


func _on_track_row_height_spin_changed(v: float) -> void:
	if _suppress_track_row_spin or _view == null:
		return
	_view.set_track_row_height(int(round(v)))
	_rebuild_track_headers(true)


func on_track_row_grip_pressed(track_index: int) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var n: int = _selected_event.event_timeline.tracks.size()
	if n <= 0:
		return
	if _track_drag_watch_running:
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


func _on_project_structure_changed() -> void:
	_refresh_view_state()
	# Clip/track effect add/remove/reorder emits structure_changed; reprime preview voices so
	# runtime FX buses match the edited chains (layout_sig includes effect fingerprints).
	if (
		_selected_event != null
		and _split_root != null
		and _split_root.visible
		and _selected_event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE
	):
		_notify_timeline_changed()


func _stop_timeline_preview_for_event_id(event_id: String) -> void:
	if _runtime == null or event_id.is_empty():
		return
	var h: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(event_id)
	if h != null:
		_runtime.stop(h)
	if _live_handle == h:
		_live_handle = null


func _refresh_view_state() -> void:
	if _selected_event == null:
		_show_empty(true)
		return
	if _selected_event.event_authoring_mode != CodaBrowserNode.AuthoringMode.TIMELINE:
		_stop_timeline_preview_for_event_id(_selected_event.id)
		_show_empty(true, "Switch to Timeline")
		return
	if _selected_event.event_timeline == null:
		_show_empty(true, "Switch to Timeline")
		return
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
	_sync_track_row_spin_to_view()
	_update_validation()
	_emit_track_selection_changed()


## Signature covers only **structural** properties — adding/removing/reordering tracks, or
## changing the selected row. Live edits (volume, mute/solo, color, name, output bus, effect
## param values) are pushed into the existing strip via [method _sync_track_headers_from_data]
## so the slider/widget under the user's cursor is never freed mid-drag.
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
		_track_headers_host.add_child(
			_make_track_header(_selected_event.event_timeline.tracks[i], i)
		)


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


func reorder_tracks_drag_drop(from_i: int, to_i: int) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	if from_i == to_i:
		return
	_push_timeline_undo()
	var t: CodaEventTimeline = _selected_event.event_timeline
	var sel: int = _selected_track_index
	t.reorder_tracks_move(from_i, to_i)
	if sel == from_i:
		_selected_track_index = to_i
	elif from_i < sel and to_i >= sel:
		_selected_track_index -= 1
	elif from_i > sel and to_i <= sel:
		_selected_track_index += 1
	_selected_track_index = clampi(_selected_track_index, 0, max(0, t.tracks.size() - 1))
	if _view != null:
		_view.set_track_row_highlight(_selected_track_index)
	_last_track_headers_sig = ""
	_rebuild_track_headers()
	_notify_timeline_changed()
	_emit_track_selection_changed()


func _make_track_header(track: CodaTimelineTrack, track_index: int) -> Control:
	var rh: int = _view.get_track_row_height()
	var strip := CodaTrackHeaderStripScript.new()
	strip.build_ui(track, track_index, rh, self, _track_select_group, _selected_track_index)
	strip.set_bus_submenu_entries(_collect_bus_menu_entries())
	strip.track_action_requested.connect(_on_track_header_action)
	return strip


func _bus_picker_label_for(bus_id: String) -> String:
	if bus_id.is_empty() or _project == null or _project.bus_root == null:
		return "→ event bus"
	var b: CodaBus = _project.bus_root.find_by_id(bus_id)
	if b == null:
		return "→ ?"
	return "→ %s" % b.bus_name


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


func _track_index_by_id(timeline: CodaEventTimeline, track_id: String) -> int:
	for idx in range(timeline.tracks.size()):
		if timeline.tracks[idx].id == track_id:
			return idx
	return -1


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
			var iu: int = _track_index_by_id(t, track_id)
			if iu > 0:
				reorder_tracks_drag_drop(iu, iu - 1)
		&"move_down":
			var idn: int = _track_index_by_id(t, track_id)
			if idn >= 0 and idn < t.tracks.size() - 1:
				reorder_tracks_drag_drop(idn, idn + 1)
		&"move_top":
			var it: int = _track_index_by_id(t, track_id)
			if it > 0:
				reorder_tracks_drag_drop(it, 0)
		&"move_bottom":
			var ib: int = _track_index_by_id(t, track_id)
			var last_i: int = t.tracks.size() - 1
			if ib >= 0 and ib < last_i:
				reorder_tracks_drag_drop(ib, last_i)
		&"reset_volume":
			_push_timeline_undo()
			tr.volume_db = 0.0
			_notify_timeline_changed()
		&"set_output_bus":
			_push_timeline_undo()
			tr.output_bus_id = str(extra)
			_notify_timeline_changed()
		&"set_color":
			_push_timeline_undo()
			tr.color = extra as Color
			if _view != null:
				_view.queue_redraw()
			_notify_timeline_changed()
		&"show_track_effects":
			_set_selected_track_index(int(extra))
			track_effects_focus_requested.emit(track_id)
		_:
			pass


func _duplicate_track_at_id(track_id: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	var src_i: int = _track_index_by_id(t, track_id)
	if src_i < 0:
		return
	_push_timeline_undo()
	var d: Dictionary = t.tracks[src_i].to_dictionary()
	d.erase("id")
	var clips_raw: Variant = d.get("clips", [])
	var new_clips: Array = []
	if clips_raw is Array:
		for c in clips_raw as Array:
			if c is Dictionary:
				var cd: Dictionary = (c as Dictionary).duplicate()
				cd.erase("id")
				new_clips.append(cd)
	d["clips"] = new_clips
	var new_tr: CodaTimelineTrack = CodaTimelineTrack.from_dictionary(d)
	new_tr.track_name = t.tracks[src_i].track_name + " copy"
	t.tracks.insert(src_i + 1, new_tr)
	_selected_track_index = src_i + 1
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


func _on_view_clip_selected_for_effects_panel(clip_id: String) -> void:
	if _selected_event == null:
		return
	clip_selection_changed.emit(_selected_event.id, clip_id)


func _on_view_clip_selection_cleared_for_effects_panel() -> void:
	if _selected_event == null:
		return
	clip_selection_changed.emit(_selected_event.id, "")


func _sync_toolbar_to_timeline() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	_suppress_writeback = true
	_loop_toggle.button_pressed = t.loop_enabled
	_bpm_spin.value = t.tempo_bpm
	if _length_spin != null:
		_length_spin.value = t.length_seconds
	for i in _snap_picker.item_count:
		if _snap_picker.get_item_id(i) == int(_view.get_snap_mode()):
			_snap_picker.select(i)
			break
	_suppress_writeback = false


func _update_validation() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		_validation_label.visible = false
		return
	var msg: String = _selected_event.event_timeline.validate()
	if msg.is_empty():
		_validation_label.visible = false
		_validation_label.text = ""
	else:
		_validation_label.text = msg
		_validation_label.visible = true


func _notify_timeline_changed() -> void:
	if _project == null or _selected_event == null:
		return
	_project.notify_event_timeline_changed(_selected_event.id)
	if _runtime != null:
		_runtime.resync_timeline_preview_for_event(_selected_event.id)
	_update_validation()
	if _length_spin != null and _selected_event.event_timeline != null:
		_suppress_writeback = true
		_length_spin.value = _selected_event.event_timeline.length_seconds
		_suppress_writeback = false
	_view.queue_redraw()


# ---------- Toolbar handlers ----------

func _on_snap_picked(idx: int) -> void:
	if _suppress_writeback:
		return
	var sid: int = _snap_picker.get_item_id(idx)
	_view.set_snap_mode(sid as CodaTimelineView.SnapMode)


func _on_bpm_changed(v: float) -> void:
	if _suppress_writeback or _selected_event == null or _selected_event.event_timeline == null:
		return
	_selected_event.event_timeline.tempo_bpm = v
	_notify_timeline_changed()


func _on_loop_toggled(on: bool) -> void:
	if _suppress_writeback or _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	t.loop_enabled = on
	if on and t.loop_end_seconds <= t.loop_start_seconds:
		t.loop_start_seconds = 0.0
		t.loop_end_seconds = t.length_seconds
	_notify_timeline_changed()


func _on_timeline_length_spin_changed(value: float) -> void:
	if _suppress_writeback or _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	t.length_seconds = maxf(0.5, value)
	_clamp_clips_to_timeline_length(t)
	if t.loop_enabled:
		t.loop_start_seconds = clampf(t.loop_start_seconds, 0.0, t.length_seconds)
		t.loop_end_seconds = clampf(t.loop_end_seconds, t.loop_start_seconds + 0.01, t.length_seconds)
	_notify_timeline_changed()


func _on_fit_timeline_length_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	_push_timeline_undo()
	var t: CodaEventTimeline = _selected_event.event_timeline
	var need: float = _timeline_content_end_seconds(t)
	var margin: float = 0.25
	t.length_seconds = maxf(0.5, need + margin)
	_clamp_clips_to_timeline_length(t)
	if t.loop_enabled:
		t.loop_end_seconds = minf(t.loop_end_seconds, t.length_seconds)
	_notify_timeline_changed()


func _timeline_content_end_seconds(t: CodaEventTimeline) -> float:
	var need: float = 0.0
	for tr in t.tracks:
		for c in tr.clips:
			need = maxf(need, c.start_seconds + c.duration_seconds)
	for m in t.markers:
		need = maxf(need, m.time_seconds)
	if t.loop_enabled:
		need = maxf(need, t.loop_end_seconds)
	return need


func _extend_timeline_if_content_exceeds() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	var need: float = _timeline_content_end_seconds(t)
	var margin: float = 0.25
	if need > t.length_seconds + 0.0001:
		t.length_seconds = need + margin


func _clamp_clips_to_timeline_length(t: CodaEventTimeline) -> void:
	for tr in t.tracks:
		for c in tr.clips:
			if c.start_seconds >= t.length_seconds:
				c.start_seconds = maxf(0.0, t.length_seconds - 0.05)
			# Use true remaining time — never assume a 0.05s floor here or clips can still
			# extend past `length_seconds` when the gap to the end is under 0.05s.
			var room: float = maxf(0.0, t.length_seconds - c.start_seconds)
			var max_src: float = c.max_source_playable_seconds()
			var max_d: float = minf(room, max_src)
			c.duration_seconds = minf(c.duration_seconds, max_d)


func _set_selected_track_index(idx: int) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var n: int = _selected_event.event_timeline.tracks.size()
	if n <= 0:
		return
	idx = clampi(idx, 0, n - 1)
	if _selected_track_index == idx:
		return
	_selected_track_index = idx
	if _view != null:
		_view.set_track_row_highlight(idx)
	_rebuild_track_headers()
	_emit_track_selection_changed()


func _on_view_track_row_selected(track_index: int) -> void:
	_set_selected_track_index(track_index)


func _on_view_clip_audio_assign_requested(clip_id: String, res_path: String) -> void:
	if clip_id.is_empty() or res_path.is_empty() or _selected_event == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	if t == null:
		return
	var info: Dictionary = t.find_clip(clip_id)
	if info.is_empty():
		return
	_push_timeline_undo()
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return
	clip.audio_path = res_path
	clip.offset_seconds = 0.0
	clip.duration_seconds = clip.max_source_playable_seconds()
	_extend_timeline_if_content_exceeds()
	_notify_timeline_changed()


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
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	if t.tracks.is_empty():
		return
	_push_timeline_undo()
	var tr_i: int = clampi(_selected_track_index, 0, t.tracks.size() - 1)
	var clip := CodaTimelineClip.new()
	clip.start_seconds = clampf(_view.get_playhead(), 0.0, t.length_seconds)
	var remain: float = max(0.01, t.length_seconds - clip.start_seconds)
	clip.duration_seconds = clampf(min(1.0, max(0.5, remain)), 0.05, remain)
	t.tracks[tr_i].clips.append(clip)
	_extend_timeline_if_content_exceeds()
	_notify_timeline_changed()


func _on_add_marker_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	_push_timeline_undo()
	var t: CodaEventTimeline = _selected_event.event_timeline
	var m := CodaTimelineMarker.new()
	m.time_seconds = clampf(_view.get_playhead(), 0.0, t.length_seconds)
	m.marker_name = "Marker %d" % (t.markers.size() + 1)
	t.markers.append(m)
	_notify_timeline_changed()


func _on_add_track_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	_push_timeline_undo()
	var t: CodaEventTimeline = _selected_event.event_timeline
	var tr := CodaTimelineTrack.new()
	tr.track_name = "Track %d" % (t.tracks.size() + 1)
	t.tracks.append(tr)
	_notify_timeline_changed()


func _on_remove_track_pressed(track_id: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	_push_timeline_undo()
	if not _selected_event.event_timeline.remove_track(track_id):
		_undo_timeline()
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	if t.tracks.is_empty():
		_selected_track_index = 0
	else:
		_selected_track_index = clampi(_selected_track_index, 0, t.tracks.size() - 1)
	if _view != null:
		_view.set_track_row_highlight(_selected_track_index)
	_notify_timeline_changed()


# ---------- View signals ----------

func _on_view_clip_moved(_clip_id: String, _new_start: float, _new_track_index: int = -1) -> void:
	_extend_timeline_if_content_exceeds()
	_notify_timeline_changed()


func _on_view_clip_resized(
	_clip_id: String, _new_start: float, _new_duration: float
) -> void:
	_extend_timeline_if_content_exceeds()
	_notify_timeline_changed()


func _on_view_browser_asset_dropped(track_index: int, start_seconds: float, res_path: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	if track_index < 0 or track_index >= t.tracks.size():
		return
	_push_timeline_undo()
	var clip := CodaTimelineClip.new()
	clip.audio_path = res_path
	clip.start_seconds = clampf(start_seconds, 0.0, t.length_seconds)
	clip.offset_seconds = 0.0
	clip.duration_seconds = clip.max_source_playable_seconds()
	t.tracks[track_index].clips.append(clip)
	_extend_timeline_if_content_exceeds()
	_notify_timeline_changed()


func _on_view_clip_delete_requested(clip_id: String) -> void:
	if clip_id.is_empty() or _selected_event == null or _selected_event.event_timeline == null:
		return
	_push_timeline_undo()
	var t: CodaEventTimeline = _selected_event.event_timeline
	var info: Dictionary = t.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	var track: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
	if clip == null or track == null:
		return
	var idx: int = track.clips.find(clip)
	if idx >= 0:
		track.clips.remove_at(idx)
	if _view != null:
		_view.clear_selection()
	_notify_timeline_changed()


func _on_view_marker_changed(_marker_id: String, _new_time: float) -> void:
	_notify_timeline_changed()


func _on_view_loop_region_changed(_start: float, _end: float) -> void:
	_notify_timeline_changed()


func _on_view_playhead_seek_requested(time_seconds: float) -> void:
	if _runtime == null or _selected_event == null:
		return
	var h: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(_selected_event.id)
	if h != null and h.is_timeline:
		h.seek(clampf(time_seconds, 0.0, h.timeline_length_seconds))


func _on_view_marker_double_clicked(marker_id: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var m: CodaTimelineMarker = _selected_event.event_timeline.find_marker(marker_id)
	if m == null:
		return
	# Inline rename via a tiny popup; deferring to a richer popup_menu would be Phase C polish.
	var dlg := AcceptDialog.new()
	dlg.title = "Rename Marker"
	var le := LineEdit.new()
	le.text = m.marker_name
	le.custom_minimum_size = Vector2(240, 0)
	dlg.add_child(le)
	dlg.confirmed.connect(
		func() -> void:
			m.marker_name = le.text
			_notify_timeline_changed()
	)
	add_child(dlg)
	dlg.popup_centered()


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


func _push_timeline_undo() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var snap: CodaEventTimeline = _selected_event.event_timeline.clone_keep_ids()
	_undo_stack.append(snap)
	_redo_stack.clear()
	while _undo_stack.size() > MAX_TIMELINE_UNDO:
		_undo_stack.pop_front()


func _restore_timeline_from(source: CodaEventTimeline) -> void:
	if _selected_event == null or source == null:
		return
	# Preview holds a snapshot of the pre-undo timeline; stop so audio matches the editor.
	if _live_handle != null and is_instance_valid(_live_handle) and _runtime != null:
		_runtime.stop(_live_handle)
		_live_handle = null
	_selected_event.event_timeline = source.clone_keep_ids()
	_show_timeline()
	_notify_timeline_changed()


func _undo_timeline() -> void:
	if _undo_stack.is_empty() or _selected_event == null:
		return
	var cur: CodaEventTimeline = _selected_event.event_timeline.clone_keep_ids()
	var past: CodaEventTimeline = _undo_stack.pop_back()
	_redo_stack.append(cur)
	_restore_timeline_from(past)


func _redo_timeline() -> void:
	if _redo_stack.is_empty() or _selected_event == null:
		return
	var cur: CodaEventTimeline = _selected_event.event_timeline.clone_keep_ids()
	var fut: CodaEventTimeline = _redo_stack.pop_back()
	_undo_stack.append(cur)
	_restore_timeline_from(fut)


func _on_view_timeline_interaction_started() -> void:
	_push_timeline_undo()


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
	var t: CodaEventTimeline = _selected_event.event_timeline
	var split_t: float = _view.get_playhead()
	_push_timeline_undo()
	var err: String = t.split_clip_at_time(cid, split_t)
	if not err.is_empty():
		_undo_timeline()
		NexusCodaLog.warn("timeline", err)
		return
	_notify_timeline_changed()


func _on_view_clip_duplicate_requested(clip_id: String) -> void:
	if clip_id.is_empty() or _selected_event == null or _selected_event.event_timeline == null:
		return
	_push_timeline_undo()
	var err: String = _selected_event.event_timeline.duplicate_clip(clip_id)
	if not err.is_empty():
		_undo_timeline()
		NexusCodaLog.warn("timeline", err)
		return
	_extend_timeline_if_content_exceeds()
	_notify_timeline_changed()


func _on_view_clip_split_at_playhead_requested(clip_id: String) -> void:
	if clip_id.is_empty() or _selected_event == null or _selected_event.event_timeline == null or _view == null:
		return
	_push_timeline_undo()
	var err: String = _selected_event.event_timeline.split_clip_at_time(clip_id, _view.get_playhead())
	if not err.is_empty():
		_undo_timeline()
		NexusCodaLog.warn("timeline", err)
		return
	_notify_timeline_changed()


func _on_view_audition_requested() -> void:
	if _selected_event == null or _runtime == null:
		return
	if _selected_event.event_authoring_mode != CodaBrowserNode.AuthoringMode.TIMELINE:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	if t == null or _view == null:
		return
	var existing: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(_selected_event.id)
	if existing != null and existing.is_timeline:
		if existing.is_paused():
			existing.resume()
			NexusCodaLog.info("timeline_preview", 'Preview resumed: "%s"' % _selected_event.name)
			return
		existing.pause()
		NexusCodaLog.info("timeline_preview", 'Preview paused: "%s"' % _selected_event.name)
		return
	if _live_handle != null and is_instance_valid(_live_handle):
		_runtime.stop(_live_handle)
	_live_handle = null
	var ph: float = clampf(_view.get_playhead(), 0.0, t.length_seconds)
	var params: Dictionary = {"loop": t.loop_enabled, "timeline_cursor_start": ph}
	var h: CodaEventHandle = _runtime.play_event_node(_selected_event, params)
	if h == null:
		NexusCodaLog.warn("timeline_preview", 'Could not start preview for "%s"' % _selected_event.name)
		return
	_live_handle = h
	NexusCodaLog.info("timeline_preview", 'Preview started: "%s"' % _selected_event.name)
