class_name CodaTimelineInputController
extends RefCounted

## Mouse, keyboard, hit testing, snap, and drag logic for CodaTimelineView.
## Mutations go out as signals; the host view applies them.

const Renderer := preload("res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_renderer.gd")
const Chrome := preload("res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_clip_chrome.gd")

const RULER_HEIGHT := Renderer.RULER_HEIGHT
const MARKER_DRAG_THRESHOLD_PX := 3.0
const EDGE_RESIZE_THRESHOLD := 6

const MIN_SECONDS_PER_PIXEL := 1.0 / 1024.0
const MAX_SECONDS_PER_PIXEL := 0.5

const FADE_HANDLE_HIT_PX := 8.0
const FADE_START_ZONE_PX := 14.0
const MIN_CLIP_WIDTH_FOR_FADE_PX := 24.0
const GHOST_TRACK_ROW_FRACTION := 1.0

enum DragKind {
	NONE = 0,
	CLIP_MOVE = 1,
	CLIP_RESIZE_LEFT = 2,
	CLIP_RESIZE_RIGHT = 3,
	CLIP_FADE_IN = 4,
	CLIP_FADE_OUT = 5,
	CLIP_FADE_IN_SHAPE = 11,
	CLIP_FADE_OUT_SHAPE = 12,
	MARKER_MOVE = 6,
	LOOP_START = 7,
	LOOP_END = 8,
	PAN = 9,
	PLAYHEAD_SEEK = 10,
}

signal clip_fade_requested(
	clip_id: String, fade_in: float, fade_out: float, fade_in_curve: float, fade_out_curve: float
)

signal clip_move_requested(clip_id: String, new_start: float, new_track_index: int)
signal clip_resize_requested(
	clip_id: String, new_start: float, new_duration: float, new_offset_seconds: float
)
signal clip_selected(clip_id: String)
signal clip_delete_requested(clip_id: String)
signal clip_duplicate_requested(clip_id: String)
signal clip_split_at_playhead_requested(clip_id: String)
signal clip_audio_assign_requested(clip_id: String, res_audio_path: String)
signal browser_asset_dropped(track_index: int, start_seconds: float, res_audio_path: String)
signal track_row_selected(track_index: int)
signal marker_changed(marker_id: String, new_time: float)
signal marker_double_clicked(marker_id: String)
signal marker_selected(marker_id: String)
signal marker_delete_requested(marker_id: String)
signal marker_rename_requested(marker_id: String)
signal marker_go_to_time_requested(marker_id: String)
signal marker_selection_cleared
signal loop_region_changed(start_seconds: float, end_seconds: float)
signal playhead_seek_requested(time_seconds: float)
signal selection_cleared
signal timeline_interaction_started
signal audition_requested

var _drag_kind: DragKind = DragKind.NONE
var _drag_clip_id: String = ""
var _drag_start_seconds: float = 0.0
var _drag_initial_clip_start: float = 0.0
var _drag_initial_clip_duration: float = 0.0
var _drag_initial_clip_offset: float = 0.0
var _drag_initial_fade_in: float = 0.0
var _drag_initial_fade_out: float = 0.0
var _drag_initial_fade_in_curve: float = 0.5
var _drag_initial_fade_out_curve: float = 0.5
var _drag_clip_rect_height: float = 64.0
var _hover_clip_edge: String = "none"
var _ghost_new_track: bool = false
var _drag_marker_id: String = ""
var _drag_pan_initial_scroll: float = 0.0
var _drag_initial_screen_pos: Vector2 = Vector2.ZERO
var _marker_press_id: String = ""
var _marker_press_pos: Vector2 = Vector2.ZERO


func is_dragging() -> bool:
	return _drag_kind != DragKind.NONE


func get_render_hints() -> Dictionary:
	return {
		"ghost_new_track": _ghost_new_track,
		"hover_clip_edge": _hover_clip_edge,
		"drag_kind": int(_drag_kind),
		"drag_clip_id": _drag_clip_id,
	}


func handle_unhandled_key(view: CodaTimelineView, event: InputEvent) -> void:
	if view.get_timeline() == null or not view.is_visible_in_tree():
		return
	if not view.has_focus():
		return
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_SPACE:
			audition_requested.emit()
			view.get_viewport().set_input_as_handled()


func handle_gui_input(view: CodaTimelineView, event: InputEvent) -> void:
	if view.get_timeline() == null:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(view, event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(view, event as InputEventMouseMotion)


func can_drop_data(view: CodaTimelineView, at_position: Vector2, data: Variant) -> bool:
	if view.get_timeline() == null or view.track_count() <= 0:
		return false
	if _timeline_drop_audio_res_path(data).is_empty():
		return false
	var hit: Dictionary = hit_test(view, at_position)
	if String(hit.get("kind", "")) == "clip":
		return true
	return _track_index_for_drop_y(view, at_position.y) >= 0


func drop_data(view: CodaTimelineView, at_position: Vector2, data: Variant) -> void:
	var path: String = _timeline_drop_audio_res_path(data)
	if path.is_empty():
		return
	var hit: Dictionary = hit_test(view, at_position)
	if String(hit.get("kind", "")) == "clip":
		var cid: String = String(hit.get("clip_id", ""))
		if not cid.is_empty():
			clip_audio_assign_requested.emit(cid, path)
		return
	var track_index: int = _track_index_for_drop_y(view, at_position.y)
	if track_index < 0:
		return
	var t_start: float = apply_snap(view, _x_to_seconds(view, at_position.x))
	browser_asset_dropped.emit(track_index, t_start, path)


func hit_test(view: CodaTimelineView, local_pos: Vector2) -> Dictionary:
	var timeline: CodaEventTimeline = view.get_timeline()
	if local_pos.y < RULER_HEIGHT:
		var marker := _hit_marker_near(view, local_pos.x)
		if marker != null:
			return {"kind": "marker", "marker_id": marker.id}
		return {"kind": "ruler"}
	if timeline == null:
		return {"kind": "empty"}
	if timeline.loop_enabled:
		var loop_x0: float = _seconds_to_x(view, timeline.loop_start_seconds)
		var loop_x1: float = _seconds_to_x(view, timeline.loop_end_seconds)
		if abs(local_pos.x - loop_x0) <= EDGE_RESIZE_THRESHOLD:
			return {"kind": "loop_start"}
		if abs(local_pos.x - loop_x1) <= EDGE_RESIZE_THRESHOLD:
			return {"kind": "loop_end"}
	var track_index: int = _track_index_at_y(view, local_pos.y)
	if track_index < 0:
		return {"kind": "empty"}
	var t: float = _x_to_seconds(view, local_pos.x)
	var track: CodaTimelineTrack = timeline.tracks[track_index]
	var clips_at_pos: Array[CodaTimelineClip] = []
	for clip in track.clips:
		if t >= clip.start_seconds and t <= clip.end_seconds():
			clips_at_pos.append(clip)
	if clips_at_pos.is_empty():
		return {"kind": "lane", "track_id": track.id, "track_index": track_index, "time": t}

	var scroll: float = view.get_scroll_seconds()
	var zoom: float = view.get_zoom()
	var lane: Rect2 = Renderer.track_lane_rect(
		track_index, view.size.x, view.get_track_row_height()
	)
	var selected_id: String = view.get_selected_clip_id()

	var target_clip: CodaTimelineClip = clips_at_pos[0]
	for clip in clips_at_pos:
		if clip.id == selected_id:
			target_clip = clip
			break

	var clip_x0: float = _seconds_to_x(view, target_clip.start_seconds)
	var clip_x1: float = _seconds_to_x(view, target_clip.end_seconds())
	var dist_l: float = abs(local_pos.x - clip_x0)
	var dist_r: float = abs(local_pos.x - clip_x1)
	var trim_outset: float = Chrome.TRIM_OUTSET
	var trim_left_hit: bool = (
		local_pos.x >= clip_x0 - trim_outset - 2.0
		and local_pos.x <= clip_x0 + EDGE_RESIZE_THRESHOLD + 2.0
	)
	var trim_right_hit: bool = (
		local_pos.x <= clip_x1 + trim_outset + 2.0
		and local_pos.x >= clip_x1 - EDGE_RESIZE_THRESHOLD - 2.0
	)
	if trim_left_hit and (not trim_right_hit or dist_l <= dist_r):
		return {
			"kind": "clip",
			"clip_id": target_clip.id,
			"track_id": track.id,
			"track_index": track_index,
			"edge": "left",
		}
	if trim_right_hit:
		return {
			"kind": "clip",
			"clip_id": target_clip.id,
			"track_id": track.id,
			"track_index": track_index,
			"edge": "right",
		}

	# Fade handles after trim strips (crossfade zone checks all overlapping clips).
	var best_fade_dist: float = 999.0
	var best_fade_edge: String = "none"
	var best_fade_clip: CodaTimelineClip = null
	for clip in clips_at_pos:
		var clip_rect: Rect2 = Chrome.clip_rect_for_times(clip, lane, scroll, zoom)
		var selected: bool = clip.id == selected_id
		var edge: String = Chrome.hit_test_fade_handle(
			local_pos, clip, clip_rect, scroll, zoom, selected
		)
		if edge == "none":
			continue
		var handle_pos: Vector2 = Chrome.handle_center_for_edge(
			edge, clip_rect, clip, scroll, zoom
		)
		var dist: float = local_pos.distance_to(handle_pos)
		if dist < best_fade_dist:
			best_fade_dist = dist
			best_fade_edge = edge
			best_fade_clip = clip
	if best_fade_clip != null:
		return {
			"kind": "clip",
			"clip_id": best_fade_clip.id,
			"track_id": track.id,
			"track_index": track_index,
			"edge": best_fade_edge,
		}

	return {
		"kind": "clip",
		"clip_id": target_clip.id,
		"track_id": track.id,
		"track_index": track_index,
		"edge": "none",
	}


func apply_snap(view: CodaTimelineView, t: float) -> float:
	var timeline: CodaEventTimeline = view.get_timeline()
	var raw: float = max(0.0, t)
	if timeline != null:
		raw = clampf(raw, 0.0, timeline.length_seconds)
	var thresh_sec: float = view.get_zoom() * 8.0
	var best: float = raw
	var best_d: float = thresh_sec + 1.0
	for cand in _snap_candidate_times(view, raw):
		var cd: float = abs(cand - raw)
		if cd < best_d:
			best_d = cd
			best = cand
	if best_d <= thresh_sec:
		raw = best
	if view.get_snap_mode() == CodaTimelineView.SnapMode.NONE:
		return raw
	var step: float = _snap_step_seconds(view)
	if step <= 0.0:
		return raw
	return round(raw / step) * step


func zoom_around(view: CodaTimelineView, pos: Vector2, factor: float) -> void:
	var time_at_cursor: float = _x_to_seconds(view, pos.x)
	var new_zoom: float = clampf(
		view.get_zoom() * factor, MIN_SECONDS_PER_PIXEL, MAX_SECONDS_PER_PIXEL
	)
	view.set_zoom(new_zoom)
	view.set_scroll_seconds(max(0.0, time_at_cursor - pos.x * new_zoom))


func _handle_mouse_button(view: CodaTimelineView, mb: InputEventMouseButton) -> void:
	if _handle_wheel(view, mb):
		view.accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE:
		if mb.pressed:
			_drag_kind = DragKind.PAN
			_drag_pan_initial_scroll = view.get_scroll_seconds()
			_drag_initial_screen_pos = mb.position
		else:
			_end_drag()
		view.accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_open_context_menu_for_hit(view, hit_test(view, mb.position))
		view.accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		view.grab_focus()
		_begin_drag(view, hit_test(view, mb.position), mb)
	else:
		_end_drag()
		view.update_minimum_size()
		view.queue_redraw()
	view.accept_event()


func _handle_wheel(view: CodaTimelineView, mb: InputEventMouseButton) -> bool:
	if not mb.pressed:
		return false
	if (
		mb.shift_pressed
		and (
			mb.button_index == MOUSE_BUTTON_WHEEL_UP
			or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		)
	):
		var dir: float = 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
		var step_sec: float = view.get_zoom() * 48.0
		view.set_scroll_seconds(max(0.0, view.get_scroll_seconds() + dir * step_sec))
		view.queue_redraw()
		return true
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_around(view, mb.position, 0.85)
		return true
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_around(view, mb.position, 1.15)
		return true
	return false


func _handle_mouse_motion(view: CodaTimelineView, mm: InputEventMouseMotion) -> void:
	if _drag_kind == DragKind.NONE and not _marker_press_id.is_empty():
		if mm.position.distance_to(_marker_press_pos) >= MARKER_DRAG_THRESHOLD_PX:
			_drag_kind = DragKind.MARKER_MOVE
			_drag_marker_id = _marker_press_id
			_marker_press_id = ""
			timeline_interaction_started.emit()
	if _drag_kind == DragKind.NONE:
		var hover: Dictionary = hit_test(view, mm.position)
		if String(hover.get("kind", "")) == "clip":
			_hover_clip_edge = String(hover.get("edge", "none"))
		else:
			_hover_clip_edge = "none"
		view.update_hover_cursor()
		view.queue_redraw()
		return
	var timeline: CodaEventTimeline = view.get_timeline()
	var t: float = _x_to_seconds(view, mm.position.x)
	match _drag_kind:
		DragKind.PAN:
			var delta_px: float = mm.position.x - _drag_initial_screen_pos.x
			view.set_scroll_seconds(
				max(0.0, _drag_pan_initial_scroll - delta_px * view.get_zoom())
			)
			view.queue_redraw()
		DragKind.PLAYHEAD_SEEK:
			var snapped: float = apply_snap(view, t)
			view.set_playhead(snapped)
			playhead_seek_requested.emit(snapped)
		DragKind.CLIP_MOVE:
			var raw_start: float = _drag_initial_clip_start + (t - _drag_start_seconds)
			var snapped_start: float = apply_snap(view, raw_start)
			var target_idx: int = _resolve_move_target_track_index(view, mm.position.y)
			_ghost_new_track = target_idx >= view.track_count()
			view.update_minimum_size()
			clip_move_requested.emit(_drag_clip_id, snapped_start, target_idx)
		DragKind.CLIP_FADE_IN:
			var info_fi: Dictionary = timeline.find_clip(_drag_clip_id)
			var clip_fi: CodaTimelineClip = info_fi.get("clip") as CodaTimelineClip
			if clip_fi != null:
				var max_fi: float = clip_fi.duration_seconds * 0.5
				var new_fi: float = clampf(
					apply_snap(view, t) - clip_fi.start_seconds, 0.0, max_fi
				)
				clip_fade_requested.emit(
					_drag_clip_id, new_fi, clip_fi.fade_out_seconds,
					clip_fi.fade_in_curve, clip_fi.fade_out_curve
				)
		DragKind.CLIP_FADE_OUT:
			var info_fo: Dictionary = timeline.find_clip(_drag_clip_id)
			var clip_fo: CodaTimelineClip = info_fo.get("clip") as CodaTimelineClip
			if clip_fo != null:
				var max_fo: float = clip_fo.duration_seconds * 0.5
				var new_fo: float = clampf(
					clip_fo.end_seconds() - apply_snap(view, t), 0.0, max_fo
				)
				clip_fade_requested.emit(
					_drag_clip_id, clip_fo.fade_in_seconds, new_fo,
					clip_fo.fade_in_curve, clip_fo.fade_out_curve
				)
		DragKind.CLIP_FADE_IN_SHAPE:
			var info_fis: Dictionary = timeline.find_clip(_drag_clip_id)
			var clip_fis: CodaTimelineClip = info_fis.get("clip") as CodaTimelineClip
			if clip_fis != null:
				var dy: float = mm.position.y - _drag_initial_screen_pos.y
				var curve_delta: float = dy / maxf(32.0, _drag_clip_rect_height) * 1.35
				var new_curve: float = clampf(
					_drag_initial_fade_in_curve + curve_delta, 0.0, 1.0
				)
				clip_fade_requested.emit(
					_drag_clip_id, clip_fis.fade_in_seconds, clip_fis.fade_out_seconds,
					new_curve, clip_fis.fade_out_curve
				)
		DragKind.CLIP_FADE_OUT_SHAPE:
			var info_fos: Dictionary = timeline.find_clip(_drag_clip_id)
			var clip_fos: CodaTimelineClip = info_fos.get("clip") as CodaTimelineClip
			if clip_fos != null:
				var dy_out: float = mm.position.y - _drag_initial_screen_pos.y
				var curve_delta_out: float = dy_out / maxf(32.0, _drag_clip_rect_height) * 1.35
				var new_curve_out: float = clampf(
					_drag_initial_fade_out_curve + curve_delta_out, 0.0, 1.0
				)
				clip_fade_requested.emit(
					_drag_clip_id, clip_fos.fade_in_seconds, clip_fos.fade_out_seconds,
					clip_fos.fade_in_curve, new_curve_out
				)
		DragKind.CLIP_RESIZE_LEFT:
			var anchor_end: float = _drag_initial_clip_start + _drag_initial_clip_duration
			var min_start: float = maxf(0.0, _drag_initial_clip_start - _drag_initial_clip_offset)
			var new_start: float = clampf(apply_snap(view, t), min_start, anchor_end - 0.01)
			var new_dur: float = anchor_end - new_start
			var new_off: float = maxf(
				0.0, _drag_initial_clip_offset + new_start - _drag_initial_clip_start
			)
			clip_resize_requested.emit(_drag_clip_id, new_start, new_dur, new_off)
		DragKind.CLIP_RESIZE_RIGHT:
			var info_r: Dictionary = timeline.find_clip(_drag_clip_id)
			var clip_r: CodaTimelineClip = info_r.get("clip") as CodaTimelineClip
			var max_play_r: float = (
				clip_r.max_source_playable_seconds() if clip_r != null else 1.0e12
			)
			var max_end: float = minf(
				timeline.length_seconds,
				_drag_initial_clip_start + max_play_r
			)
			var new_end: float = clampf(
				max(_drag_initial_clip_start + 0.01, apply_snap(view, t)),
				_drag_initial_clip_start + 0.01,
				max_end
			)
			var new_dur_r: float = new_end - _drag_initial_clip_start
			clip_resize_requested.emit(
				_drag_clip_id, _drag_initial_clip_start, new_dur_r, NAN
			)
		DragKind.MARKER_MOVE:
			var marker_t: float = apply_snap(view, t)
			_apply_marker_move(view, _drag_marker_id, marker_t)
			marker_changed.emit(_drag_marker_id, marker_t)
		DragKind.LOOP_START:
			var ls: float = clampf(apply_snap(view, t), 0.0, timeline.loop_end_seconds - 0.01)
			timeline.loop_start_seconds = ls
			loop_region_changed.emit(ls, timeline.loop_end_seconds)
			view.queue_redraw()
		DragKind.LOOP_END:
			var le: float = max(timeline.loop_start_seconds + 0.01, apply_snap(view, t))
			timeline.loop_end_seconds = le
			loop_region_changed.emit(timeline.loop_start_seconds, le)
			view.queue_redraw()


func _begin_drag(view: CodaTimelineView, hit: Dictionary, mb: InputEventMouseButton) -> void:
	var timeline: CodaEventTimeline = view.get_timeline()
	var k: String = String(hit.get("kind", ""))
	_drag_initial_screen_pos = mb.position
	_drag_start_seconds = _x_to_seconds(view, mb.position.x)
	if k == "ruler":
		view.clear_marker_selection()
		_drag_kind = DragKind.PLAYHEAD_SEEK
		var snapped: float = apply_snap(view, _drag_start_seconds)
		view.set_playhead(snapped)
		playhead_seek_requested.emit(snapped)
		return
	if k == "marker":
		var marker_id: String = String(hit.get("marker_id", ""))
		if mb.double_click:
			view.set_selected_marker(marker_id)
			marker_double_clicked.emit(marker_id)
			_drag_kind = DragKind.NONE
			return
		var was_selected: bool = view.get_selected_marker_id() == marker_id
		view.set_selected_marker(marker_id)
		if was_selected:
			_drag_kind = DragKind.MARKER_MOVE
			_drag_marker_id = marker_id
			timeline_interaction_started.emit()
		else:
			_marker_press_id = marker_id
			_marker_press_pos = mb.position
			_drag_kind = DragKind.NONE
		return
	if k == "loop_start" or k == "loop_end":
		_drag_kind = DragKind.LOOP_START if k == "loop_start" else DragKind.LOOP_END
		timeline_interaction_started.emit()
		return
	if k == "clip":
		var clip_id: String = String(hit.get("clip_id", ""))
		_drag_clip_id = clip_id
		var info: Dictionary = timeline.find_clip(clip_id)
		if info.is_empty():
			_drag_kind = DragKind.NONE
			return
		var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
		_drag_initial_clip_start = clip.start_seconds
		_drag_initial_clip_duration = clip.duration_seconds
		_drag_initial_clip_offset = clip.offset_seconds
		_drag_initial_fade_in = clip.fade_in_seconds
		_drag_initial_fade_out = clip.fade_out_seconds
		_drag_initial_fade_in_curve = clip.fade_in_curve
		_drag_initial_fade_out_curve = clip.fade_out_curve
		var track_idx: int = int(hit.get("track_index", 0))
		var lane: Rect2 = Renderer.track_lane_rect(
			track_idx, view.size.x, view.get_track_row_height()
		)
		var clip_rect: Rect2 = Chrome.clip_rect_for_times(
			clip, lane, view.get_scroll_seconds(), view.get_zoom()
		)
		_drag_clip_rect_height = clip_rect.size.y
		view.set_selected_clip(clip_id)
		clip_selected.emit(clip_id)
		match String(hit.get("edge", "none")):
			"left":
				_drag_kind = DragKind.CLIP_RESIZE_LEFT
			"right":
				_drag_kind = DragKind.CLIP_RESIZE_RIGHT
			"fade_in":
				_drag_kind = DragKind.CLIP_FADE_IN
			"fade_in_shape":
				_drag_kind = DragKind.CLIP_FADE_IN_SHAPE
			"fade_out":
				_drag_kind = DragKind.CLIP_FADE_OUT
			"fade_out_shape":
				_drag_kind = DragKind.CLIP_FADE_OUT_SHAPE
			_:
				_drag_kind = DragKind.CLIP_MOVE
		timeline_interaction_started.emit()
		return
	if k == "lane":
		var lane_idx: int = int(hit.get("track_index", -1))
		if lane_idx >= 0:
			track_row_selected.emit(lane_idx)
		view.set_selected_clip("")
		view.clear_marker_selection()
		selection_cleared.emit()
		_drag_kind = DragKind.NONE


func _end_drag() -> void:
	_drag_kind = DragKind.NONE
	_drag_clip_id = ""
	_drag_marker_id = ""
	_marker_press_id = ""
	_ghost_new_track = false
	_hover_clip_edge = "none"


func _resolve_move_target_track_index(view: CodaTimelineView, y: float) -> int:
	var n: int = view.track_count()
	if n <= 0:
		return 0
	if y < RULER_HEIGHT:
		return 0
	var row: int = _track_row_from_y(view, y)
	if row < n:
		return row
	var ghost_top: float = RULER_HEIGHT + float(n) * float(view.get_track_row_height())
	var ghost_bottom: float = ghost_top + float(view.get_track_row_height()) * GHOST_TRACK_ROW_FRACTION
	if y >= ghost_top and y < ghost_bottom:
		return n
	return n - 1


func _open_context_menu_for_hit(view: CodaTimelineView, hit: Dictionary) -> void:
	var menu_pos := Vector2i(
		int(view.get_global_mouse_position().x),
		int(view.get_global_mouse_position().y)
	)
	match String(hit.get("kind", "")):
		"clip":
			view.open_clip_context_menu(String(hit.get("clip_id", "")), menu_pos)
		"marker":
			view.open_marker_context_menu(String(hit.get("marker_id", "")), menu_pos)


func _track_index_at_y(view: CodaTimelineView, y: float) -> int:
	if y < RULER_HEIGHT:
		return -1
	var n: int = view.track_count()
	if n == 0:
		return -1
	var idx: int = _track_row_from_y(view, y)
	if idx < 0 or idx >= n:
		return -1
	return idx


func _track_index_for_drop_y(view: CodaTimelineView, y: float) -> int:
	var n: int = view.track_count()
	if n <= 0:
		return -1
	if y < RULER_HEIGHT:
		return 0
	return clampi(_track_row_from_y(view, y), 0, n - 1)


func _track_row_from_y(view: CodaTimelineView, y: float) -> int:
	return int((y - RULER_HEIGHT) / view.get_track_row_height())


func _hit_marker_near(view: CodaTimelineView, x: float) -> CodaTimelineMarker:
	var timeline: CodaEventTimeline = view.get_timeline()
	if timeline == null:
		return null
	var best_marker: CodaTimelineMarker = null
	var best_dist: float = 6.0
	for m in timeline.markers:
		var mx: float = _seconds_to_x(view, m.time_seconds)
		var d: float = abs(mx - x)
		if d < best_dist:
			best_dist = d
			best_marker = m
	return best_marker


func _snap_candidate_times(view: CodaTimelineView, for_time: float) -> Array[float]:
	var out: Array[float] = []
	var timeline: CodaEventTimeline = view.get_timeline()
	if timeline == null:
		return out
	out.append(0.0)
	out.append(timeline.length_seconds)
	if timeline.loop_enabled:
		out.append(timeline.loop_start_seconds)
		out.append(timeline.loop_end_seconds)
	for m in timeline.markers:
		out.append(m.time_seconds)
	for tr in timeline.tracks:
		for cl in tr.clips:
			out.append(cl.start_seconds)
			out.append(cl.end_seconds())
	if view.get_snap_mode() != CodaTimelineView.SnapMode.NONE:
		var step: float = _snap_step_seconds(view)
		if step > 0.0:
			out.append(round(for_time / step) * step)
	return out


func _snap_step_seconds(view: CodaTimelineView) -> float:
	match view.get_snap_mode():
		CodaTimelineView.SnapMode.TENTHS:
			return 0.1
		CodaTimelineView.SnapMode.BARS_BEATS:
			var timeline: CodaEventTimeline = view.get_timeline()
			if timeline != null and timeline.tempo_bpm > 0.0:
				return 60.0 / timeline.tempo_bpm
			return 0.1
		_:
			return 0.0


func _seconds_to_x(view: CodaTimelineView, t: float) -> float:
	return Renderer.seconds_to_x(t, view.get_scroll_seconds(), view.get_zoom())


func _x_to_seconds(view: CodaTimelineView, x: float) -> float:
	return Renderer.x_to_seconds(x, view.get_scroll_seconds(), view.get_zoom())


func _apply_marker_move(view: CodaTimelineView, marker_id: String, new_time: float) -> void:
	var timeline: CodaEventTimeline = view.get_timeline()
	if timeline == null:
		return
	var m: CodaTimelineMarker = timeline.find_marker(marker_id)
	if m == null:
		return
	m.time_seconds = clampf(new_time, 0.0, timeline.length_seconds)
	view.queue_redraw()


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
