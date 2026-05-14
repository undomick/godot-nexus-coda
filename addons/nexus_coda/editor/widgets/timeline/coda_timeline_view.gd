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

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const CodaTimelineWaveformCacheScript := preload(
	"res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_waveform_cache.gd"
)

const RULER_HEIGHT := 22
## Two-line track headers (name + M/S/controls) need more than a single compact lane row.
const DEFAULT_TRACK_ROW_HEIGHT := 92
const MIN_TRACK_ROW_HEIGHT := 88
const MAX_TRACK_ROW_HEIGHT := 200
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
signal clip_audio_assign_requested(clip_id: String, res_audio_path: String)
signal track_row_selected(track_index: int)
signal clip_selected(clip_id: String)
signal clip_moved(clip_id: String, new_start: float, new_track_index: int)
signal clip_resized(clip_id: String, new_start: float, new_duration: float)
signal clip_delete_requested(clip_id: String)
signal marker_changed(marker_id: String, new_time: float)
signal marker_double_clicked(marker_id: String)
signal loop_region_changed(start_seconds: float, end_seconds: float)
signal playhead_seek_requested(time_seconds: float)
signal selection_cleared
## Emitted once when a drag begins that should participate in host-side undo batching.
signal timeline_interaction_started
signal clip_duplicate_requested(clip_id: String)
signal clip_split_at_playhead_requested(clip_id: String)
signal audition_requested

var _timeline: CodaEventTimeline = null
var _seconds_per_pixel: float = DEFAULT_SECONDS_PER_PIXEL
var _scroll_seconds: float = 0.0
var _playhead_seconds: float = 0.0
var _snap_mode: SnapMode = SnapMode.NONE
var _track_row_height: int = DEFAULT_TRACK_ROW_HEIGHT

var _drag_kind: DragKind = DragKind.NONE
var _drag_clip_id: String = ""
var _drag_track_id: String = ""
var _drag_start_seconds: float = 0.0
var _drag_initial_clip_start: float = 0.0
var _drag_initial_clip_duration: float = 0.0
## Source trim baseline when dragging the clip's left edge ([member CodaTimelineClip.offset_seconds] at drag start).
var _drag_initial_clip_offset: float = 0.0
var _drag_marker_id: String = ""
var _drag_initial_loop_start: float = 0.0
var _drag_initial_loop_end: float = 0.0
var _drag_pan_initial_scroll: float = 0.0
var _drag_initial_screen_pos: Vector2 = Vector2.ZERO
var _selected_clip_id: String = ""
var _highlight_track_index: int = 0

var _clip_menu: PopupMenu
const _CTX_REMOVE_CLIP := 1
const _CTX_DUPLICATE_CLIP := 2
const _CTX_SPLIT_PLAYHEAD := 3
var _menu_clip_id: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(200, RULER_HEIGHT + _track_row_height)
	clip_contents = true


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if _timeline == null or track_count() <= 0:
		return false
	if _timeline_drop_audio_res_path(data).is_empty():
		return false
	var hit: Dictionary = _hit_test(at_position)
	if String(hit.get("kind", "")) == "clip":
		return true
	return _track_index_for_drop_y(at_position.y) >= 0


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var path: String = _timeline_drop_audio_res_path(data)
	if path.is_empty():
		return
	var hit: Dictionary = _hit_test(at_position)
	if String(hit.get("kind", "")) == "clip":
		var cid: String = String(hit.get("clip_id", ""))
		if not cid.is_empty():
			clip_audio_assign_requested.emit(cid, path)
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
	var idx: int = int((y - RULER_HEIGHT) / _track_row_height)
	return clampi(idx, 0, n - 1)


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
		var tr: CodaTimelineTrack = _timeline.tracks[i]
		var ac: Color = Tokens.ACCENT if tr.color.a <= 0.001 else tr.color
		draw_rect(rect, Color(ac.r, ac.g, ac.b, 0.10), true)
		if i == _highlight_track_index and n > 0:
			draw_rect(rect, Color(Tokens.ACCENT.r, Tokens.ACCENT.g, Tokens.ACCENT.b, 0.12), true)
			draw_rect(rect, Tokens.ACCENT_DIM, false, 1.0)
	# Bottom edge of lanes section.
	var lane_bottom: float = float(RULER_HEIGHT + n * _track_row_height)
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
	_draw_clip_waveform(clip, rect)
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
		Vector2(0, RULER_HEIGHT + track_index * _track_row_height),
		Vector2(size.x, _track_row_height)
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
	var raw: float = max(0.0, t)
	if _timeline != null:
		raw = clampf(raw, 0.0, _timeline.length_seconds)
	var thresh_sec: float = _seconds_per_pixel * 8.0
	var best: float = raw
	var best_d: float = thresh_sec + 1.0
	for cand in _snap_candidate_times(raw):
		var cd: float = abs(cand - raw)
		if cd < best_d:
			best_d = cd
			best = cand
	if best_d <= thresh_sec:
		raw = best
	if _snap_mode == SnapMode.NONE:
		return raw
	var step: float = _snap_step_seconds()
	if step <= 0.0:
		return raw
	return round(raw / step) * step


func _snap_candidate_times(for_time: float) -> Array[float]:
	var out: Array[float] = []
	if _timeline == null:
		return out
	out.append(0.0)
	out.append(_timeline.length_seconds)
	if _timeline.loop_enabled:
		out.append(_timeline.loop_start_seconds)
		out.append(_timeline.loop_end_seconds)
	for m in _timeline.markers:
		out.append(m.time_seconds)
	for tr in _timeline.tracks:
		for cl in tr.clips:
			out.append(cl.start_seconds)
			out.append(cl.start_seconds + cl.duration_seconds)
	if _snap_mode != SnapMode.NONE:
		var step: float = _snap_step_seconds()
		if step > 0.0:
			out.append(round(for_time / step) * step)
	return out


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
		return {
			"kind": "clip",
			"clip_id": clip.id,
			"track_id": track.id,
			"track_index": track_index,
			"edge": edge,
		}
	return {"kind": "lane", "track_id": track.id, "track_index": track_index, "time": t}


func _track_index_at_y(y: float) -> int:
	if y < RULER_HEIGHT:
		return -1
	var n: int = track_count()
	if n == 0:
		return -1
	var idx: int = int((y - RULER_HEIGHT) / _track_row_height)
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

func _unhandled_key_input(event: InputEvent) -> void:
	if _timeline == null or not is_visible_in_tree():
		return
	if not has_focus():
		return
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_SPACE:
			audition_requested.emit()
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if _timeline == null:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	if (
		mb.pressed
		and (
			mb.button_index == MOUSE_BUTTON_WHEEL_UP
			or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		)
	):
		if mb.shift_pressed:
			var dir: float = 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
			var step_sec: float = _seconds_per_pixel * 48.0
			_scroll_seconds = max(0.0, _scroll_seconds + dir * step_sec)
			queue_redraw()
			accept_event()
			return
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
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			var hit_r: Dictionary = _hit_test(mb.position)
			if String(hit_r.get("kind", "")) == "clip":
				_ensure_clip_menu()
				_menu_clip_id = String(hit_r.get("clip_id", ""))
				if not _menu_clip_id.is_empty():
					_selected_clip_id = _menu_clip_id
					clip_selected.emit(_menu_clip_id)
					var gp: Vector2i = Vector2i(int(get_global_mouse_position().x), int(get_global_mouse_position().y))
					_clip_menu.popup(Rect2i(gp, Vector2i(1, 1)))
					queue_redraw()
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
			var target_idx: int = clampi(_track_index_at_y(mm.position.y), 0, max(0, track_count() - 1))
			_move_clip_to_track(_drag_clip_id, target_idx, snapped_start)
			var info_mv: Dictionary = _timeline.find_clip(_drag_clip_id)
			if not info_mv.is_empty():
				var cl_mv: CodaTimelineClip = info_mv.get("clip") as CodaTimelineClip
				var tr_mv: CodaTimelineTrack = info_mv.get("track") as CodaTimelineTrack
				if cl_mv != null and tr_mv != null:
					var ti_mv: int = _track_index_by_id(tr_mv.id)
					clip_moved.emit(_drag_clip_id, cl_mv.start_seconds, ti_mv)
		DragKind.CLIP_RESIZE_LEFT:
			var info_l: Dictionary = _timeline.find_clip(_drag_clip_id)
			var clip_l: CodaTimelineClip = info_l.get("clip") as CodaTimelineClip
			if clip_l == null:
				return
			var anchor_end: float = _drag_initial_clip_start + _drag_initial_clip_duration
			# Keep offset_seconds in sync with timeline trim so the audible segment stays correct.
			var min_start: float = maxf(0.0, _drag_initial_clip_start - _drag_initial_clip_offset)
			var new_start: float = clampf(_apply_snap(t), min_start, anchor_end - 0.01)
			var new_dur: float = anchor_end - new_start
			var new_off: float = maxf(
				0.0, _drag_initial_clip_offset + new_start - _drag_initial_clip_start
			)
			_apply_clip_resize(_drag_clip_id, new_start, new_dur, new_off)
			clip_resized.emit(_drag_clip_id, clip_l.start_seconds, clip_l.duration_seconds)
		DragKind.CLIP_RESIZE_RIGHT:
			var info_r: Dictionary = _timeline.find_clip(_drag_clip_id)
			var clip_r: CodaTimelineClip = info_r.get("clip") as CodaTimelineClip
			var max_play_r: float = (
				clip_r.max_source_playable_seconds() if clip_r != null else 1.0e12
			)
			var max_end: float = minf(
				_timeline.length_seconds,
				_drag_initial_clip_start + max_play_r
			)
			var new_end: float = clampf(
				max(_drag_initial_clip_start + 0.01, _apply_snap(t)),
				_drag_initial_clip_start + 0.01,
				max_end
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
		timeline_interaction_started.emit()
		return
	if k == "loop_start":
		_drag_kind = DragKind.LOOP_START
		_drag_initial_loop_start = _timeline.loop_start_seconds
		_drag_initial_loop_end = _timeline.loop_end_seconds
		timeline_interaction_started.emit()
		return
	if k == "loop_end":
		_drag_kind = DragKind.LOOP_END
		_drag_initial_loop_start = _timeline.loop_start_seconds
		_drag_initial_loop_end = _timeline.loop_end_seconds
		timeline_interaction_started.emit()
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
		_drag_initial_clip_offset = clip.offset_seconds
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
		timeline_interaction_started.emit()
		return
	if k == "lane":
		var lane_idx: int = int(hit.get("track_index", -1))
		if lane_idx >= 0:
			track_row_selected.emit(lane_idx)
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


func _track_index_by_id(track_id: String) -> int:
	if _timeline == null or track_id.is_empty():
		return -1
	for i in _timeline.tracks.size():
		if _timeline.tracks[i].id == track_id:
			return i
	return -1


func _move_clip_to_track(clip_id: String, target_track_index: int, new_start: float) -> void:
	if _timeline == null or _timeline.tracks.is_empty():
		return
	var info: Dictionary = _timeline.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	var from_track: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
	if clip == null or from_track == null:
		return
	target_track_index = clampi(target_track_index, 0, _timeline.tracks.size() - 1)
	var max_start: float = max(0.0, _timeline.length_seconds - clip.duration_seconds)
	var clamped_start: float = clampf(new_start, 0.0, max_start)
	var to_track: CodaTimelineTrack = _timeline.tracks[target_track_index]
	if from_track == to_track:
		clip.start_seconds = clamped_start
	else:
		from_track.clips.erase(clip)
		to_track.clips.append(clip)
		clip.start_seconds = clamped_start
	queue_redraw()


func _draw_clip_waveform(clip: CodaTimelineClip, rect: Rect2) -> void:
	if clip.audio_path.is_empty():
		return
	var h_wave: float = maxf(4.0, rect.size.y * 0.32)
	var top: float = rect.position.y + rect.size.y - h_wave - 2.0
	var wave_rect := Rect2(Vector2(rect.position.x + 2.0, top), Vector2(rect.size.x - 4.0, h_wave))
	if wave_rect.size.x < 10.0:
		return
	var bucket_count: int = clampi(int(wave_rect.size.x / 3.0), 8, 128)
	var peaks: PackedFloat32Array = CodaTimelineWaveformCacheScript.peaks_for_clip_segment(
		clip.audio_path, clip.offset_seconds, clip.duration_seconds, bucket_count
	)
	if peaks.is_empty():
		return
	var n: int = peaks.size()
	if n <= 0:
		return
	var step_x: float = wave_rect.size.x / float(max(1, n - 1))
	var mid_y: float = wave_rect.position.y + wave_rect.size.y * 0.5
	var col := Color(Tokens.TEXT_PRIMARY.r, Tokens.TEXT_PRIMARY.g, Tokens.TEXT_PRIMARY.b, 0.4)
	for i in n:
		var pk: float = peaks[i]
		var bar_h: float = maxf(1.0, wave_rect.size.y * pk)
		var x0: float = wave_rect.position.x + float(i) * step_x
		var bar_w: float = maxf(1.0, step_x * 0.72)
		draw_rect(
			Rect2(Vector2(x0 - bar_w * 0.5, mid_y - bar_h * 0.5), Vector2(bar_w, bar_h)),
			col,
			true
		)


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


func _apply_clip_resize(
	clip_id: String, new_start: float, new_duration: float, new_offset_seconds: float = NAN
) -> void:
	if _timeline == null:
		return
	var info: Dictionary = _timeline.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	clip.start_seconds = max(0.0, new_start)
	if new_offset_seconds == new_offset_seconds:
		clip.offset_seconds = maxf(0.0, new_offset_seconds)
	var max_by_source: float = clip.max_source_playable_seconds()
	var max_by_tl: float = max(0.0, _timeline.length_seconds - clip.start_seconds)
	var max_d: float = minf(max_by_source, max_by_tl)
	clip.duration_seconds = clampf(new_duration, 0.0, max_d)
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
	return Vector2(200, RULER_HEIGHT + n * _track_row_height)
