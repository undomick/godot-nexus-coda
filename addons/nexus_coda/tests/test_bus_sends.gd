extends RefCounted
class_name TestBusSends

## Unit tests for bus link resolution, wet sends, snapshots, and VCA volume.

const CodaBusSendRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_bus_send_runtime.gd")
const CodaAudioBusMirrorScript := preload("res://addons/nexus_coda/runtime/coda_audio_bus_mirror.gd")
const CodaVcaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_vca_runtime.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_effective_level_with_parameter()
	failed += _test_filter_active_sends_requires_return()
	failed += _test_resolve_bus_link_send_name()
	failed += _test_build_id_map()
	failed += _test_snapshot_wet_send_levels()
	failed += _test_vca_effective_volume()
	return failed


static func _make_tree_with_return() -> CodaBus:
	var master := CodaBus.make_default_master()
	var ret := CodaBus.new("Reverb Return")
	ret.bus_kind = CodaBus.BusKind.RETURN
	master.children[0].wet_sends.append(_make_send(ret.id, 0.5, ""))
	master.children.append(ret)
	return master


static func _make_send(target_id: String, level: float, param_id: String) -> CodaBusSend:
	var s := CodaBusSend.new()
	s.target_bus_id = target_id
	s.level = level
	s.parameter_id = param_id
	return s


static func _test_effective_level_with_parameter() -> int:
	var s := _make_send("ret", 0.8, "p1")
	if absf(CodaBusSendRuntimeScript.effective_level(s, {"p1": 0.5}) - 0.4) > 0.001:
		push_error("send level should multiply by parameter value")
		return 1
	return 0


static func _test_filter_active_sends_requires_return() -> int:
	var root := _make_tree_with_return()
	var sfx: CodaBus = root.children[0]
	var active: Array = CodaBusSendRuntimeScript.filter_active_sends(sfx.wet_sends, root, {})
	if active.size() != 1:
		push_error("expected one active wet send to return bus")
		return 1
	var bad := CodaBusSend.new()
	bad.target_bus_id = sfx.id
	bad.level = 1.0
	var none: Array = CodaBusSendRuntimeScript.filter_active_sends([bad], root, {})
	if not none.is_empty():
		push_error("send to non-return bus should be filtered out")
		return 1
	return 0


static func _test_resolve_bus_link_send_name() -> int:
	var root := CodaBus.make_default_master()
	var sfx: CodaBus = root.children[0]
	var music: CodaBus = root.children[1]
	sfx.send_target_id = music.id
	var send_nm: String = CodaAudioBusMirrorScript._resolve_send_name(sfx, "Master", root)
	if send_nm != music.bus_name:
		push_error("bus link should resolve to rerouted ancestor name")
		return 1
	return 0


static func _test_build_id_map() -> int:
	var root := CodaBus.make_default_master()
	var map: Dictionary = CodaAudioBusMirrorScript.build_id_map(root)
	var sfx: CodaBus = root.children[0]
	if String(map.get(sfx.id, "")) != "SFX":
		push_error("build_id_map should map SFX id to Godot bus name SFX")
		return 1
	if String(map.get(root.id, "")) != "Master":
		push_error("build_id_map should map root id to Master")
		return 1
	return 0


static func _test_snapshot_wet_send_levels() -> int:
	var root := _make_tree_with_return()
	var sfx: CodaBus = root.children[0]
	var send: CodaBusSend = sfx.wet_sends[0]
	var project := CodaProject.new()
	project.bus_root = root
	var snap := CodaSnapshot.new("Cave")
	snap.bus_overrides[sfx.id] = {
		"volume_db": 0.0,
		"mute": false,
		"solo": false,
		"bypass": false,
		"send_target_id": "",
		"wet_sends": {send.id: {"level": 1.0}},
	}
	project.snapshots.append(snap)
	project.apply_snapshot(snap.id)
	if absf(send.level - 1.0) > 0.001:
		push_error("snapshot should restore wet send level")
		return 1
	return 0


static func _test_vca_effective_volume() -> int:
	var root := CodaBus.make_default_master()
	var sfx: CodaBus = root.children[0]
	var vca := CodaVca.new("SFX VCA")
	vca.volume_db = -6.0
	vca.controlled_bus_ids = [sfx.id]
	sfx.volume_db = 0.0
	var eff: float = CodaVcaRuntimeScript.effective_volume_db(sfx, [vca])
	if absf(eff - (-6.0)) > 0.001:
		push_error("VCA should offset controlled bus volume")
		return 1
	return 0
