@tool
class_name CodaBank
extends RefCounted

## Logical bundle of events from the current project. On export the bank produces a self-contained
## .coda_bank file that the runtime can load without the original .ncoda project.
## The bank stores event IDs only; export resolves them to full event data and the audio resources they reference.

var id: String
var bank_name: String = "Bank"
var event_ids: PackedStringArray = PackedStringArray()


func _init(p_name: String = "Bank") -> void:
	id = _generate_id()
	bank_name = p_name


static func _generate_id() -> String:
	return "bank_%d_%d" % [Time.get_ticks_usec(), randi()]


func add_event_id(event_id: String) -> bool:
	if event_id.is_empty() or event_ids.has(event_id):
		return false
	event_ids.append(event_id)
	return true


func remove_event_id(event_id: String) -> bool:
	for i in range(event_ids.size() - 1, -1, -1):
		if event_ids[i] == event_id:
			event_ids.remove_at(i)
			return true
	return false


func contains_event(event_id: String) -> bool:
	return event_ids.has(event_id)


func clone_keep_id() -> CodaBank:
	var b: CodaBank = CodaBank.new(bank_name)
	b.id = id
	b.event_ids = event_ids.duplicate()
	return b


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"name": bank_name,
		"event_ids": Array(event_ids),
	}


static func from_dictionary(data: Dictionary) -> CodaBank:
	var b: CodaBank = CodaBank.new(str(data.get("name", "Bank")))
	var sid: String = str(data.get("id", "")).strip_edges()
	if not sid.is_empty():
		b.id = sid
	var ids_raw: Variant = data.get("event_ids", [])
	if ids_raw is Array:
		for i in ids_raw:
			b.event_ids.append(str(i))
	return b
