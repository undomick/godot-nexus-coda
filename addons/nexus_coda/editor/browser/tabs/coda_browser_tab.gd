@tool
class_name CodaBrowserTab
extends VBoxContainer

## Pluggable tab inside the Browser panel.
##
## Each tab owns its own UI surface (filter, quick actions, content tree/list),
## listens to project changes, and routes selection back to the panel via
## `selection_emitted`. The panel forwards that signal to the editor window so
## cross-panel routing (e.g. focus the Mixer when a bus is selected) stays out
## of the individual tab classes.

## Selection envelopes use a category so the panel and the editor window can route
## without knowing each tab's internal data type.
const CATEGORY_EVENT := &"event"
const CATEGORY_ASSET := &"asset"
const CATEGORY_BUS := &"bus"
const CATEGORY_BANK := &"bank"
const CATEGORY_SNAPSHOT := &"snapshot"
const CATEGORY_GAME_SYNC := &"game_sync"

## payload is typically a string id, sometimes a richer Dictionary (for game-sync
## entries that need to disambiguate parameter vs modulation).
signal selection_emitted(category: StringName, payload: Variant)


func get_tab_title() -> String:
	return "Tab"


## Attach the live CodaState (Variant on purpose so the receiver can verify type without
## forcing every tab to import the heavy class).
func attach_state(_state: Variant) -> void:
	pass


func apply_filter(_text: String) -> void:
	pass


## Re-emits the current selection (used by the panel after layout changes so panels
## that listen to selection see a consistent snapshot).
func pulse_selection_to_editor() -> void:
	pass


## Programmatic selection. Returns true if the id was found.
func select_by_id(_target_id: String) -> bool:
	return false
