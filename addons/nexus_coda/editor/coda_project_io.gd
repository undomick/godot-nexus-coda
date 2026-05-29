extends RefCounted

## JSON save/load for CodaState and editor-wide recent-project list (cache dir).
##
## Custom extensions: raw bytes/text are written with [method FileAccess.open] and [method FileAccess.store_string].
## For the **FileSystem dock** to show a custom type and run the import pipeline, this addon also registers
## an [EditorImportPlugin] (see `editor/import/`) for `.ncoda` — same role as a `.quest` importer in Quest Weaver.

const FORMAT_EXTENSION := "ncoda"
const FORMAT_FILTER := "*.ncoda ; Nexus Coda Project"
const ERR_FILE_MISSING := "File does not exist."

const RECENT_MAX := 12
const RECENT_SUBDIR := "nexus_coda"
const RECENT_FILENAME := "recent_projects.json"

const CodaJsonUtilScript := preload("res://addons/nexus_coda/editor/io/coda_json_util.gd")


## EditorFileDialog may pass res:// or absolute paths; FileAccess in the editor is most reliable on a globalized path.
static func to_physical_path(path: String) -> String:
	var p: String = str(path).strip_edges().replace("\\", "/")
	if p.is_empty():
		return ""
	if p.begins_with("res://"):
		var g: String = ProjectSettings.globalize_path(p)
		if not g.is_empty():
			return g
		var tail: String = p.trim_prefix("res://").lstrip("/")
		var root: String = ProjectSettings.globalize_path("res://")
		if root.is_empty():
			return ""
		return root.path_join(tail)
	if p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	return p


static func save_to_path(state: CodaState, path: String) -> String:
	if state == null:
		return "Internal error: no project state."
	var data: Dictionary = state.to_dictionary()
	var text: String = CodaJsonUtilScript.stringify(data, "  ")
	if text.is_empty() and not data.is_empty():
		return "Failed to serialize project data."
	var abs_path: String = to_physical_path(path)
	if abs_path.is_empty():
		return "Invalid save path."
	var base_dir: String = abs_path.get_base_dir()
	if not base_dir.is_empty():
		var mk: Error = DirAccess.make_dir_recursive_absolute(base_dir)
		if mk != OK:
			return "Could not create folder (%s)." % error_string(mk)
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	var raw: String = str(path).strip_edges()
	if file == null and raw.begins_with("res://"):
		# Some editor builds open res:// more reliably than the globalized path.
		file = FileAccess.open(raw, FileAccess.WRITE)
	if file == null:
		return "Could not write file (%s) — path: %s" % [FileAccess.get_open_error(), abs_path]
	file.store_string(text)
	if file.has_method(&"flush"):
		file.flush()
	file.close()
	return ""


static func load_state_from_path(path: String) -> Variant:
	var abs_path: String = to_physical_path(path)
	if abs_path.is_empty():
		return "Invalid path."
	if not FileAccess.file_exists(abs_path):
		return ERR_FILE_MISSING
	var text: String = FileAccess.get_file_as_string(abs_path)
	if text.is_empty():
		return "File is empty."
	var json := JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		return "Invalid JSON (%s)." % error_string(err)
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return "Root JSON value must be an object."
	var state := CodaState.new()
	state.load_from_dictionary(root as Dictionary)
	return state


static func recent_store_path(plugin: EditorPlugin) -> String:
	var cache: String = plugin.get_editor_interface().get_editor_paths().get_cache_dir()
	return cache.path_join(RECENT_SUBDIR).path_join(RECENT_FILENAME)


static func read_recent_paths(plugin: EditorPlugin) -> PackedStringArray:
	var p: String = recent_store_path(plugin)
	if not FileAccess.file_exists(p):
		return PackedStringArray()
	var text: String = FileAccess.get_file_as_string(p)
	if text.is_empty():
		return PackedStringArray()
	var json := JSON.new()
	if json.parse(text) != OK:
		return PackedStringArray()
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return PackedStringArray()
	var arr: Variant = data.get("paths", [])
	if typeof(arr) != TYPE_ARRAY:
		return PackedStringArray()
	var out := PackedStringArray()
	for item in arr:
		var s: String = str(item).strip_edges()
		if s.is_empty():
			continue
		out.append(s)
	return out


static func write_recent_paths(plugin: EditorPlugin, paths: PackedStringArray) -> void:
	var dir_path: String = plugin.get_editor_interface().get_editor_paths().get_cache_dir().path_join(
		RECENT_SUBDIR
	)
	DirAccess.make_dir_recursive_absolute(dir_path)
	var payload := {"paths": Array(paths)}
	var text: String = CodaJsonUtilScript.stringify(payload, "  ")
	var target: String = recent_store_path(plugin)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		push_warning(
			"Nexus Coda: could not write recent files list (%s)." % FileAccess.get_open_error()
		)
		return
	file.store_string(text)
	file.close()


static func prune_missing_recent_paths(plugin: EditorPlugin) -> void:
	var list: PackedStringArray = read_recent_paths(plugin)
	var kept := PackedStringArray()
	for i in list.size():
		var p: String = list[i]
		var abs_path: String = to_physical_path(p)
		if abs_path.is_empty():
			continue
		if FileAccess.file_exists(abs_path):
			kept.append(p)
	if kept.size() == list.size():
		return
	write_recent_paths(plugin, kept)


static func remove_recent_path(plugin: EditorPlugin, path: String) -> void:
	var target: String = str(path).strip_edges()
	if target.is_empty():
		return
	var list: PackedStringArray = read_recent_paths(plugin)
	var filtered := PackedStringArray()
	for i in list.size():
		if list[i] != target:
			filtered.append(list[i])
	write_recent_paths(plugin, filtered)


static func remember_opened_path(plugin: EditorPlugin, path: String) -> void:
	var p: String = str(path).strip_edges()
	if p.is_empty():
		return
	var list: PackedStringArray = read_recent_paths(plugin)
	var filtered := PackedStringArray()
	for i in list.size():
		if list[i] != p:
			filtered.append(list[i])
	var merged := PackedStringArray()
	merged.append(p)
	for i in filtered.size():
		if merged.size() >= RECENT_MAX:
			break
		merged.append(filtered[i])
	write_recent_paths(plugin, merged)
