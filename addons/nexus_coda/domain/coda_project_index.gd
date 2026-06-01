class_name CodaProjectIndex
extends RefCounted

## Lazy id lookups for browser nodes and timeline clips. Rebuild on structure_changed.

var _project: CodaProject = null
var _node_by_id: Dictionary = {}
var _clip_by_id: Dictionary = {}
var _dirty: bool = true


func bind_project(project: CodaProject) -> void:
	unbind_project()
	_project = project
	_dirty = true
	if _project != null:
		if not _project.structure_changed.is_connected(_mark_dirty):
			_project.structure_changed.connect(_mark_dirty)


func unbind_project() -> void:
	if _project != null and is_instance_valid(_project):
		if _project.structure_changed.is_connected(_mark_dirty):
			_project.structure_changed.disconnect(_mark_dirty)
	_project = null
	_node_by_id.clear()
	_clip_by_id.clear()
	_dirty = true


func find_node_anywhere(target_id: String) -> CodaBrowserNode:
	_ensure_built()
	return _node_by_id.get(target_id, null) as CodaBrowserNode


func find_clip(clip_id: String) -> Dictionary:
	_ensure_built()
	return _clip_by_id.get(clip_id, {}) as Dictionary


func _mark_dirty() -> void:
	_dirty = true


func _ensure_built() -> void:
	if not _dirty or _project == null:
		return
	_node_by_id.clear()
	_clip_by_id.clear()
	_index_browser_subtree(_project.events_root)
	_index_browser_subtree(_project.assets_root)
	_index_event_clips(_project.events_root)
	_dirty = false


func _index_browser_subtree(root: CodaBrowserNode) -> void:
	if root == null:
		return
	_node_by_id[root.id] = root
	for child in root.children:
		_index_browser_subtree(child)


func _index_event_clips(root: CodaBrowserNode) -> void:
	if root == null:
		return
	if root.kind == CodaBrowserNode.Kind.EVENT and root.event_timeline != null:
		for tr in root.event_timeline.tracks:
			for clip in tr.clips:
				_clip_by_id[clip.id] = {
					"event_id": root.id,
					"track": tr,
					"clip": clip,
					"timeline": root.event_timeline,
				}
	for child in root.children:
		_index_event_clips(child)
