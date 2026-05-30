@tool
class_name CodaProjectSerializer
extends RefCounted

## Serializes and hydrates [CodaState] project documents (.ncoda).

const CodaGameSyncRuleScript := preload(
	"res://addons/nexus_coda/domain/coda_game_sync_rule.gd"
)


static func to_dictionary(state: CodaState) -> Dictionary:
	var snaps_arr: Array = []
	for s in state.snapshots:
		snaps_arr.append(s.to_dictionary())
	var banks_arr: Array = []
	for b in state.banks:
		banks_arr.append(b.to_dictionary())
	var rules_arr: Array = []
	for r in state.game_sync_rules:
		rules_arr.append(r.to_dictionary())
	return {
		"version": 5,
		"events": state.events_root.to_dictionary(),
		"assets": state.assets_root.to_dictionary(),
		"buses": state.bus_root.to_dictionary() if state.bus_root != null else CodaBus.make_default_master().to_dictionary(),
		"snapshots": snaps_arr,
		"banks": banks_arr,
		"game_sync_rules": rules_arr,
		"appearance": {
			"theme_mode": state.theme_mode,
			"accent_color": [state.accent_color.r, state.accent_color.g, state.accent_color.b, state.accent_color.a],
		},
	}


static func load_from_dictionary(state: CodaState, data: Dictionary) -> void:
	var ev: Variant = data.get("events", {})
	if ev is Dictionary:
		state.events_root = CodaBrowserNode.from_dictionary(ev)
	else:
		state.events_root = CodaBrowserNode.new("Events", CodaBrowserNode.Kind.FOLDER)
	var as_: Variant = data.get("assets", {})
	if as_ is Dictionary:
		state.assets_root = CodaBrowserNode.from_dictionary(as_)
	else:
		state.assets_root = CodaBrowserNode.new("Assets", CodaBrowserNode.Kind.FOLDER)
	var buses_raw: Variant = data.get("buses", null)
	if buses_raw is Dictionary:
		state.bus_root = CodaBus.from_dictionary(buses_raw)
	else:
		state.bus_root = CodaBus.make_default_master()
	state.snapshots.clear()
	for s_raw in data.get("snapshots", []) as Array:
		if s_raw is Dictionary:
			state.snapshots.append(CodaSnapshot.from_dictionary(s_raw))
	state.banks.clear()
	for b_raw in data.get("banks", []) as Array:
		if b_raw is Dictionary:
			state.banks.append(CodaBank.from_dictionary(b_raw))
	state.game_sync_rules.clear()
	for r_raw in data.get("game_sync_rules", []) as Array:
		if r_raw is Dictionary:
			state.game_sync_rules.append(CodaGameSyncRuleScript.from_dictionary(r_raw))
	state.theme_mode = "dark"
	state.accent_color = Color(0.42, 0.74, 1.00, 1.0)
	var appearance_raw: Variant = data.get("appearance", null)
	if appearance_raw is Dictionary:
		var ap: Dictionary = appearance_raw
		var mode_raw: String = str(ap.get("theme_mode", "dark")).to_lower()
		if mode_raw == "light" or mode_raw == "dark":
			state.theme_mode = mode_raw
		var ac_raw: Variant = ap.get("accent_color", null)
		if ac_raw is Array and (ac_raw as Array).size() >= 3:
			var ac_arr: Array = ac_raw
			state.accent_color = Color(
				float(ac_arr[0]),
				float(ac_arr[1]),
				float(ac_arr[2]),
				float(ac_arr[3]) if ac_arr.size() >= 4 else 1.0
			)
	state.structure_changed.emit()
