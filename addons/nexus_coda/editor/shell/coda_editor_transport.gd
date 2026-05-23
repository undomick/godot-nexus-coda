@tool
class_name CodaEditorTransport
extends RefCounted

## Keeps Player and Timeline preview cursors aligned during editor audition.

var player_panel: CodaPlayerPanel = null
var timeline_panel: CodaTimelinePanel = null
var _sync_guard: bool = false


func sync_playhead_seconds(seconds: float) -> void:
	if _sync_guard:
		return
	_sync_guard = true
	if player_panel != null and player_panel.has_method(&"set_external_playhead_seconds"):
		player_panel.set_external_playhead_seconds(seconds)
	if timeline_panel != null and timeline_panel.has_method(&"set_external_playhead_seconds"):
		timeline_panel.set_external_playhead_seconds(seconds)
	_sync_guard = false
