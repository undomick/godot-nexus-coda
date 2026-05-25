@tool
extends Node
class_name CodaRuntime

## Runtime entry point. Used both as the autoload "Coda" in running games and as an
## editor-side preview instance owned by the plugin. Both modes share this implementation.
##
## Public API:
##   Coda.set_project(state: CodaState)     # editor or boot-time wiring
##   Coda.play(path, params := {})          # returns CodaEventHandle or null
##   Coda.play_event_node(node, params)     # play a specific browser node directly
##   Coda.stop(handle, fade_ms := 0)
##   Coda.stop_all()
##   Coda.is_alive(handle)
##   Coda.set_parameter(handle, name, value)
##   Coda.set_global_parameter(name, value)
##   Coda.apply_snapshot(snapshot_id, blend_ms := -1)
##   Coda.notify_music_state_changed(handle)

signal voice_started(handle: CodaEventHandle)
signal voice_finished(handle: CodaEventHandle)
signal voice_pool_exhausted(context: Dictionary)
signal marker_reached(handle: CodaEventHandle, marker_id: String)
signal project_loaded(state: CodaState)

const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaBrowserNodeScript := preload("res://addons/nexus_coda/editor/browser/coda_browser_node.gd")
const CodaVoicePoolScript := preload("res://addons/nexus_coda/runtime/coda_voice_pool.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaEventResolverScript := preload("res://addons/nexus_coda/runtime/coda_event_resolver.gd")
const CodaGraphSchedulerScript := preload("res://addons/nexus_coda/runtime/coda_graph_scheduler.gd")
const CodaTimelineSchedulerScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_scheduler.gd"
)
const CodaFxBusHelperScript := preload("res://addons/nexus_coda/runtime/coda_fx_bus_helper.gd")
const CodaBankExportScript := preload("res://addons/nexus_coda/editor/io/coda_bank_export.gd")
const CodaBusScript := preload("res://addons/nexus_coda/editor/browser/coda_bus.gd")
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
const NexusCodaLogScript := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")

const RUNTIME_LOG_SCOPE := "runtime"

@export var bus_name: String = "Master"
@export var is_editor_preview: bool = false

var _project: CodaState = null
var _pool: CodaVoicePool
var _active_handles: Dictionary = {}  ## player_instance_id -> CodaEventHandle
var _next_handle_id: int = 1
## Loaded banks: bank_id (String) -> { "bank_name": String, "events_by_path": { path: CodaBrowserNode } }
var _loaded_banks: Dictionary = {}
## Active timeline-mode handles: handle -> dispatcher state. Each entry tracks the timeline
## cursor, currently-playing per-clip voices and which clips have already been fired in this
## (loop) iteration so the same clip is not retriggered every frame.
var _timeline_dispatchers: Dictionary = {}
## player_instance_id -> CodaEventHandle (timeline-mode only). Lets [code]_on_voice_finished[/code]
## resolve a finished timeline voice without going through [code]_active_handles[/code].
var _timeline_voice_owner: Dictionary = {}
## player_instance_id -> playback generation stamped at the last [method AudioStreamPlayer.play]
## on that pooled player. Guards against stale [signal AudioStreamPlayer.finished] after reuse.
var _timeline_voice_playback_gen: Dictionary = {}
## Monotonic generation per pooled-player play; prior gens are marked orphaned on supersede.
var _next_playback_gen: int = 1
var _player_pending_finish_gen: Dictionary = {}  ## player_instance_id -> int
var _orphaned_finish_gens: Dictionary = {}  ## gen -> true
## True while [method stop_all] is iterating pooled [AudioStreamPlayer]s. A synthetic
## [signal AudioStreamPlayer.finished] from [method AudioStreamPlayer.stop] must not dequeue graph
## plan entries or new voices would start during teardown.
var _stop_all_in_progress: bool = false
## Graph handles blocked on voice-pool exhaustion (mid-sequence or loop restart). Retried each frame.
var _graph_plan_resume_handles: Array[CodaEventHandle] = []
## Graph previews paused via [method pause_graph_preview]. Removed from [code]_active_handles[/code] while
## stopped so the pool stays available; [method stop_all] must still finalize these handles.
var _paused_graph_handles: Array[CodaEventHandle] = []
var _voice_fader: CodaVoiceFader
var _segment_driver: CodaTimelineSegmentDriver
var _snapshot_blender: CodaSnapshotBlender
var _timeline_music: CodaTimelineMusicController
var _timeline_dispatcher: CodaTimelineDispatcher
var _graph_playback: CodaGraphPlaybackRuntime
var _parameter_pipeline: CodaRuntimeParameterPipeline
var _bus_sync: CodaRuntimeBusSync
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
	_snapshot_blender = CodaSnapshotBlenderScript.new()
	_snapshot_blender.setup(_project, Callable(_bus_sync, "sync_buses"))
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


func set_project(project: Variant) -> void:
	# Editor project loads and gameplay project swaps must not keep dispatchers tied to the
	# previous CodaState (timeline cursors, graph plans, pooled players).
	stop_all()
	if project != null:
		# Loaded banks override play() resolution; clear them when wiring a new project so stale
		# bank events cannot shadow the new CodaState.
		_loaded_banks.clear()
	if _project != null:
		if _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.disconnect(_on_project_structure_changed)
		if _project.project_dirty.is_connected(_on_project_dirty_sync_buses):
			_project.project_dirty.disconnect(_on_project_dirty_sync_buses)
	if project == null:
		_project = null
		if _snapshot_blender != null:
			_snapshot_blender.setup(_project, Callable(_bus_sync, "sync_buses"))
			_snapshot_blender.clear()
		_bus_sync.apply_loaded_bank_buses()
		project_loaded.emit(null)
		return
	_project = project as CodaState
	if _snapshot_blender != null:
		_snapshot_blender.setup(_project, Callable(_bus_sync, "sync_buses"))
	_bus_sync.sync_buses()
	if _project != null:
		if not _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.connect(_on_project_structure_changed)
		if not _project.project_dirty.is_connected(_on_project_dirty_sync_buses):
			_project.project_dirty.connect(_on_project_dirty_sync_buses)
	project_loaded.emit(_project)


func _on_project_structure_changed() -> void:
	_bus_sync.apply_loaded_bank_buses()


func _on_project_dirty_sync_buses() -> void:
	_bus_sync.apply_loaded_bank_buses()


func resolve_bus_name_for_event(event: CodaBrowserNode) -> String:
	return _bus_sync.resolve_bus_name_for_event(event)


func resolve_godot_bus_name_for_coda_bus_id(coda_bus_id: String) -> String:
	return _bus_sync.resolve_godot_bus_name_for_coda_bus_id(coda_bus_id)


func get_project() -> CodaState:
	return _project


func play(event_path: String, params: Dictionary = {}) -> CodaEventHandle:
	# Loaded banks win over the live project so gameplay is deterministic across builds.
	var bank_resolved: Dictionary = _resolve_in_loaded_banks(event_path)
	var event_node: CodaBrowserNode = bank_resolved.get("node", null) as CodaBrowserNode
	var source_bank_id: String = str(bank_resolved.get("bank_id", ""))
	if event_node == null and _project != null:
		event_node = CodaEventResolverScript.resolve(_project, event_path)
	if event_node == null:
		_warn("event not found: '%s'" % event_path)
		return null
	return _start_event(event_node, event_path, params, source_bank_id)


func _resolve_in_loaded_banks(event_path: String) -> Dictionary:
	var p: String = event_path.strip_edges()
	if p.begins_with("events/"):
		p = p.substr(7)
	# Later load_bank() calls should override earlier banks (DLC / hotfix), matching
	# _rebuild_bus_id_map_from_loaded_banks where the last manifest wins per bus id.
	var bank_ids: Array = _loaded_banks.keys()
	for i in range(bank_ids.size() - 1, -1, -1):
		var bank_id: String = String(bank_ids[i])
		var entry: Dictionary = _loaded_banks[bank_id]
		var by_path: Dictionary = entry.get("events_by_path", {})
		if by_path.has(p):
			return {"node": by_path[p] as CodaBrowserNode, "bank_id": bank_id}
	return {"node": null, "bank_id": ""}


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
	_drop_paused_graph_preview_state(handle)
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
	_fade_out_and_finalize_handle(handle, fade_ms)
	if was_alive:
		voice_finished.emit(handle)


func stop_all() -> void:
	_finalize_all_paused_graph_previews()
	# Mirror [_finalize_timeline_handle]: stop lane voices, drop dispatcher refs, then emit the
	# same handle/runtime signals as a normal timeline end. Otherwise `await handle.finished` and
	# `voice_finished` subscribers never run for timeline previews stopped via stop_all().
	var timeline_handles: Array = _timeline_dispatchers.keys()
	for h in timeline_handles:
		var hh2: CodaEventHandle = h as CodaEventHandle
		if hh2 == null or not _timeline_dispatchers.has(hh2):
			continue
		var d: Dictionary = _timeline_dispatchers[hh2]
		_timeline_dispatcher.stop_voices(d, hh2)
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
		# BLEND parallel legs use sibling handles that never receive [signal voice_started]. Emitting
		# [signal voice_finished] for them here would duplicate teardown for one [method play] call.
		if bool(gh2.params.get("_coda_is_sibling", false)):
			gh2._alive = false
			continue
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


func _maybe_notify_music_state(handle: CodaEventHandle, name_or_id: String) -> void:
	if _timeline_music == null or handle == null or not handle.is_timeline:
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if not _timeline_music.should_notify_for_param(
		event, name_or_id, Callable(_parameter_pipeline, "find_event_param")
	):
		return
	notify_music_state_changed(handle)


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


func _fade_out_and_finalize_handle(handle: CodaEventHandle, fade_ms: int) -> void:
	if handle == null:
		return
	if fade_ms <= 0:
		handle._stop_local(0)
		return
	var players: Array[AudioStreamPlayer] = _collect_handle_players(handle)
	if players.is_empty():
		handle._stop_local(0)
		return
	var remaining: int = players.size()
	var on_one_done := func() -> void:
		remaining -= 1
		if remaining <= 0:
			handle._stop_local(0)
	for p in players:
		_voice_fader.fade_volume_db(p, -80.0, fade_ms, on_one_done)


func _collect_handle_players(handle: CodaEventHandle) -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	if handle == null:
		return out
	if handle.is_timeline and _timeline_dispatchers.has(handle):
		var d: Dictionary = _timeline_dispatchers[handle]
		for p in d.get("voices", {}).values():
			var pl: AudioStreamPlayer = p as AudioStreamPlayer
			if pl != null and is_instance_valid(pl) and pl.playing:
				out.append(pl)
	elif handle._player != null and is_instance_valid(handle._player) and handle._player.playing:
		out.append(handle._player)
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		if sib._player != null and is_instance_valid(sib._player) and sib._player.playing:
			out.append(sib._player)
	return out


func get_global_parameter(name: String, default_value: Variant = null) -> Variant:
	return _parameter_pipeline.get_global_parameter(name, default_value)


func active_voice_count() -> int:
	if _pool == null:
		return 0
	return _pool.active_count()


## Loads a `.coda_bank` and registers its events for playback.
## Returns the loaded bank id on success, or empty string on failure.
func load_bank(path: String) -> String:
	var manifest_raw: Variant = CodaBankExportScript.read_manifest_from_path(path)
	if manifest_raw is String:
		_warn(str(manifest_raw))
		return ""
	var manifest: Dictionary = manifest_raw
	var bank_id: String = str(manifest.get("bank_id", ""))
	if bank_id.is_empty():
		_warn("bank file has no bank_id")
		return ""
	var events_by_path: Dictionary = {}
	for event_raw in manifest.get("events", []) as Array:
		if not (event_raw is Dictionary):
			continue
		var event_dict: Dictionary = event_raw
		var event_path: String = str(event_dict.get("__path", ""))
		var node: CodaBrowserNode = CodaBrowserNode.from_dictionary(event_dict)
		if node == null or event_path.is_empty():
			continue
		events_by_path[event_path] = node
	var bank_bus_root: CodaBus = null
	var buses_raw: Variant = manifest.get("buses", null)
	if buses_raw is Dictionary:
		bank_bus_root = CodaBusScript.from_dictionary(buses_raw as Dictionary)
	# Re-loading an existing bank_id must move it to the end of insertion order. Godot keeps
	# key position on assignment, but later load_bank / hotfix wins rely on reverse iteration.
	if _loaded_banks.has(bank_id):
		_stop_voices_for_bank(bank_id)
		_loaded_banks.erase(bank_id)
	_loaded_banks[bank_id] = {
		"bank_name": str(manifest.get("bank_name", "Bank")),
		"events_by_path": events_by_path,
		"bus_root": bank_bus_root,
	}
	_bus_sync.apply_loaded_bank_buses()
	return bank_id


## Unloads a previously-loaded bank by id. No-op if id is unknown.
func unload_bank(bank_id: String) -> bool:
	if not _loaded_banks.has(bank_id):
		return false
	_stop_voices_for_bank(bank_id)
	_loaded_banks.erase(bank_id)
	_bus_sync.apply_loaded_bank_buses()
	return true


func loaded_bank_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _loaded_banks.keys():
		out.append(String(k))
	return out


func _stop_voices_for_bank(bank_id: String) -> void:
	if bank_id.is_empty():
		return
	var seen: Dictionary = {}
	for item in _collect_runtime_handles():
		var h: CodaEventHandle = item as CodaEventHandle
		if h == null or seen.has(h):
			continue
		if h.source_bank_id != bank_id:
			continue
		seen[h] = true
		stop(h)


func _collect_runtime_handles() -> Array:
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
	for h in _paused_graph_handles:
		if h != null and not seen.has(h):
			seen[h] = true
			out.append(h)
	return out


func _start_event(
	event: CodaBrowserNode, path: String, params: Dictionary, source_bank_id: String = ""
) -> CodaEventHandle:
	var exclusive_preview: bool = bool(params.get("_coda_exclusive_preview", false))
	params = params.duplicate()
	params.erase("_coda_exclusive_preview")
	# Editor panels pass this so a pinned Player preview cannot leave another event's timeline
	# dispatcher running and lose lane voices when the voice pool reuses a player.
	if exclusive_preview:
		stop_all()
	if event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE:
		return _timeline_dispatcher.start_timeline_event(event, path, params, source_bank_id)
	# Build the parameter snapshot used to plan the graph (Switch/Blend look this up).
	var live_params: Dictionary = _parameter_pipeline.build_param_values(event, params)
	# Stamp routing on params so graph voices use the right bus per voice.
	params = params.duplicate()
	params["_coda_voice_bus"] = resolve_bus_name_for_event(event)
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
	return _loaded_banks


func get_parameter_pipeline() -> CodaRuntimeParameterPipeline:
	return _parameter_pipeline


func get_bus_sync() -> CodaRuntimeBusSync:
	return _bus_sync


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
	if player != null and is_instance_valid(player):
		_voice_fader.cancel(player)
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


func _drop_paused_graph_preview_state(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	var idx: int = _paused_graph_handles.find(handle)
	if idx >= 0:
		_paused_graph_handles.remove_at(idx)
	handle.params.erase("_coda_graph_pause_snapshot")


func _finalize_all_paused_graph_previews() -> void:
	for item in _paused_graph_handles.duplicate():
		var h: CodaEventHandle = item as CodaEventHandle
		if h == null:
			continue
		_finalize_paused_graph_preview(h)
	_paused_graph_handles.clear()


func _finalize_paused_graph_preview(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	_drop_paused_graph_preview_state(handle)
	if not handle._paused:
		return
	handle._paused = false
	_graph_playback.unmark_plan_resume(handle)
	_graph_playback.stop_parallel_siblings(handle)
	handle.clear_player_binding()
	var was_alive: bool = handle._alive
	if was_alive:
		handle._alive = false
		handle.finished.emit()
	voice_finished.emit(handle)


func _snapshot_graph_pause_player(
	voice: CodaEventHandle, snapshot: Dictionary
) -> void:
	if voice._player == null or not is_instance_valid(voice._player):
		return
	var pk: int = voice._player.get_instance_id()
	var pos: float = 0.0
	if voice._player.playing:
		pos = voice._player.get_playback_position()
	_active_handles.erase(pk)
	if voice._player.playing:
		voice._player.stop()
	snapshot[str(pk)] = {
		"position": pos,
		"gen": int(voice._player.get_meta(&"_coda_playback_gen", -1)),
	}


## Graph preview: stop pooled players on pause so [code]stream_paused[/code] voices do not pin the pool.
func pause_graph_preview(handle: CodaEventHandle) -> void:
	if handle == null or handle.is_timeline:
		return
	var snapshot: Dictionary = {}
	_snapshot_graph_pause_player(handle, snapshot)
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		_snapshot_graph_pause_player(sib, snapshot)
	handle.params["_coda_graph_pause_snapshot"] = snapshot
	if not _paused_graph_handles.has(handle):
		_paused_graph_handles.append(handle)


## Graph preview: resume voices stopped by [method pause_graph_preview].
func resume_graph_preview(handle: CodaEventHandle) -> void:
	if handle == null or handle.is_timeline:
		return
	_drop_paused_graph_preview_state(handle)
	var snapshot: Variant = handle.params.get("_coda_graph_pause_snapshot", {})
	handle.params.erase("_coda_graph_pause_snapshot")
	if typeof(snapshot) != TYPE_DICTIONARY:
		return
	var snap: Dictionary = snapshot as Dictionary
	if snap.is_empty():
		return
	var expected: int = snap.size()
	var resumed: int = 0
	if _resume_graph_paused_player(handle, handle, snap):
		resumed += 1
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		if _resume_graph_paused_player(handle, sib, snap):
			resumed += 1
	# Partial resume (e.g. voice pool reused a paused BLEND leg) leaves a wrong mix â€” stop cleanly.
	if resumed != expected and handle._alive:
		stop(handle)


func _resume_graph_paused_player(
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
	var at: float = maxf(0.0, float(saved_d.get("position", 0.0)))
	voice._player.play(at)
	var gen: int = int(voice._player.get_meta(&"_coda_playback_gen", -1))
	if voice == owner:
		owner.params["_coda_playback_gen"] = gen
		_active_handles[voice._player.get_instance_id()] = owner
	else:
		voice.params["_coda_playback_gen"] = gen
		_active_handles[voice._player.get_instance_id()] = voice
	return true


func pause_timeline_preview(handle: CodaEventHandle) -> void:
	_timeline_dispatcher.pause_preview(handle)


func resume_timeline_preview(handle: CodaEventHandle) -> void:
	_timeline_dispatcher.resume_preview(handle)

