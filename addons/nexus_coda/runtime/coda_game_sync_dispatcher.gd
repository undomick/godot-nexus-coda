@tool
class_name CodaGameSyncDispatcher
extends RefCounted

## Pure rule dispatch — no Autoload or scene tree required.


static func rule_matches(rule: CodaGameSyncRule, signal_name: String, payload: Dictionary) -> bool:
	if rule == null or not rule.enabled:
		return false
	if rule.signal_name != signal_name.strip_edges():
		return false
	return _condition_passes(rule, payload)


static func dispatch(rule: CodaGameSyncRule, payload: Dictionary, ctx: CodaGameSyncContext) -> void:
	if ctx == null:
		return
	var merged: Dictionary = _merged_parameters(rule, payload)
	match rule.action:
		CodaGameSyncRule.Action.PLAY_EVENT:
			if ctx.play_fn.is_valid():
				ctx.play_fn.call(rule.target_event_path, merged)
		CodaGameSyncRule.Action.STOP_MUSIC:
			if ctx.stop_music_fn.is_valid():
				ctx.stop_music_fn.call(rule.music_slot, rule.fade_ms, rule.sync_to_bar)
		CodaGameSyncRule.Action.SET_PARAMETER:
			for key in _parameter_keys_for_apply(rule, payload):
				var k: String = String(key)
				if not merged.has(k):
					continue
				_apply_slot_parameter(ctx, rule.music_slot, k, merged[k])
		CodaGameSyncRule.Action.APPLY_SNAPSHOT:
			if not rule.snapshot_id.is_empty() and ctx.apply_snapshot_fn.is_valid():
				ctx.apply_snapshot_fn.call(rule.snapshot_id, rule.fade_ms)
		CodaGameSyncRule.Action.SET_MUSIC:
			if ctx.set_music_fn.is_valid():
				ctx.set_music_fn.call(
					rule.target_event_path, rule.fade_ms, rule.music_slot, merged, rule.sync_to_bar
				)
		CodaGameSyncRule.Action.SET_MUSIC_STATE:
			var applied_live: bool = false
			for key in _parameter_keys_for_apply(rule, payload):
				var k: String = String(key)
				if not merged.has(k):
					continue
				if _apply_slot_parameter(ctx, rule.music_slot, k, merged[k]):
					applied_live = true
			if applied_live and ctx.notify_music_state_fn.is_valid():
				var h: CodaEventHandle = _slot_handle(ctx, rule.music_slot)
				if h != null and _is_alive(ctx, h):
					ctx.notify_music_state_fn.call(h)


static func _merged_parameters(rule: CodaGameSyncRule, payload: Dictionary) -> Dictionary:
	var merged: Dictionary = rule.parameter_overrides.duplicate(true)
	for key in payload.keys():
		merged[key] = payload[key]
	return merged


static func _parameter_keys_for_apply(rule: CodaGameSyncRule, payload: Dictionary) -> Array:
	if not rule.parameter_overrides.is_empty():
		return rule.parameter_overrides.keys()
	return payload.keys()


static func _apply_slot_parameter(
	ctx: CodaGameSyncContext, slot: String, name_or_id: String, value: Variant
) -> bool:
	if ctx.set_slot_parameter_fn.is_valid():
		return bool(ctx.set_slot_parameter_fn.call(slot, name_or_id, value))
	var handle: CodaEventHandle = _slot_handle(ctx, slot)
	if handle == null or not _is_alive(ctx, handle):
		return false
	if ctx.set_parameter_fn.is_valid():
		ctx.set_parameter_fn.call(handle, name_or_id, value)
	return true


static func _slot_handle(ctx: CodaGameSyncContext, slot: String) -> CodaEventHandle:
	if ctx.get_slot_handle_fn.is_valid():
		return ctx.get_slot_handle_fn.call(slot) as CodaEventHandle
	return null


static func _is_alive(ctx: CodaGameSyncContext, handle: CodaEventHandle) -> bool:
	if ctx.is_alive_fn.is_valid():
		return bool(ctx.is_alive_fn.call(handle))
	return handle != null


static func _condition_passes(rule: CodaGameSyncRule, payload: Dictionary) -> bool:
	var expr: String = String(rule.condition_expression).strip_edges()
	if expr.is_empty():
		return true
	# Stub: full expression eval later; "zone=forest" matches payload.zone == "forest"
	if not expr.contains("="):
		return false
	var parts: PackedStringArray = expr.split("=", false, 1)
	if parts.size() != 2:
		return false
	var key: String = parts[0].strip_edges()
	var want: String = parts[1].strip_edges()
	if key.is_empty():
		return false
	return str(payload.get(key, "")) == want
