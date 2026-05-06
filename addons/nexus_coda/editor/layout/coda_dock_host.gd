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
## Narrow strip left of the bottom dock (default: Player).
const ZONE_BOTTOM_LEFT := &"bottom_left"
const ZONE_BOTTOM := &"bottom"

const SPLIT_LEFT_RATIO := 0.14
const SPLIT_RIGHT_RATIO := 0.78
const SPLIT_BOTTOM_RATIO := 0.72
const SPLIT_BOTTOM_LEFT_RATIO := 0.22

var dock_manager: CodaDockManager

var _outer_v_split: VSplitContainer
var _top_h_split: HSplitContainer
var _middle_h_split: HSplitContainer
var _zone_left: CodaDockZone
var _zone_center: CodaDockZone
var _zone_right: CodaDockZone
var _bottom_h_split: HSplitContainer
var _zone_bottom_left: CodaDockZone
var _zone_bottom: CodaDockZone

var _splits_initialized: bool = false
var _user_adjusted_top: bool = false
var _user_adjusted_middle: bool = false
var _user_adjusted_outer: bool = false
var _user_adjusted_bottom: bool = false


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

	_bottom_h_split = HSplitContainer.new()
	_bottom_h_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_h_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_outer_v_split.add_child(_bottom_h_split)

	_zone_bottom_left = _make_zone(ZONE_BOTTOM_LEFT)
	_bottom_h_split.add_child(_zone_bottom_left)

	_zone_bottom = _make_zone(ZONE_BOTTOM)
	_bottom_h_split.add_child(_zone_bottom)

	dock_manager = CodaDockManagerScript.new()
	dock_manager.name = "CodaDockManager"
	add_child(dock_manager)
	dock_manager.register_zone(ZONE_LEFT, _zone_left)
	dock_manager.register_zone(ZONE_CENTER, _zone_center)
	dock_manager.register_zone(ZONE_RIGHT, _zone_right)
	dock_manager.register_zone(ZONE_BOTTOM_LEFT, _zone_bottom_left)
	dock_manager.register_zone(ZONE_BOTTOM, _zone_bottom)

	resized.connect(_apply_proportional_splits)
	_top_h_split.drag_ended.connect(func() -> void: _user_adjusted_top = true)
	_middle_h_split.drag_ended.connect(func() -> void: _user_adjusted_middle = true)
	_outer_v_split.drag_ended.connect(func() -> void: _user_adjusted_outer = true)
	_bottom_h_split.drag_ended.connect(func() -> void: _user_adjusted_bottom = true)
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
	if w >= 64.0 and (not _splits_initialized or not _user_adjusted_top):
		var desired_left_w: float = w * SPLIT_LEFT_RATIO
		# SplitContainer offset is relative to the center (0 = centered).
		_top_h_split.split_offset = int(round(desired_left_w - w * 0.5))
	if w >= 64.0 and (not _splits_initialized or not _user_adjusted_middle):
		var left_w: float = w * SPLIT_LEFT_RATIO
		var right_w: float = maxf(64.0, w - left_w)
		var desired_center_w: float = right_w * SPLIT_RIGHT_RATIO
		_middle_h_split.split_offset = int(round(desired_center_w - right_w * 0.5))
	if h >= 64.0 and (not _splits_initialized or not _user_adjusted_outer):
		var desired_top_h: float = h * SPLIT_BOTTOM_RATIO
		_outer_v_split.split_offset = int(round(desired_top_h - h * 0.5))
	if w >= 64.0 and (not _splits_initialized or not _user_adjusted_bottom):
		var desired_bottom_left_w: float = w * SPLIT_BOTTOM_LEFT_RATIO
		_bottom_h_split.split_offset = int(round(desired_bottom_left_w - w * 0.5))
	_splits_initialized = true


func _on_zone_emptied(_zone_id: StringName) -> void:
	if not _splits_initialized:
		_apply_proportional_splits()


func _on_zone_populated(_zone_id: StringName) -> void:
	if not _splits_initialized:
		_apply_proportional_splits()
