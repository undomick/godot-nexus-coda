extends RefCounted
class_name CodaVoiceWetLayers

## Spawns parallel wet voice layers for return-bus sends.

const CodaBusSendRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_bus_send_runtime.gd")
const CodaFxBusHelperScript := preload("res://addons/nexus_coda/runtime/coda_fx_bus_helper.gd")


static func wet_volume_db_for_layer(
	dry_volume_db: float,
	wet_index: int,
	merged_sends: Array[CodaBusSend],
	bus_root: CodaBus,
	param_values: Dictionary,
	id_to_godot_name: Dictionary = {}
) -> float:
	if wet_index < 0 or bus_root == null:
		return dry_volume_db
	var spawnable: Array[CodaBusSend] = CodaBusSendRuntimeScript.collect_spawnable_wet_sends(
		merged_sends, bus_root, id_to_godot_name
	)
	if wet_index >= spawnable.size():
		return -80.0
	var send: CodaBusSend = spawnable[wet_index]
	var amt: float = CodaBusSendRuntimeScript.effective_level(send, param_values)
	if amt <= 0.001:
		return -80.0
	return dry_volume_db + CodaBusSendRuntimeScript.linear_to_db(amt)


static func merge_sends(
	event_sends: Array[CodaBusSend], track_sends: Array[CodaBusSend]
) -> Array[CodaBusSend]:
	var out: Array[CodaBusSend] = []
	for s in event_sends:
		if s != null:
			out.append(s)
	for s in track_sends:
		if s != null:
			out.append(s)
	return out


static func spawn_wet_layers(
	runtime: CodaRuntime,
	handle: CodaEventHandle,
	dry_player: AudioStreamPlayer,
	d: Dictionary,
	voice_key_prefix: String,
	sends: Array[CodaBusSend],
	param_values: Dictionary
) -> void:
	if runtime == null or dry_player == null or sends.is_empty():
		return
	var bus_root: CodaBus = runtime.get_playback_bus_root()
	if bus_root == null:
		return
	var layers: Array = CodaBusSendRuntimeScript.build_wet_voice_layers(
		sends,
		bus_root,
		_runtime_bus_id_map(runtime),
		param_values,
		dry_player.volume_db
	)
	if layers.is_empty():
		return
	var voices: Dictionary = d.get("voices", {})
	var stream_offset: float = dry_player.get_playback_position() if dry_player.playing else 0.0
	for i in range(layers.size()):
		var layer: Dictionary = layers[i]
		var wet: AudioStreamPlayer = runtime.runtime_pool().acquire()
		if wet == null:
			continue
		runtime.runtime_begin_player_voice(wet)
		wet.bus = String(layer.get("bus", "Master"))
		wet.stream = dry_player.stream
		wet.volume_db = float(layer.get("volume_db", dry_player.volume_db))
		wet.pitch_scale = dry_player.pitch_scale
		wet.stream_paused = dry_player.stream_paused
		if dry_player.has_meta(&"_coda_clip_timeline_end"):
			wet.set_meta(
				&"_coda_clip_timeline_end",
				dry_player.get_meta(&"_coda_clip_timeline_end")
			)
		if dry_player.has_meta(&"_coda_timeline_restart_offset"):
			wet.set_meta(
				&"_coda_timeline_restart_offset",
				dry_player.get_meta(&"_coda_timeline_restart_offset")
			)
		var fx_nm: String = String(layer.get("fx_bus", ""))
		if not fx_nm.is_empty():
			wet.set_meta(&"_coda_fx_bus", fx_nm)
		wet.play(stream_offset)
		voices["%s_wet_%d" % [voice_key_prefix, i]] = wet
	d["voices"] = voices


static func _runtime_bus_id_map(runtime: CodaRuntime) -> Dictionary:
	if runtime == null:
		return {}
	var bus_sync: Variant = runtime.get_bus_sync()
	if bus_sync == null:
		return {}
	return bus_sync.get_bus_id_map()


static func _spawnable_wet_send_count(
	runtime: CodaRuntime,
	sends: Array[CodaBusSend],
	bus_root: CodaBus
) -> int:
	return CodaBusSendRuntimeScript.collect_spawnable_wet_sends(
		sends, bus_root, _runtime_bus_id_map(runtime)
	).size()


static func count_timeline_wet_layers(voices: Dictionary, voice_key_prefix: String) -> int:
	var count: int = 0
	while voices.has("%s_wet_%d" % [voice_key_prefix, count]):
		count += 1
	return count


static func ensure_timeline_wet_layers(
	runtime: CodaRuntime,
	handle: CodaEventHandle,
	d: Dictionary,
	dry_player: AudioStreamPlayer,
	voice_key_prefix: String,
	sends: Array[CodaBusSend],
	param_values: Dictionary
) -> void:
	if runtime == null or handle == null or dry_player == null or not is_instance_valid(dry_player):
		return
	if sends.is_empty():
		return
	var bus_root: CodaBus = runtime.get_playback_bus_root()
	if bus_root == null:
		return
	var expected_count: int = _spawnable_wet_send_count(runtime, sends, bus_root)
	var voices: Dictionary = d.get("voices", {})
	var existing_count: int = count_timeline_wet_layers(voices, voice_key_prefix)
	if existing_count == expected_count:
		return
	teardown_wet_layers_for_prefix(d, voice_key_prefix)
	if expected_count <= 0:
		return
	spawn_wet_layers(
		runtime, handle, dry_player, d, voice_key_prefix, sends, param_values
	)


static func ensure_graph_wet_layers(
	runtime: CodaRuntime,
	owner: CodaEventHandle,
	dry_player: AudioStreamPlayer,
	sends: Array[CodaBusSend],
	param_values: Dictionary
) -> void:
	if runtime == null or owner == null or dry_player == null or not is_instance_valid(dry_player):
		return
	if sends.is_empty():
		return
	var bus_root: CodaBus = runtime.get_playback_bus_root()
	if bus_root == null:
		return
	var expected_count: int = _spawnable_wet_send_count(runtime, sends, bus_root)
	var by_dry: Dictionary = owner.params.get("_coda_graph_wet_by_dry", {})
	var dry_key: String = str(dry_player.get_instance_id())
	var dry_wets: Array = by_dry.get(dry_key, [])
	if dry_wets.size() == expected_count:
		return
	teardown_graph_wet_layers_for_dry(owner, dry_player)
	if expected_count <= 0:
		return
	spawn_graph_wet_layers(runtime, owner, dry_player, sends, param_values)


static func refresh_graph_wet_layers_for_dry(
	runtime: CodaRuntime,
	owner: CodaEventHandle,
	dry_player: AudioStreamPlayer,
	param_values: Dictionary
) -> void:
	if runtime == null or owner == null or dry_player == null or not is_instance_valid(dry_player):
		return
	var event_sends: Array[CodaBusSend] = []
	if owner.event_node is CodaBrowserNode:
		event_sends = (owner.event_node as CodaBrowserNode).event_wet_sends
	ensure_graph_wet_layers(runtime, owner, dry_player, event_sends, param_values)
	var by_dry: Dictionary = owner.params.get("_coda_graph_wet_by_dry", {})
	var dry_key: String = str(dry_player.get_instance_id())
	var dry_wets: Array = by_dry.get(dry_key, [])
	if dry_wets.is_empty():
		return
	var bus_root: CodaBus = runtime.get_playback_bus_root()
	if bus_root == null:
		return
	var dry_db: float = dry_player.volume_db
	var dry_pitch: float = dry_player.pitch_scale
	for i in range(dry_wets.size()):
		var wet: AudioStreamPlayer = dry_wets[i] as AudioStreamPlayer
		if wet == null or not is_instance_valid(wet):
			continue
		wet.volume_db = wet_volume_db_for_layer(
			dry_db, i, event_sends, bus_root, param_values, _runtime_bus_id_map(runtime)
		)
		wet.pitch_scale = dry_pitch


static func spawn_graph_wet_layers(
	runtime: CodaRuntime,
	handle: CodaEventHandle,
	dry_player: AudioStreamPlayer,
	sends: Array[CodaBusSend],
	param_values: Dictionary
) -> void:
	if runtime == null or handle == null or dry_player == null or sends.is_empty():
		return
	var bus_root: CodaBus = runtime.get_playback_bus_root()
	if bus_root == null:
		return
	var layers: Array = CodaBusSendRuntimeScript.build_wet_voice_layers(
		sends,
		bus_root,
		_runtime_bus_id_map(runtime),
		param_values,
		dry_player.volume_db
	)
	if layers.is_empty():
		return
	var by_dry: Dictionary = handle.params.get("_coda_graph_wet_by_dry", {})
	var dry_key: String = str(dry_player.get_instance_id())
	var dry_wets: Array = by_dry.get(dry_key, [])
	for i in range(layers.size()):
		var layer: Dictionary = layers[i]
		var wet: AudioStreamPlayer = runtime.runtime_pool().acquire()
		if wet == null:
			continue
		runtime.runtime_begin_player_voice(wet)
		wet.bus = String(layer.get("bus", "Master"))
		wet.stream = dry_player.stream
		wet.volume_db = float(layer.get("volume_db", dry_player.volume_db))
		wet.pitch_scale = dry_player.pitch_scale
		var fx_nm: String = String(layer.get("fx_bus", ""))
		if not fx_nm.is_empty():
			wet.set_meta(&"_coda_fx_bus", fx_nm)
		wet.play(0.0)
		dry_wets.append(wet)
	by_dry[dry_key] = dry_wets
	handle.params["_coda_graph_wet_by_dry"] = by_dry
	_rebuild_graph_wet_players_list(handle)


static func stop_graph_wet_layers(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	var wet_players: Array = handle.params.get("_coda_wet_players", [])
	for p in wet_players:
		_stop_graph_wet_player(p)
	handle.params["_coda_wet_players"] = []
	handle.params.erase("_coda_graph_wet_by_dry")


static func teardown_graph_wet_layers_for_dry(
	handle: CodaEventHandle, dry_player: AudioStreamPlayer
) -> void:
	if handle == null or dry_player == null or not is_instance_valid(dry_player):
		return
	var by_dry: Dictionary = handle.params.get("_coda_graph_wet_by_dry", {})
	var dry_key: String = str(dry_player.get_instance_id())
	var dry_wets: Array = by_dry.get(dry_key, [])
	if dry_wets.is_empty():
		return
	for p in dry_wets:
		_stop_graph_wet_player(p)
	by_dry.erase(dry_key)
	handle.params["_coda_graph_wet_by_dry"] = by_dry
	_rebuild_graph_wet_players_list(handle)


static func _rebuild_graph_wet_players_list(handle: CodaEventHandle) -> void:
	var flat: Array = []
	for wets in handle.params.get("_coda_graph_wet_by_dry", {}).values():
		for p in wets:
			flat.append(p)
	handle.params["_coda_wet_players"] = flat


static func _stop_graph_wet_player(p: Variant) -> void:
	var wet: AudioStreamPlayer = p as AudioStreamPlayer
	if wet == null or not is_instance_valid(wet):
		return
	if wet.has_meta(&"_coda_fx_bus"):
		CodaFxBusHelperScript.destroy_if_ours(String(wet.get_meta(&"_coda_fx_bus")))
	if wet.playing:
		wet.stop()


static func pause_graph_wet_layers(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	for p in handle.params.get("_coda_wet_players", []):
		var wet: AudioStreamPlayer = p as AudioStreamPlayer
		if wet != null and is_instance_valid(wet) and wet.playing:
			wet.stream_paused = true


static func resume_graph_wet_layers(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	for p in handle.params.get("_coda_wet_players", []):
		var wet: AudioStreamPlayer = p as AudioStreamPlayer
		if wet != null and is_instance_valid(wet) and wet.playing:
			wet.stream_paused = false


static func restart_wet_layers_for_prefix(
	d: Dictionary, voice_key_prefix: String, restart_at: float, stream_paused: bool
) -> void:
	var voices: Dictionary = d.get("voices", {})
	var prefix: String = "%s_wet_" % voice_key_prefix
	for k in voices.keys():
		if not str(k).begins_with(prefix):
			continue
		var wet: AudioStreamPlayer = voices[k] as AudioStreamPlayer
		if wet == null or not is_instance_valid(wet):
			continue
		wet.stream_paused = stream_paused
		wet.play(maxf(0.0, restart_at))
		wet.stream_paused = stream_paused


static func teardown_wet_layers_for_prefix(d: Dictionary, voice_key_prefix: String) -> void:
	var voices: Dictionary = d.get("voices", {})
	var remove_keys: Array = []
	for k in voices.keys():
		if str(k).begins_with("%s_wet_" % voice_key_prefix):
			var p: AudioStreamPlayer = voices[k] as AudioStreamPlayer
			if p != null and is_instance_valid(p):
				if p.has_meta(&"_coda_fx_bus"):
					CodaFxBusHelperScript.destroy_if_ours(String(p.get_meta(&"_coda_fx_bus")))
				if p.playing:
					p.stop()
			remove_keys.append(k)
	for k in remove_keys:
		voices.erase(k)
	d["voices"] = voices
