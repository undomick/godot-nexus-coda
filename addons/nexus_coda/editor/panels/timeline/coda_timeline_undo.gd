@tool
class_name CodaTimelineUndo
extends RefCounted

## Thin undo/redo stack wrapper used by [CodaTimelinePanel].


static func push_undo(stack: Array, redo_stack: Array, snapshot: Dictionary, max_depth: int = 64) -> void:
	stack.append(snapshot)
	if stack.size() > max_depth:
		stack.pop_front()
	redo_stack.clear()


static func pop_undo(stack: Array, redo_stack: Array, current: Dictionary) -> Variant:
	if stack.is_empty():
		return null
	redo_stack.append(current)
	return stack.pop_back()


static func pop_redo(stack: Array, redo_stack: Array, current: Dictionary) -> Variant:
	if redo_stack.is_empty():
		return null
	stack.append(current)
	return redo_stack.pop_back()
