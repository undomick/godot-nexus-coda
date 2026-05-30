extends RefCounted
class_name TestVoiceFader

const CodaVoiceFaderScript := preload("res://addons/nexus_coda/runtime/coda_voice_fader.gd")
const CodaFadeCurveScript := preload("res://addons/nexus_coda/runtime/coda_fade_curve.gd")
const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/domain/timeline/coda_timeline_clip.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_clip_fade()
	failed += _test_audible_end_fade()
	failed += _test_fade_curve_shapes()
	failed += _test_immediate_fade()
	return failed


static func _test_audible_end_fade() -> int:
	var clip = CodaTimelineClipScript.new()
	clip.start_seconds = 0.0
	clip.duration_seconds = 12.0
	clip.fade_out_seconds = 2.0
	var audible_end: float = 10.0
	var at_end: float = CodaVoiceFaderScript.clip_fade_db_offset(clip, audible_end, audible_end)
	if at_end > -60.0:
		push_error("fade at audible timeline end should be near silence, got %s dB" % at_end)
		return 1
	var without_clamp: float = CodaVoiceFaderScript.clip_fade_db_offset(clip, 9.0)
	if without_clamp < -10.0:
		push_error("unclamped fade should still be loud far from clip end, got %s dB" % without_clamp)
		return 1
	return 0


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


static func _test_fade_curve_shapes() -> int:
	var clip_linear = CodaTimelineClipScript.new()
	clip_linear.start_seconds = 0.0
	clip_linear.duration_seconds = 4.0
	clip_linear.fade_in_seconds = 2.0
	clip_linear.fade_in_curve = 0.5

	var clip_slow = CodaTimelineClipScript.new()
	clip_slow.start_seconds = 0.0
	clip_slow.duration_seconds = 4.0
	clip_slow.fade_in_seconds = 2.0
	clip_slow.fade_in_curve = 0.2

	var clip_fast = CodaTimelineClipScript.new()
	clip_fast.start_seconds = 0.0
	clip_fast.duration_seconds = 4.0
	clip_fast.fade_in_seconds = 2.0
	clip_fast.fade_in_curve = 0.8

	var t_mid: float = 1.0
	var db_linear: float = CodaVoiceFaderScript.clip_fade_db_offset(clip_linear, t_mid)
	var db_slow: float = CodaVoiceFaderScript.clip_fade_db_offset(clip_slow, t_mid)
	var db_fast: float = CodaVoiceFaderScript.clip_fade_db_offset(clip_fast, t_mid)
	if db_slow >= db_linear:
		push_error("concave fade (0.2) should attenuate more than linear at mid fade-in")
		return 1
	if db_fast <= db_linear:
		push_error("convex fade (0.8) should attenuate less than linear at mid fade-in")
		return 1

	var clip_out_linear = CodaTimelineClipScript.new()
	clip_out_linear.start_seconds = 0.0
	clip_out_linear.duration_seconds = 4.0
	clip_out_linear.fade_out_seconds = 2.0
	clip_out_linear.fade_out_curve = 0.5

	var clip_out_slow = CodaTimelineClipScript.new()
	clip_out_slow.start_seconds = 0.0
	clip_out_slow.duration_seconds = 4.0
	clip_out_slow.fade_out_seconds = 2.0
	clip_out_slow.fade_out_curve = 0.2

	var clip_out_fast = CodaTimelineClipScript.new()
	clip_out_fast.start_seconds = 0.0
	clip_out_fast.duration_seconds = 4.0
	clip_out_fast.fade_out_seconds = 2.0
	clip_out_fast.fade_out_curve = 0.8

	var out_t_mid: float = 3.0
	var db_out_linear: float = CodaVoiceFaderScript.clip_fade_db_offset(clip_out_linear, out_t_mid)
	var db_out_slow: float = CodaVoiceFaderScript.clip_fade_db_offset(clip_out_slow, out_t_mid)
	var db_out_fast: float = CodaVoiceFaderScript.clip_fade_db_offset(clip_out_fast, out_t_mid)
	if db_out_slow <= db_out_linear:
		push_error("concave fade-out (0.2) should stay louder than linear mid fade-out")
		return 1
	if db_out_fast >= db_out_linear:
		push_error("convex fade-out (0.8) should attenuate more than linear mid fade-out")
		return 1

	var amp: float = CodaFadeCurveScript.apply(0.5, 0.5)
	if abs(amp - 0.5) > 0.001:
		push_error("linear curve should map 0.5 to 0.5 amplitude")
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
