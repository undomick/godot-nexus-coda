@tool
class_name CodaEditorSelectionRouter
extends RefCounted

## Routes browser external selections to dock panels and panel-specific focus hooks.

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaBrowserTabScript := preload(
	"res://addons/nexus_coda/editor/browser/tabs/coda_browser_tab.gd"
)

var dock_manager: CodaDockManager = null
var browser_panel: Control = null
var mixer_panel: CodaMixerPanel = null
var inspector_panel: CodaInspectorPanel = null


func route(target_panel_id: StringName, kind: StringName, payload: Variant) -> void:
	if dock_manager == null:
		return
	if kind == CodaBrowserTabScript.CATEGORY_GAME_SYNC and payload is Dictionary:
		var event_id: String = str((payload as Dictionary).get("event_id", ""))
		if not event_id.is_empty() and browser_panel != null \
				and browser_panel.has_method(&"select_event_by_id"):
			browser_panel.select_event_by_id(event_id)
		if inspector_panel != null and inspector_panel.has_method(&"show_game_sync_rule"):
			inspector_panel.show_game_sync_rule(payload as Dictionary)
	elif kind == CodaBrowserTabScript.CATEGORY_BANK:
		if inspector_panel != null and inspector_panel.has_method(&"show_bank"):
			inspector_panel.show_bank(str(payload))
	elif kind == CodaBrowserTabScript.CATEGORY_BUS:
		if mixer_panel != null:
			mixer_panel.select_bus(str(payload))
	elif kind == CodaBrowserTabScript.CATEGORY_SNAPSHOT:
		if mixer_panel != null:
			mixer_panel.highlight_snapshot(str(payload))
	dock_manager.show_panel(target_panel_id)
	NexusCodaLog.debug(
		"browser_routing",
		"Routed %s selection to %s panel" % [String(kind), String(target_panel_id)],
	)
