@tool
extends HSplitContainer

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")

## Keeps outer columns at 15% / 85% and inner split at 70% / 15% of total width (70:15 within the right 85% strip).

const INNER_EDITOR_SHARE := 70.0 / 85.0

@onready var _inner: HSplitContainer = $InnerSplit
@onready var _browser_panel: Control = $BrowserPanel
@onready var _editor_panel: Control = $InnerSplit/EditorPanel


func _ready() -> void:
	resized.connect(_update_proportional_splits)
	call_deferred("_update_proportional_splits")
	call_deferred("_wire_editor_panel")


func _wire_editor_panel() -> void:
	if _browser_panel == null or _editor_panel == null:
		NexusCodaLog.warn("editor_layout", "missing BrowserPanel or EditorPanel (scene structure?)")
		return
	var ed := _editor_panel as CodaEditorPanel
	if ed == null:
		NexusCodaLog.warn(
			"editor_layout",
			"InnerSplit/EditorPanel is not CodaEditorPanel (script=%s) — cannot wire selection"
			% _editor_panel.get_script()
		)
		return
	if ed.has_method(&"attach_browser_panel"):
		ed.attach_browser_panel(_browser_panel)
	var slot := Callable(ed, &"on_browser_event_selected")
	if _browser_panel.has_signal(&"event_selection_changed"):
		if _browser_panel.event_selection_changed.is_connected(slot):
			_browser_panel.event_selection_changed.disconnect(slot)
		_browser_panel.event_selection_changed.connect(slot)
		NexusCodaLog.info("editor_layout", "event_selection_changed → CodaEditorPanel.on_browser_event_selected")
	else:
		NexusCodaLog.warn("editor_layout", "browser has no event_selection_changed signal")
	if _browser_panel.has_method(&"pulse_events_selection_to_editor"):
		_browser_panel.pulse_events_selection_to_editor()


func _update_proportional_splits() -> void:
	var w := size.x
	if w < 32:
		return
	split_offset = int(round(w * 0.15))
	if _inner == null:
		return
	var iw := _inner.size.x
	if iw < 16:
		return
	_inner.split_offset = int(round(iw * INNER_EDITOR_SHARE))
