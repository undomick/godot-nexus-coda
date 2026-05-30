@tool
class_name CodaAudioStreamCache
extends RefCounted

## Cached AudioStream loads for runtime voice spawn (avoids repeated sync load() hitches).

static var _cache: Dictionary = {}


static func load_stream(stream_path: String) -> AudioStream:
	var p: String = String(stream_path).strip_edges()
	if p.is_empty():
		return null
	if _cache.has(p):
		var cached: Variant = _cache[p]
		if cached is AudioStream:
			return cached as AudioStream
	if not ResourceLoader.exists(p):
		return null
	var res: Resource = load(p)
	if res is AudioStream:
		_cache[p] = res
		return res as AudioStream
	return null


static func clear() -> void:
	_cache.clear()
