@tool
class_name CodaEditorShortcutRouter
extends RefCounted

const CodaEditorShortcutsScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_shortcuts.gd"
)

## Routes window keyboard input to editor actions via a handler dictionary.


static func match_and_route(
	key: InputEventKey, handlers: Dictionary, viewport: Viewport = null
) -> bool:
	var action: int = CodaEditorShortcutsScript.match_action(key)
	if action == CodaEditorShortcutsScript.Action.NONE:
		return false
	if viewport != null and _text_input_has_focus(viewport):
		if action == CodaEditorShortcutsScript.Action.BROWSER_DELETE:
			return false
		if action == CodaEditorShortcutsScript.Action.BROWSER_RENAME:
			return false
	match action:
		CodaEditorShortcutsScript.Action.COMMAND_PALETTE:
			return _call_handler(handlers, &"open_command_palette")
		CodaEditorShortcutsScript.Action.SHORTCUT_SHEET:
			return _call_handler(handlers, &"open_shortcut_sheet")
		CodaEditorShortcutsScript.Action.NEW_PROJECT:
			return _call_handler(handlers, &"new_project")
		CodaEditorShortcutsScript.Action.OPEN_PROJECT:
			return _call_handler(handlers, &"open_project")
		CodaEditorShortcutsScript.Action.SAVE_PROJECT:
			return _call_handler(handlers, &"save_project")
		CodaEditorShortcutsScript.Action.SAVE_PROJECT_AS:
			return _call_handler(handlers, &"save_project_as")
		CodaEditorShortcutsScript.Action.BROWSER_RENAME:
			return _call_optional_bool(handlers, &"browser_rename")
		CodaEditorShortcutsScript.Action.BROWSER_DELETE:
			if _call_optional_bool(handlers, &"timeline_delete"):
				return true
			return _call_optional_bool(handlers, &"browser_delete")
		CodaEditorShortcutsScript.Action.FOCUS_BROWSER:
			return _call_handler(handlers, &"focus_browser")
		CodaEditorShortcutsScript.Action.FOCUS_GRAPH:
			return _call_handler(handlers, &"focus_graph")
		CodaEditorShortcutsScript.Action.FOCUS_TIMELINE:
			return _call_handler(handlers, &"focus_timeline")
		CodaEditorShortcutsScript.Action.FOCUS_MIXER:
			return _call_handler(handlers, &"focus_mixer")
		CodaEditorShortcutsScript.Action.FOCUS_PLAYER:
			return _call_handler(handlers, &"focus_player")
		CodaEditorShortcutsScript.Action.FOCUS_INSPECTOR:
			return _call_handler(handlers, &"focus_inspector")
	return false


static func _call_handler(handlers: Dictionary, key: StringName) -> bool:
	var cb: Variant = handlers.get(key, null)
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call()
		return true
	return false


static func _call_optional_bool(handlers: Dictionary, key: StringName) -> bool:
	var cb: Variant = handlers.get(key, null)
	if cb is Callable and (cb as Callable).is_valid():
		return bool((cb as Callable).call())
	return false


static func _text_input_has_focus(viewport: Viewport) -> bool:
	var focus: Control = viewport.gui_get_focus_owner()
	if focus == null:
		return false
	if focus is LineEdit or focus is TextEdit:
		return true
	if focus is SpinBox:
		return true
	return false
