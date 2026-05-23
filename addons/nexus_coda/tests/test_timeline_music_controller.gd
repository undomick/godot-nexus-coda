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


static func run() -> int:
	var failed: int = 0
	failed += _test_marker_crossed_once()
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
