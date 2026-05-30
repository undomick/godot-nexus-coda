class_name CodaState
extends CodaProject

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

var _events_store: CodaEventsStore
var _assets_store: CodaAssetsStore
var _mixer_store: CodaMixerStore
var _banks_store: CodaBanksStore
var _effects_mutator: CodaEffectsMutator


func _init() -> void:
	super._init()
	_banks_store = CodaBanksStoreScript.new(self)
	_events_store = CodaEventsStoreScript.new(self, _banks_store)
	_assets_store = CodaAssetsStoreScript.new(self)
	_mixer_store = CodaMixerStoreScript.new(self)
	_effects_mutator = CodaEffectsMutatorScript.new(self)


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


func set_event_properties(event_id: String, properties: Array[CodaEventProperty]) -> String:
	return _events_store.set_event_properties(event_id, properties)


func set_event_tags(event_id: String, tags: PackedStringArray) -> String:
	return _events_store.set_event_tags(event_id, tags)


func set_event_notes(event_id: String, notes: String) -> String:
	return _events_store.set_event_notes(event_id, notes)


func notify_event_graph_changed(event_id: String) -> String:
	return _events_store.notify_event_graph_changed(event_id)


func set_event_authoring_mode(event_id: String, mode: int) -> String:
	return _events_store.set_event_authoring_mode(event_id, mode)


func notify_event_timeline_changed(event_id: String) -> String:
	return _events_store.notify_event_timeline_changed(event_id)


func set_event_modulations(event_id: String, modulations: Array[CodaModulation]) -> String:
	return _events_store.set_event_modulations(event_id, modulations)


func rename_node(target_id: String, new_name: String) -> bool:
	var err: String = _events_store.rename_events_node(target_id, new_name)
	if err.is_empty():
		return true
	if err != "Event not found.":
		return false
	err = _assets_store.rename_assets_node(target_id, new_name)
	return err.is_empty()


func delete_node(target_id: String) -> bool:
	var err: String = _events_store.delete_events_node(target_id)
	if err.is_empty():
		return true
	if err != "Event not found.":
		return false
	err = _assets_store.delete_assets_node(target_id)
	return err.is_empty()


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


func update_wet_send_level(bus_id: String, send_id: String, level: float) -> void:
	_mixer_store.update_wet_send_level(bus_id, send_id, level)


func add_wet_send(source_bus_id: String, return_bus_id: String, level: float = 0.0) -> CodaBusSend:
	return _mixer_store.add_wet_send(source_bus_id, return_bus_id, level)


func add_return_bus(parent_id: String, bus_name: String = "Reverb Return") -> CodaBus:
	return _mixer_store.add_return_bus(parent_id, bus_name)


func add_vca(p_name: String = "VCA") -> CodaVca:
	return _mixer_store.add_vca(p_name)


func update_vca_volume(vca_id: String, volume_db: float) -> void:
	_mixer_store.update_vca_volume(vca_id, volume_db)


func set_vca_controls_bus(vca_id: String, bus_id: String, enabled: bool) -> void:
	_mixer_store.set_vca_controls_bus(vca_id, bus_id, enabled)


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
