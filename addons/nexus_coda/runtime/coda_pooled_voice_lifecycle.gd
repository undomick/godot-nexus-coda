@tool
class_name CodaPooledVoiceLifecycle
extends RefCounted

## Playback-generation guards for pooled [AudioStreamPlayer]s shared by graph and timeline paths.


static func detach_player_from_timeline_dispatchers(
	player: AudioStreamPlayer,
	dispatchers: Dictionary,
	voice_owner: Dictionary,
	voice_playback_gen: Dictionary,
	clear_meta: Callable,
	free_fx_bus: Callable
) -> void:
	if player == null or not is_instance_valid(player):
		return
	var key: int = player.get_instance_id()
	voice_owner.erase(key)
	voice_playback_gen.erase(key)
	if clear_meta.is_valid():
		clear_meta.call(player)
	if free_fx_bus.is_valid():
		free_fx_bus.call(player)
	for h in dispatchers.keys():
		var d: Dictionary = dispatchers[h]
		var voices: Dictionary = d.get("voices", {})
		if voices.is_empty():
			continue
		var stale_clip_ids: Array = []
		for clip_id in voices.keys():
			if voices[clip_id] == player:
				stale_clip_ids.append(clip_id)
		if stale_clip_ids.is_empty():
			continue
		for clip_id in stale_clip_ids:
			voices.erase(clip_id)
		d["voices"] = voices


static func begin_player_voice(
	player: AudioStreamPlayer,
	dispatchers: Dictionary,
	voice_owner: Dictionary,
	voice_playback_gen: Dictionary,
	active_handles: Dictionary,
	pending_finish_gen: Dictionary,
	orphaned_finish_gens: Dictionary,
	next_gen: int,
	clear_meta: Callable,
	free_fx_bus: Callable
) -> int:
	detach_player_from_timeline_dispatchers(
		player, dispatchers, voice_owner, voice_playback_gen, clear_meta, free_fx_bus
	)
	var key: int = player.get_instance_id()
	var prior_gen: int = int(player.get_meta(&"_coda_playback_gen", -1))
	if prior_gen >= 0:
		orphaned_finish_gens[prior_gen] = true
	var gen: int = next_gen
	player.set_meta(&"_coda_playback_gen", gen)
	pending_finish_gen[key] = gen
	active_handles.erase(key)
	return gen


static func is_stale_finish(
	player: AudioStreamPlayer,
	pending_finish_gen: Dictionary,
	orphaned_finish_gens: Dictionary
) -> bool:
	var key: int = player.get_instance_id()
	var gen: int = int(player.get_meta(&"_coda_playback_gen", -1))
	if gen < 0:
		return true
	if orphaned_finish_gens.erase(gen):
		return true
	return int(pending_finish_gen.get(key, -1)) != gen


static func orphan_pending_finish(
	player: AudioStreamPlayer,
	pending_finish_gen: Dictionary,
	orphaned_finish_gens: Dictionary
) -> void:
	var key: int = player.get_instance_id()
	var gen: int = int(player.get_meta(&"_coda_playback_gen", -1))
	if gen >= 0:
		pending_finish_gen[key] = gen
		orphaned_finish_gens.erase(gen)
