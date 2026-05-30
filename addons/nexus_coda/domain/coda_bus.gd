@tool
class_name CodaBus
extends RefCounted

## A virtual bus owned by the Coda project. The runtime mirrors these into Godot's
## AudioServer buses (one Godot bus per CodaBus, parented appropriately) so voices route correctly.

const CodaTrackEffectScript := preload("res://addons/nexus_coda/domain/effects/coda_track_effect.gd")
const CodaBusSendScript := preload("res://addons/nexus_coda/domain/coda_bus_send.gd")

enum BusKind { MIX = 0, RETURN = 1, VCA = 2 }

var id: String
var bus_name: String = "Bus"
## MIX = group/mix bus, RETURN = effect return (reverb hall), VCA = marker only (see project vcas).
var bus_kind: BusKind = BusKind.MIX
var volume_db: float = 0.0
var mute: bool = false
var solo: bool = false
var bypass: bool = false
## Bus link toward Master (Godot set_bus_send). Not a wet send; see [member wet_sends].
var send_target_id: String = ""
## Parallel wet sends to return buses (FMOD-style aux).
var wet_sends: Array[CodaBusSend] = []
var children: Array[CodaBus] = []
var effects: Array[CodaTrackEffect] = []


func _init(p_name: String = "Bus") -> void:
	id = _generate_id()
	bus_name = p_name


static func _generate_id() -> String:
	return "b_%d_%d" % [Time.get_ticks_usec(), randi()]


## Walks this bus and all descendants, returning a flat list (root first, depth-first).
func collect_flat(into: Array[CodaBus] = []) -> Array[CodaBus]:
	into.append(self)
	for c in children:
		c.collect_flat(into)
	return into


func find_by_id(target_id: String) -> CodaBus:
	if id == target_id:
		return self
	for c in children:
		var f: CodaBus = c.find_by_id(target_id)
		if f != null:
			return f
	return null


func find_by_name(target_name: String) -> CodaBus:
	if String(bus_name).strip_edges() == target_name.strip_edges():
		return self
	for c in children:
		var f: CodaBus = c.find_by_name(target_name)
		if f != null:
			return f
	return null


func remove_child_by_id(target_id: String) -> bool:
	for i in range(children.size()):
		if children[i].id == target_id:
			children.remove_at(i)
			return true
		if children[i].remove_child_by_id(target_id):
			return true
	return false


func find_wet_send_by_id(send_id: String) -> CodaBusSend:
	for s in wet_sends:
		if s.id == send_id:
			return s
	return null


func collect_return_buses(into: Array[CodaBus] = []) -> Array[CodaBus]:
	if bus_kind == BusKind.RETURN:
		into.append(self)
	for c in children:
		c.collect_return_buses(into)
	return into


func clone_keep_id() -> CodaBus:
	var b: CodaBus = CodaBus.new(bus_name)
	b.id = id
	b.volume_db = volume_db
	b.mute = mute
	b.solo = solo
	b.bypass = bypass
	b.bus_kind = bus_kind
	b.send_target_id = send_target_id
	for ws in wet_sends:
		b.wet_sends.append(ws.clone_keep_id())
	for e in effects:
		b.effects.append(e.clone_keep_id())
	for c in children:
		b.children.append(c.clone_keep_id())
	return b


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": bus_name,
		"volume_db": volume_db,
		"mute": mute,
		"solo": solo,
		"bypass": bypass,
		"bus_kind": bus_kind,
		"send_target_id": send_target_id,
		"wet_sends": CodaBusSendScript.sends_to_array(wet_sends),
		"effects": effects.map(func(e: CodaTrackEffect) -> Dictionary: return e.to_dictionary()),
		"children": children.map(func(c: CodaBus) -> Dictionary: return c.to_dictionary()),
	}


static func from_dictionary(data: Dictionary) -> CodaBus:
	var b: CodaBus = CodaBus.new(str(data.get("name", "Bus")))
	var stored_id: String = str(data.get("id", "")).strip_edges()
	if not stored_id.is_empty():
		b.id = stored_id
	b.volume_db = float(data.get("volume_db", 0.0))
	b.mute = bool(data.get("mute", false))
	b.solo = bool(data.get("solo", false))
	b.bypass = bool(data.get("bypass", false))
	b.bus_kind = clampi(int(data.get("bus_kind", BusKind.MIX)), 0, BusKind.VCA)
	b.send_target_id = str(data.get("send_target_id", ""))
	b.wet_sends = CodaBusSendScript.sends_from_array(data.get("wet_sends", []) as Array)
	for e_raw in data.get("effects", []) as Array:
		if e_raw is Dictionary:
			b.effects.append(CodaTrackEffectScript.from_dictionary(e_raw))
	for c_raw in data.get("children", []) as Array:
		if c_raw is Dictionary:
			b.children.append(CodaBus.from_dictionary(c_raw))
	return b


static func make_default_master() -> CodaBus:
	var master := CodaBus.new("Master")
	var sfx := CodaBus.new("SFX")
	var music := CodaBus.new("Music")
	var ui := CodaBus.new("UI")
	var voice := CodaBus.new("Voice")
	master.children.append(sfx)
	master.children.append(music)
	master.children.append(ui)
	master.children.append(voice)
	return master
