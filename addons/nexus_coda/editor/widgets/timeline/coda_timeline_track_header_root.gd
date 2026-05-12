@tool
extends HBoxContainer

## Track header row: accepts drops from [CodaTimelineTrackDragHandle] to reorder tracks.

var track_index: int = 0
var on_drop: Callable = Callable()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	return (data as Dictionary).has("coda_timeline_track_drag")


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var d: Dictionary = data as Dictionary
	var from_i: int = int(d.get("coda_timeline_track_drag", -1))
	if from_i < 0 or from_i == track_index:
		return
	if on_drop.is_valid():
		on_drop.call(from_i, track_index)
