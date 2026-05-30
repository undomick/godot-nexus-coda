@tool
class_name CodaTimelineClip
extends RefCounted

## Audio fragment placed on a CodaTimelineTrack.
## `audio_path` is a `res://...` path to a Godot AudioStream; `start_seconds` is the
## clip's start position on the timeline; `duration_seconds` is how long it plays;
## `offset_seconds` skips into the source audio; volume / pitch / fades are local.

const CodaTrackEffectScript := preload("res://addons/nexus_coda/domain/effects/coda_track_effect.gd")

var id: String
var audio_path: String = ""
var start_seconds: float = 0.0
var duration_seconds: float = 0.0
var offset_seconds: float = 0.0
var volume_db: float = 0.0
var pitch_scale: float = 1.0
var fade_in_seconds: float = 0.0
var fade_out_seconds: float = 0.0
## 0 = concave / slow start, 0.5 = linear, 1 = convex / fast start (Audacity-style).
var fade_in_curve: float = 0.5
var fade_out_curve: float = 0.5
## Optional segment key for interactive music on a "Segments" track (Phase: game music).
var segment_id: String = ""
var effects: Array[CodaTrackEffect] = []


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "tcl_%d_%d" % [Time.get_ticks_usec(), randi()]


func end_seconds() -> float:
	return start_seconds + duration_seconds


## Upper bound for `duration_seconds` from the asset (after `offset_seconds`), or very large
## when there is no audio / length is unknown.
func max_source_playable_seconds() -> float:
	if audio_path.is_empty():
		return 1.0e12
	if not ResourceLoader.exists(audio_path):
		return 1.0e12
	var res: Resource = ResourceLoader.load(audio_path)
	if res is AudioStream:
		var stream_len: float = (res as AudioStream).get_length()
		if stream_len > 0.0:
			return maxf(0.05, stream_len - offset_seconds)
	return 1.0e12


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
	c.fade_in_curve = fade_in_curve
	c.fade_out_curve = fade_out_curve
	c.segment_id = segment_id
	for e in effects:
		c.effects.append(e.clone_keep_id())
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
		"fade_in_curve": fade_in_curve,
		"fade_out_curve": fade_out_curve,
		"segment_id": segment_id,
		"effects": effects.map(func(e: CodaTrackEffect) -> Dictionary: return e.to_dictionary()),
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
	c.fade_in_curve = clampf(float(data.get("fade_in_curve", 0.5)), 0.0, 1.0)
	c.fade_out_curve = clampf(float(data.get("fade_out_curve", 0.5)), 0.0, 1.0)
	c.segment_id = str(data.get("segment_id", ""))
	for e_raw in data.get("effects", []) as Array:
		if e_raw is Dictionary:
			c.effects.append(CodaTrackEffectScript.from_dictionary(e_raw))
	return c
