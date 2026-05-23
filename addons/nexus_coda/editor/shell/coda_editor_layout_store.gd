@tool
class_name CodaEditorLayoutStore
extends RefCounted

## Serializes dock panel placement, split offsets, and last-zone hints.

const LAYOUT_VERSION := 2


static func build_payload(dock_host: CodaDockHost, dock_manager: CodaDockManager) -> Dictionary:
	var payload := {
		"version": LAYOUT_VERSION,
		"layout": dock_manager.get_layout_state(),
		"last_zones": dock_manager.get_last_zones(),
	}
	if dock_host != null:
		payload["splits"] = dock_host.get_split_state()
	return payload


static func apply_payload(
	dock_host: CodaDockHost,
	dock_manager: CodaDockManager,
	root: Dictionary
) -> void:
	if root.is_empty():
		return
	var version: int = int(root.get("version", 1))
	var layout: Variant = root.get("layout", null)
	if layout is Dictionary:
		if version >= 2 and root.has("last_zones"):
			dock_manager.set_last_zones(root.get("last_zones", {}) as Dictionary)
		dock_manager.apply_layout_state(layout as Dictionary)
	if version >= 2 and dock_host != null:
		var splits: Variant = root.get("splits", null)
		if splits is Dictionary:
			dock_host.apply_split_state(splits as Dictionary)
