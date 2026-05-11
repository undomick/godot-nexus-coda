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

const HEADERS_WIDTH := 240
const TRACK_HEIGHT := CodaTimelineViewScript.TRACK_HEIGHT
const RULER_HEIGHT := CodaTimelineViewScript.RULER_HEIGHT

var _project: CodaState = null
var _runtime: CodaRuntime = null
var _selected_event: CodaBrowserNode = null
var _live_handle: CodaEventHandle = null

var _toolbar: HBoxContainer
var _empty_state: CodaEmptyState
var _split_root: HBoxContainer
var _track_headers_column: VBoxContainer
var _ruler_spacer: Control
var _track_headers_host: VBoxContainer
var _add_track_btn: Button

var _view: CodaTimelineView

var _snap_picker: OptionButton
var _bpm_spin: SpinBox
var _loop_toggle: CheckBox
var _add_marker_btn: Button
var _add_clip_btn: Button
var _switch_mode_btn: Button

var _validation_label: Label

var _suppress_writeback: bool = false


func _ready() -> void:
	name = "Timeline"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 0)

	_build_toolbar()
	_build_empty_state()
	_build_split_root()
	_build_validation_label()

	_show_empty()
	set_process(true)


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.disconnect(_on_project_structure_changed)
	_project = project
	if _project != null:
		_project.structure_changed.connect(_on_project_structure_changed)
	_refresh_view_state()


func attach_runtime(runtime: CodaRuntime) -> void:
	if _runtime != null and is_instance_valid(_runtime):
		if _runtime.voice_finished.is_connected(_on_runtime_voice_finished):
			_runtime.voice_finished.disconnect(_on_runtime_voice_finished)
	_runtime = runtime
	if _runtime != null:
		_runtime.voice_finished.connect(_on_runtime_voice_finished)


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
		_view.set_playhead(_live_handle.timeline_cursor_seconds)


func on_browser_event_selected(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
	else:
		_selected_event = bn
	# Active handle becomes stale when the visible event changes; the next process tick re-resolves.
	_live_handle = null
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
	_add_clip_btn.tooltip_text = "Add an empty clip to the first track at the current playhead"
	_add_clip_btn.pressed.connect(_on_add_clip_pressed)
	_toolbar.add_child(_add_clip_btn)

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

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(spacer)

	_switch_mode_btn = Button.new()
	_switch_mode_btn.text = "Switch to Graph"
	_switch_mode_btn.tooltip_text = "Use the Event-Graph authoring model instead of the timeline"
	_switch_mode_btn.pressed.connect(_on_switch_mode_pressed)
	_toolbar.add_child(_switch_mode_btn)


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
	_split_root = HBoxContainer.new()
	_split_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split_root.add_theme_constant_override(&"separation", 0)
	_split_root.visible = false
	add_child(_split_root)

	_track_headers_column = VBoxContainer.new()
	_track_headers_column.custom_minimum_size = Vector2(HEADERS_WIDTH, 0)
	_track_headers_column.size_flags_horizontal = Control.SIZE_FILL
	_track_headers_column.add_theme_constant_override(&"separation", 0)
	_split_root.add_child(_track_headers_column)

	_ruler_spacer = Control.new()
	_ruler_spacer.custom_minimum_size = Vector2(0, RULER_HEIGHT)
	_track_headers_column.add_child(_ruler_spacer)

	_track_headers_host = VBoxContainer.new()
	_track_headers_host.add_theme_constant_override(&"separation", 0)
	_track_headers_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_view.browser_asset_dropped.connect(_on_view_browser_asset_dropped)
	_view.marker_changed.connect(_on_view_marker_changed)
	_view.loop_region_changed.connect(_on_view_loop_region_changed)
	_view.playhead_seek_requested.connect(_on_view_playhead_seek_requested)
	_view.marker_double_clicked.connect(_on_view_marker_double_clicked)
	_split_root.add_child(_view)


func _build_validation_label() -> void:
	_validation_label = Label.new()
	_validation_label.add_theme_color_override(&"font_color", Tokens.DANGER)
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation_label.visible = false
	add_child(_validation_label)


# ---------- State refresh ----------

func _on_project_structure_changed() -> void:
	_refresh_view_state()


func _refresh_view_state() -> void:
	if _selected_event == null:
		_show_empty(true)
		return
	if _selected_event.event_authoring_mode != CodaBrowserNode.AuthoringMode.TIMELINE:
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
	_view.set_timeline(_selected_event.event_timeline)
	_rebuild_track_headers()
	_sync_toolbar_to_timeline()
	_update_validation()


func _rebuild_track_headers() -> void:
	for c in _track_headers_host.get_children():
		c.queue_free()
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	for i in _selected_event.event_timeline.tracks.size():
		_track_headers_host.add_child(_make_track_header(_selected_event.event_timeline.tracks[i]))


func _make_track_header(track: CodaTimelineTrack) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, TRACK_HEIGHT)
	row.add_theme_stylebox_override(
		&"panel", Tokens.make_panel_stylebox(Tokens.SURFACE_SUNKEN, Tokens.SURFACE_BORDER, 0, 0)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_right", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_top", Tokens.SPACING_XS)
	margin.add_theme_constant_override(&"margin_bottom", Tokens.SPACING_XS)
	row.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override(&"separation", 2)
	margin.add_child(vb)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	vb.add_child(name_row)

	var name_edit := LineEdit.new()
	name_edit.text = track.track_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(
		func(t: String) -> void:
			track.track_name = t
			_notify_timeline_changed()
	)
	name_edit.focus_exited.connect(
		func() -> void:
			if track.track_name != name_edit.text:
				track.track_name = name_edit.text
				_notify_timeline_changed()
	)
	name_row.add_child(name_edit)

	var mute_btn := Button.new()
	mute_btn.toggle_mode = true
	mute_btn.text = "M"
	mute_btn.tooltip_text = "Mute this track (visual only in MVP)"
	mute_btn.button_pressed = track.mute
	mute_btn.toggled.connect(
		func(on: bool) -> void:
			track.mute = on
			_notify_timeline_changed()
	)
	name_row.add_child(mute_btn)

	var solo_btn := Button.new()
	solo_btn.toggle_mode = true
	solo_btn.text = "S"
	solo_btn.tooltip_text = "Solo this track (visual only in MVP)"
	solo_btn.button_pressed = track.solo
	solo_btn.toggled.connect(
		func(on: bool) -> void:
			track.solo = on
			_notify_timeline_changed()
	)
	name_row.add_child(solo_btn)

	var del_btn := Button.new()
	del_btn.text = "−"
	del_btn.tooltip_text = "Remove this track"
	del_btn.pressed.connect(_on_remove_track_pressed.bind(track.id))
	name_row.add_child(del_btn)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	vb.add_child(volume_row)

	var volume_label := Label.new()
	volume_label.text = "Vol"
	volume_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	volume_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	volume_label.custom_minimum_size = Vector2(28, 0)
	volume_row.add_child(volume_label)

	var volume_slider := HSlider.new()
	volume_slider.min_value = -60.0
	volume_slider.max_value = 6.0
	volume_slider.step = 0.5
	volume_slider.value = track.volume_db
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(
		func(v: float) -> void:
			track.volume_db = v
			_notify_timeline_changed()
	)
	volume_row.add_child(volume_slider)

	var bus_label := Label.new()
	bus_label.text = _bus_picker_label_for(track.output_bus_id)
	bus_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	bus_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	bus_label.tooltip_text = "Per-track bus routing comes in a follow-up; track inherits the event's bus"
	volume_row.add_child(bus_label)

	return row


func _bus_picker_label_for(bus_id: String) -> String:
	if bus_id.is_empty() or _project == null or _project.bus_root == null:
		return "→ event bus"
	var b: CodaBus = _project.bus_root.find_by_id(bus_id)
	if b == null:
		return "→ ?"
	return "→ %s" % b.bus_name


func _sync_toolbar_to_timeline() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	_suppress_writeback = true
	_loop_toggle.button_pressed = t.loop_enabled
	_bpm_spin.value = t.tempo_bpm
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
	_update_validation()
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
	var clip := CodaTimelineClip.new()
	clip.start_seconds = clampf(_view.get_playhead(), 0.0, t.length_seconds)
	clip.duration_seconds = min(1.0, max(0.5, t.length_seconds - clip.start_seconds))
	t.tracks[0].clips.append(clip)
	_notify_timeline_changed()


func _on_add_marker_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	var m := CodaTimelineMarker.new()
	m.time_seconds = clampf(_view.get_playhead(), 0.0, t.length_seconds)
	m.marker_name = "Marker %d" % (t.markers.size() + 1)
	t.markers.append(m)
	_notify_timeline_changed()


func _on_add_track_pressed() -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	var tr := CodaTimelineTrack.new()
	tr.track_name = "Track %d" % (t.tracks.size() + 1)
	t.tracks.append(tr)
	_notify_timeline_changed()


func _on_remove_track_pressed(track_id: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	if _selected_event.event_timeline.remove_track(track_id):
		_notify_timeline_changed()


# ---------- View signals ----------

func _on_view_clip_moved(_clip_id: String, _new_start: float) -> void:
	_notify_timeline_changed()


func _on_view_clip_resized(
	_clip_id: String, _new_start: float, _new_duration: float
) -> void:
	_notify_timeline_changed()


func _on_view_browser_asset_dropped(track_index: int, start_seconds: float, res_path: String) -> void:
	if _selected_event == null or _selected_event.event_timeline == null:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	if track_index < 0 or track_index >= t.tracks.size():
		return
	var clip := CodaTimelineClip.new()
	clip.audio_path = res_path
	clip.start_seconds = clampf(start_seconds, 0.0, t.length_seconds)
	var remain: float = max(0.01, t.length_seconds - clip.start_seconds)
	clip.duration_seconds = _audio_clip_duration_seconds(res_path, remain)
	clip.offset_seconds = 0.0
	t.tracks[track_index].clips.append(clip)
	_notify_timeline_changed()


func _audio_clip_duration_seconds(res_path: String, max_seconds: float) -> float:
	var r: Resource = ResourceLoader.load(res_path)
	if r is AudioStream:
		var a: AudioStream = r as AudioStream
		var len: float = a.get_length()
		if len > 0.0:
			return clampf(len, 0.05, max_seconds)
	return clampf(1.0, 0.05, max_seconds)


func _on_view_marker_changed(_marker_id: String, _new_time: float) -> void:
	_notify_timeline_changed()


func _on_view_loop_region_changed(_start: float, _end: float) -> void:
	_notify_timeline_changed()


func _on_view_playhead_seek_requested(_time: float) -> void:
	# The Player panel drives playback; the timeline panel only needs to keep its visual
	# cursor in sync, which already happened in the view itself. Intentionally a no-op
	# until C/4 wires Player ↔ Timeline.
	pass


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
