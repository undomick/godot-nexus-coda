# AGENTS.md

## Cursor Cloud specific instructions

### Product overview

**Nexus Coda** is a Godot 4.7 editor plugin and runtime for adaptive game audio. There is no web server or database. Development and testing are Godot-centric.

### Required tooling (one-time VM setup)

| Tool | Version | Notes |
|------|---------|-------|
| Godot | 4.7+ | Project targets `config/features=PackedStringArray("4.7")`. Install to `~/.local/bin/godot` (e.g. Godot 4.7-rc1 from [godot-builds releases](https://github.com/godotengine/godot-builds/releases)). |
| Python 3 | 3.x | For `scripts/deploy_addon.py` |
| SCons | 4.x | `pip install --user scons` — GDExtension build |
| build-essential | — | `g++` for SCons/CMake |
| CMake | 3.16+ | Optional C++ smoke tests |

Ensure `export PATH="$HOME/.local/bin:$PATH"` is in your shell (Godot + pip user binaries).

### Test harness symlink (required per clone)

`test_run/addons/` is gitignored. Create once after checkout:

```bash
ln -sf ../addons test_run/addons
```

Then import assets once:

```bash
godot --headless --path test_run --import
```

### Services

| Service | Required? | How to run |
|---------|-----------|------------|
| Godot + `test_run/` harness | **Yes** | Headless test commands below |
| GDExtension binary | Optional (stub; not used by GDScript yet) | `scons platform=linux target=template_debug generate_bindings=yes` then `python3 scripts/deploy_addon.py --build-dir build/extension/bin` |
| Local `project/` Godot project | Optional | Gitignored; for full interactive editor work |

No Docker, no long-running daemons. Audio uses Godot's built-in AudioServer.

### Lint / test / build commands

**Primary verification (headless, no display):**

```bash
# Editor shell tests (pass on main)
godot --headless --path test_run -s res://addons/nexus_coda/tests/test_editor_shell.gd

# Game/music characterization tests (18 suites; 2 known failures on main as of setup)
godot --headless --path test_run -s res://addons/nexus_coda/tests/run_game_music_tests.gd
```

**Native extension (matches CI `.github/workflows/gdextension.yml`):**

```bash
git submodule update --init --recursive
scons platform=linux target=template_debug generate_bindings=yes -j$(nproc)
python3 scripts/deploy_addon.py --build-dir build/extension/bin
```

**C++ smoke test (optional):**

```bash
cmake -B build -DCMAKE_CXX_COMPILER=g++
cmake --build build
ctest --test-dir build --output-on-failure
```

Note: `clang++` requires `libstdc++-13-dev` for linking; `g++` works without extra packages.

### Gotchas

- Missing `test_run/addons` symlink causes all Godot tests to fail loading the addon.
- GDExtension `.so` missing only warns at import; GDScript runtime works without it.
- `project/` is gitignored — interactive editor E2E needs a local Godot project there.
- Game/music test runner may report 2 failures (`test_bus_sends`, `test_wet_layer_lifecycle`) on current `main`; editor shell tests are the cleaner green signal for environment health.
