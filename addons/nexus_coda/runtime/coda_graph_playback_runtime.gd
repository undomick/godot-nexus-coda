@tool
class_name CodaGraphPlaybackRuntime
extends RefCounted

const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaRuntimeGraphPlaybackScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_graph_playback.gd"
)
const CodaRuntimeParameterPipelineScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_parameter_pipeline.gd"
)
const CodaVoiceWetLayersScript := preload(
	"res://addons/nexus_coda/runtime/coda_voice_wet_layers.gd"
)
const CodaSpatialVoiceRuntimeScript := preload(
	"res://addons/nexus_coda/runtime/coda_spatial_voice_runtime.gd"
)
const CodaAudioStreamCacheScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_stream_cache.gd"
)

var _runtime: CodaRuntime = null
var _voice_fader: CodaVoiceFader = null
var _paused_graph_handles: Array[CodaEventHandle] = []


func setup(runtime: CodaRuntime, voice_fader: CodaVoiceFader) -> void:
	_runtime = runtime
	_voice_fader = voice_fader


func start_graph_event(
	event: CodaBrowserNode,
	path: String,
	params: Dictionary,
	source_bank_id: String,
	live_params: Dictionary,
	plan_entries: Array,
	graph_event_loop: bool
) -> CodaEventHandle:
	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.id = _runtime.runtime_allocate_handle_id()
	handle.event_path = path
	handle.event_node = event
	handle.source_bank_id = source_bank_id
	handle.params = params.duplicate()
	handle.param_values = live_params
	handle.param_values_smoothed = live_params.duplicate()
	handle.loop = bool(params.get("loop", false)) or graph_event_loop
	handle._bus_name = _runtime.bus_name
	handle.timeline_runtime = _runtime

	var parallel_entries: Array = _split_parallel_entries(plan_entries)
	var queued_after_parallel: Array = plan_entries.slice(parallel_entries.size())
	var step: Dictionary = _start_parallel_step(
		handle, parallel_entries, queued_after_parallel, params, handle.loop
	)
	if step.get("primary_player") == null:
		return null
	var started_indices: Dictionary = step.get("started_indices", {}) as Dictionary
	if started_indices.size() < parallel_entries.size():
		_report_blend_pool_exhausted(
			event.name, started_indices.size(), parallel_entries.size()
		)
		handle.params["_coda_full_plan"] = plan_entries
		handle.params["_coda_plan"] = _graph_plan_after_incomplete_parallel_step(
			parallel_entries, started_indices, queued_after_parallel
		)
		mark_plan_resume(handle)
		_runtime.runtime_emit_voice_started(handle)
		return handle
	handle.params["_coda_plan"] = queued_after_parallel
	handle.params["_coda_full_plan"] = plan_entries
	_runtime.runtime_emit_voice_started(handle)
	return handle


func resume_pending_plans() -> void:
	var resume_handles: Array = _runtime.get_graph_plan_resume_handles()
	if resume_handles.is_empty():
		return
	var pending: Array = resume_handles.duplicate()
	for item in pending:
		var h: CodaEventHandle = item as CodaEventHandle
		if h == null or not h._alive or h.is_timeline:
			unmark_plan_resume(h)
			continue
		if _graph_parallel_still_playing(h):
			continue
		_try_finish_graph_handle(h)


func on_voice_finished_for_graph(
	player: AudioStreamPlayer, key: int, stop_all_in_progress: bool
) -> bool:
	var active_handles: Dictionary = _runtime.get_active_handles()
	if not active_handles.has(key):
		return false
	if stop_all_in_progress:
		active_handles.erase(key)
		return true
	var h: CodaEventHandle = active_handles[key] as CodaEventHandle
	active_handles.erase(key)
	if h == null:
		return true
	if int(h.params.get("_coda_playback_gen", -1)) != int(player.get_meta(&"_coda_playback_gen", -1)):
		return true
	if bool(h.params.get("_coda_is_sibling", false)):
		if not h._alive:
			return true
		CodaVoiceWetLayersScript.stop_graph_wet_layers(h)
		h._alive = false
		var parent: CodaEventHandle = h.params.get("_coda_graph_parent", null) as CodaEventHandle
		if parent != null:
			var sib_idx: int = parent.graph_parallel_siblings.find(h)
			if sib_idx >= 0:
				parent.graph_parallel_siblings.remove_at(sib_idx)
			if not parent._paused:
				_try_finish_graph_handle(parent)
		return true
	CodaVoiceWetLayersScript.stop_graph_wet_layers(h)
	_try_finish_graph_handle(h)
	return true


func stop_parallel_siblings(handle: CodaEventHandle, fade_ms: int = 0) -> void:
	var active_handles: Dictionary = _runtime.get_active_handles()
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		CodaVoiceWetLayersScript.stop_graph_wet_layers(sib)
		if fade_ms > 0 and sib._player != null and is_instance_valid(sib._player) and sib._player.playing:
			_voice_fader.fade_volume_db(
				sib._player, -80.0, fade_ms, Callable(sib, "_stop_local").bind(0)
			)
		else:
			sib._alive = false
			if sib._player != null and is_instance_valid(sib._player) and sib._player.playing:
				sib._player.stop()
		if sib._player != null and is_instance_valid(sib._player):
			active_handles.erase(sib._player.get_instance_id())
	handle.graph_parallel_siblings.clear()


func mark_plan_resume(handle: CodaEventHandle) -> void:
	if handle == null or handle.is_timeline or not handle._alive:
		return
	var resume_handles: Array = _runtime.get_graph_plan_resume_handles()
	if resume_handles.has(handle):
		return
	resume_handles.append(handle)


func unmark_plan_resume(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	var resume_handles: Array = _runtime.get_graph_plan_resume_handles()
	var idx: int = resume_handles.find(handle)
	if idx >= 0:
		resume_handles.remove_at(idx)


func get_paused_graph_handles() -> Array[CodaEventHandle]:
	return _paused_graph_handles


func drop_paused_preview_state(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	_unpause_graph_players(handle)
	var idx: int = _paused_graph_handles.find(handle)
	if idx >= 0:
		_paused_graph_handles.remove_at(idx)
	handle.params.erase("_coda_graph_pause_snapshot")


func finalize_all_paused_previews() -> void:
	for item in _paused_graph_handles.duplicate():
		var h: CodaEventHandle = item as CodaEventHandle
		if h == null:
			continue
		_finalize_paused_preview(h)
	_paused_graph_handles.clear()


func pause_graph_preview(handle: CodaEventHandle) -> void:
	if handle == null or handle.is_timeline:
		return
	var snapshot: Dictionary = {}
	_snapshot_pause_player(handle, snapshot)
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		_snapshot_pause_player(sib, snapshot)
	handle.params["_coda_graph_pause_snapshot"] = snapshot
	CodaVoiceWetLayersScript.pause_graph_wet_layers(handle)
	for sib in handle.graph_parallel_siblings:
		if sib != null:
			CodaVoiceWetLayersScript.pause_graph_wet_layers(sib)
	if not _paused_graph_handles.has(handle):
		_paused_graph_handles.append(handle)


func resume_graph_preview(handle: CodaEventHandle) -> void:
	if handle == null or handle.is_timeline:
		return
	var snapshot: Variant = handle.params.get("_coda_graph_pause_snapshot", {})
	drop_paused_preview_state(handle)
	if typeof(snapshot) != TYPE_DICTIONARY:
		return
	var snap: Dictionary = snapshot as Dictionary
	if snap.is_empty():
		return
	var expected: int = snap.size()
	var resumed: int = 0
	if _resume_paused_player(handle, handle, snap):
		resumed += 1
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		if _resume_paused_player(handle, sib, snap):
			resumed += 1
	if resumed != expected and handle._alive:
		_runtime.stop(handle)
		return
	CodaVoiceWetLayersScript.resume_graph_wet_layers(handle)
	for sib in handle.graph_parallel_siblings:
		if sib != null:
			CodaVoiceWetLayersScript.resume_graph_wet_layers(sib)


func _finalize_paused_preview(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	drop_paused_preview_state(handle)
	if not handle._paused:
		return
	handle._paused = false
	unmark_plan_resume(handle)
	_unpause_graph_players(handle)
	stop_parallel_siblings(handle)
	CodaVoiceWetLayersScript.stop_graph_wet_layers(handle)
	handle.clear_player_binding()
	var was_alive: bool = handle._alive
	if was_alive:
		handle._alive = false
		handle.finished.emit()
	_runtime.runtime_emit_voice_finished(handle)


func _snapshot_pause_player(voice: CodaEventHandle, snapshot: Dictionary) -> void:
	if voice._player == null or not is_instance_valid(voice._player):
		return
	var pk: int = voice._player.get_instance_id()
	var pos: float = 0.0
	if voice._player.playing:
		pos = voice._player.get_playback_position()
		# Keep the pooled player reserved (stream_paused still reports playing). Stopping
		# would return the slot to acquire() and another voice could reuse this player.
		voice._player.stream_paused = true
	voice._player.set_meta(&"_coda_graph_paused", true)
	snapshot[str(pk)] = {
		"position": pos,
		"gen": int(voice._player.get_meta(&"_coda_playback_gen", -1)),
	}


func _resume_paused_player(
	owner: CodaEventHandle, voice: CodaEventHandle, snapshot: Dictionary
) -> bool:
	if voice._player == null or not is_instance_valid(voice._player):
		return false
	if voice._player.stream == null:
		return false
	var key: String = str(voice._player.get_instance_id())
	var saved: Variant = snapshot.get(key, null)
	if typeof(saved) != TYPE_DICTIONARY:
		return false
	var saved_d: Dictionary = saved as Dictionary
	var expected_gen: int = int(saved_d.get("gen", -2))
	if int(voice._player.get_meta(&"_coda_playback_gen", -1)) != expected_gen:
		return false
	if voice._player.has_meta(&"_coda_graph_paused"):
		voice._player.remove_meta(&"_coda_graph_paused")
	if voice._player.playing:
		voice._player.stream_paused = false
	else:
		var at: float = maxf(0.0, float(saved_d.get("position", 0.0)))
		voice._player.play(at)
	var gen: int = int(voice._player.get_meta(&"_coda_playback_gen", -1))
	var active_handles: Dictionary = _runtime.get_active_handles()
	if voice == owner:
		owner.params["_coda_playback_gen"] = gen
		active_handles[voice._player.get_instance_id()] = owner
	else:
		voice.params["_coda_playback_gen"] = gen
		active_handles[voice._player.get_instance_id()] = voice
	return true


func _unpause_graph_players(handle: CodaEventHandle) -> void:
	if handle._player != null and is_instance_valid(handle._player):
		if handle._player.has_meta(&"_coda_graph_paused"):
			handle._player.remove_meta(&"_coda_graph_paused")
		handle._player.stream_paused = false
	for sib in handle.graph_parallel_siblings:
		if sib == null or sib._player == null or not is_instance_valid(sib._player):
			continue
		if sib._player.has_meta(&"_coda_graph_paused"):
			sib._player.remove_meta(&"_coda_graph_paused")
		sib._player.stream_paused = false


func _start_parallel_step(
	owner: CodaEventHandle,
	parallel_entries: Array,
	plan_tail: Array,
	params: Dictionary,
	event_loops: bool,
) -> Dictionary:
	CodaVoiceWetLayersScript.stop_graph_wet_layers(owner)
	var active_handles: Dictionary = _runtime.get_active_handles()
	var primary_player: AudioStreamPlayer = null
	var started_indices: Dictionary = {}
	for i in parallel_entries.size():
		var entry: Dictionary = parallel_entries[i] as Dictionary
		var tail: Array = parallel_entries.slice(i + 1)
		tail.append_array(plan_tail)
		var player: AudioStreamPlayer = _start_player_for_entry(
			entry, params, tail, event_loops
		)
		if player == null:
			continue
		started_indices[i] = true
		if primary_player == null:
			_bind_primary_player(owner, entry, player, params)
			_spawn_graph_wet_layers_for_entry(owner, player)
			active_handles[player.get_instance_id()] = owner
			primary_player = player
		else:
			var sib_h: CodaEventHandle = _make_sibling_handle(owner, entry, player)
			_spawn_graph_wet_layers_for_entry(sib_h, player)
			owner.graph_parallel_siblings.append(sib_h)
			active_handles[player.get_instance_id()] = sib_h
	return {"primary_player": primary_player, "started_indices": started_indices}


func _bind_primary_player(
	owner: CodaEventHandle, entry: Dictionary, player: AudioStreamPlayer, params: Dictionary
) -> void:
	owner.current_sound_id = String(entry.get("sound_id", ""))
	owner.base_volume_db = float(entry.get("volume_db", 0.0)) + float(params.get("volume_db", 0.0))
	owner.base_pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(params.get("pitch_scale", 1.0))
	owner.blend_weight = float(entry.get("blend_weight", 1.0))
	owner._bind_player(player)
	owner.params["_coda_playback_gen"] = int(player.get_meta(&"_coda_playback_gen", -1))


func _split_parallel_entries(entries: Array) -> Array:
	return CodaRuntimeGraphPlaybackScript.split_parallel_entries(entries)


func _graph_plan_after_incomplete_parallel_step(
	parallel_entries: Array, started_indices: Dictionary, rest: Array
) -> Array:
	return CodaRuntimeGraphPlaybackScript.plan_after_incomplete_parallel_step(
		parallel_entries, started_indices, rest
	)


func _make_sibling_handle(
	parent: CodaEventHandle, entry: Dictionary, player: AudioStreamPlayer
) -> CodaEventHandle:
	var sib: CodaEventHandle = CodaEventHandleScript.new()
	sib.id = _runtime.runtime_allocate_handle_id()
	sib.event_path = parent.event_path
	sib.event_node = parent.event_node
	sib.source_bank_id = parent.source_bank_id
	sib.params = {"_coda_is_sibling": true, "_coda_graph_parent": parent}
	sib.param_values = parent.param_values
	sib.param_values_smoothed = parent.param_values_smoothed
	sib.loop = false
	sib._bus_name = parent._bus_name
	sib.current_sound_id = String(entry.get("sound_id", ""))
	sib.base_volume_db = float(entry.get("volume_db", 0.0)) + float(parent.params.get("volume_db", 0.0))
	sib.base_pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(
		parent.params.get("pitch_scale", 1.0)
	)
	sib.blend_weight = float(entry.get("blend_weight", 1.0))
	sib._bind_player(player)
	sib.params["_coda_playback_gen"] = int(player.get_meta(&"_coda_playback_gen", -1))
	return sib


func _graph_parallel_still_playing(handle: CodaEventHandle) -> bool:
	if handle._player != null and is_instance_valid(handle._player) and handle._player.playing:
		return true
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		if sib._player != null and is_instance_valid(sib._player) and sib._player.playing:
			return true
	return false


func _restart_graph_loop_from_full_plan(h: CodaEventHandle) -> bool:
	var full: Variant = h.params.get("_coda_full_plan", [])
	if not full is Array or (full as Array).is_empty():
		return false
	stop_parallel_siblings(h)
	var plan_entries: Array = full as Array
	var parallel_entries: Array = _split_parallel_entries(plan_entries)
	var queued_after_parallel: Array = plan_entries.slice(parallel_entries.size())
	var step: Dictionary = _start_parallel_step(
		h, parallel_entries, queued_after_parallel, h.params, h.loop
	)
	if step.get("primary_player") == null:
		return false
	var started_indices: Dictionary = step.get("started_indices", {}) as Dictionary
	if started_indices.size() < parallel_entries.size():
		h.params["_coda_plan"] = _graph_plan_after_incomplete_parallel_step(
			parallel_entries, started_indices, queued_after_parallel
		)
		mark_plan_resume(h)
		return false
	h.params["_coda_plan"] = queued_after_parallel
	return true


static func _entry_should_loop_stream(
	entry: Dictionary, plan_remaining: Array, event_loops: bool
) -> bool:
	if not bool(entry.get("loop", false)):
		return false
	if not plan_remaining.is_empty():
		return false
	if event_loops:
		return false
	return true


func reroute_voices_for_output_bus(handle: CodaEventHandle, voice_bus: String) -> void:
	if handle == null:
		return
	var route_bus: String = String(voice_bus).strip_edges()
	if route_bus.is_empty() or AudioServer.get_bus_index(route_bus) < 0:
		route_bus = "Master"
	_set_player_output_bus(handle._player, route_bus)
	for sib in handle.graph_parallel_siblings:
		var sh: CodaEventHandle = sib as CodaEventHandle
		if sh != null:
			_set_player_output_bus(sh._player, route_bus)


func _set_player_output_bus(player: AudioStreamPlayer, route_bus: String) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.bus = route_bus


func _start_player_for_entry(
	entry: Dictionary,
	params: Dictionary,
	plan_remaining: Array = [],
	event_loops: bool = false,
) -> AudioStreamPlayer:
	var stream_path: String = String(entry.get("audio_path", "")).strip_edges()
	if stream_path.is_empty():
		_runtime.runtime_warn("plan entry has empty audio_path")
		return null
	if not ResourceLoader.exists(stream_path):
		_runtime.runtime_warn("audio resource missing: '%s'" % stream_path)
		return null
	var stream: AudioStream = CodaAudioStreamCacheScript.load_stream(stream_path)
	if stream == null:
		_runtime.runtime_warn("audio resource not an AudioStream: '%s'" % stream_path)
		return null
	if _entry_should_loop_stream(entry, plan_remaining, event_loops):
		stream = stream.duplicate()
		stream.loop = true
	var player: AudioStreamPlayer = _runtime.runtime_pool().acquire()
	if player == null:
		_runtime.runtime_report_pool_exhausted({
			"mode": "graph",
			"path": stream_path,
			"active": _runtime.active_voice_count(),
			"pool_size": _runtime.runtime_pool_size(),
			"detail": "voice pool exhausted while playing '%s'" % stream_path,
		})
		return null
	var route_bus: String = String(params.get("_coda_voice_bus", _runtime.bus_name))
	if AudioServer.get_bus_index(route_bus) < 0:
		route_bus = "Master"
	player.bus = route_bus
	player.stream = stream
	var override_db: float = float(params.get("volume_db", 0.0))
	var entry_blend: float = float(entry.get("blend_weight", 1.0))
	var blend_db: float = 0.0
	if entry_blend < 1.0 and entry_blend > 0.0:
		blend_db = CodaRuntimeParameterPipelineScript.linear_to_db(entry_blend)
	elif entry_blend <= 0.0:
		blend_db = -80.0
	player.volume_db = float(entry.get("volume_db", 0.0)) + override_db + blend_db
	player.pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(params.get("pitch_scale", 1.0))
	CodaSpatialVoiceRuntimeScript.apply_from_meta(player, player.volume_db)
	_runtime.runtime_begin_player_voice(player)
	player.play()
	return player


func _spawn_graph_wet_layers_for_entry(
	wet_handle: CodaEventHandle, player: AudioStreamPlayer
) -> void:
	if wet_handle == null or player == null:
		return
	if wet_handle.event_node is CodaBrowserNode:
		var ev: CodaBrowserNode = wet_handle.event_node as CodaBrowserNode
		if not ev.event_wet_sends.is_empty():
			CodaVoiceWetLayersScript.spawn_graph_wet_layers(
				_runtime,
				wet_handle,
				player,
				ev.event_wet_sends,
				wet_handle.param_values_smoothed
			)


func _try_finish_graph_handle(h: CodaEventHandle) -> void:
	if h == null or not h._alive:
		return
	if h._paused:
		return
	if _graph_parallel_still_playing(h):
		return
	var queued: Variant = h.params.get("_coda_plan", [])
	if queued is Array and (queued as Array).size() > 0:
		stop_parallel_siblings(h)
		var plan_slice: Array = queued as Array
		var parallel_entries: Array = _split_parallel_entries(plan_slice)
		var rest: Array = plan_slice.slice(parallel_entries.size())
		var step: Dictionary = _start_parallel_step(h, parallel_entries, rest, h.params, h.loop)
		if step.get("primary_player") != null:
			var started_indices: Dictionary = step.get("started_indices", {}) as Dictionary
			if started_indices.size() < parallel_entries.size():
				_report_blend_pool_exhausted(
					h.event_path, started_indices.size(), parallel_entries.size()
				)
				h.params["_coda_plan"] = _graph_plan_after_incomplete_parallel_step(
					parallel_entries, started_indices, rest
				)
				mark_plan_resume(h)
				return
			h.params["_coda_plan"] = rest
			unmark_plan_resume(h)
			return
		_report_sequence_pool_exhausted(h.event_path, plan_slice.size())
		mark_plan_resume(h)
		return
	if h.loop:
		if _restart_graph_loop_from_full_plan(h):
			unmark_plan_resume(h)
			return
		mark_plan_resume(h)
		return
	unmark_plan_resume(h)
	CodaVoiceWetLayersScript.stop_graph_wet_layers(h)
	h._on_player_finished()
	_runtime.runtime_emit_voice_finished(h)


func _report_blend_pool_exhausted(path_label: String, started: int, total: int) -> void:
	_runtime.runtime_report_pool_exhausted({
		"mode": "graph_blend",
		"path": path_label,
		"active": _runtime.active_voice_count(),
		"pool_size": _runtime.runtime_pool_size(),
		"detail": "voice pool exhausted; BLEND step incomplete for '%s' (%d/%d voices)"
			% [path_label, started, total],
	})


func _report_sequence_pool_exhausted(path_label: String, remaining: int) -> void:
	_runtime.runtime_report_pool_exhausted({
		"mode": "graph_sequence",
		"path": path_label,
		"active": _runtime.active_voice_count(),
		"pool_size": _runtime.runtime_pool_size(),
		"detail": "voice pool exhausted; sequence paused for '%s' (%d entries remain)"
			% [path_label, remaining],
	})
