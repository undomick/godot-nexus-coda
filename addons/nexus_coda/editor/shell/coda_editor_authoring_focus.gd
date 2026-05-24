@tool
class_name CodaEditorAuthoringFocus
extends RefCounted

## Switches center dock tab when event authoring mode changes.

const PANEL_GRAPH := &"graph"
const PANEL_TIMELINE := &"timeline"

var dock_manager: CodaDockManager = null
var graph_panel: CodaEventGraphPanel = null
var timeline_panel: CodaTimelinePanel = null


func focus_for_event(node: CodaBrowserNode) -> void:
	if dock_manager == null or node == null or node.kind != CodaBrowserNode.Kind.EVENT:
		return
	match node.event_authoring_mode:
		CodaBrowserNode.AuthoringMode.GRAPH:
			dock_manager.show_panel(PANEL_GRAPH)
			if graph_panel != null and graph_panel.has_method(&"grab_focus"):
				var focus_mode: Control.FocusMode = graph_panel.focus_mode
				if focus_mode != Control.FOCUS_NONE:
					graph_panel.grab_focus()
		CodaBrowserNode.AuthoringMode.TIMELINE:
			dock_manager.show_panel(PANEL_TIMELINE)
			if timeline_panel != null and timeline_panel.has_method(&"grab_authoring_focus"):
				timeline_panel.call(&"grab_authoring_focus")
		_:
			pass


func open_graph_for_event(node: CodaBrowserNode) -> void:
	if dock_manager == null or node == null:
		return
	dock_manager.show_panel(PANEL_GRAPH)
	if graph_panel != null and graph_panel.has_method(&"grab_focus"):
		var focus_mode: Control.FocusMode = graph_panel.focus_mode
		if focus_mode != Control.FOCUS_NONE:
			graph_panel.grab_focus()


func open_timeline_for_event(node: CodaBrowserNode) -> void:
	if dock_manager == null or node == null:
		return
	dock_manager.show_panel(PANEL_TIMELINE)
	if timeline_panel != null and timeline_panel.has_method(&"grab_authoring_focus"):
		timeline_panel.call(&"grab_authoring_focus")
