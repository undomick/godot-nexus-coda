class_name CodaProject
extends RefCounted

## Domain project root: serializable data and lookups without editor mutation stores.

const CodaProjectSerializerScript := preload(
	"res://addons/nexus_coda/domain/coda_project_serializer.gd"
)
const CodaProjectIndexScript := preload(
	"res://addons/nexus_coda/domain/coda_project_index.gd"
)
const CodaBusSendScript := preload("res://addons/nexus_coda/domain/coda_bus_send.gd")

signal structure_changed
signal project_dirty
## Emitted when an event's Set Parameters list changes (add/remove/rename/type/default).
signal event_parameters_changed(event_id: String)

var events_root: CodaBrowserNode
var assets_root: CodaBrowserNode
var bus_root: CodaBus
var snapshots: Array[CodaSnapshot] = []
var vcas: Array[CodaVca] = []
var banks: Array[CodaBank] = []
var game_sync_rules: Array[CodaGameSyncRule] = []

var theme_mode: String = "dark"
var accent_color: Color = Color(0.42, 0.74, 1.00, 1.0)

var _project_index: CodaProjectIndex


func _init() -> void:
	_project_index = CodaProjectIndexScript.new()
	_project_index.bind_project(self)
	clear_to_empty_project()


func clear_to_empty_project() -> void:
	events_root = CodaBrowserNode.new("Events", CodaBrowserNode.Kind.FOLDER)
	assets_root = CodaBrowserNode.new("Assets", CodaBrowserNode.Kind.FOLDER)
	bus_root = CodaBus.make_default_master()
	snapshots.clear()
	vcas.clear()
	banks.clear()
	game_sync_rules.clear()
	theme_mode = "dark"
	accent_color = Color(0.42, 0.74, 1.00, 1.0)
	structure_changed.emit()


func set_theme_appearance(p_theme_mode: String, p_accent_color: Color) -> void:
	var normalized: String = p_theme_mode.strip_edges().to_lower()
	if normalized != "light" and normalized != "dark":
		normalized = "dark"
	theme_mode = normalized
	accent_color = p_accent_color
	project_dirty.emit()


func find_node_anywhere(target_id: String) -> CodaBrowserNode:
	var indexed: CodaBrowserNode = _project_index.find_node_anywhere(target_id)
	if indexed != null:
		return indexed
	return null


func find_clip_anywhere(clip_id: String) -> Dictionary:
	return _project_index.find_clip(clip_id)


func find_snapshot_by_id(snapshot_id: String) -> CodaSnapshot:
	for s in snapshots:
		if s.id == snapshot_id:
			return s
	return null


func find_snapshot_by_name(p_name: String) -> CodaSnapshot:
	var trimmed: String = p_name.strip_edges()
	for s in snapshots:
		if s.snapshot_name == trimmed:
			return s
	return null


func find_vca_by_id(vca_id: String) -> CodaVca:
	for v in vcas:
		if v.id == vca_id:
			return v
	return null


func apply_snapshot(snapshot_id: String) -> bool:
	var s: CodaSnapshot = find_snapshot_by_id(snapshot_id)
	if s == null:
		return false
	for bus_id in s.bus_overrides.keys():
		var b: CodaBus = bus_root.find_by_id(bus_id)
		if b == null:
			continue
		var entry: Dictionary = s.bus_overrides[bus_id]
		b.volume_db = float(entry.get("volume_db", b.volume_db))
		b.mute = bool(entry.get("mute", b.mute))
		b.solo = bool(entry.get("solo", b.solo))
		b.bypass = bool(entry.get("bypass", b.bypass))
		b.send_target_id = str(entry.get("send_target_id", b.send_target_id))
		_apply_snapshot_wet_sends(b, entry)
	project_dirty.emit()
	return true


func _apply_snapshot_wet_sends(bus: CodaBus, entry: Dictionary) -> void:
	var raw: Variant = entry.get("wet_sends", null)
	if raw == null:
		return
	if raw is Array:
		bus.wet_sends = CodaBusSendScript.sends_from_array(raw)
	elif raw is Dictionary:
		for send_id in raw.keys():
			var send: CodaBusSend = bus.find_wet_send_by_id(str(send_id))
			if send == null:
				continue
			var ov: Dictionary = raw[send_id] as Dictionary
			send.level = clampf(float(ov.get("level", send.level)), 0.0, 1.0)


## Break RefCounted cycles (project <-> index, stores) so editor shutdown can drop the graph.
func release_owned_references() -> void:
	if _project_index != null:
		_project_index.unbind_project()
		_project_index = null
	events_root = null
	assets_root = null
	bus_root = null
	snapshots.clear()
	vcas.clear()
	banks.clear()
	game_sync_rules.clear()


## Immutable playback copy; editor preview runtime must not share live authoring state.
func duplicate_for_playback() -> CodaProject:
	var copy := CodaProject.new()
	CodaProjectSerializerScript.load_from_dictionary(
		copy, CodaProjectSerializerScript.to_dictionary(self)
	)
	_copy_event_work_areas(events_root, copy.events_root)
	return copy


func _copy_event_work_areas(src_root: CodaBrowserNode, dst_root: CodaBrowserNode) -> void:
	if src_root == null or dst_root == null:
		return
	if (
		src_root.kind == CodaBrowserNode.Kind.EVENT
		and dst_root.kind == CodaBrowserNode.Kind.EVENT
	):
		var src_tl: CodaEventTimeline = src_root.event_timeline
		var dst_tl: CodaEventTimeline = dst_root.event_timeline
		if src_tl != null and dst_tl != null:
			const Transport := preload("res://addons/nexus_coda/domain/coda_timeline_transport.gd")
			Transport.copy_preview_transport(src_tl, dst_tl)
	for src_child in src_root.children:
		var dst_child: CodaBrowserNode = dst_root.find_by_id(src_child.id)
		if dst_child != null:
			_copy_event_work_areas(src_child, dst_child)


func to_dictionary() -> Dictionary:
	return CodaProjectSerializerScript.to_dictionary(self)


func load_from_dictionary(data: Dictionary) -> void:
	CodaProjectSerializerScript.load_from_dictionary(self, data)
