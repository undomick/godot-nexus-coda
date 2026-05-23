extends Node

## Minimal gameplay demo wiring for CodaMusic + CodaGameBridge.
## Attach to a scene root and call [method boot_with_sample_project] from _ready().

const CodaSampleProjectScript := preload(
	"res://addons/nexus_coda/editor/samples/coda_sample_project.gd"
)


func boot_with_sample_project() -> void:
	var sample = CodaSampleProjectScript.build()
	Coda.set_project(sample)
	CodaGameBridge.bind_from_project(sample)
	CodaMusic.set_music("music/exploration", 0)


func on_zone_entered(zone_name: String) -> void:
	CodaGameBridge.emit_game_signal("zone_entered", {"zone": zone_name})


func on_combat_started() -> void:
	CodaGameBridge.emit_game_signal("combat_started", {})


func on_intensity_changed(level: int) -> void:
	CodaGameBridge.emit_game_signal("music_intensity_changed", {"music_state": level})
