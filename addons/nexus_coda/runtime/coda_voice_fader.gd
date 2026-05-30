@tool
class_name CodaVoiceFader
extends RefCounted

## Volume tweens for pooled timeline/graph voices. Cancels stale fades on player reuse.

const CodaFadeCurveScript := preload("res://addons/nexus_coda/runtime/coda_fade_curve.gd")

var _owner: Node
var _tweens: Dictionary = {}


func _init(owner: Node) -> void:
	_owner = owner


func cancel(player: AudioStreamPlayer) -> void:
	if player == null or not is_instance_valid(player):
		return
	var key: int = player.get_instance_id()
	if not _tweens.has(key):
		return
	var tw: Tween = _tweens[key] as Tween
	if tw != null and tw.is_valid():
		tw.kill()
	_tweens.erase(key)


func fade_volume_db(
	player: AudioStreamPlayer, target_db: float, fade_ms: int, on_complete: Callable = Callable()
) -> void:
	cancel(player)
	if player == null or not is_instance_valid(player):
		_call_if_valid(on_complete)
		return
	if fade_ms <= 0 or _owner == null or not is_instance_valid(_owner):
		player.volume_db = target_db
		_call_if_valid(on_complete)
		return
	var tw: Tween = _owner.create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.set_ease(Tween.EASE_IN_OUT)
	var key: int = player.get_instance_id()
	_tweens[key] = tw
	tw.tween_property(player, "volume_db", target_db, float(fade_ms) / 1000.0)
	tw.finished.connect(
		func() -> void:
			_tweens.erase(key)
			_call_if_valid(on_complete),
		CONNECT_ONE_SHOT
	)


static func clip_fade_db_offset(
	clip: CodaTimelineClip,
	cursor_seconds: float,
	audible_end_seconds: float = -1.0,
	include_fade_out: bool = true,
) -> float:
	if clip == null:
		return 0.0
	var fade_in: float = maxf(0.0, clip.fade_in_seconds)
	var fade_out: float = maxf(0.0, clip.fade_out_seconds)
	var start_seconds: float = clip.start_seconds
	var end_seconds: float = clip.end_seconds()
	if audible_end_seconds > 0.0:
		end_seconds = minf(end_seconds, audible_end_seconds)
	var rel: float = cursor_seconds - start_seconds
	if rel < 0.0:
		return -80.0
	if fade_in > 0.0 and rel < fade_in:
		var lin_in: float = CodaFadeCurveScript.apply(rel / fade_in, clip.fade_in_curve)
		return linear_to_db(lin_in)
	if not include_fade_out:
		return 0.0
	var time_to_end: float = end_seconds - cursor_seconds
	if fade_out > 0.0 and time_to_end < fade_out:
		var lin_out: float = CodaFadeCurveScript.apply_fade_out(
			time_to_end / fade_out, clip.fade_out_curve
		)
		return linear_to_db(lin_out)
	return 0.0


static func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)


static func _call_if_valid(cb: Callable) -> void:
	if cb.is_valid():
		cb.call()
