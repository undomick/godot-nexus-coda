extends RefCounted
class_name TestTimelineClipChrome

const ChromeScript := preload(
	"res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_clip_chrome.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_overlap_pairs()
	failed += _test_bezier_midpoint()
	failed += _test_shape_drag_tracks_mouse()
	return failed


static func _test_shape_drag_tracks_mouse() -> int:
	var rect := Rect2(0.0, 0.0, 200.0, 80.0)
	var top_in: float = ChromeScript.curve_from_shape_drag_y(0.0, rect, true)
	var bottom_in: float = ChromeScript.curve_from_shape_drag_y(80.0, rect, true)
	if top_in < bottom_in:
		push_error("fade-in curve should decrease when dragging down")
		return 1
	var top_out: float = ChromeScript.curve_from_shape_drag_y(0.0, rect, false)
	var bottom_out: float = ChromeScript.curve_from_shape_drag_y(80.0, rect, false)
	if top_out > bottom_out:
		push_error("fade-out curve should increase when dragging down")
		return 1
	return 0


static func _test_overlap_pairs() -> int:
	var a = CodaTimelineClipScript.new()
	a.start_seconds = 0.0
	a.duration_seconds = 4.0
	var b = CodaTimelineClipScript.new()
	b.start_seconds = 3.0
	b.duration_seconds = 4.0
	var c = CodaTimelineClipScript.new()
	c.start_seconds = 8.0
	c.duration_seconds = 2.0
	var pairs: Array = ChromeScript.find_overlapping_pairs([a, b, c])
	if pairs.size() != 1:
		push_error("expected one overlapping pair")
		return 1
	var pair: Dictionary = pairs[0]
	if abs(float(pair.get("start", -1.0)) - 3.0) > 0.001:
		push_error("overlap start should be 3.0")
		return 1
	if abs(float(pair.get("end", -1.0)) - 4.0) > 0.001:
		push_error("overlap end should be 4.0")
		return 1
	return 0


static func _test_bezier_midpoint() -> int:
	var p0 := Vector2(0.0, 0.0)
	var p1 := Vector2(50.0, 20.0)
	var p2 := Vector2(100.0, 100.0)
	var mid: Vector2 = ChromeScript.quad_bezier_midpoint(p0, p1, p2)
	if mid.x <= p0.x or mid.x >= p2.x:
		push_error("bezier midpoint x should lie between endpoints")
		return 1
	return 0
