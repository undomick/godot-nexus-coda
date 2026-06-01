@tool
class_name CodaDockManager
extends Node

## Owns dock zones and panels. Routes panels to zones, persists layout,
## and answers "is panel visible?" / "show panel" / "hide panel" requests
## from the View menu and other UI surfaces.

signal panel_visibility_changed(panel_id: StringName, is_visible: bool)
signal layout_changed

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaDockZoneScript := preload("res://addons/nexus_coda/editor/layout/coda_dock_zone.gd")
const CodaDockPanelInfoScript := preload("res://addons/nexus_coda/editor/layout/coda_dock_panel_base.gd")

var _zones_by_id: Dictionary = {}
var _panels_by_id: Dictionary = {}
var _zone_order: PackedStringArray = PackedStringArray()
var _last_zone_by_panel: Dictionary = {}


func register_zone(zone_id: StringName, zone: CodaDockZone) -> void:
	if zone == null:
		NexusCodaLog.warn("dock_manager", 'register_zone: null for "%s"' % String(zone_id))
		return
	zone.zone_id = zone_id
	_zones_by_id[String(zone_id)] = zone
	if not _zone_order.has(String(zone_id)):
		_zone_order.append(String(zone_id))


func get_zone(zone_id: StringName) -> CodaDockZone:
	return _zones_by_id.get(String(zone_id), null) as CodaDockZone


func get_zone_ids() -> PackedStringArray:
	return _zone_order.duplicate()


func register_panel(info: CodaDockPanelInfo) -> void:
	if info == null or info.control == null:
		NexusCodaLog.warn("dock_manager", "register_panel: missing control or info")
		return
	_panels_by_id[String(info.panel_id)] = info
	if info.default_visible:
		_place_panel_in_zone(info, info.default_zone_id)
	# Detached by default: parent stays null until shown.


func get_panel_info(panel_id: StringName) -> CodaDockPanelInfo:
	return _panels_by_id.get(String(panel_id), null) as CodaDockPanelInfo


func get_panel_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _panels_by_id.keys():
		out.append(String(k))
	return out


func is_panel_visible(panel_id: StringName) -> bool:
	var info: CodaDockPanelInfo = get_panel_info(panel_id)
	if info == null or info.control == null:
		return false
	return info.control.get_parent() != null


func show_panel(panel_id: StringName) -> void:
	var info: CodaDockPanelInfo = get_panel_info(panel_id)
	if info == null:
		return
	if is_panel_visible(panel_id):
		_focus_panel(info)
		return
	var zone_id: StringName = _find_current_or_default_zone(info)
	_place_panel_in_zone(info, zone_id)
	_last_zone_by_panel[String(info.panel_id)] = String(zone_id)
	panel_visibility_changed.emit(info.panel_id, true)
	layout_changed.emit()


func hide_panel(panel_id: StringName) -> void:
	var info: CodaDockPanelInfo = get_panel_info(panel_id)
	if info == null or info.control == null:
		return
	if info.control.get_parent() == null:
		return
	var parent: Node = info.control.get_parent()
	if parent is CodaDockZone:
		_last_zone_by_panel[String(info.panel_id)] = String((parent as CodaDockZone).zone_id)
	parent.remove_child(info.control)
	panel_visibility_changed.emit(info.panel_id, false)
	layout_changed.emit()


func toggle_panel(panel_id: StringName) -> void:
	if is_panel_visible(panel_id):
		hide_panel(panel_id)
	else:
		show_panel(panel_id)


func reset_to_default_layout() -> void:
	for panel_id in _panels_by_id.keys():
		var info: CodaDockPanelInfo = _panels_by_id[panel_id] as CodaDockPanelInfo
		if info.control != null and info.control.get_parent() != null:
			info.control.get_parent().remove_child(info.control)
	for panel_id in _panels_by_id.keys():
		var info: CodaDockPanelInfo = _panels_by_id[panel_id] as CodaDockPanelInfo
		if info.default_visible:
			_place_panel_in_zone(info, info.default_zone_id)
	layout_changed.emit()


## Returns a Dictionary mapping zone_id -> [panel_id, …] reflecting current placement
## (panels in tab order). Hidden panels are absent.
func get_layout_state() -> Dictionary:
	var state: Dictionary = {}
	for zone_id_s in _zones_by_id.keys():
		var zone: CodaDockZone = _zones_by_id[zone_id_s] as CodaDockZone
		var arr: Array = []
		for ctrl in zone.panel_controls():
			var pid: String = String(ctrl.get_meta(CodaDockPanelInfoScript.META_PANEL_ID, ""))
			if pid.is_empty():
				continue
			arr.append(pid)
		state[zone_id_s] = arr
	return state


func apply_layout_state(state: Dictionary) -> void:
	if state == null or state.is_empty():
		return
	# Detach all first to avoid duplicate parents.
	for panel_id in _panels_by_id.keys():
		var info: CodaDockPanelInfo = _panels_by_id[panel_id] as CodaDockPanelInfo
		if info.control != null and info.control.get_parent() != null:
			info.control.get_parent().remove_child(info.control)
	for zone_id_s in state.keys():
		var zone: CodaDockZone = _zones_by_id.get(String(zone_id_s), null) as CodaDockZone
		if zone == null:
			continue
		var arr: Variant = state[zone_id_s]
		if not (arr is Array):
			continue
		for entry in arr:
			var pid: String = String(entry)
			var info2: CodaDockPanelInfo = _panels_by_id.get(pid, null) as CodaDockPanelInfo
			if info2 == null or info2.control == null:
				continue
			zone.add_panel_control(info2.control)
	layout_changed.emit()


func _place_panel_in_zone(info: CodaDockPanelInfo, zone_id: StringName) -> void:
	var zone: CodaDockZone = get_zone(zone_id)
	if zone == null:
		# Fallback to first registered zone if requested zone is missing.
		if _zone_order.size() == 0:
			NexusCodaLog.warn(
				"dock_manager",
				'no zones registered; cannot place panel "%s"' % String(info.panel_id)
			)
			return
		zone = get_zone(StringName(_zone_order[0]))
	zone.add_panel_control(info.control)
	_focus_panel(info)


func _focus_panel(info: CodaDockPanelInfo) -> void:
	if info == null or info.control == null:
		return
	var parent: Node = info.control.get_parent()
	if parent == null:
		return
	var tabs: TabContainer = parent as TabContainer
	if tabs == null:
		# Parent might be the CodaDockZone or its inner TabContainer wrapper.
		var z: CodaDockZone = parent as CodaDockZone
		if z != null:
			z.focus_panel_control(info.control)
		return
	var idx: int = tabs.get_tab_idx_from_control(info.control)
	if idx >= 0:
		tabs.current_tab = idx


func get_last_zones() -> Dictionary:
	return _last_zone_by_panel.duplicate(true)


func set_last_zones(zones: Dictionary) -> void:
	_last_zone_by_panel.clear()
	for k in zones.keys():
		_last_zone_by_panel[String(k)] = String(zones[k])


func _find_current_or_default_zone(info: CodaDockPanelInfo) -> StringName:
	var remembered: String = str(_last_zone_by_panel.get(String(info.panel_id), ""))
	if not remembered.is_empty() and get_zone(StringName(remembered)) != null:
		return StringName(remembered)
	return info.default_zone_id


func teardown() -> void:
	const Lifecycle := preload("res://addons/nexus_coda/editor/shell/coda_editor_lifecycle.gd")
	for panel_id in _panels_by_id.keys():
		var info: CodaDockPanelInfo = _panels_by_id[panel_id] as CodaDockPanelInfo
		if info == null or info.control == null or not is_instance_valid(info.control):
			continue
		Lifecycle.call_editor_teardown(info.control)
		info.control.free()
	_panels_by_id.clear()
	_last_zone_by_panel.clear()
