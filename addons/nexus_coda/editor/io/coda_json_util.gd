@tool
class_name CodaJsonUtil
extends RefCounted

## JSON helpers that strip NaN/Inf floats before [method JSON.stringify].


static func sanitize(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f):
				return 0.0
			return f
		TYPE_DICTIONARY:
			var src: Dictionary = value
			var out: Dictionary = {}
			for k in src.keys():
				out[k] = sanitize(src[k])
			return out
		TYPE_ARRAY:
			var src_a: Array = value
			var out_a: Array = []
			for item in src_a:
				out_a.append(sanitize(item))
			return out_a
		_:
			return value


static func stringify(data: Variant, indent: String = "") -> String:
	return JSON.stringify(sanitize(data), indent)
