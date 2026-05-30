extends RefCounted
class_name CodaFxBusHelper

## Builds a short-lived AudioServer bus that hosts a Coda effect chain and sends into a
## destination mix bus. Coda's per-voice inserts (clip + track effects) need this because
## Godot only supports bus-level effect chains, not per-voice ones.

const CodaEffectCatalogScript := preload(
	"res://addons/nexus_coda/domain/effects/coda_effect_catalog.gd"
)

const BUS_NAME_PREFIX := "__CodaFx_"

static var _tail_release_token: Dictionary = {}


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
	for eff in effects:
		if eff is CodaTrackEffect:
			var e: CodaTrackEffect = eff as CodaTrackEffect
			var ae: AudioEffect = CodaEffectCatalogScript.build_audio_effect_from_slot(e)
			if ae == null:
				continue
			AudioServer.add_bus_effect(idx, ae)
			var slot: int = AudioServer.get_bus_effect_count(idx) - 1
			AudioServer.set_bus_effect_enabled(idx, slot, not e.bypass)
	return bus_name


static func destroy_if_ours(bus_name: String) -> void:
	var nm: String = String(bus_name).strip_edges()
	cancel_pending_destroy(nm)
	if nm.is_empty() or not nm.begins_with(BUS_NAME_PREFIX):
		return
	var idx: int = AudioServer.get_bus_index(nm)
	if idx <= 0:
		return
	AudioServer.remove_bus(idx)


static func cancel_pending_destroy(bus_name: String) -> void:
	var nm: String = String(bus_name).strip_edges()
	if nm.is_empty():
		return
	_tail_release_token[nm] = int(_tail_release_token.get(nm, 0)) + 1


## Keeps the FX bus alive so wet tails can decay after the dry source stops.
## Rescheduling extends the deadline (older timer callbacks are ignored via token).
static func mute_dry_on_bus(bus_name: String) -> void:
	var idx: int = AudioServer.get_bus_index(String(bus_name).strip_edges())
	if idx < 0:
		return
	var count: int = AudioServer.get_bus_effect_count(idx)
	for slot in range(count):
		var ae: AudioEffect = AudioServer.get_bus_effect(idx, slot)
		if ae is AudioEffectReverb:
			(ae as AudioEffectReverb).dry = 0.0
		elif ae is AudioEffectDelay:
			(ae as AudioEffectDelay).dry = 0.0
		elif ae is AudioEffectChorus:
			(ae as AudioEffectChorus).dry = 0.0


static func schedule_destroy_after_tail(
	bus_name: String, tail_seconds: float, owner_node: Node
) -> void:
	var nm: String = String(bus_name).strip_edges()
	if nm.is_empty() or not is_helper_bus(nm):
		return
	if AudioServer.get_bus_index(nm) < 0:
		return
	var token: int = int(_tail_release_token.get(nm, 0)) + 1
	_tail_release_token[nm] = token
	var delay: float = maxf(tail_seconds, 0.05)
	var tree: SceneTree = _scene_tree(owner_node)
	if tree == null:
		push_warning("CodaFxBusHelper: no SceneTree for tail release on '%s'" % nm)
		destroy_if_ours(nm)
		return
	tree.create_timer(delay).timeout.connect(
		_on_tail_timer_fired.bind(nm, token), CONNECT_ONE_SHOT
	)


static func _scene_tree(owner_node: Node) -> SceneTree:
	if owner_node != null and is_instance_valid(owner_node):
		var tree: SceneTree = owner_node.get_tree()
		if tree != null:
			return tree
	return Engine.get_main_loop() as SceneTree


static func _on_tail_timer_fired(nm: String, token: int) -> void:
	if int(_tail_release_token.get(nm, 0)) != token:
		return
	_tail_release_token.erase(nm)
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
