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
	var merged: Dictionary = rule.parameter_overrides.duplicate(true)
	for key in payload.keys():
		merged[key] = payload[key]
	match rule.action:
		CodaGameSyncRule.Action.PLAY_EVENT:
			if ctx.play_fn.is_valid():
				ctx.play_fn.call(rule.target_event_path, merged)
		CodaGameSyncRule.Action.STOP_MUSIC:
			if ctx.stop_music_fn.is_valid():
				ctx.stop_music_fn.call(rule.music_slot, rule.fade_ms, rule.sync_to_bar)
		CodaGameSyncRule.Action.SET_PARAMETER:
			var handle: CodaEventHandle = _slot_handle(ctx, rule.music_slot)
			if handle != null and _is_alive(ctx, handle):
				for key in merged.keys():
					if ctx.set_parameter_fn.is_valid():
						ctx.set_parameter_fn.call(handle, String(key), merged[key])
		CodaGameSyncRule.Action.APPLY_SNAPSHOT:
			if not rule.snapshot_id.is_empty() and ctx.apply_snapshot_fn.is_valid():
				ctx.apply_snapshot_fn.call(rule.snapshot_id, rule.fade_ms)
		CodaGameSyncRule.Action.SET_MUSIC:
			if ctx.set_music_fn.is_valid():
				ctx.set_music_fn.call(
					rule.target_event_path, rule.fade_ms, rule.music_slot, merged, rule.sync_to_bar
				)
		CodaGameSyncRule.Action.SET_MUSIC_STATE:
			var h: CodaEventHandle = _slot_handle(ctx, rule.music_slot)
			if h == null or not _is_alive(ctx, h):
				return
			for key in merged.keys():
				if ctx.set_parameter_fn.is_valid():
					ctx.set_parameter_fn.call(h, String(key), merged[key])
			if ctx.notify_music_state_fn.is_valid():
				ctx.notify_music_state_fn.call(h)


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
	if expr.contains("="):
		var parts: PackedStringArray = expr.split("=", false, 1)
		if parts.size() == 2:
			var key: String = parts[0].strip_edges()
			var want: String = parts[1].strip_edges()
			return str(payload.get(key, "")) == want
	return true
