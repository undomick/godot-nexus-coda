@tool
class_name CodaEditorShortcuts
extends RefCounted

## Single source of truth for Nexus Coda editor window keyboard shortcuts.

enum Action {
	NONE,
	NEW_PROJECT,
	OPEN_PROJECT,
	SAVE_PROJECT,
	SAVE_PROJECT_AS,
	COMMAND_PALETTE,
	SHORTCUT_SHEET,
	BROWSER_RENAME,
	BROWSER_DELETE,
	FOCUS_BROWSER,
	FOCUS_GRAPH,
	FOCUS_TIMELINE,
	FOCUS_MIXER,
	FOCUS_PLAYER,
	FOCUS_INSPECTOR,
}


static func sheet_entries() -> Array:
	return [
		{"category": "Window", "rows": [
			[_combo_label(KEY_P, true, false, false), "Open command palette"],
			["F1", "Open this shortcut sheet"],
			[_combo_label(KEY_N, true, false, false), "New project"],
			[_combo_label(KEY_O, true, false, false), "Open project"],
			[_combo_label(KEY_S, true, false, false), "Save project"],
			[_combo_label(KEY_S, true, true, false), "Save project as…"],
		]},
		{"category": "Navigation", "rows": [
			[_combo_label(KEY_1, true, false, false), "Focus Browser panel"],
			[_combo_label(KEY_2, true, false, false), "Focus Graph panel"],
			[_combo_label(KEY_3, true, false, false), "Focus Timeline panel"],
			[_combo_label(KEY_4, true, false, false), "Focus Mixer panel"],
			[_combo_label(KEY_5, true, false, false), "Focus Player panel"],
			[_combo_label(KEY_6, true, false, false), "Focus Inspector panel"],
		]},
		{"category": "Browser", "rows": [
			["Enter / Double-click", "Open event in Graph or Timeline (authoring mode)"],
			["F2", "Rename selected node"],
			["Delete", "Remove selected node"],
			["Drag asset onto graph", "Add SOUND node"],
		]},
		{"category": "Graph", "rows": [
			["Ctrl+Drag", "Box-select multiple nodes"],
			["Delete", "Remove selected nodes/edges"],
			["Right-click canvas", "Add node menu"],
		]},
		{"category": "Timeline", "rows": [
			["Space", "Play / pause (when Timeline has focus)"],
			["Delete", "Remove selected clip, marker, or track"],
			["Mouse wheel", "Zoom timeline"],
			["Middle mouse drag", "Pan timeline"],
			["Ctrl+Z / Ctrl+Y", "Undo / redo (Timeline focus)"],
		]},
		{"category": "Inspector", "rows": [
			["Tab", "Cycle between fields"],
			["Esc", "Cancel rename / drop edit"],
		]},
	]


static func panel_help_hint(panel_id: StringName) -> String:
	match panel_id:
		&"browser":
			return "Browser: F2 rename, Delete remove, Enter opens event in Graph/Timeline."
		&"graph":
			return "Graph: Right-click to add nodes. Delete removes selection."
		&"timeline":
			return "Timeline: Space play/pause, Delete removes selection, wheel zoom, MMB pan, Ctrl+Z/Y undo."
		&"mixer":
			return "Mixer: Click a strip to select. Snapshot Recall applies bus levels."
		&"player":
			return "Player: Transport controls preview playback for the selected event."
		&"inspector":
			return "Inspector: Edit authoring mode, parameters, modulation, and output bus."
		_:
			return ""


static func match_action(event: InputEventKey) -> Action:
	if not event.pressed or event.echo:
		return Action.NONE
	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	var shift: bool = event.shift_pressed
	var alt: bool = event.alt_pressed
	match event.keycode:
		KEY_P:
			if ctrl and not shift and not alt:
				return Action.COMMAND_PALETTE
		KEY_F1:
			if not ctrl and not shift and not alt:
				return Action.SHORTCUT_SHEET
		KEY_N:
			if ctrl and not shift and not alt:
				return Action.NEW_PROJECT
		KEY_O:
			if ctrl and not shift and not alt:
				return Action.OPEN_PROJECT
		KEY_S:
			if ctrl and shift and not alt:
				return Action.SAVE_PROJECT_AS
			if ctrl and not shift and not alt:
				return Action.SAVE_PROJECT
		KEY_F2:
			if not ctrl and not shift and not alt:
				return Action.BROWSER_RENAME
		KEY_DELETE, KEY_BACKSPACE:
			if not ctrl and not shift and not alt:
				return Action.BROWSER_DELETE
		KEY_1:
			if ctrl and not shift and not alt:
				return Action.FOCUS_BROWSER
		KEY_2:
			if ctrl and not shift and not alt:
				return Action.FOCUS_GRAPH
		KEY_3:
			if ctrl and not shift and not alt:
				return Action.FOCUS_TIMELINE
		KEY_4:
			if ctrl and not shift and not alt:
				return Action.FOCUS_MIXER
		KEY_5:
			if ctrl and not shift and not alt:
				return Action.FOCUS_PLAYER
		KEY_6:
			if ctrl and not shift and not alt:
				return Action.FOCUS_INSPECTOR
	return Action.NONE


static func _combo_label(keycode: Key, ctrl: bool, shift: bool, alt: bool) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if ctrl:
		parts.append("Ctrl")
	if shift:
		parts.append("Shift")
	if alt:
		parts.append("Alt")
	parts.append(OS.get_keycode_string(keycode))
	return "+".join(parts)
