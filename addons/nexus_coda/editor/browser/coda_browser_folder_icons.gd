@tool
extends RefCounted

## SVGs are authored at 64x64; scale in the Tree via theme constant icon_max_width (~16).
## Expected files in res://addons/nexus_coda/icons/ (prefix configurable):
##   {prefix}_opened_empty.svg, {prefix}_opened_filled.svg,
##   {prefix}_closed_empty.svg, {prefix}_closed_filled.svg
## Event rows: event.svg (same display size as folder icons via Tree theme).

const ICONS_DIR := "res://addons/nexus_coda/icons"
const FILE_PREFIX := "folder"
const EVENT_LEAF_SVG := "res://addons/nexus_coda/icons/event.svg"

static var _cache: Dictionary = {}
static var _event_leaf_tex: Texture2D = null
static var _event_leaf_loaded: bool = false


static func get_folder_texture(collapsed: bool, filled: bool) -> Texture2D:
	var path: String = _path_for(collapsed, filled)
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var res: Resource = load(path)
	var tex: Texture2D = res as Texture2D
	_cache[path] = tex
	return tex


static func get_event_leaf_texture() -> Texture2D:
	if _event_leaf_loaded:
		return _event_leaf_tex
	_event_leaf_loaded = true
	if not ResourceLoader.exists(EVENT_LEAF_SVG):
		return null
	var res: Resource = load(EVENT_LEAF_SVG)
	_event_leaf_tex = res as Texture2D
	return _event_leaf_tex


static func clear_cache() -> void:
	_cache.clear()
	_event_leaf_loaded = false
	_event_leaf_tex = null


static func _path_for(collapsed: bool, filled: bool) -> String:
	var open_close: String = "closed" if collapsed else "opened"
	var empty_fill: String = "filled" if filled else "empty"
	return "%s/%s_%s_%s.svg" % [ICONS_DIR, FILE_PREFIX, open_close, empty_fill]
