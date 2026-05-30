@tool
extends RefCounted
class_name CodaVcaRuntime

## Applies VCA faders on top of mirrored bus volumes (options-menu layer).
## Called from [CodaAudioBusMirror] after a gated sync; writes directly to AudioServer.


static func effective_volume_db(bus: CodaBus, vcas: Array[CodaVca]) -> float:
	if bus == null:
		return 0.0
	var db: float = bus.volume_db
	for vca in vcas:
		if vca == null or vca.mute:
			continue
		if bus.id in vca.controlled_bus_ids:
			db += vca.volume_db
	return db


static func apply_vca_volumes(
	bus_root: CodaBus,
	vcas: Array[CodaVca],
	id_to_godot_name: Dictionary
) -> void:
	if bus_root == null:
		return
	for b in bus_root.collect_flat([]):
		var gname: String = String(id_to_godot_name.get(b.id, "")).strip_edges()
		if gname.is_empty():
			continue
		var idx: int = AudioServer.get_bus_index(gname)
		if idx < 0:
			continue
		var eff_db: float = effective_volume_db(b, vcas)
		AudioServer.set_bus_volume_db(idx, eff_db)
