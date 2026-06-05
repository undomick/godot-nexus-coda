class_name CodaPlayOptions
extends RefCounted

## Typed playback options passed from editor preview / gameplay into CodaRuntime.play.

var loop: bool = false
var timeline_cursor_start: float = 0.0
var exclusive_preview: bool = false
var voice_bus: String = ""
var loop_region_start: float = -1.0
var loop_region_end: float = -1.0
## Optional Node3D path for Nexus Resonance (or other spatial backends) to track this voice.
var spatial_emitter: NodePath = NodePath()


func has_loop_region() -> bool:
	return loop_region_start >= 0.0 and loop_region_end > loop_region_start


func to_params_dict() -> Dictionary:
	var out: Dictionary = {
		"loop": loop,
		"timeline_cursor_start": timeline_cursor_start,
	}
	if exclusive_preview:
		out["_coda_exclusive_preview"] = true
	if not voice_bus.is_empty():
		out["_coda_voice_bus"] = voice_bus
	if has_loop_region():
		out["_coda_loop_region"] = [loop_region_start, loop_region_end]
	if spatial_emitter != NodePath():
		out["_coda_spatial_emitter"] = spatial_emitter
	return out


static func from_params_dict(params: Dictionary) -> CodaPlayOptions:
	var opts := CodaPlayOptions.new()
	opts.loop = bool(params.get("loop", false))
	opts.timeline_cursor_start = float(params.get("timeline_cursor_start", 0.0))
	opts.exclusive_preview = bool(params.get("_coda_exclusive_preview", false))
	opts.voice_bus = String(params.get("_coda_voice_bus", ""))
	var region: Variant = params.get("_coda_loop_region", null)
	if region is Array and (region as Array).size() == 2:
		opts.loop_region_start = float((region as Array)[0])
		opts.loop_region_end = float((region as Array)[1])
	var emitter: Variant = params.get("_coda_spatial_emitter", null)
	if emitter is NodePath:
		opts.spatial_emitter = emitter as NodePath
	elif emitter is Node and is_instance_valid(emitter):
		opts.spatial_emitter = (emitter as Node).get_path()
	return opts


## Keep RTPC / gameplay parameters when stripping typed play options for runtime dispatch.
static func route_event_params(params: Dictionary) -> Dictionary:
	var opts: CodaPlayOptions = from_params_dict(params)
	var routed: Dictionary = opts.to_params_dict()
	for key in params.keys():
		var k: String = String(key)
		if routed.has(k) or k.begins_with("_coda_"):
			continue
		routed[k] = params[key]
	return routed
