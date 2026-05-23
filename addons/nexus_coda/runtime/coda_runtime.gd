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

signal voice_started(handle: CodaEventHandle)
signal voice_finished(handle: CodaEventHandle)

const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaBrowserNodeScript := preload("res://addons/nexus_coda/editor/browser/coda_browser_node.gd")
const CodaVoicePoolScript := preload("res://addons/nexus_coda/runtime/coda_voice_pool.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaEventResolverScript := preload("res://addons/nexus_coda/runtime/coda_event_resolver.gd")
const CodaGraphSchedulerScript := preload("res://addons/nexus_coda/runtime/coda_graph_scheduler.gd")
const CodaTimelineSchedulerScript := preload(
	"res://addons/nexus_coda/runtime/coda_timeline_scheduler.gd"
)
const CodaModulationScript := preload("res://addons/nexus_coda/editor/browser/coda_modulation.gd")
const CodaAudioBusMirrorScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_mirror.gd")
const CodaFxBusHelperScript := preload("res://addons/nexus_coda/runtime/coda_fx_bus_helper.gd")
const CodaBankExportScript := preload("res://addons/nexus_coda/editor/io/coda_bank_export.gd")
const CodaBusScript := preload("res://addons/nexus_coda/editor/browser/coda_bus.gd")

const RUNTIME_LOG_SCOPE := "runtime"

@export var bus_name: String = "Master"

var _project: CodaState = null
var _pool: CodaVoicePool
var _active_handles: Dictionary = {}  ## player_instance_id -> CodaEventHandle
var _global_params: Dictionary = {}
var _next_handle_id: int = 1
## Map of coda_bus_id (String) -> godot_bus_name (String); refreshed on project change.
var _bus_id_to_godot_name: Dictionary = {}
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


func _ready() -> void:
	if _pool == null:
		_pool = CodaVoicePoolScript.new()
		_pool.name = "VoicePool"
		add_child(_pool)
	if not _pool.voice_finished.is_connected(_on_voice_finished):
		_pool.voice_finished.connect(_on_voice_finished)
	set_process(true)


func _process(delta: float) -> void:
	if not _timeline_dispatchers.is_empty():
		_tick_timeline_dispatchers(delta)
	if not _graph_plan_resume_handles.is_empty():
		_resume_pending_graph_plans()
	if _active_handles.is_empty():
		return
	for h in _active_handles.values():
		var hh: CodaEventHandle = h as CodaEventHandle
		if hh == null or not hh._alive:
			continue
		_advance_smoothing(hh, delta)
		_apply_modulations(hh)


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
		_apply_loaded_bank_buses()
		return
	_project = project as CodaState
	_sync_buses()
	if _project != null:
		if not _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.connect(_on_project_structure_changed)
		if not _project.project_dirty.is_connected(_on_project_dirty_sync_buses):
			_project.project_dirty.connect(_on_project_dirty_sync_buses)


func _on_project_structure_changed() -> void:
	_apply_loaded_bank_buses()


func _on_project_dirty_sync_buses() -> void:
	_apply_loaded_bank_buses()


func _sync_buses() -> void:
	if _project == null or _project.bus_root == null:
		_rebuild_bus_id_map_from_loaded_banks()
		return
	_bus_id_to_godot_name = CodaAudioBusMirrorScript.sync_to_audio_server(_project.bus_root)


## Bank-only gameplay may load multiple .coda_bank files. Merge each manifest bus tree into
## AudioServer and union id→name maps so earlier banks keep routing after later loads/unloads.
func _apply_loaded_bank_buses() -> void:
	if _project != null:
		_sync_buses()
	else:
		_rebuild_bus_id_map_from_loaded_banks()
		return
	# Project + load_bank(): overlay each manifest bus tree (later banks win per coda bus id).
	if _loaded_banks.is_empty():
		return
	for bank_id in _loaded_banks.keys():
		var entry: Dictionary = _loaded_banks[bank_id]
		var root: Variant = entry.get("bus_root", null)
		if root is CodaBus:
			var partial: Dictionary = CodaAudioBusMirrorScript.sync_to_audio_server(
				root as CodaBus, false
			)
			for cid in partial.keys():
				_bus_id_to_godot_name[cid] = partial[cid]


func _rebuild_bus_id_map_from_loaded_banks() -> void:
	_bus_id_to_godot_name.clear()
	if _loaded_banks.is_empty():
		return
	for bank_id in _loaded_banks.keys():
		var entry: Dictionary = _loaded_banks[bank_id]
		var root: Variant = entry.get("bus_root", null)
		if root is CodaBus:
			var partial: Dictionary = CodaAudioBusMirrorScript.sync_to_audio_server(
				root as CodaBus, false
			)
			for cid in partial.keys():
				_bus_id_to_godot_name[cid] = partial[cid]


func resolve_bus_name_for_event(event: CodaBrowserNode) -> String:
	if event == null:
		return bus_name
	if not event.event_output_bus_id.is_empty():
		var name: Variant = _bus_id_to_godot_name.get(event.event_output_bus_id, null)
		if name != null:
			return String(name)
	return bus_name


func resolve_godot_bus_name_for_coda_bus_id(coda_bus_id: String) -> String:
	var tid: String = String(coda_bus_id).strip_edges()
	if tid.is_empty():
		return ""
	var v: Variant = _bus_id_to_godot_name.get(tid, null)
	if v == null:
		return ""
	return String(v)


func get_project() -> CodaState:
	return _project


func play(event_path: String, params: Dictionary = {}) -> CodaEventHandle:
	# Loaded banks win over the live project so gameplay is deterministic across builds.
	var event_node: CodaBrowserNode = _resolve_in_loaded_banks(event_path)
	if event_node == null and _project != null:
		event_node = CodaEventResolverScript.resolve(_project, event_path)
	if event_node == null:
		_warn("event not found: '%s'" % event_path)
		return null
	return _start_event(event_node, event_path, params)


func _resolve_in_loaded_banks(event_path: String) -> CodaBrowserNode:
	var p: String = event_path.strip_edges()
	if p.begins_with("events/"):
		p = p.substr(7)
	# Later load_bank() calls should override earlier banks (DLC / hotfix), matching
	# _rebuild_bus_id_map_from_loaded_banks where the last manifest wins per bus id.
	var bank_ids: Array = _loaded_banks.keys()
	for i in range(bank_ids.size() - 1, -1, -1):
		var entry: Dictionary = _loaded_banks[bank_ids[i]]
		var by_path: Dictionary = entry.get("events_by_path", {})
		if by_path.has(p):
			return by_path[p] as CodaBrowserNode
	return null


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
			_finalize_timeline_handle(handle)
		elif handle._alive:
			handle._stop_local(fade_ms)
		return
	var was_alive: bool = handle._alive
	_unmark_graph_plan_resume(handle)
	_stop_graph_parallel_siblings(handle)
	handle._stop_local(fade_ms)
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
		_stop_timeline_voices(d, hh2)
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
	return handle != null and handle.is_playing()


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
		# Fall back to using the supplied key as-is so users can pre-set values without param defs.
		handle.param_values[name_or_id] = value
		return
	var param: CodaEventParameter = _find_event_param(event, param_id)
	var clamped: Variant = value if param == null else param.clamp_value(value)
	handle.param_values[param_id] = clamped


func set_global_parameter(name: String, value: Variant) -> void:
	if name.is_empty():
		return
	_global_params[name] = value


func _find_event_param(event: CodaBrowserNode, param_id: String) -> CodaEventParameter:
	if event == null:
		return null
	for p in event.event_parameters:
		if p.id == param_id:
			return p
	return null


func _build_param_values(event: CodaBrowserNode, user_params: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	if event != null:
		for p in event.event_parameters:
			values[p.id] = CodaEventParameter.to_float_value(p.default_value)
	# User overrides keyed by name or id.
	for key in user_params.keys():
		var k: String = String(key)
		if k.begins_with("_coda_"):
			continue
		var val: Variant = user_params[key]
		if event != null:
			var match_id: String = ""
			for p in event.event_parameters:
				if p.id == k:
					match_id = p.id
					break
			if match_id.is_empty():
				var lookup: String = k.to_lower()
				for p in event.event_parameters:
					if String(p.param_name).strip_edges().to_lower() == lookup:
						match_id = p.id
						break
			if not match_id.is_empty():
				values[match_id] = CodaEventParameter.to_float_value(val)
				continue
		values[k] = CodaEventParameter.to_float_value(val)
	return values


func _advance_smoothing(handle: CodaEventHandle, delta: float) -> void:
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null:
		handle.param_values_smoothed = handle.param_values.duplicate()
		return
	for p in event.event_parameters:
		var target: float = float(handle.param_values.get(p.id, CodaEventParameter.to_float_value(p.default_value)))
		var current: float = float(handle.param_values_smoothed.get(p.id, target))
		if p.smoothing_ms <= 0.0:
			handle.param_values_smoothed[p.id] = target
			continue
		# First-order exponential glide: alpha = 1 - exp(-delta / tau).
		var tau: float = max(0.001, p.smoothing_ms / 1000.0)
		var alpha: float = clampf(1.0 - exp(-delta / tau), 0.0, 1.0)
		handle.param_values_smoothed[p.id] = lerp(current, target, alpha)


func _apply_modulations(handle: CodaEventHandle) -> void:
	if handle._player == null or not is_instance_valid(handle._player):
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null or event.event_modulations.is_empty():
		# No modulations; still honor blend_weight.
		_apply_voice_base_with_blend(handle)
		return
	var sound_id: String = handle.current_sound_id
	var voice_volume_db: float = handle.base_volume_db
	var voice_pitch: float = handle.base_pitch_scale
	for m in event.event_modulations:
		if m.target_node_id != sound_id:
			continue
		var src_val: float = float(handle.param_values_smoothed.get(m.source_param_id, 0.0))
		var out_val: float = m.evaluate(src_val)
		match m.target_property:
			CodaModulationScript.TargetProperty.SOUND_VOLUME_DB:
				voice_volume_db += out_val
			CodaModulationScript.TargetProperty.SOUND_PITCH_SCALE:
				voice_pitch *= out_val
			# RANDOM_WEIGHT, SWITCH_SELECTED_BRANCH, BLEND_MIX only affect the next plan(); ignored here.
	# Apply blend weight as additional dB attenuation (linearGain → dB).
	if handle.blend_weight < 1.0 and handle.blend_weight > 0.0:
		voice_volume_db += linear_to_db(handle.blend_weight)
	elif handle.blend_weight <= 0.0:
		voice_volume_db = -80.0
	handle._player.volume_db = voice_volume_db
	handle._player.pitch_scale = max(0.05, voice_pitch)


func _apply_voice_base_with_blend(handle: CodaEventHandle) -> void:
	if handle._player == null or not is_instance_valid(handle._player):
		return
	var voice_volume_db: float = handle.base_volume_db
	if handle.blend_weight < 1.0 and handle.blend_weight > 0.0:
		voice_volume_db += linear_to_db(handle.blend_weight)
	elif handle.blend_weight <= 0.0:
		voice_volume_db = -80.0
	handle._player.volume_db = voice_volume_db


static func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * (log(linear) / log(10.0))


func get_global_parameter(name: String, default_value: Variant = null) -> Variant:
	return _global_params.get(name, default_value)


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
		_loaded_banks.erase(bank_id)
	_loaded_banks[bank_id] = {
		"bank_name": str(manifest.get("bank_name", "Bank")),
		"events_by_path": events_by_path,
		"bus_root": bank_bus_root,
	}
	_apply_loaded_bank_buses()
	return bank_id


## Unloads a previously-loaded bank by id. No-op if id is unknown.
func unload_bank(bank_id: String) -> bool:
	if not _loaded_banks.has(bank_id):
		return false
	_loaded_banks.erase(bank_id)
	_apply_loaded_bank_buses()
	return true


func loaded_bank_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _loaded_banks.keys():
		out.append(String(k))
	return out


func _start_event(event: CodaBrowserNode, path: String, params: Dictionary) -> CodaEventHandle:
	var exclusive_preview: bool = bool(params.get("_coda_exclusive_preview", false))
	params = params.duplicate()
	params.erase("_coda_exclusive_preview")
	# Editor panels pass this so a pinned Player preview cannot leave another event's timeline
	# dispatcher running and lose lane voices when the voice pool reuses a player.
	if exclusive_preview:
		stop_all()
	if event.event_authoring_mode == CodaBrowserNode.AuthoringMode.TIMELINE:
		return _start_timeline_event(event, path, params)
	# Build the parameter snapshot used to plan the graph (Switch/Blend look this up).
	var live_params: Dictionary = _build_param_values(event, params)
	# Stamp routing on params so _start_player_for_entry uses the right bus per voice.
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

	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.id = _next_handle_id
	_next_handle_id += 1
	handle.event_path = path
	handle.event_node = event
	handle.params = params.duplicate()
	handle.param_values = live_params
	handle.param_values_smoothed = live_params.duplicate()
	handle.loop = bool(params.get("loop", false)) or graph_event_loop
	handle._bus_name = bus_name
	handle.timeline_runtime = self

	# Phase 4: BLEND can produce two simultaneous voices that share a handle. Detect this by
	# looking at blend_weight on the first two entries; if both are <1, start them in parallel.
	var parallel_entries: Array = _split_parallel_entries(plan_entries)
	var queued_after_parallel: Array = plan_entries.slice(parallel_entries.size())

	var primary_player: AudioStreamPlayer = null
	var parallel_started_indices: Dictionary = {}
	for i in parallel_entries.size():
		var entry: Dictionary = parallel_entries[i] as Dictionary
		var tail: Array = parallel_entries.slice(i + 1)
		tail.append_array(queued_after_parallel)
		var player: AudioStreamPlayer = _start_player_for_entry(
			entry, params, tail, handle.loop
		)
		if player == null:
			continue
		parallel_started_indices[i] = true
		if primary_player == null:
			primary_player = player
			handle.current_sound_id = String(entry.get("sound_id", ""))
			handle.base_volume_db = float(entry.get("volume_db", 0.0)) + float(params.get("volume_db", 0.0))
			handle.base_pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(params.get("pitch_scale", 1.0))
			handle.blend_weight = float(entry.get("blend_weight", 1.0))
			handle._bind_player(player)
			handle.params["_coda_playback_gen"] = int(player.get_meta(&"_coda_playback_gen", -1))
			_active_handles[player.get_instance_id()] = handle
		else:
			var sib_h: CodaEventHandle = _make_sibling_handle(handle, entry, player)
			handle.graph_parallel_siblings.append(sib_h)
			_active_handles[player.get_instance_id()] = sib_h
	if primary_player == null:
		return null
	if parallel_started_indices.size() < parallel_entries.size():
		_warn(
			"voice pool exhausted; BLEND step incomplete for '%s' (%d/%d voices)"
			% [event.name, parallel_started_indices.size(), parallel_entries.size()]
		)
		handle.params["_coda_full_plan"] = plan_entries
		handle.params["_coda_plan"] = _graph_plan_after_incomplete_parallel_step(
			parallel_entries, parallel_started_indices, queued_after_parallel
		)
		_mark_graph_plan_resume(handle)
		voice_started.emit(handle)
		return handle
	handle.params["_coda_plan"] = queued_after_parallel
	handle.params["_coda_full_plan"] = plan_entries
	voice_started.emit(handle)
	return handle


func _split_parallel_entries(entries: Array) -> Array:
	# Treat consecutive entries with blend_weight < 1.0 at the front of the plan as parallel siblings
	# (this is what a BLEND container produces). BLEND crossfades also stamp blend_parallel_step so
	# interleaved SEQUENCE children only mix within the same step. Sequence/Random produce
	# blend_weight == 1.0 so they stay sequential.
	var out: Array = []
	var first_step: int = -1
	for i in entries.size():
		var entry: Dictionary = entries[i] as Dictionary
		var w: float = float(entry.get("blend_weight", 1.0))
		if w >= 1.0:
			if out.is_empty():
				out.append(entries[i])
			break
		var step: int = int(entry.get("blend_parallel_step", 0))
		if out.is_empty():
			first_step = step
			out.append(entries[i])
		elif step == first_step:
			out.append(entries[i])
		else:
			break
	if out.is_empty() and not entries.is_empty():
		out.append(entries[0])
	return out


## Remaining parallel legs plus the rest of the plan. Used when the voice pool starts only part
## of a BLEND step so finished legs are not replayed from the beginning.
func _graph_plan_after_incomplete_parallel_step(
	parallel_entries: Array, started_indices: Dictionary, rest: Array
) -> Array:
	var out: Array = []
	for i in parallel_entries.size():
		if not started_indices.has(i):
			out.append(parallel_entries[i])
	out.append_array(rest)
	return out


func _make_sibling_handle(parent: CodaEventHandle, entry: Dictionary, player: AudioStreamPlayer) -> CodaEventHandle:
	var sib: CodaEventHandle = CodaEventHandleScript.new()
	sib.id = _next_handle_id
	_next_handle_id += 1
	sib.event_path = parent.event_path
	sib.event_node = parent.event_node
	# Siblings carry no plan stash so they don't advance the sequence on finish.
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


func _stop_graph_parallel_siblings(handle: CodaEventHandle) -> void:
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		sib._alive = false
		if sib._player != null and is_instance_valid(sib._player) and sib._player.playing:
			sib._player.stop()
		if sib._player != null and is_instance_valid(sib._player):
			_active_handles.erase(sib._player.get_instance_id())
	handle.graph_parallel_siblings.clear()


func _graph_parallel_still_playing(handle: CodaEventHandle) -> bool:
	if handle._player != null and is_instance_valid(handle._player) and handle._player.playing:
		return true
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		if sib._player != null and is_instance_valid(sib._player) and sib._player.playing:
			return true
	return false


func _mark_graph_plan_resume(handle: CodaEventHandle) -> void:
	if handle == null or handle.is_timeline or not handle._alive:
		return
	if _graph_plan_resume_handles.has(handle):
		return
	_graph_plan_resume_handles.append(handle)


func _unmark_graph_plan_resume(handle: CodaEventHandle) -> void:
	if handle == null:
		return
	var idx: int = _graph_plan_resume_handles.find(handle)
	if idx >= 0:
		_graph_plan_resume_handles.remove_at(idx)


func _resume_pending_graph_plans() -> void:
	var pending: Array = _graph_plan_resume_handles.duplicate()
	for item in pending:
		var h: CodaEventHandle = item as CodaEventHandle
		if h == null or not h._alive or h.is_timeline:
			_unmark_graph_plan_resume(h)
			continue
		if _graph_parallel_still_playing(h):
			continue
		_try_finish_graph_handle(h)


func _restart_graph_loop_from_full_plan(h: CodaEventHandle) -> bool:
	var full: Variant = h.params.get("_coda_full_plan", [])
	if not full is Array or (full as Array).is_empty():
		return false
	_stop_graph_parallel_siblings(h)
	var plan_entries: Array = full as Array
	var parallel_entries: Array = _split_parallel_entries(plan_entries)
	var queued_after_parallel: Array = plan_entries.slice(parallel_entries.size())
	var primary_player: AudioStreamPlayer = null
	var parallel_started_indices: Dictionary = {}
	for i in parallel_entries.size():
		var entry: Dictionary = parallel_entries[i] as Dictionary
		var tail: Array = parallel_entries.slice(i + 1)
		tail.append_array(queued_after_parallel)
		var player: AudioStreamPlayer = _start_player_for_entry(entry, h.params, tail, h.loop)
		if player == null:
			continue
		parallel_started_indices[i] = true
		if primary_player == null:
			primary_player = player
			h.current_sound_id = String(entry.get("sound_id", ""))
			h.base_volume_db = float(entry.get("volume_db", 0.0)) + float(h.params.get("volume_db", 0.0))
			h.base_pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(h.params.get("pitch_scale", 1.0))
			h.blend_weight = float(entry.get("blend_weight", 1.0))
			h._bind_player(player)
			h.params["_coda_playback_gen"] = int(player.get_meta(&"_coda_playback_gen", -1))
			_active_handles[player.get_instance_id()] = h
		else:
			var sib_h: CodaEventHandle = _make_sibling_handle(h, entry, player)
			h.graph_parallel_siblings.append(sib_h)
			_active_handles[player.get_instance_id()] = sib_h
	if primary_player == null:
		return false
	if parallel_started_indices.size() < parallel_entries.size():
		h.params["_coda_plan"] = _graph_plan_after_incomplete_parallel_step(
			parallel_entries, parallel_started_indices, queued_after_parallel
		)
		_mark_graph_plan_resume(h)
		return false
	h.params["_coda_plan"] = queued_after_parallel
	return true


## Drop pooled-player ownership from every timeline dispatcher (and FX meta) before graph
## or another lane reuses the player. Otherwise a stale voices entry can stop unrelated audio
## at clip-end, and orphaned finished signals can leak __CodaFx_* buses.
## Keeps [code]fired_clip_ids[/code] intact: the playhead may still be inside the clip window, and
## clearing fired would retrigger the lane on the next tick while the reused player plays elsewhere.
func _detach_player_from_timeline_dispatchers(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	var key: int = player.get_instance_id()
	_timeline_voice_owner.erase(key)
	_timeline_voice_playback_gen.erase(key)
	_clear_timeline_voice_player_meta(player)
	_free_player_timeline_fx_bus(player)
	for h in _timeline_dispatchers.keys():
		var d: Dictionary = _timeline_dispatchers[h]
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


## Stamp a new playback generation and orphan any still-pending finish for this pooled player.
func _begin_player_voice(player: AudioStreamPlayer) -> int:
	_detach_player_from_timeline_dispatchers(player)
	var key: int = player.get_instance_id()
	var prior_gen: int = int(player.get_meta(&"_coda_playback_gen", -1))
	if prior_gen >= 0:
		_orphaned_finish_gens[prior_gen] = true
	var gen: int = _next_playback_gen
	_next_playback_gen += 1
	player.set_meta(&"_coda_playback_gen", gen)
	_player_pending_finish_gen[key] = gen
	_active_handles.erase(key)
	return gen


func _is_stale_player_finish(player: AudioStreamPlayer) -> bool:
	var key: int = player.get_instance_id()
	var gen: int = int(player.get_meta(&"_coda_playback_gen", -1))
	if gen < 0:
		return true
	if _orphaned_finish_gens.erase(gen):
		return true
	return int(_player_pending_finish_gen.get(key, -1)) != gen


## Sound-node Loop only applies as [member AudioStream.loop] when this entry is the last queued
## step and the event is not using plan-level loop (Sequence Loop). Otherwise [code]stream.loop[/code]
## never emits [signal AudioStreamPlayer.finished] and later plan entries / [member CodaEventHandle.loop]
## restarts never run.
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


func _start_player_for_entry(
	entry: Dictionary, params: Dictionary, plan_remaining: Array = [], event_loops: bool = false
) -> AudioStreamPlayer:
	var stream_path: String = String(entry.get("audio_path", "")).strip_edges()
	if stream_path.is_empty():
		_warn("plan entry has empty audio_path")
		return null
	if not ResourceLoader.exists(stream_path):
		_warn("audio resource missing: '%s'" % stream_path)
		return null
	var stream: AudioStream = load(stream_path) as AudioStream
	if stream == null:
		_warn("audio resource not an AudioStream: '%s'" % stream_path)
		return null
	if _entry_should_loop_stream(entry, plan_remaining, event_loops):
		stream = stream.duplicate()
		stream.loop = true
	var player: AudioStreamPlayer = _pool.acquire()
	if player == null:
		_warn("voice pool exhausted while playing '%s'" % stream_path)
		return null
	var route_bus: String = String(params.get("_coda_voice_bus", bus_name))
	if AudioServer.get_bus_index(route_bus) < 0:
		route_bus = "Master"
	player.bus = route_bus
	player.stream = stream
	var override_db: float = float(params.get("volume_db", 0.0))
	var entry_blend: float = float(entry.get("blend_weight", 1.0))
	var blend_db: float = 0.0
	if entry_blend < 1.0 and entry_blend > 0.0:
		blend_db = linear_to_db(entry_blend)
	elif entry_blend <= 0.0:
		blend_db = -80.0
	player.volume_db = float(entry.get("volume_db", 0.0)) + override_db + blend_db
	player.pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(params.get("pitch_scale", 1.0))
	_begin_player_voice(player)
	player.play()
	return player


func _on_voice_finished(player: AudioStreamPlayer) -> void:
	if _is_stale_player_finish(player):
		return
	var key: int = player.get_instance_id()
	if int(_timeline_voice_playback_gen.get(key, -1)) == int(player.get_meta(&"_coda_playback_gen", -1)):
		_on_timeline_voice_finished(player, key)
		return
	if not _active_handles.has(key):
		return
	if _stop_all_in_progress:
		_active_handles.erase(key)
		return
	var h: CodaEventHandle = _active_handles[key] as CodaEventHandle
	_active_handles.erase(key)
	if h == null:
		return
	if int(h.params.get("_coda_playback_gen", -1)) != int(player.get_meta(&"_coda_playback_gen", -1)):
		return
	if bool(h.params.get("_coda_is_sibling", false)):
		if not h._alive:
			return
		h._alive = false
		var parent: CodaEventHandle = h.params.get("_coda_graph_parent", null) as CodaEventHandle
		if parent != null:
			var sib_idx: int = parent.graph_parallel_siblings.find(h)
			if sib_idx >= 0:
				parent.graph_parallel_siblings.remove_at(sib_idx)
			if not parent._paused:
				_try_finish_graph_handle(parent)
		return
	_try_finish_graph_handle(h)


func _try_finish_graph_handle(h: CodaEventHandle) -> void:
	if h == null or not h._alive:
		return
	if h._paused:
		return
	if _graph_parallel_still_playing(h):
		return
	# If the plan still has queued entries, play the next batch (parallel BLEND step or one sequence voice).
	var queued: Variant = h.params.get("_coda_plan", [])
	if queued is Array and (queued as Array).size() > 0:
		_stop_graph_parallel_siblings(h)
		var plan_slice: Array = queued as Array
		var parallel_entries: Array = _split_parallel_entries(plan_slice)
		var rest: Array = plan_slice.slice(parallel_entries.size())
		var primary_player: AudioStreamPlayer = null
		var parallel_started_indices: Dictionary = {}
		for i in parallel_entries.size():
			var entry: Dictionary = parallel_entries[i] as Dictionary
			var tail: Array = parallel_entries.slice(i + 1)
			tail.append_array(rest)
			var player: AudioStreamPlayer = _start_player_for_entry(entry, h.params, tail, h.loop)
			if player == null:
				continue
			parallel_started_indices[i] = true
			if primary_player == null:
				primary_player = player
				h.current_sound_id = String(entry.get("sound_id", ""))
				h.base_volume_db = float(entry.get("volume_db", 0.0)) + float(h.params.get("volume_db", 0.0))
				h.base_pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(h.params.get("pitch_scale", 1.0))
				h.blend_weight = float(entry.get("blend_weight", 1.0))
				h._bind_player(player)
				h.params["_coda_playback_gen"] = int(player.get_meta(&"_coda_playback_gen", -1))
				_active_handles[player.get_instance_id()] = h
			else:
				var sib_h: CodaEventHandle = _make_sibling_handle(h, entry, player)
				h.graph_parallel_siblings.append(sib_h)
				_active_handles[player.get_instance_id()] = sib_h
		if primary_player != null:
			if parallel_started_indices.size() < parallel_entries.size():
				_warn(
					"voice pool exhausted; BLEND step incomplete for '%s' (%d/%d voices)"
					% [h.event_path, parallel_started_indices.size(), parallel_entries.size()]
				)
				h.params["_coda_plan"] = _graph_plan_after_incomplete_parallel_step(
					parallel_entries, parallel_started_indices, rest
				)
				_mark_graph_plan_resume(h)
				return
			h.params["_coda_plan"] = rest
			_unmark_graph_plan_resume(h)
			return
		_warn(
			"voice pool exhausted; sequence paused for '%s' (%d entries remain)"
			% [h.event_path, plan_slice.size()]
		)
		_mark_graph_plan_resume(h)
		return
	if h.loop:
		if _restart_graph_loop_from_full_plan(h):
			_unmark_graph_plan_resume(h)
			return
		_mark_graph_plan_resume(h)
		return
	_unmark_graph_plan_resume(h)
	h._on_player_finished()
	voice_finished.emit(h)


func _warn(msg: String) -> void:
	push_warning("Coda: %s" % msg)


# ---- Timeline-mode dispatching ----

func _start_timeline_event(
	event: CodaBrowserNode, path: String, params: Dictionary
) -> CodaEventHandle:
	var prior: CodaEventHandle = get_active_timeline_handle_for_event(event.id)
	if prior != null:
		_finalize_timeline_handle(prior)
	var timeline: CodaEventTimeline = event.event_timeline
	if timeline == null:
		_warn("event '%s' is in timeline mode but has no timeline data" % event.name)
		return null
	var live_params: Dictionary = _build_param_values(event, params)
	params = params.duplicate()
	params["_coda_voice_bus"] = resolve_bus_name_for_event(event)

	var handle: CodaEventHandle = CodaEventHandleScript.new()
	handle.id = _next_handle_id
	_next_handle_id += 1
	handle.event_path = path
	handle.event_node = event
	handle.params = params.duplicate()
	handle.param_values = live_params
	handle.param_values_smoothed = live_params.duplicate()
	handle.loop = bool(params.get("loop", false))
	handle._bus_name = bus_name
	handle.is_timeline = true
	handle.timeline_length_seconds = timeline.length_seconds
	var start_sec: float = float(params.get("timeline_cursor_start", 0.0))
	handle.timeline_cursor_seconds = clampf(start_sec, 0.0, timeline.length_seconds)
	# Optional override: player panel may pass [start, end] to scrub a sub-range.
	var loop_region: Variant = params.get("_coda_loop_region", null)
	var loop_override_start: float = -1.0
	var loop_override_end: float = -1.0
	if loop_region is Array and (loop_region as Array).size() == 2:
		loop_override_start = float((loop_region as Array)[0])
		loop_override_end = float((loop_region as Array)[1])

	_timeline_dispatchers[handle] = {
		"timeline": timeline,
		"voices": {},  # clip_id -> AudioStreamPlayer
		"fired_clip_ids": {},  # clip_id -> true (cleared on loop wrap or seek)
		"spent_clip_ids": {},  # clip_id -> true when source ended before clip window ends
		"layout_sig": _timeline_layout_signature(timeline),
		"live_params": live_params,
		"loop_override_start": loop_override_start,
		"loop_override_end": loop_override_end,
	}
	handle.timeline_runtime = self
	_prime_timeline_overlapping_voices(handle, _timeline_dispatchers[handle], timeline, handle.timeline_cursor_seconds)
	voice_started.emit(handle)
	return handle


func _prime_timeline_overlapping_voices(
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
			if _spawn_timeline_voice(handle, d, entry):
				fired[clip.id] = true
	d["fired_clip_ids"] = fired


## Drop stale [code]fired_clip_ids[/code] when a lane has no voice but the playhead is still inside
## the clip. Recovers silence after pool reuse orphans [signal AudioStreamPlayer.finished].
func _heal_timeline_orphaned_fired_clips(
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


func _tick_timeline_dispatchers(delta: float) -> void:
	# Iterate over a copy because we may erase entries on finish.
	var handles: Array = _timeline_dispatchers.keys()
	for h in handles:
		var handle: CodaEventHandle = h as CodaEventHandle
		if handle == null:
			_timeline_dispatchers.erase(h)
			continue
		if not handle._alive:
			_finalize_timeline_handle(handle)
			continue
		var d: Dictionary = _timeline_dispatchers[handle]
		var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
		if timeline == null:
			_finalize_timeline_handle(handle)
			continue

		_advance_smoothing(handle, delta)

		if handle.timeline_pending_seek_seconds >= 0.0:
			_apply_timeline_seek(handle, d, handle.timeline_pending_seek_seconds)
			handle.timeline_pending_seek_seconds = -1.0

		_refresh_timeline_voice_output_levels(handle, d, timeline)

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
				_fire_clips_in_range(
					handle, d, timeline, prev_cursor, timeline.length_seconds
				)
				handle.timeline_cursor_seconds = timeline.length_seconds
				_finalize_timeline_handle(handle)
				continue

		if wrapped:
			# Fire any remaining clips up to the wrap point, then reset and continue from the
			# loop start so designers don't see clips silently skipped at the wrap.
			var wrap_target: float = (
				loop_end if loop_end > 0.0 else timeline.length_seconds
			)
			var cursor_at_frame_start: float = prev_cursor
			_fire_clips_in_range(handle, d, timeline, cursor_at_frame_start, wrap_target)
			d["fired_clip_ids"] = {}
			d["spent_clip_ids"] = {}
			# Stop currently-playing voices so the next iteration retriggers them on cue.
			_stop_timeline_voices(d, handle)
			var loop_lo: float = loop_start if loop_start >= 0.0 else 0.0
			# Multi-wrap in one frame (large delta / hitch) can land before clip starts we flew past.
			if next_cursor < cursor_at_frame_start:
				_fire_clips_in_range(
					handle, d, timeline, next_cursor, cursor_at_frame_start
				)
			# Re-prime clips overlapping the post-wrap cursor (same as seek). Without this,
			# clips that started before loop_start stay silent after the first loop iteration.
			_prime_timeline_overlapping_voices(handle, d, timeline, next_cursor)
			prev_cursor = loop_lo

		handle.timeline_cursor_seconds = next_cursor
		_stop_timeline_voices_past_clip_end(d, handle, next_cursor)
		_heal_timeline_orphaned_fired_clips(handle, d, timeline, next_cursor)
		_fire_clips_in_range(handle, d, timeline, prev_cursor, next_cursor)


func _refresh_timeline_voice_output_levels(
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
			p.volume_db = float(cl.volume_db + tr.volume_db) + override_db


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
			# Fire on start crossing, or retry while the playhead is still inside an unfired clip
			# (e.g. voice pool was exhausted on the first attempt).
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
			if _spawn_timeline_voice(handle, d, entry):
				fired[clip.id] = true
	d["fired_clip_ids"] = fired


func _timeline_send_bus_for_track(handle: CodaEventHandle, track_output_bus_id: String) -> String:
	# Track-level output bus wins over the event-level fallback so designers can route lanes
	# to dedicated buses without changing the event itself.
	var mapped: String = resolve_godot_bus_name_for_coda_bus_id(track_output_bus_id)
	if not mapped.is_empty() and AudioServer.get_bus_index(mapped) >= 0:
		return mapped
	var fallback: String = String(handle.params.get("_coda_voice_bus", bus_name))
	if AudioServer.get_bus_index(fallback) < 0:
		fallback = "Master"
	return fallback


func _free_player_timeline_fx_bus(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if not player.has_meta(&"_coda_fx_bus"):
		return
	var nm: String = String(player.get_meta(&"_coda_fx_bus", ""))
	player.remove_meta(&"_coda_fx_bus")
	CodaFxBusHelperScript.destroy_if_ours(nm)


func _collect_timeline_fx_chain(entry: Dictionary) -> Array:
	var out: Array = []
	# Clip-level inserts run first, then the track's, so a per-clip gain doesn't get
	# undone by a track compressor downstream of it.
	for e in entry.get("clip_effects", []) as Array:
		if e is CodaTrackEffect:
			out.append(e)
	for e2 in entry.get("track_effects", []) as Array:
		if e2 is CodaTrackEffect:
			out.append(e2)
	return out


func _clear_timeline_voice_player_meta(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_meta(&"_coda_timeline_restart_offset"):
		player.remove_meta(&"_coda_timeline_restart_offset")
	if player.has_meta(&"_coda_clip_timeline_end"):
		player.remove_meta(&"_coda_clip_timeline_end")


func _retire_timeline_lane_voice(d: Dictionary, clip_id: String) -> void:
	if clip_id.is_empty():
		return
	var voices: Dictionary = d.get("voices", {})
	if not voices.has(clip_id):
		return
	var p: AudioStreamPlayer = voices[clip_id] as AudioStreamPlayer
	voices.erase(clip_id)
	d["voices"] = voices
	if p == null or not is_instance_valid(p):
		return
	var pk: int = p.get_instance_id()
	_timeline_voice_owner.erase(pk)
	_timeline_voice_playback_gen.erase(pk)
	if p.playing:
		p.stop()
	_clear_timeline_voice_player_meta(p)
	_free_player_timeline_fx_bus(p)


func _spawn_timeline_voice(
	handle: CodaEventHandle, d: Dictionary, entry: Dictionary
) -> bool:
	var stream_path: String = String(entry.get("audio_path", "")).strip_edges()
	if stream_path.is_empty():
		return false
	if not ResourceLoader.exists(stream_path):
		_warn("timeline clip audio missing: '%s'" % stream_path)
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
	# When offset is 0, looping the stream from the start fills the clip window. With offset > 0,
	# AudioStream.loop restarts at 0 and plays the wrong part of the asset until the clip ends.
	var use_stream_loop_extend: bool = needs_source_extend and stream_offset <= 0.001
	if use_stream_loop_extend:
		stream = stream.duplicate()
		stream.loop = true
	var clip_id: String = String(entry.get("sound_id", ""))
	_retire_timeline_lane_voice(d, clip_id)
	var player: AudioStreamPlayer = _pool.acquire()
	if player == null:
		_warn("voice pool exhausted while playing timeline clip '%s'" % stream_path)
		return false
	# Pooled players may still carry lane metas from a prior timeline clip (seek/loop/stop does not
	# always run through _retire_timeline_lane_voice). Stale restart/clip-end metas mis-route finished.
	_clear_timeline_voice_player_meta(player)
	_free_player_timeline_fx_bus(player)
	var voice_gen: int = _begin_player_voice(player)
	var send_bus: String = _timeline_send_bus_for_track(
		handle, String(entry.get("track_output_bus_id", ""))
	)
	var route_bus: String = send_bus
	var fx_chain: Array = _collect_timeline_fx_chain(entry)
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
	if handle._paused:
		player.stream_paused = true
	var voices: Dictionary = d.get("voices", {})
	voices[entry.get("sound_id", "")] = player
	d["voices"] = voices
	var player_key: int = player.get_instance_id()
	_timeline_voice_owner[player_key] = handle
	_timeline_voice_playback_gen[player_key] = voice_gen
	# Track the most recent voice on the handle so legacy graph-based code paths (modulation
	# bookkeeping, status checks) keep referencing a live player object.
	handle._bind_player(player)
	handle.current_sound_id = String(entry.get("sound_id", ""))
	handle.base_volume_db = float(entry.get("volume_db", 0.0))
	handle.base_pitch_scale = float(entry.get("pitch_scale", 1.0))
	return true


func _on_timeline_voice_finished(player: AudioStreamPlayer, key: int) -> void:
	# Stop/seek/loop-wrap clears owner + FX before the pool reuses this player. A late
	# [signal AudioStreamPlayer.finished] must not tear down a new lane's FX bus.
	var h: CodaEventHandle = _timeline_voice_owner.get(key, null) as CodaEventHandle
	if h == null:
		return
	if not _timeline_dispatchers.has(h):
		return
	var d: Dictionary = _timeline_dispatchers[h]
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
		_finalize_timeline_lane_voice(player, key, h, d, finished_clip_id)
		return
	if player.has_meta(&"_coda_timeline_restart_offset"):
		var restart_at: float = maxf(0.0, float(player.get_meta(&"_coda_timeline_restart_offset", 0.0)))
		var gen: int = int(player.get_meta(&"_coda_playback_gen", -1))
		if gen >= 0:
			_player_pending_finish_gen[key] = gen
		player.play(restart_at)
		return
	_finalize_timeline_lane_voice(player, key, h, d, finished_clip_id)
	# Source ended before the clip window ends. Keep fired set so we do not respawn every frame;
	# pool-orphan recovery uses _heal_timeline_orphaned_fired_clips (spent lanes are excluded).
	var spent: Dictionary = d.get("spent_clip_ids", {})
	spent[finished_clip_id] = true
	d["spent_clip_ids"] = spent


func _finalize_timeline_lane_voice(
	player: AudioStreamPlayer,
	key: int,
	h: CodaEventHandle,
	d: Dictionary,
	finished_clip_id: String,
) -> void:
	_free_player_timeline_fx_bus(player)
	_timeline_voice_owner.erase(key)
	_timeline_voice_playback_gen.erase(key)
	var voices: Dictionary = d.get("voices", {})
	if voices.get(finished_clip_id, null) == player:
		voices.erase(finished_clip_id)
		d["voices"] = voices
	_clear_timeline_voice_player_meta(player)


func _apply_timeline_seek(
	handle: CodaEventHandle, d: Dictionary, target_seconds: float
) -> void:
	var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
	if timeline == null:
		return
	var clamped: float = clampf(target_seconds, 0.0, timeline.length_seconds)
	handle.timeline_cursor_seconds = clamped
	_stop_timeline_voices(d, handle)
	# Seek invalidates prior start-crossing state; _prime skips ids still listed in fired_clip_ids.
	d["fired_clip_ids"] = {}
	d["spent_clip_ids"] = {}
	# Re-prime clips overlapping the new cursor. Without this, scrubbing the playhead or using
	# the transport seek slider leaves silence until the cursor crosses another clip start.
	_prime_timeline_overlapping_voices(handle, d, timeline, clamped)


func _stop_timeline_voices_past_clip_end(
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
		if p.playing:
			p.stop()
		var pk: int = p.get_instance_id()
		_timeline_voice_owner.erase(pk)
		_timeline_voice_playback_gen.erase(pk)
		_clear_timeline_voice_player_meta(p)
		_free_player_timeline_fx_bus(p)
		stale_keys.append(sound_key)
	for k in stale_keys:
		voices.erase(k)
	d["voices"] = voices
	if stale_keys.size() > 0 and handle != null:
		handle.clear_player_binding()


func _stop_timeline_voices(d: Dictionary, handle: CodaEventHandle = null) -> void:
	var voices: Dictionary = d.get("voices", {})
	for k in voices.keys():
		var p: AudioStreamPlayer = voices[k] as AudioStreamPlayer
		if p == null or not is_instance_valid(p):
			continue
		var pk: int = p.get_instance_id()
		_timeline_voice_owner.erase(pk)
		_timeline_voice_playback_gen.erase(pk)
		if p.playing:
			p.stop()
		_clear_timeline_voice_player_meta(p)
		_free_player_timeline_fx_bus(p)
	d["voices"] = {}
	if handle != null:
		handle.clear_player_binding()


func _finalize_timeline_handle(handle: CodaEventHandle) -> void:
	if not _timeline_dispatchers.has(handle):
		return
	var was_alive: bool = handle._alive
	var d: Dictionary = _timeline_dispatchers[handle]
	_stop_timeline_voices(d, handle)
	handle.timeline_runtime = null
	_timeline_dispatchers.erase(handle)
	if was_alive:
		handle._alive = false
		handle.finished.emit()
	voice_finished.emit(handle)


# ---- Player panel ↔ Timeline panel sync ----

## Editor: after timeline layout edits (clip move/trim/delete, track changes), clear stale
## [code]fired_clip_ids[/code] and re-prime voices at the playhead. Skips work when layout is
## unchanged so volume/mute drags do not restart every lane.
func resync_timeline_preview_for_event(event_id: String) -> void:
	if event_id.is_empty():
		return
	var handle: CodaEventHandle = get_active_timeline_handle_for_event(event_id)
	if handle == null or not _timeline_dispatchers.has(handle):
		return
	var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
	if event == null or event.event_timeline == null:
		return
	var timeline: CodaEventTimeline = event.event_timeline
	var d: Dictionary = _timeline_dispatchers[handle]
	# Always follow the event's current timeline object (undo/redo replaces the ref).
	d["timeline"] = timeline
	handle.timeline_length_seconds = timeline.length_seconds
	var sig: String = _timeline_layout_signature(timeline)
	if String(d.get("layout_sig", "")) == sig:
		return
	d["layout_sig"] = sig
	d["fired_clip_ids"] = {}
	d["spent_clip_ids"] = {}
	_stop_timeline_voices(d, handle)
	_prime_timeline_overlapping_voices(handle, d, timeline, handle.timeline_cursor_seconds)


static func _timeline_layout_signature(timeline: CodaEventTimeline) -> String:
	if timeline == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for tr in timeline.tracks:
		var bus_id: String = String(tr.output_bus_id)
		var track_fx: String = _timeline_fx_chain_signature(tr.effects)
		for clip in tr.clips:
			parts.append(
				"%s|%s|%s|%.6f|%.6f|%s|fx:%s|tfx:%s"
				% [
					clip.id,
					tr.id,
					clip.audio_path,
					clip.start_seconds,
					clip.duration_seconds,
					bus_id,
					_timeline_fx_chain_signature(clip.effects),
					track_fx,
				]
			)
	parts.sort()
	return "%.6f|%s" % [timeline.length_seconds, "|".join(parts)]


static func _timeline_fx_chain_signature(effects: Array) -> String:
	if effects.is_empty():
		return ""
	var fx_parts: PackedStringArray = PackedStringArray()
	for eff in effects:
		if eff is CodaTrackEffect:
			var e: CodaTrackEffect = eff as CodaTrackEffect
			fx_parts.append(
				"%s|%d|%s|%s"
				% [e.id, int(e.type), str(e.bypass), JSON.stringify(e.params)]
			)
	fx_parts.sort()
	return ",".join(fx_parts)


## Returns the active timeline handle for the given event id, or null. Used by the timeline
## panel to keep its visual cursor in sync with the player panel without leaking dispatcher
## internals.
func get_active_timeline_handle_for_event(event_id: String) -> CodaEventHandle:
	if event_id.is_empty():
		return null
	for h in _timeline_dispatchers.keys():
		var handle: CodaEventHandle = h as CodaEventHandle
		if handle == null or not handle._alive:
			continue
		var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
		if event == null:
			continue
		if event.id == event_id:
			return handle
	return null


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
	_unmark_graph_plan_resume(handle)
	_stop_graph_parallel_siblings(handle)
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
	var any_resumed: bool = false
	if _resume_graph_paused_player(handle, handle, snap):
		any_resumed = true
	for sib in handle.graph_parallel_siblings:
		if sib == null:
			continue
		if _resume_graph_paused_player(handle, sib, snap):
			any_resumed = true
	if not any_resumed and handle._alive:
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


## Editor preview: pause every timeline lane voice (handle.pause() routes here when [member CodaEventHandle.is_timeline]).
func pause_timeline_preview(handle: CodaEventHandle) -> void:
	if handle == null or not _timeline_dispatchers.has(handle):
		return
	handle._paused = true
	var d: Dictionary = _timeline_dispatchers[handle]
	# Stop lane voices instead of stream_paused so pooled players stay available for graph preview.
	_stop_timeline_voices(d, handle)
	d["fired_clip_ids"] = {}
	d["spent_clip_ids"] = {}


## Editor preview: resume all lane voices; if seek cleared every player, re-prime at the cursor.
func resume_timeline_preview(handle: CodaEventHandle) -> void:
	if handle == null or not _timeline_dispatchers.has(handle):
		return
	var d: Dictionary = _timeline_dispatchers[handle]
	var voices: Dictionary = d.get("voices", {})
	if voices.is_empty():
		var timeline: CodaEventTimeline = d.get("timeline", null) as CodaEventTimeline
		if timeline == null:
			handle._paused = false
			return
		handle._paused = false
		d["fired_clip_ids"] = {}
		d["spent_clip_ids"] = {}
		_prime_timeline_overlapping_voices(handle, d, timeline, handle.timeline_cursor_seconds)
		return
	handle._paused = false
	for p in voices.values():
		var pl: AudioStreamPlayer = p as AudioStreamPlayer
		if pl != null and is_instance_valid(pl):
			pl.stream_paused = false
