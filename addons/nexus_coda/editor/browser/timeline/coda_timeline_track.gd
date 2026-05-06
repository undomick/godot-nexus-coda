@tool
class_name CodaTimelineTrack
extends RefCounted

## A single track on a CodaEventTimeline. Tracks live conceptually inside an event;
## `output_bus_id` references a `CodaBus.id` from the project (empty = inherit event-level bus).

const CodaTimelineClipScript := preload(
	"res://addons/nexus_coda/editor/browser/timeline/coda_timeline_clip.gd"
)

var id: String
var track_name: String = "Track"
var mute: bool = false
var solo: bool = false
var volume_db: float = 0.0
var output_bus_id: String = ""
var clips: Array[CodaTimelineClip] = []


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "ttr_%d_%d" % [Time.get_ticks_usec(), randi()]


func clone_keep_id() -> CodaTimelineTrack:
	var t := CodaTimelineTrack.new()
	t.id = id
	t.track_name = track_name
	t.mute = mute
	t.solo = solo
	t.volume_db = volume_db
	t.output_bus_id = output_bus_id
	for c in clips:
		t.clips.append(c.clone_keep_id())
	return t


func find_clip(clip_id: String) -> CodaTimelineClip:
	for c in clips:
		if c.id == clip_id:
			return c
	return null


func remove_clip(clip_id: String) -> bool:
	for i in range(clips.size()):
		if clips[i].id == clip_id:
			clips.remove_at(i)
			return true
	return false


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": track_name,
		"mute": mute,
		"solo": solo,
		"volume_db": volume_db,
		"output_bus_id": output_bus_id,
		"clips": clips.map(func(c: CodaTimelineClip) -> Dictionary: return c.to_dictionary()),
	}


static func from_dictionary(data: Dictionary) -> CodaTimelineTrack:
	var t := CodaTimelineTrack.new()
	var sid: String = str(data.get("id", "")).strip_edges()
	if not sid.is_empty():
		t.id = sid
	t.track_name = str(data.get("name", "Track"))
	t.mute = bool(data.get("mute", false))
	t.solo = bool(data.get("solo", false))
	t.volume_db = float(data.get("volume_db", 0.0))
	t.output_bus_id = str(data.get("output_bus_id", ""))
	for c_raw in data.get("clips", []) as Array:
		if c_raw is Dictionary:
			t.clips.append(CodaTimelineClipScript.from_dictionary(c_raw))
	return t
