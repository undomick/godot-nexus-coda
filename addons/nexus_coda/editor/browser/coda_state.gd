class_name CodaState
extends RefCounted

const CodaProjectSerializerScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_project_serializer.gd"
)
const CodaEventsStoreScript := preload(
	"res://addons/nexus_coda/editor/browser/stores/coda_events_store.gd"
)
const CodaAssetsStoreScript := preload(
	"res://addons/nexus_coda/editor/browser/stores/coda_assets_store.gd"
)
const CodaMixerStoreScript := preload(
	"res://addons/nexus_coda/editor/browser/stores/coda_mixer_store.gd"
)
const CodaBanksStoreScript := preload(
	"res://addons/nexus_coda/editor/browser/stores/coda_banks_store.gd"
)
const CodaEffectsMutatorScript := preload(
	"res://addons/nexus_coda/editor/browser/stores/coda_effects_mutator.gd"
)

signal structure_changed
## Bus volume/mute/bypass and other non-structural edits; marks unsaved state without forcing full UI rebuilds.
signal project_dirty

var events_root: CodaBrowserNode
var assets_root: CodaBrowserNode
var bus_root: CodaBus
var snapshots: Array[CodaSnapshot] = []
var banks: Array[CodaBank] = []
var game_sync_rules: Array[CodaGameSyncRule] = []

## Project-level appearance metadata; the editor window applies these on load.
## `theme_mode` is "dark" or "light"; `accent_color` overrides the default Coda accent.
var theme_mode: String = "dark"
var accent_color: Color = Color(0.42, 0.74, 1.00, 1.0)

var _events_store: CodaEventsStore
var _assets_store: CodaAssetsStore
var _mixer_store: CodaMixerStore
var _banks_store: CodaBanksStore
var _effects_mutator: CodaEffectsMutator


func _init() -> void:
	_events_store = CodaEventsStoreScript.new(self)
	_assets_store = CodaAssetsStoreScript.new(self, _events_store)
	_mixer_store = CodaMixerStoreScript.new(self)
	_banks_store = CodaBanksStoreScript.new(self)
	_effects_mutator = CodaEffectsMutatorScript.new(self)
	clear_to_empty_project()


func clear_to_empty_project() -> void:
	events_root = CodaBrowserNode.new("Events", CodaBrowserNode.Kind.FOLDER)
	assets_root = CodaBrowserNode.new("Assets", CodaBrowserNode.Kind.FOLDER)
	bus_root = CodaBus.make_default_master()
	snapshots.clear()
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
	structure_changed.emit()


func find_node_anywhere(target_id: String) -> CodaBrowserNode:
	var e: CodaBrowserNode = events_root.find_by_id(target_id)
	if e != null:
		return e
	return assets_root.find_by_id(target_id)


func parent_of(target_id: String) -> CodaBrowserNode:
	var p: CodaBrowserNode = _events_store.events_parent_of(target_id)
	if p != null:
		return p
	return _assets_store.assets_parent_of(target_id)


func events_parent_of(target_id: String) -> CodaBrowserNode:
	return _events_store.events_parent_of(target_id)


func assets_parent_of(target_id: String) -> CodaBrowserNode:
	return _assets_store.assets_parent_of(target_id)


func add_events_folder(parent_id: String, folder_name: String = "New Folder") -> CodaBrowserNode:
	return _events_store.add_events_folder(parent_id, folder_name)


func add_events_event(parent_id: String, event_name: String = "New Event") -> CodaBrowserNode:
	return _events_store.add_events_event(parent_id, event_name)


func duplicate_events_node(node_id: String) -> CodaBrowserNode:
	return _events_store.duplicate_events_node(node_id)


func add_assets_folder(parent_id: String, folder_name: String = "New Folder") -> CodaBrowserNode:
	return _assets_store.add_assets_folder(parent_id, folder_name)


func add_asset_placeholder(parent_id: String, asset_name: String = "New Asset") -> CodaBrowserNode:
	return _assets_store.add_asset_placeholder(parent_id, asset_name)


func resolve_assets_drop_parent_id(target_id: String, section: int) -> String:
	return _assets_store.resolve_assets_drop_parent_id(target_id, section)


func import_assets_from_res_paths(target_folder_id: String, files: Variant) -> void:
	_assets_store.import_assets_from_res_paths(target_folder_id, files)


func set_event_authoring_data(
	event_id: String,
	parameters: Array[CodaEventParameter],
	audio_paths: PackedStringArray
) -> String:
	return _events_store.set_event_authoring_data(event_id, parameters, audio_paths)


func set_event_parameters(event_id: String, parameters: Array[CodaEventParameter]) -> String:
	return _events_store.set_event_parameters(event_id, parameters)


func notify_event_graph_changed(event_id: String) -> String:
	return _events_store.notify_event_graph_changed(event_id)


func set_event_authoring_mode(event_id: String, mode: int) -> String:
	return _events_store.set_event_authoring_mode(event_id, mode)


func notify_event_timeline_changed(event_id: String) -> String:
	return _events_store.notify_event_timeline_changed(event_id)


func set_event_modulations(event_id: String, modulations: Array[CodaModulation]) -> String:
	return _events_store.set_event_modulations(event_id, modulations)


func rename_node(target_id: String, new_name: String) -> bool:
	var node: CodaBrowserNode = find_node_anywhere(target_id)
	if node == null or node == events_root or node == assets_root:
		return false
	node.name = new_name.strip_edges()
	if node.name.is_empty():
		node.name = "Untitled"
	structure_changed.emit()
	return true


func delete_node(target_id: String) -> bool:
	var purge_event_ids: PackedStringArray = PackedStringArray()
	var events_node: CodaBrowserNode = events_root.find_by_id(target_id)
	if events_node != null:
		purge_event_ids = _banks_store.collect_event_ids_in_subtree(events_node)
	if events_root.remove_child_by_id(target_id):
		_banks_store.purge_event_ids_from_banks(purge_event_ids)
		structure_changed.emit()
		return true
	if assets_root.remove_child_by_id(target_id):
		structure_changed.emit()
		return true
	return false


func move_events_drop(moving_id: String, target_id: String, section: int) -> bool:
	return _events_store.move_events_drop(moving_id, target_id, section)


func move_assets_drop(moving_id: String, target_id: String, section: int) -> bool:
	return _assets_store.move_assets_drop(moving_id, target_id, section)


func update_bus_volume(bus_id: String, volume_db: float) -> void:
	_mixer_store.update_bus_volume(bus_id, volume_db)


func update_bus_mute(bus_id: String, mute: bool) -> void:
	_mixer_store.update_bus_mute(bus_id, mute)


func update_bus_solo(bus_id: String, solo: bool) -> void:
	_mixer_store.update_bus_solo(bus_id, solo)


func update_bus_bypass(bus_id: String, bypass: bool) -> void:
	_mixer_store.update_bus_bypass(bus_id, bypass)


func update_bus_send_target(bus_id: String, target_bus_id: String) -> void:
	_mixer_store.update_bus_send_target(bus_id, target_bus_id)


func move_bus_before_in_tree(drag_bus_id: String, before_bus_id: String) -> bool:
	return _mixer_store.move_bus_before_in_tree(drag_bus_id, before_bus_id)


func move_bus_after_in_tree(drag_bus_id: String, after_bus_id: String) -> bool:
	return _mixer_store.move_bus_after_in_tree(drag_bus_id, after_bus_id)


func parent_bus_of(child_bus_id: String) -> CodaBus:
	return _mixer_store.parent_bus_of(child_bus_id)


func add_child_bus(parent_id: String, bus_name: String = "Bus") -> CodaBus:
	return _mixer_store.add_child_bus(parent_id, bus_name)


func remove_bus(bus_id: String) -> bool:
	return _mixer_store.remove_bus(bus_id)


func add_bus_after(after_bus_id: String, bus_name: String = "Bus") -> CodaBus:
	return _mixer_store.add_bus_after(after_bus_id, bus_name)


func duplicate_bus(bus_id: String) -> CodaBus:
	return _mixer_store.duplicate_bus(bus_id)


func reset_bus_volume(bus_id: String) -> void:
	_mixer_store.reset_bus_volume(bus_id)


func rename_bus(bus_id: String, new_name: String) -> bool:
	return _mixer_store.rename_bus(bus_id, new_name)


func add_snapshot(p_name: String = "Snapshot") -> CodaSnapshot:
	return _mixer_store.add_snapshot(p_name)


func remove_snapshot(snapshot_id: String) -> bool:
	return _mixer_store.remove_snapshot(snapshot_id)


func rename_snapshot(snapshot_id: String, new_name: String) -> bool:
	return _mixer_store.rename_snapshot(snapshot_id, new_name)


func find_snapshot_by_id(snapshot_id: String) -> CodaSnapshot:
	return _mixer_store.find_snapshot_by_id(snapshot_id)


func find_snapshot_by_name(p_name: String) -> CodaSnapshot:
	return _mixer_store.find_snapshot_by_name(p_name)


func apply_snapshot(snapshot_id: String) -> bool:
	return _mixer_store.apply_snapshot(snapshot_id)


func add_bank(p_name: String = "Bank") -> CodaBank:
	return _banks_store.add_bank(p_name)


func remove_bank(bank_id: String) -> bool:
	return _banks_store.remove_bank(bank_id)


func rename_bank(bank_id: String, new_name: String) -> bool:
	return _banks_store.rename_bank(bank_id, new_name)


func duplicate_bank(bank_id: String) -> CodaBank:
	return _banks_store.duplicate_bank(bank_id)


func find_bank_by_id(bank_id: String) -> CodaBank:
	return _banks_store.find_bank_by_id(bank_id)


func add_game_sync_rule(rule: CodaGameSyncRule = null) -> CodaGameSyncRule:
	return _banks_store.add_game_sync_rule(rule)


func remove_game_sync_rule(rule_id: String) -> bool:
	return _banks_store.remove_game_sync_rule(rule_id)


func find_game_sync_rule(rule_id: String) -> CodaGameSyncRule:
	return _banks_store.find_game_sync_rule(rule_id)


func banks_containing_event(event_id: String) -> Array[CodaBank]:
	return _banks_store.banks_containing_event(event_id)


func add_event_to_bank(bank_id: String, event_id: String) -> bool:
	return _banks_store.add_event_to_bank(bank_id, event_id)


func remove_event_from_bank(bank_id: String, event_id: String) -> bool:
	return _banks_store.remove_event_from_bank(bank_id, event_id)


func add_track_effect(event_id: String, track_id: String, effect_type: CodaTrackEffect.Type) -> String:
	return _effects_mutator.add(CodaEffectsMutator.Scope.TRACK, event_id, track_id, effect_type)


func remove_track_effect(event_id: String, track_id: String, effect_id: String) -> void:
	_effects_mutator.remove(CodaEffectsMutator.Scope.TRACK, event_id, track_id, effect_id)


func move_track_effect(event_id: String, track_id: String, from_index: int, to_index: int) -> void:
	_effects_mutator.move(CodaEffectsMutator.Scope.TRACK, event_id, track_id, from_index, to_index)


func set_track_effect_params(event_id: String, track_id: String, effect_id: String, params: Dictionary) -> void:
	_effects_mutator.set_params(CodaEffectsMutator.Scope.TRACK, event_id, track_id, effect_id, params)


func set_track_effect_bypass(event_id: String, track_id: String, effect_id: String, on: bool) -> void:
	_effects_mutator.set_bypass(CodaEffectsMutator.Scope.TRACK, event_id, track_id, effect_id, on)


func add_clip_effect(event_id: String, clip_id: String, effect_type: CodaTrackEffect.Type) -> String:
	return _effects_mutator.add(CodaEffectsMutator.Scope.CLIP, event_id, clip_id, effect_type)


func remove_clip_effect(event_id: String, clip_id: String, effect_id: String) -> void:
	_effects_mutator.remove(CodaEffectsMutator.Scope.CLIP, event_id, clip_id, effect_id)


func move_clip_effect(event_id: String, clip_id: String, from_index: int, to_index: int) -> void:
	_effects_mutator.move(CodaEffectsMutator.Scope.CLIP, event_id, clip_id, from_index, to_index)


func set_clip_effect_params(event_id: String, clip_id: String, effect_id: String, params: Dictionary) -> void:
	_effects_mutator.set_params(CodaEffectsMutator.Scope.CLIP, event_id, clip_id, effect_id, params)


func set_clip_effect_bypass(event_id: String, clip_id: String, effect_id: String, on: bool) -> void:
	_effects_mutator.set_bypass(CodaEffectsMutator.Scope.CLIP, event_id, clip_id, effect_id, on)


func add_bus_effect(bus_id: String, effect_type: CodaTrackEffect.Type) -> String:
	return _effects_mutator.add(CodaEffectsMutator.Scope.BUS, "", bus_id, effect_type)


func remove_bus_effect(bus_id: String, effect_id: String) -> void:
	_effects_mutator.remove(CodaEffectsMutator.Scope.BUS, "", bus_id, effect_id)


func move_bus_effect(bus_id: String, from_index: int, to_index: int) -> void:
	_effects_mutator.move(CodaEffectsMutator.Scope.BUS, "", bus_id, from_index, to_index)


func set_bus_effect_params(bus_id: String, effect_id: String, params: Dictionary) -> void:
	_effects_mutator.set_params(CodaEffectsMutator.Scope.BUS, "", bus_id, effect_id, params)


func set_bus_effect_bypass(bus_id: String, effect_id: String, on: bool) -> void:
	_effects_mutator.set_bypass(CodaEffectsMutator.Scope.BUS, "", bus_id, effect_id, on)


func to_dictionary() -> Dictionary:
	return CodaProjectSerializerScript.to_dictionary(self)


func load_from_dictionary(data: Dictionary) -> void:
	CodaProjectSerializerScript.load_from_dictionary(self, data)
