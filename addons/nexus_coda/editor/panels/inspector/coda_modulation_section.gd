@tool
class_name CodaModulationSection
extends VBoxContainer

## Inspector section: list of modulation mappings (parameter → graph node property).
## Drives `event.event_modulations`. Runtime applies these per frame to active voices.

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const SectionHeaderScript := preload("res://addons/nexus_coda/editor/theme/coda_section_header.gd")
const NodeData := preload("res://addons/nexus_coda/domain/coda_event_graph_node_data.gd")
const CodaModulationScript := preload("res://addons/nexus_coda/domain/coda_modulation.gd")

var _project: CodaState = null
var _selected_event: CodaBrowserNode = null
var _draft: Array[CodaModulation] = []

var _header: CodaSectionHeader
var _rows_host: VBoxContainer
var _add_button: Button
var _empty_hint: Label


func _ready() -> void:
	add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_header = SectionHeaderScript.new()
	_header.heading = "Modulation"
	add_child(_header)

	_add_button = Button.new()
	_add_button.text = "+"
	_add_button.tooltip_text = "Add modulation"
	_add_button.pressed.connect(_on_add_pressed)
	_header.add_trailing(_add_button)

	_empty_hint = Label.new()
	_empty_hint.text = "No modulations yet. Connect a parameter to a Sound's volume or pitch."
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	_empty_hint.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	_empty_hint.visible = false
	add_child(_empty_hint)

	_rows_host = VBoxContainer.new()
	_rows_host.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	_rows_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rows_host)


func attach_project(project: CodaState) -> void:
	_project = project


func set_event(event: Variant) -> void:
	var bn := event as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
		_draft.clear()
		_clear_rows()
		_empty_hint.visible = false
		_add_button.disabled = true
		return
	_selected_event = bn
	_add_button.disabled = false
	_load_drafts_from_selection()
	_rebuild_rows()


func _load_drafts_from_selection() -> void:
	_draft.clear()
	if _selected_event == null:
		return
	for m in _selected_event.event_modulations:
		_draft.append(m.clone_keep_id())


func _clear_rows() -> void:
	for c in _rows_host.get_children():
		c.queue_free()


func _rebuild_rows() -> void:
	_clear_rows()
	if _draft.is_empty():
		_empty_hint.visible = _selected_event != null
		return
	_empty_hint.visible = false
	for i in range(_draft.size()):
		_append_row(_draft[i], i)


func _append_row(mod: CodaModulation, index: int) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		&"panel",
		Tokens.make_panel_stylebox(Tokens.SURFACE_RAISED, Tokens.SURFACE_BORDER, Tokens.RADIUS_SM)
	)
	_rows_host.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	card.add_child(col)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	col.add_child(top_row)

	var src_lbl := Label.new()
	src_lbl.text = "From"
	src_lbl.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	src_lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	top_row.add_child(src_lbl)

	var src_picker := OptionButton.new()
	src_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_param_picker(src_picker, mod.source_param_id)
	src_picker.item_selected.connect(_on_source_selected.bind(index, src_picker))
	top_row.add_child(src_picker)

	var remove_btn := Button.new()
	remove_btn.text = "−"
	remove_btn.tooltip_text = "Remove modulation"
	remove_btn.pressed.connect(_on_remove_pressed.bind(index))
	top_row.add_child(remove_btn)

	var mid_row := HBoxContainer.new()
	mid_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	col.add_child(mid_row)

	var dst_lbl := Label.new()
	dst_lbl.text = "To"
	dst_lbl.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	dst_lbl.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	mid_row.add_child(dst_lbl)

	var node_picker := OptionButton.new()
	node_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_target_node_picker(node_picker, mod.target_node_id)
	node_picker.item_selected.connect(_on_target_node_selected.bind(index, node_picker))
	mid_row.add_child(node_picker)

	var prop_picker := OptionButton.new()
	_populate_target_property_picker(prop_picker, mod.target_property)
	prop_picker.item_selected.connect(_on_target_property_selected.bind(index, prop_picker))
	mid_row.add_child(prop_picker)

	var range_row := HBoxContainer.new()
	range_row.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	col.add_child(range_row)

	_make_labeled_spin(range_row, "In Min", mod.range_in_min, _on_in_min_changed.bind(index))
	_make_labeled_spin(range_row, "In Max", mod.range_in_max, _on_in_max_changed.bind(index))
	_make_labeled_spin(range_row, "Out Min", mod.range_out_min, _on_out_min_changed.bind(index))
	_make_labeled_spin(range_row, "Out Max", mod.range_out_max, _on_out_max_changed.bind(index))


func _make_labeled_spin(host: Container, label_text: String, value: float, callback: Callable) -> SpinBox:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override(&"separation", 0)
	host.add_child(v)

	var l := Label.new()
	l.text = label_text
	l.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	l.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	v.add_child(l)

	var s := SpinBox.new()
	s.min_value = -1e6
	s.max_value = 1e6
	s.step = 0.01
	s.value = value
	s.value_changed.connect(callback)
	v.add_child(s)
	return s


func _populate_param_picker(picker: OptionButton, current_id: String) -> void:
	picker.clear()
	if _selected_event == null:
		return
	picker.add_item("(pick parameter)", -1)
	picker.set_item_disabled(0, true)
	var sel_idx: int = 0
	for i in _selected_event.event_parameters.size():
		var p: CodaEventParameter = _selected_event.event_parameters[i]
		picker.add_item(p.param_name, i)
		if p.id == current_id:
			sel_idx = picker.item_count - 1
	picker.select(sel_idx)


func _populate_target_node_picker(picker: OptionButton, current_id: String) -> void:
	picker.clear()
	if _selected_event == null or _selected_event.event_graph == null:
		return
	picker.add_item("(pick node)", -1)
	picker.set_item_disabled(0, true)
	var sel_idx: int = 0
	var nodes: Array = _selected_event.event_graph.nodes
	for i in nodes.size():
		var n: CodaEventGraphNodeData = nodes[i]
		if n.kind == NodeData.Kind.TRIGGER:
			continue
		var label_text: String = "%s (%s)" % [NodeData.display_name_for_kind(n.kind), n.id.right(4)]
		picker.add_item(label_text, i)
		if n.id == current_id:
			sel_idx = picker.item_count - 1
	picker.select(sel_idx)


func _populate_target_property_picker(picker: OptionButton, current: int) -> void:
	picker.clear()
	picker.add_item(CodaModulationScript.display_name_for_target(CodaModulationScript.TargetProperty.SOUND_VOLUME_DB), CodaModulationScript.TargetProperty.SOUND_VOLUME_DB)
	picker.add_item(CodaModulationScript.display_name_for_target(CodaModulationScript.TargetProperty.SOUND_PITCH_SCALE), CodaModulationScript.TargetProperty.SOUND_PITCH_SCALE)
	picker.add_item(CodaModulationScript.display_name_for_target(CodaModulationScript.TargetProperty.SWITCH_SELECTED_BRANCH), CodaModulationScript.TargetProperty.SWITCH_SELECTED_BRANCH)
	picker.add_item(CodaModulationScript.display_name_for_target(CodaModulationScript.TargetProperty.BLEND_MIX), CodaModulationScript.TargetProperty.BLEND_MIX)
	for i in picker.item_count:
		if picker.get_item_id(i) == current:
			picker.select(i)
			return
	picker.select(0)


func _on_source_selected(_idx_unused: int, modulation_index: int, picker: OptionButton) -> void:
	if modulation_index < 0 or modulation_index >= _draft.size():
		return
	var sel: int = picker.get_selected()
	if sel < 0:
		return
	var param_idx: int = picker.get_item_id(sel)
	if param_idx < 0 or _selected_event == null or param_idx >= _selected_event.event_parameters.size():
		return
	_draft[modulation_index].source_param_id = _selected_event.event_parameters[param_idx].id
	_push_changes()


func _on_target_node_selected(_idx_unused: int, modulation_index: int, picker: OptionButton) -> void:
	if modulation_index < 0 or modulation_index >= _draft.size():
		return
	var sel: int = picker.get_selected()
	if sel < 0:
		return
	var node_idx: int = picker.get_item_id(sel)
	if node_idx < 0 or _selected_event == null or _selected_event.event_graph == null:
		return
	if node_idx >= _selected_event.event_graph.nodes.size():
		return
	_draft[modulation_index].target_node_id = (_selected_event.event_graph.nodes[node_idx] as CodaEventGraphNodeData).id
	_push_changes()


func _on_target_property_selected(_idx_unused: int, modulation_index: int, picker: OptionButton) -> void:
	if modulation_index < 0 or modulation_index >= _draft.size():
		return
	var sel: int = picker.get_selected()
	if sel < 0:
		return
	_draft[modulation_index].target_property = picker.get_item_id(sel) as CodaModulationScript.TargetProperty
	_push_changes()


func _on_in_min_changed(v: float, idx: int) -> void:
	if idx >= 0 and idx < _draft.size():
		_draft[idx].range_in_min = v
		_push_changes()


func _on_in_max_changed(v: float, idx: int) -> void:
	if idx >= 0 and idx < _draft.size():
		_draft[idx].range_in_max = v
		_push_changes()


func _on_out_min_changed(v: float, idx: int) -> void:
	if idx >= 0 and idx < _draft.size():
		_draft[idx].range_out_min = v
		_push_changes()


func _on_out_max_changed(v: float, idx: int) -> void:
	if idx >= 0 and idx < _draft.size():
		_draft[idx].range_out_max = v
		_push_changes()


func _on_remove_pressed(idx: int) -> void:
	if idx >= 0 and idx < _draft.size():
		_draft.remove_at(idx)
		_rebuild_rows()
		_push_changes()


func _on_add_pressed() -> void:
	if _selected_event == null:
		return
	var m := CodaModulationScript.new()
	if not _selected_event.event_parameters.is_empty():
		m.source_param_id = _selected_event.event_parameters[0].id
	# Provide a friendly default for SOUND volume in dB.
	m.range_in_min = 0.0
	m.range_in_max = 1.0
	m.range_out_min = -24.0
	m.range_out_max = 0.0
	_draft.append(m)
	_rebuild_rows()
	_push_changes()


func _push_changes() -> void:
	if _project == null or _selected_event == null:
		return
	var err: String = _project.set_event_modulations(_selected_event.id, _draft)
	if not err.is_empty():
		NexusCodaLog.warn("modulation_section", err)
	_load_drafts_from_selection()
