@tool
class_name CodaTimelineDispatcher
extends RefCounted

const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaRuntimeTimelineLayoutScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_timeline_layout.gd"
)
const CodaTimelineSegmentDriverScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_segment_driver.gd"
)
const CodaTimelineLaneVoiceScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_lane_voice.gd"
)
const CodaTimelineClipDispatchScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_clip_dispatch.gd"
)

var _runtime: CodaRuntime = null
var _voice_fader: CodaVoiceFader = null
var _timeline_music: CodaTimelineMusicController = null
var _lane_voice: CodaTimelineLaneVoice
var _clip_dispatch: CodaTimelineClipDispatch


func setup(
	runtime: CodaRuntime,
	voice_fader: CodaVoiceFader,
	timeline_music: CodaTimelineMusicController
) -> void:
	_runtime = runtime
	_voice_fader = voice_fader
	_timeline_music = timeline_music
	_lane_voice = CodaTimelineLaneVoiceScript.new()
	_lane_voice.setup(runtime, timeline_music)
	_clip_dispatch = CodaTimelineClipDispatchScript.new()
	_clip_dispatch.setup(runtime, _lane_voice)


func start_timeline_event(
	event: CodaBrowserNode, path: String, params: Dictionary, source_bank_id: String = ""
) -> CodaEventHandle:
	var prior: CodaEventHandle = active_handle_for_event(event.id)
	if prior != null:
		finalize_handle(prior)
	var timeline: CodaEventTimeline = event.event_timeline
	if timeline == null:
		_runtime.runtime_warn("event '%s' is in timeline mode but has no timeline data" % event.name)
		return null
	var live_params: Dictionary = _runtime.get_parameter_pipeline().build_param_values(event, params)
	params = params.duplicate()
	params["_coda_voice_bus"] = _runtime.resolve_bus_name_for_event(event)

	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.id = _runtime.runtime_allocate_handle_id()
	handle.event_path = path
	handle.event_node = event
	handle.source_bank_id = source_bank_id
	handle.params = params.duplicate()
	handle.param_values = live_params
	handle.param_values_smoothed = live_params.duplicate()
	handle.loop = bool(params.get("loop", false))
	handle._bus_name = _runtime.bus_name
	handle.is_timeline = true
	handle.timeline_length_seconds = timeline.length_seconds
	var start_sec: float = float(params.get("timeline_cursor_start", 0.0))
	handle.timeline_cursor_seconds = clampf(start_sec, 0.0, timeline.length_seconds)
	var loop_override_start: float = -1.0
	var loop_override_end: float = -1.0
	var loop_region: Variant = params.get("_coda_loop_region", null)
	if loop_region is Array and (loop_region as Array).size() == 2:
		loop_override_start = float((loop_region as Array)[0])
		loop_override_end = float((loop_region as Array)[1])

	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	dispatchers[handle] = {
		"timeline": timeline,
		"voices": {},
		"fired_clip_ids": {},
		"fired_marker_ids": {},
		"spent_clip_ids": {},
		"layout_sig": CodaRuntimeTimelineLayoutScript.layout_signature(timeline),
		"live_params": live_params,
		"loop_override_start": loop_override_start,
		"loop_override_end": loop_override_end,
	}
	handle.timeline_runtime = _runtime
	var dispatch_entry: Dictionary = dispatchers[handle]
	_clip_dispatch.prime_overlapping_voices(handle, dispatch_entry, timeline, handle.timeline_cursor_seconds)
	_sync_segment_voice_after_prime(handle, dispatch_entry, timeline)
	_runtime.runtime_emit_voice_started(handle)
	return handle


func tick_dispatchers(delta: float) -> void:
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	var handles: Array = dispatchers.keys()
	for h in handles:
		var handle: CodaEventHandle = h as CodaEventHandle
		if handle == null:
			dispatchers.erase(h)
			continue
		if not handle._alive:
			finalize_handle(handle)
			continue
		var d: Dictionary = dispatchers[handle]
		var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
		if timeline == null:
			finalize_handle(handle)
			continue

		_runtime.get_parameter_pipeline().advance_smoothing(handle, delta)

		if handle.timeline_pending_seek_seconds >= 0.0:
			var seek_target: float = handle.timeline_pending_seek_seconds
			handle.timeline_pending_seek_seconds = -1.0
			if handle._paused:
				_apply_seek_cursor_only(handle, d, seek_target)
			else:
				_apply_seek(handle, d, seek_target)

		_clip_dispatch.refresh_voice_output_levels(handle, d, timeline)

		if handle._paused:
			continue

		var prev_cursor: float = handle.timeline_cursor_seconds
		var next_cursor: float = prev_cursor + delta

		var loop_start: float = float(d.get("loop_override_start", -1.0))
		var loop_end: float = float(d.get("loop_override_end", -1.0))
		if loop_start < 0.0 or loop_end <= loop_start:
			if timeline.loop_enabled and timeline.loop_end_seconds > timeline.loop_start_seconds:
				loop_start = timeline.loop_start_seconds
				loop_end = timeline.loop_end_seconds
			else:
				loop_start = -1.0
				loop_end = -1.0

		var wrapped: bool = false
		if loop_end > 0.0:
			while next_cursor >= loop_end:
				next_cursor = loop_start + (next_cursor - loop_end)
				wrapped = true
		elif next_cursor >= timeline.length_seconds:
			if handle.loop:
				while next_cursor >= timeline.length_seconds and timeline.length_seconds > 0.0:
					next_cursor -= timeline.length_seconds
				wrapped = true
			else:
				_clip_dispatch.fire_clips_in_range(
					handle, d, timeline, prev_cursor, timeline.length_seconds
				)
				handle.timeline_cursor_seconds = timeline.length_seconds
				finalize_handle(handle)
				continue

		if wrapped:
			d["fired_marker_ids"] = {}
			var wrap_target: float = loop_end if loop_end > 0.0 else timeline.length_seconds
			var cursor_at_frame_start: float = prev_cursor
			var backward_landing: bool = next_cursor < cursor_at_frame_start
			# Markers between pre-wrap cursor and loop end are skipped if we only scan after wrap.
			if _timeline_music != null:
				_timeline_music.check_markers_crossed(
					handle, timeline, cursor_at_frame_start, wrap_target, dispatchers
				)
			_clip_dispatch.fire_clips_in_range(handle, d, timeline, cursor_at_frame_start, wrap_target)
			d["spent_clip_ids"] = {}
			_lane_voice.stop_voices(d, handle)
			var loop_lo: float = loop_start if loop_start >= 0.0 else 0.0
			if backward_landing:
				d["fired_clip_ids"] = {}
				_clip_dispatch.fire_clips_in_range(
					handle, d, timeline, next_cursor, cursor_at_frame_start
				)
			_clip_dispatch.prime_overlapping_voices(handle, d, timeline, next_cursor)
			_sync_segment_voice_after_prime(handle, d, timeline)
			prev_cursor = loop_lo if backward_landing else cursor_at_frame_start

		handle.timeline_cursor_seconds = next_cursor
		if _timeline_music != null:
			_timeline_music.check_markers_crossed(
				handle, timeline, prev_cursor, next_cursor, dispatchers
			)
		_lane_voice.stop_voices_past_clip_end(d, handle, next_cursor)
		_clip_dispatch.heal_orphaned_fired_clips(handle, d, timeline, next_cursor)
		_clip_dispatch.fire_clips_in_range(handle, d, timeline, prev_cursor, next_cursor)


func active_handle_for_event(event_id: String) -> CodaEventHandle:
	if event_id.is_empty():
		return null
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	for h in dispatchers.keys():
		var handle: CodaEventHandle = h as CodaEventHandle
		if handle == null or not handle._alive:
			continue
		var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
		if event == null:
			continue
		if event.id == event_id:
			return handle
	return null


func finalize_handle(handle: CodaEventHandle, fade_ms: int = 0) -> void:
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if not dispatchers.has(handle):
		return
	var was_alive: bool = handle._alive
	var d: Dictionary = dispatchers[handle]
	if fade_ms > 0:
		# Keep dispatcher entry during fade; do not advance cursor or fire new clips.
		handle._paused = true
		var voices: Dictionary = d.get("voices", {})
		var playing_count: int = 0
		for p in voices.values():
			var pl: AudioStreamPlayer = p as AudioStreamPlayer
			if pl != null and is_instance_valid(pl) and pl.playing:
				playing_count += 1
		if playing_count > 0:
			var remaining: Array[int] = [playing_count]
			var finish := func() -> void:
				_finish_teardown(handle, was_alive)
			var on_done := func() -> void:
				remaining[0] -= 1
				if remaining[0] <= 0:
					finish.call()
			for p in voices.values():
				var pl2: AudioStreamPlayer = p as AudioStreamPlayer
				if pl2 != null and is_instance_valid(pl2) and pl2.playing:
					_voice_fader.fade_volume_db(pl2, -80.0, fade_ms, on_done)
			return
	_finish_teardown(handle, was_alive)


func resync_preview_for_event(event_id: String) -> void:
	if event_id.is_empty():
		return
	var handle: CodaEventHandle = active_handle_for_event(event_id)
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if handle == null or not dispatchers.has(handle) or handle._paused:
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null or event.event_timeline == null:
		return
	var timeline: CodaEventTimeline = event.event_timeline
	var d: Dictionary = dispatchers[handle]
	d["timeline"] = timeline
	handle.timeline_length_seconds = timeline.length_seconds
	_apply_work_area_loop_override(d, timeline)
	var sig: String = CodaRuntimeTimelineLayoutScript.layout_signature(timeline)
	if String(d.get("layout_sig", "")) == sig:
		return
	d["layout_sig"] = sig
	CodaTimelineClipDispatchScript.reset_bookkeeping(d)
	_lane_voice.stop_voices(d, handle)
	_clip_dispatch.prime_overlapping_voices(handle, d, timeline, handle.timeline_cursor_seconds)
	_sync_segment_voice_after_prime(handle, d, timeline)


func pause_preview(handle: CodaEventHandle) -> void:
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if handle == null or not dispatchers.has(handle):
		return
	handle._paused = true
	var d: Dictionary = dispatchers[handle]
	_lane_voice.stop_voices(d, handle)
	CodaTimelineClipDispatchScript.reset_bookkeeping(d)


func resume_preview(handle: CodaEventHandle) -> void:
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if handle == null or not dispatchers.has(handle):
		return
	var d: Dictionary = dispatchers[handle]
	var voices: Dictionary = d.get("voices", {})
	if voices.is_empty():
		var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
		if timeline == null:
			handle._paused = false
			return
		handle._paused = false
		CodaTimelineClipDispatchScript.reset_bookkeeping(d)
		_clip_dispatch.prime_overlapping_voices(handle, d, timeline, handle.timeline_cursor_seconds)
		_sync_segment_voice_after_prime(handle, d, timeline)
		return
	handle._paused = false
	for p in voices.values():
		var pl: AudioStreamPlayer = p as AudioStreamPlayer
		if pl != null and is_instance_valid(pl):
			pl.stream_paused = false


func on_voice_finished(player: AudioStreamPlayer, key: int) -> void:
	# Stop/seek/wrap clears owner before pool reuse; ignore stale finished signals.
	var voice_owner: Dictionary = _runtime.get_timeline_voice_owner()
	var h: CodaEventHandle = voice_owner.get(key, null) as CodaEventHandle
	if h == null:
		return
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if not dispatchers.has(h):
		return
	var d: Dictionary = dispatchers[h]
	var voices: Dictionary = d.get("voices", {})
	var finished_clip_id: String = ""
	for k in voices.keys():
		if voices[k] == player:
			finished_clip_id = str(k)
			break
	if finished_clip_id.is_empty():
		return
	var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
	if timeline == null:
		return
	var info: Dictionary = timeline.find_clip(finished_clip_id)
	var cl: CodaTimelineClip = info.get("clip", null) as CodaTimelineClip
	if cl == null:
		return
	var clip_end: float = cl.start_seconds + cl.duration_seconds
	if h.timeline_cursor_seconds >= clip_end - 0.001:
		_lane_voice.finalize_lane_voice(player, key, h, d, finished_clip_id)
		return
	if player.has_meta(&"_coda_timeline_restart_offset"):
		var restart_at: float = maxf(0.0, float(player.get_meta(&"_coda_timeline_restart_offset", 0.0)))
		var gen: int = int(player.get_meta(&"_coda_playback_gen", -1))
		if gen >= 0:
			_runtime.get_player_pending_finish_gen()[key] = gen
		player.play(restart_at)
		return
	_lane_voice.finalize_lane_voice(player, key, h, d, finished_clip_id)
	var spent: Dictionary = d.get("spent_clip_ids", {})
	spent[finished_clip_id] = true
	d["spent_clip_ids"] = spent


func spawn_lane_voice(handle: CodaEventHandle, d: Dictionary, entry: Dictionary) -> bool:
	return _lane_voice.spawn_lane_voice(handle, d, entry)


func stop_voices(d: Dictionary, handle: CodaEventHandle = null) -> void:
	_lane_voice.stop_voices(d, handle)


func stop_voices_past_clip_end(
	d: Dictionary, handle: CodaEventHandle, cursor_seconds: float
) -> void:
	_lane_voice.stop_voices_past_clip_end(d, handle, cursor_seconds)


func retire_lane_voice(d: Dictionary, clip_id: String) -> void:
	_lane_voice.retire_lane_voice(d, clip_id)


func clear_voice_player_meta(player: AudioStreamPlayer) -> void:
	_lane_voice.clear_voice_player_meta(player)


func free_player_fx_bus(player: AudioStreamPlayer) -> void:
	_lane_voice.free_player_fx_bus(player)


func _finish_teardown(handle: CodaEventHandle, was_alive: bool) -> void:
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if not dispatchers.has(handle):
		return
	var d: Dictionary = dispatchers[handle]
	_lane_voice.stop_voices(d, handle)
	handle.timeline_runtime = null
	dispatchers.erase(handle)
	if was_alive:
		handle._alive = false
		handle.finished.emit()
	_runtime.runtime_emit_voice_finished(handle)


func _apply_seek_cursor_only(
	handle: CodaEventHandle, d: Dictionary, target_seconds: float
) -> void:
	var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
	if timeline == null:
		return
	handle.timeline_cursor_seconds = clampf(target_seconds, 0.0, timeline.length_seconds)


func _apply_seek(handle: CodaEventHandle, d: Dictionary, target_seconds: float) -> void:
	var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
	if timeline == null:
		return
	var clamped: float = clampf(target_seconds, 0.0, timeline.length_seconds)
	handle.timeline_cursor_seconds = clamped
	_lane_voice.stop_voices(d, handle)
	CodaTimelineClipDispatchScript.reset_bookkeeping(d)
	_clip_dispatch.prime_overlapping_voices(handle, d, timeline, clamped)
	_sync_segment_voice_after_prime(handle, d, timeline)


func _sync_segment_voice_after_prime(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline
) -> void:
	if _runtime == null or handle == null or timeline == null:
		return
	if CodaTimelineSegmentDriverScript.segments_track(timeline) == null:
		return
	# Segment lanes follow music-state params, not cursor overlap.
	_runtime.notify_music_state_changed(handle)


static func _apply_work_area_loop_override(d: Dictionary, timeline: CodaEventTimeline) -> void:
	if timeline.has_work_area():
		d["loop_override_start"] = timeline.work_area_start()
		d["loop_override_end"] = timeline.work_area_end()
	else:
		d["loop_override_start"] = -1.0
		d["loop_override_end"] = -1.0
