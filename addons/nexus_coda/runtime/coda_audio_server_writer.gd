@tool
class_name CodaAudioServerWriter
extends RefCounted

## Single entry for gated AudioServer mutations. Reads are direct on AudioServer.
##
## WRITE INVENTORY (mutations must go through may_sync or allow_prune):
## - [CodaAudioBusMirror] sync_to_audio_server — volume/mute/bypass/send/effects/structure
## - [CodaRuntimeBusSync] — calls mirror when gate allows
## - [CodaSnapshotBlender] — blend tick volume via set_bus_volume_db
## - [CodaFxBusHelper] — __CodaFx_* temp buses (preview/gameplay runtime)
## - [CodaMixerPanel] — live strip recall when gate allows (EditorMixer)
##
## READ-ONLY (no gate): peak meters in player/mixer UI, bus index lookups in routing.

const CodaAudioBusSyncGateScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd"
)


static func set_bus_volume_db(
	caller: int, bus_name: String, volume_db: float, allow_prune: bool = false
) -> bool:
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(caller, allow_prune):
		return false
	var idx: int = AudioServer.get_bus_index(String(bus_name).strip_edges())
	if idx < 0:
		return false
	AudioServer.set_bus_volume_db(idx, volume_db)
	return true


static func set_bus_volume_db_by_index(
	caller: int, bus_idx: int, volume_db: float, allow_prune: bool = false
) -> bool:
	if bus_idx < 0:
		return false
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(caller, allow_prune):
		return false
	AudioServer.set_bus_volume_db(bus_idx, volume_db)
	return true
