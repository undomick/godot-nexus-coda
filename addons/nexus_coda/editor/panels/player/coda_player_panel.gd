@tool
class_name CodaPlayerPanel
extends VBoxContainer

signal playhead_changed(seconds: float)

## Standalone audition surface for the editor.
## Drives the editor-side CodaRuntime so designers can preview events with full
## time / loop / meter / live-parameter feedback. Optionally pinned so browser
## selection changes do not override the loaded event.
##
## Replaces the small transport bar that used to sit inside the Inspector — single
## source of truth for transport in the editor.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaPlayOptionsScript := preload("res://addons/nexus_coda/domain/coda_play_options.gd")
const CodaTimelineTransportScript := preload(
	"res://addons/nexus_coda/domain/coda_timeline_transport.gd"
)
const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")
const CodaSectionHeaderScript := preload(
	"res://addons/nexus_coda/editor/theme/coda_section_header.gd"
)
const CodaEventTransportBarScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_event_transport_bar.gd"
)
const CodaPlayerParamGridScript := preload(
	"res://addons/nexus_coda/editor/panels/player/coda_player_param_grid.gd"
)

const STATUS_IDLE := "Idle"
const STATUS_PLAYING := "Playing"
const STATUS_PAUSED := "Paused"

const SOUND_NODE_KIND := 5

var _project: CodaState = null
var _runtime: CodaRuntime = null

var _selected_event: CodaBrowserNode = null
var _is_pinned: bool = false
var _active_handle: CodaEventHandle = null
var _seek_slider_dragging: bool = false
var _transport_armed_for_handle_id: int = -1

var _empty_state: CodaEmptyState
var _scroll: ScrollContainer
var _content: VBoxContainer
var _header: CodaSectionHeader
var _pin_button: Button
var _transport_bar: CodaEventTransportBar
var _status_label: Label
var _time_label: Label
var _seek_slider: HSlider
var _meter_l: ProgressBar
var _meter_r: ProgressBar
var _meter_value_label: Label
var _params_header: CodaSectionHeader
var _param_grid: CodaPlayerParamGrid
var _last_playhead_broadcast: float = NAN


func _ready() -> void:
	name = "Player"
	add_theme_constant_override(&"separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_empty_state = CodaEmptyStateScript.new()
	_empty_state.title_text = "No event selected"
	_empty_state.body_text = "Pick an event in the Browser, or pin one here, to audition it."
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_empty_state)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.visible = false
	add_child(_scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", Tokens.SPACING_LG)
	margin.add_theme_constant_override(&"margin_right", Tokens.SPACING_LG)
	margin.add_theme_constant_override(&"margin_top", Tokens.SPACING_MD)
	margin.add_theme_constant_override(&"margin_bottom", Tokens.SPACING_LG)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", Tokens.SPACING_MD)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_content)

	_header = CodaSectionHeaderScript.new()
	_header.heading = "—"
	_content.add_child(_header)

	_pin_button = Button.new()
	_pin_button.toggle_mode = true
	_pin_button.text = "Pin"
	_pin_button.tooltip_text = "Lock this event so browser selection does not change it"
	_pin_button.toggled.connect(_on_pin_toggled)
	_header.add_trailing(_pin_button)

	var transport_row := HBoxContainer.new()
	transport_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	transport_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(transport_row)

	_transport_bar = CodaEventTransportBarScript.new()
	transport_row.add_child(_transport_bar)
	_transport_bar.set_status_label_visible(false)
	_transport_bar.play_requested.connect(_on_play_requested)
	_transport_bar.stop_requested.connect(_on_stop_requested)
	_transport_bar.pause_toggled.connect(_on_pause_toggled)
	_transport_bar.loop_toggled.connect(_on_loop_toggled)

	_time_label = Label.new()
	_time_label.text = _format_time_pair(0.0, 0.0)
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override(&"font_size", Tokens.FONT_BODY_SIZE)
	_time_label.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	transport_row.add_child(_time_label)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_content.add_child(time_row)

	_seek_slider = HSlider.new()
	_seek_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek_slider.min_value = 0.0
	_seek_slider.max_value = 1.0
	_seek_slider.step = 0.001
	_seek_slider.editable = false
	_seek_slider.drag_started.connect(_on_seek_drag_started)
	_seek_slider.drag_ended.connect(_on_seek_drag_ended)
	time_row.add_child(_seek_slider)

	var meter_row := HBoxContainer.new()
	meter_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_content.add_child(meter_row)

	var meter_caption := Label.new()
	meter_caption.text = "Output"
	meter_caption.custom_minimum_size = Vector2(60, 0)
	meter_caption.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	meter_caption.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	meter_row.add_child(meter_caption)

	var meter_box := VBoxContainer.new()
	meter_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter_box.add_theme_constant_override(&"separation", 2)
	meter_row.add_child(meter_box)

	_meter_l = _make_meter_bar()
	meter_box.add_child(_meter_l)
	_meter_r = _make_meter_bar()
	meter_box.add_child(_meter_r)

	_meter_value_label = Label.new()
	_meter_value_label.custom_minimum_size = Vector2(70, 0)
	_meter_value_label.text = "-inf dB"
	_meter_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_meter_value_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_meter_value_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	meter_row.add_child(_meter_value_label)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	_content.add_child(status_row)
	var status_caption := Label.new()
	status_caption.text = "Status:"
	status_caption.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	status_caption.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	status_row.add_child(status_caption)
	_status_label = Label.new()
	_status_label.text = STATUS_IDLE
	_status_label.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_status_label.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	status_row.add_child(_status_label)

	_content.add_child(HSeparator.new())

	_params_header = CodaSectionHeaderScript.new()
	_params_header.heading = "Live Parameters"
	_content.add_child(_params_header)

	_param_grid = CodaPlayerParamGridScript.new()
	_param_grid.param_value_changed.connect(_on_param_grid_value_changed)
	_content.add_child(_param_grid)

	tooltip_text = (
		"Player — audition events with full transport, time, meter and live parameter control."
	)
	set_process(true)


func _make_meter_bar() -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = 0.0
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 6)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func attach_browser_panel(browser_panel: Control) -> void:
	if browser_panel != null and browser_panel.has_method(&"get_project"):
		attach_project(browser_panel.get_project())


func attach_project(project: CodaState) -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.disconnect(_on_project_structure_changed)
		if _project.project_dirty.is_connected(_on_project_dirty_lite):
			_project.project_dirty.disconnect(_on_project_dirty_lite)
	_project = project
	if _project != null:
		_project.structure_changed.connect(_on_project_structure_changed)
		# Timeline drops fire only `project_dirty` (no structural shape change). Listen for it
		# so Play enables itself as soon as the first clip lands on a lane.
		_project.project_dirty.connect(_on_project_dirty_lite)


func _on_project_structure_changed() -> void:
	# Authoring mode, parameters, or audio paths may have changed for the loaded event;
	# rebuild dependent UI so Play stays accurate.
	_refresh_play_enabled()
	_rebuild_param_rows()


func _on_project_dirty_lite() -> void:
	# Cheap refresh: drag-dropping a clip, changing track/clip volume, or any other
	# non-structural mutation runs through here.
	_refresh_play_enabled()


func attach_runtime(runtime: CodaRuntime) -> void:
	_runtime = runtime
	_refresh_play_enabled()


## Browser-selection slot. Same signature as Inspector/Graph so the editor window can wire
## all selection consumers identically.
func on_browser_event_selected(node: Variant) -> void:
	if _is_pinned:
		return
	_set_event_internal(node)


func is_pinned() -> bool:
	return _is_pinned


## Programmatic playback for the command palette.
func play_current_selection() -> void:
	_on_play_requested()


func stop_current_voice() -> void:
	_stop_active_voice()


func toggle_pin() -> void:
	if _pin_button != null:
		_pin_button.button_pressed = not _pin_button.button_pressed


func _set_event_internal(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
		_stop_active_voice()
		_show_empty()
		_rebuild_param_rows()
		return
	var changed: bool = bn != _selected_event
	var prev_event: CodaBrowserNode = _selected_event
	_selected_event = bn
	_header.heading = bn.name
	_show_event()
	_refresh_play_enabled()
	if changed:
		if _runtime != null and prev_event != null:
			var old_tl: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(
				prev_event.id
			)
			if old_tl != null:
				_runtime.stop(old_tl)
		_stop_active_voice()
	_rebuild_param_rows()


func _show_empty() -> void:
	if _empty_state != null:
		_empty_state.visible = true
	if _scroll != null:
		_scroll.visible = false


func _show_event() -> void:
	if _empty_state != null:
		_empty_state.visible = false
	if _scroll != null:
		_scroll.visible = true


func _refresh_play_enabled() -> void:
	if _transport_bar == null:
		return
	if _selected_event == null:
		_transport_bar.set_play_enabled(false, "Select an event first")
		return
	if _runtime == null:
		_transport_bar.set_play_enabled(false, "Runtime not available")
		return
	var has_content: bool = _event_has_playable_content(_selected_event)
	if not has_content:
		var hint: String = "Add a Sound node and pick an audio file in the Graph"
		if _selected_event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE:
			hint = "Add a clip with an audio file to the timeline"
		_transport_bar.set_play_enabled(false, hint)
		return
	_transport_bar.set_play_enabled(true)


static func _event_has_playable_content(event: CodaBrowserNode) -> bool:
	if event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE:
		var t: CodaEventTimeline = event.event_timeline
		if t == null:
			return false
		for track in t.tracks:
			for clip in track.clips:
				if not String(clip.audio_path).strip_edges().is_empty():
					return true
		return false
	if event.event_audio_paths.size() > 0:
		return true
	if event.event_graph != null:
		for n in event.event_graph.nodes:
			if int(n.kind) != SOUND_NODE_KIND:
				continue
			if not String(n.properties.get("audio_path", "")).strip_edges().is_empty():
				return true
	return false


func _resolve_preview_handle() -> CodaEventHandle:
	if _selected_event == null or _runtime == null:
		return null
	var tl: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(_selected_event.id)
	if tl != null:
		return tl
	return _active_handle


func _arm_transport_for_handle(h: CodaEventHandle) -> void:
	if h == null or _transport_bar == null:
		return
	if _transport_armed_for_handle_id == h.id:
		return
	_transport_bar.arm_pause_for_playback()
	_transport_armed_for_handle_id = h.id


# ---- Transport handlers ----

func _on_play_requested() -> void:
	if _selected_event == null or _runtime == null:
		return
	_stop_active_voice()
	var opts := CodaPlayOptionsScript.new()
	opts.loop = _transport_bar.is_loop_enabled()
	opts.exclusive_preview = true
	if _selected_event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE:
		var tline: CodaEventTimeline = _selected_event.event_timeline
		if tline != null:
			opts.timeline_cursor_start = clampf(_seek_slider.value, 0.0, tline.length_seconds)
			CodaTimelineTransportScript.apply_to_play_options(tline, opts)
			_sync_playback_work_area()
	var playback_event: CodaBrowserNode = _resolve_playback_event(_selected_event)
	var h: CodaEventHandle = _runtime.play_event_node(playback_event, opts.to_params_dict())
	if h == null:
		_transport_bar.set_playing(false)
		_set_status(STATUS_IDLE)
		NexusCodaLog.warn(
			"player_preview", 'Could not start preview for "%s"' % _selected_event.name
		)
		return
	if h.is_timeline:
		_active_handle = null
	else:
		_active_handle = h
	_transport_bar.set_playing(true)
	_arm_transport_for_handle(h)
	_set_status(STATUS_PLAYING)
	if _seek_slider != null:
		_seek_slider.editable = true
	NexusCodaLog.info("player_preview", 'Preview started: "%s"' % _selected_event.name)


func _on_stop_requested() -> void:
	_stop_active_voice()


func _on_loop_toggled(loop: bool) -> void:
	if _selected_event != null and _selected_event.event_timeline != null:
		_selected_event.event_timeline.loop_enabled = loop
	if _selected_event != null and _selected_event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE:
		_sync_playback_work_area()
	var r: CodaEventHandle = _resolve_preview_handle()
	if r != null:
		r.loop = loop


func _on_pause_toggled(on: bool) -> void:
	var r: CodaEventHandle = _resolve_preview_handle()
	if r == null:
		if _transport_bar != null:
			_transport_bar.set_pause_pressed_no_signal(false)
		return
	if on:
		r.pause()
		_set_status(STATUS_PAUSED)
	else:
		r.resume()
		_set_status(STATUS_PLAYING)


func _on_seek_drag_started() -> void:
	_seek_slider_dragging = true


func _on_seek_drag_ended(_value_changed: bool) -> void:
	_seek_slider_dragging = false
	var r: CodaEventHandle = _resolve_preview_handle()
	if r != null:
		r.seek(_seek_slider.value)


func _on_pin_toggled(on: bool) -> void:
	_is_pinned = on
	_pin_button.text = "Pinned" if on else "Pin"


func _stop_active_voice() -> void:
	if _active_handle != null and _runtime != null:
		_runtime.stop(_active_handle)
		_active_handle = null
	elif _active_handle != null:
		_active_handle.stop()
		_active_handle = null
	if _runtime != null and _selected_event != null:
		var tlh: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(_selected_event.id)
		if tlh != null:
			_runtime.stop(tlh)
	_transport_armed_for_handle_id = -1
	if _transport_bar != null:
		_transport_bar.set_playing(false)
	if _seek_slider != null:
		_seek_slider.editable = false
		_seek_slider.set_value_no_signal(0.0)
	_set_status(STATUS_IDLE)


func set_external_playhead_seconds(seconds: float) -> void:
	if _seek_slider != null:
		_seek_slider.set_value_no_signal(clampf(seconds, _seek_slider.min_value, _seek_slider.max_value))
	_update_time_display()


# ---- Frame loop ----

func _process(_delta: float) -> void:
	var r: CodaEventHandle = _resolve_preview_handle()
	if r == null:
		if _active_handle != null:
			_active_handle = null
		_transport_armed_for_handle_id = -1
		if _transport_bar != null:
			_transport_bar.set_playing(false)
		if _seek_slider != null:
			_seek_slider.editable = false
		_set_status(STATUS_IDLE)
	elif not r.is_timeline and not r.is_playing():
		_active_handle = null
		_transport_armed_for_handle_id = -1
		if _transport_bar != null:
			_transport_bar.set_playing(false)
		if _seek_slider != null:
			_seek_slider.editable = false
		_set_status(STATUS_IDLE)
	else:
		if not r.is_timeline:
			_active_handle = r
		if _transport_bar != null:
			_transport_bar.set_playing(true)
			_arm_transport_for_handle(r)
			_transport_bar.set_pause_pressed_no_signal(r.is_paused())
		if r.is_paused():
			_set_status(STATUS_PAUSED)
		else:
			_set_status(STATUS_PLAYING)
		if _seek_slider != null:
			_seek_slider.editable = true
	_update_time_display()
	_update_meter()


func _update_time_display() -> void:
	var pos: float = 0.0
	var length: float = 0.0
	var r: CodaEventHandle = _resolve_preview_handle()
	if r != null:
		pos = r.get_position()
		length = r.get_length()
	if _time_label != null:
		_time_label.text = _format_time_pair(pos, length)
	if _seek_slider != null and not _seek_slider_dragging:
		if length > 0.0:
			_seek_slider.max_value = length
			_seek_slider.set_value_no_signal(clampf(pos, 0.0, length))
		else:
			_seek_slider.max_value = 1.0
			_seek_slider.set_value_no_signal(0.0)
	# Without an active preview handle, do not broadcast 0 every frame — that would
	# overwrite the timeline's authoring playhead before the first audition.
	if r != null:
		var should_broadcast: bool = not r.is_paused() or not is_equal_approx(pos, _last_playhead_broadcast)
		if should_broadcast:
			_last_playhead_broadcast = pos
			playhead_changed.emit(pos)
	else:
		_last_playhead_broadcast = NAN


func _update_meter() -> void:
	var bus_name: String = ""
	var r: CodaEventHandle = _resolve_preview_handle()
	if r != null:
		bus_name = r.get_bus_name()
	if bus_name.is_empty() and _runtime != null and _selected_event != null:
		bus_name = _runtime.resolve_bus_name_for_event(_selected_event)
	if bus_name.is_empty():
		bus_name = "Master"
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		_set_meter_inactive()
		return
	var l_db: float = AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
	var r_db: float = AudioServer.get_bus_peak_volume_right_db(bus_idx, 0)
	if _meter_l != null:
		_meter_l.value = _db_to_meter_norm(l_db)
	if _meter_r != null:
		_meter_r.value = _db_to_meter_norm(r_db)
	if _meter_value_label != null:
		var hot: float = max(l_db, r_db)
		if hot <= -79.5:
			_meter_value_label.text = "-inf dB"
		else:
			_meter_value_label.text = "%.1f dB" % hot


func _set_meter_inactive() -> void:
	if _meter_l != null:
		_meter_l.value = 0.0
	if _meter_r != null:
		_meter_r.value = 0.0
	if _meter_value_label != null:
		_meter_value_label.text = "—"


static func _db_to_meter_norm(db: float) -> float:
	# Map [-60, +6] dB → [0.0, 1.0] for the visual meter bars.
	var clamped: float = clampf(db, -60.0, 6.0)
	return (clamped + 60.0) / 66.0


static func _format_time_pair(current: float, total: float) -> String:
	return "%s  /  %s" % [_format_transport_time(current), _format_transport_time(total)]


static func _format_transport_time(secs: float) -> String:
	if not is_finite(secs) or secs < 0.0:
		secs = 0.0
	var whole: int = int(secs)
	var hours: int = whole / 3600
	var minutes: int = (whole % 3600) / 60
	var seconds: int = whole % 60
	var centis: int = int(round((secs - float(whole)) * 100.0))
	if centis >= 100:
		seconds += 1
		centis = 0
		if seconds >= 60:
			minutes += 1
			seconds = 0
			if minutes >= 60:
				hours += 1
				minutes = 0
	if hours > 0:
		return "%dh%02dm%02d.%02ds" % [hours, minutes, seconds, centis]
	return "00h%02dm%02d.%02ds" % [minutes, seconds, centis]


func _set_status(text: String) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	var color: Color = Tokens.TEXT_MUTED
	if text == STATUS_PLAYING:
		color = Tokens.SUCCESS
	elif text == STATUS_PAUSED:
		color = Tokens.WARN
	_status_label.add_theme_color_override(&"font_color", color)


# ---- Live parameter rows ----

func _rebuild_param_rows() -> void:
	if _param_grid != null:
		_param_grid.rebuild_for_event(_selected_event)


func _on_param_grid_value_changed(param_id: String, value: Variant) -> void:
	var rh: CodaEventHandle = _resolve_preview_handle()
	if rh != null and _runtime != null:
		_runtime.set_parameter(rh, param_id, value)


func _resolve_playback_event(source: CodaBrowserNode) -> CodaBrowserNode:
	if _runtime == null or source == null:
		return source
	var project: CodaState = _runtime.get_project()
	if project == null:
		return source
	var playback: CodaBrowserNode = project.find_node_anywhere(source.id)
	return playback if playback != null else source


func _sync_playback_work_area() -> void:
	if _runtime == null or _selected_event == null:
		return
	var live_tl: CodaEventTimeline = _selected_event.event_timeline
	if live_tl == null:
		return
	var playback: CodaBrowserNode = _resolve_playback_event(_selected_event)
	if playback == null or playback.event_timeline == null:
		return
	CodaTimelineTransportScript.copy_preview_transport(live_tl, playback.event_timeline)
