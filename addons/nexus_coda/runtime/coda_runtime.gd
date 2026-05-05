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
const CodaModulationScript := preload("res://addons/nexus_coda/editor/browser/coda_modulation.gd")
const CodaAudioBusMirrorScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_mirror.gd")
const CodaBankExportScript := preload("res://addons/nexus_coda/editor/io/coda_bank_export.gd")

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


func _ready() -> void:
	if _pool == null:
		_pool = CodaVoicePoolScript.new()
		_pool.name = "VoicePool"
		add_child(_pool)
	if not _pool.voice_finished.is_connected(_on_voice_finished):
		_pool.voice_finished.connect(_on_voice_finished)
	set_process(true)


func _process(delta: float) -> void:
	if _active_handles.is_empty():
		return
	for h in _active_handles.values():
		var hh: CodaEventHandle = h as CodaEventHandle
		if hh == null or not hh._alive:
			continue
		_advance_smoothing(hh, delta)
		_apply_modulations(hh)


func set_project(project: Variant) -> void:
	if _project != null:
		if _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.disconnect(_on_project_structure_changed)
		if _project.project_dirty.is_connected(_on_project_dirty_sync_buses):
			_project.project_dirty.disconnect(_on_project_dirty_sync_buses)
	if project == null:
		_project = null
		_bus_id_to_godot_name.clear()
		return
	_project = project as CodaState
	_sync_buses()
	if _project != null:
		if not _project.structure_changed.is_connected(_on_project_structure_changed):
			_project.structure_changed.connect(_on_project_structure_changed)
		if not _project.project_dirty.is_connected(_on_project_dirty_sync_buses):
			_project.project_dirty.connect(_on_project_dirty_sync_buses)


func _on_project_structure_changed() -> void:
	_sync_buses()


func _on_project_dirty_sync_buses() -> void:
	_sync_buses()


func _sync_buses() -> void:
	if _project == null or _project.bus_root == null:
		_bus_id_to_godot_name.clear()
		return
	_bus_id_to_godot_name = CodaAudioBusMirrorScript.sync_to_audio_server(_project.bus_root)


func resolve_bus_name_for_event(event: CodaBrowserNode) -> String:
	if event == null or _project == null or _project.bus_root == null:
		return bus_name
	if not event.event_output_bus_id.is_empty():
		var name: Variant = _bus_id_to_godot_name.get(event.event_output_bus_id, null)
		if name != null:
			return String(name)
	return bus_name


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
	for bank_id in _loaded_banks.keys():
		var entry: Dictionary = _loaded_banks[bank_id]
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
	handle.stop(fade_ms)


func stop_all() -> void:
	if _pool != null:
		_pool.stop_all()
	for h in _active_handles.values():
		var hh := h as CodaEventHandle
		if hh != null:
			hh._alive = false
	_active_handles.clear()


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
	_loaded_banks[bank_id] = {
		"bank_name": str(manifest.get("bank_name", "Bank")),
		"events_by_path": events_by_path,
	}
	return bank_id


## Unloads a previously-loaded bank by id. No-op if id is unknown.
func unload_bank(bank_id: String) -> bool:
	if not _loaded_banks.has(bank_id):
		return false
	_loaded_banks.erase(bank_id)
	return true


func loaded_bank_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _loaded_banks.keys():
		out.append(String(k))
	return out


func _start_event(event: CodaBrowserNode, path: String, params: Dictionary) -> CodaEventHandle:
	# Build the parameter snapshot used to plan the graph (Switch/Blend look this up).
	var live_params: Dictionary = _build_param_values(event, params)
	# Stamp routing on params so _start_player_for_entry uses the right bus per voice.
	params = params.duplicate()
	params["_coda_voice_bus"] = resolve_bus_name_for_event(event)
	# Resolve the play list. Prefer the v2 graph; fall back to legacy flat list (random pick) if missing.
	var plan_entries: Array = []
	if event.event_graph != null:
		plan_entries = CodaGraphSchedulerScript.plan(event.event_graph, live_params)
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
	handle.loop = bool(params.get("loop", false))
	handle._bus_name = bus_name

	# Phase 4: BLEND can produce two simultaneous voices that share a handle. Detect this by
	# looking at blend_weight on the first two entries; if both are <1, start them in parallel.
	var parallel_entries: Array = _split_parallel_entries(plan_entries)
	var queued_after_parallel: Array = plan_entries.slice(parallel_entries.size())

	var primary_player: AudioStreamPlayer = null
	for entry in parallel_entries:
		var player: AudioStreamPlayer = _start_player_for_entry(entry, params)
		if player == null:
			continue
		if primary_player == null:
			primary_player = player
			handle.current_sound_id = String(entry.get("sound_id", ""))
			handle.base_volume_db = float(entry.get("volume_db", 0.0)) + float(params.get("volume_db", 0.0))
			handle.base_pitch_scale = float(entry.get("pitch_scale", 1.0)) * float(params.get("pitch_scale", 1.0))
			handle.blend_weight = float(entry.get("blend_weight", 1.0))
			handle._bind_player(player)
			_active_handles[player.get_instance_id()] = handle
		else:
			# Sibling parallel voice: track separately so it stops with the handle but doesn't get
			# its own modulation pass (Phase 4 limitation).
			_active_handles[player.get_instance_id()] = _make_sibling_handle(handle, entry, player)
	if primary_player == null:
		return null
	handle.params["_coda_plan"] = queued_after_parallel
	handle.params["_coda_full_plan"] = plan_entries
	voice_started.emit(handle)
	return handle


func _split_parallel_entries(entries: Array) -> Array:
	# Treat consecutive entries with blend_weight < 1.0 at the front of the plan as parallel siblings
	# (this is what a BLEND container produces). Sequence/Random produce blend_weight == 1.0 so they
	# stay sequential.
	var out: Array = []
	for i in entries.size():
		var w: float = float((entries[i] as Dictionary).get("blend_weight", 1.0))
		if w >= 1.0:
			if out.is_empty():
				out.append(entries[i])
			break
		out.append(entries[i])
	if out.is_empty() and not entries.is_empty():
		out.append(entries[0])
	return out


func _make_sibling_handle(parent: CodaEventHandle, entry: Dictionary, player: AudioStreamPlayer) -> CodaEventHandle:
	var sib: CodaEventHandle = CodaEventHandleScript.new()
	sib.id = _next_handle_id
	_next_handle_id += 1
	sib.event_path = parent.event_path
	sib.event_node = parent.event_node
	# Siblings carry no plan stash so they don't advance the sequence on finish.
	sib.params = {"_coda_is_sibling": true}
	sib.param_values = parent.param_values
	sib.param_values_smoothed = parent.param_values_smoothed
	sib.loop = false
	sib._bus_name = parent._bus_name
	sib.current_sound_id = String(entry.get("sound_id", ""))
	sib.base_volume_db = float(entry.get("volume_db", 0.0))
	sib.base_pitch_scale = float(entry.get("pitch_scale", 1.0))
	sib.blend_weight = float(entry.get("blend_weight", 1.0))
	sib._bind_player(player)
	return sib


func _start_player_for_entry(entry: Dictionary, params: Dictionary) -> AudioStreamPlayer:
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
	player.play()
	return player


func _on_voice_finished(player: AudioStreamPlayer) -> void:
	var key: int = player.get_instance_id()
	if not _active_handles.has(key):
		return
	var h: CodaEventHandle = _active_handles[key] as CodaEventHandle
	_active_handles.erase(key)
	if h == null:
		return
	# If the plan still has queued entries, play the next one on a fresh player.
	var queued: Variant = h.params.get("_coda_plan", [])
	if queued is Array and (queued as Array).size() > 0 and h._alive:
		var entry: Dictionary = (queued as Array)[0]
		var rest: Array = (queued as Array).slice(1)
		var next_player: AudioStreamPlayer = _start_player_for_entry(entry, h.params)
		if next_player != null:
			h._bind_player(next_player)
			h.params["_coda_plan"] = rest
			_active_handles[next_player.get_instance_id()] = h
			return
	if h.loop and h._alive:
		# Restart the full plan from scratch.
		var full: Variant = h.params.get("_coda_full_plan", [])
		if full is Array and (full as Array).size() > 0:
			var entry2: Dictionary = (full as Array)[0]
			h.params["_coda_plan"] = (full as Array).slice(1)
			var p2: AudioStreamPlayer = _start_player_for_entry(entry2, h.params)
			if p2 != null:
				h._bind_player(p2)
				_active_handles[p2.get_instance_id()] = h
				return
	h._on_player_finished()
	voice_finished.emit(h)


func _warn(msg: String) -> void:
	push_warning("Coda: %s" % msg)
