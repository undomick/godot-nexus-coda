@tool
class_name CodaEditorSelectionRouter
extends RefCounted

## Routes browser external selections to dock panels and panel-specific focus hooks.

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaBrowserTabScript := preload(
	"res://addons/nexus_coda/editor/browser/tabs/coda_browser_tab.gd"
)
const CodaInspectorSelectionScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_inspector_selection.gd"
)

var dock_manager: CodaDockManager = null
var browser_panel: Control = null
var mixer_panel: CodaMixerPanel = null
var on_inspector_selection: Callable = Callable()


func route(target_panel_id: StringName, kind: StringName, payload: Variant) -> void:
	if dock_manager == null:
		return
	if kind == CodaBrowserTabScript.CATEGORY_GAME_SYNC and payload is Dictionary:
		var event_id: String = str((payload as Dictionary).get("event_id", ""))
		if not event_id.is_empty() and browser_panel != null \
				and browser_panel.has_method(&"select_event_by_id"):
			browser_panel.select_event_by_id(event_id)
		_apply_inspector(
			CodaInspectorSelectionScript.Subject.BROWSER_GAME_SYNC,
			{"payload": payload as Dictionary}
		)
	elif kind == CodaBrowserTabScript.CATEGORY_BANK:
		_apply_inspector(
			CodaInspectorSelectionScript.Subject.BROWSER_BANK,
			{"bank_id": str(payload)}
		)
	elif kind == CodaBrowserTabScript.CATEGORY_BUS:
		var bus_id: String = str(payload)
		if mixer_panel != null:
			mixer_panel.select_bus(bus_id)
		_apply_inspector(CodaInspectorSelectionScript.Subject.MIXER_BUS, {"bus_id": bus_id})
	elif kind == CodaBrowserTabScript.CATEGORY_SNAPSHOT:
		if mixer_panel != null:
			mixer_panel.highlight_snapshot(str(payload))
	dock_manager.show_panel(target_panel_id)
	NexusCodaLog.debug(
		"browser_routing",
		"Routed %s selection to %s panel" % [String(kind), String(target_panel_id)],
	)


func _apply_inspector(subject: CodaInspectorSelection.Subject, payload: Dictionary) -> void:
	if on_inspector_selection.is_valid():
		on_inspector_selection.call(subject, payload)
