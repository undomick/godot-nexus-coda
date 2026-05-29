@tool
extends Node
class_name CodaEventEmitter

## Plays a Coda event from the scene tree. Thin wrapper around the Coda autoload.

@export var event_path: String = ""
@export var play_on_ready: bool = false
@export var stop_on_exit: bool = true

var _handle: CodaEventHandle = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if play_on_ready:
		play()


func play(params: Dictionary = {}) -> CodaEventHandle:
	var runtime: CodaRuntime = _runtime()
	if runtime == null:
		push_warning("CodaEventEmitter: Coda autoload not found.")
		return null
	var path: String = event_path.strip_edges()
	if path.is_empty():
		return null
	_handle = runtime.play(path, params)
	return _handle


func stop(fade_ms: int = 0) -> void:
	if _handle == null:
		return
	_handle.stop(fade_ms)
	_handle = null


func get_handle() -> CodaEventHandle:
	return _handle


func _exit_tree() -> void:
	if Engine.is_editor_hint() or not stop_on_exit:
		return
	stop()


static func _runtime() -> CodaRuntime:
	var coda: Node = Engine.get_main_loop().root.get_node_or_null("Coda")
	if coda is CodaRuntime:
		return coda as CodaRuntime
	return null
