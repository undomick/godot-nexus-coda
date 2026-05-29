# Godot integration

Nexus Coda registers three autoloads when the editor plugin is enabled:

| Autoload | Role |
|----------|------|
| `Coda` | Event playback, parameters, snapshots, bank loading |
| `CodaMusic` | Music slots, crossfades, stingers |
| `CodaGameBridge` | Maps gameplay signals to Coda actions via Game Sync rules |

Gameplay code can call these autoloads directly, or use the scene nodes below for a more familiar Godot workflow.

## Quick start

1. Export a bank from the Nexus Coda editor (`.coda_bank`).
2. Add a `CodaProjectBootstrap` node to your main scene.
3. Set `bank_paths` to your exported bank file(s).
4. Play events with `Coda.play("events/category/name")` or a `CodaEventEmitter` node.

## Loading banks

```gdscript
var bank_id := Coda.load_bank("res://audio/banks/main.coda_bank")
if bank_id.is_empty():
    push_warning("Bank load failed")
```

Banks can also load automatically via `CodaProjectBootstrap` (`@export var bank_paths`).

Event paths use the same hierarchy as in the Coda browser, for example `music/exploration` or `sfx/ui/click`.

## Pattern 1: Event emitter node

Add `CodaEventEmitter` to a scene:

- `event_path` — Coda event path
- `play_on_ready` — start when the scene loads
- `stop_on_exit` — stop when the node leaves the tree

```gdscript
@onready var explosion: CodaEventEmitter = $ExplosionSfx

func _on_exploded() -> void:
    explosion.play({"intensity": 0.8})
```

## Pattern 2: Music zone

Add `CodaMusicZone` and connect an `Area2D` / `Area3D`:

```gdscript
func _on_body_entered(body: Node2D) -> void:
    $CodaMusicZone.on_body_entered(body, {"zone": "forest"})

func _on_body_exited(body: Node2D) -> void:
    $CodaMusicZone.on_body_exited(body)
```

Or call `enter()` / `exit()` from gameplay code without an Area.

## Pattern 3: Game Sync

Define rules in the Coda editor (Game Syncs tab). At runtime, either:

- Enable `auto_connect_game_sync` on `CodaProjectBootstrap` (wires signals under the current scene or `game_sync_root`), or
- Call `CodaGameBridge.connect_game_signals_from(your_subtree)` manually.

Emit from gameplay:

```gdscript
CodaGameBridge.emit_game_signal("combat_started", {"zone": "arena"})
```

For Area triggers:

```gdscript
CodaGameBridge.emit_from_area("zone_entered", body, {"zone": "cave"})
```

## Parameters and music control

```gdscript
var handle := Coda.play("music/exploration")
Coda.set_parameter(handle, "intensity", 0.5)

CodaMusic.set_music("music/combat", 2000, "default")
CodaMusic.stop_music("default", 1500)
```

## Editor preview vs. gameplay

The Coda editor uses the same `Coda` runtime for timeline preview. In gameplay, bus layout and banks come from loaded `.coda_bank` files (and optional editor project state when testing in the editor).
