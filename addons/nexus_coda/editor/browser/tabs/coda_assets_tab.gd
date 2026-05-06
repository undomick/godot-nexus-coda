@tool
class_name CodaAssetsTab
extends CodaTreeBrowserTab

## Assets tab — folder/asset tree from CodaState.assets_root.
## Quick actions: New Folder (target = selected folder, falls back to root).
## Asset import lives in the context menu via "Import Audio File…" (Phase B/2 polish).

const _FolderNewIcon := preload("res://addons/nexus_coda/icons/folder_new.svg")

var _qa_new_folder: TextureButton


func _init() -> void:
	configure(false)


func get_tab_title() -> String:
	return "Assets"


func _build_quick_actions(host: HBoxContainer) -> void:
	_qa_new_folder = TextureButton.new()
	_qa_new_folder.custom_minimum_size = Vector2(28, 28)
	_qa_new_folder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_qa_new_folder.texture_normal = _FolderNewIcon
	_qa_new_folder.ignore_texture_size = true
	_qa_new_folder.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_qa_new_folder.tooltip_text = "New Folder"
	_qa_new_folder.pressed.connect(_on_quick_action_new_folder)
	host.add_child(_qa_new_folder)


func _on_quick_action_new_folder() -> void:
	var folder_id: String = _quick_action_target_folder_id()
	if not folder_id.is_empty():
		_create_folder(folder_id)
