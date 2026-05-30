extends RefCounted
class_name TestTimelineCommands

const CodaTimelineCommandsScript := preload(
	"res://addons/nexus_coda/editor/panels/timeline/coda_timeline_commands.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_event_timeline.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_clamp_clip_fades()
	failed += _test_set_clip_fades()
	failed += _test_fade_curve_serialization()
	failed += _test_move_clip_to_new_track()
	return failed


static func _test_clamp_clip_fades() -> int:
	var clip = CodaTimelineClipScript.new()
	clip.duration_seconds = 4.0
	clip.fade_in_seconds = 3.0
	clip.fade_out_seconds = 3.0
	CodaTimelineCommandsScript.clamp_clip_fades(clip)
	if clip.fade_in_seconds + clip.fade_out_seconds > clip.duration_seconds + 0.001:
		push_error("clamp_clip_fades should keep sum <= duration")
		return 1
	clip.fade_in_seconds = 3.8
	clip.fade_out_seconds = 0.1
	CodaTimelineCommandsScript.clamp_clip_fades(clip)
	if clip.fade_in_seconds + clip.fade_out_seconds > clip.duration_seconds + 0.001:
		push_error("fades should meet without half-duration cap")
		return 1
	return 0


static func _test_set_clip_fades() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var clip = CodaTimelineClipScript.new()
	clip.duration_seconds = 2.0
	timeline.tracks[0].clips.append(clip)
	var snap = CodaTimelineCommandsScript.set_clip_fades(timeline, clip.id, 1.5, 1.5)
	if snap == null:
		push_error("set_clip_fades should return snapshot")
		return 1
	if clip.fade_in_seconds + clip.fade_out_seconds > clip.duration_seconds + 0.001:
		push_error("set_clip_fades should clamp overlapping fades")
		return 1
	return 0


static func _test_fade_curve_serialization() -> int:
	var clip = CodaTimelineClipScript.new()
	clip.fade_in_curve = 0.2
	clip.fade_out_curve = 0.8
	var data: Dictionary = clip.to_dictionary()
	var restored = CodaTimelineClipScript.from_dictionary(data)
	if abs(restored.fade_in_curve - 0.2) > 0.001:
		push_error("fade_in_curve should round-trip through serialization")
		return 1
	if abs(restored.fade_out_curve - 0.8) > 0.001:
		push_error("fade_out_curve should round-trip through serialization")
		return 1
	clip.fade_in_curve = 1.5
	clip.fade_out_curve = -0.5
	CodaTimelineCommandsScript.clamp_clip_fades(clip)
	if clip.fade_in_curve > 1.0 or clip.fade_out_curve < 0.0:
		push_error("clamp_clip_fades should clamp curve values to 0..1")
		return 1
	return 0


static func _test_move_clip_to_new_track() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var clip = CodaTimelineClipScript.new()
	clip.duration_seconds = 1.0
	clip.start_seconds = 0.5
	timeline.tracks[0].clips.append(clip)
	var snap = CodaTimelineCommandsScript.move_clip_to_track(timeline, clip.id, 2.0, 1)
	if snap == null:
		push_error("move_clip_to_track should return snapshot when creating track")
		return 1
	if timeline.tracks.size() != 2:
		push_error("move_clip_to_track should append a track")
		return 1
	if timeline.tracks[1].clips.size() != 1:
		push_error("clip should be on the new track")
		return 1
	if abs(clip.start_seconds - 2.0) > 0.001:
		push_error("clip start should be preserved on new track")
		return 1
	return 0
