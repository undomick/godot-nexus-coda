@tool
class_name CodaTimelineDispatcher
extends RefCounted

const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaRuntimeTimelineLayoutScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_timeline_layout.gd"
)
const CodaVoiceFaderScript := preload("res://addons/nexus_coda/runtime/coda_voice_fader.gd")
const CodaFxBusHelperScript := preload("res://addons/nexus_coda/runtime/coda_fx_bus_helper.gd")
const CodaPooledVoiceLifecycleScript := preload(
	"res://addons/nexus_coda/runtime/coda_pooled_voice_lifecycle.gd"
)
const CodaTimelineSegmentDriverScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_segment_driver.gd"
)

var _runtime: CodaRuntime = null
var _voice_fader: CodaVoiceFader = null
var _timeline_music: CodaTimelineMusicController = null


func setup(
	runtime: CodaRuntime,
	voice_fader: CodaVoiceFader,
	timeline_music: CodaTimelineMusicController
) -> void:
	_runtime = runtime
	_voice_fader = voice_fader
	_timeline_music = timeline_music


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
	var loop_region: Variant = params.get("_coda_loop_region", null)
	var loop_override_start: float = -1.0
	var loop_override_end: float = -1.0
	if loop_region is Array and (loop_region as Array).size() == 2:
		loop_override_start = float((loop_region as Array)[0])
		loop_override_end = float((loop_region as Array)[1])

	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	dispatchers[handle] = {
		"timeline": timeline,
		"voices": {},
		"fired_clip_ids": {},
		"spent_clip_ids": {},
		"layout_sig": CodaRuntimeTimelineLayoutScript.layout_signature(timeline),
		"live_params": live_params,
		"loop_override_start": loop_override_start,
		"loop_override_end": loop_override_end,
	}
	handle.timeline_runtime = _runtime
	_prime_overlapping_voices(handle, dispatchers[handle], timeline, handle.timeline_cursor_seconds)
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
			_apply_seek(handle, d, handle.timeline_pending_seek_seconds)
			handle.timeline_pending_seek_seconds = -1.0

		_refresh_voice_output_levels(handle, d, timeline)

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
				_fire_clips_in_range(handle, d, timeline, prev_cursor, timeline.length_seconds)
				handle.timeline_cursor_seconds = timeline.length_seconds
				finalize_handle(handle)
				continue

		if wrapped:
			var wrap_target: float = loop_end if loop_end > 0.0 else timeline.length_seconds
			var cursor_at_frame_start: float = prev_cursor
			# Markers between the pre-wrap cursor and loop end are skipped if we only
			# check [loop_lo, next_cursor] after the wrap.
			if _timeline_music != null:
				_timeline_music.check_markers_crossed(
					handle, timeline, cursor_at_frame_start, wrap_target, dispatchers
				)
			_fire_clips_in_range(handle, d, timeline, cursor_at_frame_start, wrap_target)
			d["fired_clip_ids"] = {}
			d["spent_clip_ids"] = {}
			stop_voices(d, handle)
			var loop_lo: float = loop_start if loop_start >= 0.0 else 0.0
			if next_cursor < cursor_at_frame_start:
				_fire_clips_in_range(handle, d, timeline, next_cursor, cursor_at_frame_start)
			_prime_overlapping_voices(handle, d, timeline, next_cursor)
			prev_cursor = loop_lo

		handle.timeline_cursor_seconds = next_cursor
		if _timeline_music != null:
			_timeline_music.check_markers_crossed(
				handle, timeline, prev_cursor, next_cursor, dispatchers
			)
		stop_voices_past_clip_end(d, handle, next_cursor)
		_heal_orphaned_fired_clips(handle, d, timeline, next_cursor)
		_fire_clips_in_range(handle, d, timeline, prev_cursor, next_cursor)


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
		# Keep the dispatcher entry until fades finish, but do not advance the cursor or
		# fire new clips while outgoing music is crossfading away.
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
				else:
					on_done.call()
			return
	_finish_teardown(handle, was_alive)


func resync_preview_for_event(event_id: String) -> void:
	if event_id.is_empty():
		return
	var handle: CodaEventHandle = active_handle_for_event(event_id)
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if handle == null or not dispatchers.has(handle):
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null or event.event_timeline == null:
		return
	var timeline: CodaEventTimeline = event.event_timeline
	var d: Dictionary = dispatchers[handle]
	d["timeline"] = timeline
	handle.timeline_length_seconds = timeline.length_seconds
	var sig: String = CodaRuntimeTimelineLayoutScript.layout_signature(timeline)
	if String(d.get("layout_sig", "")) == sig:
		return
	d["layout_sig"] = sig
	d["fired_clip_ids"] = {}
	d["spent_clip_ids"] = {}
	stop_voices(d, handle)
	_prime_overlapping_voices(handle, d, timeline, handle.timeline_cursor_seconds)


func pause_preview(handle: CodaEventHandle) -> void:
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if handle == null or not dispatchers.has(handle):
		return
	handle._paused = true
	var d: Dictionary = dispatchers[handle]
	stop_voices(d, handle)
	d["fired_clip_ids"] = {}
	d["spent_clip_ids"] = {}


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
		d["fired_clip_ids"] = {}
		d["spent_clip_ids"] = {}
		_prime_overlapping_voices(handle, d, timeline, handle.timeline_cursor_seconds)
		return
	handle._paused = false
	for p in voices.values():
		var pl: AudioStreamPlayer = p as AudioStreamPlayer
		if pl != null and is_instance_valid(pl):
			pl.stream_paused = false


func on_voice_finished(player: AudioStreamPlayer, key: int) -> void:
	# Stop/seek/loop-wrap clears owner + FX before the pool reuses this player. A late
	# finished signal must not tear down a new lane's FX bus.
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
		_finalize_lane_voice(player, key, h, d, finished_clip_id)
		return
	if player.has_meta(&"_coda_timeline_restart_offset"):
		var restart_at: float = maxf(0.0, float(player.get_meta(&"_coda_timeline_restart_offset", 0.0)))
		var gen: int = int(player.get_meta(&"_coda_playback_gen", -1))
		if gen >= 0:
			_runtime.get_player_pending_finish_gen()[key] = gen
		player.play(restart_at)
		return
	_finalize_lane_voice(player, key, h, d, finished_clip_id)
	var spent: Dictionary = d.get("spent_clip_ids", {})
	spent[finished_clip_id] = true
	d["spent_clip_ids"] = spent


func spawn_lane_voice(handle: CodaEventHandle, d: Dictionary, entry: Dictionary) -> bool:
	var stream_path: String = String(entry.get("audio_path", "")).strip_edges()
	if stream_path.is_empty():
		return false
	if not ResourceLoader.exists(stream_path):
		_runtime.runtime_warn("timeline clip audio missing: '%s'" % stream_path)
		return false
	var stream: AudioStream = load(stream_path) as AudioStream
	if stream == null:
		return false
	var stream_offset: float = maxf(0.0, float(entry.get("stream_offset_seconds", 0.0)))
	var play_duration: float = float(entry.get("duration_seconds", 0.0))
	var asset_len: float = stream.get_length()
	var needs_source_extend: bool = (
		play_duration > 0.0
		and asset_len > 0.0
		and stream_offset + play_duration > asset_len + 0.001
	)
	var use_stream_loop_extend: bool = needs_source_extend and stream_offset <= 0.001
	if use_stream_loop_extend:
		stream = stream.duplicate()
		stream.loop = true
	var clip_id: String = String(entry.get("sound_id", ""))
	retire_lane_voice(d, clip_id)
	var player: AudioStreamPlayer = _runtime.runtime_pool().acquire()
	if player == null:
		_runtime.runtime_report_pool_exhausted({
			"mode": "timeline",
			"path": stream_path,
			"active": _runtime.active_voice_count(),
			"pool_size": _runtime.runtime_pool_size(),
			"detail": "voice pool exhausted while playing timeline clip '%s'" % stream_path,
		})
		return false
	clear_voice_player_meta(player)
	free_player_fx_bus(player)
	var voice_gen: int = _runtime.runtime_begin_player_voice(player)
	var send_bus: String = _send_bus_for_track(handle, String(entry.get("track_output_bus_id", "")))
	var route_bus: String = send_bus
	var fx_chain: Array = _collect_fx_chain(entry)
	if fx_chain.size() > 0:
		var fx_nm: String = CodaFxBusHelperScript.create_effects_bus(send_bus, fx_chain)
		if not fx_nm.is_empty():
			route_bus = fx_nm
			player.set_meta(&"_coda_fx_bus", fx_nm)
	player.bus = route_bus
	player.stream = stream
	var override_db: float = float(handle.params.get("volume_db", 0.0))
	player.volume_db = float(entry.get("volume_db", 0.0)) + override_db
	player.pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(
		handle.params.get("pitch_scale", 1.0)
	)
	var clip_end: float = float(entry.get("timeline_clip_end_seconds", -1.0))
	if clip_end > 0.0:
		player.set_meta(&"_coda_clip_timeline_end", clip_end)
	if needs_source_extend and stream_offset > 0.001:
		player.set_meta(&"_coda_timeline_restart_offset", stream_offset)
	player.play(maxf(0.0, float(entry.get("stream_offset_seconds", 0.0))))
	if _timeline_music != null:
		_timeline_music.apply_music_fade_in(handle, player)
	if handle._paused:
		player.stream_paused = true
	var voices: Dictionary = d.get("voices", {})
	voices[entry.get("sound_id", "")] = player
	d["voices"] = voices
	var player_key: int = player.get_instance_id()
	_runtime.get_timeline_voice_owner()[player_key] = handle
	_runtime.get_timeline_voice_playback_gen()[player_key] = voice_gen
	handle._bind_player(player)
	handle.current_sound_id = String(entry.get("sound_id", ""))
	handle.base_volume_db = float(entry.get("volume_db", 0.0))
	handle.base_pitch_scale = float(entry.get("pitch_scale", 1.0))
	return true


func stop_voices(d: Dictionary, handle: CodaEventHandle = null) -> void:
	var voice_owner: Dictionary = _runtime.get_timeline_voice_owner()
	var voice_playback_gen: Dictionary = _runtime.get_timeline_voice_playback_gen()
	var voices: Dictionary = d.get("voices", {})
	for k in voices.keys():
		var p: AudioStreamPlayer = voices[k] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			continue
		var pk: int = p.get_instance_id()
		voice_owner.erase(pk)
		voice_playback_gen.erase(pk)
		if p.playing:
			p.stop()
		clear_voice_player_meta(p)
		free_player_fx_bus(p)
	d["voices"] = {}
	if handle != null:
		handle.clear_player_binding()


func stop_voices_past_clip_end(
	d: Dictionary, handle: CodaEventHandle, cursor_seconds: float
) -> void:
	var voice_owner: Dictionary = _runtime.get_timeline_voice_owner()
	var voice_playback_gen: Dictionary = _runtime.get_timeline_voice_playback_gen()
	var voices: Dictionary = d.get("voices", {})
	if voices.is_empty():
		return
	var stale_keys: Array = []
	for sound_key in voices.keys():
		var p: AudioStreamPlayer = voices[sound_key] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			stale_keys.append(sound_key)
			continue
		if not p.has_meta(&"_coda_clip_timeline_end"):
			continue
		var end_at: float = float(p.get_meta(&"_coda_clip_timeline_end", -1.0))
		if cursor_seconds < end_at:
			continue
		if p.playing:
			p.stop()
		var pk: int = p.get_instance_id()
		voice_owner.erase(pk)
		voice_playback_gen.erase(pk)
		clear_voice_player_meta(p)
		free_player_fx_bus(p)
		stale_keys.append(sound_key)
	for k in stale_keys:
		voices.erase(k)
	d["voices"] = voices
	if stale_keys.size() > 0 and handle != null:
		handle.clear_player_binding()


func retire_lane_voice(d: Dictionary, clip_id: String) -> void:
	if clip_id.is_empty():
		return
	var voice_owner: Dictionary = _runtime.get_timeline_voice_owner()
	var voice_playback_gen: Dictionary = _runtime.get_timeline_voice_playback_gen()
	var voices: Dictionary = d.get("voices", {})
	if not voices.has(clip_id):
		return
	var p: AudioStreamPlayer = voices[clip_id] as AudioStreamPlayer
	voices.erase(clip_id)
	d["voices"] = voices
	if p == null or not is_instance_valid(p):
		return
	var pk: int = p.get_instance_id()
	voice_owner.erase(pk)
	voice_playback_gen.erase(pk)
	if p.playing:
		p.stop()
	clear_voice_player_meta(p)
	free_player_fx_bus(p)


func clear_voice_player_meta(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_meta(&"_coda_timeline_restart_offset"):
		player.remove_meta(&"_coda_timeline_restart_offset")
	if player.has_meta(&"_coda_clip_timeline_end"):
		player.remove_meta(&"_coda_clip_timeline_end")


func free_player_fx_bus(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_meta(&"_coda_fx_bus"):
		return
	var nm: String = String(player.get_meta(&"_coda_fx_bus", ""))
	player.remove_meta(&"_coda_fx_bus")
	CodaFxBusHelperScript.destroy_if_ours(nm)


func _finish_teardown(handle: CodaEventHandle, was_alive: bool) -> void:
	var dispatchers: Dictionary = _runtime.get_timeline_dispatchers()
	if not dispatchers.has(handle):
		return
	var d: Dictionary = dispatchers[handle]
	stop_voices(d, handle)
	handle.timeline_runtime = null
	dispatchers.erase(handle)
	if was_alive:
		handle._alive = false
		handle.finished.emit()
	_runtime.runtime_emit_voice_finished(handle)


func _apply_seek(handle: CodaEventHandle, d: Dictionary, target_seconds: float) -> void:
	var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
	if timeline == null:
		return
	var clamped: float = clampf(target_seconds, 0.0, timeline.length_seconds)
	handle.timeline_cursor_seconds = clamped
	stop_voices(d, handle)
	d["fired_clip_ids"] = {}
	d["spent_clip_ids"] = {}
	_prime_overlapping_voices(handle, d, timeline, clamped)


func _prime_overlapping_voices(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline, at_seconds: float
) -> void:
	var has_solo: bool = false
	for tr in timeline.tracks:
		if tr.solo:
			has_solo = true
			break
	var fired: Dictionary = d.get("fired_clip_ids", {}).duplicate()
	for track in timeline.tracks:
		if track.mute:
			continue
		if has_solo and not track.solo:
			continue
		for clip in track.clips:
			if clip.audio_path.is_empty() or clip.duration_seconds <= 0.0:
				continue
			if fired.has(clip.id):
				continue
			var clip_end: float = clip.start_seconds + clip.duration_seconds
			if at_seconds < clip.start_seconds or at_seconds >= clip_end:
				continue
			var into_clip: float = at_seconds - clip.start_seconds
			var entry: Dictionary = {
				"audio_path": clip.audio_path,
				"volume_db": clip.volume_db + track.volume_db,
				"pitch_scale": clip.pitch_scale,
				"sound_id": clip.id,
				"track_id": track.id,
				"stream_offset_seconds": clip.offset_seconds + into_clip,
				"duration_seconds": clip.duration_seconds - into_clip,
				"timeline_clip_end_seconds": clip_end,
				"clip_effects": clip.effects,
				"track_effects": track.effects,
				"track_output_bus_id": track.output_bus_id,
			}
			if spawn_lane_voice(handle, d, entry):
				fired[clip.id] = true
	d["fired_clip_ids"] = fired


func _heal_orphaned_fired_clips(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline, at_seconds: float
) -> void:
	var fired: Dictionary = d.get("fired_clip_ids", {})
	if fired.is_empty():
		return
	var voices: Dictionary = d.get("voices", {})
	var has_solo: bool = false
	for tr in timeline.tracks:
		if tr.solo:
			has_solo = true
			break
	var healed: bool = false
	for track in timeline.tracks:
		if track.mute:
			continue
		if has_solo and not track.solo:
			continue
		if CodaTimelineSegmentDriverScript.is_segments_track(track):
			continue
		for clip in track.clips:
			if not fired.has(clip.id):
				continue
			var spent: Dictionary = d.get("spent_clip_ids", {})
			if spent.has(clip.id):
				continue
			if voices.has(clip.id):
				continue
			var clip_end: float = clip.start_seconds + clip.duration_seconds
			if at_seconds < clip.start_seconds or at_seconds >= clip_end:
				continue
			fired.erase(clip.id)
			healed = true
	if healed:
		d["fired_clip_ids"] = fired


func _refresh_voice_output_levels(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline
) -> void:
	var voices: Dictionary = d.get("voices", {})
	if voices.is_empty():
		return
	var has_solo: bool = false
	for tr in timeline.tracks:
		if tr.solo:
			has_solo = true
			break
	var override_db: float = float(handle.params.get("volume_db", 0.0))
	for sound_key in voices.keys():
		var p: AudioStreamPlayer = voices[sound_key] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			continue
		var clip_id: String = str(sound_key)
		var info: Dictionary = timeline.find_clip(clip_id)
		if info.is_empty():
			continue
		var tr: CodaTimelineTrack = info.get("track", null) as CodaTimelineTrack
		var cl: CodaTimelineClip = info.get("clip", null) as CodaTimelineClip
		if tr == null or cl == null:
			continue
		if tr.mute or (has_solo and not tr.solo):
			p.volume_db = -80.0
		else:
			var base_db: float = float(cl.volume_db + tr.volume_db) + override_db
			base_db += CodaVoiceFaderScript.clip_fade_db_offset(cl, handle.timeline_cursor_seconds)
			p.volume_db = base_db


func _fire_clips_in_range(
	handle: CodaEventHandle,
	d: Dictionary,
	timeline: CodaEventTimeline,
	from_seconds: float,
	to_seconds: float,
) -> void:
	if to_seconds <= from_seconds:
		return
	var has_solo: bool = false
	for t in timeline.tracks:
		if t.solo:
			has_solo = true
			break
	var fired: Dictionary = d.get("fired_clip_ids", {})
	for track in timeline.tracks:
		if track.mute:
			continue
		if has_solo and not track.solo:
			continue
		if CodaTimelineSegmentDriverScript.is_segments_track(track):
			continue
		for clip in track.clips:
			if clip.audio_path.is_empty() or clip.duration_seconds <= 0.0:
				continue
			if fired.has(clip.id):
				continue
			var spent: Dictionary = d.get("spent_clip_ids", {})
			if spent.has(clip.id):
				continue
			var clip_end: float = clip.start_seconds + clip.duration_seconds
			if clip_end <= from_seconds or clip.start_seconds >= to_seconds:
				continue
			var crosses_start: bool = (
				clip.start_seconds >= from_seconds and clip.start_seconds < to_seconds
			)
			var overlaps_unfired: bool = clip.start_seconds < from_seconds and clip_end > from_seconds
			if not crosses_start and not overlaps_unfired:
				continue
			var into_clip: float = maxf(0.0, from_seconds - clip.start_seconds)
			var entry: Dictionary = {
				"audio_path": clip.audio_path,
				"volume_db": clip.volume_db + track.volume_db,
				"pitch_scale": clip.pitch_scale,
				"sound_id": clip.id,
				"track_id": track.id,
				"stream_offset_seconds": clip.offset_seconds + into_clip,
				"duration_seconds": clip.duration_seconds - into_clip,
				"timeline_clip_end_seconds": clip_end,
				"clip_effects": clip.effects,
				"track_effects": track.effects,
				"track_output_bus_id": track.output_bus_id,
			}
			if spawn_lane_voice(handle, d, entry):
				fired[clip.id] = true
	d["fired_clip_ids"] = fired


func _send_bus_for_track(handle: CodaEventHandle, track_output_bus_id: String) -> String:
	var mapped: String = _runtime.resolve_godot_bus_name_for_coda_bus_id(track_output_bus_id)
	if not mapped.is_empty() and AudioServer.get_bus_index(mapped) >= 0:
		return mapped
	var fallback: String = String(handle.params.get("_coda_voice_bus", _runtime.bus_name))
	if AudioServer.get_bus_index(fallback) < 0:
		fallback = "Master"
	return fallback


func _collect_fx_chain(entry: Dictionary) -> Array:
	var out: Array = []
	for e in entry.get("clip_effects", []) as Array:
		if e is CodaTrackEffect:
			out.append(e)
	for e2 in entry.get("track_effects", []) as Array:
		if e2 is CodaTrackEffect:
			out.append(e2)
	return out


func _finalize_lane_voice(
	player: AudioStreamPlayer,
	key: int,
	h: CodaEventHandle,
	d: Dictionary,
	finished_clip_id: String,
) -> void:
	free_player_fx_bus(player)
	var voice_owner: Dictionary = _runtime.get_timeline_voice_owner()
	var voice_playback_gen: Dictionary = _runtime.get_timeline_voice_playback_gen()
	voice_owner.erase(key)
	voice_playback_gen.erase(key)
	var voices: Dictionary = d.get("voices", {})
	if voices.get(finished_clip_id, null) == player:
		voices.erase(finished_clip_id)
		d["voices"] = voices
	clear_voice_player_meta(player)
