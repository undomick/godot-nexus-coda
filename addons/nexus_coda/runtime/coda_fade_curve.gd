class_name CodaFadeCurve
extends RefCounted

## Shared fade curve shaping (0.5 = linear, lower = slow start, higher = fast start).


static func curve_to_exponent(curve: float) -> float:
	var c: float = clampf(curve, 0.0, 1.0)
	if is_equal_approx(c, 0.5):
		return 1.0
	if c < 0.5:
		return lerpf(1.0, 4.0, (0.5 - c) / 0.5)
	return lerpf(1.0, 0.25, (c - 0.5) / 0.5)


static func apply(linear_t: float, curve: float) -> float:
	var t: float = clampf(linear_t, 0.0, 1.0)
	if t <= 0.0:
		return 0.0
	return pow(t, curve_to_exponent(curve))
