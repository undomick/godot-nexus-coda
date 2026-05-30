@tool
extends RefCounted
class_name CodaEditorPlaybackSync

## Keeps the preview runtime's playback copy aligned with live authoring for routing fields.


static func merge_authoring_routing(live: CodaBrowserNode, playback: CodaBrowserNode) -> void:
	if live == null or playback == null:
		return
	playback.event_output_bus_id = live.event_output_bus_id


static func apply_output_bus_to_preview_runtime(
	runtime: CodaRuntime, live: CodaBrowserNode
) -> void:
	if runtime == null or live == null:
		return
	runtime.apply_event_output_bus_from_authoring(live)


static func resolve_playback_event(
	runtime: CodaRuntime, live: CodaBrowserNode
) -> CodaBrowserNode:
	if runtime == null or live == null:
		return live
	var project: CodaProject = runtime.get_project()
	if project == null:
		return live
	var playback: CodaBrowserNode = project.find_node_anywhere(live.id)
	if playback == null:
		return live
	merge_authoring_routing(live, playback)
	return playback
