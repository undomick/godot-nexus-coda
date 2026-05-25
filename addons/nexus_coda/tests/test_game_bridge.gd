extends RefCounted
class_name TestGameBridge

const CodaGameSyncRuleScript := preload("res://addons/nexus_coda/editor/browser/coda_game_sync_rule.gd")
const CodaGameSyncContextScript := preload("res://addons/nexus_coda/runtime/coda_game_sync_context.gd")
const CodaGameSyncDispatcherScript := preload(
	"res://addons/nexus_coda/runtime/coda_game_sync_dispatcher.gd"
)
const CodaGameBridgeScript := preload("res://addons/nexus_coda/runtime/coda_game_bridge.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_rule_roundtrip()
	failed += _test_all_actions()
	failed += _test_condition_expression()
	failed += _test_payload_from_signal_arg()
	failed += _test_set_music_state_ignores_unlisted_payload_keys()
	return failed


static func _test_rule_roundtrip() -> int:
	var rule = CodaGameSyncRuleScript.new()
	rule.signal_name = "combat_started"
	rule.action = CodaGameSyncRuleScript.Action.SET_MUSIC
	rule.target_event_path = "music/combat"
	rule.condition_expression = "zone=forest"
	rule.transition_id = "combat_in"
	var data: Dictionary = rule.to_dictionary()
	var restored = CodaGameSyncRuleScript.from_dictionary(data)
	if restored.signal_name != "combat_started":
		push_error("game sync rule roundtrip failed")
		return 1
	if restored.condition_expression != "zone=forest":
		push_error("condition_expression roundtrip failed")
		return 1
	return 0


static func _test_all_actions() -> int:
	var calls: Dictionary = {
		"play": [],
		"set_music": [],
		"stop_music": [],
		"set_parameter": [],
		"apply_snapshot": [],
		"notify": [],
	}
	var alive_handle: CodaEventHandle = CodaEventHandleScript.new()
	alive_handle._alive = true
	var ctx := CodaGameSyncContextScript.new()
	ctx.play_fn = func(path: String, params: Dictionary) -> void: calls["play"].append({"path": path, "params": params})
	ctx.set_music_fn = func(path: String, fade: int, slot: String, params: Dictionary, sync: bool) -> void:
		calls["set_music"].append({"path": path, "fade": fade, "slot": slot})
	ctx.stop_music_fn = func(slot: String, fade: int, sync: bool) -> void:
		calls["stop_music"].append({"slot": slot, "fade": fade})
	ctx.set_parameter_fn = func(h: CodaEventHandle, name: String, value: Variant) -> void:
		calls["set_parameter"].append({"name": name, "value": value})
	ctx.set_slot_parameter_fn = func(slot: String, name: String, value: Variant) -> bool:
		var h: CodaEventHandle = ctx.get_slot_handle_fn.call(slot) as CodaEventHandle
		if h == null:
			return false
		ctx.set_parameter_fn.call(h, name, value)
		return true
	ctx.apply_snapshot_fn = func(sid: String, fade: int) -> void:
		calls["apply_snapshot"].append({"snapshot_id": sid, "fade": fade})
	ctx.notify_music_state_fn = func(h: CodaEventHandle) -> void: calls["notify"].append(h)
	ctx.get_slot_handle_fn = func(_slot: String) -> CodaEventHandle: return alive_handle
	ctx.is_alive_fn = func(_h: CodaEventHandle) -> bool: return true

	var play_rule := _make_rule(CodaGameSyncRuleScript.Action.PLAY_EVENT, "play_evt")
	play_rule.target_event_path = "sfx/hit"
	CodaGameSyncDispatcherScript.dispatch(play_rule, {}, ctx)
	if calls["play"].size() != 1:
		push_error("PLAY_EVENT dispatch failed")
		return 1

	var stop_rule := _make_rule(CodaGameSyncRuleScript.Action.STOP_MUSIC, "stop")
	CodaGameSyncDispatcherScript.dispatch(stop_rule, {}, ctx)
	if calls["stop_music"].size() != 1:
		push_error("STOP_MUSIC dispatch failed")
		return 1

	var param_rule := _make_rule(CodaGameSyncRuleScript.Action.SET_PARAMETER, "param")
	param_rule.parameter_overrides = {"intensity": 0.8}
	CodaGameSyncDispatcherScript.dispatch(param_rule, {}, ctx)
	if calls["set_parameter"].size() != 1:
		push_error("SET_PARAMETER dispatch failed")
		return 1

	var snap_rule := _make_rule(CodaGameSyncRuleScript.Action.APPLY_SNAPSHOT, "snap")
	snap_rule.snapshot_id = "quiet"
	CodaGameSyncDispatcherScript.dispatch(snap_rule, {}, ctx)
	if calls["apply_snapshot"].size() != 1:
		push_error("APPLY_SNAPSHOT dispatch failed")
		return 1

	var music_rule := _make_rule(CodaGameSyncRuleScript.Action.SET_MUSIC, "music")
	music_rule.target_event_path = "music/combat"
	CodaGameSyncDispatcherScript.dispatch(music_rule, {}, ctx)
	if calls["set_music"].size() != 1:
		push_error("SET_MUSIC dispatch failed")
		return 1

	var state_rule := _make_rule(CodaGameSyncRuleScript.Action.SET_MUSIC_STATE, "state")
	state_rule.parameter_overrides = {"music_state": 2}
	CodaGameSyncDispatcherScript.dispatch(state_rule, {}, ctx)
	if calls["set_parameter"].size() != 2:
		push_error("SET_MUSIC_STATE should set parameter")
		return 1
	if calls["notify"].size() != 1:
		push_error("SET_MUSIC_STATE should notify music state")
		return 1
	return 0


static func _test_condition_expression() -> int:
	var rule := _make_rule(CodaGameSyncRuleScript.Action.SET_MUSIC, "zone")
	rule.condition_expression = "zone=forest"
	if not CodaGameSyncDispatcherScript.rule_matches(rule, "zone", {"zone": "forest"}):
		push_error("condition should pass for matching zone")
		return 1
	if CodaGameSyncDispatcherScript.rule_matches(rule, "zone", {"zone": "desert"}):
		push_error("condition should fail for non-matching zone")
		return 1
	var unsupported := _make_rule(CodaGameSyncRuleScript.Action.SET_MUSIC, "zone")
	unsupported.condition_expression = "zone!=forest"
	if CodaGameSyncDispatcherScript.rule_matches(unsupported, "zone", {"zone": "forest"}):
		push_error("unsupported condition expressions must not match")
		return 1
	return 0


static func _test_set_music_state_ignores_unlisted_payload_keys() -> int:
	var calls: Dictionary = {"set_parameter": []}
	var alive_handle: CodaEventHandle = CodaEventHandleScript.new()
	alive_handle._alive = true
	var ctx := CodaGameSyncContextScript.new()
	ctx.set_slot_parameter_fn = func(slot: String, name: String, value: Variant) -> bool:
		calls["set_parameter"].append({"slot": slot, "name": name, "value": value})
		return true
	ctx.get_slot_handle_fn = func(_slot: String) -> CodaEventHandle:
		return alive_handle
	ctx.is_alive_fn = func(_h: CodaEventHandle) -> bool:
		return true
	ctx.notify_music_state_fn = func(_h: CodaEventHandle) -> void:
		pass
	var rule := _make_rule(CodaGameSyncRuleScript.Action.SET_MUSIC_STATE, "zone_entered")
	rule.parameter_overrides = {"music_state": 2}
	CodaGameSyncDispatcherScript.dispatch(rule, {"zone": "forest"}, ctx)
	if calls["set_parameter"].size() != 1:
		push_error("SET_MUSIC_STATE should only apply declared override keys")
		return 1
	if str(calls["set_parameter"][0].get("name", "")) != "music_state":
		push_error("SET_MUSIC_STATE should apply music_state, not zone")
		return 1
	if int(calls["set_parameter"][0].get("value", -1)) != 2:
		push_error("SET_MUSIC_STATE should use override value when payload has no music_state")
		return 1
	return 0


static func _test_payload_from_signal_arg() -> int:
	var dict_payload: Dictionary = CodaGameBridgeScript.payload_from_signal_arg({"zone": "forest"})
	if dict_payload.get("zone", "") != "forest":
		push_error("dictionary signal arg should pass through as payload")
		return 1
	var scalar: Dictionary = CodaGameBridgeScript.payload_from_signal_arg(42)
	if scalar.get("value", null) != 42:
		push_error("scalar signal arg should wrap as value")
		return 1
	if not CodaGameBridgeScript.payload_from_signal_arg(null).is_empty():
		push_error("null signal arg should yield empty payload")
		return 1
	return 0


static func _make_rule(action: CodaGameSyncRule.Action, signal_name: String) -> CodaGameSyncRule:
	var rule := CodaGameSyncRuleScript.new()
	rule.signal_name = signal_name
	rule.action = action
	return rule
