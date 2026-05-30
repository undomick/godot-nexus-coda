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
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return Vector2(sanitize(v2.x), sanitize(v2.y))
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return Vector3(sanitize(v3.x), sanitize(v3.y), sanitize(v3.z))
		TYPE_VECTOR4:
			var v4: Vector4 = value
			return Vector4(sanitize(v4.x), sanitize(v4.y), sanitize(v4.z), sanitize(v4.w))
		TYPE_COLOR:
			var c: Color = value
			return Color(sanitize(c.r), sanitize(c.g), sanitize(c.b), sanitize(c.a))
		TYPE_PACKED_FLOAT32_ARRAY:
			var pf: PackedFloat32Array = value
			var out_pf: Array = []
			out_pf.resize(pf.size())
			for i in pf.size():
				out_pf[i] = sanitize(pf[i])
			return out_pf
		TYPE_PACKED_FLOAT64_ARRAY:
			var pd: PackedFloat64Array = value
			var out_pd: Array = []
			out_pd.resize(pd.size())
			for i in pd.size():
				out_pd[i] = sanitize(pd[i])
			return out_pd
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
