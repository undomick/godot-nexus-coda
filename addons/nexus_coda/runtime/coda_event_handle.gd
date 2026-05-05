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

var _player: AudioStreamPlayer = null
var _bus_name: String = "Master"
var _alive: bool = true


func _init() -> void:
	started_at_msec = Time.get_ticks_msec()


func is_playing() -> bool:
	if not _alive:
		return false
	if _player == null or not is_instance_valid(_player):
		return false
	return _player.playing


func stop(_fade_ms: int = 0) -> void:
	# Phase 4 will add proper fade; for MVP we stop immediately.
	_alive = false
	if _player != null and is_instance_valid(_player) and _player.playing:
		_player.stop()
	finished.emit()


func _bind_player(player: AudioStreamPlayer) -> void:
	_player = player


func _on_player_finished() -> void:
	if loop and _player != null and is_instance_valid(_player):
		_player.play()
		return
	_alive = false
	finished.emit()
