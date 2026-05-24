@tool
class_name CodaAudioBusSyncGate
extends RefCounted

## AudioServer is process-global; editor preview and gameplay autoload must not stomp each other.

enum SyncCaller { EditorPreview, GameplayAutoload, EditorMixer }

static var _editor_preview_owners: Dictionary = {}
static var _gameplay_active: bool = false


static func register_editor_preview(owner_id: int) -> void:
	if owner_id <= 0:
		return
	_editor_preview_owners[owner_id] = true


static func unregister_editor_preview(owner_id: int) -> void:
	_editor_preview_owners.erase(owner_id)


static func set_gameplay_active(active: bool) -> void:
	_gameplay_active = active


static func is_gameplay_active() -> bool:
	return _gameplay_active


static func has_editor_preview() -> bool:
	return not _editor_preview_owners.is_empty()


static func may_sync_to_audio_server(caller: SyncCaller, allow_prune: bool = false) -> bool:
	if allow_prune:
		return true
	match caller:
		SyncCaller.EditorPreview, SyncCaller.EditorMixer:
			return not _gameplay_active
		SyncCaller.GameplayAutoload:
			return _gameplay_active or not has_editor_preview()
	return false


static func reset_for_tests() -> void:
	_editor_preview_owners.clear()
	_gameplay_active = false
