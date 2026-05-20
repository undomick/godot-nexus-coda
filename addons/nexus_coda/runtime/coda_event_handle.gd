@tool
class_name CodaEventHandle
extends RefCounted

## Lightweight handle returned by Coda.play(). Gameplay code keeps this around
## to stop, query, or modulate the running event.

signal finished

var id: int = 0
var event_path: String = ""
var event_node: Variant = null  ## CodaBrowserNode or null after free
var params: Dictionary = {}
## Live parameter values keyed by parameter id (string). Mutated via Coda.set_parameter().
var param_values: Dictionary = {}
## Smoothed parameter values, updated per frame from `param_values` using each parameter's smoothing_ms.
var param_values_smoothed: Dictionary = {}
var started_at_msec: int = 0
var loop: bool = false
## Currently-playing leaf SOUND node id (matches CodaEventGraphNodeData.id). Modulations targeting
## this node apply to the active voice.
var current_sound_id: String = ""
## Base values for the current voice; per-frame modulation reads from these and adds/multiplies on top.
var base_volume_db: float = 0.0
var base_pitch_scale: float = 1.0
## Extra weight (BLEND only): final volume_db = base_volume_db + 20*log10(blend_weight).
var blend_weight: float = 1.0

## Parallel graph voices (BLEND) started with this handle. Filled by [CodaRuntime]; cleared on stop.
var graph_parallel_siblings: Array[CodaEventHandle] = []

## Timeline-mode metadata (graph-mode handles ignore these).
## [code]is_timeline[/code] flips the player-panel cursor source from the player position to
## [code]timeline_cursor_seconds[/code], which the runtime advances each frame.
var is_timeline: bool = false
var timeline_cursor_seconds: float = 0.0
var timeline_length_seconds: float = 0.0
## When >= 0, the timeline dispatcher should jump the cursor to this time on the next tick
## and re-plan voices. Reset to -1 after the dispatcher consumes it.
var timeline_pending_seek_seconds: float = -1.0
## Set only for timeline-mode handles created by [CodaRuntime]; used to pause every lane voice.
var timeline_runtime: CodaRuntime = null

var _player: AudioStreamPlayer = null
var _bus_name: String = "Master"
var _alive: bool = true
var _paused: bool = false


func _init() -> void:
	started_at_msec = Time.get_ticks_msec()


func is_playing() -> bool:
	if not _alive:
		return false
	if is_timeline:
		# Timeline handles stay alive across silent gaps between clips; the runtime dispatcher
		# clears [code]_alive[/code] when the cursor reaches the end (and looping is off).
		return true
	if _player == null or not is_instance_valid(_player):
		return false
	return _player.playing


func stop(_fade_ms: int = 0) -> void:
	# Phase 4 will add proper fade; for MVP we stop immediately.
	_alive = false
	if _player != null and is_instance_valid(_player) and _player.playing:
		_player.stop()
	finished.emit()


## Editor preview controls. AudioStreamPlayer.stream_paused keeps `.playing == true`,
## so is_playing() above continues to return true while paused — handles can resume cleanly.
## Timeline-mode voices are paused by the runtime dispatcher via the [code]_paused[/code] flag.
func pause() -> void:
	_paused = true
	if is_timeline and timeline_runtime != null and is_instance_valid(timeline_runtime):
		timeline_runtime.pause_timeline_preview(self)
		return
	if _player != null and is_instance_valid(_player):
		_player.stream_paused = true


func resume() -> void:
	if is_timeline and timeline_runtime != null and is_instance_valid(timeline_runtime):
		timeline_runtime.resume_timeline_preview(self)
		return
	_paused = false
	if _player != null and is_instance_valid(_player):
		_player.stream_paused = false


func is_paused() -> bool:
	if is_timeline:
		return _paused
	if _player == null or not is_instance_valid(_player):
		return false
	return _player.stream_paused


func seek(time_seconds: float) -> void:
	if is_timeline:
		timeline_pending_seek_seconds = maxf(0.0, time_seconds)
		return
	if _player == null or not is_instance_valid(_player):
		return
	_player.seek(maxf(0.0, time_seconds))


func get_position() -> float:
	if is_timeline:
		return timeline_cursor_seconds
	if _player == null or not is_instance_valid(_player):
		return 0.0
	return _player.get_playback_position()


func get_length() -> float:
	if is_timeline:
		return timeline_length_seconds
	if _player == null or not is_instance_valid(_player):
		return 0.0
	if _player.stream == null:
		return 0.0
	return _player.stream.get_length()


func get_bus_name() -> String:
	return _bus_name


func _bind_player(player: AudioStreamPlayer) -> void:
	_player = player


func clear_player_binding() -> void:
	_player = null


func _on_player_finished() -> void:
	if loop and _alive and _player != null and is_instance_valid(_player):
		_player.play()
		return
	if _alive:
		_alive = false
		finished.emit()
