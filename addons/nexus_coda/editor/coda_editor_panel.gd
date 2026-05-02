@tool
class_name CodaEditorPanel
extends VBoxContainer

## Shell: tab strip + instanced event authoring UI (`CodaEventAuthoringView`).

# Type not annotated: class loads after this file; would cause "Could not find type" parse error.
@onready var _authoring: Node = $Content/EventAuthoringView


func _ready() -> void:
	var tab_bar: TabBar = $TabBar
	tab_bar.add_tab("Main")


func attach_browser_panel(browser_panel: Control) -> void:
	if _authoring != null:
		_authoring.set_browser_panel(browser_panel)


func on_browser_event_selected(node: Variant) -> void:
	if _authoring != null:
		_authoring.on_browser_event_selected(node)
