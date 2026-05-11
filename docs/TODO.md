# TODO

## Drag & drop: Godot FileSystem → Coda asset browser

**Status:** Still unreliable — needs follow-up work.

There are already code paths (`CodaBrowserTree` + `CodaState.import_assets_from_res_paths`) that expect editor payloads with `type` `files` / `files_and_dirs` and `files` (`res://…`). In practice, dragging from the FileSystem dock into the Nexus Coda **Assets** tree is still not stable (e.g. native editor `Window`, OS/engine limits, or further payload / tree drop-section cases).

**Workaround in place:** FileSystem dock context menu **“Send to Coda Assets”** (`EditorContextMenuPlugin`, `coda_filesystem_context_menu_plugin.gd` + `plugin.gd`) calls the same `import_assets_from_res_paths` pipeline when the selection is only `res://` folders and/or supported audio files.

**To finish later:**

- Verify and harden DnD from the FileSystem dock into the Coda Assets tree (Godot version, target `Window` vs embedded dock, `get_drop_section_at_position`, raw OS drops).
- Optional: **EditorFileDialog** entry using the same import API if you want a third path besides DnD and context menu.

**Relevant files (current repo):**

- `project/addons/nexus_coda/editor/coda_filesystem_context_menu_plugin.gd` — FileSystem context menu entry
- `project/addons/nexus_coda/plugin.gd` — registers/removes the context menu plugin; `send_fs_selection_to_coda_assets`
- `project/addons/nexus_coda/editor/nexus_coda_editor_window.gd` — `import_fs_paths_into_assets`
- `project/addons/nexus_coda/editor/browser/coda_browser_tree.gd` — `_can_drop_data` / `_drop_data`, `_filesystem_drag_files`
- `project/addons/nexus_coda/editor/browser/coda_state.gd` — `import_assets_from_res_paths`, `resolve_assets_drop_parent_id`

After editing the working tree: run `scripts/sync_addon_from_project.ps1` so `addons/nexus_coda/` stays in sync.
