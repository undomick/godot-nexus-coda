class_name CodaTimelineClipChrome
extends RefCounted

## Clip body, trim handles, Audacity-style fade curves, diamonds, and crossfade overlays.
## Fade-in: bottom-left (silent) -> top at fade end (full). Fade-out: top at fade start -> bottom-right.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const Renderer := preload("res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_renderer.gd")

const DIAMOND_HIT_RADIUS := 14.0
const APEX_HIT_RADIUS := 9.0
const APEX_IDLE_HIT_RADIUS := 8.0
const DIAMOND_HALF := 6.0
const APEX_HALF := 4.0
const TRIM_HANDLE_WIDTH := 7.0
const TRIM_OUTSET := 5.0
const FADE_APEX_IDLE_INSET := 12.0
const CORNER_RADIUS := 5.0
const FADE_CURVE_SEGMENTS := 24
const SHAPE_BULGE_FRAC := 0.44


static func clip_rect_for_times(
	clip: CodaTimelineClip,
	lane: Rect2,
	scroll: float,
	spp: float,
	inner_padding: float = Renderer.CLIP_INNER_PADDING
) -> Rect2:
	var x_start: float = Renderer.seconds_to_x(clip.start_seconds, scroll, spp)
	var x_end: float = Renderer.seconds_to_x(clip.end_seconds(), scroll, spp)
	return Rect2(
		Vector2(x_start, lane.position.y + inner_padding),
		Vector2(max(Renderer.MIN_CLIP_WIDTH_PX, x_end - x_start), lane.size.y - 2.0 * inner_padding)
	)


static func find_overlapping_pairs(clips: Array) -> Array:
	var sorted: Array = clips.duplicate()
	sorted.sort_custom(
		func(a: CodaTimelineClip, b: CodaTimelineClip) -> bool:
			return a.start_seconds < b.start_seconds
	)
	var pairs: Array = []
	for i in sorted.size():
		var a: CodaTimelineClip = sorted[i] as CodaTimelineClip
		if a == null:
			continue
		for j in range(i + 1, sorted.size()):
			var b: CodaTimelineClip = sorted[j] as CodaTimelineClip
			if b == null:
				continue
			if b.start_seconds >= a.end_seconds():
				break
			var ov_start: float = maxf(a.start_seconds, b.start_seconds)
			var ov_end: float = minf(a.end_seconds(), b.end_seconds())
			if ov_end > ov_start + 0.001:
				pairs.append({"a": a, "b": b, "start": ov_start, "end": ov_end})
	return pairs


static func fade_in_x_end(rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float) -> float:
	if clip.fade_in_seconds <= 0.0:
		return rect.position.x
	var x_end: float = Renderer.seconds_to_x(
		clip.start_seconds + clip.fade_in_seconds, scroll, spp
	)
	return clampf(x_end, rect.position.x, rect.position.x + rect.size.x)


static func fade_out_x_start(rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float) -> float:
	if clip.fade_out_seconds <= 0.0:
		return rect.position.x + rect.size.x
	var x_start: float = Renderer.seconds_to_x(
		clip.end_seconds() - clip.fade_out_seconds, scroll, spp
	)
	return clampf(x_start, rect.position.x, rect.position.x + rect.size.x)


static func fade_in_bezier(rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float) -> PackedVector2Array:
	var x_end: float = fade_in_x_end(rect, clip, scroll, spp)
	var bottom: float = rect.position.y + rect.size.y
	var top: float = rect.position.y
	var p0 := Vector2(rect.position.x, bottom)
	var p2 := Vector2(x_end, top)
	var p1 := _shape_control_point(p0, p2, clip.fade_in_curve, rect)
	return PackedVector2Array([p0, p1, p2])


static func fade_out_bezier(rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float) -> PackedVector2Array:
	var x_start: float = fade_out_x_start(rect, clip, scroll, spp)
	var bottom: float = rect.position.y + rect.size.y
	var top: float = rect.position.y
	var p0 := Vector2(x_start, top)
	var p2 := Vector2(rect.position.x + rect.size.x, bottom)
	var p1 := _shape_control_point(p0, p2, clip.fade_out_curve, rect)
	return PackedVector2Array([p0, p1, p2])


## Control point stays on the vertical midline; only Y shifts with curve (no degenerate loops).
static func _shape_control_point(p0: Vector2, p2: Vector2, curve: float, rect: Rect2) -> Vector2:
	var mid_x: float = lerpf(p0.x, p2.x, 0.5)
	var mid_y: float = lerpf(p0.y, p2.y, 0.5)
	var bulge: float = rect.size.y * SHAPE_BULGE_FRAC
	var offset_y: float = (0.5 - clampf(curve, 0.0, 1.0)) * bulge
	return Vector2(
		mid_x,
		clampf(mid_y + offset_y, rect.position.y, rect.position.y + rect.size.y)
	)


static func quad_bezier_point(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var a: Vector2 = p0.lerp(p1, t)
	var b: Vector2 = p1.lerp(p2, t)
	return a.lerp(b, t)


static func quad_bezier_midpoint(p0: Vector2, p1: Vector2, p2: Vector2) -> Vector2:
	return quad_bezier_point(p0, p1, p2, 0.5)


static func sample_quad_bezier(p0: Vector2, p1: Vector2, p2: Vector2, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		pts.append(quad_bezier_point(p0, p1, p2, t))
	return pts


static func fade_in_apex(rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float) -> Vector2:
	if clip.fade_in_seconds <= 0.0:
		return Vector2(rect.position.x + FADE_APEX_IDLE_INSET, rect.position.y)
	var bez := fade_in_bezier(rect, clip, scroll, spp)
	return bez[2]


static func fade_out_apex(rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float) -> Vector2:
	if clip.fade_out_seconds <= 0.0:
		return Vector2(rect.position.x + rect.size.x - FADE_APEX_IDLE_INSET, rect.position.y)
	var bez := fade_out_bezier(rect, clip, scroll, spp)
	return bez[0]


static func fade_in_diamond(rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float) -> Vector2:
	var bez := fade_in_bezier(rect, clip, scroll, spp)
	return quad_bezier_midpoint(bez[0], bez[1], bez[2])


static func fade_out_diamond(rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float) -> Vector2:
	var bez := fade_out_bezier(rect, clip, scroll, spp)
	return quad_bezier_midpoint(bez[0], bez[1], bez[2])


static func handle_center_for_edge(
	edge: String, rect: Rect2, clip: CodaTimelineClip, scroll: float, spp: float
) -> Vector2:
	match edge:
		"fade_in":
			return fade_in_apex(rect, clip, scroll, spp)
		"fade_in_shape":
			return fade_in_diamond(rect, clip, scroll, spp)
		"fade_out":
			return fade_out_apex(rect, clip, scroll, spp)
		"fade_out_shape":
			return fade_out_diamond(rect, clip, scroll, spp)
	return Vector2.ZERO


static func hit_test_fade_handle(
	local_pos: Vector2,
	clip: CodaTimelineClip,
	rect: Rect2,
	scroll: float,
	spp: float,
	selected: bool
) -> String:
	if rect.size.x < 24.0:
		return "none"
	if not selected and clip.fade_in_seconds <= 0.0 and clip.fade_out_seconds <= 0.0:
		return "none"
	var best_edge: String = "none"
	var best_dist: float = 999.0
	if clip.fade_in_seconds > 0.0:
		var apex_in: Vector2 = fade_in_apex(rect, clip, scroll, spp)
		var d_apex: float = local_pos.distance_to(apex_in)
		if d_apex <= APEX_HIT_RADIUS and d_apex < best_dist:
			best_dist = d_apex
			best_edge = "fade_in"
		var diamond_in: Vector2 = fade_in_diamond(rect, clip, scroll, spp)
		var d_shape: float = local_pos.distance_to(diamond_in)
		if d_shape <= DIAMOND_HIT_RADIUS and d_shape < best_dist:
			best_dist = d_shape
			best_edge = "fade_in_shape"
	elif selected and _point_in_fade_in_zone(local_pos, rect):
		var idle_in: Vector2 = fade_in_apex(rect, clip, scroll, spp)
		var d_idle: float = local_pos.distance_to(idle_in)
		if d_idle <= APEX_IDLE_HIT_RADIUS and d_idle < best_dist:
			best_dist = d_idle
			best_edge = "fade_in"
	if clip.fade_out_seconds > 0.0:
		var apex_out: Vector2 = fade_out_apex(rect, clip, scroll, spp)
		var d_apex_out: float = local_pos.distance_to(apex_out)
		if d_apex_out <= APEX_HIT_RADIUS and d_apex_out < best_dist:
			best_dist = d_apex_out
			best_edge = "fade_out"
		var diamond_out: Vector2 = fade_out_diamond(rect, clip, scroll, spp)
		var d_shape_out: float = local_pos.distance_to(diamond_out)
		if d_shape_out <= DIAMOND_HIT_RADIUS and d_shape_out < best_dist:
			best_dist = d_shape_out
			best_edge = "fade_out_shape"
	elif selected and _point_in_fade_out_zone(local_pos, rect):
		var idle_out: Vector2 = fade_out_apex(rect, clip, scroll, spp)
		var d_idle_out: float = local_pos.distance_to(idle_out)
		if d_idle_out <= APEX_IDLE_HIT_RADIUS and d_idle_out < best_dist:
			best_dist = d_idle_out
			best_edge = "fade_out"
	return best_edge


static func _point_in_fade_in_zone(local_pos: Vector2, rect: Rect2) -> bool:
	return (
		local_pos.x >= rect.position.x + FADE_APEX_IDLE_INSET
		and local_pos.x <= rect.position.x + rect.size.x * 0.5
		and local_pos.y >= rect.position.y
		and local_pos.y <= rect.position.y + rect.size.y * 0.45
	)


static func _point_in_fade_out_zone(local_pos: Vector2, rect: Rect2) -> bool:
	return (
		local_pos.x <= rect.position.x + rect.size.x - FADE_APEX_IDLE_INSET
		and local_pos.x >= rect.position.x + rect.size.x * 0.5
		and local_pos.y >= rect.position.y
		and local_pos.y <= rect.position.y + rect.size.y * 0.45
	)


static func draw_clip_body(
	canvas: CanvasItem, clip: CodaTimelineClip, rect: Rect2, selected: bool
) -> void:
	var fill: Color = Tokens.CLIP_FILL_SELECTED if selected else Tokens.CLIP_FILL
	var border: Color = Tokens.CLIP_BORDER_SELECTED if selected else Tokens.CLIP_BORDER
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(CORNER_RADIUS)
	canvas.draw_style_box(sb, rect)


static func draw_trim_handles(
	canvas: CanvasItem,
	rect: Rect2,
	selected: bool,
	hover_edge: String,
	drag_clip_id: String,
	clip_id: String,
	drag_kind: int
) -> void:
	if not selected or rect.size.x < 20.0:
		return
	var hot_l: bool = (
		hover_edge == "left"
		or (drag_clip_id == clip_id and drag_kind == 2)
	)
	var hot_r: bool = (
		hover_edge == "right"
		or (drag_clip_id == clip_id and drag_kind == 3)
	)
	var col_l: Color = Tokens.TRIM_HANDLE_HOT if hot_l else Tokens.TRIM_HANDLE
	var col_r: Color = Tokens.TRIM_HANDLE_HOT if hot_r else Tokens.TRIM_HANDLE
	var h: float = rect.size.y * 0.55
	var top: float = rect.position.y + (rect.size.y - h) * 0.5
	canvas.draw_rect(
		Rect2(Vector2(rect.position.x - TRIM_OUTSET, top), Vector2(TRIM_HANDLE_WIDTH, h)),
		col_l,
		true
	)
	canvas.draw_rect(
		Rect2(
			Vector2(rect.position.x + rect.size.x + TRIM_OUTSET - TRIM_HANDLE_WIDTH, top),
			Vector2(TRIM_HANDLE_WIDTH, h)
		),
		col_r,
		true
	)


static func draw_fade_curve(
	canvas: CanvasItem,
	bez: PackedVector2Array,
	fade_in: bool,
	draw_shade: bool,
	draw_handles: bool,
	hot_apex: bool,
	hot_shape: bool,
	bounds: Rect2
) -> void:
	if bez.size() < 3:
		return
	var p0: Vector2 = bez[0]
	var p1: Vector2 = bez[1]
	var p2: Vector2 = bez[2]
	var curve_pts: PackedVector2Array = sample_quad_bezier(p0, p1, p2, FADE_CURVE_SEGMENTS)
	for i in curve_pts.size():
		curve_pts[i] = _clamp_point_to_rect(curve_pts[i], bounds)
	if draw_shade and curve_pts.size() >= 2:
		var shade := PackedVector2Array()
		if fade_in:
			shade.append(p0)
			shade.append(Vector2(p2.x, p0.y))
			for i in range(curve_pts.size() - 1, -1, -1):
				shade.append(curve_pts[i])
		else:
			shade.append(p0)
			for pt in curve_pts:
				shade.append(pt)
			shade.append(Vector2(p0.x, p2.y))
		canvas.draw_colored_polygon(shade, Tokens.FADE_SHADE)
	canvas.draw_polyline(curve_pts, Tokens.FADE_LINE, 1.5, true)
	if draw_handles:
		var apex: Vector2 = p2 if fade_in else p0
		var shape: Vector2 = quad_bezier_midpoint(p0, p1, p2)
		_draw_apex(canvas, apex, hot_apex, false)
		if draw_shade:
			_draw_diamond(canvas, shape, hot_shape)


static func draw_clip_fades(
	canvas: CanvasItem,
	state: Dictionary,
	clip: CodaTimelineClip,
	rect: Rect2,
	selected: bool
) -> void:
	if rect.size.x < 8.0:
		return
	var scroll: float = state.get("scroll_seconds", 0.0)
	var spp: float = state.get("seconds_per_pixel", 1.0 / 80.0)
	var hover_edge: String = String(state.get("hover_clip_edge", ""))
	var drag_clip_id: String = String(state.get("drag_clip_id", ""))
	var drag_kind: int = int(state.get("drag_kind", 0))
	var show_in: bool = clip.fade_in_seconds > 0.0 or selected
	var show_out: bool = clip.fade_out_seconds > 0.0 or selected
	if show_in:
		var hot_apex: bool = (
			hover_edge == "fade_in"
			or (drag_clip_id == clip.id and drag_kind == 4)
		)
		var hot_shape: bool = (
			hover_edge == "fade_in_shape"
			or (drag_clip_id == clip.id and drag_kind == 11)
		)
		if clip.fade_in_seconds > 0.0:
			var bez_in := fade_in_bezier(rect, clip, scroll, spp)
			draw_fade_curve(
				canvas,
				bez_in,
				true,
				true,
				selected,
				hot_apex,
				hot_shape,
				rect
			)
		elif selected:
			_draw_apex(canvas, fade_in_apex(rect, clip, scroll, spp), hot_apex, true)
	if show_out:
		var hot_apex_out: bool = (
			hover_edge == "fade_out"
			or (drag_clip_id == clip.id and drag_kind == 5)
		)
		var hot_shape_out: bool = (
			hover_edge == "fade_out_shape"
			or (drag_clip_id == clip.id and drag_kind == 12)
		)
		if clip.fade_out_seconds > 0.0:
			var bez_out := fade_out_bezier(rect, clip, scroll, spp)
			draw_fade_curve(
				canvas,
				bez_out,
				false,
				true,
				selected,
				hot_apex_out,
				hot_shape_out,
				rect
			)
		elif selected:
			_draw_apex(canvas, fade_out_apex(rect, clip, scroll, spp), hot_apex_out, true)


static func draw_track_crossfades(
	canvas: CanvasItem,
	state: Dictionary,
	clip_rects: Array
) -> void:
	if clip_rects.is_empty():
		return
	var scroll: float = state.get("scroll_seconds", 0.0)
	var spp: float = state.get("seconds_per_pixel", 1.0 / 80.0)
	var clips: Array = []
	for item in clip_rects:
		if item is Dictionary:
			clips.append(item.get("clip"))
	var pairs: Array = find_overlapping_pairs(clips)
	for pair in pairs:
		var a: CodaTimelineClip = pair.get("a") as CodaTimelineClip
		var b: CodaTimelineClip = pair.get("b") as CodaTimelineClip
		if a == null or b == null:
			continue
		if a.fade_out_seconds <= 0.0 and b.fade_in_seconds <= 0.0:
			continue
		var rect_a: Rect2 = _rect_for_clip_id(clip_rects, a.id)
		var rect_b: Rect2 = _rect_for_clip_id(clip_rects, b.id)
		if rect_a.size.x <= 0.0 or rect_b.size.x <= 0.0:
			continue
		var x0: float = Renderer.seconds_to_x(float(pair.get("start", 0.0)), scroll, spp)
		var x1: float = Renderer.seconds_to_x(float(pair.get("end", 0.0)), scroll, spp)
		if x1 <= x0:
			continue
		var y_top: float = minf(rect_a.position.y, rect_b.position.y)
		var y_bot: float = maxf(rect_a.end.y, rect_b.end.y)
		canvas.draw_rect(
			Rect2(Vector2(x0, y_top), Vector2(x1 - x0, y_bot - y_top)),
			Tokens.CROSSFADE_HIGHLIGHT,
			true
		)
		if a.fade_out_seconds > 0.0:
			var bez_out := fade_out_bezier(rect_a, a, scroll, spp)
			draw_fade_curve(canvas, bez_out, false, true, false, false, false, rect_a)
		if b.fade_in_seconds > 0.0:
			var bez_in := fade_in_bezier(rect_b, b, scroll, spp)
			draw_fade_curve(canvas, bez_in, true, true, false, false, false, rect_b)


static func _clamp_point_to_rect(p: Vector2, rect: Rect2) -> Vector2:
	return Vector2(
		clampf(p.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(p.y, rect.position.y, rect.position.y + rect.size.y)
	)


static func _rect_for_clip_id(clip_rects: Array, clip_id: String) -> Rect2:
	for item in clip_rects:
		if item is Dictionary and String(item.get("clip_id", "")) == clip_id:
			return item.get("rect", Rect2())
	return Rect2()


static func _draw_apex(canvas: CanvasItem, center: Vector2, hot: bool, idle: bool) -> void:
	var half: float = APEX_HALF * (0.85 if idle else 1.0)
	var rect := Rect2(center - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
	var fill: Color = Tokens.HANDLE_DIAMOND_FILL
	if hot:
		fill = Color(Tokens.ACCENT.r, Tokens.ACCENT.g, Tokens.ACCENT.b, 0.95)
	elif idle:
		fill = Color(fill.r, fill.g, fill.b, 0.72)
	canvas.draw_rect(rect, fill, true)
	canvas.draw_rect(rect, Tokens.HANDLE_DIAMOND_BORDER, false, 1.0)


static func _draw_diamond(canvas: CanvasItem, center: Vector2, hot: bool) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0.0, -DIAMOND_HALF),
		center + Vector2(DIAMOND_HALF, 0.0),
		center + Vector2(0.0, DIAMOND_HALF),
		center + Vector2(-DIAMOND_HALF, 0.0),
	])
	var fill: Color = Tokens.HANDLE_DIAMOND_FILL
	if hot:
		fill = Color(Tokens.ACCENT.r, Tokens.ACCENT.g, Tokens.ACCENT.b, 0.95)
	canvas.draw_colored_polygon(pts, fill)
	for i in 4:
		canvas.draw_line(pts[i], pts[(i + 1) % 4], Tokens.HANDLE_DIAMOND_BORDER, 1.0)
