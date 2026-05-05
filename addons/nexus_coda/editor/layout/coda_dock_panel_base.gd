@tool
extends RefCounted
class_name CodaDockPanelInfo

## Lightweight descriptor that pairs a Godot Control with dock metadata.
## Keeping the metadata external lets existing panels (e.g. CodaBrowserPanel: VBoxContainer)
## be docked without changing their base class.

const META_PANEL_ID := &"coda_panel_id"
const META_PANEL_TITLE := &"coda_panel_title"

var panel_id: StringName
var display_title: String
var default_zone_id: StringName
var icon: Texture2D
var control: Control
## When true, the panel is shown by default after a layout reset.
var default_visible: bool = true


static func make(
	panel_id: StringName,
	display_title: String,
	default_zone_id: StringName,
	control: Control,
	icon: Texture2D = null,
	default_visible: bool = true
) -> CodaDockPanelInfo:
	var info := CodaDockPanelInfo.new()
	info.panel_id = panel_id
	info.display_title = display_title
	info.default_zone_id = default_zone_id
	info.control = control
	info.icon = icon
	info.default_visible = default_visible
	if control != null:
		control.set_meta(META_PANEL_ID, String(panel_id))
		control.set_meta(META_PANEL_TITLE, display_title)
	return info
