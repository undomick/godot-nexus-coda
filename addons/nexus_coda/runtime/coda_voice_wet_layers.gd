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
	param_values: Dictionary
) -> float:
	if wet_index < 0 or bus_root == null:
		return dry_volume_db
	var active: Array[CodaBusSend] = CodaBusSendRuntimeScript.filter_active_sends(
		merged_sends, bus_root, param_values
	)
	if wet_index >= active.size():
		# Send disabled via RTPC or filtered out; silence instead of full dry into return bus.
		return -80.0
	var amt: float = CodaBusSendRuntimeScript.effective_level(active[wet_index], param_values)
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
	var id_map: Dictionary = runtime.get_bus_id_map()
	var layers: Array = CodaBusSendRuntimeScript.build_wet_voice_layers(
		sends,
		bus_root,
		id_map,
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
		runtime.get_bus_id_map(),
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
