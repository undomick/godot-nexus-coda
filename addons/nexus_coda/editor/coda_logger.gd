extends Node

## Category-filtered logger for Nexus Coda (Autoload [code]CodaLogger[/code]).
## Ring buffer for the log panel, optional NDJSON file output, ProjectSettings filters.

const PRODUCT := "Nexus Coda"
const PROJECT_PREFIX := "nexus/coda/logger/"
const CodaJsonUtilScript := preload("res://addons/nexus_coda/domain/io/coda_json_util.gd")
const DEFAULT_BUFFER_SIZE := 512
const DEFAULT_FILE_PATH := "user://nexus_coda_log.ndjson"

enum Level { DEBUG, INFO, WARN, ERROR }

const CATEGORY_BROWSER := &"browser"
const CATEGORY_DOCK := &"dock"
const CATEGORY_DOCK_MANAGER := &"dock_manager"
const CATEGORY_EDITOR := &"editor"
const CATEGORY_EDITOR_WINDOW := &"editor_window"
const CATEGORY_GRAPH := &"graph"
const CATEGORY_LAYOUT := &"layout"
const CATEGORY_MIXER := &"mixer"
const CATEGORY_PALETTE := &"palette"
const CATEGORY_PLAYER_PREVIEW := &"player_preview"
const CATEGORY_PROJECT_IO := &"project_io"
const CATEGORY_RUNTIME := &"runtime"
const CATEGORY_SELECTION := &"selection_router"
const CATEGORY_SNAPSHOTS := &"snapshots"
const CATEGORY_TIMELINE := &"timeline"
const CATEGORY_TIMELINE_PREVIEW := &"timeline_preview"
const CATEGORY_VALIDATION := &"validation"
const CATEGORY_BANK_EXPORT := &"bank_export"
const CATEGORY_MODULATION := &"modulation"
const CATEGORY_PLUGIN := &"plugin"
const CATEGORY_IMPORT := &"import"

const ALL_CATEGORIES: Array[StringName] = [
	CATEGORY_BROWSER,
	CATEGORY_DOCK,
	CATEGORY_DOCK_MANAGER,
	CATEGORY_EDITOR,
	CATEGORY_EDITOR_WINDOW,
	CATEGORY_GRAPH,
	CATEGORY_LAYOUT,
	CATEGORY_MIXER,
	CATEGORY_PALETTE,
	CATEGORY_PLAYER_PREVIEW,
	CATEGORY_PROJECT_IO,
	CATEGORY_RUNTIME,
	CATEGORY_SELECTION,
	CATEGORY_SNAPSHOTS,
	CATEGORY_TIMELINE,
	CATEGORY_TIMELINE_PREVIEW,
	CATEGORY_VALIDATION,
	CATEGORY_BANK_EXPORT,
	CATEGORY_MODULATION,
	CATEGORY_PLUGIN,
	CATEGORY_IMPORT,
]

signal log_entry_added(level: int, category: StringName, message: String, data: Dictionary)

var _buffer: Array[Dictionary] = []
var _buffer_size: int = DEFAULT_BUFFER_SIZE
var _categories_enabled: Dictionary = {}
var _minimum_level: Level = Level.DEBUG
var _output_to_debug: bool = true
var _output_to_file: bool = false
var _file_path: String = DEFAULT_FILE_PATH
var _file_write_queue: Array = []
var _file_write_mutex: Mutex = Mutex.new()
var _ui_subscribers: Dictionary = {}


static func get_default_categories_enabled_dict() -> Dictionary:
	var d: Dictionary = {}
	for c in ALL_CATEGORIES:
		d[str(c)] = true
	return d


static func _is_safe_log_path(path: String) -> bool:
	if path.is_empty():
		return false
	if not path.begins_with("user://") and not path.begins_with("res://"):
		return false
	if ".." in path or "/../" in path or path.ends_with("/.."):
		return false
	return true


func _init() -> void:
	_load_settings()
	for cat in ALL_CATEGORIES:
		if not _categories_enabled.has(cat):
			_categories_enabled[cat] = true


func _ready() -> void:
	_load_settings()


func _process(_delta: float) -> void:
	if not _output_to_file:
		return
	_file_write_mutex.lock()
	var to_write: Array = _file_write_queue.duplicate()
	_file_write_queue.clear()
	_file_write_mutex.unlock()
	for entry in to_write:
		_write_to_file(entry)


func _load_settings() -> void:
	if ProjectSettings.has_setting(PROJECT_PREFIX + "categories_enabled"):
		var v: Variant = ProjectSettings.get_setting(PROJECT_PREFIX + "categories_enabled")
		if v is Dictionary:
			var d: Dictionary = v as Dictionary
			if d.is_empty():
				for cat in ALL_CATEGORIES:
					_categories_enabled[cat] = true
			else:
				for k in d:
					_categories_enabled[StringName(str(k))] = bool(d[k])
	if ProjectSettings.has_setting(PROJECT_PREFIX + "minimum_level"):
		var lvl: int = int(ProjectSettings.get_setting(PROJECT_PREFIX + "minimum_level"))
		_minimum_level = clampi(lvl, Level.DEBUG, Level.ERROR) as Level
	if ProjectSettings.has_setting(PROJECT_PREFIX + "output_to_debug"):
		_output_to_debug = bool(ProjectSettings.get_setting(PROJECT_PREFIX + "output_to_debug"))
	if ProjectSettings.has_setting(PROJECT_PREFIX + "output_to_file"):
		_output_to_file = bool(ProjectSettings.get_setting(PROJECT_PREFIX + "output_to_file"))
	if ProjectSettings.has_setting(PROJECT_PREFIX + "file_path"):
		var configured: String = str(ProjectSettings.get_setting(PROJECT_PREFIX + "file_path"))
		if _is_safe_log_path(configured):
			_file_path = configured
		else:
			push_warning(
				"%s: Logger file_path must be user:// or res:// (no path traversal). Using default."
				% PRODUCT
			)


func log_message(
	category: StringName,
	message: String,
	level: Level = Level.INFO,
	data: Dictionary = {}
) -> void:
	if level < _minimum_level:
		return
	if not _is_category_enabled(category):
		return

	var entry := {
		"timestamp": Time.get_ticks_msec(),
		"level": int(level),
		"category": String(category),
		"message": message,
		"data": data.duplicate(),
	}

	_add_to_buffer(entry)

	if _output_to_debug:
		_output_to_debug_console(category, message, level, data)

	if _output_to_file:
		_file_write_mutex.lock()
		_file_write_queue.append(entry)
		_file_write_mutex.unlock()

	log_entry_added.emit(level, category, message, data)
	_notify_ui_subscribers(level, category, message)


func debug(category: StringName, message: String, data: Dictionary = {}) -> void:
	log_message(category, message, Level.DEBUG, data)


func info(category: StringName, message: String, data: Dictionary = {}) -> void:
	log_message(category, message, Level.INFO, data)


func warn(category: StringName, message: String, data: Dictionary = {}) -> void:
	log_message(category, message, Level.WARN, data)


func error(category: StringName, message: String, data: Dictionary = {}) -> void:
	log_message(category, message, Level.ERROR, data)


func subscribe(owner: Object, callable: Callable) -> void:
	if owner == null or not callable.is_valid():
		return
	_ui_subscribers[owner.get_instance_id()] = callable


func unsubscribe(owner: Object) -> void:
	if owner == null:
		return
	_ui_subscribers.erase(owner.get_instance_id())


func set_category_enabled(category: StringName, enabled: bool) -> void:
	_categories_enabled[category] = enabled


func is_category_enabled(category: StringName) -> bool:
	return _is_category_enabled(category)


func set_minimum_level(level: Level) -> void:
	_minimum_level = level


func get_minimum_level() -> Level:
	return _minimum_level


func get_recent_entries(count: int = 32) -> Array[Dictionary]:
	var start: int = maxi(0, _buffer.size() - count)
	var result: Array[Dictionary] = []
	for i in range(start, _buffer.size()):
		result.append(_buffer[i])
	return result


func clear_buffer() -> void:
	_buffer.clear()


func set_buffer_size(size: int) -> void:
	_buffer_size = maxi(16, size)
	while _buffer.size() > _buffer_size:
		_buffer.pop_front()


func set_output_to_debug(enabled: bool) -> void:
	_output_to_debug = enabled


func set_output_to_file(enabled: bool) -> void:
	_output_to_file = enabled


func set_file_path(path: String) -> void:
	if _is_safe_log_path(path):
		_file_path = path
	else:
		push_warning(
			"%s: Logger file_path must be user:// or res:// (no path traversal). Ignored." % PRODUCT
		)


func get_all_categories() -> Array[StringName]:
	return ALL_CATEGORIES.duplicate()


func _is_category_enabled(category: StringName) -> bool:
	if _categories_enabled.has(category):
		return bool(_categories_enabled[category])
	return true


func _add_to_buffer(entry: Dictionary) -> void:
	_buffer.append(entry)
	while _buffer.size() > _buffer_size:
		_buffer.pop_front()


func _output_to_debug_console(
	category: StringName,
	message: String,
	level: Level,
	data: Dictionary
) -> void:
	var tag: String = _level_tag(level)
	var data_suffix: String = "" if data.is_empty() else " " + str(data)
	var line := "%s | %s | %s %s%s" % [PRODUCT, String(category), tag, message, data_suffix]
	match level:
		Level.DEBUG:
			print_rich("[color=gray]%s[/color]" % line)
		Level.INFO:
			print_rich("[color=lightgray]%s[/color]" % line)
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)


func _write_to_file(entry: Dictionary) -> void:
	if not _is_safe_log_path(_file_path):
		return
	var path: String = _file_path
	if path.begins_with("user://") or path.begins_with("res://"):
		path = ProjectSettings.globalize_path(path)
	var dict := {
		"timestamp": entry.get("timestamp", 0),
		"level": entry.get("level", Level.INFO),
		"category": entry.get("category", ""),
		"message": entry.get("message", ""),
		"data": entry.get("data", {}),
	}
	var line: String = CodaJsonUtilScript.stringify(dict) + "\n"
	var f: FileAccess = null
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning(
			"%s: Cannot open log file for writing: %s (error %d)"
			% [PRODUCT, path, FileAccess.get_open_error()]
		)
		return
	f.seek_end()
	f.store_string(line)
	f.close()


func _notify_ui_subscribers(level: Level, category: StringName, message: String) -> void:
	if _ui_subscribers.is_empty():
		return
	var stale: Array = []
	for k in _ui_subscribers.keys():
		var cb: Callable = _ui_subscribers[k] as Callable
		if not cb.is_valid():
			stale.append(k)
			continue
		var owner_obj: Object = instance_from_id(int(k))
		if owner_obj == null:
			stale.append(k)
			continue
		cb.call(int(level), String(category), message)
	for k in stale:
		_ui_subscribers.erase(k)


static func _level_tag(level: Level) -> String:
	match level:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARN:
			return "WARN"
		Level.ERROR:
			return "ERROR"
	return "?"
