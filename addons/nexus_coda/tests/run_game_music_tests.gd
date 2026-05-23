extends SceneTree

## Headless game-music characterization tests. Run:
##   godot --headless --path . -s res://addons/nexus_coda/tests/run_game_music_tests.gd
## Or from test_run/:
##   godot --headless --path test_run -s res://addons/nexus_coda/tests/run_game_music_tests.gd

const TestVoiceFaderScript := preload("res://addons/nexus_coda/tests/test_voice_fader.gd")
const TestMusicClockScript := preload("res://addons/nexus_coda/tests/test_music_clock.gd")
const TestSegmentDriverScript := preload("res://addons/nexus_coda/tests/test_segment_driver.gd")
const TestMusicDirectorScript := preload("res://addons/nexus_coda/tests/test_music_director.gd")
const TestGameBridgeScript := preload("res://addons/nexus_coda/tests/test_game_bridge.gd")
const TestSnapshotBlenderScript := preload("res://addons/nexus_coda/tests/test_snapshot_blender.gd")
const TestTimelineMusicControllerScript := preload(
	"res://addons/nexus_coda/tests/test_timeline_music_controller.gd"
)
const TestTransitionPolicyScript := preload("res://addons/nexus_coda/tests/test_transition_policy.gd")
const TestRuntimeMusicScript := preload("res://addons/nexus_coda/tests/test_runtime_music.gd")


func _initialize() -> void:
	var failed: int = 0
	failed += TestVoiceFaderScript.run()
	failed += TestMusicClockScript.run()
	failed += TestSegmentDriverScript.run()
	failed += TestMusicDirectorScript.run()
	failed += TestGameBridgeScript.run()
	failed += TestSnapshotBlenderScript.run()
	failed += TestTimelineMusicControllerScript.run()
	failed += TestTransitionPolicyScript.run()
	failed += TestRuntimeMusicScript.run()
	if failed == 0:
		print("Coda game music tests: OK")
		quit(0)
	else:
		push_error("Coda game music tests: %d failed" % failed)
		quit(1)
