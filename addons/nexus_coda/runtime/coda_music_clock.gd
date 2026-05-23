@tool
class_name CodaMusicClock
extends RefCounted

## Beat/bar helpers from timeline tempo metadata. Uses the timeline cursor (seconds), not
## sample-accurate audio playback position.


static func beat_duration_seconds(tempo_bpm: float) -> float:
	if tempo_bpm <= 0.0:
		return 0.0
	return 60.0 / tempo_bpm


static func bar_duration_seconds(tempo_bpm: float, time_signature: Vector2i) -> float:
	var beat: float = beat_duration_seconds(tempo_bpm)
	if beat <= 0.0:
		return 0.0
	return beat * maxi(1, time_signature.x)


static func beat_index(cursor_seconds: float, tempo_bpm: float) -> int:
	var beat_len: float = beat_duration_seconds(tempo_bpm)
	if beat_len <= 0.0:
		return 0
	return int(floor(cursor_seconds / beat_len))


static func bar_index(cursor_seconds: float, tempo_bpm: float, time_signature: Vector2i) -> int:
	var bar_len: float = bar_duration_seconds(tempo_bpm, time_signature)
	if bar_len <= 0.0:
		return 0
	return int(floor(cursor_seconds / bar_len))


static func next_bar_time(
	cursor_seconds: float, tempo_bpm: float, time_signature: Vector2i
) -> float:
	var bar_len: float = bar_duration_seconds(tempo_bpm, time_signature)
	if bar_len <= 0.0:
		return cursor_seconds
	var idx: int = int(ceil(cursor_seconds / bar_len))
	return float(idx) * bar_len


static func time_until_next_bar(
	cursor_seconds: float, tempo_bpm: float, time_signature: Vector2i
) -> float:
	return maxf(0.0, next_bar_time(cursor_seconds, tempo_bpm, time_signature) - cursor_seconds)
