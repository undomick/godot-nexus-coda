@tool
extends Node
class_name CodaMusicDirector

## High-level music API: one active timeline/graph event per music slot, crossfades between
## [method set_music] calls, and parallel stingers via [method post_stinger].

const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")
const CodaMusicClockScript := preload("res://addons/nexus_coda/runtime/coda_music_clock.gd")
const CodaMusicTransitionPolicyScript := preload(
	"res://addons/nexus_coda/runtime/coda_music_transition_policy.gd"
)

var _runtime = null
var _policy: CodaMusicTransitionPolicy = null
## slot -> { handle, event_path, outgoing_handle, priority, paused }
var _slots: Dictionary = {}
var _pending_quantized: Array[Dictionary] = []


func bind_runtime(runtime) -> void:
	_runtime = runtime
	if runtime != null and runtime.has_method("get_transition_policy"):
		_policy = runtime.get_transition_policy()
	else:
		_policy = CodaMusicTransitionPolicyScript.default_policy()


func _ready() -> void:
	call_deferred(&"_auto_bind")


func _auto_bind() -> void:
	if _runtime != null:
		return
	var coda: Node = get_node_or_null("/root/Coda")
	if coda is CodaRuntime:
		bind_runtime(coda as CodaRuntime)
	var bridge: Node = get_node_or_null("/root/CodaGameBridge")
	if bridge != null and bridge.has_method("bind_runtime"):
		bridge.bind_runtime(coda, self)


func set_music(
	event_path: String,
	fade_ms: int = -1,
	slot: String = "default",
	params: Dictionary = {},
	sync_to_bar: bool = false
) -> CodaEventHandle:
	if _runtime == null:
		push_warning("CodaMusic: no runtime bound")
		return null
	var path: String = event_path.strip_edges()
	if path.is_empty():
		return null
	var slot_key: String = slot if not slot.is_empty() else "default"
	var actual_fade: int = fade_ms if fade_ms >= 0 else _event_crossfade_ms()
	var do_sync: bool = sync_to_bar or (_policy != null and _policy.quantize_to_bar)
	if do_sync:
		var cursor: float = _music_cursor_for_slot(slot_key)
		var wait_sec: float = _seconds_until_next_bar(cursor, slot_key)
		if wait_sec > 0.001:
			_queue_quantized(
				{
					"kind": "set_music",
					"event_path": path,
					"fade_ms": actual_fade,
					"slot": slot_key,
					"params": params.duplicate(true),
					"fire_at": Time.get_ticks_msec() + int(wait_sec * 1000.0),
				}
			)
			return _slot_handle(slot_key)
	return _set_music_immediate(path, actual_fade, slot_key, params)


func post_stinger(event_path: String, params: Dictionary = {}) -> CodaEventHandle:
	if _runtime == null:
		return null
	# Extension stub: policy.max_stingers / duck_music_db not enforced yet.
	return _runtime.play(event_path, params)


func stop_music(slot: String = "default", fade_ms: int = -1, sync_to_bar: bool = false) -> void:
	if _runtime == null:
		return
	var slot_key: String = slot if not slot.is_empty() else "default"
	var actual_fade: int = fade_ms if fade_ms >= 0 else _event_crossfade_ms()
	var do_sync: bool = sync_to_bar or (_policy != null and _policy.quantize_to_bar)
	if do_sync:
		var cursor: float = _music_cursor_for_slot(slot_key)
		var wait_sec: float = _seconds_until_next_bar(cursor, slot_key)
		if wait_sec > 0.001:
			_queue_quantized(
				{
					"kind": "stop_music",
					"slot": slot_key,
					"fade_ms": actual_fade,
					"fire_at": Time.get_ticks_msec() + int(wait_sec * 1000.0),
				}
			)
			return
	_stop_slot(slot_key, actual_fade)


func get_slot_handle(slot: String = "default") -> CodaEventHandle:
	return _slot_handle(slot if not slot.is_empty() else "default")


## Routes parameter writes to a queued [method set_music] when bar-quantized, otherwise the live slot handle.
## Returns true when the value was applied to a live handle (caller may notify segment drivers).
func set_slot_parameter(slot: String, name_or_id: String, value: Variant) -> bool:
	if _runtime == null:
		return false
	var key: String = String(name_or_id).strip_edges()
	if key.is_empty():
		return false
	var slot_key: String = slot if not slot.is_empty() else "default"
	var pending: Dictionary = _pending_set_music_item_for_slot(slot_key)
	if not pending.is_empty():
		var params: Dictionary = pending.get("params", {}) as Dictionary
		params[key] = value
		pending["params"] = params
		return false
	var handle: CodaEventHandle = _slot_handle(slot_key)
	if handle == null or not _runtime.is_alive(handle):
		return false
	_runtime.set_parameter(handle, key, value)
	return true


func _process(_delta: float) -> void:
	if _pending_quantized.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var remaining: Array[Dictionary] = []
	for item in _pending_quantized:
		if int(item.get("fire_at", 0)) > now:
			remaining.append(item)
			continue
		match str(item.get("kind", "")):
			"set_music":
				_set_music_immediate(
					str(item.get("event_path", "")),
					int(item.get("fade_ms", _event_crossfade_ms())),
					str(item.get("slot", "default")),
					item.get("params", {}) as Dictionary
				)
			"stop_music":
				_stop_slot(str(item.get("slot", "default")), int(item.get("fade_ms", _event_crossfade_ms())))
	_pending_quantized = remaining


func _set_music_immediate(
	event_path: String, fade_ms: int, slot_key: String, params: Dictionary
) -> CodaEventHandle:
	var existing: Dictionary = _slots.get(slot_key, {}) as Dictionary
	var old_handle: CodaEventHandle = existing.get("handle", null) as CodaEventHandle
	var old_path: String = str(existing.get("event_path", ""))
	if old_handle != null and _runtime.is_alive(old_handle) and old_path == event_path:
		for key in params.keys():
			_runtime.set_parameter(old_handle, String(key), params[key])
		return old_handle
	var new_handle: CodaEventHandle = _runtime.play(event_path, params)
	if new_handle == null:
		return null
	if old_handle != null and _runtime.is_alive(old_handle):
		existing["outgoing_handle"] = old_handle
		_runtime.stop(old_handle, fade_ms)
	_slots[slot_key] = {
		"handle": new_handle,
		"event_path": event_path,
		"outgoing_handle": null,
		"priority": int(existing.get("priority", 0)),
		"paused": bool(existing.get("paused", false)),
	}
	if fade_ms > 0 and new_handle.is_timeline:
		new_handle.params["_coda_music_fade_in_ms"] = fade_ms
	return new_handle


func _stop_slot(slot_key: String, fade_ms: int) -> void:
	var existing: Dictionary = _slots.get(slot_key, {}) as Dictionary
	var handle: CodaEventHandle = existing.get("handle", null) as CodaEventHandle
	if handle != null and _runtime.is_alive(handle):
		_runtime.stop(handle, fade_ms)
	_slots.erase(slot_key)


func _slot_handle(slot_key: String) -> CodaEventHandle:
	var existing: Dictionary = _slots.get(slot_key, {}) as Dictionary
	return existing.get("handle", null) as CodaEventHandle


func _event_crossfade_ms() -> int:
	if _policy != null:
		return _policy.event_crossfade_ms
	return 2000


func _music_cursor_for_slot(slot_key: String) -> float:
	var h: CodaEventHandle = _slot_handle(slot_key)
	if h == null:
		return 0.0
	if _policy != null:
		return _policy.get_music_cursor_seconds(h)
	if h.is_timeline:
		return h.timeline_cursor_seconds
	return 0.0


func _seconds_until_next_bar(cursor: float, slot_key: String = "default") -> float:
	var h: CodaEventHandle = _slot_handle(slot_key)
	if h == null:
		return 0.0
	var event := h.event_node as CodaBrowserNode
	if event == null or event.event_timeline == null:
		return 0.0
	var tl: CodaEventTimeline = event.event_timeline
	if tl.tempo_bpm <= 0.0:
		return 0.0
	return CodaMusicClockScript.time_until_next_bar(cursor, tl.tempo_bpm, tl.time_signature)


func _queue_quantized(item: Dictionary) -> void:
	var slot_key: String = str(item.get("slot", "default"))
	_cancel_pending_quantized_for_slot(slot_key)
	_pending_quantized.append(item)


func _cancel_pending_quantized_for_slot(slot_key: String) -> void:
	var remaining: Array[Dictionary] = []
	for pending in _pending_quantized:
		if str(pending.get("slot", "default")) != slot_key:
			remaining.append(pending)
	_pending_quantized = remaining


func _pending_set_music_item_for_slot(slot_key: String) -> Dictionary:
	for pending in _pending_quantized:
		if str(pending.get("kind", "")) != "set_music":
			continue
		if str(pending.get("slot", "default")) == slot_key:
			return pending
	return {}
