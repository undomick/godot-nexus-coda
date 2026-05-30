class_name CodaTimelineTransport
extends RefCounted

## Resolves work-area vs loop-region bounds for preview and runtime dispatch.


static func effective_loop_bounds(timeline: CodaEventTimeline) -> Dictionary:
	if timeline == null:
		return {"start": 0.0, "end": 0.0, "loop_enabled": false, "uses_work_area": false}
	if timeline.has_work_area():
		return {
			"start": timeline.work_area_start(),
			"end": timeline.work_area_end(),
			"loop_enabled": timeline.loop_enabled,
			"uses_work_area": true,
		}
	return {
		"start": timeline.loop_start_seconds,
		"end": timeline.loop_end_seconds,
		"loop_enabled": timeline.loop_enabled,
		"uses_work_area": false,
	}


static func apply_to_play_options(timeline: CodaEventTimeline, opts: CodaPlayOptions) -> void:
	if timeline == null or opts == null:
		return
	opts.loop = timeline.loop_enabled
	var bounds: Dictionary = effective_loop_bounds(timeline)
	if timeline.has_work_area():
		opts.loop_region_start = float(bounds.get("start", 0.0))
		opts.loop_region_end = float(bounds.get("end", 0.0))
	else:
		opts.loop_region_start = -1.0
		opts.loop_region_end = -1.0


static func reconcile_playhead_after_work_area_edit(
	timeline: CodaEventTimeline, handle: CodaEventHandle
) -> Dictionary:
	if timeline == null or handle == null or not timeline.has_work_area():
		return {"time": handle.timeline_cursor_seconds if handle != null else 0.0, "stop_at_out": false}
	var cur: float = handle.timeline_cursor_seconds
	var lo: float = timeline.work_area_start()
	var hi: float = timeline.work_area_end()
	if cur >= lo and cur <= hi:
		return {"time": cur, "stop_at_out": false}
	if cur < lo:
		return {"time": lo, "stop_at_out": false}
	if timeline.loop_enabled:
		return {"time": lo, "stop_at_out": false}
	return {"time": hi, "stop_at_out": true}


static func copy_preview_transport(
	from_timeline: CodaEventTimeline, to_timeline: CodaEventTimeline
) -> void:
	if from_timeline == null or to_timeline == null:
		return
	to_timeline.in_point_seconds = from_timeline.in_point_seconds
	to_timeline.out_point_seconds = from_timeline.out_point_seconds
	to_timeline.loop_enabled = from_timeline.loop_enabled


## Back-compat alias for callers that only synced work-area points.
static func copy_work_area(from_timeline: CodaEventTimeline, to_timeline: CodaEventTimeline) -> void:
	copy_preview_transport(from_timeline, to_timeline)


static func _loop_region_from_handle(handle: CodaEventHandle) -> Array:
	if handle == null:
		return []
	var region: Variant = handle.params.get("_coda_loop_region", null)
	if region is Array and (region as Array).size() == 2:
		return region as Array
	return []


static func sync_dispatcher_bounds(
	handle: CodaEventHandle, d: Dictionary, timeline: CodaEventTimeline
) -> void:
	if timeline == null or d.is_empty():
		return
	var start: float = -1.0
	var end: float = -1.0
	if timeline.has_work_area():
		start = timeline.work_area_start()
		end = timeline.work_area_end()
	elif timeline.loop_enabled and timeline.loop_end_seconds > timeline.loop_start_seconds:
		start = timeline.loop_start_seconds
		end = timeline.loop_end_seconds
	else:
		var region: Array = _loop_region_from_handle(handle)
		if region.size() == 2:
			start = float(region[0])
			end = float(region[1])
	d["loop_override_start"] = start
	d["loop_override_end"] = end
	if handle == null:
		return
	# Work-area bounds define play range; loop_enabled controls wrap vs stop at out.
	handle.loop = timeline.loop_enabled
	if start >= 0.0 and end > start:
		handle.params["_coda_loop_region"] = [start, end]
	elif handle.params.has("_coda_loop_region"):
		handle.params.erase("_coda_loop_region")
