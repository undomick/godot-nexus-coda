extends RefCounted
class_name TestTimelineMusicController

const CodaTimelineMusicControllerScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_music_controller.gd"
)
const CodaTimelineSegmentDriverScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_segment_driver.gd"
)
const CodaTestRuntimeScript := preload("res://addons/nexus_coda/tests/helpers/coda_test_runtime.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaTimelineMarkerScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_marker.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_marker_crossed_once()
	failed += _test_marker_in_loop_wrap_tail()
	failed += _test_marker_forward_wrap_overlap_dedupe()
	failed += _test_should_notify_for_param()
	return failed


static func _test_marker_crossed_once() -> int:
	var markers: Array[String] = []
	var ctrl := CodaTimelineMusicControllerScript.new()
	ctrl.setup(null, null, CodaTimelineSegmentDriverScript.new(), null, func(h: CodaEventHandle, mid: String) -> void:
		markers.append(mid)
	)
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle.event_node = ev
	var d: Dictionary = {"timeline": ev.event_timeline}
	var dispatchers: Dictionary = {handle: d}
	ctrl.check_markers_crossed(handle, ev.event_timeline, 9.0, 10.5, dispatchers)
	if markers.size() != 1 or markers[0] != ev.event_timeline.markers[0].id:
		push_error("marker should fire once when cursor crosses")
		return 1
	ctrl.check_markers_crossed(handle, ev.event_timeline, 10.5, 11.0, dispatchers)
	if markers.size() != 1:
		push_error("marker should not fire again")
		return 1
	return 0


static func _test_marker_in_loop_wrap_tail() -> int:
	var markers: Array[String] = []
	var ctrl := CodaTimelineMusicControllerScript.new()
	ctrl.setup(null, null, CodaTimelineSegmentDriverScript.new(), null, func(_h: CodaEventHandle, mid: String) -> void:
		markers.append(mid)
	)
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var timeline = ev.event_timeline
	timeline.loop_enabled = true
	timeline.loop_start_seconds = 0.0
	timeline.loop_end_seconds = 10.0
	timeline.markers.clear()
	var tail_marker := CodaTimelineMarkerScript.new()
	tail_marker.time_seconds = 9.95
	timeline.markers.append(tail_marker)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle.event_node = ev
	var dispatchers: Dictionary = {handle: {"timeline": timeline}}
	ctrl.check_markers_crossed(handle, timeline, 9.9, 10.0, dispatchers)
	if markers.size() != 1 or markers[0] != tail_marker.id:
		push_error("loop-wrap tail marker should fire when checking pre-wrap range")
		return 1
	markers.clear()
	ctrl.check_markers_crossed(handle, timeline, 0.0, 0.1, dispatchers)
	if not markers.is_empty():
		push_error("post-wrap-only range must not fire tail marker")
		return 1
	return 0


static func _test_marker_forward_wrap_overlap_dedupe() -> int:
	var markers: Array[String] = []
	var ctrl := CodaTimelineMusicControllerScript.new()
	ctrl.setup(null, null, CodaTimelineSegmentDriverScript.new(), null, func(_h: CodaEventHandle, mid: String) -> void:
		markers.append(mid)
	)
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var timeline = ev.event_timeline
	timeline.loop_enabled = true
	timeline.loop_start_seconds = 0.0
	timeline.loop_end_seconds = 10.0
	timeline.markers.clear()
	var mid := CodaTimelineMarkerScript.new()
	mid.time_seconds = 3.0
	timeline.markers.append(mid)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle.event_node = ev
	var dispatchers: Dictionary = {handle: {"fired_marker_ids": {}}}
	# Simulates pre-wrap tail + post-wrap overlap on forward loop landing.
	ctrl.check_markers_crossed(handle, timeline, 2.0, 10.0, dispatchers)
	ctrl.check_markers_crossed(handle, timeline, 2.0, 5.0, dispatchers)
	if markers.size() != 1 or markers[0] != mid.id:
		push_error("forward wrap overlap must not fire the same marker twice in one lap")
		return 1
	return 0


static func _test_should_notify_for_param() -> int:
	var ctrl := CodaTimelineMusicControllerScript.new()
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var find_param := func(_event: CodaBrowserNode, _id: String) -> CodaEventParameter: return null
	if not ctrl.should_notify_for_param(ev, "music_state", find_param):
		push_error("music_state should notify")
		return 1
	if ctrl.should_notify_for_param(ev, "intensity", find_param):
		push_error("intensity should not notify segment change")
		return 1
	return 0
