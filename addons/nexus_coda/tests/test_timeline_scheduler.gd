extends RefCounted
class_name TestTimelineScheduler

const CodaTimelineSchedulerScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_scheduler.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_event_timeline.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_track.gd"
)
const CodaBusSendScript := preload("res://addons/nexus_coda/domain/coda_bus_send.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_entry_includes_wet_sends_and_bus_routing()
	return failed


static func _test_entry_includes_wet_sends_and_bus_routing() -> int:
	var timeline: CodaEventTimeline = CodaEventTimelineScript.new()
	timeline.length_seconds = 10.0
	var track: CodaTimelineTrack = CodaTimelineTrackScript.new()
	track.output_bus_id = "bus_main"
	var send: CodaBusSend = CodaBusSendScript.new()
	send.target_bus_id = "bus_return"
	track.wet_sends.append(send)
	var clip: CodaTimelineClip = CodaTimelineClipScript.new()
	clip.audio_path = "res://audio/test.ogg"
	clip.start_seconds = 0.0
	clip.duration_seconds = 5.0
	track.clips.append(clip)
	timeline.tracks.append(track)
	var planned: Array = CodaTimelineSchedulerScript.plan(timeline, {}, 0.0, 10.0)
	if planned.is_empty():
		push_error("scheduler should plan active clip")
		return 1
	var entry: Dictionary = planned[0] as Dictionary
	if String(entry.get("track_output_bus_id", "")) != "bus_main":
		push_error("scheduler entry should include track_output_bus_id")
		return 1
	var wet_sends: Array = entry.get("track_wet_sends", []) as Array
	if wet_sends.is_empty() or wet_sends[0].target_bus_id != "bus_return":
		push_error("scheduler entry should include track_wet_sends")
		return 1
	if float(entry.get("timeline_clip_end_seconds", -1.0)) < 4.9:
		push_error("scheduler entry should include timeline_clip_end_seconds")
		return 1
	return 0
