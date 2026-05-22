extends RefCounted
class_name CodaFxBusHelper

## Builds a short-lived AudioServer bus that hosts a Coda effect chain and sends into a
## destination mix bus. Coda's per-voice inserts (clip + track effects) need this because
## Godot only supports bus-level effect chains, not per-voice ones.

const CodaEffectCatalogScript := preload(
	"res://addons/nexus_coda/editor/browser/effects/coda_effect_catalog.gd"
)

const BUS_NAME_PREFIX := "__CodaFx_"


## Creates a temporary bus, appends [param effects] (already a CodaTrackEffect chain), and
## routes its send to [param send_to_bus_name]. Returns the new bus name, or empty if the
## chain is empty.
static func create_effects_bus(send_to_bus_name: String, effects: Array) -> String:
	if effects.is_empty():
		return ""
	var send_nm: String = String(send_to_bus_name).strip_edges()
	if send_nm.is_empty() or AudioServer.get_bus_index(send_nm) < 0:
		send_nm = "Master"
	var bus_name: String = _make_unique_bus_name()
	AudioServer.add_bus()
	var idx: int = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, send_nm)
	AudioServer.set_bus_volume_db(idx, 0.0)
	AudioServer.set_bus_mute(idx, false)
	AudioServer.set_bus_bypass_effects(idx, false)
	_apply_effects_to_bus(idx, effects)
	return bus_name


## Rebuilds the effect slots on an existing helper bus (same name/send). Used while a timeline
## preview is playing so effect parameter and bypass edits apply without restarting voices.
static func refresh_effects_bus(bus_name: String, effects: Array) -> void:
	var nm: String = String(bus_name).strip_edges()
	if nm.is_empty() or not nm.begins_with(BUS_NAME_PREFIX):
		return
	var idx: int = AudioServer.get_bus_index(nm)
	if idx <= 0:
		return
	var n: int = AudioServer.get_bus_effect_count(idx)
	for i in range(n - 1, -1, -1):
		AudioServer.remove_bus_effect(idx, i)
	_apply_effects_to_bus(idx, effects)


static func _apply_effects_to_bus(bus_idx: int, effects: Array) -> void:
	if bus_idx <= 0:
		return
	for eff in effects:
		if eff is CodaTrackEffect:
			var e: CodaTrackEffect = eff as CodaTrackEffect
			var ae: AudioEffect = CodaEffectCatalogScript.build_audio_effect_from_slot(e)
			if ae == null:
				continue
			AudioServer.add_bus_effect(bus_idx, ae)
			var slot: int = AudioServer.get_bus_effect_count(bus_idx) - 1
			AudioServer.set_bus_effect_enabled(bus_idx, slot, not e.bypass)


static func destroy_if_ours(bus_name: String) -> void:
	var nm: String = String(bus_name).strip_edges()
	if nm.is_empty() or not nm.begins_with(BUS_NAME_PREFIX):
		return
	var idx: int = AudioServer.get_bus_index(nm)
	if idx <= 0:
		return
	AudioServer.remove_bus(idx)


static func is_helper_bus(bus_name: String) -> bool:
	return String(bus_name).strip_edges().begins_with(BUS_NAME_PREFIX)


static func _make_unique_bus_name() -> String:
	for _i in 64:
		var nm: String = "%s%d_%d" % [BUS_NAME_PREFIX, Time.get_ticks_usec(), randi() % 100000000]
		if AudioServer.get_bus_index(nm) < 0:
			return nm
	return "%s%d" % [BUS_NAME_PREFIX, Time.get_ticks_usec()]
