@tool
extends Node
class_name CodaRuntime

## Autoload and editor preview runtime. Public API: play/stop, parameters, snapshots, banks.

signal voice_started(handle: CodaEventHandle)
signal voice_finished(handle: CodaEventHandle)
signal voice_pool_exhausted(context: Dictionary)
signal marker_reached(handle: CodaEventHandle, marker_id: String)
signal project_loaded(state: CodaProject)

const CodaVoicePoolScript := preload("res://addons/nexus_coda/runtime/coda_voice_pool.gd")
const CodaEventResolverScript := preload("res://addons/nexus_coda/runtime/coda_event_resolver.gd")
const CodaGraphSchedulerScript := preload("res://addons/nexus_coda/runtime/coda_graph_scheduler.gd")
const CodaVoiceFaderScript := preload("res://addons/nexus_coda/runtime/coda_voice_fader.gd")
const CodaTimelineSegmentDriverScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_segment_driver.gd"
)
const CodaSnapshotBlenderScript := preload("res://addons/nexus_coda/runtime/coda_snapshot_blender.gd")
const CodaTimelineMusicControllerScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_music_controller.gd"
)
const CodaMusicTransitionPolicyScript := preload(
	"res://addons/nexus_coda/runtime/coda_music_transition_policy.gd"
)
const CodaGraphPlaybackRuntimeScript := preload(
	"res://addons/nexus_coda/runtime/coda_graph_playback_runtime.gd"
)
const CodaTimelineDispatcherScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_dispatcher.gd"
)
const CodaPooledVoiceLifecycleScript := preload(
	"res://addons/nexus_coda/runtime/coda_pooled_voice_lifecycle.gd"
)
const CodaRuntimeParameterPipelineScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_parameter_pipeline.gd"
)
const CodaRuntimeBusSyncScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_bus_sync.gd"
)
const CodaAudioBusSyncGateScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd"
)
const CodaRuntimeBankRegistryScript := preload(
	"res://addons/nexus_coda/runtime/coda_runtime_bank_registry.gd"
)
const CodaAudioStreamCacheScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_stream_cache.gd"
)
const CodaPlayOptionsScript := preload("res://addons/nexus_coda/domain/coda_play_options.gd")
const CodaVoiceWetLayersScript := preload("res://addons/nexus_coda/runtime/coda_voice_wet_layers.gd")
const NexusCodaLogScript := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")

const RUNTIME_LOG_SCOPE := "runtime"

@export var bus_name: String = "Master"
@export var is_editor_preview: bool = false

var _project: CodaProject = null
var _pool: CodaVoicePool
var _active_handles: Dictionary = {}
var _next_handle_id: int = 1
var _timeline_dispatchers: Dictionary = {}
var _timeline_voice_owner: Dictionary = {}
var _timeline_voice_playback_gen: Dictionary = {}
var _next_playback_gen: int = 1
var _player_pending_finish_gen: Dictionary = {}
var _orphaned_finish_gens: Dictionary = {}
var _stop_all_in_progress: bool = false
var _graph_plan_resume_handles: Array[CodaEventHandle] = []
var _voice_fader: CodaVoiceFader
var _segment_driver: CodaTimelineSegmentDriver
var _snapshot_blender: CodaSnapshotBlender
var _timeline_music: CodaTimelineMusicController
var _timeline_dispatcher: CodaTimelineDispatcher
var _graph_playback: CodaGraphPlaybackRuntime
var _parameter_pipeline: CodaRuntimeParameterPipeline
var _bus_sync: CodaRuntimeBusSync
var _bank_registry: CodaRuntimeBankRegistry
var _transition_policy: CodaMusicTransitionPolicy
var _pool_warn_last_ms: Dictionary = {}


func _ready() -> void:
	if _pool == null:
		_pool = CodaVoicePoolScript.new()
		_pool.name = "VoicePool"
		add_child(_pool)
	if not _pool.voice_finished.is_connected(_on_voice_finished):
		_pool.voice_finished.connect(_on_voice_finished)
	_voice_fader = CodaVoiceFaderScript.new(self)
	_segment_driver = CodaTimelineSegmentDriverScript.new()
	_transition_policy = CodaMusicTransitionPolicyScript.default_policy()
	_parameter_pipeline = CodaRuntimeParameterPipelineScript.new()
	_parameter_pipeline.setup(self)
	_bus_sync = CodaRuntimeBusSyncScript.new()
	_bus_sync.setup(self)
	_bank_registry = CodaRuntimeBankRegistryScript.new()
	_bank_registry.setup(self)
	_snapshot_blender = CodaSnapshotBlenderScript.new()
	_snapshot_blender.setup(
		_project,
		Callable(_bus_sync, "sync_buses"),
		_snapshot_sync_caller(),
	)
	_timeline_music = CodaTimelineMusicControllerScript.new()
	_timeline_music.setup(
		self,
		_voice_fader,
		_segment_driver,
		_transition_policy,
		Callable(self, "_emit_marker_reached")
	)
	_timeline_dispatcher = CodaTimelineDispatcherScript.new()
	_timeline_dispatcher.setup(self, _voice_fader, _timeline_music)
	_graph_playback = CodaGraphPlaybackRuntimeScript.new()
	_graph_playback.setup(self, _voice_fader)
	set_process(true)


func get_transition_policy() -> CodaMusicTransitionPolicy:
	return _transition_policy


func _emit_marker_reached(handle: CodaEventHandle, marker_id: String) -> void:
	marker_reached.emit(handle, marker_id)


func _process(delta: float) -> void:
	if _snapshot_blender != null:
		_snapshot_blender.tick(delta)
	if not _timeline_dispatchers.is_empty():
		_timeline_dispatcher.tick_dispatchers(delta)
	_graph_playback.resume_pending_plans()
	if _active_handles.is_empty() and not _parameter_pipeline.has_global_params():
		return
	_parameter_pipeline.apply_global_parameters()
	for h in _active_handles.values():
		var hh: CodaEventHandle = h as CodaEventHandle
		if hh == null or not hh._alive:
			continue
		_parameter_pipeline.advance_smoothing(hh, delta)
		_parameter_pipeline.apply_modulations(hh)


func _exit_tree() -> void:
	# Autoload and editor-preview runtimes should leave no active voices/dispatchers behind.
	stop_all()
	set_project(null)


func _drop_project_reference() -> void:
	if _project == null:
		return
	if _project.structure_changed.is_connected(_on_project_bus_structure_changed):
		_project.structure_changed.disconnect(_on_project_bus_structure_changed)
	_project.release_owned_references()
	_project = null


func sync_editor_playback_copy(source: CodaProject) -> void:
	if not is_editor_preview or source == null:
		return
	set_project(source.duplicate_for_playback())


func set_project(project: Variant) -> void:
	# Editor project loads and gameplay project swaps must not keep dispatchers tied to the
	# previous CodaState (timeline cursors, graph plans, pooled players).
	stop_all()
	CodaAudioStreamCacheScript.clear()
	if project != null:
		_bank_registry.clear()
	_drop_project_reference()
	if project == null:
		if _snapshot_blender != null:
			_snapshot_blender.setup(
				_project, Callable(_bus_sync, "sync_buses"), _snapshot_sync_caller()
			)
			_snapshot_blender.clear()
		_bus_sync.apply_loaded_bank_buses()
		project_loaded.emit(null)
		return
	_project = project as CodaProject
	if _snapshot_blender != null:
		_snapshot_blender.setup(
			_project, Callable(_bus_sync, "sync_buses"), _snapshot_sync_caller()
		)
	_bus_sync.sync_buses()
	if _project != null:
		if not _project.structure_changed.is_connected(_on_project_bus_structure_changed):
			_project.structure_changed.connect(_on_project_bus_structure_changed)
	project_loaded.emit(_project)


func _on_project_bus_structure_changed() -> void:
	_bus_sync.sync_buses()


func resolve_bus_name_for_event(event: CodaBrowserNode) -> String:
	return _bus_sync.resolve_bus_name_for_event(event)


func resolve_godot_bus_name_for_coda_bus_id(coda_bus_id: String) -> String:
	return _bus_sync.resolve_godot_bus_name_for_coda_bus_id(coda_bus_id)


## Live authoring change: sync playback copy routing and reroute active preview voices.
func apply_event_output_bus_from_authoring(live_event: CodaBrowserNode) -> void:
	if live_event == null or _project == null:
		return
	var playback: CodaBrowserNode = _project.find_node_anywhere(live_event.id) as CodaBrowserNode
	if playback == null:
		return
	playback.event_output_bus_id = live_event.event_output_bus_id
	var voice_bus: String = resolve_bus_name_for_event(playback)
	_apply_voice_bus_to_active_handles(live_event.id, voice_bus)


func _apply_voice_bus_to_active_handles(event_id: String, voice_bus: String) -> void:
	if event_id.is_empty():
		return
	var timeline_handle: CodaEventHandle = _timeline_dispatcher.active_handle_for_event(event_id)
	if timeline_handle != null and timeline_handle._alive:
		timeline_handle.params["_coda_voice_bus"] = voice_bus
		_timeline_dispatcher.reroute_voices_for_event_output(timeline_handle)
	for handle in _collect_alive_graph_handles_for_event(event_id):
		handle.params["_coda_voice_bus"] = voice_bus
		_graph_playback.reroute_voices_for_output_bus(handle, voice_bus)


func _collect_alive_graph_handles_for_event(event_id: String) -> Array[CodaEventHandle]:
	var out: Array[CodaEventHandle] = []
	var seen: Dictionary = {}
	for h in _active_handles.values():
		var gh: CodaEventHandle = h as CodaEventHandle
		if gh == null or not gh._alive or gh.is_timeline:
			continue
		if not _handle_matches_event_id(gh, event_id):
			continue
		if seen.has(gh):
			continue
		seen[gh] = true
		out.append(gh)
	for h in _graph_plan_resume_handles:
		if h == null or not h._alive or h.is_timeline:
			continue
		if not _handle_matches_event_id(h, event_id):
			continue
		if seen.has(h):
			continue
		seen[h] = true
		out.append(h)
	return out


func _handle_matches_event_id(handle: CodaEventHandle, event_id: String) -> bool:
	if handle == null or handle.event_node == null:
		return false
	return String(handle.event_node.id) == event_id


func get_project() -> CodaProject:
	return _project


func get_playback_bus_root() -> CodaBus:
	if _project != null and _project.bus_root != null:
		return _project.bus_root
	var banks: Dictionary = _bank_registry.get_loaded_banks()
	if banks.is_empty():
		return null
	for bank_id in banks.keys():
		var entry: Dictionary = banks[bank_id]
		var root: Variant = entry.get("bus_root", null)
		if root is CodaBus:
			return root as CodaBus
	return null


func get_bus_id_map() -> Dictionary:
	return _bus_sync.get_bus_id_map()


func _snapshot_sync_caller() -> int:
	if is_editor_preview:
		return CodaAudioBusSyncGateScript.SyncCaller.EditorPreview
	return CodaAudioBusSyncGateScript.SyncCaller.GameplayAutoload


func play(event_path: String, params: Dictionary = {}) -> CodaEventHandle:
	var bank_resolved: Dictionary = _bank_registry.resolve_event(event_path)
	var event_node: CodaBrowserNode = bank_resolved.get("node", null) as CodaBrowserNode
	var source_bank_id: String = str(bank_resolved.get("bank_id", ""))
	if event_node == null and _project != null:
		event_node = CodaEventResolverScript.resolve(_project, event_path)
	if event_node == null:
		_warn("event not found: '%s'" % event_path)
		return null
	return _start_event(event_node, event_path, params, source_bank_id)


func play_event_node(node: Variant, params: Dictionary = {}) -> CodaEventHandle:
	var bn := node as CodaBrowserNode
	if bn == null:
		_warn("play_event_node: node is null or wrong type")
		return null
	if bn.kind != CodaBrowserNode.Kind.EVENT:
		_warn("play_event_node: node '%s' is not an event" % bn.name)
		return null
	var path: String = ""
	if _project != null:
		path = CodaEventResolverScript.path_for_event_id(_project, bn.id)
	return _start_event(bn, path, params)


func stop(handle: CodaEventHandle, fade_ms: int = 0) -> void:
	if handle == null:
		return
	_graph_playback.drop_paused_preview_state(handle)
	if handle.is_timeline:
		if _timeline_dispatchers.has(handle):
			_timeline_dispatcher.finalize_handle(handle, fade_ms)
		elif handle._alive:
			_fade_out_and_finalize_handle(handle, fade_ms)
		return
	var was_alive: bool = handle._alive
	_graph_playback.unmark_plan_resume(handle)
	# Faded graph stops keep the pooled player alive until the tween ends. Without quiescing the
	# handle, a natural stream-finished during the fade can dequeue the next plan step.
	handle.params["_coda_plan"] = []
	if fade_ms > 0:
		handle._paused = true
	_graph_playback.stop_parallel_siblings(handle, fade_ms)
	if was_alive and fade_ms > 0:
		_fade_out_and_finalize_handle(
			handle, fade_ms, func() -> void: voice_finished.emit(handle)
		)
	else:
		_fade_out_and_finalize_handle(handle, fade_ms)
		if was_alive:
			voice_finished.emit(handle)


func stop_all() -> void:
	_graph_playback.finalize_all_paused_previews()
	# Mirror [_finalize_timeline_handle]: stop lane voices, drop dispatcher refs, then emit the
	# same handle/runtime signals as a normal timeline end. Otherwise `await handle.finished` and
	# `voice_finished` subscribers never run for timeline previews stopped via stop_all().
	var timeline_handles: Array = _timeline_dispatchers.keys()
	for h in timeline_handles:
		var hh2: CodaEventHandle = h as CodaEventHandle
		if hh2 == null or not _timeline_dispatchers.has(hh2):
			continue
		var d: Dictionary = _timeline_dispatchers[hh2]
		_timeline_dispatcher.stop_voices_dry(d, hh2)
		hh2.timeline_runtime = null
		_timeline_dispatchers.erase(hh2)
		if hh2._alive:
			hh2._alive = false
			hh2.finished.emit()
		voice_finished.emit(hh2)
	# Snapshot graph handles before stopping the pool so we can emit finished / voice_finished after
	# teardown. While the pool calls AudioStreamPlayer.stop(), finished may fire synchronously; see
	# _stop_all_in_progress in _on_voice_finished.
	var graph_handles: Array[CodaEventHandle] = []
	var graph_seen: Dictionary = {}
	for h in _active_handles.values():
		var gh: CodaEventHandle = h as CodaEventHandle
		if gh != null and not graph_seen.has(gh):
			graph_seen[gh] = true
			graph_handles.append(gh)
	# Plan-resume handles (pool-exhausted graph steps) are removed from _active_handles while
	# waiting for a free voice; stop_all must still finalize them like unload_bank/stop() do.
	for h in _graph_plan_resume_handles:
		var rh: CodaEventHandle = h as CodaEventHandle
		if rh != null and not graph_seen.has(rh):
			graph_seen[rh] = true
			graph_handles.append(rh)
	_stop_all_in_progress = true
	if _pool != null:
		_pool.stop_all()
	_stop_all_in_progress = false
	for gh2 in graph_handles:
		# BLEND siblings never get voice_started; skip voice_finished to avoid double teardown.
		if bool(gh2.params.get("_coda_is_sibling", false)):
			CodaVoiceWetLayersScript.stop_graph_wet_layers(gh2)
			gh2._alive = false
			continue
		CodaVoiceWetLayersScript.stop_graph_wet_layers(gh2)
		if gh2._alive:
			gh2._alive = false
			gh2.finished.emit()
		voice_finished.emit(gh2)
	_active_handles.clear()
	_timeline_dispatchers.clear()
	_timeline_voice_owner.clear()
	_timeline_voice_playback_gen.clear()
	_player_pending_finish_gen.clear()
	_graph_plan_resume_handles.clear()


func is_alive(handle: CodaEventHandle) -> bool:
	return handle != null and handle._alive


func set_parameter(handle: CodaEventHandle, name_or_id: String, value: Variant) -> void:
	if handle == null or not is_instance_valid(handle):
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null:
		handle.param_values[name_or_id] = value
		return
	# Resolve by id first, then by name (case-insensitive).
	var param_id: String = ""
	for p in event.event_parameters:
		if p.id == name_or_id:
			param_id = p.id
			break
	if param_id.is_empty():
		var lookup: String = name_or_id.to_lower()
		for p in event.event_parameters:
			if String(p.param_name).strip_edges().to_lower() == lookup:
				param_id = p.id
				break
	if param_id.is_empty():
		handle.param_values[name_or_id] = value
		_maybe_notify_music_state(handle, name_or_id)
		return
	var param: CodaEventParameter = _parameter_pipeline.find_event_param(event, param_id)
	var clamped: Variant = value if param == null else param.clamp_value(value)
	handle.param_values[param_id] = clamped
	var notify_key: String = param.param_name if param != null else name_or_id
	_maybe_notify_music_state(handle, notify_key)


func get_property(handle: CodaEventHandle, key: String, default_value: Variant = null) -> Variant:
	if handle == null or not is_instance_valid(handle):
		return default_value
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null:
		return default_value
	var val: Variant = CodaEventProperty.resolve_value(event.event_properties, key)
	if val == null:
		return default_value
	return val


func get_property_for_path(event_path: String, key: String, default_value: Variant = null) -> Variant:
	var event: CodaBrowserNode = _resolve_event_node(event_path)
	if event == null:
		return default_value
	var val: Variant = CodaEventProperty.resolve_value(event.event_properties, key)
	if val == null:
		return default_value
	return val


func _resolve_event_node(event_path: String) -> CodaBrowserNode:
	var bank_resolved: Dictionary = _bank_registry.resolve_event(event_path)
	var event_node: CodaBrowserNode = bank_resolved.get("node", null) as CodaBrowserNode
	if event_node == null and _project != null:
		event_node = CodaEventResolverScript.resolve(_project, event_path)
	return event_node


func _maybe_notify_music_state(handle: CodaEventHandle, name_or_id: String) -> void:
	if _timeline_music == null or handle == null or not handle.is_timeline:
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if not _timeline_music.should_notify_for_param(
		event, name_or_id, Callable(_parameter_pipeline, "find_event_param")
	):
		return
	notify_music_state_changed(handle)


func notify_global_param_applied(handle: CodaEventHandle, name_or_id: String) -> void:
	_maybe_notify_music_state(handle, name_or_id)


func set_global_parameter(name: String, value: Variant) -> void:
	_parameter_pipeline.set_global_parameter(name, value)


func apply_snapshot(snapshot_id: String, blend_ms: int = -1) -> bool:
	if _project == null or _snapshot_blender == null:
		return false
	var snap: CodaSnapshot = _project.find_snapshot_by_id(snapshot_id)
	if snap == null:
		return false
	var ms: int = blend_ms if blend_ms >= 0 else snap.blend_ms
	return _snapshot_blender.apply(snapshot_id, ms)


func notify_music_state_changed(handle: CodaEventHandle) -> void:
	if _timeline_music == null:
		return
	_timeline_music.notify_music_state_changed(
		handle, _timeline_dispatchers, Callable(_parameter_pipeline, "find_event_param")
	)


func spawn_timeline_segment_voice(
	handle: CodaEventHandle, d: Dictionary, entry: Dictionary, crossfade_ms: int = -1
) -> bool:
	if _timeline_music == null:
		return false
	return _timeline_music.spawn_segment_voice(
		handle, d, entry, Callable(_timeline_dispatcher, "spawn_lane_voice"), crossfade_ms
	)


func fade_out_timeline_voice(
	player: AudioStreamPlayer, fade_ms: int, on_complete: Callable = Callable()
) -> void:
	if _timeline_music != null:
		_timeline_music.fade_out_voice(player, fade_ms, on_complete)


func retire_timeline_voice(d: Dictionary, clip_id: String) -> void:
	_timeline_dispatcher.retire_lane_voice(d, clip_id)


func _fade_out_and_finalize_handle(
	handle: CodaEventHandle, fade_ms: int, on_complete: Callable = Callable()
) -> void:
	if handle == null:
		return
	if fade_ms <= 0:
		CodaVoiceWetLayersScript.stop_graph_wet_layers(handle)
		handle._stop_local(0)
		if on_complete.is_valid():
			on_complete.call()
		return
	var players: Array[AudioStreamPlayer] = _collect_handle_players(handle, fade_ms > 0)
	if players.is_empty():
		CodaVoiceWetLayersScript.stop_graph_wet_layers(handle)
		handle._stop_local(0)
		if on_complete.is_valid():
			on_complete.call()
		return
	var remaining: int = players.size()
	var on_one_done := func() -> void:
		remaining -= 1
		if remaining <= 0:
			CodaVoiceWetLayersScript.stop_graph_wet_layers(handle)
			handle._stop_local(0)
			if on_complete.is_valid():
				on_complete.call()
	for p in players:
		_voice_fader.fade_volume_db(p, -80.0, fade_ms, on_one_done)


func _collect_handle_players(handle: CodaEventHandle, include_idle: bool = false) -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	if handle == null:
		return out
	if handle.is_timeline and _timeline_dispatchers.has(handle):
		var d: Dictionary = _timeline_dispatchers[handle]
		for p in d.get("voices", {}).values():
			var pl: AudioStreamPlayer = p as AudioStreamPlayer
			if pl != null and is_instance_valid(pl) and (include_idle or pl.playing):
				out.append(pl)
	elif handle._player != null and is_instance_valid(handle._player):
		if include_idle or handle._player.playing:
			out.append(handle._player)
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		if sib._player != null and is_instance_valid(sib._player):
			if include_idle or sib._player.playing:
				out.append(sib._player)
	for p in handle.params.get("_coda_wet_players", []):
		var wet: AudioStreamPlayer = p as AudioStreamPlayer
		if wet != null and is_instance_valid(wet):
			if include_idle or wet.playing:
				out.append(wet)
	return out


func get_global_parameter(name: String, default_value: Variant = null) -> Variant:
	return _parameter_pipeline.get_global_parameter(name, default_value)


func active_voice_count() -> int:
	if _pool == null:
		return 0
	return _pool.active_count()


func load_bank(path: String) -> String:
	return _bank_registry.load_bank(path)


func unload_bank(bank_id: String) -> bool:
	return _bank_registry.unload_bank(bank_id)


func loaded_bank_ids() -> PackedStringArray:
	return _bank_registry.loaded_bank_ids()


func collect_runtime_handles() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for h in _active_handles.values():
		if h != null and not seen.has(h):
			seen[h] = true
			out.append(h)
	for h in _timeline_dispatchers.keys():
		if h != null and not seen.has(h):
			seen[h] = true
			out.append(h)
	for h in _graph_plan_resume_handles:
		if h != null and not seen.has(h):
			seen[h] = true
			out.append(h)
	for h in _graph_playback.get_paused_graph_handles():
		if h != null and not seen.has(h):
			seen[h] = true
			out.append(h)
	return out


func _start_event(
	event: CodaBrowserNode, path: String, params: Dictionary, source_bank_id: String = ""
) -> CodaEventHandle:
	var play_opts: CodaPlayOptions = CodaPlayOptionsScript.from_params_dict(params)
	if play_opts.exclusive_preview:
		stop_all()
	params = play_opts.to_params_dict()
	if event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE:
		return _timeline_dispatcher.start_timeline_event(event, path, params, source_bank_id)
	# Build the parameter snapshot used to plan the graph (Switch/Blend look this up).
	var live_params: Dictionary = _parameter_pipeline.build_param_values(event, params)
	# Stamp routing on params so graph voices use the right bus per voice.
	if play_opts.voice_bus.is_empty():
		play_opts.voice_bus = resolve_bus_name_for_event(event)
	params = play_opts.to_params_dict()
	# Resolve the play list. Prefer the v2 graph; fall back to legacy flat list (random pick) if missing.
	var plan_entries: Array = []
	var graph_event_loop: bool = false
	if event.event_graph != null:
		var planned: Dictionary = CodaGraphSchedulerScript.plan(event.event_graph, live_params)
		plan_entries = planned.get("entries", []) as Array
		graph_event_loop = bool(planned.get("event_loop", false))
	if plan_entries.is_empty() and event.event_audio_paths.size() > 0:
		var legacy_path: String = event.event_audio_paths[randi() % event.event_audio_paths.size()]
		plan_entries = [{
			"audio_path": legacy_path,
			"volume_db": 0.0,
			"pitch_scale": 1.0,
			"loop": false,
			"sound_id": "",
			"blend_weight": 1.0,
		}]
	if plan_entries.is_empty():
		_warn("event '%s' produced no playable sounds" % event.name)
		return null
	return _graph_playback.start_graph_event(
		event, path, params, source_bank_id, live_params, plan_entries, graph_event_loop
	)


func _on_voice_finished(player: AudioStreamPlayer) -> void:
	if CodaPooledVoiceLifecycleScript.is_stale_finish(
		player, _player_pending_finish_gen, _orphaned_finish_gens
	):
		return
	var key: int = player.get_instance_id()
	if int(_timeline_voice_playback_gen.get(key, -1)) == int(player.get_meta(&"_coda_playback_gen", -1)):
		_timeline_dispatcher.on_voice_finished(player, key)
		return
	_graph_playback.on_voice_finished_for_graph(player, key, _stop_all_in_progress)


func _warn(msg: String) -> void:
	push_warning("Coda: %s" % msg)


func resync_timeline_preview_for_event(event_id: String) -> void:
	_timeline_dispatcher.resync_preview_for_event(event_id)


func get_active_timeline_handle_for_event(event_id: String) -> CodaEventHandle:
	return _timeline_dispatcher.active_handle_for_event(event_id)


func runtime_warn(msg: String) -> void:
	_warn(msg)


func runtime_report_pool_exhausted(context: Dictionary) -> void:
	var msg: String = String(context.get("detail", "voice pool exhausted"))
	var rate_key: String = "%s|%s" % [str(context.get("mode", "")), msg]
	var now_ms: int = Time.get_ticks_msec()
	if _pool_warn_last_ms.has(rate_key):
		var last_ms: int = int(_pool_warn_last_ms[rate_key])
		if now_ms - last_ms < 1000:
			return
	_pool_warn_last_ms[rate_key] = now_ms
	push_warning("Coda: %s" % msg)
	voice_pool_exhausted.emit(context)
	if is_editor_preview:
		NexusCodaLogScript.warn(RUNTIME_LOG_SCOPE, msg)


func runtime_pool_size() -> int:
	if _pool == null:
		return 0
	return _pool.pool_size


func runtime_pool() -> CodaVoicePool:
	return _pool


func runtime_allocate_handle_id() -> int:
	var id: int = _next_handle_id
	_next_handle_id += 1
	return id


func runtime_emit_voice_started(handle: CodaEventHandle) -> void:
	voice_started.emit(handle)


func runtime_emit_voice_finished(handle: CodaEventHandle) -> void:
	voice_finished.emit(handle)


func get_loaded_banks() -> Dictionary:
	return _bank_registry.get_loaded_banks()


func get_parameter_pipeline() -> CodaRuntimeParameterPipeline:
	return _parameter_pipeline


func get_bus_sync() -> CodaRuntimeBusSync:
	return _bus_sync


func get_voice_players(handle: CodaEventHandle) -> Array[AudioStreamPlayer]:
	return _collect_handle_players(handle, true)


func get_player_pending_finish_gen() -> Dictionary:
	return _player_pending_finish_gen


func get_active_handles() -> Dictionary:
	return _active_handles


func get_graph_plan_resume_handles() -> Array[CodaEventHandle]:
	return _graph_plan_resume_handles


func get_timeline_dispatchers() -> Dictionary:
	return _timeline_dispatchers


func get_timeline_voice_owner() -> Dictionary:
	return _timeline_voice_owner


func get_timeline_voice_playback_gen() -> Dictionary:
	return _timeline_voice_playback_gen


func runtime_orphaned_finish_gens() -> Dictionary:
	return _orphaned_finish_gens


func runtime_bump_playback_gen() -> int:
	var gen: int = _next_playback_gen
	_next_playback_gen += 1
	return gen


func runtime_begin_player_voice(player: AudioStreamPlayer) -> int:
	return CodaPooledVoiceLifecycleScript.begin_player_voice(
		player,
		_timeline_dispatchers,
		_timeline_voice_owner,
		_timeline_voice_playback_gen,
		_active_handles,
		_player_pending_finish_gen,
		_orphaned_finish_gens,
		runtime_bump_playback_gen(),
		Callable(_timeline_dispatcher, "clear_voice_player_meta"),
		Callable(_timeline_dispatcher, "free_player_fx_bus"),
	)


func pause_graph_preview(handle: CodaEventHandle) -> void:
	_graph_playback.pause_graph_preview(handle)


func resume_graph_preview(handle: CodaEventHandle) -> void:
	_graph_playback.resume_graph_preview(handle)


func pause_timeline_preview(handle: CodaEventHandle) -> void:
	_timeline_dispatcher.pause_preview(handle)


func resume_timeline_preview(handle: CodaEventHandle) -> void:
	_timeline_dispatcher.resume_preview(handle)

