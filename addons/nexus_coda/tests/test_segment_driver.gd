extends RefCounted
class_name TestSegmentDriver

const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_clip.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_event_timeline.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_track.gd"
)
const CodaTimelineSegmentDriverScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_segment_driver.gd"
)
const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaBrowserNodeScript := preload("res://addons/nexus_coda/editor/browser/coda_browser_node.gd")
const CodaTestRuntimeScript := preload("res://addons/nexus_coda/tests/helpers/coda_test_runtime.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_segment_resolution()
	failed += _test_default_param_names()
	failed += _test_custom_segment_param()
	failed += _test_intensity_not_segment()
	failed += _test_segment_dispatch_state_sync()
	return failed


static func _test_segment_resolution() -> int:
	var tl = CodaEventTimelineScript.make_default()
	var tr = CodaTimelineTrackScript.new()
	tr.track_name = "Segments"
	var clip = CodaTimelineClipScript.new()
	clip.segment_id = "calm"
	tr.clips.append(clip)
	tl.tracks.append(tr)
	var seg: String = CodaTimelineSegmentDriverScript.resolve_segment_id(tl, "music_state", 0)
	if seg != "calm":
		push_error("segment resolution expected calm, got %s" % seg)
		return 1
	return 0


static func _test_default_param_names() -> int:
	if not CodaTimelineSegmentDriverScript.should_drive_param("music_state", null):
		push_error("music_state should drive segments")
		return 1
	return 0


static func _test_custom_segment_param() -> int:
	var ev := CodaBrowserNodeScript.new("ev", CodaBrowserNodeScript.Kind.EVENT)
	ev.event_music_segment_param = "zone_mode"
	if CodaTimelineSegmentDriverScript.should_drive_param("zone_mode", ev):
		pass
	else:
		push_error("custom segment param should match")
		return 1
	if CodaTimelineSegmentDriverScript.should_drive_param("music_state", ev):
		push_error("default name should not match when custom param set")
		return 1
	return 0


static func _test_segment_dispatch_state_sync() -> int:
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var timeline = ev.event_timeline
	var seg_tr = CodaTimelineSegmentDriverScript.segments_track(timeline)
	if seg_tr == null or seg_tr.clips.size() < 2:
		push_error("segment dispatch test needs Segments track with two clips")
		return 1
	var calm = seg_tr.clips[0]
	var tense = seg_tr.clips[1]
	var d: Dictionary = {
		"timeline": timeline,
		"fired_clip_ids": {calm.id: true},
		"spent_clip_ids": {},
		"voices": {},
		"active_segment_id": "",
	}
	CodaTimelineSegmentDriverScript._sync_segment_clip_dispatch_state(d, timeline, tense.id)
	var fired: Dictionary = d.get("fired_clip_ids", {})
	var spent: Dictionary = d.get("spent_clip_ids", {})
	if not fired.has(tense.id) or fired.has(calm.id):
		push_error("active segment clip should be fired; outgoing should not stay fired")
		return 1
	if not spent.has(calm.id):
		push_error("outgoing segment clip should be marked spent")
		return 1
	return 0


static func _test_intensity_not_segment() -> int:
	var ev := CodaBrowserNodeScript.new("ev", CodaBrowserNodeScript.Kind.EVENT)
	ev.event_music_segment_param = "music_state"
	if CodaTimelineSegmentDriverScript.should_drive_param("intensity", ev):
		push_error("intensity should not drive segments when music_state is configured")
		return 1
	return 0
