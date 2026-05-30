@tool
class_name CodaBrowserRenameDialog
extends RefCounted

## Shared AcceptDialog + LineEdit for browser tree and bank rename flows.

var dialog: AcceptDialog
var field: LineEdit


static func create(parent: Node, title: String = "Rename") -> CodaBrowserRenameDialog:
	var inst := CodaBrowserRenameDialog.new()
	inst._build(parent, title)
	return inst


func _build(parent: Node, title: String) -> void:
	dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_autowrap = true
	field = LineEdit.new()
	field.custom_minimum_size = Vector2(280, 0)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 8)
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	margin.add_child(field)
	dialog.add_child(margin)
	dialog.about_to_popup.connect(
		func() -> void: field.call_deferred(&"grab_focus")
	)
	parent.add_child(dialog)


func connect_confirmed(callback: Callable) -> void:
	dialog.confirmed.connect(callback)


func connect_text_submitted(callback: Callable) -> void:
	field.text_submitted.connect(callback)


func popup_for(target_name: String) -> void:
	field.text = target_name
	dialog.popup_centered()


func hide_dialog() -> void:
	dialog.hide()
