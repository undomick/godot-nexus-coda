extends CodaRuntime
class_name SegmentSpawnTestRuntime

## Runtime stub for segment spawn tests (must live in its own file — inner classes cannot extend CodaRuntime).

var segment_spawn_ok: bool = true


func spawn_timeline_segment_voice(
	handle: CodaEventHandle, d: Dictionary, entry: Dictionary, crossfade_ms: int = -1
) -> bool:
	if not segment_spawn_ok:
		return false
	var clip_id: String = String(entry.get("sound_id", ""))
	if clip_id.is_empty():
		return false
	var voices: Dictionary = d.get("voices", {})
	voices[clip_id] = AudioStreamPlayer.new()
	d["voices"] = voices
	return true
