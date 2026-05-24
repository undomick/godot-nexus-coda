@tool
class_name CodaTimelineMusicController
extends RefCounted

## Timeline music: segment switches, marker callbacks, segment voice spawn/fade.

const CodaTimelineSegmentDriverScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_segment_driver.gd"
)

var _runtime: CodaRuntime = null
var _voice_fader: CodaVoiceFader = null
var _segment_driver: CodaTimelineSegmentDriver = null
var _policy: CodaMusicTransitionPolicy = null
var _marker_reached: Callable = Callable()


func setup(
	runtime: CodaRuntime,
	voice_fader: CodaVoiceFader,
	segment_driver: CodaTimelineSegmentDriver,
	policy: CodaMusicTransitionPolicy,
	marker_reached_cb: Callable
) -> void:
	_runtime = runtime
	_voice_fader = voice_fader
	_segment_driver = segment_driver
	_policy = policy if policy != null else CodaMusicTransitionPolicy.default_policy()
	_marker_reached = marker_reached_cb


func segment_crossfade_ms() -> int:
	if _policy != null:
		return _policy.segment_crossfade_ms
	return 500


func notify_music_state_changed(
	handle: CodaEventHandle, dispatchers: Dictionary, find_param: Callable
) -> void:
	if handle == null or not handle.is_timeline or not dispatchers.has(handle):
		return
	var d: Dictionary = dispatchers[handle]
	var timeline = d.get("timeline", null)
	if timeline == null:
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	var segment_id: String = ""
	for pname in handle.param_values.keys():
		var pdef: CodaEventParameter = find_param.call(event, str(pname)) as CodaEventParameter
		var pname_str: String = str(pname)
		if pdef != null:
			pname_str = pdef.param_name
		if not CodaTimelineSegmentDriverScript.should_drive_param(pname_str, event):
			continue
		segment_id = CodaTimelineSegmentDriverScript.resolve_segment_id(
			timeline, pname_str, handle.param_values[pname]
		)
		if not segment_id.is_empty():
			break
	if segment_id.is_empty():
		return
	_segment_driver.apply_segment_change(
		_runtime, handle, d, segment_id, segment_crossfade_ms()
	)


func check_markers_crossed(
	handle: CodaEventHandle,
	timeline,
	prev_cursor: float,
	next_cursor: float,
	dispatchers: Dictionary
) -> void:
	if timeline == null or timeline.markers.is_empty():
		return
	var fired_markers: Dictionary = {}
	if dispatchers.has(handle):
		var d0: Dictionary = dispatchers[handle]
		var raw: Variant = d0.get("fired_marker_ids", {})
		if raw is Dictionary:
			fired_markers = raw as Dictionary
	for m in timeline.markers:
		if m.time_seconds <= prev_cursor or m.time_seconds > next_cursor:
			continue
		if fired_markers.has(m.id):
			continue
		fired_markers[m.id] = true
		if _marker_reached.is_valid():
			_marker_reached.call(handle, m.id)
		if (
			m.kind == CodaTimelineMarker.Kind.TRANSITION
			and not m.target_segment_id.is_empty()
			and dispatchers.has(handle)
		):
			var d: Dictionary = dispatchers[handle]
			_segment_driver.apply_segment_change(
				_runtime, handle, d, m.target_segment_id, segment_crossfade_ms()
			)
	if dispatchers.has(handle):
		(dispatchers[handle] as Dictionary)["fired_marker_ids"] = fired_markers


func spawn_segment_voice(
	handle: CodaEventHandle,
	d: Dictionary,
	entry: Dictionary,
	spawn_voice: Callable,
	crossfade_ms: int = -1
) -> bool:
	var ms: int = crossfade_ms if crossfade_ms >= 0 else segment_crossfade_ms()
	if not spawn_voice.call(handle, d, entry):
		return false
	var clip_id: String = String(entry.get("sound_id", ""))
	var voices: Dictionary = d.get("voices", {})
	var p: AudioStreamPlayer = voices.get(clip_id, null) as AudioStreamPlayer
	if p != null and ms > 0 and _voice_fader != null:
		var target_db: float = p.volume_db
		p.volume_db = -80.0
		_voice_fader.fade_volume_db(p, target_db, ms)
	return true


func fade_out_voice(
	player: AudioStreamPlayer, fade_ms: int, on_complete: Callable = Callable()
) -> void:
	if player == null or not is_instance_valid(player):
		if on_complete.is_valid():
			on_complete.call()
		return
	if _voice_fader != null:
		_voice_fader.fade_volume_db(player, -80.0, fade_ms, on_complete)


func apply_music_fade_in(handle: CodaEventHandle, player: AudioStreamPlayer) -> void:
	if player == null or _voice_fader == null:
		return
	var fade_in_ms: int = int(handle.params.get("_coda_music_fade_in_ms", 0))
	if fade_in_ms <= 0:
		return
	var target_db: float = player.volume_db
	player.volume_db = -80.0
	_voice_fader.fade_volume_db(player, target_db, fade_in_ms)


func should_notify_for_param(event: CodaBrowserNode, name_or_id: String, find_param: Callable) -> bool:
	if event == null:
		return CodaTimelineSegmentDriverScript.should_drive_param(name_or_id, null)
	var param_id: String = ""
	for p in event.event_parameters:
		if p.id == name_or_id or String(p.param_name).to_lower() == name_or_id.to_lower():
			return CodaTimelineSegmentDriverScript.should_drive_param(p.param_name, event)
	return CodaTimelineSegmentDriverScript.should_drive_param(name_or_id, event)
