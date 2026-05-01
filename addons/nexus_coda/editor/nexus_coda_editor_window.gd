@tool
extends Window


func _ready() -> void:
	close_requested.connect(_on_close_requested)


func _on_close_requested() -> void:
	hide()
