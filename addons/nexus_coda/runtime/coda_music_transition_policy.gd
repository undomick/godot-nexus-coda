@tool
class_name CodaMusicTransitionPolicy
extends RefCounted

## Default crossfade and sync settings (FMOD/Wwise-inspired domain defaults, no SDK coupling).

enum ClockSource { TIMELINE_CURSOR = 0, AUDIO_PLAYBACK = 1 }

var event_crossfade_ms: int = 2000
var segment_crossfade_ms: int = 500
var quantize_to_bar: bool = false
var clock_source: ClockSource = ClockSource.TIMELINE_CURSOR
## Stinger extension stubs (Phase 4).
var max_stingers: int = 4
var duck_music_db: float = -6.0


static func default_policy() -> CodaMusicTransitionPolicy:
	return CodaMusicTransitionPolicy.new()


func get_music_cursor_seconds(handle: CodaEventHandle) -> float:
	if handle == null:
		return 0.0
	match clock_source:
		ClockSource.TIMELINE_CURSOR:
			if handle.is_timeline:
				return handle.timeline_cursor_seconds
			if handle._player != null and is_instance_valid(handle._player):
				return handle.get_position()
			return 0.0
		ClockSource.AUDIO_PLAYBACK:
			# Stub: sample-accurate clock not wired yet; fall back to timeline cursor.
			if handle.is_timeline:
				return handle.timeline_cursor_seconds
			return handle.get_position()
	return 0.0
