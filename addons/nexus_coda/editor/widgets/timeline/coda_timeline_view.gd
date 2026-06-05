@tool
class_name CodaTimelineView
extends Control

## Reusable view widget over a CodaEventTimeline.
## Pure presentation + interaction layer; the widget never touches CodaState — the host
## panel translates emitted signals into state mutations.
##
## Coordinates: time runs horizontally (seconds), tracks stack vertically. The ruler at
## the top of the widget shows seconds (and optional bars/beats when `tempo_bpm > 0`).
## Track lane height is configurable ([member set_track_row_height]); the host panel keeps
## its header rows in sync via [method get_track_row_height].


const Renderer := preload("res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_renderer.gd")
const InputController := preload(
	"res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_input_controller.gd"
)

const RULER_HEIGHT := Renderer.RULER_HEIGHT
const DEFAULT_TRACK_ROW_HEIGHT := 92
const MIN_TRACK_ROW_HEIGHT := 88
const MAX_TRACK_ROW_HEIGHT := 200

const DEFAULT_SECONDS_PER_PIXEL := 1.0 / 80.0
const MIN_SECONDS_PER_PIXEL := 1.0 / 1024.0
const MAX_SECONDS_PER_PIXEL := 0.5

enum SnapMode { NONE = 0, TENTHS = 1, BARS_BEATS = 2 }

signal browser_asset_dropped(track_index: int, start_seconds: float, res_audio_path: String)
signal clip_audio_assign_requested(clip_id: String, res_audio_path: String)
signal track_row_selected(track_index: int)
signal clip_selected(clip_id: String)
signal clip_move_requested(clip_id: String, new_start: float, new_track_index: int)
signal clip_resize_requested(
	clip_id: String, new_start: float, new_duration: float, new_offset_seconds: float
)
signal clip_fade_requested(
	clip_id: String, fade_in: float, fade_out: float, fade_in_curve: float, fade_out_curve: float
)
signal clip_delete_requested(clip_id: String)
signal marker_changed(marker_id: String, new_time: float)
signal marker_double_clicked(marker_id: String)
signal marker_selected(marker_id: String)
signal marker_delete_requested(marker_id: String)
signal marker_rename_requested(marker_id: String)
signal marker_go_to_time_requested(marker_id: String)
signal marker_selection_cleared
signal work_point_changed(kind: String, new_time: float)
signal work_point_toggle_requested(kind: String)
signal work_point_delete_requested(kind: String)
signal work_point_selected(kind: String)
signal work_point_selection_cleared
signal loop_region_changed(start_seconds: float, end_seconds: float)
signal playhead_seek_requested(time_seconds: float)
signal selection_cleared
## Emitted once when a drag begins that should participate in host-side undo batching.
signal timeline_interaction_started
signal timeline_interaction_committed(kind: int, clip_id: String)
signal clip_duplicate_requested(clip_id: String)
signal clip_split_at_playhead_requested(clip_id: String)
signal audition_requested

var _timeline: CodaEventTimeline = null
var _seconds_per_pixel: float = DEFAULT_SECONDS_PER_PIXEL
var _scroll_seconds: float = 0.0
var _playhead_seconds: float = 0.0
var _snap_mode: SnapMode = SnapMode.NONE
var _track_row_height: int = DEFAULT_TRACK_ROW_HEIGHT
var _selected_clip_id: String = ""
var _selected_marker_id: String = ""
var _selected_work_point: String = ""
var _highlight_track_index: int = 0

var _input: InputController

var _clip_menu: PopupMenu
const _CTX_REMOVE_CLIP := 1
const _CTX_DUPLICATE_CLIP := 2
const _CTX_SPLIT_PLAYHEAD := 3
var _menu_clip_id: String = ""

var _marker_menu: PopupMenu
const _CTX_MARKER_RENAME := 1
const _CTX_MARKER_DELETE := 2
const _CTX_MARKER_GO_TO := 3
var _menu_marker_id: String = ""

var _work_point_menu: PopupMenu
const _CTX_WORK_POINT_DELETE := 1
var _menu_work_point_kind: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(200, RULER_HEIGHT + _track_row_height)
	clip_contents = true
	_input = InputController.new()
	_wire_input_controller()


func _wire_input_controller() -> void:
	_input.browser_asset_dropped.connect(
		func(track_index: int, start_seconds: float, res_audio_path: String) -> void:
			browser_asset_dropped.emit(track_index, start_seconds, res_audio_path)
	)
	_input.clip_audio_assign_requested.connect(
		func(clip_id: String, res_audio_path: String) -> void:
			clip_audio_assign_requested.emit(clip_id, res_audio_path)
	)
	_input.track_row_selected.connect(
		func(track_index: int) -> void:
			track_row_selected.emit(track_index)
	)
	_input.clip_selected.connect(
		func(clip_id: String) -> void:
			clip_selected.emit(clip_id)
	)
	_input.clip_move_requested.connect(
		func(clip_id: String, new_start: float, new_track_index: int) -> void:
			clip_move_requested.emit(clip_id, new_start, new_track_index)
	)
	_input.clip_resize_requested.connect(
		func(
			clip_id: String, new_start: float, new_duration: float, new_offset_seconds: float
		) -> void:
			clip_resize_requested.emit(clip_id, new_start, new_duration, new_offset_seconds)
	)
	_input.clip_fade_requested.connect(
		func(
			clip_id: String,
			fade_in: float,
			fade_out: float,
			fade_in_curve: float,
			fade_out_curve: float
		) -> void:
			clip_fade_requested.emit(
				clip_id, fade_in, fade_out, fade_in_curve, fade_out_curve
			)
	)
	_input.clip_delete_requested.connect(
		func(clip_id: String) -> void:
			clip_delete_requested.emit(clip_id)
	)
	_input.clip_duplicate_requested.connect(
		func(clip_id: String) -> void:
			clip_duplicate_requested.emit(clip_id)
	)
	_input.clip_split_at_playhead_requested.connect(
		func(clip_id: String) -> void:
			clip_split_at_playhead_requested.emit(clip_id)
	)
	_input.marker_changed.connect(
		func(marker_id: String, new_time: float) -> void:
			marker_changed.emit(marker_id, new_time)
	)
	_input.marker_double_clicked.connect(
		func(marker_id: String) -> void:
			marker_double_clicked.emit(marker_id)
	)
	_input.marker_selected.connect(
		func(marker_id: String) -> void:
			marker_selected.emit(marker_id)
	)
	_input.marker_delete_requested.connect(
		func(marker_id: String) -> void:
			marker_delete_requested.emit(marker_id)
	)
	_input.marker_rename_requested.connect(
		func(marker_id: String) -> void:
			marker_rename_requested.emit(marker_id)
	)
	_input.marker_go_to_time_requested.connect(
		func(marker_id: String) -> void:
			marker_go_to_time_requested.emit(marker_id)
	)
	_input.marker_selection_cleared.connect(
		func() -> void:
			marker_selection_cleared.emit()
	)
	_input.work_point_changed.connect(
		func(kind: String, new_time: float) -> void:
			work_point_changed.emit(kind, new_time)
	)
	_input.work_point_toggle_requested.connect(
		func(kind: String) -> void:
			work_point_toggle_requested.emit(kind)
	)
	_input.work_point_delete_requested.connect(
		func(kind: String) -> void:
			work_point_delete_requested.emit(kind)
	)
	_input.work_point_selected.connect(
		func(kind: String) -> void:
			work_point_selected.emit(kind)
	)
	_input.work_point_selection_cleared.connect(
		func() -> void:
			work_point_selection_cleared.emit()
	)
	_input.loop_region_changed.connect(
		func(start_seconds: float, end_seconds: float) -> void:
			loop_region_changed.emit(start_seconds, end_seconds)
	)
	_input.playhead_seek_requested.connect(
		func(time_seconds: float) -> void:
			playhead_seek_requested.emit(time_seconds)
	)
	_input.selection_cleared.connect(
		func() -> void:
			selection_cleared.emit()
	)
	_input.timeline_interaction_started.connect(
		func() -> void:
			timeline_interaction_started.emit()
	)
	_input.timeline_interaction_committed.connect(
		func(kind: int, clip_id: String) -> void:
			timeline_interaction_committed.emit(kind, clip_id)
	)
	_input.audition_requested.connect(
		func() -> void:
			audition_requested.emit()
	)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return _input.can_drop_data(self, at_position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	_input.drop_data(self, at_position, data)


# ---------- Public API ----------

func set_timeline(t: CodaEventTimeline) -> void:
	_timeline = t
	_clamp_scroll()
	queue_redraw()
	update_minimum_size()


func set_track_row_highlight(track_index: int) -> void:
	if _timeline == null:
		return
	_highlight_track_index = clampi(track_index, 0, max(0, _timeline.tracks.size() - 1))
	queue_redraw()


func get_timeline() -> CodaEventTimeline:
	return _timeline


func get_scroll_seconds() -> float:
	return _scroll_seconds


func set_playhead(time_seconds: float) -> void:
	_playhead_seconds = max(0.0, time_seconds)
	queue_redraw()


func get_playhead() -> float:
	return _playhead_seconds


func get_track_row_height() -> int:
	return _track_row_height


func set_track_row_height(px: int) -> void:
	var h: int = clampi(px, MIN_TRACK_ROW_HEIGHT, MAX_TRACK_ROW_HEIGHT)
	if h == _track_row_height:
		return
	_track_row_height = h
	custom_minimum_size = Vector2(200, RULER_HEIGHT + _track_row_height)
	update_minimum_size()
	queue_redraw()


func set_zoom(seconds_per_pixel: float) -> void:
	_seconds_per_pixel = clampf(
		seconds_per_pixel, MIN_SECONDS_PER_PIXEL, MAX_SECONDS_PER_PIXEL
	)
	_clamp_scroll()
	queue_redraw()


func get_zoom() -> float:
	return _seconds_per_pixel


func set_snap_mode(mode: SnapMode) -> void:
	_snap_mode = mode


func get_snap_mode() -> SnapMode:
	return _snap_mode


func get_selected_clip_id() -> String:
	return _selected_clip_id


func get_selected_marker_id() -> String:
	return _selected_marker_id


func get_selected_work_point() -> String:
	return _selected_work_point


func set_selected_clip(clip_id: String) -> void:
	_selected_clip_id = clip_id
	queue_redraw()


func set_selected_marker(marker_id: String) -> void:
	if _selected_marker_id == marker_id:
		return
	_selected_marker_id = marker_id
	if not marker_id.is_empty():
		clear_work_point_selection()
		marker_selected.emit(marker_id)
	queue_redraw()


func set_selected_work_point(kind: String) -> void:
	if _selected_work_point == kind:
		return
	_selected_work_point = kind
	if not kind.is_empty():
		clear_marker_selection()
		work_point_selected.emit(kind)
	queue_redraw()


func clear_work_point_selection() -> void:
	if _selected_work_point.is_empty():
		return
	_selected_work_point = ""
	work_point_selection_cleared.emit()
	queue_redraw()


func clear_marker_selection() -> void:
	if _selected_marker_id.is_empty():
		return
	_selected_marker_id = ""
	marker_selection_cleared.emit()
	queue_redraw()


func zoom_timeline_to_fit(width_px: float, margin_px: float = 40.0) -> void:
	if _timeline == null or _timeline.length_seconds <= 0.001:
		return
	var usable: float = width_px - margin_px
	if usable < 32.0:
		return
	set_zoom(_timeline.length_seconds / usable)
	set_scroll_seconds(0.0)


func set_scroll_seconds(scroll: float) -> void:
	_scroll_seconds = max(0.0, scroll)
	queue_redraw()


func clear_selection() -> void:
	if _selected_clip_id.is_empty():
		return
	_selected_clip_id = ""
	selection_cleared.emit()
	queue_redraw()


func track_count() -> int:
	if _timeline == null:
		return 0
	return _timeline.tracks.size()


func open_clip_context_menu(clip_id: String, global_pos: Vector2i) -> void:
	if clip_id.is_empty():
		return
	_ensure_clip_menu()
	_menu_clip_id = clip_id
	set_selected_clip(clip_id)
	clip_selected.emit(clip_id)
	_clip_menu.popup(Rect2i(global_pos, Vector2i(1, 1)))


func open_marker_context_menu(marker_id: String, global_pos: Vector2i) -> void:
	if marker_id.is_empty():
		return
	set_selected_marker(marker_id)
	_ensure_marker_menu()
	_menu_marker_id = marker_id
	_marker_menu.popup(Rect2i(global_pos, Vector2i(1, 1)))


func open_work_point_context_menu(kind: String, global_pos: Vector2i) -> void:
	if kind.is_empty():
		return
	set_selected_work_point(kind)
	_ensure_work_point_menu(kind)
	_menu_work_point_kind = kind
	_work_point_menu.popup(Rect2i(global_pos, Vector2i(1, 1)))


# ---------- Drawing ----------

func _draw() -> void:
	Renderer.draw(self, _build_render_state())


func _build_render_state() -> Dictionary:
	var hints: Dictionary = _input.get_render_hints()
	return {
		"size": size,
		"timeline": _timeline,
		"scroll_seconds": _scroll_seconds,
		"seconds_per_pixel": _seconds_per_pixel,
		"track_row_height": _track_row_height,
		"highlight_track_index": _highlight_track_index,
		"selected_clip_id": _selected_clip_id,
		"selected_marker_id": _selected_marker_id,
		"selected_work_point": _selected_work_point,
		"playhead_seconds": _playhead_seconds,
		"snap_mode": int(_snap_mode),
		"has_focus": has_focus(),
		"theme_font": get_theme_default_font(),
		"ghost_new_track": hints.get("ghost_new_track", false),
		"hover_clip_edge": hints.get("hover_clip_edge", "none"),
		"drag_kind": hints.get("drag_kind", 0),
		"drag_clip_id": hints.get("drag_clip_id", ""),
	}


func _clamp_scroll() -> void:
	_scroll_seconds = max(0.0, _scroll_seconds)


# ---------- Input ----------

func _unhandled_key_input(event: InputEvent) -> void:
	_input.handle_unhandled_key(self, event)


func _gui_input(event: InputEvent) -> void:
	_input.handle_gui_input(self, event)


func update_hover_cursor() -> void:
	var edge: String = String(_input.get_render_hints().get("hover_clip_edge", "none"))
	match edge:
		"left", "right":
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		"fade_in", "fade_out":
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		"fade_in_shape", "fade_out_shape":
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		_:
			mouse_default_cursor_shape = Control.CURSOR_ARROW


func _ensure_clip_menu() -> void:
	if _clip_menu != null:
		return
	_clip_menu = PopupMenu.new()
	_clip_menu.name = "TimelineClipMenu"
	_clip_menu.add_item("Remove from timeline", _CTX_REMOVE_CLIP)
	_clip_menu.add_item("Duplicate", _CTX_DUPLICATE_CLIP)
	_clip_menu.add_item("Split at playhead", _CTX_SPLIT_PLAYHEAD)
	_clip_menu.about_to_popup.connect(_on_clip_menu_about_to_popup)
	_clip_menu.id_pressed.connect(_on_clip_menu_id_pressed)
	add_child(_clip_menu)


func _on_clip_menu_about_to_popup() -> void:
	if _clip_menu == null or _timeline == null:
		return
	var can_split: bool = false
	if not _menu_clip_id.is_empty():
		var inf: Dictionary = _timeline.find_clip(_menu_clip_id)
		if not inf.is_empty():
			var cl: CodaTimelineClip = inf.get("clip") as CodaTimelineClip
			if cl != null:
				var ph: float = _playhead_seconds
				var lo: float = cl.start_seconds + 0.02
				var hi: float = cl.start_seconds + cl.duration_seconds - 0.02
				can_split = ph > lo and ph < hi
	var idx_split: int = _clip_menu.get_item_index(_CTX_SPLIT_PLAYHEAD)
	if idx_split >= 0:
		_clip_menu.set_item_disabled(idx_split, not can_split)


func _on_clip_menu_id_pressed(id: int) -> void:
	if _menu_clip_id.is_empty():
		return
	match id:
		_CTX_REMOVE_CLIP:
			clip_delete_requested.emit(_menu_clip_id)
		_CTX_DUPLICATE_CLIP:
			clip_duplicate_requested.emit(_menu_clip_id)
		_CTX_SPLIT_PLAYHEAD:
			clip_split_at_playhead_requested.emit(_menu_clip_id)
	_menu_clip_id = ""


func _ensure_marker_menu() -> void:
	if _marker_menu != null:
		return
	_marker_menu = PopupMenu.new()
	_marker_menu.name = "TimelineMarkerMenu"
	_marker_menu.add_item("Rename", _CTX_MARKER_RENAME)
	_marker_menu.add_item("Delete", _CTX_MARKER_DELETE)
	_marker_menu.add_separator()
	_marker_menu.add_item("Go to time", _CTX_MARKER_GO_TO)
	_marker_menu.id_pressed.connect(_on_marker_menu_id_pressed)
	add_child(_marker_menu)


func _on_marker_menu_id_pressed(id: int) -> void:
	if _menu_marker_id.is_empty():
		return
	match id:
		_CTX_MARKER_RENAME:
			marker_rename_requested.emit(_menu_marker_id)
		_CTX_MARKER_DELETE:
			marker_delete_requested.emit(_menu_marker_id)
		_CTX_MARKER_GO_TO:
			marker_go_to_time_requested.emit(_menu_marker_id)
	_menu_marker_id = ""


func _ensure_work_point_menu(kind: String) -> void:
	if _work_point_menu != null:
		_work_point_menu.clear()
	else:
		_work_point_menu = PopupMenu.new()
		_work_point_menu.name = "TimelineWorkPointMenu"
		_work_point_menu.id_pressed.connect(_on_work_point_menu_id_pressed)
		add_child(_work_point_menu)
	var label: String = "Clear in point" if kind == "in" else "Clear out point"
	_work_point_menu.add_item(label, _CTX_WORK_POINT_DELETE)


func _on_work_point_menu_id_pressed(id: int) -> void:
	if _menu_work_point_kind.is_empty():
		return
	if id == _CTX_WORK_POINT_DELETE:
		work_point_delete_requested.emit(_menu_work_point_kind)
	_menu_work_point_kind = ""


# ---------- Sizing ----------

func _get_minimum_size() -> Vector2:
	var n: int = max(1, track_count())
	var extra_rows: int = 0
	if bool(_input.get_render_hints().get("ghost_new_track", false)):
		extra_rows = 1
	return Vector2(200, RULER_HEIGHT + (n + extra_rows) * _track_row_height)
