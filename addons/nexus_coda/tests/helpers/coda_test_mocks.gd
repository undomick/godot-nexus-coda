extends Node
class_name CodaTestMockRuntime

## Lightweight runtime stand-in for director/bridge unit tests.

const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaMusicTransitionPolicyScript := preload(
	"res://addons/nexus_coda/runtime/coda_music_transition_policy.gd"
)

var play_calls: Array[Dictionary] = []
var stop_calls: Array[Dictionary] = []
var set_parameter_calls: Array[Dictionary] = []
var notify_calls: Array[CodaEventHandle] = []
var apply_snapshot_calls: Array[Dictionary] = []
var _next_id: int = 1
var _policy: CodaMusicTransitionPolicy = CodaMusicTransitionPolicyScript.default_policy()


func play(path: String, params: Dictionary = {}) -> CodaEventHandle:
	var h: CodaEventHandle = CodaEventHandleScript.new()
	h.id = _next_id
	_next_id += 1
	h._alive = true
	h.event_path = path
	h.params = params.duplicate(true)
	h.is_timeline = bool(params.get("_test_timeline", false))
	play_calls.append({"path": path, "params": params, "handle": h})
	return h


func stop(handle: CodaEventHandle, fade_ms: int = 0) -> void:
	stop_calls.append({"handle": handle, "fade_ms": fade_ms})
	if handle != null:
		handle._alive = false


func is_alive(handle: CodaEventHandle) -> bool:
	return handle != null and handle._alive


func set_parameter(handle: CodaEventHandle, name_or_id: String, value: Variant) -> void:
	set_parameter_calls.append({"handle": handle, "name": name_or_id, "value": value})
	if handle != null:
		handle.param_values[name_or_id] = value


func notify_music_state_changed(handle: CodaEventHandle) -> void:
	notify_calls.append(handle)


func apply_snapshot(snapshot_id: String, blend_ms: int = -1) -> bool:
	apply_snapshot_calls.append({"snapshot_id": snapshot_id, "blend_ms": blend_ms})
	return true


func get_transition_policy() -> CodaMusicTransitionPolicy:
	return _policy
