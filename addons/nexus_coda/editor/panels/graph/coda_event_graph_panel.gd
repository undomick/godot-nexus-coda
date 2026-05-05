@tool
class_name CodaEventGraphPanel
extends VBoxContainer

## Central authoring view: visual node-graph for the selected event.
## Listens to browser selection, mirrors the selected event's CodaEventGraph into a Godot GraphEdit,
## and pushes mutations back to the project (selection emits structure_changed for the dirty marker).

const Tokens := preload("res://addons/nexus_coda/editor/theme/coda_design_tokens.gd")
const NexusCodaLog := preload("res://addons/nexus_coda/editor/nexus_coda_log.gd")
const CodaEmptyStateScript := preload("res://addons/nexus_coda/editor/theme/coda_empty_state.gd")
const NodeData := preload("res://addons/nexus_coda/editor/browser/coda_event_graph_node_data.gd")
const CodaGraphNodeViewScript := preload(
	"res://addons/nexus_coda/editor/panels/graph/coda_graph_node_view.gd"
)
const CodaEventGraphScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_event_graph.gd"
)
const CodaGraphSchedulerScript := preload(
	"res://addons/nexus_coda/runtime/coda_graph_scheduler.gd"
)

signal graph_node_selected(graph_node_id: String)

const AUDIO_TYPE := 0

var _empty_state: CodaEmptyState
var _content: HBoxContainer
var _palette: VBoxContainer
var _graph_edit: GraphEdit
var _selection_label: Label

var _selected_event: CodaBrowserNode = null
var _project: CodaState = null
var _runtime: CodaRuntime = null
var _node_views: Dictionary = {}  ## node_id (String) -> CodaGraphNodeView


func _ready() -> void:
	name = "Graph"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 0)

	_empty_state = CodaEmptyStateScript.new()
	_empty_state.title_text = "No event selected"
	_empty_state.body_text = "Select an event in the Browser, or create a new one to start designing its graph."
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_empty_state)

	_content = HBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override(&"separation", 0)
	_content.visible = false
	add_child(_content)

	_palette = _build_palette()
	_content.add_child(_palette)

	var graph_holder := VBoxContainer.new()
	graph_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_holder.add_theme_constant_override(&"separation", 0)
	_content.add_child(graph_holder)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", Tokens.SPACING_SM)
	graph_holder.add_child(header)

	var selection_caption := Label.new()
	selection_caption.text = "Event:"
	selection_caption.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	selection_caption.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	header.add_child(selection_caption)

	_selection_label = Label.new()
	_selection_label.text = "—"
	_selection_label.add_theme_color_override(&"font_color", Tokens.TEXT_PRIMARY)
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_selection_label)

	var preview_btn := Button.new()
	preview_btn.text = "Preview Event"
	preview_btn.tooltip_text = "Audition the full event graph"
	preview_btn.pressed.connect(_on_preview_event_pressed)
	header.add_child(preview_btn)

	_graph_edit = GraphEdit.new()
	_graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_edit.right_disconnects = true
	_graph_edit.show_arrange_button = true
	_graph_edit.minimap_enabled = true
	_graph_edit.minimap_size = Vector2(160, 80)
	_graph_edit.add_valid_connection_type(AUDIO_TYPE, AUDIO_TYPE)
	_graph_edit.connection_request.connect(_on_connection_request)
	_graph_edit.disconnection_request.connect(_on_disconnection_request)
	_graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph_edit.node_selected.connect(_on_graph_node_selected_view)
	_graph_edit.node_deselected.connect(_on_graph_node_deselected_view)
	_graph_edit.popup_request.connect(_on_popup_request)
	graph_holder.add_child(_graph_edit)


func _build_palette() -> VBoxContainer:
	var pal := VBoxContainer.new()
	pal.custom_minimum_size = Vector2(180, 0)
	pal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pal.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override(&"margin_left", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_top", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_right", Tokens.SPACING_SM)
	margin.add_theme_constant_override(&"margin_bottom", Tokens.SPACING_SM)
	pal.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override(&"separation", Tokens.SPACING_XS)
	margin.add_child(inner)

	var hdr := Label.new()
	hdr.text = "Add Node"
	hdr.add_theme_color_override(&"font_color", Tokens.TEXT_SECONDARY)
	hdr.add_theme_font_size_override(&"font_size", Tokens.FONT_HEADING_SIZE)
	inner.add_child(hdr)

	_add_palette_button(inner, "Sequence", NodeData.Kind.SEQUENCE,
		"Plays children in the order they are connected")
	_add_palette_button(inner, "Random", NodeData.Kind.RANDOM,
		"Picks one connected child at random")
	_add_palette_button(inner, "Sound", NodeData.Kind.SOUND,
		"Plays a single audio file")

	var sep := HSeparator.new()
	inner.add_child(sep)

	var hint := Label.new()
	hint.text = "Right-click the canvas for the same options."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override(&"font_color", Tokens.TEXT_MUTED)
	hint.add_theme_font_size_override(&"font_size", Tokens.FONT_LABEL_SIZE)
	inner.add_child(hint)

	return pal


func _add_palette_button(host: Container, label_text: String, kind: int, tip: String) -> void:
	var b := Button.new()
	b.text = "+ %s" % label_text
	b.tooltip_text = tip
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(_on_palette_add.bind(kind))
	host.add_child(b)


func attach_project(project: CodaState) -> void:
	_project = project


func attach_runtime(runtime: CodaRuntime) -> void:
	_runtime = runtime


func on_browser_event_selected(node: Variant) -> void:
	var bn := node as CodaBrowserNode
	if bn == null or bn.kind != CodaBrowserNode.Kind.EVENT:
		_selected_event = null
		_show_empty()
		return
	_selected_event = bn
	if _selected_event.event_graph == null:
		_selected_event.event_graph = CodaEventGraphScript.new()
	_selected_event.event_graph.ensure_trigger_node()
	_selection_label.text = bn.name
	_show_graph()
	_rebuild_graph_view()


func _show_empty() -> void:
	if _empty_state != null:
		_empty_state.visible = true
	if _content != null:
		_content.visible = false


func _show_graph() -> void:
	if _empty_state != null:
		_empty_state.visible = false
	if _content != null:
		_content.visible = true


func _rebuild_graph_view() -> void:
	if _graph_edit == null or _selected_event == null:
		return
	# Disconnect all visual connections and free node views.
	_graph_edit.clear_connections()
	for view in _node_views.values():
		var v: GraphNode = view as GraphNode
		if v != null and v.get_parent() == _graph_edit:
			_graph_edit.remove_child(v)
			v.queue_free()
	_node_views.clear()

	var graph: CodaEventGraph = _selected_event.event_graph
	for node_data in graph.nodes:
		_create_graph_node_view(node_data)
	for edge in graph.edges:
		var from_view: CodaGraphNodeView = _node_views.get(edge.from_node_id, null)
		var to_view: CodaGraphNodeView = _node_views.get(edge.to_node_id, null)
		if from_view == null or to_view == null:
			continue
		_graph_edit.connect_node(from_view.name, edge.from_port, to_view.name, edge.to_port)


func _create_graph_node_view(data: CodaEventGraphNodeData) -> CodaGraphNodeView:
	var view := CodaGraphNodeViewScript.new()
	view.name = "n_%s" % data.id.replace("-", "_")
	_graph_edit.add_child(view)
	view.bind(data)
	view.position_offset_changed.connect(_on_node_position_changed.bind(data.id))
	view.property_changed.connect(_on_node_property_changed)
	view.browse_audio_requested.connect(_on_browse_audio)
	view.preview_sound_requested.connect(_on_preview_sound)
	_node_views[data.id] = view
	return view


func _find_view_by_graph_node_name(graph_node_name: StringName) -> CodaGraphNodeView:
	for v in _node_views.values():
		var view: CodaGraphNodeView = v as CodaGraphNodeView
		if view != null and view.name == graph_node_name:
			return view
	return null


func _on_connection_request(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	if _selected_event == null:
		return
	var from_view: CodaGraphNodeView = _find_view_by_graph_node_name(from_node)
	var to_view: CodaGraphNodeView = _find_view_by_graph_node_name(to_node)
	if from_view == null or to_view == null:
		return
	var graph: CodaEventGraph = _selected_event.event_graph
	if not graph.add_edge(from_view.get_model_node_id(), to_view.get_model_node_id(), from_port, to_port):
		NexusCodaLog.warn("graph_panel", "connection rejected (cycle or invalid kinds)")
		return
	_graph_edit.connect_node(from_node, from_port, to_node, to_port)
	_notify_graph_changed()


func _on_disconnection_request(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	if _selected_event == null:
		return
	var from_view: CodaGraphNodeView = _find_view_by_graph_node_name(from_node)
	var to_view: CodaGraphNodeView = _find_view_by_graph_node_name(to_node)
	if from_view == null or to_view == null:
		return
	var graph: CodaEventGraph = _selected_event.event_graph
	graph.remove_edge(from_view.get_model_node_id(), to_view.get_model_node_id(), from_port, to_port)
	_graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	_notify_graph_changed()


func _on_delete_nodes_request(graph_node_names: Array) -> void:
	if _selected_event == null:
		return
	var graph: CodaEventGraph = _selected_event.event_graph
	var any_changed: bool = false
	for n in graph_node_names:
		var view: CodaGraphNodeView = _find_view_by_graph_node_name(StringName(n))
		if view == null:
			continue
		var data_id: String = view.get_model_node_id()
		var data: CodaEventGraphNodeData = graph.find_node(data_id)
		if data != null and data.kind == NodeData.Kind.TRIGGER:
			# Trigger is mandatory; never delete.
			NexusCodaLog.warn("graph_panel", "Trigger node cannot be deleted")
			continue
		if graph.remove_node(data_id):
			any_changed = true
	if any_changed:
		_rebuild_graph_view()
		_notify_graph_changed()


func _on_node_position_changed(model_node_id: String) -> void:
	if _selected_event == null:
		return
	var view: CodaGraphNodeView = _node_views.get(model_node_id, null)
	if view == null:
		return
	var graph: CodaEventGraph = _selected_event.event_graph
	var data: CodaEventGraphNodeData = graph.find_node(model_node_id)
	if data == null:
		return
	data.graph_position = view.position_offset
	# Position changes don't need full structure_changed (would re-render whole tree); save will pick it up.


func _on_node_property_changed(model_node_id: String, key: String, value: Variant) -> void:
	if _selected_event == null:
		return
	var graph: CodaEventGraph = _selected_event.event_graph
	var data: CodaEventGraphNodeData = graph.find_node(model_node_id)
	if data == null:
		return
	data.properties[key] = value
	_notify_graph_changed()


func _on_graph_node_selected_view(view: Node) -> void:
	if not (view is CodaGraphNodeView):
		return
	graph_node_selected.emit((view as CodaGraphNodeView).get_model_node_id())


func _on_graph_node_deselected_view(_view: Node) -> void:
	graph_node_selected.emit("")


func _on_popup_request(at_position: Vector2) -> void:
	if _selected_event == null:
		return
	var menu := PopupMenu.new()
	menu.add_item("Add Sequence", NodeData.Kind.SEQUENCE)
	menu.add_item("Add Random", NodeData.Kind.RANDOM)
	menu.add_item("Add Sound", NodeData.Kind.SOUND)
	menu.id_pressed.connect(_on_popup_picked.bind(at_position))
	add_child(menu)
	menu.popup_on_parent(Rect2(at_position, Vector2.ZERO))


func _on_popup_picked(kind_id: int, at_position: Vector2) -> void:
	_create_node_at(kind_id, _viewport_to_graph(at_position))


func _viewport_to_graph(at_position: Vector2) -> Vector2:
	if _graph_edit == null:
		return at_position
	var local: Vector2 = _graph_edit.get_local_mouse_position()
	return (local + _graph_edit.scroll_offset) / _graph_edit.zoom


func _on_palette_add(kind_id: int) -> void:
	# Place new nodes near the visible center of the canvas.
	var fallback: Vector2 = Vector2(200, 120)
	if _graph_edit != null:
		fallback = (_graph_edit.size * 0.5 + _graph_edit.scroll_offset) / _graph_edit.zoom
	_create_node_at(kind_id, fallback)


func _create_node_at(kind_id: int, at_pos: Vector2) -> void:
	if _selected_event == null or _selected_event.event_graph == null:
		return
	var kind: NodeData.Kind = NodeData.Kind.SOUND
	match kind_id:
		NodeData.Kind.SEQUENCE, NodeData.Kind.RANDOM, NodeData.Kind.SOUND, NodeData.Kind.SWITCH, NodeData.Kind.BLEND:
			kind = kind_id as NodeData.Kind
		_:
			NexusCodaLog.warn("graph_panel", "unknown kind id %d" % kind_id)
			return
	var data: CodaEventGraphNodeData = NodeData.new(kind)
	data.graph_position = at_pos
	_selected_event.event_graph.add_node(data)
	_create_graph_node_view(data)
	_notify_graph_changed()


func _notify_graph_changed() -> void:
	if _project == null or _selected_event == null:
		return
	_project.notify_event_graph_changed(_selected_event.id)


func _on_browse_audio(model_node_id: String) -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.title = "Pick Audio Resource"
	fd.add_filter("*.wav, *.ogg, *.mp3, *.flac, *.webm", "Audio")
	fd.use_native_dialog = false
	add_child(fd)
	fd.file_selected.connect(_on_browse_audio_picked.bind(model_node_id))
	fd.canceled.connect(fd.queue_free)
	fd.confirmed.connect(fd.queue_free)
	fd.popup_centered_ratio(0.6)


func _on_browse_audio_picked(picked_path: String, model_node_id: String) -> void:
	if _selected_event == null:
		return
	var graph: CodaEventGraph = _selected_event.event_graph
	var data: CodaEventGraphNodeData = graph.find_node(model_node_id)
	if data == null or data.kind != NodeData.Kind.SOUND:
		return
	data.properties["audio_path"] = picked_path
	var view: CodaGraphNodeView = _node_views.get(model_node_id, null)
	if view != null:
		view.refresh_from_data()
	_notify_graph_changed()


func _on_preview_sound(model_node_id: String) -> void:
	if _runtime == null or _selected_event == null:
		return
	var data: CodaEventGraphNodeData = _selected_event.event_graph.find_node(model_node_id)
	if data == null or data.kind != NodeData.Kind.SOUND:
		return
	var path: String = String(data.properties.get("audio_path", "")).strip_edges()
	if path.is_empty():
		NexusCodaLog.warn("graph_panel", "Cannot preview: sound has no audio file")
		return
	# Direct one-shot play through the editor runtime, bypassing the graph for accurate isolation.
	_runtime.stop_all()
	if not ResourceLoader.exists(path):
		NexusCodaLog.warn("graph_panel", "audio resource missing: %s" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		NexusCodaLog.warn("graph_panel", "audio resource not an AudioStream: %s" % path)
		return
	var preview := AudioStreamPlayer.new()
	preview.stream = stream
	preview.bus = "Master"
	preview.volume_db = float(data.properties.get("volume_db", 0.0))
	preview.pitch_scale = float(data.properties.get("pitch_scale", 1.0))
	add_child(preview)
	preview.finished.connect(preview.queue_free)
	preview.play()


func _selected_event_has_preview_audio() -> bool:
	if _selected_event == null:
		return false
	var plan_entries: Array = []
	if _selected_event.event_graph != null:
		plan_entries = CodaGraphSchedulerScript.plan(_selected_event.event_graph, {})
	if not plan_entries.is_empty():
		return true
	return _selected_event.event_audio_paths.size() > 0


func _on_preview_event_pressed() -> void:
	if _runtime == null or _selected_event == null:
		return
	if not _selected_event_has_preview_audio():
		NexusCodaLog.warn("graph_panel", "Nothing to preview: add sounds to the graph or legacy audio on the event.")
		return
	_runtime.stop_all()
	_runtime.play_event_node(_selected_event)
