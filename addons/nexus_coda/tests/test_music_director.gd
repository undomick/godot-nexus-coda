extends RefCounted
class_name TestMusicDirector

const CodaMusicDirectorScript := preload("res://addons/nexus_coda/runtime/coda_music_director.gd")
const CodaTestMockRuntimeScript := preload(
	"res://addons/nexus_coda/tests/helpers/coda_test_mocks.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_same_path_only_params()
	failed += _test_new_path_stops_old()
	failed += _test_failed_play_keeps_old_music()
	return failed


static func _test_same_path_only_params() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h: CodaEventHandle = director.set_music("music/a", 500, "default", {"music_state": 0})
	if h == null:
		push_error("set_music should return handle")
		mock.queue_free()
		return 1
	if mock.play_calls.size() != 1:
		push_error("expected one play call")
		mock.queue_free()
		return 1
	director.set_music("music/a", 500, "default", {"music_state": 1})
	if mock.play_calls.size() != 1:
		push_error("same path should not play again")
		mock.queue_free()
		return 1
	if mock.set_parameter_calls.size() != 1:
		push_error("same path should update params")
		mock.queue_free()
		return 1
	if mock.stop_calls.size() != 0:
		push_error("same path should not stop")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_new_path_stops_old() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h1: CodaEventHandle = director.set_music("music/a", 800)
	if h1 == null:
		push_error("set_music should return handle")
		mock.queue_free()
		return 1
	director.set_music("music/b", 1200)
	if mock.stop_calls.size() != 1:
		push_error("new path should stop old handle")
		mock.queue_free()
		return 1
	if int(mock.stop_calls[0].get("fade_ms", 0)) != 1200:
		push_error("stop should use fade_ms from set_music")
		mock.queue_free()
		return 1
	if mock.play_calls.size() != 2:
		push_error("new path should play again")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0


static func _test_failed_play_keeps_old_music() -> int:
	var mock: CodaTestMockRuntime = CodaTestMockRuntimeScript.new()
	mock.play_fail_paths["music/b"] = true
	var director: CodaMusicDirector = CodaMusicDirectorScript.new()
	director.bind_runtime(mock)
	var h1: CodaEventHandle = director.set_music("music/a", 800)
	if h1 == null or not mock.is_alive(h1):
		push_error("set_music should start first track")
		mock.queue_free()
		return 1
	var h2: CodaEventHandle = director.set_music("music/b", 1200)
	if h2 != null:
		push_error("failed play should return null")
		mock.queue_free()
		return 1
	if mock.stop_calls.size() != 0:
		push_error("failed play must not stop outgoing music")
		mock.queue_free()
		return 1
	if not mock.is_alive(h1):
		push_error("outgoing handle should stay alive after failed play")
		mock.queue_free()
		return 1
	mock.queue_free()
	return 0
