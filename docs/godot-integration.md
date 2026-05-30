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

Set-Parameters are written by gameplay and drive audio (switches, blends, modulation). Get-Properties are defined by the designer and read by gameplay (subtitles, radius, UI flags).

```gdscript
var handle := Coda.play("music/exploration")
Coda.set_parameter(handle, "intensity", 0.5)

var radius: float = Coda.get_property(handle, "DamageRadius")
var subtitle: String = str(Coda.get_property(handle, "SubtitleID"))

# Without a running voice:
var animate: bool = Coda.get_property_for_path("ui/click", "AnimateButton")

CodaMusic.set_music("music/combat", 2000, "default")
CodaMusic.stop_music("default", 1500)
```

## Editor preview vs. gameplay

The Coda editor uses the same `Coda` runtime for timeline preview. In gameplay, bus layout and banks come from loaded `.coda_bank` files (and optional editor project state when testing in the editor).

## Optional: Nexus Resonance (spatial occlusion)

Nexus Resonance can drive room simulation (occlusion, transmission, distance) for Coda event voices without routing PCM through `ResonancePlayer`. This is the **Option A** bridge: one Resonance source handle per Coda voice, attenuation applied as extra `volume_db` on Coda's pooled `AudioStreamPlayer`s.

### Setup

1. Install both addons in the same Godot project (`nexus_coda` + `nexus_resonance` from `C:\__projects__\nexus-resonance\audio_resonance_tool\addons\nexus_resonance`).
2. Keep autoload `Coda` → `CodaRuntime` (plugin default).
3. Add a `ResonanceRuntime` node to the scene and enable **Coda Bridge** (`coda_bridge_enabled = true`).
4. Bake or assign static geometry / probes as usual for Resonance.
5. For 3D SFX, add `ResonanceCodaEventEmitter` (`Node3D`) instead of a plain `CodaEventEmitter`, or pass an emitter path when calling `play`:

```gdscript
# From code (ResonanceCodaEventEmitter does this automatically):
Coda.play("sfx/gunshot", {"_coda_spatial_emitter": $GunshotEmitter.get_path()})
```

### Scene node

`ResonanceCodaEventEmitter` (Nexus Resonance addon):

- `event_path` — Coda event path (same as `CodaEventEmitter`)
- `auto_play` — play on `_ready`
- `source_radius` — Resonance source radius (default `1.0`)

Requires `ResonanceRuntime.coda_bridge_enabled` and a loaded Coda bank.

### Demo scene (Coda test project)

See `project/scenes/coda_resonance_bridge_demo.tscn` after linking the Resonance addon. Enable the Nexus Resonance editor plugin, assign baked geometry, load a bank via `CodaProjectBootstrap`, and press Play.

### Limitations (Phase 1)

- Timeline multi-lane voices and BLEND parallel voices share one Resonance handle per event handle (see TODOs in `resonance_coda_bridge.gd`).
- Global Resonance reverb and Coda bus wet sends are independent; bus-matrix wiring is planned later.
- Rebuild the Nexus Resonance GDExtension after updating source-handle GDScript bindings (`create_source_handle`, `update_source`, `get_source_occlusion_data`).
