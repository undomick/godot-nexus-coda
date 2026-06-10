@tool
extends RefCounted
class_name CodaBusSendRuntime

## Resolves wet-send levels and applies bus-level send inserts during AudioServer mirror.

const CodaBusSendScript := preload("res://addons/nexus_coda/domain/coda_bus_send.gd")
const CodaEffectCatalogScript := preload(
	"res://addons/nexus_coda/domain/effects/coda_effect_catalog.gd"
)
const CodaTrackEffectScript := preload(
	"res://addons/nexus_coda/domain/effects/coda_track_effect.gd"
)
const CodaFxBusHelperScript := preload("res://addons/nexus_coda/runtime/coda_fx_bus_helper.gd")

const TAP_PREFIX := "__CodaSendTap_"


static func effective_level(send: CodaBusSend, param_values: Dictionary = {}) -> float:
	if send == null:
		return 0.0
	var base: float = clampf(send.level, 0.0, 1.0)
	var pid: String = String(send.parameter_id).strip_edges()
	if pid.is_empty():
		return base
	var mod: float = clampf(float(param_values.get(pid, 0.0)), 0.0, 1.0)
	return clampf(base * mod, 0.0, 1.0)


static func filter_active_sends(
	sends: Array[CodaBusSend],
	bus_root: CodaBus,
	param_values: Dictionary = {}
) -> Array[CodaBusSend]:
	var out: Array[CodaBusSend] = []
	if bus_root == null:
		return out
	for send in sends:
		if send == null:
			continue
		if effective_level(send, param_values) <= 0.001:
			continue
		var target: CodaBus = bus_root.find_by_id(send.target_bus_id)
		if target == null or target.bus_kind != CodaBus.BusKind.RETURN:
			continue
		out.append(send)
	return out


static func is_helper_tap_bus(name: String) -> bool:
	return String(name).begins_with(TAP_PREFIX)


static func build_send_insert_effects(
	active_sends: Array[CodaBusSend],
	bus_root: CodaBus,
	param_values: Dictionary = {}
) -> Array:
	var inserts: Array = []
	for send in active_sends:
		var target: CodaBus = bus_root.find_by_id(send.target_bus_id)
		if target == null:
			continue
		var amt: float = effective_level(send, param_values)
		if amt <= 0.001:
			continue
		for eff in target.effects:
			if not eff is CodaTrackEffect:
				continue
			var slot: CodaTrackEffect = (eff as CodaTrackEffect).clone_new_id()
			slot.params = slot.params.duplicate(true)
			match slot.type:
				CodaTrackEffect.Type.REVERB:
					slot.params["dry"] = 1.0
					slot.params["wet"] = float(slot.params.get("wet", 0.2)) * amt
				CodaTrackEffect.Type.DELAY:
					slot.params["dry"] = 1.0
					var tap1_db: float = float(slot.params.get("tap1_level_db", -6.0))
					slot.params["tap1_level_db"] = tap1_db + linear_to_db(amt)
				CodaTrackEffect.Type.CHORUS:
					slot.params["dry"] = 1.0
					slot.params["wet"] = float(slot.params.get("wet", 0.5)) * amt
				_:
					slot.params["gain_db"] = float(slot.params.get("gain_db", 0.0)) + linear_to_db(amt)
			inserts.append(slot)
	return inserts


static func apply_bus_wet_sends(
	source_bus: CodaBus,
	bus_idx: int,
	bus_root: CodaBus,
	param_values: Dictionary = {}
) -> void:
	if source_bus == null or bus_idx < 0 or bus_root == null:
		return
	var active: Array[CodaBusSend] = filter_active_sends(source_bus.wet_sends, bus_root, param_values)
	_clear_send_insert_effects(bus_idx, source_bus.effects.size())
	if active.is_empty():
		return
	var send_inserts: Array = build_send_insert_effects(active, bus_root, param_values)
	var base_count: int = source_bus.effects.size()
	for i in range(send_inserts.size()):
		var eff: CodaTrackEffect = send_inserts[i] as CodaTrackEffect
		var ae: AudioEffect = CodaEffectCatalogScript.build_audio_effect_from_slot(eff)
		if ae == null:
			continue
		AudioServer.add_bus_effect(bus_idx, ae)
		var slot: int = AudioServer.get_bus_effect_count(bus_idx) - 1
		AudioServer.set_bus_effect_enabled(bus_idx, slot, not eff.bypass)


static func _clear_send_insert_effects(bus_idx: int, base_effect_count: int) -> void:
	var n: int = AudioServer.get_bus_effect_count(bus_idx)
	for i in range(n - 1, base_effect_count - 1, -1):
		if i >= base_effect_count:
			AudioServer.remove_bus_effect(bus_idx, i)


static func collect_spawnable_wet_sends(
	sends: Array[CodaBusSend], bus_root: CodaBus, id_to_godot_name: Dictionary = {}
) -> Array[CodaBusSend]:
	var out: Array[CodaBusSend] = []
	if bus_root == null:
		return out
	for send in sends:
		if send == null:
			continue
		var target: CodaBus = bus_root.find_by_id(send.target_bus_id)
		if target == null or target.bus_kind != CodaBus.BusKind.RETURN:
			continue
		var return_nm: String = String(id_to_godot_name.get(target.id, target.bus_name)).strip_edges()
		if return_nm.is_empty() or AudioServer.get_bus_index(return_nm) < 0:
			continue
		for eff in target.effects:
			if eff is CodaTrackEffect:
				out.append(send)
				break
	return out


static func build_wet_voice_layers(
	sends: Array[CodaBusSend],
	bus_root: CodaBus,
	id_to_godot_name: Dictionary,
	param_values: Dictionary,
	base_volume_db: float
) -> Array:
	var layers: Array = []
	if bus_root == null:
		return layers
	for send in collect_spawnable_wet_sends(sends, bus_root, id_to_godot_name):
		var target: CodaBus = bus_root.find_by_id(send.target_bus_id)
		if target == null:
			continue
		var return_nm: String = String(id_to_godot_name.get(target.id, target.bus_name)).strip_edges()
		var amt: float = effective_level(send, param_values)
		var wet_chain: Array = []
		for eff in target.effects:
			if eff is CodaTrackEffect:
				var slot: CodaTrackEffect = (eff as CodaTrackEffect).clone_new_id()
				slot.params = slot.params.duplicate(true)
				match slot.type:
					CodaTrackEffect.Type.REVERB:
						slot.params["dry"] = 0.0
						slot.params["wet"] = 1.0
					CodaTrackEffect.Type.DELAY:
						slot.params["dry"] = 0.0
					CodaTrackEffect.Type.CHORUS:
						slot.params["dry"] = 0.0
						slot.params["wet"] = 1.0
				wet_chain.append(slot)
		if wet_chain.is_empty():
			continue
		var tap_nm: String = CodaFxBusHelperScript.create_effects_bus(return_nm, wet_chain)
		if tap_nm.is_empty():
			continue
		layers.append({
			"bus": tap_nm,
			"volume_db": base_volume_db + linear_to_db(amt),
			"fx_bus": tap_nm,
		})
	return layers


static func project_uses_send_param(project: CodaProject, param_id: String) -> bool:
	if project == null or param_id.is_empty():
		return false
	for b in project.bus_root.collect_flat([]):
		for ws in b.wet_sends:
			if String(ws.parameter_id).strip_edges() == param_id:
				return true
	return _events_use_send_param(project.events_root, param_id)


static func _events_use_send_param(node: CodaBrowserNode, param_id: String) -> bool:
	if node == null:
		return false
	if node.kind == CodaBrowserNode.Kind.EVENT:
		for ws in node.event_wet_sends:
			if String(ws.parameter_id).strip_edges() == param_id:
				return true
		if node.event_timeline != null:
			for tr in node.event_timeline.tracks:
				for ws in tr.wet_sends:
					if String(ws.parameter_id).strip_edges() == param_id:
						return true
	for c in node.children:
		if _events_use_send_param(c, param_id):
			return true
	return false


static func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * (log(linear) / log(10.0))
