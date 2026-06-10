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
const CodaTimelineClipOverlapResolverScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip_overlap_resolver.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_clamp_clip_fades()
	failed += _test_set_clip_fades()
	failed += _test_fade_curve_serialization()
	failed += _test_move_clip_to_new_track()
	failed += _test_paste_resolves_overlap()
	failed += _test_drop_resolves_overlap()
	failed += _test_duplicate_resolves_overlap()
	failed += _test_add_clip_resolves_overlap()
	failed += _test_assign_clip_audio_resolves_overlap()
	failed += _test_duplicate_track_invalidates_clip_index()
	failed += _test_move_clip_invalidates_spatial_index()
	failed += _test_resize_clip_invalidates_spatial_index()
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


static func _test_paste_resolves_overlap() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var existing = CodaTimelineClipScript.new()
	existing.start_seconds = 0.0
	existing.duration_seconds = 5.0
	timeline.tracks[0].clips.append(existing)
	var pasted = CodaTimelineClipScript.new()
	pasted.duration_seconds = 5.0
	var data: Dictionary = pasted.to_dictionary()
	var result: Dictionary = CodaTimelineCommandsScript.paste_clip_at_playhead(
		timeline, 0, 2.0, data
	)
	if not String(result.get("error", "")).is_empty():
		push_error("paste overlap: paste should succeed")
		return 1
	if CodaTimelineClipOverlapResolverScript.intervals_overlap(
		2.0, 7.0, existing.start_seconds, existing.end_seconds()
	):
		push_error("paste overlap: existing clip should be trimmed under pasted clip")
		return 1
	return 0


static func _test_drop_resolves_overlap() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var existing = CodaTimelineClipScript.new()
	existing.start_seconds = 0.0
	existing.duration_seconds = 5.0
	timeline.tracks[0].clips.append(existing)
	CodaTimelineCommandsScript.drop_browser_asset(timeline, 0, 2.0, "res://missing.wav")
	if existing.end_seconds() > 2.0 + 0.001:
		push_error("drop overlap: existing clip should be trimmed to end at 2s")
		return 1
	return 0


static func _test_duplicate_resolves_overlap() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var first = CodaTimelineClipScript.new()
	first.start_seconds = 0.0
	first.duration_seconds = 4.0
	var second = CodaTimelineClipScript.new()
	second.start_seconds = 4.05
	second.duration_seconds = 4.0
	timeline.tracks[0].clips.append(first)
	timeline.tracks[0].clips.append(second)
	var result: Dictionary = CodaTimelineCommandsScript.duplicate_clip(timeline, first.id)
	if not String(result.get("error", "")).is_empty():
		push_error("duplicate overlap: duplicate should succeed")
		return 1
	var dup_id: String = String(result.get("clip_id", ""))
	if dup_id.is_empty():
		push_error("duplicate overlap: should return new clip id")
		return 1
	var dup_info: Dictionary = timeline.find_clip(dup_id)
	var dup: CodaTimelineClip = dup_info.get("clip") as CodaTimelineClip
	if dup == null:
		push_error("duplicate overlap: duplicated clip not found")
		return 1
	for clip in timeline.tracks[0].clips:
		if clip.id == dup_id:
			continue
		if CodaTimelineClipOverlapResolverScript.intervals_overlap(
			dup.start_seconds, dup.end_seconds(), clip.start_seconds, clip.end_seconds()
		):
			push_error("duplicate overlap: no clip on track should overlap duplicate")
			return 1
	return 0


static func _test_add_clip_resolves_overlap() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var existing = CodaTimelineClipScript.new()
	existing.start_seconds = 0.0
	existing.duration_seconds = 5.0
	timeline.tracks[0].clips.append(existing)
	CodaTimelineCommandsScript.add_clip(timeline, 0, 2.0)
	if existing.end_seconds() > 2.0 + 0.001:
		push_error("add clip overlap: existing clip should be trimmed to end at 2s")
		return 1
	return 0


static func _test_assign_clip_audio_resolves_overlap() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var assigned = CodaTimelineClipScript.new()
	assigned.start_seconds = 0.0
	assigned.duration_seconds = 2.0
	var neighbor = CodaTimelineClipScript.new()
	neighbor.start_seconds = 5.0
	neighbor.duration_seconds = 5.0
	timeline.tracks[0].clips.append(assigned)
	timeline.tracks[0].clips.append(neighbor)
	timeline.invalidate_clip_index()
	# Missing asset -> max_source_playable_seconds is huge; must not leave overlapping neighbor.
	CodaTimelineCommandsScript.assign_clip_audio(
		timeline, assigned.id, "res://addons/nexus_coda/tests/missing_test_audio.ogg"
	)
	for clip in timeline.tracks[0].clips:
		if clip.id == assigned.id:
			continue
		if CodaTimelineClipOverlapResolverScript.intervals_overlap(
			assigned.start_seconds,
			assigned.end_seconds(),
			clip.start_seconds,
			clip.end_seconds()
		):
			push_error("assign clip audio overlap: neighbor should be trimmed or removed")
			return 1
	return 0


static func _test_duplicate_track_invalidates_clip_index() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var clip = CodaTimelineClipScript.new()
	clip.duration_seconds = 2.0
	timeline.tracks[0].clips.append(clip)
	timeline.find_clip(clip.id)
	var track_id: String = timeline.tracks[0].id
	var result: Dictionary = CodaTimelineCommandsScript.duplicate_track(timeline, track_id)
	if int(result.get("new_index", -1)) < 0:
		push_error("duplicate track should succeed")
		return 1
	var new_track = timeline.tracks[int(result.get("new_index", -1))]
	if new_track.clips.is_empty():
		push_error("duplicated track should copy clips")
		return 1
	var dup_clip_id: String = new_track.clips[0].id
	if timeline.find_clip(dup_clip_id).is_empty():
		push_error("duplicated clip must be findable after duplicate_track")
		return 1
	var snap = CodaTimelineCommandsScript.set_clip_volume_db(timeline, dup_clip_id, -6.0)
	if snap == null:
		push_error("commands on duplicated clip should work after duplicate_track")
		return 1
	return 0


static func _clip_active_at(timeline: CodaEventTimeline, clip_id: String, at_seconds: float) -> bool:
	for entry in timeline.clips_active_at(at_seconds):
		var clip: CodaTimelineClip = entry.get("clip") as CodaTimelineClip
		if clip != null and clip.id == clip_id:
			return true
	return false


static func _test_move_clip_invalidates_spatial_index() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var clip = CodaTimelineClipScript.new()
	clip.start_seconds = 1.0
	clip.duration_seconds = 2.0
	timeline.tracks[0].clips.append(clip)
	timeline.find_clip(clip.id)
	CodaTimelineCommandsScript.move_clip(timeline, clip.id, 6.0, 0)
	if _clip_active_at(timeline, clip.id, 1.5):
		push_error("move_clip: spatial index should not keep clip active at old start")
		return 1
	if not _clip_active_at(timeline, clip.id, 6.5):
		push_error("move_clip: spatial index should list clip at new start")
		return 1
	return 0


static func _test_resize_clip_invalidates_spatial_index() -> int:
	var timeline = CodaEventTimelineScript.make_default()
	var clip = CodaTimelineClipScript.new()
	clip.start_seconds = 0.0
	clip.duration_seconds = 2.0
	timeline.tracks[0].clips.append(clip)
	timeline.find_clip(clip.id)
	CodaTimelineCommandsScript.resize_clip(timeline, clip.id, 0.0, 5.0)
	if not _clip_active_at(timeline, clip.id, 4.5):
		push_error("resize_clip: spatial index should reflect extended duration")
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
