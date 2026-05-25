@tool
extends Node
class_name CodaMusicDirector

## High-level music API: slotted timeline playback, crossfades, stingers via post_stinger.

const CodaMusicClockScript := preload("res://addons/nexus_coda/runtime/coda_music_clock.gd")
const CodaMusicTransitionPolicyScript := preload(
	"res://addons/nexus_coda/runtime/coda_music_transition_policy.gd"
)

var _runtime: CodaRuntime = null
var _policy: CodaMusicTransitionPolicy = null
var _slots: Dictionary = {}
var _pending_quantized: Array[Dictionary] = []


func bind_runtime(runtime: CodaRuntime) -> void:
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
	var slot_key: String = _normalize_slot(slot)
	var actual_fade: int = fade_ms if fade_ms >= 0 else _event_crossfade_ms()
	if _try_queue_at_next_bar(
		slot_key,
		{
			"kind": "set_music",
			"event_path": path,
			"fade_ms": actual_fade,
			"params": params.duplicate(true),
		},
		_should_quantize_to_bar(sync_to_bar)
	):
		return _slot_handle(slot_key)
	return _set_music_immediate(path, actual_fade, slot_key, params)


func post_stinger(event_path: String, params: Dictionary = {}) -> CodaEventHandle:
	if _runtime == null:
		return null
	return _runtime.play(event_path, params)


func stop_music(slot: String = "default", fade_ms: int = -1, sync_to_bar: bool = false) -> void:
	if _runtime == null:
		return
	var slot_key: String = _normalize_slot(slot)
	var actual_fade: int = fade_ms if fade_ms >= 0 else _event_crossfade_ms()
	if _try_queue_at_next_bar(
		slot_key,
		{"kind": "stop_music", "fade_ms": actual_fade},
		_should_quantize_to_bar(sync_to_bar)
	):
		return
	_stop_slot(slot_key, actual_fade)


func get_slot_handle(slot: String = "default") -> CodaEventHandle:
	return _slot_handle(_normalize_slot(slot))


func set_slot_parameter(slot: String, name_or_id: String, value: Variant) -> bool:
	if _runtime == null:
		return false
	var key: String = String(name_or_id).strip_edges()
	if key.is_empty():
		return false
	var slot_key: String = _normalize_slot(slot)
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
	_cancel_pending_quantized_for_slot(slot_key)
	var existing: Dictionary = _slots.get(slot_key, {}) as Dictionary
	var active: CodaEventHandle = _slot_handle(slot_key)
	var old_path: String = str(existing.get("event_path", ""))
	if active != null and _runtime.is_alive(active) and old_path == event_path:
		for key in params.keys():
			_runtime.set_parameter(active, String(key), params[key])
		return active
	_stop_outgoing_in_slot(existing, fade_ms)
	var old_handle: CodaEventHandle = existing.get("handle", null) as CodaEventHandle
	var new_handle: CodaEventHandle = _runtime.play(event_path, params)
	if new_handle == null:
		return null
	if old_handle != null and _runtime.is_alive(old_handle) and old_handle != new_handle:
		existing["outgoing_handle"] = old_handle
		_runtime.stop(old_handle, fade_ms)
	var slot_state: Dictionary = {
		"handle": new_handle,
		"event_path": event_path,
		"outgoing_handle": null,
	}
	slot_state.merge(_slot_meta(existing))
	_slots[slot_key] = slot_state
	if fade_ms > 0 and new_handle.is_timeline:
		new_handle.params["_coda_music_fade_in_ms"] = fade_ms
	return new_handle


func _stop_slot(slot_key: String, fade_ms: int) -> void:
	_cancel_pending_quantized_for_slot(slot_key)
	var existing: Dictionary = _slots.get(slot_key, {}) as Dictionary
	_stop_outgoing_in_slot(existing, 0)
	var handle: CodaEventHandle = existing.get("handle", null) as CodaEventHandle
	if handle != null and _runtime.is_alive(handle):
		_runtime.stop(handle, fade_ms)
		if fade_ms > 0:
			var fading_slot: Dictionary = {
				"outgoing_handle": handle,
				"event_path": str(existing.get("event_path", "")),
			}
			fading_slot.merge(_slot_meta(existing))
			_slots[slot_key] = fading_slot
			return
	_slots.erase(slot_key)


func _slot_handle(slot_key: String) -> CodaEventHandle:
	var existing: Dictionary = _slots.get(slot_key, {}) as Dictionary
	var primary: CodaEventHandle = existing.get("handle", null) as CodaEventHandle
	if primary != null:
		return primary
	return existing.get("outgoing_handle", null) as CodaEventHandle


func _normalize_slot(slot: String) -> String:
	return slot if not slot.is_empty() else "default"


func _should_quantize_to_bar(sync_to_bar: bool) -> bool:
	return sync_to_bar or (_policy != null and _policy.quantize_to_bar)


func _try_queue_at_next_bar(slot_key: String, item: Dictionary, quantize: bool) -> bool:
	if not quantize:
		return false
	var wait_sec: float = _seconds_until_next_bar(_music_cursor_for_slot(slot_key), slot_key)
	if wait_sec <= 0.001:
		return false
	item["fire_at"] = Time.get_ticks_msec() + int(wait_sec * 1000.0)
	item["slot"] = slot_key
	_queue_quantized(item)
	return true


func _slot_meta(existing: Dictionary) -> Dictionary:
	return {
		"priority": int(existing.get("priority", 0)),
		"paused": bool(existing.get("paused", false)),
	}


func _stop_outgoing_in_slot(existing: Dictionary, fade_ms: int) -> void:
	var outgoing: CodaEventHandle = existing.get("outgoing_handle", null) as CodaEventHandle
	if outgoing != null and _runtime.is_alive(outgoing):
		_runtime.stop(outgoing, fade_ms)


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
	var event: CodaBrowserNode = h.event_node as CodaBrowserNode
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
