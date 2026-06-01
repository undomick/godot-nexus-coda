@tool
extends Node
class_name CodaSetup

## One-Setup entry point for gameplay:
## - Loads exported banks on scene start.
## - Optionally wires Game Sync rules to a subtree.

const Common := preload("res://addons/nexus_coda/runtime/nodes/coda_setup_common.gd")

@export var bank_paths: Array[String] = []
@export var auto_connect_game_sync: bool = true
@export var game_sync_root: NodePath


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var runtime: CodaRuntime = Common.get_coda_runtime()
	Common.load_banks(runtime, bank_paths, "CodaSetup")
	Common.connect_game_sync(auto_connect_game_sync, self, game_sync_root)

