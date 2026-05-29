extends RefCounted

## Back-compat static facade. Prefer the [CodaLogger] autoload when available.

const CodaLoggerScript := preload("res://addons/nexus_coda/editor/coda_logger.gd")

const PRODUCT := "Nexus Coda"

enum Level { DEBUG, INFO, WARN, ERROR }

static var minimum_level: Level = Level.DEBUG

static var _fallback_subscribers: Dictionary = {}


static func print_ready_banner() -> void:
	var lg: Node = _logger()
	if lg != null and lg.has_method(&"info"):
		lg.call(&"info", CodaLoggerScript.CATEGORY_PLUGIN, "Ready.", {"product": PRODUCT})
		return
	print_rich("[color=chartreuse]%s: Ready.[/color]" % PRODUCT)


static func debug(scope: String, message: String) -> void:
	_emit(Level.DEBUG, scope, message)


static func info(scope: String, message: String) -> void:
	_emit(Level.INFO, scope, message)


static func warn(scope: String, message: String) -> void:
	_emit(Level.WARN, scope, message)


static func error(scope: String, message: String) -> void:
	_emit(Level.ERROR, scope, message)


static func inspect(scope: String, label: String, value: Variant) -> void:
	var text: String
	if value == null:
		text = "null"
	elif typeof(value) == TYPE_OBJECT and is_instance_valid(value):
		text = str(value)
	else:
		text = str(value)
	debug(scope, "%s: %s" % [label, text])


static func subscribe(owner: Object, callable: Callable) -> void:
	if owner == null or not callable.is_valid():
		return
	var lg: Node = _logger()
	if lg != null and lg.has_method(&"subscribe"):
		lg.call(&"subscribe", owner, callable)
		return
	_fallback_subscribers[owner.get_instance_id()] = callable


static func unsubscribe(owner: Object) -> void:
	if owner == null:
		return
	var lg: Node = _logger()
	if lg != null and lg.has_method(&"unsubscribe"):
		lg.call(&"unsubscribe", owner)
	_fallback_subscribers.erase(owner.get_instance_id())


static func _emit(level: Level, scope: String, message: String, data: Dictionary = {}) -> void:
	var lg: Node = _logger()
	if lg != null and lg.has_method(&"log_message"):
		lg.call(&"log_message", StringName(scope), message, level, data)
		return
	_log_fallback(level, scope, message, data)


static func _logger() -> Node:
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		var root: Window = (ml as SceneTree).root
		if root != null:
			return root.get_node_or_null("CodaLogger")
	return null


static func _log_fallback(
	level: Level, scope: String, message: String, data: Dictionary = {}
) -> void:
	if level < minimum_level:
		return
	var tag := _level_name(level)
	var head := "%s | %s |" % [PRODUCT, scope] if not scope.is_empty() else "%s |" % PRODUCT
	var data_suffix: String = "" if data.is_empty() else " " + str(data)
	var line := "%s %s %s%s" % [head, tag, message, data_suffix]
	match level:
		Level.DEBUG:
			print_rich("[color=gray]%s[/color]" % line)
		Level.INFO:
			print_rich("[color=lightgray]%s[/color]" % line)
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)
	_notify_fallback_subscribers(level, scope, message)


static func _notify_fallback_subscribers(level: Level, scope: String, message: String) -> void:
	if _fallback_subscribers.is_empty():
		return
	var stale: Array = []
	for k in _fallback_subscribers.keys():
		var cb: Callable = _fallback_subscribers[k] as Callable
		if not cb.is_valid():
			stale.append(k)
			continue
		var owner_obj: Object = instance_from_id(int(k))
		if owner_obj == null:
			stale.append(k)
			continue
		cb.call(int(level), scope, message)
	for k in stale:
		_fallback_subscribers.erase(k)


static func _level_name(level: Level) -> String:
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
