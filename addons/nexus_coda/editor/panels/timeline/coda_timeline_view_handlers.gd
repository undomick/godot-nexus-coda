@tool
class_name CodaTimelineViewHandlers
extends RefCounted

## View signal handlers extracted from [CodaTimelinePanel] (clip/marker/work-point edits).

const CodaTimelineCommands := preload(
	"res://addons/nexus_coda/editor/panels/timeline/coda_timeline_commands.gd"
)

var _panel: CodaTimelinePanel


func _init(panel: CodaTimelinePanel) -> void:
	_panel = panel


func connect_view(view: CodaTimelineView) -> void:
	view.clip_move_requested.connect(_on_clip_move_requested)
	view.clip_fade_requested.connect(_on_clip_fade_requested)
	view.clip_resize_requested.connect(_on_clip_resize_requested)
	view.clip_delete_requested.connect(_on_clip_delete_requested)
	view.browser_asset_dropped.connect(_on_browser_asset_dropped)
	view.marker_changed.connect(_on_marker_changed)
	view.loop_region_changed.connect(_on_loop_region_changed)
	view.playhead_seek_requested.connect(_on_playhead_seek_requested)
	view.marker_double_clicked.connect(_on_marker_double_clicked)
	view.marker_selected.connect(_on_marker_selected)
	view.marker_delete_requested.connect(_on_marker_delete_requested)
	view.marker_rename_requested.connect(_on_marker_rename_requested)
	view.marker_go_to_time_requested.connect(_on_marker_go_to_time_requested)
	view.work_point_changed.connect(_on_work_point_changed)
	view.work_point_toggle_requested.connect(_on_work_point_toggle_requested)
	view.work_point_delete_requested.connect(_on_work_point_delete_requested)
	view.track_row_selected.connect(_on_track_row_selected)
	view.clip_audio_assign_requested.connect(_on_clip_audio_assign_requested)
	view.timeline_interaction_started.connect(_on_timeline_interaction_started)
	view.timeline_interaction_committed.connect(_on_timeline_interaction_committed)
	view.clip_duplicate_requested.connect(_on_clip_duplicate_requested)
	view.clip_split_at_playhead_requested.connect(_on_clip_split_at_playhead_requested)
	view.audition_requested.connect(_on_audition_requested)
	view.clip_selected.connect(_on_clip_selected_for_effects_panel)
	view.selection_cleared.connect(_on_clip_selection_cleared_for_effects_panel)


func _on_track_row_selected(track_index: int) -> void:
	_panel.call(&"_set_selected_track_index", track_index, true)


func _on_clip_audio_assign_requested(clip_id: String, res_path: String) -> void:
	if clip_id.is_empty() or res_path.is_empty():
		return
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null:
		return
	var t: CodaEventTimeline = ev.event_timeline
	if t == null:
		return
	_panel.call(&"_apply_mutation", CodaTimelineCommands.assign_clip_audio(t, clip_id, res_path))


func _on_clip_move_requested(clip_id: String, new_start: float, new_track_index: int) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null or ev.event_timeline == null:
		return
	var t: CodaEventTimeline = ev.event_timeline
	var prev_count: int = t.tracks.size()
	var snap: CodaEventTimeline = CodaTimelineCommands.move_clip_to_track(
		t, clip_id, new_start, new_track_index
	)
	if snap != null:
		_panel.call(&"_push_snapshot", snap)
	if t.tracks.size() > prev_count:
		_panel.call(&"set_selected_track_index_value", t.tracks.size() - 1)
		_panel.call(&"clear_track_headers_signature")
		_panel.call(&"_rebuild_track_headers")
		var view: CodaTimelineView = _panel.call(&"get_timeline_view") as CodaTimelineView
		if view != null:
			view.set_track_row_highlight(int(_panel.call(&"get_selected_track_index")))
		_panel.call(&"_emit_track_selection_changed")
	_panel.call(&"_notify_timeline_changed")


func _on_clip_fade_requested(
	clip_id: String,
	fade_in: float,
	fade_out: float,
	fade_in_curve: float,
	fade_out_curve: float
) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null or ev.event_timeline == null:
		return
	CodaTimelineCommands.apply_clip_fades(
		ev.event_timeline, clip_id, fade_in, fade_out, fade_in_curve, fade_out_curve
	)
	_panel.call(&"_notify_timeline_changed")


func _on_clip_resize_requested(
	clip_id: String,
	new_start: float,
	new_duration: float,
	new_offset_seconds: float
) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null or ev.event_timeline == null:
		return
	var t: CodaEventTimeline = ev.event_timeline
	CodaTimelineCommands.resize_clip(t, clip_id, new_start, new_duration, new_offset_seconds)
	_panel.call(&"_notify_timeline_changed")


func _on_browser_asset_dropped(track_index: int, start_seconds: float, res_path: String) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null or ev.event_timeline == null:
		return
	_panel.call(
		&"_apply_mutation",
		CodaTimelineCommands.drop_browser_asset(
			ev.event_timeline, track_index, start_seconds, res_path
		)
	)


func _on_clip_delete_requested(clip_id: String) -> void:
	if clip_id.is_empty():
		return
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null or ev.event_timeline == null:
		return
	var snap: CodaEventTimeline = CodaTimelineCommands.delete_clip(ev.event_timeline, clip_id)
	if snap == null:
		return
	_panel.call(&"_push_snapshot", snap)
	var view: CodaTimelineView = _panel.call(&"get_timeline_view") as CodaTimelineView
	if view != null:
		view.clear_selection()
	_panel.call(&"_notify_timeline_changed")


func _on_marker_changed(_marker_id: String, _new_time: float) -> void:
	_panel.call(&"_notify_timeline_changed")


func _on_work_point_changed(_kind: String, _new_time: float) -> void:
	_panel.call(&"_notify_timeline_changed")


func _on_work_point_toggle_requested(kind: String) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	var view: CodaTimelineView = _panel.call(&"get_timeline_view") as CodaTimelineView
	if ev == null or ev.event_timeline == null or view == null:
		return
	var t: CodaEventTimeline = ev.event_timeline
	var ph: float = view.get_playhead()
	var snap: CodaEventTimeline = null
	if kind == "in":
		snap = CodaTimelineCommands.toggle_in_point(t, ph)
	else:
		snap = CodaTimelineCommands.toggle_out_point(t, ph)
	_panel.call(&"_apply_mutation", snap)


func _on_work_point_delete_requested(kind: String) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	var view: CodaTimelineView = _panel.call(&"get_timeline_view") as CodaTimelineView
	if ev == null or ev.event_timeline == null or view == null:
		return
	var t: CodaEventTimeline = ev.event_timeline
	var snap: CodaEventTimeline = null
	if kind == "in":
		snap = CodaTimelineCommands.delete_in_point(t)
	else:
		snap = CodaTimelineCommands.delete_out_point(t)
	if snap == null:
		return
	_panel.call(&"_apply_mutation", snap)
	if view.get_selected_work_point() == kind:
		view.clear_work_point_selection()


func _on_loop_region_changed(_start: float, _end: float) -> void:
	_panel.call(&"_notify_timeline_changed")


func _on_playhead_seek_requested(time_seconds: float) -> void:
	var preview: CodaTimelinePreviewBridge = _panel.call(&"get_timeline_preview") as CodaTimelinePreviewBridge
	if preview != null:
		preview.seek_playhead(time_seconds)


func _on_marker_double_clicked(marker_id: String) -> void:
	_panel.call(&"_open_marker_rename", marker_id)


func _on_marker_selected(_marker_id: String) -> void:
	pass


func _on_marker_rename_requested(marker_id: String) -> void:
	_panel.call(&"_open_marker_rename", marker_id)


func _on_marker_delete_requested(marker_id: String) -> void:
	_panel.call(&"_delete_marker", marker_id)


func _on_marker_go_to_time_requested(marker_id: String) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	var view: CodaTimelineView = _panel.call(&"get_timeline_view") as CodaTimelineView
	if ev == null or ev.event_timeline == null or view == null:
		return
	var m: CodaTimelineMarker = ev.event_timeline.find_marker(marker_id)
	if m == null:
		return
	view.set_playhead(m.time_seconds)
	var preview: CodaTimelinePreviewBridge = _panel.call(&"get_timeline_preview") as CodaTimelinePreviewBridge
	if preview != null:
		preview.seek_playhead(m.time_seconds)


func _on_timeline_interaction_started() -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null or ev.event_timeline == null:
		return
	_panel.call(&"begin_timeline_edit_interaction")
	_panel.call(
		&"_push_snapshot", CodaTimelineCommands.snapshot(ev.event_timeline)
	)


func _on_timeline_interaction_committed(kind: int, clip_id: String) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev != null and ev.event_timeline != null and not clip_id.is_empty():
		if kind in [
			CodaTimelineInputController.DragKind.CLIP_MOVE,
			CodaTimelineInputController.DragKind.CLIP_RESIZE_LEFT,
			CodaTimelineInputController.DragKind.CLIP_RESIZE_RIGHT,
		]:
			CodaTimelineCommands.resolve_clip_overlaps(ev.event_timeline, clip_id)
			_panel.call(&"_notify_timeline_changed")
	_panel.call(&"commit_timeline_edit_interaction")


func _on_clip_duplicate_requested(clip_id: String) -> void:
	if clip_id.is_empty():
		return
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null or ev.event_timeline == null:
		return
	var result: Dictionary = CodaTimelineCommands.duplicate_clip(ev.event_timeline, clip_id)
	_panel.call(&"_apply_split_or_duplicate_result", result)


func _on_clip_split_at_playhead_requested(clip_id: String) -> void:
	if clip_id.is_empty():
		return
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	var view: CodaTimelineView = _panel.call(&"get_timeline_view") as CodaTimelineView
	if ev == null or ev.event_timeline == null or view == null:
		return
	_panel.call(&"_run_split_command", clip_id, view.get_playhead())


func _on_audition_requested() -> void:
	var preview: CodaTimelinePreviewBridge = _panel.call(&"get_timeline_preview") as CodaTimelinePreviewBridge
	if preview != null:
		preview.toggle_audition()


func _on_clip_selected_for_effects_panel(clip_id: String) -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null:
		return
	if not clip_id.is_empty() and ev.event_timeline != null:
		var info: Dictionary = ev.event_timeline.find_clip(clip_id)
		if not info.is_empty():
			var tr: CodaTimelineTrack = info.get("track") as CodaTimelineTrack
			if tr != null:
				var tracks: Array[CodaTimelineTrack] = ev.event_timeline.tracks
				for i in tracks.size():
					if tracks[i].id == tr.id:
						_panel.call(&"_sync_track_index_for_clip", i)
						break
	_panel.clip_selection_changed.emit(ev.id, clip_id)


func _on_clip_selection_cleared_for_effects_panel() -> void:
	var ev: CodaBrowserNode = _panel.call(&"get_authoring_event") as CodaBrowserNode
	if ev == null:
		return
	_panel.clip_selection_changed.emit(ev.id, "")
