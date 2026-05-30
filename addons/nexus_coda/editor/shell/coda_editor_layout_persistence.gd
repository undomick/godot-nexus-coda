@tool
class_name CodaEditorLayoutPersistence
extends RefCounted

## Persists dock layout JSON and layout preference under the editor cache dir.

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaJsonUtilScript := preload("res://addons/nexus_coda/domain/io/coda_json_util.gd")
const CodaEditorLayoutStoreScript := preload(
	"res://addons/nexus_coda/editor/shell/coda_editor_layout_store.gd"
)

const CUSTOM_LAYOUT_SUBDIR := "nexus_coda"
const CUSTOM_LAYOUT_FILENAME := "custom_layout.json"
const CUSTOM_LAYOUT_PREFS_FILENAME := "layout_prefs.json"
const CUSTOM_LAYOUT_PREFS_KEY := "preferred_layout"
const CUSTOM_LAYOUT_PREF_FACTORY := "factory"
const CUSTOM_LAYOUT_PREF_CUSTOM := "custom"

var plugin: EditorPlugin = null
var dock_host: CodaDockHost = null
var _autosave_queued: bool = false
var _host: Node = null


func setup(host: Node, plugin_ref: EditorPlugin, dock_host_ref: CodaDockHost) -> void:
	_host = host
	plugin = plugin_ref
	dock_host = dock_host_ref


func on_layout_changed() -> void:
	if _autosave_queued:
		return
	_autosave_queued = true
	if _host != null and _host.has_method(&"_deferred_layout_autosave"):
		_host.call_deferred(&"_deferred_layout_autosave")


func run_deferred_autosave() -> void:
	_autosave_queued = false
	if _host == null or not is_instance_valid(_host) or dock_host == null or dock_host.dock_manager == null:
		return
	var path: String = custom_layout_store_path()
	if path.is_empty():
		return
	var payload: Dictionary = CodaEditorLayoutStoreScript.build_payload(
		dock_host, dock_host.dock_manager
	)
	var text: String = CodaJsonUtilScript.stringify(payload, "  ")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	if f.has_method(&"flush"):
		f.flush()
	f.close()
	set_preferred_layout(CUSTOM_LAYOUT_PREF_CUSTOM)


func custom_layout_store_path() -> String:
	if plugin == null:
		return ""
	var cache: String = plugin.get_editor_interface().get_editor_paths().get_cache_dir()
	if cache.is_empty():
		return ""
	return cache.path_join(CUSTOM_LAYOUT_SUBDIR).path_join(CUSTOM_LAYOUT_FILENAME)


func layout_prefs_store_path() -> String:
	if plugin == null:
		return ""
	var cache: String = plugin.get_editor_interface().get_editor_paths().get_cache_dir()
	if cache.is_empty():
		return ""
	return cache.path_join(CUSTOM_LAYOUT_SUBDIR).path_join(CUSTOM_LAYOUT_PREFS_FILENAME)


func get_preferred_layout() -> String:
	var p: String = layout_prefs_store_path()
	if p.is_empty() or not FileAccess.file_exists(p):
		return CUSTOM_LAYOUT_PREF_CUSTOM
	var text: String = FileAccess.get_file_as_string(p)
	if text.is_empty():
		return CUSTOM_LAYOUT_PREF_CUSTOM
	var json := JSON.new()
	if json.parse(text) != OK:
		return CUSTOM_LAYOUT_PREF_CUSTOM
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return CUSTOM_LAYOUT_PREF_CUSTOM
	var pref: String = str((root as Dictionary).get(CUSTOM_LAYOUT_PREFS_KEY, CUSTOM_LAYOUT_PREF_CUSTOM))
	return pref if pref in [CUSTOM_LAYOUT_PREF_FACTORY, CUSTOM_LAYOUT_PREF_CUSTOM] else CUSTOM_LAYOUT_PREF_CUSTOM


func set_preferred_layout(pref: String) -> void:
	var p: String = layout_prefs_store_path()
	if p.is_empty():
		return
	var dir_path: String = p.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(dir_path)
	var payload := {
		"version": 1,
		CUSTOM_LAYOUT_PREFS_KEY: pref,
	}
	var text: String = CodaJsonUtilScript.stringify(payload, "  ")
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	if f.has_method(&"flush"):
		f.flush()
	f.close()


func save_custom_layout() -> void:
	if dock_host == null or dock_host.dock_manager == null:
		return
	var path: String = custom_layout_store_path()
	if path.is_empty():
		return
	var dir_path: String = path.get_base_dir()
	if not dir_path.is_empty():
		DirAccess.make_dir_recursive_absolute(dir_path)
	var dm: CodaDockManager = dock_host.dock_manager
	var payload: Dictionary = CodaEditorLayoutStoreScript.build_payload(dock_host, dm)
	var text: String = CodaJsonUtilScript.stringify(payload, "  ")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		NexusCodaLog.warn("layout", "Could not save custom layout (%s)" % str(FileAccess.get_open_error()))
		return
	f.store_string(text)
	if f.has_method(&"flush"):
		f.flush()
	f.close()
	set_preferred_layout(CUSTOM_LAYOUT_PREF_CUSTOM)
	NexusCodaLog.info("layout", "Saved custom layout.")


func load_custom_layout_if_present() -> void:
	var path: String = custom_layout_store_path()
	if get_preferred_layout() != CUSTOM_LAYOUT_PREF_CUSTOM:
		return
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	load_custom_layout()


func load_custom_layout() -> void:
	if dock_host == null or dock_host.dock_manager == null:
		return
	var path: String = custom_layout_store_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		NexusCodaLog.info("layout", "No saved custom layout found.")
		return
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		NexusCodaLog.warn("layout", "Saved custom layout is invalid JSON.")
		return
	var root: Variant = json.data
	if typeof(root) != TYPE_DICTIONARY:
		return
	CodaEditorLayoutStoreScript.apply_payload(
		dock_host, dock_host.dock_manager, root as Dictionary
	)
	set_preferred_layout(CUSTOM_LAYOUT_PREF_CUSTOM)
	NexusCodaLog.info("layout", "Loaded custom layout.")


func clear_custom_layout() -> void:
	var path: String = custom_layout_store_path()
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		var err: Error = DirAccess.remove_absolute(path)
		if err != OK:
			NexusCodaLog.warn("layout", "Could not remove saved custom layout (%s)" % error_string(err))
			return
	set_preferred_layout(CUSTOM_LAYOUT_PREF_FACTORY)
	NexusCodaLog.info("layout", "Cleared saved custom layout.")


func reset_to_factory_layout() -> void:
	if dock_host == null or dock_host.dock_manager == null:
		return
	set_preferred_layout(CUSTOM_LAYOUT_PREF_FACTORY)
	dock_host.dock_manager.reset_to_default_layout()
