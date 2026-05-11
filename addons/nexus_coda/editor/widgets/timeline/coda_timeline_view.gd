@tool
class_name CodaTimelineView
extends Control

## Reusable view widget over a CodaEventTimeline.
## Pure presentation + interaction layer; the widget never touches CodaState — the host
## panel translates emitted signals into state mutations.
##
## Coordinates: time runs horizontally (seconds), tracks stack vertically. The ruler at
## the top of the widget shows seconds (and optional bars/beats when `tempo_bpm > 0`).
## Track lane heights are constant so the host panel can render aligned track headers
## next to the widget.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")

const RULER_HEIGHT := 22
const TRACK_HEIGHT := 48
const TRACK_HEADER_GAP := 1
const CLIP_INNER_PADDING := 2
const MIN_CLIP_WIDTH_PX := 4
const EDGE_RESIZE_THRESHOLD := 6

const DEFAULT_SECONDS_PER_PIXEL := 1.0 / 80.0
const MIN_SECONDS_PER_PIXEL := 1.0 / 1024.0
const MAX_SECONDS_PER_PIXEL := 0.5

enum SnapMode { NONE = 0, TENTHS = 1, BARS_BEATS = 2 }

enum DragKind {
	NONE = 0,
	CLIP_MOVE = 1,
	CLIP_RESIZE_LEFT = 2,
	CLIP_RESIZE_RIGHT = 3,
	MARKER_MOVE = 4,
	LOOP_START = 5,
	LOOP_END = 6,
	PAN = 7,
	PLAYHEAD_SEEK = 8,
}

signal browser_asset_dropped(track_index: int, start_seconds: float, res_audio_path: String)
signal clip_selected(clip_id: String)
signal clip_moved(clip_id: String, new_start: float)
signal clip_resized(clip_id: String, new_start: float, new_duration: float)
signal marker_changed(marker_id: String, new_time: float)
signal marker_double_clicked(marker_id: String)
signal loop_region_changed(start_seconds: float, end_seconds: float)
signal playhead_seek_requested(time_seconds: float)
signal selection_cleared

var _timeline: CodaEventTimeline = null
var _seconds_per_pixel: float = DEFAULT_SECONDS_PER_PIXEL
var _scroll_seconds: float = 0.0
var _playhead_seconds: float = 0.0
var _snap_mode: SnapMode = SnapMode.NONE

var _drag_kind: DragKind = DragKind.NONE
var _drag_clip_id: String = ""
var _drag_track_id: String = ""
var _drag_start_seconds: float = 0.0
var _drag_initial_clip_start: float = 0.0
var _drag_initial_clip_duration: float = 0.0
var _drag_marker_id: String = ""
var _drag_initial_loop_start: float = 0.0
var _drag_initial_loop_end: float = 0.0
var _drag_pan_initial_scroll: float = 0.0
var _drag_initial_screen_pos: Vector2 = Vector2.ZERO
var _selected_clip_id: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(200, RULER_HEIGHT + TRACK_HEIGHT)
	clip_contents = true


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _timeline == null or track_count() <= 0:
		return false
	if _timeline_drop_audio_res_path(data).is_empty():
		return false
	return _track_index_for_drop_y(at_position.y) >= 0


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var path: String = _timeline_drop_audio_res_path(data)
	if path.is_empty():
		return
	var track_index: int = _track_index_for_drop_y(at_position.y)
	if track_index < 0:
		return
	var t_start: float = _apply_snap(_x_to_seconds(at_position.x))
	browser_asset_dropped.emit(track_index, t_start, path)


func _timeline_drop_audio_res_path(data: Variant) -> String:
	if not (data is Dictionary):
		return ""
	var d: Dictionary = data as Dictionary
	var direct: String = str(d.get("coda_asset_source_path", "")).strip_edges()
	if direct.begins_with("res://"):
		return direct
	var t: String = str(d.get("type", ""))
	if not t.is_empty() and t != "files" and t != "files_and_dirs":
		return ""
	var raw: Variant = d.get("files", null)
	var paths: PackedStringArray = PackedStringArray()
	if raw is PackedStringArray:
		for p in raw as PackedStringArray:
			paths.append(str(p).strip_edges())
	elif raw is Array:
		for p in raw as Array:
			paths.append(str(p).strip_edges())
	if paths.size() != 1:
		return ""
	var one: String = paths[0]
	if not one.begins_with("res://"):
		return ""
	if not _timeline_drop_audio_extension_allowed(String(one.get_extension())):
		return ""
	return one


func _timeline_drop_audio_extension_allowed(ext: String) -> bool:
	match String(ext).to_lower():
		"wav", "ogg", "oga", "mp3", "flac":
			return true
		_:
			return false


func _track_index_for_drop_y(y: float) -> int:
	var n: int = track_count()
	if n <= 0:
		return -1
	if y < RULER_HEIGHT:
		return 0
	var idx: int = int((y - RULER_HEIGHT) / TRACK_HEIGHT)
	return clampi(idx, 0, n - 1)


# ---------- Public API ----------

func set_timeline(t: CodaEventTimeline) -> void:
	_timeline = t
	_clamp_scroll()
	queue_redraw()
	update_minimum_size()


func get_timeline() -> CodaEventTimeline:
	return _timeline


func set_playhead(time_seconds: float) -> void:
	_playhead_seconds = max(0.0, time_seconds)
	queue_redraw()


func get_playhead() -> float:
	return _playhead_seconds


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


# ---------- Drawing ----------

func _draw() -> void:
	var area: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(area, Tokens.SURFACE_BG, true)

	if _timeline == null:
		_draw_placeholder()
		return

	_draw_track_lanes()
	_draw_loop_region()
	_draw_clips()
	_draw_ruler()
	_draw_markers()
	_draw_playhead()
	if has_focus():
		var focus_rect := Rect2(Vector2.ZERO, size)
		draw_rect(focus_rect, Tokens.ACCENT_DIM, false, 1.0)


func _draw_placeholder() -> void:
	var msg: String = "No timeline"
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var size_px: int = Tokens.FONT_BODY_SIZE
	var text_size: Vector2 = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, size_px)
	var pos: Vector2 = (size - text_size) * 0.5
	draw_string(font, pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Tokens.TEXT_MUTED)


func _draw_track_lanes() -> void:
	var n: int = track_count()
	for i in n:
		var rect: Rect2 = _track_lane_rect(i)
		var bg: Color = Tokens.SURFACE_RAISED if i % 2 == 0 else Tokens.SURFACE_SUNKEN
		draw_rect(rect, bg, true)
	# Bottom edge of lanes section.
	var lane_bottom: float = float(RULER_HEIGHT + n * TRACK_HEIGHT)
	draw_line(
		Vector2(0, lane_bottom), Vector2(size.x, lane_bottom), Tokens.SURFACE_BORDER, 1.0
	)


func _draw_clips() -> void:
	if _timeline == null:
		return
	for i in _timeline.tracks.size():
		var track: CodaTimelineTrack = _timeline.tracks[i]
		var lane: Rect2 = _track_lane_rect(i)
		for clip in track.clips:
			_draw_one_clip(clip, lane)


func _draw_one_clip(clip: CodaTimelineClip, lane: Rect2) -> void:
	var x_start: float = _seconds_to_x(clip.start_seconds)
	var x_end: float = _seconds_to_x(clip.start_seconds + clip.duration_seconds)
	if x_end < lane.position.x or x_start > lane.position.x + lane.size.x:
		return  # offscreen
	var rect: Rect2 = Rect2(
		Vector2(x_start, lane.position.y + CLIP_INNER_PADDING),
		Vector2(max(MIN_CLIP_WIDTH_PX, x_end - x_start), lane.size.y - 2 * CLIP_INNER_PADDING)
	)
	var fill: Color = Tokens.ACCENT_DIM
	var border: Color = Tokens.ACCENT
	if clip.id == _selected_clip_id:
		fill = Tokens.ACCENT
		border = Tokens.TEXT_PRIMARY
	draw_rect(rect, Color(fill.r, fill.g, fill.b, 0.55), true)
	draw_rect(rect, border, false, 1.0)
	# Clip label.
	var font: Font = get_theme_default_font()
	if font != null and rect.size.x > 24:
		var label: String = clip.audio_path.get_file() if not clip.audio_path.is_empty() else "Clip"
		var size_px: int = Tokens.FONT_LABEL_SIZE
		var pos: Vector2 = Vector2(rect.position.x + 4, rect.position.y + size_px + 2)
		draw_string(
			font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, size_px,
			Tokens.TEXT_PRIMARY
		)


func _draw_loop_region() -> void:
	if _timeline == null or not _timeline.loop_enabled:
		return
	var x0: float = _seconds_to_x(_timeline.loop_start_seconds)
	var x1: float = _seconds_to_x(_timeline.loop_end_seconds)
	if x1 <= x0:
		return
	var rect_full: Rect2 = Rect2(
		Vector2(x0, RULER_HEIGHT), Vector2(x1 - x0, size.y - RULER_HEIGHT)
	)
	draw_rect(
		rect_full, Color(Tokens.SUCCESS.r, Tokens.SUCCESS.g, Tokens.SUCCESS.b, 0.10), true
	)
	draw_line(Vector2(x0, RULER_HEIGHT), Vector2(x0, size.y), Tokens.SUCCESS, 1.0)
	draw_line(Vector2(x1, RULER_HEIGHT), Vector2(x1, size.y), Tokens.SUCCESS, 1.0)


func _draw_ruler() -> void:
	var ruler_rect: Rect2 = Rect2(0, 0, size.x, float(RULER_HEIGHT))
	draw_rect(ruler_rect, Tokens.SURFACE_RAISED, true)
	draw_line(
		Vector2(0, RULER_HEIGHT), Vector2(size.x, RULER_HEIGHT), Tokens.SURFACE_BORDER, 1.0
	)
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var step: float = _ruler_step_seconds()
	if step <= 0.0:
		return
	var first_tick: float = floorf(_scroll_seconds / step) * step
	var t: float = first_tick
	var lim: float = _scroll_seconds + size.x * _seconds_per_pixel
	var size_px: int = Tokens.FONT_LABEL_SIZE
	while t <= lim + step:
		if t >= 0.0:
			var x: float = _seconds_to_x(t)
			draw_line(
				Vector2(x, RULER_HEIGHT - 6), Vector2(x, RULER_HEIGHT), Tokens.TEXT_MUTED, 1.0
			)
			var label: String = _format_ruler_time(t, step)
			draw_string(
				font, Vector2(x + 3, size_px + 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px,
				Tokens.TEXT_SECONDARY
			)
		t += step


func _draw_markers() -> void:
	if _timeline == null:
		return
	var font: Font = get_theme_default_font()
	for m in _timeline.markers:
		var x: float = _seconds_to_x(m.time_seconds)
		if x < 0 or x > size.x:
			continue
		var col: Color = _color_for_marker(m)
		draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
		if font != null:
			draw_string(
				font, Vector2(x + 3, RULER_HEIGHT - 6), m.marker_name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_LABEL_SIZE, col
			)


func _draw_playhead() -> void:
	var x: float = _seconds_to_x(_playhead_seconds)
	if x < 0 or x > size.x:
		return
	draw_line(Vector2(x, 0), Vector2(x, size.y), Tokens.ACCENT, 2.0)


# ---------- Geometry helpers ----------

func _track_lane_rect(track_index: int) -> Rect2:
	return Rect2(
		Vector2(0, RULER_HEIGHT + track_index * TRACK_HEIGHT),
		Vector2(size.x, TRACK_HEIGHT - TRACK_HEADER_GAP)
	)


func _seconds_to_x(t: float) -> float:
	if _seconds_per_pixel <= 0.0:
		return 0.0
	return (t - _scroll_seconds) / _seconds_per_pixel


func _x_to_seconds(x: float) -> float:
	return x * _seconds_per_pixel + _scroll_seconds


func _ruler_step_seconds() -> float:
	# Pick a "nice" step size (1, 2, 5, 10 …) that yields ~80 px between ticks.
	var ideal_seconds_per_step: float = _seconds_per_pixel * 80.0
	if ideal_seconds_per_step <= 0.0:
		return 1.0
	var pow10: float = pow(10.0, floor(log(ideal_seconds_per_step) / log(10.0)))
	var ratio: float = ideal_seconds_per_step / pow10
	var snap: float = 1.0
	if ratio > 5.0:
		snap = 10.0
	elif ratio > 2.0:
		snap = 5.0
	elif ratio > 1.0:
		snap = 2.0
	return snap * pow10


func _format_ruler_time(seconds: float, step: float) -> String:
	if _timeline != null and _timeline.tempo_bpm > 0.0 and _snap_mode == SnapMode.BARS_BEATS:
		var beat_seconds: float = 60.0 / _timeline.tempo_bpm
		var beats: float = seconds / beat_seconds
		var num: int = max(1, _timeline.time_signature.x)
		var bar: int = int(floor(beats / float(num))) + 1
		var beat: int = int(floor(beats)) % num + 1
		return "%d.%d" % [bar, beat]
	var precision: int = 2 if step < 0.5 else (1 if step < 5.0 else 0)
	if precision == 0:
		return "%ds" % int(round(seconds))
	if precision == 1:
		return "%.1fs" % seconds
	return "%.2fs" % seconds


func _color_for_marker(m: CodaTimelineMarker) -> Color:
	match m.kind:
		CodaTimelineMarker.Kind.TRANSITION:
			return Tokens.WARN
		CodaTimelineMarker.Kind.CUE:
			return Tokens.SUCCESS
	return Tokens.TEXT_SECONDARY


# ---------- Snap & clamp ----------

func _apply_snap(t: float) -> float:
	t = max(0.0, t)
	if _timeline != null:
		t = clampf(t, 0.0, _timeline.length_seconds)
	if _snap_mode == SnapMode.NONE:
		return t
	var step: float = _snap_step_seconds()
	if step <= 0.0:
		return t
	return round(t / step) * step


func _snap_step_seconds() -> float:
	if _snap_mode == SnapMode.TENTHS:
		return 0.1
	if _snap_mode == SnapMode.BARS_BEATS:
		if _timeline != null and _timeline.tempo_bpm > 0.0:
			return 60.0 / _timeline.tempo_bpm
		return 0.1
	return 0.0


func _clamp_scroll() -> void:
	_scroll_seconds = max(0.0, _scroll_seconds)


# ---------- Hit testing ----------

func _hit_test(local_pos: Vector2) -> Dictionary:
	var on_ruler: bool = local_pos.y < RULER_HEIGHT
	if on_ruler:
		var marker := _hit_marker_near(local_pos.x)
		if marker != null:
			return {"kind": "marker", "marker_id": marker.id}
		return {"kind": "ruler"}
	if _timeline == null:
		return {"kind": "empty"}
	if _timeline.loop_enabled:
		var loop_x0: float = _seconds_to_x(_timeline.loop_start_seconds)
		var loop_x1: float = _seconds_to_x(_timeline.loop_end_seconds)
		if abs(local_pos.x - loop_x0) <= EDGE_RESIZE_THRESHOLD:
			return {"kind": "loop_start"}
		if abs(local_pos.x - loop_x1) <= EDGE_RESIZE_THRESHOLD:
			return {"kind": "loop_end"}
	var track_index: int = _track_index_at_y(local_pos.y)
	if track_index < 0:
		return {"kind": "empty"}
	var t: float = _x_to_seconds(local_pos.x)
	var track: CodaTimelineTrack = _timeline.tracks[track_index]
	for clip in track.clips:
		if t < clip.start_seconds or t > clip.start_seconds + clip.duration_seconds:
			continue
		var clip_x0: float = _seconds_to_x(clip.start_seconds)
		var clip_x1: float = _seconds_to_x(clip.start_seconds + clip.duration_seconds)
		var dist_l: float = abs(local_pos.x - clip_x0)
		var dist_r: float = abs(local_pos.x - clip_x1)
		var edge: String = "none"
		if dist_l <= EDGE_RESIZE_THRESHOLD and dist_l < dist_r:
			edge = "left"
		elif dist_r <= EDGE_RESIZE_THRESHOLD:
			edge = "right"
		return {"kind": "clip", "clip_id": clip.id, "track_id": track.id, "edge": edge}
	return {"kind": "lane", "track_id": track.id, "time": t}


func _track_index_at_y(y: float) -> int:
	if y < RULER_HEIGHT:
		return -1
	var n: int = track_count()
	if n == 0:
		return -1
	var idx: int = int((y - RULER_HEIGHT) / TRACK_HEIGHT)
	if idx < 0 or idx >= n:
		return -1
	return idx


func _hit_marker_near(x: float) -> CodaTimelineMarker:
	if _timeline == null:
		return null
	var best_marker: CodaTimelineMarker = null
	var best_dist: float = 6.0
	for m in _timeline.markers:
		var mx: float = _seconds_to_x(m.time_seconds)
		var d: float = abs(mx - x)
		if d < best_dist:
			best_dist = d
			best_marker = m
	return best_marker


# ---------- Input ----------

func _gui_input(event: InputEvent) -> void:
	if _timeline == null:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_zoom_around(mb.position, 0.85)
		accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_zoom_around(mb.position, 1.15)
		accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		if mb.pressed:
			_drag_kind = DragKind.PAN
			_drag_pan_initial_scroll = _scroll_seconds
			_drag_initial_screen_pos = mb.position
		else:
			_end_drag()
		accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		grab_focus()
		var hit: Dictionary = _hit_test(mb.position)
		_begin_drag(hit, mb)
	else:
		_end_drag()
	accept_event()


func _handle_mouse_motion(mm: InputEventMouseMotion) -> void:
	if _drag_kind == DragKind.NONE:
		return
	var t: float = _x_to_seconds(mm.position.x)
	match _drag_kind:
		DragKind.PAN:
			var delta_px: float = mm.position.x - _drag_initial_screen_pos.x
			_scroll_seconds = max(0.0, _drag_pan_initial_scroll - delta_px * _seconds_per_pixel)
			queue_redraw()
		DragKind.PLAYHEAD_SEEK:
			var snapped: float = _apply_snap(t)
			set_playhead(snapped)
			playhead_seek_requested.emit(snapped)
		DragKind.CLIP_MOVE:
			var raw_start: float = (
				_drag_initial_clip_start + (t - _drag_start_seconds)
			)
			var snapped_start: float = _apply_snap(raw_start)
			_apply_clip_move(_drag_clip_id, snapped_start)
			clip_moved.emit(_drag_clip_id, snapped_start)
		DragKind.CLIP_RESIZE_LEFT:
			var anchor_end: float = _drag_initial_clip_start + _drag_initial_clip_duration
			var new_start: float = clampf(_apply_snap(t), 0.0, anchor_end - 0.01)
			_apply_clip_resize(_drag_clip_id, new_start, anchor_end - new_start)
			clip_resized.emit(_drag_clip_id, new_start, anchor_end - new_start)
		DragKind.CLIP_RESIZE_RIGHT:
			var new_end: float = max(
				_drag_initial_clip_start + 0.01, _apply_snap(t)
			)
			var new_dur: float = new_end - _drag_initial_clip_start
			_apply_clip_resize(_drag_clip_id, _drag_initial_clip_start, new_dur)
			clip_resized.emit(_drag_clip_id, _drag_initial_clip_start, new_dur)
		DragKind.MARKER_MOVE:
			var marker_t: float = _apply_snap(t)
			_apply_marker_move(_drag_marker_id, marker_t)
			marker_changed.emit(_drag_marker_id, marker_t)
		DragKind.LOOP_START:
			var ls: float = clampf(_apply_snap(t), 0.0, _timeline.loop_end_seconds - 0.01)
			_timeline.loop_start_seconds = ls
			loop_region_changed.emit(ls, _timeline.loop_end_seconds)
			queue_redraw()
		DragKind.LOOP_END:
			var le: float = max(_timeline.loop_start_seconds + 0.01, _apply_snap(t))
			_timeline.loop_end_seconds = le
			loop_region_changed.emit(_timeline.loop_start_seconds, le)
			queue_redraw()


func _begin_drag(hit: Dictionary, mb: InputEventMouseButton) -> void:
	var k: String = String(hit.get("kind", ""))
	_drag_initial_screen_pos = mb.position
	_drag_start_seconds = _x_to_seconds(mb.position.x)
	if k == "ruler":
		_drag_kind = DragKind.PLAYHEAD_SEEK
		var snapped: float = _apply_snap(_drag_start_seconds)
		set_playhead(snapped)
		playhead_seek_requested.emit(snapped)
		return
	if k == "marker":
		var marker_id: String = String(hit.get("marker_id", ""))
		if mb.double_click:
			marker_double_clicked.emit(marker_id)
			_drag_kind = DragKind.NONE
			return
		_drag_kind = DragKind.MARKER_MOVE
		_drag_marker_id = marker_id
		return
	if k == "loop_start":
		_drag_kind = DragKind.LOOP_START
		_drag_initial_loop_start = _timeline.loop_start_seconds
		_drag_initial_loop_end = _timeline.loop_end_seconds
		return
	if k == "loop_end":
		_drag_kind = DragKind.LOOP_END
		_drag_initial_loop_start = _timeline.loop_start_seconds
		_drag_initial_loop_end = _timeline.loop_end_seconds
		return
	if k == "clip":
		var clip_id: String = String(hit.get("clip_id", ""))
		_drag_clip_id = clip_id
		_drag_track_id = String(hit.get("track_id", ""))
		var info: Dictionary = _timeline.find_clip(clip_id)
		if info.is_empty():
			_drag_kind = DragKind.NONE
			return
		var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
		_drag_initial_clip_start = clip.start_seconds
		_drag_initial_clip_duration = clip.duration_seconds
		_selected_clip_id = clip_id
		clip_selected.emit(clip_id)
		queue_redraw()
		match String(hit.get("edge", "none")):
			"left":
				_drag_kind = DragKind.CLIP_RESIZE_LEFT
			"right":
				_drag_kind = DragKind.CLIP_RESIZE_RIGHT
			_:
				_drag_kind = DragKind.CLIP_MOVE
		return
	if k == "lane":
		_selected_clip_id = ""
		selection_cleared.emit()
		queue_redraw()
		_drag_kind = DragKind.NONE
		return


func _end_drag() -> void:
	_drag_kind = DragKind.NONE
	_drag_clip_id = ""
	_drag_track_id = ""
	_drag_marker_id = ""


func _apply_clip_move(clip_id: String, new_start: float) -> void:
	if _timeline == null:
		return
	var info: Dictionary = _timeline.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	var clamped: float = clampf(new_start, 0.0, max(0.0, _timeline.length_seconds - clip.duration_seconds))
	clip.start_seconds = clamped
	queue_redraw()


func _apply_clip_resize(clip_id: String, new_start: float, new_duration: float) -> void:
	if _timeline == null:
		return
	var info: Dictionary = _timeline.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	clip.start_seconds = max(0.0, new_start)
	clip.duration_seconds = max(0.0, new_duration)
	queue_redraw()


func _apply_marker_move(marker_id: String, new_time: float) -> void:
	if _timeline == null:
		return
	var m: CodaTimelineMarker = _timeline.find_marker(marker_id)
	if m == null:
		return
	m.time_seconds = clampf(new_time, 0.0, _timeline.length_seconds)
	queue_redraw()


func _zoom_around(pos: Vector2, factor: float) -> void:
	var time_at_cursor: float = _x_to_seconds(pos.x)
	_seconds_per_pixel = clampf(
		_seconds_per_pixel * factor, MIN_SECONDS_PER_PIXEL, MAX_SECONDS_PER_PIXEL
	)
	# Keep the time under the cursor stable on screen.
	_scroll_seconds = max(0.0, time_at_cursor - pos.x * _seconds_per_pixel)
	queue_redraw()


# ---------- Sizing ----------

func _get_minimum_size() -> Vector2:
	var n: int = max(1, track_count())
	return Vector2(200, RULER_HEIGHT + n * TRACK_HEIGHT)
