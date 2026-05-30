extends RefCounted

## Tests for event tags, notes, set-parameters migration, get-properties, bank strip, and runtime API.

const CodaBrowserNodeScript := preload("res://addons/nexus_coda/domain/coda_browser_node.gd")
const CodaBankExportScript := preload("res://addons/nexus_coda/domain/io/coda_bank_export.gd")
const CodaStateScript := preload("res://addons/nexus_coda/editor/browser/coda_state.gd")
const CodaBrowserTreeModelScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_tree_model.gd"
)
const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaEventHandleScript := preload("res://addons/nexus_coda/runtime/coda_event_handle.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_legacy_event_parameters_migration()
	failed += _test_metadata_roundtrip()
	failed += _test_bank_strips_editor_fields()
	failed += _test_tag_filter()
	failed += _test_get_property_for_path()
	return failed


static func _test_legacy_event_parameters_migration() -> int:
	var legacy: Dictionary = {
		"id": "ev1",
		"name": "Legacy",
		"kind": CodaBrowserNode.Kind.EVENT,
		"event_parameters": [{"id": "p1", "name": "Intensity", "param_type": 0, "default": 0.5}],
		"children": [],
	}
	var node: CodaBrowserNode = CodaBrowserNodeScript.from_dictionary(legacy)
	if node.event_parameters.size() != 1:
		push_error("legacy event_parameters should load into event_parameters array")
		return 1
	if String(node.event_parameters[0].param_name) != "Intensity":
		push_error("legacy parameter name mismatch")
		return 1
	var saved: Dictionary = node.to_dictionary()
	if not saved.has("event_set_parameters"):
		push_error("save should use event_set_parameters key")
		return 1
	if saved.has("event_parameters"):
		push_error("save should not write legacy event_parameters key")
		return 1
	return 0


static func _test_metadata_roundtrip() -> int:
	var ev := CodaBrowserNodeScript.new("Meta", CodaBrowserNode.Kind.EVENT)
	ev.event_tags = PackedStringArray(["UI", "#combat"])
	ev.event_notes = "Boss intro sting"
	var prop := CodaEventProperty.new()
	prop.property_key = "DamageRadius"
	prop.value_type = CodaEventProperty.ValueType.FLOAT
	prop.default_value = 12.5
	ev.event_properties.append(prop)
	var data: Dictionary = ev.to_dictionary()
	var copy: CodaBrowserNode = CodaBrowserNodeScript.from_dictionary(data)
	if copy.event_tags.size() != 2:
		push_error("tags roundtrip size")
		return 1
	if copy.event_tags[0] != "ui" or copy.event_tags[1] != "combat":
		push_error("tags should normalize on load")
		return 1
	if copy.event_notes != "Boss intro sting":
		push_error("notes roundtrip")
		return 1
	if copy.event_properties.size() != 1:
		push_error("properties roundtrip size")
		return 1
	if float(copy.event_properties[0].default_value) != 12.5:
		push_error("property default roundtrip")
		return 1
	return 0


static func _test_bank_strips_editor_fields() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev: CodaBrowserNode = state.add_events_event(state.events_root.id, "BankEv")
	if ev == null:
		push_error("bank strip setup failed")
		return 1
	ev.event_tags = PackedStringArray(["ui"])
	ev.event_notes = "secret note"
	var prop := CodaEventProperty.new()
	prop.property_key = "SubtitleID"
	prop.value_type = CodaEventProperty.ValueType.STRING
	prop.default_value = "boom"
	ev.event_properties.append(prop)
	var bank: CodaBank = state.add_bank("TestBank")
	state.add_event_to_bank(bank.id, ev.id)
	var manifest: Dictionary = CodaBankExportScript.build_manifest(state, bank)
	var events: Array = manifest.get("events", [])
	if events.is_empty():
		push_error("bank manifest missing events")
		return 1
	var ed: Dictionary = events[0]
	if ed.has("event_tags") or ed.has("event_notes"):
		push_error("bank export should strip editor-only tags/notes")
		return 1
	if not ed.has("event_properties"):
		push_error("bank export should keep event_properties")
		return 1
	if not ed.has("event_set_parameters"):
		push_error("bank export should use event_set_parameters")
		return 1
	return 0


static func _test_tag_filter() -> int:
	var root := CodaBrowserNodeScript.new("Events", CodaBrowserNode.Kind.FOLDER)
	var tagged := CodaBrowserNodeScript.new("UiClick", CodaBrowserNode.Kind.EVENT)
	tagged.event_tags = PackedStringArray(["ui"])
	var other := CodaBrowserNodeScript.new("Explosion", CodaBrowserNode.Kind.EVENT)
	other.event_tags = PackedStringArray(["combat"])
	root.children.append(tagged)
	root.children.append(other)
	if not CodaBrowserTreeModelScript.branch_visible(tagged, "#ui"):
		push_error("#ui filter should match tagged event")
		return 1
	if CodaBrowserTreeModelScript.branch_visible(other, "#ui"):
		push_error("#ui filter should hide non-matching event")
		return 1
	if not CodaBrowserTreeModelScript.branch_visible(root, "#ui"):
		push_error("folder with matching child should stay visible")
		return 1
	return 0


static func _test_get_property_for_path() -> int:
	var state: CodaState = CodaStateScript.new()
	var ev: CodaBrowserNode = state.add_events_event(state.events_root.id, "Props")
	if ev == null:
		push_error("get_property setup failed")
		return 1
	var radius := CodaEventProperty.new()
	radius.property_key = "DamageRadius"
	radius.value_type = CodaEventProperty.ValueType.FLOAT
	radius.default_value = 8.0
	var flag := CodaEventProperty.new()
	flag.property_key = "AnimateButton"
	flag.value_type = CodaEventProperty.ValueType.BOOL
	flag.default_value = true
	ev.event_properties.append(radius)
	ev.event_properties.append(flag)

	var runtime: CodaRuntime = CodaRuntimeScript.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.add_child(runtime)
	runtime._ready()
	runtime.set_project(state)

	if abs(float(runtime.get_property_for_path("Props", "DamageRadius")) - 8.0) > 0.001:
		push_error("get_property_for_path float")
		runtime.queue_free()
		return 1
	if runtime.get_property_for_path("Props", "AnimateButton") != true:
		push_error("get_property_for_path bool")
		runtime.queue_free()
		return 1
	if runtime.get_property_for_path("Props", "Missing", 99) != 99:
		push_error("get_property_for_path default")
		runtime.queue_free()
		return 1

	var handle := CodaEventHandleScript.new()
	handle.event_node = ev
	if abs(float(runtime.get_property(handle, "DamageRadius")) - 8.0) > 0.001:
		push_error("get_property on handle")
		runtime.queue_free()
		return 1
	runtime.queue_free()
	return 0
