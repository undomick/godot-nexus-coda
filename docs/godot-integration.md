# Godot integration

Nexus Coda registers three autoloads when the editor plugin is enabled:

| Autoload | Role |
|----------|------|
| `Coda` | Event playback, parameters, snapshots, bank loading |
| `CodaMusic` | Music slots, crossfades, stingers |
| `CodaGameBridge` | Maps gameplay signals to Coda actions via Game Sync rules |

Gameplay code can call these autoloads directly. For a more familiar Godot workflow, use the scene nodes below.

## Recommended: One-Setup workflow

The recommended setup is a single node that loads banks and (optionally) wires Game Sync.

1. Export a bank from the Nexus Coda editor (`.coda_bank`).
2. Add a `CodaSetup` node to your main scene.
3. Set `bank_paths` to your exported bank file(s).
4. (Optional) Enable `auto_connect_game_sync` and set `game_sync_root` if you want auto-wiring.
5. Play events via `CodaEventEmitter` nodes (recommended) or by calling `Coda.play(...)`.

### Common pitfalls

- If you see warnings about missing `Coda` autoload, ensure the editor plugin is enabled and `CodaRuntime` is registered as autoload `Coda`.
- If banks do not load, verify the paths are `res://...` and point at exported `.coda_bank` files.

## Playing sounds (scene node)

Add `CodaEventEmitter` to a scene:

- `event_path` - Coda event path
- `play_on_ready` - start when the scene loads
- `stop_on_exit` - stop when the node leaves the tree

```gdscript
@onready var explosion: CodaEventEmitter = $ExplosionSfx

func _on_exploded() -> void:
	explosion.play({"intensity": 0.8})
```

Event paths use the same hierarchy as in the Coda browser, for example `music/exploration` or `sfx/ui/click`.

## Music (zone node)

Add `CodaMusicZone` and connect an `Area2D` / `Area3D`:

```gdscript
func _on_body_entered(body: Node2D) -> void:
	$CodaMusicZone.on_body_entered(body, {"zone": "forest"})

func _on_body_exited(body: Node2D) -> void:
	$CodaMusicZone.on_body_exited(body)
```

Or call `enter()` / `exit()` from gameplay code without an Area.

## Game Sync

Define rules in the Coda editor (Game Syncs tab). At runtime:

- Recommended: enable `auto_connect_game_sync` on `CodaSetup` (wires signals under the current scene or `game_sync_root`).
- Advanced: call `CodaGameBridge.connect_game_signals_from(your_subtree)` manually.

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

## Loading banks (advanced API)

`CodaSetup` can load banks automatically (`@export var bank_paths`). If you need manual control:

```gdscript
var bank_id := Coda.load_bank("res://audio/banks/main.coda_bank")
if bank_id.is_empty():
	push_warning("Bank load failed")
```

## Alternative: minimal bootstrap (legacy)

`CodaProjectBootstrap` is a minimal predecessor of `CodaSetup`. It is still supported, but the documentation and defaults focus on `CodaSetup`.

## Editor preview vs. gameplay

The Coda editor uses the same `Coda` runtime for timeline preview. In gameplay, bus layout and banks come from loaded `.coda_bank` files (and optional editor project state when testing in the editor).

## Optional: importing assets into the Coda editor

Dragging audio from Godot's FileSystem dock into the Coda Assets tree is still unreliable in some setups. Use the FileSystem context menu entry **\"Send to Coda Assets\"** as a stable workaround. See `docs/TODO.md` for the current status and relevant files.

## Optional: Nexus Resonance (spatial occlusion)

Nexus Resonance can drive room simulation (occlusion, transmission, distance) for Coda event voices without routing PCM through `ResonancePlayer`. This is the Option A bridge: one Resonance source handle per Coda voice, attenuation applied as extra `volume_db` on Coda's pooled `AudioStreamPlayer`s.

### Setup

1. Install both addons in the same Godot project (`nexus_coda` + `nexus_resonance`).
2. Keep autoload `Coda` -> `CodaRuntime` (plugin default).
3. Add a `ResonanceRuntime` node to the scene and enable **Coda Bridge** (`coda_bridge_enabled = true`).
4. Bake or assign static geometry / probes as usual for Resonance.
5. For 3D SFX, add `ResonanceCodaEventEmitter` (`Node3D`) instead of a plain `CodaEventEmitter`.

`ResonanceCodaEventEmitter` requires `ResonanceRuntime.coda_bridge_enabled` and a loaded Coda bank.

### Advanced: calling `Coda.play` with an emitter

`ResonanceCodaEventEmitter` does this automatically, but you can also pass an emitter path when calling `play`:

```gdscript
Coda.play("sfx/gunshot", {"_coda_spatial_emitter": $GunshotEmitter.get_path()})
```

### Demo scene (Coda test project)

See `project/scenes/coda_resonance_bridge_demo.tscn` after linking the Resonance addon. Enable the Nexus Resonance editor plugin, assign baked geometry, load a bank via `CodaSetup`, and press Play.

### Known limitations (Phase 1)

- Timeline multi-lane voices and BLEND parallel voices share one Resonance handle per event handle (see TODOs in `resonance_coda_bridge.gd`).
- Global Resonance reverb and Coda bus wet sends are independent; bus-matrix wiring is planned later.
- `CodaSpatialVoiceRuntime` currently bypasses distance attenuation when a player has `_coda_resonance_handle` meta set (external backend expected).

## Known TODOs

These items are tracked in the repository as TODOs and are expected improvements (not user error):

- **Coda editor asset import**: Drag & drop from Godot's FileSystem dock into the Coda Assets tree is still unreliable in some setups. Workaround: FileSystem context menu **\"Send to Coda Assets\"**. See `docs/TODO.md`.
- **Coda spatial runtime**: `CodaSpatialVoiceRuntime` has a TODO to delegate distance attenuation to external spatial backends when `_coda_resonance_handle` is present.
- **Resonance bridge roadmap** (see TODOs in `resonance_coda_bridge.gd` and `resonance_coda_voice_sync.gd`):
  - One Resonance handle per timeline lane voice (instead of per event handle).
  - Separate handles for BLEND parallel siblings.
  - Optional smoothing for occlusion/transmission updates.
  - Future mapping of occlusion/transmission into Get-Properties and/or wet-send/reverb routing.
