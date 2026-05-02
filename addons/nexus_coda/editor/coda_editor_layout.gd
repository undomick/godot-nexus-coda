extends HSplitContainer

## Keeps outer columns at 15% / 85% and inner split at 70% / 15% of total width (70:15 within the right 85% strip).

const INNER_EDITOR_SHARE := 70.0 / 85.0

@onready var _inner: HSplitContainer = $InnerSplit


func _ready() -> void:
	resized.connect(_update_proportional_splits)
	call_deferred("_update_proportional_splits")


func _update_proportional_splits() -> void:
	var w := size.x
	if w < 32:
		return
	split_offset = int(round(w * 0.15))
	if _inner == null:
		return
	var iw := _inner.size.x
	if iw < 16:
		return
	_inner.split_offset = int(round(iw * INNER_EDITOR_SHARE))
