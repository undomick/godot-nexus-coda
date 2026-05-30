extends RefCounted
class_name CodaTestRuntime

## Builds minimal [CodaState] + timeline music events for headless runtime tests.

const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaBrowserNodeScript := preload("res://addons/nexus_coda/domain/coda_browser_node.gd")
const CodaEventParameterScript := preload(
	"res://addons/nexus_coda/domain/coda_event_parameter.gd"
)
const CodaEventTimelineScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_event_timeline.gd"
)
const CodaTimelineTrackScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_track.gd"
)
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)
const CodaTimelineMarkerScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_marker.gd"
)
const CodaEventResolverScript := preload("res://addons/nexus_coda/runtime/coda_event_resolver.gd")


static func build_music_state() -> CodaState:
	var state: CodaState = CodaStateScript.new()
	var music_folder := CodaBrowserNodeScript.new("music", CodaBrowserNodeScript.Kind.FOLDER)
	state.events_root.children.append(music_folder)

	var ev := CodaBrowserNodeScript.new("exploration", CodaBrowserNodeScript.Kind.EVENT)
	ev.event_authoring_mode = CodaBrowserNodeScript.AuthoringMode.TIMELINE
	ev.event_timeline = CodaEventTimelineScript.make_default()
	ev.event_music_segment_param = "music_state"
	var tl: CodaEventTimeline = ev.event_timeline
	tl.length_seconds = 32.0
	tl.tempo_bpm = 120.0
	tl.loop_enabled = true

	var music_state := CodaEventParameterScript.new()
	music_state.param_name = "music_state"
	music_state.param_type = CodaEventParameterScript.ParamType.INT
	music_state.default_value = 0
	ev.event_parameters.append(music_state)

	var intensity := CodaEventParameterScript.new()
	intensity.param_name = "intensity"
	intensity.param_type = CodaEventParameterScript.ParamType.FLOAT
	intensity.default_value = 0.5
	ev.event_parameters.append(intensity)

	var seg_track: CodaTimelineTrack = CodaTimelineTrackScript.new()
	seg_track.track_name = "Segments"
	for i in 2:
		var clip: CodaTimelineClip = CodaTimelineClipScript.new()
		clip.start_seconds = float(i) * 10.0
		clip.duration_seconds = 10.0
		clip.segment_id = ["calm", "tense"][i]
		seg_track.clips.append(clip)
	tl.tracks.append(seg_track)

	var marker: CodaTimelineMarker = CodaTimelineMarkerScript.new()
	marker.marker_name = "ToTense"
	marker.time_seconds = 10.0
	marker.kind = CodaTimelineMarker.Kind.TRANSITION
	marker.target_segment_id = "tense"
	tl.markers.append(marker)

	music_folder.children.append(ev)
	return state


static func music_exploration_event(state: CodaState) -> CodaBrowserNode:
	return CodaEventResolverScript.resolve(state, "music/exploration")


static func build_snapshot_state() -> CodaState:
	var state: CodaState = CodaStateScript.new()
	var snap: CodaSnapshot = state.add_snapshot("TestSnap")
	snap.blend_ms = 1000
	snap.bus_overrides[state.bus_root.id] = {"volume_db": -12.0, "mute": false}
	return state
