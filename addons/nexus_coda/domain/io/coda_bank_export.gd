@tool
extends RefCounted
class_name CodaBankExport

## Exports a CodaBank to a self-contained .coda_bank file (JSON manifest).
## The runtime can later mount the file to play the bank's events without the original .ncoda.
## Phase 6 MVP keeps audio paths as-is (res:// references). Embedded payloads can be added in
## a future revision without changing the file extension.

const FORMAT_EXTENSION := "coda_bank"
const FORMAT_FILTER := "*.coda_bank ; Nexus Coda Bank"
const SCHEMA_VERSION := 1

const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaProjectIo := preload("res://addons/nexus_coda/domain/io/coda_project_io.gd")
const CodaJsonUtilScript := preload("res://addons/nexus_coda/domain/io/coda_json_util.gd")
const CodaEventResolverScript := preload("res://addons/nexus_coda/runtime/coda_event_resolver.gd")
const NodeData := preload("res://addons/nexus_coda/domain/coda_event_graph_node_data.gd")


## Pre-flight validation. Returns an empty array on success, otherwise human-readable issues.
static func validate_bank(state: CodaState, bank: CodaBank) -> PackedStringArray:
	var problems := PackedStringArray()
	if state == null or bank == null:
		problems.append("Bank or project missing.")
		return problems
	if bank.event_ids.is_empty():
		problems.append('Bank "%s" has no events.' % bank.bank_name)
	var seen_paths: Dictionary = {}
	for event_id in bank.event_ids:
		var event: CodaBrowserNode = state.events_root.find_by_id(event_id)
		if event == null:
			problems.append("Event id %s referenced but missing in project." % event_id)
			continue
		var path: String = CodaEventResolverScript.path_for_event_id(state, event_id)
		if path.is_empty():
			problems.append('Event "%s" has no resolvable path.' % event.name)
		elif seen_paths.has(path):
			problems.append('Duplicate event path "%s" inside bank "%s".' % [path, bank.bank_name])
		else:
			seen_paths[path] = true
		if event.event_graph == null or event.event_graph.nodes.is_empty():
			problems.append('Event "%s" has an empty graph.' % event.name)
		else:
			# Check that every SOUND node references an existing audio resource.
			for n in event.event_graph.nodes:
				if int(n.kind) != NodeData.Kind.SOUND:
					continue
				var audio_path: String = String(n.properties.get("audio_path", "")).strip_edges()
				if audio_path.is_empty():
					problems.append('Event "%s" has a Sound node without audio file.' % event.name)
				elif not ResourceLoader.exists(audio_path):
					problems.append('Audio file missing for event "%s": %s' % [event.name, audio_path])
	return problems


## Serializes the bank to a JSON dictionary. Each event is exported in full so the runtime can
## play it independently of any .ncoda file.
static func build_manifest(state: CodaState, bank: CodaBank) -> Dictionary:
	var events: Array = []
	var audio_paths: Dictionary = {}
	for event_id in bank.event_ids:
		var event: CodaBrowserNode = state.events_root.find_by_id(event_id)
		if event == null:
			continue
		var path: String = CodaEventResolverScript.path_for_event_id(state, event_id)
		var d: Dictionary = event.to_dictionary()
		d["__path"] = path
		events.append(d)
		# Track unique audio refs for asset diagnostics.
		if event.event_graph != null:
			for n in event.event_graph.nodes:
				if int(n.kind) == NodeData.Kind.SOUND:
					var p: String = String(n.properties.get("audio_path", "")).strip_edges()
					if not p.is_empty():
						audio_paths[p] = true
	# Buses are included so the bank knows where to route at load-time. Modulations live on each event.
	var buses: Variant = state.bus_root.to_dictionary() if state.bus_root != null else {}
	return {
		"version": SCHEMA_VERSION,
		"bank_id": bank.id,
		"bank_name": bank.bank_name,
		"events": events,
		"audio_paths": audio_paths.keys(),
		"buses": buses,
	}


## Writes the bank to disk. Returns "" on success, otherwise an English error message.
static func write_to_path(state: CodaState, bank: CodaBank, path: String) -> String:
	if state == null or bank == null:
		return "Internal error: missing project or bank."
	var manifest: Dictionary = build_manifest(state, bank)
	var text: String = CodaJsonUtilScript.stringify(manifest, "  ")
	var abs_path: String = CodaProjectIo.to_physical_path(path)
	if abs_path.is_empty():
		return "Invalid bank path."
	var base_dir: String = abs_path.get_base_dir()
	if not base_dir.is_empty():
		var mk: Error = DirAccess.make_dir_recursive_absolute(base_dir)
		if mk != OK:
			return "Could not create folder (%s)." % error_string(mk)
	var file: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if file == null and path.begins_with("res://"):
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write bank (%s) — path: %s" % [FileAccess.get_open_error(), abs_path]
	file.store_string(text)
	if file.has_method(&"flush"):
		file.flush()
	file.close()
	NexusCodaLog.info("bank_export", 'Wrote bank "%s" → %s' % [bank.bank_name, path])
	return ""


## Reads a bank manifest from disk. Returns Dictionary on success, String on error.
static func read_manifest_from_path(path: String) -> Variant:
	var abs_path: String = CodaProjectIo.to_physical_path(path)
	if abs_path.is_empty():
		return "Invalid path."
	if not FileAccess.file_exists(abs_path):
		return "Bank file not found: %s" % path
	var text: String = FileAccess.get_file_as_string(abs_path)
	if text.is_empty():
		return "Bank file is empty."
	var json := JSON.new()
	if json.parse(text) != OK:
		return "Invalid bank JSON."
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return "Bank root must be a dictionary."
	return data
