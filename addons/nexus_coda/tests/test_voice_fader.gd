extends RefCounted
class_name TestVoiceFader

const CodaVoiceFaderScript := preload("res://addons/nexus_coda/runtime/coda_voice_fader.gd")
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_clip.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_clip_fade()
	failed += _test_immediate_fade()
	failed += _test_cancel_suppresses_fade_callback()
	failed += _test_cancel_before_reuse()
	return failed


static func _test_clip_fade() -> int:
	var clip = CodaTimelineClipScript.new()
	clip.start_seconds = 10.0
	clip.duration_seconds = 8.0
	clip.fade_in_seconds = 2.0
	clip.fade_out_seconds = 2.0
	var mid: float = CodaVoiceFaderScript.clip_fade_db_offset(clip, 14.0)
	if mid < -0.1:
		push_error("clip fade mid should be near 0 dB, got %s" % mid)
		return 1
	var start: float = CodaVoiceFaderScript.clip_fade_db_offset(clip, 10.5)
	if start >= mid:
		push_error("clip fade in should attenuate at start")
		return 1
	return 0


static func _test_immediate_fade() -> int:
	var owner := Node.new()
	var player := AudioStreamPlayer.new()
	owner.add_child(player)
	player.volume_db = 0.0
	var fader := CodaVoiceFaderScript.new(owner)
	fader.fade_volume_db(player, -20.0, 0)
	if abs(player.volume_db - (-20.0)) > 0.001:
		push_error("fade_ms 0 should set volume immediately")
		owner.queue_free()
		return 1
	owner.queue_free()
	return 0


static func _test_cancel_suppresses_fade_callback() -> int:
	var owner := Node.new()
	var player := AudioStreamPlayer.new()
	owner.add_child(player)
	var fader := CodaVoiceFaderScript.new(owner)
	var completed := false
	fader.fade_volume_db(player, -80.0, 5000, func() -> void: completed = true)
	fader.cancel(player)
	if completed:
		push_error("cancel should suppress fade on_complete callback")
		owner.queue_free()
		return 1
	owner.queue_free()
	return 0


static func _test_cancel_before_reuse() -> int:
	var owner := Node.new()
	var player := AudioStreamPlayer.new()
	owner.add_child(player)
	player.volume_db = 0.0
	var fader := CodaVoiceFaderScript.new(owner)
	fader.fade_volume_db(player, -80.0, 5000)
	fader.cancel(player)
	player.volume_db = -6.0
	if abs(player.volume_db - (-6.0)) > 0.001:
		push_error("cancel should leave volume at the value set for reuse")
		owner.queue_free()
		return 1
	owner.queue_free()
	return 0
