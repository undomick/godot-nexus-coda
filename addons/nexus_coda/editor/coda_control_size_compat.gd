@tool
class_name CodaControlSizeCompat
extends RefCounted

## Godot 4.7 adds [member Control.custom_maximum_size]; 4.6 projects must not reference it at parse time.

static var _has_custom_maximum_size: bool = _engine_has_custom_maximum_size()


static func _engine_has_custom_maximum_size() -> bool:
	return int(Engine.get_version_info().get("hex", 0)) >= 0x040700


static func set_custom_maximum_size(control: Control, max_size: Vector2) -> void:
	if not _has_custom_maximum_size or control == null:
		return
	control.set(&"custom_maximum_size", max_size)
