@tool
class_name CodaTimelineUndo
extends RefCounted

## Undo/redo stack wrapper for timeline editing in [CodaTimelinePanel].

const MAX_DEPTH := 40


static func make_snapshot(timeline: CodaEventTimeline) -> CodaEventTimeline:
	if timeline == null:
		return null
	return timeline.clone_keep_ids()


static func push_undo(
	undo_stack: Array,
	redo_stack: Array,
	snapshot: CodaEventTimeline,
	max_depth: int = MAX_DEPTH
) -> void:
	if snapshot == null:
		return
	undo_stack.append(snapshot)
	redo_stack.clear()
	while undo_stack.size() > max_depth:
		undo_stack.pop_front()


static func pop_undo(
	undo_stack: Array,
	redo_stack: Array,
	current: CodaEventTimeline
) -> CodaEventTimeline:
	if undo_stack.is_empty() or current == null:
		return null
	redo_stack.append(make_snapshot(current))
	return undo_stack.pop_back() as CodaEventTimeline


static func pop_redo(
	undo_stack: Array,
	redo_stack: Array,
	current: CodaEventTimeline
) -> CodaEventTimeline:
	if redo_stack.is_empty() or current == null:
		return null
	undo_stack.append(make_snapshot(current))
	return redo_stack.pop_back() as CodaEventTimeline
