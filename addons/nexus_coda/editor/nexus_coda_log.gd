extends RefCounted
## Central logging for the Nexus Coda editor addon.
## Use static methods only; preload this script where needed (no global class_name).

const PRODUCT := "Nexus Coda"

enum Level { DEBUG, INFO, WARN, ERROR }

## Raise to INFO or WARN to reduce noise while debugging specific areas.
static var minimum_level: Level = Level.DEBUG


static func print_ready_banner() -> void:
	print_rich("[color=chartreuse]%s: Ready.[/color]" % PRODUCT)


static func debug(scope: String, message: String) -> void:
	_log(Level.DEBUG, scope, message)


static func info(scope: String, message: String) -> void:
	_log(Level.INFO, scope, message)


static func warn(scope: String, message: String) -> void:
	_log(Level.WARN, scope, message)


static func error(scope: String, message: String) -> void:
	_log(Level.ERROR, scope, message)


## Logs an unexpected Variant (errors, nullables, dictionaries) without losing detail.
static func inspect(scope: String, label: String, value: Variant) -> void:
	var text: String
	if value == null:
		text = "null"
	elif typeof(value) == TYPE_OBJECT and is_instance_valid(value):
		text = str(value)
	else:
		text = str(value)
	debug(scope, "%s: %s" % [label, text])


static func _log(level: Level, scope: String, message: String) -> void:
	if level < minimum_level:
		return
	var tag := _level_name(level)
	var head := "%s | %s |" % [PRODUCT, scope] if not scope.is_empty() else "%s |" % PRODUCT
	var line := "%s %s %s" % [head, tag, message]
	match level:
		Level.DEBUG:
			print_rich("[color=gray]%s[/color]" % line)
		Level.INFO:
			print_rich("[color=lightgray]%s[/color]" % line)
		Level.WARN:
			push_warning(line)
		Level.ERROR:
			push_error(line)


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
