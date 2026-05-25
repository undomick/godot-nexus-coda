@tool
class_name CodaVoicePool
extends Node

## Pool of AudioStreamPlayers. Picks an idle player when starting a voice; emits a "voice_finished"
## signal so the runtime can clean up handles.

signal voice_finished(player: AudioStreamPlayer)

const DEFAULT_POOL_SIZE := 24

@export var pool_size: int = DEFAULT_POOL_SIZE

var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_ensure_pool_size()


func _ensure_pool_size() -> void:
	while _players.size() < pool_size:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.finished.connect(_on_player_finished.bind(p))
		add_child(p)
		_players.append(p)


func acquire() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return null


func active_count() -> int:
	var n := 0
	for p in _players:
		if p.playing:
			n += 1
	return n


func all_players() -> Array[AudioStreamPlayer]:
	return _players.duplicate()


func stop_all() -> void:
	for p in _players:
		if p.playing:
			p.stop()


func _on_player_finished(player: AudioStreamPlayer) -> void:
	voice_finished.emit(player)
