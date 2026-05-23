@tool
class_name CodaTimelineMarkerUi
extends RefCounted

## Marker edit helpers for the timeline panel.


static func rename_marker(marker: CodaTimelineMarker, new_name: String) -> void:
	if marker == null:
		return
	var trimmed: String = new_name.strip_edges()
	marker.marker_name = trimmed if not trimmed.is_empty() else "Marker"


static func delete_marker(timeline: CodaEventTimeline, marker_id: String) -> bool:
	if timeline == null or marker_id.is_empty():
		return false
	return timeline.remove_marker(marker_id)


static func open_rename_dialog(
	parent: Node,
	marker: CodaTimelineMarker,
	on_commit: Callable,
	dialog_ref: Array = []
) -> void:
	if parent == null or marker == null or not on_commit.is_valid():
		return
	var dlg: AcceptDialog = null
	if not dialog_ref.is_empty() and dialog_ref[0] is AcceptDialog:
		dlg = dialog_ref[0] as AcceptDialog
	if dlg == null:
		dlg = AcceptDialog.new()
		dlg.title = "Rename Marker"
		var le := LineEdit.new()
		le.name = "RenameField"
		le.custom_minimum_size = Vector2(240, 0)
		dlg.add_child(le)
		dlg.confirmed.connect(
			func() -> void:
				var field: LineEdit = dlg.get_node("RenameField") as LineEdit
				if field != null and on_commit.is_valid():
					on_commit.call(field.text)
		)
		parent.add_child(dlg)
		if dialog_ref.is_empty():
			dialog_ref.append(dlg)
		else:
			dialog_ref[0] = dlg
	var field_existing: LineEdit = dlg.get_node("RenameField") as LineEdit
	if field_existing != null:
		field_existing.text = marker.marker_name
	dlg.popup_centered()
	if field_existing != null:
		field_existing.call_deferred(&"grab_focus")
