@tool
extends EditorContextMenuPlugin

## Adds "Send to Coda Assets" to the FileSystem dock for folders and supported audio files.

var _plugin: EditorPlugin


func attach_plugin(p: EditorPlugin) -> void:
	_plugin = p


func _popup_menu(paths: PackedStringArray) -> void:
	if not _selection_sendable(paths):
		return
	add_context_menu_item("Send to Coda Assets", _on_send_to_coda)


func _on_send_to_coda(args: Array) -> void:
	var out: PackedStringArray = PackedStringArray()
	for x in args:
		out.append(str(x).strip_edges())
	if _plugin != null and _plugin.has_method(&"send_fs_selection_to_coda_assets"):
		_plugin.call(&"send_fs_selection_to_coda_assets", out)


func _selection_sendable(paths: PackedStringArray) -> bool:
	if paths.is_empty():
		return false
	for raw in paths:
		if not _path_sendable(str(raw).strip_edges()):
			return false
	return true


func _path_sendable(p: String) -> bool:
	var s: String = p.strip_edges()
	if not s.begins_with("res://"):
		return false
	var probe: String = s.trim_suffix("/")
	if DirAccess.open(probe) != null:
		return true
	if FileAccess.file_exists(probe) and _audio_extension_allowed(String(probe.get_extension())):
		return true
	return false


func _audio_extension_allowed(ext: String) -> bool:
	match String(ext).to_lower():
		"wav", "ogg", "oga", "mp3", "flac":
			return true
		_:
			return false
