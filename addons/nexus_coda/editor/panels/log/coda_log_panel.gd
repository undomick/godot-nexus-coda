@tool
class_name CodaLogPanel
extends VBoxContainer

## In-window log viewer that mirrors NexusCodaLog output.
## Subscribes to a small ring buffer maintained by NexusCodaLog so multiple windows
## can each show the live tail without intercepting print().

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")

const MAX_LINES := 500

var _output: RichTextLabel
var _filter: LineEdit
var _level_option: OptionButton
var _autoscroll_button: CheckBox
var _entries: Array = []


func _ready() -> void:
	name = "CodaLogPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", Tokens.SPACING_XS)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(toolbar)

	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter…"
	_filter.clear_button_enabled = true
	_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter.text_changed.connect(_on_filter_changed)
	toolbar.add_child(_filter)

	_level_option = OptionButton.new()
	_level_option.add_item("All", 0)
	_level_option.add_item("Info+", 1)
	_level_option.add_item("Warn+", 2)
	_level_option.add_item("Error", 3)
	_level_option.item_selected.connect(_on_level_changed)
	toolbar.add_child(_level_option)

	_autoscroll_button = CheckBox.new()
	_autoscroll_button.text = "Autoscroll"
	_autoscroll_button.button_pressed = true
	toolbar.add_child(_autoscroll_button)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_on_clear_pressed)
	toolbar.add_child(clear_btn)

	_output = RichTextLabel.new()
	_output.scroll_active = true
	_output.bbcode_enabled = true
	_output.fit_content = false
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.selection_enabled = true
	add_child(_output)

	NexusCodaLog.subscribe(self, _on_log_event)
	_refresh()


func _exit_tree() -> void:
	NexusCodaLog.unsubscribe(self)


func _on_log_event(level: int, scope: String, message: String) -> void:
	_entries.append({"level": level, "scope": scope, "message": message})
	if _entries.size() > MAX_LINES:
		_entries.pop_front()
	_refresh()


func _on_filter_changed(_text: String) -> void:
	_refresh()


func _on_level_changed(_idx: int) -> void:
	_refresh()


func _on_clear_pressed() -> void:
	_entries.clear()
	_refresh()


func _refresh() -> void:
	if _output == null:
		return
	var min_level: int = _level_option.get_selected_id() if _level_option != null else 0
	var filt: String = _filter.text.strip_edges().to_lower() if _filter != null else ""
	_output.clear()
	for entry in _entries:
		var lvl: int = int(entry.get("level", 0))
		if lvl < min_level:
			continue
		var scope: String = str(entry.get("scope", ""))
		var msg: String = str(entry.get("message", ""))
		if not filt.is_empty():
			var hay: String = (scope + " " + msg).to_lower()
			if not hay.contains(filt):
				continue
		_output.append_text(_format_entry(lvl, scope, msg) + "\n")
	if _autoscroll_button != null and _autoscroll_button.button_pressed:
		_output.scroll_to_line(max(0, _output.get_line_count() - 1))


func _format_entry(level: int, scope: String, message: String) -> String:
	var color: String
	var tag: String
	match level:
		NexusCodaLog.Level.DEBUG:
			color = "#888"
			tag = "DEBUG"
		NexusCodaLog.Level.INFO:
			color = "#cdd"
			tag = "INFO"
		NexusCodaLog.Level.WARN:
			color = "#e3b35a"
			tag = "WARN"
		NexusCodaLog.Level.ERROR:
			color = "#e25656"
			tag = "ERROR"
		_:
			color = "#aaa"
			tag = "?"
	var scope_part: String = ""
	if not scope.is_empty():
		scope_part = "[color=#7aa8d4]%s[/color] " % scope
	return "[color=%s]%s[/color] %s%s" % [color, tag, scope_part, message]
