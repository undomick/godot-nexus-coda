@tool
class_name CodaTimelinePreviewBridge
extends RefCounted

## Runtime preview wiring for the timeline panel — playhead sync and transport from the editor.

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaPlayOptionsScript := preload("res://addons/nexus_coda/domain/coda_play_options.gd")
const CodaTimelineTransportScript := preload(
	"res://addons/nexus_coda/domain/coda_timeline_transport.gd"
)

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
		var t: float = time_seconds
		if _selected_event.event_timeline != null and _selected_event.event_timeline.has_work_area():
			t = _selected_event.event_timeline.clamp_time_to_work_area(t)
		h.seek(clampf(t, 0.0, h.timeline_length_seconds))


func resync_preview_for_event(event_id: String) -> void:
	commit_transport_for_event(event_id, _view)


func commit_transport_for_event(event_id: String, view: CodaTimelineView = null) -> void:
	if _runtime == null or event_id.is_empty():
		return
	_sync_authoring_timeline_to_runtime(event_id)
	var handle: CodaEventHandle = _runtime.get_active_timeline_handle_for_event(event_id)
	var live_tl: CodaEventTimeline = _live_timeline_for_event(event_id)
	var stop_at_out := false
	var playhead_time := -1.0
	if handle != null and live_tl != null:
		var plan: Dictionary = CodaTimelineTransportScript.reconcile_playhead_after_work_area_edit(
			live_tl, handle
		)
		playhead_time = float(plan.get("time", handle.timeline_cursor_seconds))
		stop_at_out = bool(plan.get("stop_at_out", false))
		if absf(playhead_time - handle.timeline_cursor_seconds) > 0.0001:
			handle.seek(playhead_time)
	_runtime.resync_timeline_preview_for_event(event_id)
	if playhead_time >= 0.0 and view != null:
		view.set_playhead(playhead_time)
	if stop_at_out and handle != null:
		_runtime.stop(handle)
		if _live_handle == handle:
			_live_handle = null


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
	if t.has_work_area():
		ph = t.clamp_time_to_work_area(ph)
	var opts := CodaPlayOptionsScript.new()
	opts.loop = t.loop_enabled
	opts.timeline_cursor_start = ph
	opts.exclusive_preview = true
	CodaTimelineTransportScript.apply_to_play_options(t, opts)
	_sync_authoring_timeline_to_runtime(_selected_event.id)
	var playback_event: CodaBrowserNode = _resolve_playback_event(_selected_event)
	var h: CodaEventHandle = _runtime.play_event_node(playback_event, opts.to_params_dict())
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


func _resolve_playback_event(source: CodaBrowserNode) -> CodaBrowserNode:
	if _runtime == null or source == null:
		return source
	var project: CodaState = _runtime.get_project()
	if project == null:
		return source
	var playback: CodaBrowserNode = project.find_node_anywhere(source.id)
	return playback if playback != null else source


func _live_timeline_for_event(event_id: String) -> CodaEventTimeline:
	if _selected_event == null or _selected_event.id != event_id:
		return null
	return _selected_event.event_timeline


func _sync_authoring_timeline_to_runtime(event_id: String) -> void:
	var live_tl: CodaEventTimeline = _live_timeline_for_event(event_id)
	if _runtime == null or live_tl == null or _selected_event == null:
		return
	var playback: CodaBrowserNode = _resolve_playback_event(_selected_event)
	if playback == null or playback.event_timeline == null:
		return
	playback.event_timeline.overwrite_from_authoring(live_tl)


func _sync_work_area_to_runtime(event_id: String) -> void:
	_sync_authoring_timeline_to_runtime(event_id)
