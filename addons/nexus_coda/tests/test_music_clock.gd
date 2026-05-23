extends RefCounted
class_name TestMusicClock

const CodaMusicClockScript := preload("res://addons/nexus_coda/runtime/coda_music_clock.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_next_bar()
	failed += _test_time_until_next_bar()
	return failed


static func _test_next_bar() -> int:
	var next_bar: float = CodaMusicClockScript.next_bar_time(1.0, 120.0, Vector2i(4, 4))
	if abs(next_bar - 2.0) > 0.001:
		push_error("next_bar_time expected 2.0, got %s" % next_bar)
		return 1
	return 0


static func _test_time_until_next_bar() -> int:
	var wait: float = CodaMusicClockScript.time_until_next_bar(1.5, 120.0, Vector2i(4, 4))
	if abs(wait - 0.5) > 0.001:
		push_error("time_until_next_bar expected 0.5, got %s" % wait)
		return 1
	return 0
