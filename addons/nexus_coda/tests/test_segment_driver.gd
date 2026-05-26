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
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaTimelineDispatcherScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_dispatcher.gd"
)
const CodaModulationScript := preload("res://addons/nexus_coda/editor/browser/coda_modulation.gd")
const CodaEventParameterScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_event_parameter.gd"
)
const CodaRuntimeParameterPipelineScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_parameter_pipeline.gd"
)


class SegmentReprimeTestRuntime extends CodaRuntimeScript:
	var crossfade_used: Array[int] = []

	func spawn_timeline_segment_voice(
		_h: CodaEventHandle, d: Dictionary, entry: Dictionary, crossfade_ms: int = -1
	) -> bool:
		if not crossfade_used.is_empty():
			crossfade_used[0] = crossfade_ms
		var clip_id: String = String(entry.get("sound_id", ""))
		if clip_id.is_empty():
			return false
		var voices: Dictionary = d.get("voices", {})
		voices[clip_id] = AudioStreamPlayer.new()
		d["voices"] = voices
		return true


static func run() -> int:
	var failed: int = 0
	failed += _test_segment_resolution()
	failed += _test_default_param_names()
	failed += _test_custom_segment_param()
	failed += _test_intensity_not_segment()
	failed += _test_segment_dispatch_state_sync()
	failed += _test_same_segment_reprime_uses_zero_crossfade()
	failed += _test_timeline_refresh_applies_per_voice_modulation()
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


static func _test_same_segment_reprime_uses_zero_crossfade() -> int:
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var timeline = ev.event_timeline
	var seg_tr = CodaTimelineSegmentDriverScript.segments_track(timeline)
	if seg_tr == null or seg_tr.clips.is_empty():
		push_error("reprime test needs Segments track")
		return 1
	var calm = seg_tr.clips[0]
	var crossfade_used: Array[int] = [-1]
	var runtime := SegmentReprimeTestRuntime.new()
	runtime.crossfade_used = crossfade_used
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle.event_node = ev
	handle.param_values = {"music_state": 0}
	var d: Dictionary = {
		"timeline": timeline,
		"active_segment_id": calm.segment_id,
		"voices": {},
		"fired_clip_ids": {},
		"spent_clip_ids": {},
	}
	CodaTimelineSegmentDriverScript.new().apply_segment_change(
		runtime, handle, d, calm.segment_id, 500
	)
	if crossfade_used[0] != 0:
		push_error("same-segment reprime after voice loss should use 0 ms crossfade, got %s" % crossfade_used[0])
		return 1
	if not (d.get("voices", {}) as Dictionary).has(calm.id):
		push_error("same-segment reprime should respawn the segment voice")
		return 1
	runtime.free()
	return 0


static func _test_intensity_not_segment() -> int:
	var ev := CodaBrowserNodeScript.new("ev", CodaBrowserNodeScript.Kind.EVENT)
	ev.event_music_segment_param = "music_state"
	if CodaTimelineSegmentDriverScript.should_drive_param("intensity", ev):
		push_error("intensity should not drive segments when music_state is configured")
		return 1
	return 0


static func _test_timeline_refresh_applies_per_voice_modulation() -> int:
	var state: CodaState = CodaTestRuntimeScript.build_music_state()
	var ev: CodaBrowserNode = CodaTestRuntimeScript.music_exploration_event(state)
	var timeline = ev.event_timeline
	var intensity: CodaEventParameter = null
	for p in ev.event_parameters:
		if p.param_name == "intensity":
			intensity = p
			break
	if intensity == null:
		push_error("music test event needs intensity parameter")
		return 1
	var stem_track: CodaTimelineTrack = CodaTimelineTrackScript.new()
	stem_track.track_name = "Stems"
	var stem_clip: CodaTimelineClip = CodaTimelineClipScript.new()
	stem_clip.id = "stem_low"
	stem_clip.start_seconds = 0.0
	stem_clip.duration_seconds = 20.0
	stem_track.clips.append(stem_clip)
	timeline.tracks.append(stem_track)
	var mod := CodaModulationScript.new()
	mod.source_param_id = intensity.id
	mod.target_node_id = stem_clip.id
	mod.target_property = CodaModulationScript.TargetProperty.SOUND_VOLUME_DB
	mod.range_in_min = 0.0
	mod.range_in_max = 1.0
	mod.range_out_min = 0.0
	mod.range_out_max = -12.0
	ev.event_modulations.append(mod)
	var runtime: CodaRuntime = CodaRuntimeScript.new()
	runtime._parameter_pipeline = CodaRuntimeParameterPipelineScript.new()
	runtime._parameter_pipeline.setup(runtime)
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.is_timeline = true
	handle._alive = true
	handle.event_node = ev
	handle.param_values[intensity.id] = 1.0
	handle.param_values_smoothed[intensity.id] = 1.0
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	runtime.add_child(player)
	var d: Dictionary = {
		"timeline": timeline,
		"voices": {stem_clip.id: player},
		"fired_clip_ids": {stem_clip.id: true},
	}
	runtime._timeline_dispatchers[handle] = d
	var dispatcher: CodaTimelineDispatcher = CodaTimelineDispatcherScript.new()
	dispatcher.setup(runtime, null, null)
	dispatcher._clip_dispatch.refresh_voice_output_levels(handle, d, timeline)
	if abs(player.volume_db - (-12.0)) > 0.05:
		push_error("timeline refresh should apply RTPC modulation per voice, got %s" % player.volume_db)
		return 1
	runtime.free()
	return 0
