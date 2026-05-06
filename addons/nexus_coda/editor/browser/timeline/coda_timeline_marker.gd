@tool
class_name CodaTimelineMarker
extends RefCounted

## Named point on a CodaEventTimeline. Markers are visual hints (cues, transitions)
## and may later drive runtime jumps; for the MVP they are pure metadata.

enum Kind { GENERIC = 0, TRANSITION = 1, CUE = 2 }

var id: String
var marker_name: String = "Marker"
var time_seconds: float = 0.0
var kind: Kind = Kind.GENERIC


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "tmk_%d_%d" % [Time.get_ticks_usec(), randi()]


func clone_keep_id() -> CodaTimelineMarker:
	var m := CodaTimelineMarker.new()
	m.id = id
	m.marker_name = marker_name
	m.time_seconds = time_seconds
	m.kind = kind
	return m


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": marker_name,
		"time": time_seconds,
		"kind": int(kind),
	}


static func from_dictionary(data: Dictionary) -> CodaTimelineMarker:
	var m := CodaTimelineMarker.new()
	var sid: String = str(data.get("id", "")).strip_edges()
	if not sid.is_empty():
		m.id = sid
	m.marker_name = str(data.get("name", "Marker"))
	m.time_seconds = max(0.0, float(data.get("time", 0.0)))
	var k: int = int(data.get("kind", 0))
	match k:
		Kind.GENERIC, Kind.TRANSITION, Kind.CUE:
			m.kind = k as Kind
		_:
			m.kind = Kind.GENERIC
	return m
