@tool
class_name CodaTimelineCommands
extends RefCounted

## Track/clip/marker/BPM/loop mutations on [CodaEventTimeline].
## Each mutator returns a pre-change snapshot for undo when a change is attempted.

const CodaTimelineMarkerUiScript := preload(
	"res://addons/nexus_coda/editor/panels/timeline/coda_timeline_marker_ui.gd"
)


static func snapshot(timeline: CodaEventTimeline) -> CodaEventTimeline:
	return CodaTimelineUndo.make_snapshot(timeline)


static func validate(timeline: CodaEventTimeline) -> String:
	if timeline == null:
		return ""
	return timeline.validate()


static func timeline_content_end_seconds(timeline: CodaEventTimeline) -> float:
	if timeline == null:
		return 0.0
	var need: float = 0.0
	for tr in timeline.tracks:
		for c in tr.clips:
			need = maxf(need, c.start_seconds + c.duration_seconds)
	for m in timeline.markers:
		need = maxf(need, m.time_seconds)
	if timeline.loop_enabled:
		need = maxf(need, timeline.loop_end_seconds)
	return need


static func timeline_length_change_would_truncate(timeline: CodaEventTimeline, new_length: float) -> bool:
	return false


static func clamp_clips_to_timeline_length(_timeline: CodaEventTimeline) -> void:
	pass


static func extend_timeline_if_content_exceeds(timeline: CodaEventTimeline, margin: float = 0.25) -> void:
	if timeline == null:
		return
	var need: float = timeline_content_end_seconds(timeline)
	if need > timeline.length_seconds + 0.0001:
		timeline.length_seconds = need + margin


static func set_bpm(timeline: CodaEventTimeline, bpm: float) -> void:
	timeline.tempo_bpm = bpm


static func set_loop_enabled(timeline: CodaEventTimeline, on: bool) -> void:
	timeline.loop_enabled = on
	if on:
		timeline.clamp_loop_region_to_length()


static func set_timeline_length(timeline: CodaEventTimeline, value: float) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	timeline.length_seconds = maxf(0.5, value)
	timeline.clamp_work_points_to_length()
	return snap


static func fit_timeline_length(timeline: CodaEventTimeline, margin: float = 0.25) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	var need: float = timeline_content_end_seconds(timeline)
	timeline.length_seconds = maxf(0.5, need + margin)
	timeline.clamp_work_points_to_length()
	return snap


static func add_track(timeline: CodaEventTimeline) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	var tr := CodaTimelineTrack.new()
	tr.track_name = "Track %d" % (timeline.tracks.size() + 1)
	timeline.tracks.append(tr)
	return snap


static func remove_track(timeline: CodaEventTimeline, track_id: String) -> Dictionary:
	var snap := snapshot(timeline)
	var ok: bool = timeline.remove_track(track_id)
	return {"snapshot": snap, "success": ok}


static func reorder_tracks(timeline: CodaEventTimeline, from_i: int, to_i: int) -> CodaEventTimeline:
	if from_i == to_i:
		return null
	var snap := snapshot(timeline)
	timeline.reorder_tracks_move(from_i, to_i)
	return snap


static func duplicate_track(timeline: CodaEventTimeline, track_id: String) -> Dictionary:
	var src_i: int = track_index_by_id(timeline, track_id)
	if src_i < 0:
		return {"snapshot": null, "new_index": -1}
	var snap := snapshot(timeline)
	var d: Dictionary = timeline.tracks[src_i].to_dictionary()
	d.erase("id")
	var clips_raw: Variant = d.get("clips", [])
	var new_clips: Array = []
	if clips_raw is Array:
		for c in clips_raw as Array:
			if c is Dictionary:
				var cd: Dictionary = (c as Dictionary).duplicate()
				cd.erase("id")
				new_clips.append(cd)
	d["clips"] = new_clips
	var new_tr: CodaTimelineTrack = CodaTimelineTrack.from_dictionary(d)
	new_tr.track_name = timeline.tracks[src_i].track_name + " copy"
	timeline.tracks.insert(src_i + 1, new_tr)
	return {"snapshot": snap, "new_index": src_i + 1}


static func apply_track_volume_reset(timeline: CodaEventTimeline, track: CodaTimelineTrack) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	track.volume_db = 0.0
	return snap


static func apply_track_output_bus(
	timeline: CodaEventTimeline, track: CodaTimelineTrack, bus_id: String
) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	track.output_bus_id = bus_id
	return snap


static func apply_track_color(
	timeline: CodaEventTimeline, track: CodaTimelineTrack, color: Color
) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	track.color = color
	return snap


static func add_clip(
	timeline: CodaEventTimeline, track_index: int, playhead: float
) -> CodaEventTimeline:
	if timeline.tracks.is_empty():
		return null
	var snap := snapshot(timeline)
	var tr_i: int = clampi(track_index, 0, timeline.tracks.size() - 1)
	var clip := CodaTimelineClip.new()
	clip.start_seconds = maxf(0.0, playhead)
	clip.duration_seconds = 1.0
	timeline.tracks[tr_i].clips.append(clip)
	timeline.invalidate_clip_index()
	return snap


static func add_marker(timeline: CodaEventTimeline, playhead: float) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	var m := CodaTimelineMarker.new()
	m.time_seconds = clampf(playhead, 0.0, timeline.length_seconds)
	m.marker_name = "Marker %d" % (timeline.markers.size() + 1)
	timeline.markers.append(m)
	return snap


static func assign_clip_audio(
	timeline: CodaEventTimeline, clip_id: String, res_path: String
) -> CodaEventTimeline:
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return null
	var snap := snapshot(timeline)
	clip.audio_path = res_path
	clip.offset_seconds = 0.0
	clip.duration_seconds = clip.max_source_playable_seconds()
	return snap


static func drop_browser_asset(
	timeline: CodaEventTimeline, track_index: int, start_seconds: float, res_path: String
) -> CodaEventTimeline:
	if track_index < 0 or track_index >= timeline.tracks.size():
		return null
	var snap := snapshot(timeline)
	var clip := CodaTimelineClip.new()
	clip.audio_path = res_path
	clip.start_seconds = maxf(0.0, start_seconds)
	clip.offset_seconds = 0.0
	clip.duration_seconds = clip.max_source_playable_seconds()
	timeline.tracks[track_index].clips.append(clip)
	timeline.invalidate_clip_index()
	return snap


static func move_clip(
	timeline: CodaEventTimeline, clip_id: String, new_start: float, new_track_index: int
) -> void:
	if timeline == null or timeline.tracks.is_empty():
		return
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	var from_track: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
	if clip == null or from_track == null:
		return
	var target_track_index: int = clampi(new_track_index, 0, timeline.tracks.size() - 1)
	var clamped_start: float = maxf(0.0, new_start)
	var to_track: CodaTimelineTrack = timeline.tracks[target_track_index]
	if from_track != to_track:
		from_track.clips.erase(clip)
		to_track.clips.append(clip)
		timeline.invalidate_clip_index()
	clip.start_seconds = clamped_start


const MIN_CLIP_DURATION_SECONDS := 0.05


static func clamp_clip_fades(clip: CodaTimelineClip) -> void:
	if clip == null:
		return
	var dur: float = maxf(0.0, clip.duration_seconds)
	clip.fade_in_seconds = clampf(
		clip.fade_in_seconds, 0.0, maxf(0.0, dur - clip.fade_out_seconds)
	)
	clip.fade_out_seconds = clampf(
		clip.fade_out_seconds, 0.0, maxf(0.0, dur - clip.fade_in_seconds)
	)
	clip.fade_in_curve = clampf(clip.fade_in_curve, 0.0, 1.0)
	clip.fade_out_curve = clampf(clip.fade_out_curve, 0.0, 1.0)
	if clip.fade_in_seconds + clip.fade_out_seconds > dur:
		var scale: float = dur / maxf(0.0001, clip.fade_in_seconds + clip.fade_out_seconds)
		clip.fade_in_seconds *= scale
		clip.fade_out_seconds *= scale


static func apply_clip_fades(
	timeline: CodaEventTimeline,
	clip_id: String,
	fade_in: float,
	fade_out: float,
	fade_in_curve: float = -1.0,
	fade_out_curve: float = -1.0
) -> void:
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return
	clip.fade_in_seconds = maxf(0.0, fade_in)
	clip.fade_out_seconds = maxf(0.0, fade_out)
	if fade_in_curve >= 0.0:
		clip.fade_in_curve = clampf(fade_in_curve, 0.0, 1.0)
	if fade_out_curve >= 0.0:
		clip.fade_out_curve = clampf(fade_out_curve, 0.0, 1.0)
	clamp_clip_fades(clip)


static func set_clip_fades(
	timeline: CodaEventTimeline,
	clip_id: String,
	fade_in: float,
	fade_out: float,
	fade_in_curve: float = -1.0,
	fade_out_curve: float = -1.0
) -> CodaEventTimeline:
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return null
	var snap := snapshot(timeline)
	clip.fade_in_seconds = maxf(0.0, fade_in)
	clip.fade_out_seconds = maxf(0.0, fade_out)
	if fade_in_curve >= 0.0:
		clip.fade_in_curve = clampf(fade_in_curve, 0.0, 1.0)
	if fade_out_curve >= 0.0:
		clip.fade_out_curve = clampf(fade_out_curve, 0.0, 1.0)
	clamp_clip_fades(clip)
	return snap


static func set_clip_fade_curves(
	timeline: CodaEventTimeline,
	clip_id: String,
	fade_in_curve: float,
	fade_out_curve: float
) -> CodaEventTimeline:
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return null
	var snap := snapshot(timeline)
	clip.fade_in_curve = clampf(fade_in_curve, 0.0, 1.0)
	clip.fade_out_curve = clampf(fade_out_curve, 0.0, 1.0)
	return snap


static func set_clip_volume_db(
	timeline: CodaEventTimeline, clip_id: String, volume_db: float
) -> CodaEventTimeline:
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return null
	var snap := snapshot(timeline)
	clip.volume_db = volume_db
	return snap


static func set_clip_pitch_scale(
	timeline: CodaEventTimeline, clip_id: String, pitch_scale: float
) -> CodaEventTimeline:
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return null
	var snap := snapshot(timeline)
	clip.pitch_scale = maxf(0.01, pitch_scale)
	return snap


static func move_clip_to_track(
	timeline: CodaEventTimeline, clip_id: String, new_start: float, track_index: int
) -> CodaEventTimeline:
	if timeline == null:
		return null
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	var snap: CodaEventTimeline = null
	if track_index >= timeline.tracks.size():
		snap = add_track(timeline)
		track_index = timeline.tracks.size() - 1
	move_clip(timeline, clip_id, new_start, track_index)
	return snap


static func resize_clip(
	timeline: CodaEventTimeline,
	clip_id: String,
	new_start: float,
	new_duration: float,
	new_offset_seconds: float = NAN
) -> void:
	if timeline == null:
		return
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return
	clip.start_seconds = max(0.0, new_start)
	if new_offset_seconds == new_offset_seconds:
		clip.offset_seconds = maxf(0.0, new_offset_seconds)
	var max_d: float = clip.max_source_playable_seconds()
	clip.duration_seconds = clampf(new_duration, MIN_CLIP_DURATION_SECONDS, max_d)
	clamp_clip_fades(clip)


static func delete_clip(timeline: CodaEventTimeline, clip_id: String) -> CodaEventTimeline:
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	var track: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
	if clip == null or track == null:
		return null
	var snap := snapshot(timeline)
	var idx: int = track.clips.find(clip)
	if idx >= 0:
		track.clips.remove_at(idx)
		timeline.invalidate_clip_index()
	return snap


static func split_clip_at_time(
	timeline: CodaEventTimeline, clip_id: String, split_seconds: float
) -> Dictionary:
	var snap := snapshot(timeline)
	var err: String = timeline.split_clip_at_time(clip_id, split_seconds)
	return {"snapshot": snap, "error": err}


static func duplicate_clip(timeline: CodaEventTimeline, clip_id: String) -> Dictionary:
	var snap := snapshot(timeline)
	var err: String = timeline.duplicate_clip(clip_id)
	return {"snapshot": snap, "error": err}


static func clip_copy_data(timeline: CodaEventTimeline, clip_id: String) -> Dictionary:
	var info: Dictionary = timeline.find_clip(clip_id)
	if info.is_empty():
		return {}
	var clip: CodaTimelineClip = info.get("clip") as CodaTimelineClip
	if clip == null:
		return {}
	return clip.to_dictionary()


static func paste_clip_at_playhead(
	timeline: CodaEventTimeline,
	track_index: int,
	start_seconds: float,
	data: Dictionary
) -> Dictionary:
	if timeline == null or data.is_empty():
		return {"snapshot": null, "error": "Nothing to paste.", "clip_id": ""}
	var snap := snapshot(timeline)
	var result: Dictionary = timeline.paste_clip_at(track_index, start_seconds, data)
	if not String(result.get("error", "")).is_empty():
		return {"snapshot": snap, "error": result.get("error", ""), "clip_id": ""}
	return {
		"snapshot": snap,
		"error": "",
		"clip_id": String(result.get("clip_id", "")),
	}


static func cut_clip(timeline: CodaEventTimeline, clip_id: String) -> Dictionary:
	var data: Dictionary = clip_copy_data(timeline, clip_id)
	if data.is_empty():
		return {"snapshot": null, "error": "Clip not found.", "data": {}}
	var snap := delete_clip(timeline, clip_id)
	return {"snapshot": snap, "error": "", "data": data}


static func rename_marker(timeline: CodaEventTimeline, marker: CodaTimelineMarker, new_name: String) -> CodaEventTimeline:
	if marker == null:
		return null
	var snap := snapshot(timeline)
	CodaTimelineMarkerUiScript.rename_marker(marker, new_name)
	return snap


static func delete_marker(timeline: CodaEventTimeline, marker_id: String) -> Dictionary:
	var snap := snapshot(timeline)
	var ok: bool = CodaTimelineMarkerUiScript.delete_marker(timeline, marker_id)
	return {"snapshot": snap, "success": ok}


static func toggle_in_point(timeline: CodaEventTimeline, playhead: float) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	var t: float = clampf(playhead, 0.0, timeline.length_seconds)
	if timeline.has_in_point() and is_equal_approx(timeline.in_point_seconds, t):
		timeline.clear_in_point()
	else:
		timeline.in_point_seconds = t
		if timeline.has_out_point() and timeline.out_point_seconds <= t:
			timeline.out_point_seconds = minf(
				timeline.length_seconds, t + CodaEventTimeline.MIN_WORK_AREA_GAP_SECONDS
			)
	return snap


static func toggle_out_point(timeline: CodaEventTimeline, playhead: float) -> CodaEventTimeline:
	var snap := snapshot(timeline)
	var t: float = clampf(playhead, 0.0, timeline.length_seconds)
	if timeline.has_out_point() and is_equal_approx(timeline.out_point_seconds, t):
		timeline.clear_out_point()
	else:
		timeline.out_point_seconds = t
		if timeline.has_in_point() and timeline.in_point_seconds >= t:
			timeline.in_point_seconds = maxf(
				0.0, t - CodaEventTimeline.MIN_WORK_AREA_GAP_SECONDS
			)
	return snap


static func delete_in_point(timeline: CodaEventTimeline) -> CodaEventTimeline:
	if not timeline.has_in_point():
		return null
	var snap := snapshot(timeline)
	timeline.clear_in_point()
	return snap


static func delete_out_point(timeline: CodaEventTimeline) -> CodaEventTimeline:
	if not timeline.has_out_point():
		return null
	var snap := snapshot(timeline)
	timeline.clear_out_point()
	return snap


static func track_index_by_id(timeline: CodaEventTimeline, track_id: String) -> int:
	for idx in range(timeline.tracks.size()):
		if timeline.tracks[idx].id == track_id:
			return idx
	return -1


static func selected_track_index_after_reorder(from_i: int, to_i: int, selected: int) -> int:
	if selected == from_i:
		return to_i
	if from_i < selected and to_i >= selected:
		return selected - 1
	if from_i > selected and to_i <= selected:
		return selected + 1
	return selected
