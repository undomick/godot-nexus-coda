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
const TestTimelineCommandsScript := preload(
	"res://addons/nexus_coda/tests/test_timeline_commands.gd"
)
const TestTimelineClipChromeScript := preload(
	"res://addons/nexus_coda/tests/test_timeline_clip_chrome.gd"
)
const TestRuntimeNodesScript := preload("res://addons/nexus_coda/tests/test_runtime_nodes.gd")
const TestFxTailLifecycleScript := preload("res://addons/nexus_coda/tests/test_fx_tail_lifecycle.gd")
const TestBusSendsScript := preload("res://addons/nexus_coda/tests/test_bus_sends.gd")
const TestBusSyncMatrixScript := preload("res://addons/nexus_coda/tests/test_bus_sync_matrix.gd")
const TestEventMetadataScript := preload("res://addons/nexus_coda/tests/test_event_metadata.gd")


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
	failed += TestTimelineCommandsScript.run()
	failed += TestTimelineClipChromeScript.run()
	failed += TestRuntimeNodesScript.run()
	failed += TestFxTailLifecycleScript.run()
	failed += TestBusSendsScript.run()
	failed += TestBusSyncMatrixScript.run()
	failed += TestEventMetadataScript.run()
	if failed == 0:
		print("Coda game music tests: OK")
		quit(0)
	else:
		push_error("Coda game music tests: %d failed" % failed)
		quit(1)
