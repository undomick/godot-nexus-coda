class_name CodaTimelineRenderer
extends RefCounted

## Stateless draw helpers for [CodaTimelineView]. All methods take a [CanvasItem] target
## and a state dictionary assembled by the view each frame.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const Chrome := preload("res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_clip_chrome.gd")
const CodaTimelineWaveformCacheScript := preload(
	"res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_waveform_cache.gd"
)

const RULER_HEIGHT := 22
const MARKER_FLAG_HALF_W := 5.0
const MARKER_FLAG_H := 10.0
const CLIP_INNER_PADDING := 2
const MIN_CLIP_WIDTH_PX := 4


static func draw(canvas: CanvasItem, state: Dictionary) -> void:
	var area: Rect2 = Rect2(Vector2.ZERO, state.get("size", Vector2.ZERO))
	canvas.draw_rect(area, Tokens.SURFACE_BG, true)

	var timeline: CodaEventTimeline = state.get("timeline", null)
	if timeline == null:
		draw_placeholder(canvas, state)
		return

	draw_track_lanes(canvas, state)
	draw_ghost_track_lane(canvas, state)
	draw_loop_region(canvas, state)
	draw_clips(canvas, state)
	draw_timeline_end(canvas, state)
	draw_ruler(canvas, state)
	draw_markers(canvas, state)
	draw_playhead(canvas, state)
	if state.get("has_focus", false):
		canvas.draw_rect(area, Tokens.ACCENT_DIM, false, 1.0)


static func draw_placeholder(canvas: CanvasItem, state: Dictionary) -> void:
	var msg: String = "No timeline"
	var font: Font = state.get("theme_font", null)
	if font == null:
		return
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var size_px: int = Tokens.FONT_BODY_SIZE
	var text_size: Vector2 = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, size_px)
	var pos: Vector2 = (widget_size - text_size) * 0.5
	canvas.draw_string(
		font, pos, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Tokens.TEXT_MUTED
	)


static func draw_track_lanes(canvas: CanvasItem, state: Dictionary) -> void:
	var timeline: CodaEventTimeline = state.get("timeline", null)
	if timeline == null:
		return
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var track_row_height: int = int(state.get("track_row_height", 92))
	var highlight_track_index: int = int(state.get("highlight_track_index", 0))
	var n: int = timeline.tracks.size()
	for i in n:
		var rect: Rect2 = track_lane_rect(i, widget_size.x, track_row_height)
		var bg: Color = Tokens.SURFACE_RAISED if i % 2 == 0 else Tokens.SURFACE_SUNKEN
		canvas.draw_rect(rect, bg, true)
		var tr: CodaTimelineTrack = timeline.tracks[i]
		var ac: Color = Tokens.ACCENT if tr.color.a <= 0.001 else tr.color
		canvas.draw_rect(rect, Color(ac.r, ac.g, ac.b, 0.10), true)
		if i == highlight_track_index and n > 0:
			canvas.draw_rect(
				rect, Color(Tokens.ACCENT.r, Tokens.ACCENT.g, Tokens.ACCENT.b, 0.14), true
			)
			canvas.draw_rect(rect, Tokens.ACCENT, false, 2.0)
	var lane_bottom: float = float(RULER_HEIGHT + n * track_row_height)
	canvas.draw_line(
		Vector2(0, lane_bottom), Vector2(widget_size.x, lane_bottom), Tokens.SURFACE_BORDER, 1.0
	)


static func draw_timeline_end(canvas: CanvasItem, state: Dictionary) -> void:
	var timeline: CodaEventTimeline = state.get("timeline", null)
	if timeline == null or timeline.length_seconds <= 0.001:
		return
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var scroll: float = state.get("scroll_seconds", 0.0)
	var spp: float = state.get("seconds_per_pixel", 1.0 / 80.0)
	var x: float = seconds_to_x(timeline.length_seconds, scroll, spp)
	if x < -2.0 or x > widget_size.x + 2.0:
		return
	var col := Color(Tokens.WARN.r, Tokens.WARN.g, Tokens.WARN.b, 0.85)
	canvas.draw_line(Vector2(x, float(RULER_HEIGHT)), Vector2(x, widget_size.y), col, 2.0)
	var font: Font = state.get("theme_font", null)
	if font != null and x >= 0.0 and x <= widget_size.x - 40.0:
		var label: String = "%.1fs" % timeline.length_seconds
		canvas.draw_string(
			font,
			Vector2(x + 4.0, float(RULER_HEIGHT) - 4.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			Tokens.FONT_LABEL_SIZE,
			Tokens.WARN
		)


static func draw_clips(canvas: CanvasItem, state: Dictionary) -> void:
	var timeline: CodaEventTimeline = state.get("timeline", null)
	if timeline == null:
		return
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var track_row_height: int = int(state.get("track_row_height", 92))
	var scroll: float = state.get("scroll_seconds", 0.0)
	var spp: float = state.get("seconds_per_pixel", 1.0 / 80.0)
	for i in timeline.tracks.size():
		var track: CodaTimelineTrack = timeline.tracks[i]
		var lane: Rect2 = track_lane_rect(i, widget_size.x, track_row_height)
		var clip_rects: Array = []
		for clip in track.clips:
			var rect: Rect2 = Chrome.clip_rect_for_times(clip, lane, scroll, spp)
			if rect.position.x + rect.size.x < lane.position.x:
				continue
			if rect.position.x > lane.position.x + lane.size.x:
				continue
			clip_rects.append({"clip": clip, "clip_id": clip.id, "rect": rect})
			draw_one_clip(canvas, state, clip, rect)
		Chrome.draw_track_crossfades(canvas, state, clip_rects)
		for item in clip_rects:
			var clip: CodaTimelineClip = item.get("clip") as CodaTimelineClip
			var rect: Rect2 = item.get("rect", Rect2())
			if clip == null:
				continue
			var selected: bool = clip.id == String(state.get("selected_clip_id", ""))
			Chrome.draw_clip_fades(canvas, state, clip, rect, selected)
			Chrome.draw_trim_handles(
				canvas,
				rect,
				selected,
				String(state.get("hover_clip_edge", "")),
				String(state.get("drag_clip_id", "")),
				clip.id,
				int(state.get("drag_kind", 0))
			)


static func draw_one_clip(
	canvas: CanvasItem, state: Dictionary, clip: CodaTimelineClip, rect: Rect2
) -> void:
	var selected_clip_id: String = String(state.get("selected_clip_id", ""))
	var selected: bool = clip.id == selected_clip_id
	Chrome.draw_clip_body(canvas, clip, rect, selected)
	draw_clip_waveform(canvas, clip, rect)
	var font: Font = state.get("theme_font", null)
	if font != null and rect.size.x > 24:
		var label: String = clip.audio_path.get_file() if not clip.audio_path.is_empty() else "Clip"
		var size_px: int = Tokens.FONT_LABEL_SIZE
		var pos: Vector2 = Vector2(rect.position.x + 4, rect.position.y + size_px + 2)
		canvas.draw_string(
			font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 8, size_px,
			Tokens.TEXT_PRIMARY
		)


static func draw_ghost_track_lane(canvas: CanvasItem, state: Dictionary) -> void:
	if not bool(state.get("ghost_new_track", false)):
		return
	var timeline: CodaEventTimeline = state.get("timeline", null)
	if timeline == null:
		return
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var track_row_height: int = int(state.get("track_row_height", 92))
	var idx: int = timeline.tracks.size()
	var rect: Rect2 = track_lane_rect(idx, widget_size.x, track_row_height)
	canvas.draw_rect(rect, Color(Tokens.ACCENT.r, Tokens.ACCENT.g, Tokens.ACCENT.b, 0.08), true)
	canvas.draw_rect(rect, Tokens.ACCENT, false, 1.0)


static func draw_loop_region(canvas: CanvasItem, state: Dictionary) -> void:
	var timeline: CodaEventTimeline = state.get("timeline", null)
	if timeline == null or not timeline.loop_enabled:
		return
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var scroll_seconds: float = state.get("scroll_seconds", 0.0)
	var seconds_per_pixel: float = state.get("seconds_per_pixel", 1.0 / 80.0)
	var x0: float = seconds_to_x(timeline.loop_start_seconds, scroll_seconds, seconds_per_pixel)
	var x1: float = seconds_to_x(timeline.loop_end_seconds, scroll_seconds, seconds_per_pixel)
	if x1 <= x0:
		return
	var rect_full: Rect2 = Rect2(
		Vector2(x0, RULER_HEIGHT), Vector2(x1 - x0, widget_size.y - RULER_HEIGHT)
	)
	canvas.draw_rect(
		rect_full, Color(Tokens.SUCCESS.r, Tokens.SUCCESS.g, Tokens.SUCCESS.b, 0.10), true
	)
	canvas.draw_line(Vector2(x0, RULER_HEIGHT), Vector2(x0, widget_size.y), Tokens.SUCCESS, 1.0)
	canvas.draw_line(Vector2(x1, RULER_HEIGHT), Vector2(x1, widget_size.y), Tokens.SUCCESS, 1.0)


static func draw_ruler(canvas: CanvasItem, state: Dictionary) -> void:
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var scroll_seconds: float = state.get("scroll_seconds", 0.0)
	var seconds_per_pixel: float = state.get("seconds_per_pixel", 1.0 / 80.0)
	var timeline: CodaEventTimeline = state.get("timeline", null)
	var snap_mode: int = int(state.get("snap_mode", 0))

	var ruler_rect: Rect2 = Rect2(0, 0, widget_size.x, float(RULER_HEIGHT))
	canvas.draw_rect(ruler_rect, Tokens.SURFACE_RAISED, true)
	canvas.draw_line(
		Vector2(0, RULER_HEIGHT), Vector2(widget_size.x, RULER_HEIGHT), Tokens.SURFACE_BORDER, 1.0
	)
	var font: Font = state.get("theme_font", null)
	if font == null:
		return
	var step: float = ruler_step_seconds(seconds_per_pixel)
	if step <= 0.0:
		return
	var first_tick: float = floorf(scroll_seconds / step) * step
	var t: float = first_tick
	var lim: float = scroll_seconds + widget_size.x * seconds_per_pixel
	var size_px: int = Tokens.FONT_LABEL_SIZE
	while t <= lim + step:
		if t >= 0.0:
			var x: float = seconds_to_x(t, scroll_seconds, seconds_per_pixel)
			canvas.draw_line(
				Vector2(x, RULER_HEIGHT - 6), Vector2(x, RULER_HEIGHT), Tokens.TEXT_MUTED, 1.0
			)
			var label: String = format_ruler_time(t, step, timeline, snap_mode)
			canvas.draw_string(
				font, Vector2(x + 3, size_px + 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px,
				Tokens.TEXT_SECONDARY
			)
		t += step


static func draw_markers(canvas: CanvasItem, state: Dictionary) -> void:
	var timeline: CodaEventTimeline = state.get("timeline", null)
	if timeline == null:
		return
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var scroll_seconds: float = state.get("scroll_seconds", 0.0)
	var seconds_per_pixel: float = state.get("seconds_per_pixel", 1.0 / 80.0)
	var selected_marker_id: String = String(state.get("selected_marker_id", ""))
	var font: Font = state.get("theme_font", null)
	for m in timeline.markers:
		var x: float = seconds_to_x(m.time_seconds, scroll_seconds, seconds_per_pixel)
		if x < 0 or x > widget_size.x:
			continue
		var col: Color = color_for_marker(m)
		var selected: bool = m.id == selected_marker_id
		draw_marker_flag(canvas, x, col, selected, m.marker_name, font, widget_size.y)


static func draw_marker_flag(
	canvas: CanvasItem,
	x: float,
	col: Color,
	selected: bool,
	label: String,
	font: Font,
	widget_height: float
) -> void:
	var tip_y: float = float(RULER_HEIGHT)
	var base_y: float = tip_y - MARKER_FLAG_H
	var points := PackedVector2Array([
		Vector2(x, tip_y),
		Vector2(x - MARKER_FLAG_HALF_W, base_y),
		Vector2(x + MARKER_FLAG_HALF_W, base_y),
	])
	canvas.draw_colored_polygon(points, col)
	if selected:
		for i in 3:
			canvas.draw_line(points[i], points[(i + 1) % 3], Tokens.ACCENT, 2.0)
	if font != null and not label.is_empty():
		canvas.draw_string(
			font,
			Vector2(x + MARKER_FLAG_HALF_W + 2, RULER_HEIGHT - 5),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			Tokens.FONT_LABEL_SIZE,
			col if not selected else Tokens.TEXT_PRIMARY
		)
	var line_w: float = 2.0 if selected else 1.0
	var line_col: Color = Tokens.ACCENT if selected else col
	canvas.draw_line(Vector2(x, RULER_HEIGHT), Vector2(x, widget_height), line_col, line_w)


static func draw_playhead(canvas: CanvasItem, state: Dictionary) -> void:
	var widget_size: Vector2 = state.get("size", Vector2.ZERO)
	var scroll_seconds: float = state.get("scroll_seconds", 0.0)
	var seconds_per_pixel: float = state.get("seconds_per_pixel", 1.0 / 80.0)
	var playhead_seconds: float = state.get("playhead_seconds", 0.0)
	var x: float = seconds_to_x(playhead_seconds, scroll_seconds, seconds_per_pixel)
	if x < 0 or x > widget_size.x:
		return
	var tip_y: float = float(RULER_HEIGHT)
	var base_y: float = 2.0
	var half_w: float = 4.0
	var tri := PackedVector2Array([
		Vector2(x, tip_y),
		Vector2(x - half_w, base_y),
		Vector2(x + half_w, base_y),
	])
	canvas.draw_colored_polygon(tri, Tokens.ACCENT)
	canvas.draw_line(Vector2(x, RULER_HEIGHT), Vector2(x, widget_size.y), Tokens.ACCENT, 2.0)


static func draw_clip_waveform(canvas: CanvasItem, clip: CodaTimelineClip, rect: Rect2) -> void:
	if clip.audio_path.is_empty():
		return
	var h_wave: float = maxf(4.0, rect.size.y * 0.36)
	var top: float = rect.position.y + rect.size.y - h_wave - 2.0
	var wave_rect := Rect2(Vector2(rect.position.x + 1.0, top), Vector2(rect.size.x - 2.0, h_wave))
	if wave_rect.size.x < 10.0:
		return
	var bucket_count: int = clampi(int(wave_rect.size.x), 64, 2048)
	var peaks: PackedFloat32Array = CodaTimelineWaveformCacheScript.peaks_for_clip_segment(
		clip.audio_path, clip.offset_seconds, clip.duration_seconds, bucket_count
	)
	if peaks.is_empty():
		return
	var n: int = peaks.size()
	if n <= 0:
		return
	var mid_y: float = wave_rect.position.y + wave_rect.size.y * 0.5
	var col := Color(Tokens.TEXT_PRIMARY.r, Tokens.TEXT_PRIMARY.g, Tokens.TEXT_PRIMARY.b, 0.48)
	var x_step: float = wave_rect.size.x / float(max(1, n - 1))
	for i in n:
		var pk: float = peaks[i]
		var bar_h: float = maxf(0.5, wave_rect.size.y * pk * 0.5)
		var x: float = wave_rect.position.x + float(i) * x_step
		canvas.draw_line(
			Vector2(x, mid_y - bar_h), Vector2(x, mid_y + bar_h), col, 1.0
		)


static func track_lane_rect(track_index: int, width: float, track_row_height: int) -> Rect2:
	return Rect2(
		Vector2(0, RULER_HEIGHT + track_index * track_row_height),
		Vector2(width, track_row_height)
	)


static func seconds_to_x(t: float, scroll_seconds: float, seconds_per_pixel: float) -> float:
	if seconds_per_pixel <= 0.0:
		return 0.0
	return (t - scroll_seconds) / seconds_per_pixel


static func x_to_seconds(x: float, scroll_seconds: float, seconds_per_pixel: float) -> float:
	return x * seconds_per_pixel + scroll_seconds


static func ruler_step_seconds(seconds_per_pixel: float) -> float:
	var ideal_seconds_per_step: float = seconds_per_pixel * 80.0
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


static func format_ruler_time(
	seconds: float, step: float, timeline: CodaEventTimeline, snap_mode: int
) -> String:
	const SNAP_BARS_BEATS := 2
	if timeline != null and timeline.tempo_bpm > 0.0 and snap_mode == SNAP_BARS_BEATS:
		var beat_seconds: float = 60.0 / timeline.tempo_bpm
		var beats: float = seconds / beat_seconds
		var num: int = max(1, timeline.time_signature.x)
		var bar: int = int(floor(beats / float(num))) + 1
		var beat: int = int(floor(beats)) % num + 1
		return "%d.%d" % [bar, beat]
	var precision: int = 2 if step < 0.5 else (1 if step < 5.0 else 0)
	if precision == 0:
		return "%ds" % int(round(seconds))
	if precision == 1:
		return "%.1fs" % seconds
	return "%.2fs" % seconds


static func color_for_marker(m: CodaTimelineMarker) -> Color:
	match m.kind:
		CodaTimelineMarker.Kind.TRANSITION:
			return Tokens.WARN
		CodaTimelineMarker.Kind.CUE:
			return Tokens.SUCCESS
	return Tokens.TEXT_SECONDARY
