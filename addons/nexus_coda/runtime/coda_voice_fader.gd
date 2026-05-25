@tool
class_name CodaVoiceFader
extends RefCounted

const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_clip.gd"
)

## Tweens [AudioStreamPlayer.volume_db] on behalf of [CodaRuntime]. Cancels stale fades when a
## pooled player is reused so volume jumps never leak across voices.

var _owner: Node
var _tweens: Dictionary = {}  ## player_instance_id (int) -> Tween


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


func cancel_players(players: Array) -> void:
	for item in players:
		cancel(item as AudioStreamPlayer)


func fade_volume_db(
	player: AudioStreamPlayer, target_db: float, fade_ms: int, on_complete: Callable = Callable()
) -> void:
	cancel(player)
	if player == null or not is_instance_valid(player):
		if on_complete.is_valid():
			on_complete.call()
		return
	if fade_ms <= 0:
		player.volume_db = target_db
		if on_complete.is_valid():
			on_complete.call()
		return
	if _owner == null or not is_instance_valid(_owner):
		player.volume_db = target_db
		if on_complete.is_valid():
			on_complete.call()
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
			if on_complete.is_valid():
				on_complete.call(),
		CONNECT_ONE_SHOT
	)


static func clip_fade_db_offset(clip, cursor_seconds: float) -> float:
	if clip == null:
		return 0.0
	var fade_in: float = maxf(0.0, float(clip.fade_in_seconds))
	var fade_out: float = maxf(0.0, float(clip.fade_out_seconds))
	var start_seconds: float = float(clip.start_seconds)
	var end_seconds: float = start_seconds + float(clip.duration_seconds)
	var rel: float = cursor_seconds - start_seconds
	if rel < 0.0:
		return -80.0
	if fade_in > 0.0 and rel < fade_in:
		return linear_to_db(clampf(rel / fade_in, 0.0, 1.0))
	var time_to_end: float = end_seconds - cursor_seconds
	if fade_out > 0.0 and time_to_end < fade_out:
		return linear_to_db(clampf(time_to_end / fade_out, 0.0, 1.0))
	return 0.0


static func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return 20.0 * log(linear) / log(10.0)
