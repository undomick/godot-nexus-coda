@tool
class_name CodaDockZone
extends TabContainer

## A single dock zone hosting any number of panels as tabs.
## Direct subclass of TabContainer so Godot's native cross-container drag-rearrange just works.
## TabContainer only forwards rearrange drops to its TabBar; a top-level shield over the content
## rectangle accepts dock-tab drops for the panel area without stealing tab-strip insert feedback.

signal zone_emptied(zone_id: StringName)
signal zone_populated(zone_id: StringName)

## Shared across all zones so users can drag tabs between zones.
const REARRANGE_GROUP := 9412

const META_PLACEHOLDER := &"coda_dock_placeholder"

const DND_TAB_TYPE := "tab"
const DND_TAB_CONTAINER_KIND := "tab_container_tab"

const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")

@export var zone_id: StringName = &"unnamed"

var _last_was_empty: bool = true
## After at least one real dock panel lived here, show a drop placeholder when the zone is empty.
var _had_real_panels: bool = false

var _content_drop_shield: Control = null


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
	call_deferred(&"_install_content_drop_shield")


func _exit_tree() -> void:
	if _content_drop_shield != null and is_instance_valid(_content_drop_shield):
		_content_drop_shield.queue_free()
		_content_drop_shield = null


func add_panel_control(control: Control) -> void:
	if control == null:
		return
	if control.get_parent() == self:
		return
	_remove_placeholder_if_any()
	tabs_visible = true
	custom_minimum_size = Vector2.ZERO
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
	return panel_controls().size()


func panel_controls() -> Array[Control]:
	var out: Array[Control] = []
	for i in get_tab_count():
		var ctrl: Control = get_tab_control(i) as Control
		if ctrl != null and not _is_placeholder_control(ctrl):
			out.append(ctrl)
	return out


func focus_panel_control(control: Control) -> void:
	if control == null or _is_placeholder_control(control):
		return
	var idx: int = get_tab_idx_from_control(control)
	if idx >= 0:
		current_tab = idx


func _on_children_changed() -> void:
	call_deferred(&"_update_visibility")


func _update_visibility() -> void:
	visible = true
	var n: int = _count_dock_panels()

	if n > 0:
		_had_real_panels = true
		_remove_placeholder_if_any()
		tabs_visible = true
		custom_minimum_size = Vector2.ZERO
	else:
		if not _had_real_panels:
			_remove_placeholder_if_any()
			tabs_visible = true
			custom_minimum_size = Vector2(64.0, 64.0)
		else:
			_ensure_placeholder()
			custom_minimum_size = Vector2.ZERO

	var has_real: bool = n > 0
	if has_real and _last_was_empty:
		_last_was_empty = false
		zone_populated.emit(zone_id)
	elif not has_real and not _last_was_empty:
		_last_was_empty = true
		zone_emptied.emit(zone_id)


func _count_dock_panels() -> int:
	var c: int = 0
	for i in get_tab_count():
		var ctrl: Control = get_tab_control(i) as Control
		if ctrl == null or _is_placeholder_control(ctrl):
			continue
		var pid: String = String(ctrl.get_meta(CodaDockPanelInfo.META_PANEL_ID, ""))
		if not pid.is_empty():
			c += 1
	return c


func _is_placeholder_control(ctrl: Control) -> bool:
	return ctrl.get_meta(META_PLACEHOLDER, false) == true


func _find_placeholder() -> Control:
	for i in get_tab_count():
		var ctrl: Control = get_tab_control(i) as Control
		if ctrl != null and _is_placeholder_control(ctrl):
			return ctrl
	return null


func _remove_placeholder_if_any() -> void:
	var ph: Control = _find_placeholder()
	if ph != null:
		remove_child(ph)
		ph.queue_free()


func _ensure_placeholder() -> void:
	if _find_placeholder() != null:
		tabs_visible = false
		return
	var ph: CodaEmptyState = CodaEmptyStateScript.new()
	ph.name = "DockEmptyPlaceholder"
	ph.title_text = "Drop a panel here"
	ph.body_text = "Drag a tab from another dock zone."
	ph.set_meta(META_PLACEHOLDER, true)
	add_child(ph)
	tabs_visible = false
	call_deferred(&"_apply_placeholder_mouse_pass", ph)


func _install_content_drop_shield() -> void:
	if _content_drop_shield != null:
		return
	var sh := _DockContentDropShield.new(self)
	sh.name = "DockContentDropShield_%s" % String(zone_id)
	add_child(sh)
	_content_drop_shield = sh


func _install_content_drop_shield_deferred_retry() -> void:
	if _content_drop_shield != null and is_instance_valid(_content_drop_shield):
		return
	call_deferred(&"_install_content_drop_shield")


## TabBar hit area stays on native reorder; only the remaining rect accepts our "append/move" semantics.
func _tab_strip_global_rect() -> Rect2:
	var full := get_global_rect()
	var th: float = _tab_strip_height_px()
	if th <= 0.0:
		return Rect2()
	var y_top: float = full.position.y
	var y_bot: float = full.position.y + full.size.y
	if tabs_position == TabContainer.POSITION_BOTTOM:
		return Rect2(full.position.x, y_bot - th, full.size.x, th)
	return Rect2(full.position.x, y_top, full.size.x, th)


func _content_area_global_rect() -> Rect2:
	var full := get_global_rect()
	var th: float = _tab_strip_height_px()
	if th <= 0.0:
		return full
	if tabs_position == TabContainer.POSITION_BOTTOM:
		return Rect2(full.position.x, full.position.y, full.size.x, maxf(0.0, full.size.y - th))
	return Rect2(full.position.x, full.position.y + th, full.size.x, maxf(0.0, full.size.y - th))


func _tab_strip_height_px() -> float:
	if not tabs_visible or get_tab_count() == 0:
		return 0.0
	var bar := get_tab_bar()
	if bar == null:
		return 0.0
	return maxf(bar.size.y, bar.get_combined_minimum_size().y)


func _accepts_tab_rearrange_drag(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	if String(d.get("type", "")) != DND_TAB_TYPE:
		return false
	if String(d.get("tab_type", "")) != DND_TAB_CONTAINER_KIND:
		return false
	if get_tabs_rearrange_group() < 0:
		return false
	var pth_u: Variant = d.get("from_path", NodePath())
	if typeof(pth_u) != TYPE_NODE_PATH:
		return false
	var from_bar := get_node_or_null(pth_u) as TabBar
	if from_bar == null:
		return false
	if from_bar.get_tabs_rearrange_group() != get_tabs_rearrange_group():
		return false
	return true


func _drop_tab_on_content_area(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	var from_ix: int = int(d.get("tab_index", -1))
	var pth_u: Variant = d.get("from_path", NodePath())
	if typeof(pth_u) != TYPE_NODE_PATH or from_ix < 0:
		return
	var from_bar := get_node_or_null(pth_u) as TabBar
	if from_bar == null:
		return
	var hb := from_bar.get_parent()
	if hb == null:
		return
	var from_tc := hb.get_parent() as TabContainer
	if from_tc == null:
		return
	if from_ix >= from_tc.get_tab_count():
		return
	# Mirrors TabContainer::move_tab_from_tab_container(_, _, get_tab_count()) — append/order by index.
	var insert_before: int = get_tab_count()
	_xfer_tab_from_container(from_tc, from_ix, insert_before)


func _xfer_tab_from_container(from_tc: TabContainer, from_idx: int, p_to_index_pre_add: int) -> void:
	if from_tc == null or from_idx < 0 or from_idx >= from_tc.get_tab_count():
		return

	var ctrl: Control = from_tc.get_tab_control(from_idx)
	if ctrl == null:
		return

	var n_here: int = get_tab_count()
	var p_ix: int = p_to_index_pre_add
	if p_ix < 0 or p_ix > n_here:
		p_ix = clampi(p_to_index_pre_add, 0, n_here)

	var title := from_tc.get_tab_title(from_idx)
	var tooltip := from_tc.get_tab_tooltip(from_idx)
	var icon := from_tc.get_tab_icon(from_idx)
	var button_icon := from_tc.get_tab_button_icon(from_idx)
	var disabled := from_tc.is_tab_disabled(from_idx)
	var hidden := from_tc.is_tab_hidden(from_idx)
	var metadata := from_tc.get_tab_metadata(from_idx)

	var icon_max_width := from_tc.get_tab_icon_max_width(from_idx)

	from_tc.remove_child(ctrl)
	add_child(ctrl, true)

	var nc_after: int = get_tab_count()
	var ix: int = p_ix
	if ix < 0 or ix > nc_after - 1:
		ix = nc_after - 1
	var pivot: Control = get_tab_control(ix) as Control
	if pivot == null:
		return
	move_child(ctrl, pivot.get_index(false))

	set_tab_title(ix, title)
	set_tab_tooltip(ix, tooltip)
	set_tab_icon(ix, icon)
	set_tab_button_icon(ix, button_icon)
	set_tab_disabled(ix, disabled)
	set_tab_hidden(ix, hidden)
	set_tab_metadata(ix, metadata)

	set_tab_icon_max_width(ix, icon_max_width)

	if not is_tab_disabled(ix):
		current_tab = ix


## IGNORE sends input to controls *under* this node in the viewport, not up to TabContainer — breaks tab drag-drop.
## PASS forwards to parent so the zone can accept rearrange drops on the placeholder surface.
func _apply_placeholder_mouse_pass(ph: Node) -> void:
	if ph == null or not is_instance_valid(ph):
		return
	if ph.get_parent() != self:
		return
	_set_mouse_filter_recursive(ph as Control, Control.MOUSE_FILTER_PASS)


func _set_mouse_filter_recursive(ctrl: Control, filter: MouseFilter) -> void:
	if ctrl == null:
		return
	ctrl.mouse_filter = filter
	for child in ctrl.get_children():
		if child is Control:
			_set_mouse_filter_recursive(child as Control, filter)


## Full-zone overlay: only TabContainer native drag payloads; hides while pointer is over the tab strip.
class _DockContentDropShield extends Control:
	var _zone: CodaDockZone = null

	func _init(z: CodaDockZone) -> void:
		_zone = z
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		focus_mode = Control.FOCUS_NONE
		visible = false
		z_as_relative = false
		z_index = 4096
		set_as_top_level(true)

	func _ready() -> void:
		set_process(true)

	func _process(_dt: float) -> void:
		if _zone == null or not _zone.is_inside_tree():
			_set_active(false)
			return
		var vp := get_viewport()
		if vp == null:
			return
		var drag_data: Variant = vp.gui_get_drag_data()
		if not _zone._accepts_tab_rearrange_drag(drag_data):
			_set_active(false)
			return
		var mp: Vector2 = vp.get_mouse_position()
		if _zone._tab_strip_global_rect().has_point(mp):
			_set_active(false)
			return
		if not _zone._content_area_global_rect().has_point(mp):
			_set_active(false)
			return
		var r := _zone._content_area_global_rect()
		global_position = r.position
		size = r.size
		_set_active(true)

	func _set_active(on: bool) -> void:
		visible = on
		mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if _zone == null:
			return false
		return _zone._accepts_tab_rearrange_drag(data)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if _zone == null:
			return
		_zone._drop_tab_on_content_area(data)
