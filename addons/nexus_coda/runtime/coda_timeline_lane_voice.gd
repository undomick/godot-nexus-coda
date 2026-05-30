@tool
class_name CodaTimelineLaneVoice
extends RefCounted

const CodaFxBusHelperScript := preload("res://addons/nexus_coda/runtime/coda_fx_bus_helper.gd")
const CodaEffectCatalogScript := preload(
	"res://addons/nexus_coda/domain/effects/coda_effect_catalog.gd"
)
const CodaAudioStreamCacheScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_stream_cache.gd"
)


var _runtime: CodaRuntime = null
var _timeline_music: CodaTimelineMusicController = null


func setup(runtime: CodaRuntime, timeline_music: CodaTimelineMusicController) -> void:
	_runtime = runtime
	_timeline_music = timeline_music


func spawn_lane_voice(handle: CodaEventHandle, d: Dictionary, entry: Dictionary) -> bool:
	var stream_path: String = String(entry.get("audio_path", "")).strip_edges()
	if stream_path.is_empty():
		return false
	if not ResourceLoader.exists(stream_path):
		_runtime.runtime_warn("timeline clip audio missing: '%s'" % stream_path)
		return false
	var stream: AudioStream = CodaAudioStreamCacheScript.load_stream(stream_path)
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
			var tail_s: float = CodaEffectCatalogScript.estimate_chain_tail_seconds(fx_chain)
			if tail_s > 0.0:
				player.set_meta(&"_coda_fx_tail_seconds", tail_s)
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
	var voices: Dictionary = d.get("voices", {})
	for k in voices.keys():
		var p: AudioStreamPlayer = voices[k] as AudioStreamPlayer
		_teardown_immediate(p, true)
	d["voices"] = {}
	if handle != null:
		handle.clear_player_binding()


func stop_voices_dry(d: Dictionary, handle: CodaEventHandle = null) -> void:
	var voices: Dictionary = d.get("voices", {})
	for k in voices.keys():
		var p: AudioStreamPlayer = voices[k] as AudioStreamPlayer
		_stop_dry_at_clip_end(p)
	d["voices"] = {}
	if handle != null:
		handle.clear_player_binding()


func stop_voices_past_clip_end(
	d: Dictionary, handle: CodaEventHandle, cursor_seconds: float
) -> void:
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
		_stop_dry_at_clip_end(p)
		stale_keys.append(sound_key)
	for k in stale_keys:
		voices.erase(k)
	d["voices"] = voices
	if stale_keys.size() > 0 and handle != null:
		handle.clear_player_binding()


func retire_lane_voice(d: Dictionary, clip_id: String) -> void:
	if clip_id.is_empty():
		return
	var voices: Dictionary = d.get("voices", {})
	if not voices.has(clip_id):
		return
	var p: AudioStreamPlayer = voices[clip_id] as AudioStreamPlayer
	voices.erase(clip_id)
	d["voices"] = voices
	_teardown_immediate(p, true)


func finalize_lane_voice(
	player: AudioStreamPlayer,
	key: int,
	h: CodaEventHandle,
	d: Dictionary,
	finished_clip_id: String,
) -> void:
	_release_fx_bus_with_tail(player)
	_runtime.get_timeline_voice_owner().erase(key)
	_runtime.get_timeline_voice_playback_gen().erase(key)
	var voices: Dictionary = d.get("voices", {})
	if voices.get(finished_clip_id, null) == player:
		voices.erase(finished_clip_id)
		d["voices"] = voices
	clear_voice_player_meta(player)


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
	if player.has_meta(&"_coda_fx_tail_seconds"):
		player.remove_meta(&"_coda_fx_tail_seconds")
	CodaFxBusHelperScript.cancel_pending_destroy(nm)
	CodaFxBusHelperScript.destroy_if_ours(nm)


func _stop_dry_at_clip_end(p: AudioStreamPlayer) -> void:
	if p == null or not is_instance_valid(p):
		return
	var pk: int = p.get_instance_id()
	_runtime.get_timeline_voice_owner().erase(pk)
	_runtime.get_timeline_voice_playback_gen().erase(pk)
	var fx_nm: String = ""
	var tail_s: float = 0.0
	if p.has_meta(&"_coda_fx_bus"):
		fx_nm = String(p.get_meta(&"_coda_fx_bus", ""))
		tail_s = float(p.get_meta(&"_coda_fx_tail_seconds", 0.0))
	if tail_s > 0.0 and not fx_nm.is_empty():
		CodaFxBusHelperScript.mute_dry_on_bus(fx_nm)
	if p.playing:
		p.stop()
	clear_voice_player_meta(p)
	_release_fx_bus_with_tail(p)


func _teardown_immediate(p: AudioStreamPlayer, stop_if_playing: bool) -> void:
	if p == null or not is_instance_valid(p):
		return
	var pk: int = p.get_instance_id()
	_runtime.get_timeline_voice_owner().erase(pk)
	_runtime.get_timeline_voice_playback_gen().erase(pk)
	if stop_if_playing and p.playing:
		p.stop()
	clear_voice_player_meta(p)
	free_player_fx_bus(p)


func _release_fx_bus_with_tail(p: AudioStreamPlayer) -> void:
	if p == null or not is_instance_valid(p):
		return
	if not p.has_meta(&"_coda_fx_bus"):
		return
	var nm: String = String(p.get_meta(&"_coda_fx_bus", ""))
	var tail_s: float = float(p.get_meta(&"_coda_fx_tail_seconds", 0.0))
	p.remove_meta(&"_coda_fx_bus")
	if p.has_meta(&"_coda_fx_tail_seconds"):
		p.remove_meta(&"_coda_fx_tail_seconds")
	if tail_s > 0.0 and _runtime != null:
		CodaFxBusHelperScript.schedule_destroy_after_tail(nm, tail_s, _runtime)
	else:
		CodaFxBusHelperScript.destroy_if_ours(nm)


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
