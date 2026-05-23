@tool
class_name CodaGameSyncRule
extends RefCounted

## Declarative mapping from a gameplay signal name to a Coda runtime action.
## Stored on [CodaState] and consumed by [CodaGameBridge] at runtime.

enum Action {
	PLAY_EVENT = 0,
	STOP_MUSIC = 1,
	SET_PARAMETER = 2,
	APPLY_SNAPSHOT = 3,
	SET_MUSIC = 4,
	SET_MUSIC_STATE = 5,
}

var id: String
var signal_name: String = ""
var action: Action = Action.SET_MUSIC
var target_event_path: String = ""
var parameter_overrides: Dictionary = {}
var fade_ms: int = 2000
var music_slot: String = "default"
var snapshot_id: String = ""
var sync_to_bar: bool = false
var enabled: bool = true
## Stub: optional condition (e.g. "zone=forest"); empty = always.
var condition_expression: String = ""
## Stub: transition matrix id for future per-pair fade rules.
var transition_id: String = ""


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "gsr_%d_%d" % [Time.get_ticks_usec(), randi()]


static func action_label(a: Action) -> String:
	match a:
		Action.PLAY_EVENT:
			return "Play Event"
		Action.STOP_MUSIC:
			return "Stop Music"
		Action.SET_PARAMETER:
			return "Set Parameter"
		Action.APPLY_SNAPSHOT:
			return "Apply Snapshot"
		Action.SET_MUSIC:
			return "Set Music"
		Action.SET_MUSIC_STATE:
			return "Set Music State"
	return "?"


func clone_keep_id() -> CodaGameSyncRule:
	var r := CodaGameSyncRule.new()
	r.id = id
	r.signal_name = signal_name
	r.action = action
	r.target_event_path = target_event_path
	r.parameter_overrides = parameter_overrides.duplicate(true)
	r.fade_ms = fade_ms
	r.music_slot = music_slot
	r.snapshot_id = snapshot_id
	r.sync_to_bar = sync_to_bar
	r.enabled = enabled
	r.condition_expression = condition_expression
	r.transition_id = transition_id
	return r


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"signal_name": signal_name,
		"action": int(action),
		"target_event_path": target_event_path,
		"parameter_overrides": parameter_overrides.duplicate(true),
		"fade_ms": fade_ms,
		"music_slot": music_slot,
		"snapshot_id": snapshot_id,
		"sync_to_bar": sync_to_bar,
		"enabled": enabled,
		"condition_expression": condition_expression,
		"transition_id": transition_id,
	}


static func from_dictionary(data: Dictionary) -> CodaGameSyncRule:
	var r := CodaGameSyncRule.new()
	var sid: String = str(data.get("id", "")).strip_edges()
	if not sid.is_empty():
		r.id = sid
	r.signal_name = str(data.get("signal_name", ""))
	var act: int = int(data.get("action", Action.SET_MUSIC))
	match act:
		Action.PLAY_EVENT, Action.STOP_MUSIC, Action.SET_PARAMETER, Action.APPLY_SNAPSHOT, Action.SET_MUSIC, Action.SET_MUSIC_STATE:
			r.action = act as Action
		_:
			r.action = Action.SET_MUSIC
	r.target_event_path = str(data.get("target_event_path", ""))
	var po: Variant = data.get("parameter_overrides", {})
	if po is Dictionary:
		r.parameter_overrides = (po as Dictionary).duplicate(true)
	r.fade_ms = maxi(0, int(data.get("fade_ms", 2000)))
	r.music_slot = str(data.get("music_slot", "default"))
	if r.music_slot.is_empty():
		r.music_slot = "default"
	r.snapshot_id = str(data.get("snapshot_id", ""))
	r.sync_to_bar = bool(data.get("sync_to_bar", false))
	r.enabled = bool(data.get("enabled", true))
	r.condition_expression = str(data.get("condition_expression", ""))
	r.transition_id = str(data.get("transition_id", ""))
	return r
