@tool
class_name CodaRuntimeTimelineDispatch
extends RefCounted

## Timeline preview handle lookup extracted from [CodaRuntime].


static func active_handle_for_event(
	dispatchers: Dictionary, event_id: String
) -> CodaEventHandle:
	if event_id.is_empty():
		return null
	for h in dispatchers.keys():
		var handle: CodaEventHandle = h as CodaEventHandle
		if handle == null or not handle._alive:
			continue
		var event: CodaBrowserNode = handle.event_node as CodaBrowserNode
		if event == null:
			continue
		if event.id == event_id:
			return handle
	return null
