@tool
class_name CodaDockZone
extends TabContainer

## A single dock zone hosting any number of panels as tabs.
## Direct subclass of TabContainer so Godot's native cross-container drag-rearrange just works.

signal zone_emptied(zone_id: StringName)
signal zone_populated(zone_id: StringName)

## Shared across all zones so users can drag tabs between zones.
const REARRANGE_GROUP := 9412

@export var zone_id: StringName = &"unnamed"

var _last_was_empty: bool = true


func _init() -> void:
	drag_to_rearrange_enabled = true
	tabs_rearrange_group = REARRANGE_GROUP
	use_hidden_tabs_for_min_size = false
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	child_entered_tree.connect(_on_children_changed.unbind(1))
	child_exiting_tree.connect(_on_children_changed.unbind(1))
	_update_visibility()


func add_panel_control(control: Control) -> void:
	if control == null:
		return
	if control.get_parent() == self:
		return
	if control.get_parent() != null:
		control.get_parent().remove_child(control)
	# Ensure the tab title matches the registered display title (not the control's node name).
	var title: String = str(control.get_meta(CodaDockPanelInfo.META_PANEL_TITLE, "")).strip_edges()
	if not title.is_empty():
		control.name = title
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(control)


func remove_panel_control(control: Control) -> bool:
	if control == null:
		return false
	if control.get_parent() != self:
		return false
	remove_child(control)
	return true


func has_panel_control(control: Control) -> bool:
	return control != null and control.get_parent() == self


func panel_count() -> int:
	return get_tab_count()


func panel_controls() -> Array[Control]:
	var out: Array[Control] = []
	for i in get_tab_count():
		var ctrl: Control = get_tab_control(i) as Control
		if ctrl != null:
			out.append(ctrl)
	return out


func focus_panel_control(control: Control) -> void:
	if control == null:
		return
	var idx: int = get_tab_idx_from_control(control)
	if idx >= 0:
		current_tab = idx


func _on_children_changed() -> void:
	call_deferred(&"_update_visibility")


func _update_visibility() -> void:
	var has_tabs: bool = get_tab_count() > 0
	visible = has_tabs
	if has_tabs and _last_was_empty:
		_last_was_empty = false
		zone_populated.emit(zone_id)
	elif not has_tabs and not _last_was_empty:
		_last_was_empty = true
		zone_emptied.emit(zone_id)
