extends RefCounted

## Session autosave under the editor cache dir. Restores the newest of autosave vs last saved file.

const CodaProjectIo := preload("res://addons/nexus_coda/editor/coda_project_io.gd")
const CodaJsonUtilScript := preload("res://addons/nexus_coda/editor/io/coda_json_util.gd")

const AUTOSAVE_SUBDIR := "nexus_coda"
const AUTOSAVE_FILENAME := "project_autosave.json"
const ENVELOPE_VERSION := 1

const KIND_NONE := &"none"
const KIND_AUTOSAVE := &"autosave"
const KIND_SOURCE := &"source"
const KIND_RECENT := &"recent"


static func autosave_store_path(plugin: EditorPlugin) -> String:
	if plugin == null:
		return ""
	var cache: String = plugin.get_editor_interface().get_editor_paths().get_cache_dir()
	if cache.is_empty():
		return ""
	return cache.path_join(AUTOSAVE_SUBDIR).path_join(AUTOSAVE_FILENAME)


static func write(plugin: EditorPlugin, state: CodaState, source_path: String) -> String:
	if plugin == null or state == null:
		return "No project state."
	var path: String = autosave_store_path(plugin)
	if path.is_empty():
		return "Autosave path unavailable."
	var envelope := {
		"version": ENVELOPE_VERSION,
		"source_path": str(source_path).strip_edges(),
		"project": state.to_dictionary(),
	}
	var text: String = CodaJsonUtilScript.stringify(envelope, "  ")
	if text.is_empty():
		return "Failed to serialize autosave."
	var dir_path: String = path.get_base_dir()
	if not dir_path.is_empty():
		var mk: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk != OK:
			return "Could not create autosave folder (%s)." % error_string(mk)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write autosave (%s)." % FileAccess.get_open_error()
	file.store_string(text)
	if file.has_method(&"flush"):
		file.flush()
	file.close()
	return ""


static func clear(plugin: EditorPlugin) -> void:
	var path: String = autosave_store_path(plugin)
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(path)


static func resolve_restore_candidate(plugin: EditorPlugin) -> Dictionary:
	if plugin == null:
		return {"kind": KIND_NONE}
	var autosave_path: String = autosave_store_path(plugin)
	var envelope: Dictionary = _read_envelope(autosave_path)
	var source_path: String = str(envelope.get("source_path", "")).strip_edges()
	var autosave_mtime: int = _file_modified_time_unix(autosave_path)
	var source_mtime: int = -1
	if not source_path.is_empty():
		source_mtime = _file_modified_time_unix(source_path)

	if autosave_mtime > 0 and not envelope.is_empty():
		if source_mtime < 0 or autosave_mtime >= source_mtime:
			var st: CodaState = _state_from_envelope(envelope)
			if st != null:
				return {
					"kind": KIND_AUTOSAVE,
					"state": st,
					"source_path": source_path,
				}

	if source_mtime > 0 and not source_path.is_empty():
		var loaded: Variant = CodaProjectIo.load_state_from_path(source_path)
		if loaded is CodaState:
			return {
				"kind": KIND_SOURCE,
				"state": loaded as CodaState,
				"source_path": source_path,
			}

	var recent: PackedStringArray = CodaProjectIo.read_recent_paths(plugin)
	if not recent.is_empty():
		var recent_path: String = recent[0]
		if _file_modified_time_unix(recent_path) > 0:
			var recent_loaded: Variant = CodaProjectIo.load_state_from_path(recent_path)
			if recent_loaded is CodaState:
				return {
					"kind": KIND_RECENT,
					"state": recent_loaded as CodaState,
					"source_path": recent_path,
				}

	return {"kind": KIND_NONE}


static func _read_envelope(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return {}
	return root as Dictionary


static func _state_from_envelope(envelope: Dictionary) -> CodaState:
	var project_data: Variant = envelope.get("project", {})
	if typeof(project_data) != TYPE_DICTIONARY:
		return null
	var state := CodaState.new()
	state.load_from_dictionary(project_data as Dictionary)
	return state


static func _file_modified_time_unix(path: String) -> int:
	var abs_path: String = CodaProjectIo.to_physical_path(path)
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		return -1
	return int(FileAccess.get_modified_time(abs_path))
