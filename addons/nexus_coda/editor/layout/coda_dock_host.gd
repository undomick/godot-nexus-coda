@tool
class_name CodaDockHost
extends VBoxContainer

## Hosts the dock zones inside the editor window. Pure layout container;
## panel registration is performed by the owning window via CodaDockManager.

signal panels_ready

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaDockZoneScript := preload("res://addons/nexus_coda/editor/layout/coda_dock_zone.gd")
const CodaDockManagerScript := preload("res://addons/nexus_coda/editor/layout/coda_dock_manager.gd")

const ZONE_LEFT := &"left"
const ZONE_CENTER := &"center"
const ZONE_RIGHT := &"right"
const ZONE_BOTTOM := &"bottom"

const SPLIT_LEFT_RATIO := 0.18
const SPLIT_RIGHT_RATIO := 0.78
const SPLIT_BOTTOM_RATIO := 0.72

var dock_manager: CodaDockManager

var _outer_v_split: VSplitContainer
var _top_h_split: HSplitContainer
var _middle_h_split: HSplitContainer
var _zone_left: CodaDockZone
var _zone_center: CodaDockZone
var _zone_right: CodaDockZone
var _zone_bottom: CodaDockZone


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 0)

	_outer_v_split = VSplitContainer.new()
	_outer_v_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outer_v_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_outer_v_split)

	_top_h_split = HSplitContainer.new()
	_top_h_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_h_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_outer_v_split.add_child(_top_h_split)

	_zone_left = _make_zone(ZONE_LEFT)
	_top_h_split.add_child(_zone_left)

	_middle_h_split = HSplitContainer.new()
	_middle_h_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_middle_h_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_top_h_split.add_child(_middle_h_split)

	_zone_center = _make_zone(ZONE_CENTER)
	_middle_h_split.add_child(_zone_center)

	_zone_right = _make_zone(ZONE_RIGHT)
	_middle_h_split.add_child(_zone_right)

	_zone_bottom = _make_zone(ZONE_BOTTOM)
	_outer_v_split.add_child(_zone_bottom)

	dock_manager = CodaDockManagerScript.new()
	dock_manager.name = "CodaDockManager"
	add_child(dock_manager)
	dock_manager.register_zone(ZONE_LEFT, _zone_left)
	dock_manager.register_zone(ZONE_CENTER, _zone_center)
	dock_manager.register_zone(ZONE_RIGHT, _zone_right)
	dock_manager.register_zone(ZONE_BOTTOM, _zone_bottom)

	resized.connect(_apply_proportional_splits)
	call_deferred(&"_apply_proportional_splits")
	call_deferred(&"_emit_ready")


func _make_zone(zone_id: StringName) -> CodaDockZone:
	var z := CodaDockZoneScript.new()
	z.zone_id = zone_id
	z.name = "Zone_%s" % String(zone_id)
	z.zone_emptied.connect(_on_zone_emptied)
	z.zone_populated.connect(_on_zone_populated)
	return z


func _emit_ready() -> void:
	panels_ready.emit()


func _apply_proportional_splits() -> void:
	var w: float = size.x
	var h: float = size.y
	if w >= 64.0:
		_top_h_split.split_offset = int(round(w * SPLIT_LEFT_RATIO))
		_middle_h_split.split_offset = int(round((w - w * SPLIT_LEFT_RATIO) * 0.78))
	if h >= 64.0:
		_outer_v_split.split_offset = int(round(h * SPLIT_BOTTOM_RATIO))


func _on_zone_emptied(_zone_id: StringName) -> void:
	_apply_proportional_splits()


func _on_zone_populated(_zone_id: StringName) -> void:
	_apply_proportional_splits()
