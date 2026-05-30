class_name CodaBanksStore
extends RefCounted

const CodaGameSyncRuleScript := preload("res://addons/nexus_coda/domain/coda_game_sync_rule.gd")

var _state: CodaState


func _init(state: CodaState) -> void:
	_state = state


func collect_event_ids_in_subtree(node: CodaBrowserNode) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if node == null:
		return out
	if node.kind == CodaBrowserNode.Kind.EVENT:
		out.append(node.id)
	for child in node.children:
		for eid in collect_event_ids_in_subtree(child):
			out.append(eid)
	return out


func purge_event_ids_from_banks(event_ids: PackedStringArray) -> void:
	if event_ids.is_empty():
		return
	for b in _state.banks:
		for eid in event_ids:
			b.remove_event_id(eid)


func add_bank(p_name: String = "Bank") -> CodaBank:
	var b: CodaBank = CodaBank.new(p_name)
	_state.banks.append(b)
	_state.structure_changed.emit()
	return b


func remove_bank(bank_id: String) -> bool:
	for i in range(_state.banks.size() - 1, -1, -1):
		if _state.banks[i].id == bank_id:
			_state.banks.remove_at(i)
			_state.structure_changed.emit()
			return true
	return false


func rename_bank(bank_id: String, new_name: String) -> bool:
	for b in _state.banks:
		if b.id == bank_id:
			var trimmed: String = new_name.strip_edges()
			if trimmed.is_empty():
				trimmed = "Bank"
			b.bank_name = trimmed
			_state.structure_changed.emit()
			return true
	return false


func duplicate_bank(bank_id: String) -> CodaBank:
	var src: CodaBank = find_bank_by_id(bank_id)
	if src == null:
		return null
	var dup: CodaBank = CodaBank.new("Copy of %s" % src.bank_name)
	dup.event_ids = src.event_ids.duplicate()
	var idx: int = _state.banks.find(src)
	if idx >= 0:
		_state.banks.insert(idx + 1, dup)
	else:
		_state.banks.append(dup)
	_state.structure_changed.emit()
	return dup


func find_bank_by_id(bank_id: String) -> CodaBank:
	for b in _state.banks:
		if b.id == bank_id:
			return b
	return null


func add_game_sync_rule(rule: CodaGameSyncRule = null) -> CodaGameSyncRule:
	var r: CodaGameSyncRule = rule if rule != null else CodaGameSyncRuleScript.new()
	_state.game_sync_rules.append(r)
	_state.structure_changed.emit()
	return r


func remove_game_sync_rule(rule_id: String) -> bool:
	for i in range(_state.game_sync_rules.size()):
		if _state.game_sync_rules[i].id == rule_id:
			_state.game_sync_rules.remove_at(i)
			_state.structure_changed.emit()
			return true
	return false


func find_game_sync_rule(rule_id: String) -> CodaGameSyncRule:
	for r in _state.game_sync_rules:
		if r.id == rule_id:
			return r
	return null


func banks_containing_event(event_id: String) -> Array[CodaBank]:
	var out: Array[CodaBank] = []
	for b in _state.banks:
		if b.contains_event(event_id):
			out.append(b)
	return out


func add_event_to_bank(bank_id: String, event_id: String) -> bool:
	var b: CodaBank = find_bank_by_id(bank_id)
	if b == null:
		return false
	if not b.add_event_id(event_id):
		return false
	_state.structure_changed.emit()
	return true


func remove_event_from_bank(bank_id: String, event_id: String) -> bool:
	var b: CodaBank = find_bank_by_id(bank_id)
	if b == null:
		return false
	if not b.remove_event_id(event_id):
		return false
	_state.structure_changed.emit()
	return true
