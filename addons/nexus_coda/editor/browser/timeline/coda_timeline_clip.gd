@tool
class_name CodaTimelineClip
extends RefCounted

## Audio fragment placed on a CodaTimelineTrack.
## `audio_path` is a `res://...` path to a Godot AudioStream; `start_seconds` is the
## clip's start position on the timeline; `duration_seconds` is how long it plays;
## `offset_seconds` skips into the source audio; volume / pitch / fades are local.

var id: String
var audio_path: String = ""
var start_seconds: float = 0.0
var duration_seconds: float = 0.0
var offset_seconds: float = 0.0
var volume_db: float = 0.0
var pitch_scale: float = 1.0
var fade_in_seconds: float = 0.0
var fade_out_seconds: float = 0.0


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "tcl_%d_%d" % [Time.get_ticks_usec(), randi()]


func end_seconds() -> float:
	return start_seconds + duration_seconds


func clone_keep_id() -> CodaTimelineClip:
	var c := CodaTimelineClip.new()
	c.id = id
	c.audio_path = audio_path
	c.start_seconds = start_seconds
	c.duration_seconds = duration_seconds
	c.offset_seconds = offset_seconds
	c.volume_db = volume_db
	c.pitch_scale = pitch_scale
	c.fade_in_seconds = fade_in_seconds
	c.fade_out_seconds = fade_out_seconds
	return c


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"audio_path": audio_path,
		"start": start_seconds,
		"duration": duration_seconds,
		"offset": offset_seconds,
		"volume_db": volume_db,
		"pitch_scale": pitch_scale,
		"fade_in": fade_in_seconds,
		"fade_out": fade_out_seconds,
	}


static func from_dictionary(data: Dictionary) -> CodaTimelineClip:
	var c := CodaTimelineClip.new()
	var sid: String = str(data.get("id", "")).strip_edges()
	if not sid.is_empty():
		c.id = sid
	c.audio_path = str(data.get("audio_path", ""))
	c.start_seconds = max(0.0, float(data.get("start", 0.0)))
	c.duration_seconds = max(0.0, float(data.get("duration", 0.0)))
	c.offset_seconds = max(0.0, float(data.get("offset", 0.0)))
	c.volume_db = float(data.get("volume_db", 0.0))
	c.pitch_scale = max(0.01, float(data.get("pitch_scale", 1.0)))
	c.fade_in_seconds = max(0.0, float(data.get("fade_in", 0.0)))
	c.fade_out_seconds = max(0.0, float(data.get("fade_out", 0.0)))
	return c
