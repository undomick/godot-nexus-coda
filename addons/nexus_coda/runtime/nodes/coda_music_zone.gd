@tool
extends Node
class_name CodaMusicZone

## Starts or stops music on a slot when the gameplay zone is entered or left.
## Connect Area2D/Area3D body_entered/body_exited to [method enter] / [method exit],
## or call those methods from gameplay code directly.

@export var event_path: String = ""
@export var fade_ms: int = -1
@export var music_slot: String = "default"
@export var stop_on_exit: bool = true
@export var sync_to_bar: bool = false


func enter(params: Dictionary = {}) -> void:
	var music: CodaMusicDirector = _music()
	if music == null:
		push_warning("CodaMusicZone: CodaMusic autoload not found.")
		return
	var path: String = event_path.strip_edges()
	if path.is_empty():
		return
	music.set_music(path, fade_ms, music_slot, params, sync_to_bar)


func exit(exit_fade_ms: int = -1) -> void:
	if not stop_on_exit:
		return
	var music: CodaMusicDirector = _music()
	if music == null:
		return
	var actual_fade: int = exit_fade_ms if exit_fade_ms >= 0 else fade_ms
	music.stop_music(music_slot, actual_fade, sync_to_bar)


func on_body_entered(body: Node, params: Dictionary = {}) -> void:
	var payload: Dictionary = params.duplicate(true)
	if body != null:
		payload["body"] = body.name
	enter(payload)


func on_body_exited(_body: Node = null) -> void:
	exit()


static func _music() -> CodaMusicDirector:
	var node: Node = Engine.get_main_loop().root.get_node_or_null("CodaMusic")
	if node is CodaMusicDirector:
		return node as CodaMusicDirector
	return null
