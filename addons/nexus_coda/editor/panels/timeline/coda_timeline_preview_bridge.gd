@tool
class_name CodaTimelinePreviewBridge
extends RefCounted

## Runtime preview wiring for the timeline panel — playhead sync and transport from the editor.

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")

var _runtime: CodaRuntime = null
var _view: CodaTimelineView = null
var _selected_event: CodaBrowserNode = null
var _live_handle: CodaEventHandle = null


func attach_runtime(runtime: CodaRuntime) -> void:
	if _runtime != null and is_instance_valid(_runtime):
		if _runtime.voice_finished.is_connected(_on_runtime_voice_finished):
			_runtime.voice_finished.disconnect(_on_runtime_voice_finished)
	_runtime = runtime
	if _runtime != null:
		_runtime.voice_finished.connect(_on_runtime_voice_finished)


func set_view(view: CodaTimelineView) -> void:
	_view = view


func set_selected_event(event: CodaBrowserNode) -> void:
	_selected_event = event
	_live_handle = null


func get_live_handle() -> CodaEventHandle:
	return _live_handle


func clear_live_handle() -> void:
	_live_handle = null


func stop_all_previews() -> void:
	if _runtime != null:
		_runtime.stop_all()
	_live_handle = null


func stop_preview_for_event(event_id: String) -> void:
	if _runtime == null or event_id.is_empty():
		return
	var h: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(event_id)
	if h != null:
		_runtime.stop(h)
	if _live_handle == h:
		_live_handle = null


func process_tick() -> void:
	if _selected_event == null or _view == null:
		return
	if _selected_event.event_authoring_mode != CodaBrowserNode.AuthoringMode.TIMELINE:
		return
	if _runtime == null:
		return
	if (
		_live_handle == null
		or not is_instance_valid(_live_handle)
		or not _live_handle.is_playing()
	):
		_live_handle = _runtime.get_active_timeline_handle_for_event(_selected_event.id)
	if _live_handle != null and _live_handle.is_timeline:
		if not _live_handle.is_paused():
			_view.set_playhead(_live_handle.timeline_cursor_seconds)


func set_external_playhead_seconds(seconds: float) -> void:
	if _view != null:
		_view.set_playhead(seconds)


func seek_playhead(time_seconds: float) -> void:
	if _runtime == null or _selected_event == null:
		return
	var h: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(_selected_event.id)
	if h != null and h.is_timeline:
		h.seek(clampf(time_seconds, 0.0, h.timeline_length_seconds))


func resync_preview_for_event(event_id: String) -> void:
	if _runtime != null and not event_id.is_empty():
		_runtime.resync_timeline_preview_for_event(event_id)


func stop_before_timeline_restore(event_id: String) -> void:
	if _runtime == null:
		_live_handle = null
		return
	var active: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(event_id)
	if active != null:
		_runtime.stop(active)
	_live_handle = null


func get_runtime() -> CodaRuntime:
	return _runtime


func toggle_audition() -> void:
	if _selected_event == null or _runtime == null or _view == null:
		return
	if _selected_event.event_authoring_mode != CodaBrowserNode.AuthoringMode.TIMELINE:
		return
	var t: CodaEventTimeline = _selected_event.event_timeline
	if t == null:
		return
	var existing: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(_selected_event.id)
	if existing != null and existing.is_timeline:
		if existing.is_paused():
			existing.resume()
			NexusCodaLog.info("timeline_preview", 'Preview resumed: "%s"' % _selected_event.name)
			return
		existing.pause()
		NexusCodaLog.info("timeline_preview", 'Preview paused: "%s"' % _selected_event.name)
		return
	if _live_handle != null and is_instance_valid(_live_handle):
		_runtime.stop(_live_handle)
	_live_handle = null
	var ph: float = clampf(_view.get_playhead(), 0.0, t.length_seconds)
	var params: Dictionary = {
		"loop": t.loop_enabled,
		"timeline_cursor_start": ph,
		"_coda_exclusive_preview": true,
	}
	var h: CodaEventHandle = _runtime.play_event_node(_selected_event, params)
	if h == null:
		NexusCodaLog.warn(
			"timeline_preview", 'Could not start preview for "%s"' % _selected_event.name
		)
		return
	_live_handle = h
	NexusCodaLog.info("timeline_preview", 'Preview started: "%s"' % _selected_event.name)


func _on_runtime_voice_finished(handle: CodaEventHandle) -> void:
	if _live_handle == handle:
		_live_handle = null
		if _view != null and handle.is_timeline:
			_view.set_playhead(handle.timeline_cursor_seconds)
