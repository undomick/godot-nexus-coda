@tool
class_name CodaModulation
extends RefCounted

## A single mapping from one parameter value to a target node property.
## At runtime, the runtime evaluates each modulation per frame and applies
## the curve-mapped result to the corresponding voice property (volume_db, pitch_scale, etc.).

## Targets a property of a graph node. Phase 4 supports SOUND.volume_db / SOUND.pitch_scale,
## RANDOM.weight (with `target_index` selecting the child), SWITCH.selected_branch, BLEND.mix.
enum TargetProperty {
	SOUND_VOLUME_DB = 0,
	SOUND_PITCH_SCALE = 1,
	RANDOM_WEIGHT = 2,
	SWITCH_SELECTED_BRANCH = 3,
	BLEND_MIX = 4,
}

var id: String
var source_param_id: String = ""
var target_node_id: String = ""
var target_property: TargetProperty = TargetProperty.SOUND_VOLUME_DB
var target_index: int = 0  ## Used for RANDOM_WEIGHT branch index; ignored otherwise.
## Range maps the source parameter to the property output: out = lerp(range_out_min, range_out_max,
##   inverse_lerp(range_in_min, range_in_max, source))
var range_in_min: float = 0.0
var range_in_max: float = 1.0
var range_out_min: float = 0.0
var range_out_max: float = 1.0
## Optional curve resource to remap [0..1] before output range mapping. null => linear.
var curve: Curve = null


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "m_%d_%d" % [Time.get_ticks_usec(), randi()]


static func display_name_for_target(p: TargetProperty) -> String:
	match p:
		TargetProperty.SOUND_VOLUME_DB:
			return "Sound: Volume (dB)"
		TargetProperty.SOUND_PITCH_SCALE:
			return "Sound: Pitch"
		TargetProperty.RANDOM_WEIGHT:
			return "Random: Weight"
		TargetProperty.SWITCH_SELECTED_BRANCH:
			return "Switch: Selected Branch"
		TargetProperty.BLEND_MIX:
			return "Blend: Mix"
	return "Unknown"


## Evaluates the modulation given a source parameter value.
func evaluate(source_value: float) -> float:
	var t01: float = 0.0
	if range_in_max != range_in_min:
		t01 = clamp((source_value - range_in_min) / (range_in_max - range_in_min), 0.0, 1.0)
	if curve != null:
		t01 = clamp(curve.sample(t01), 0.0, 1.0)
	return lerp(range_out_min, range_out_max, t01)


func clone_keep_id() -> CodaModulation:
	var m := CodaModulation.new()
	m.id = id
	m.source_param_id = source_param_id
	m.target_node_id = target_node_id
	m.target_property = target_property
	m.target_index = target_index
	m.range_in_min = range_in_min
	m.range_in_max = range_in_max
	m.range_out_min = range_out_min
	m.range_out_max = range_out_max
	m.curve = curve
	return m


func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"source_param_id": source_param_id,
		"target_node_id": target_node_id,
		"target_property": int(target_property),
		"target_index": target_index,
		"range_in_min": range_in_min,
		"range_in_max": range_in_max,
		"range_out_min": range_out_min,
		"range_out_max": range_out_max,
		# Curve resources can't be inlined as JSON; persist a res:// path if the user assigned one.
		"curve_path": curve.resource_path if curve != null else "",
	}


static func from_dictionary(data: Dictionary) -> CodaModulation:
	var m := CodaModulation.new()
	var sid: String = str(data.get("id", "")).strip_edges()
	if not sid.is_empty():
		m.id = sid
	m.source_param_id = str(data.get("source_param_id", ""))
	m.target_node_id = str(data.get("target_node_id", ""))
	var tp_raw: int = int(data.get("target_property", TargetProperty.SOUND_VOLUME_DB))
	match tp_raw:
		TargetProperty.SOUND_VOLUME_DB, TargetProperty.SOUND_PITCH_SCALE, TargetProperty.RANDOM_WEIGHT, TargetProperty.SWITCH_SELECTED_BRANCH, TargetProperty.BLEND_MIX:
			m.target_property = tp_raw as TargetProperty
		_:
			m.target_property = TargetProperty.SOUND_VOLUME_DB
	m.target_index = int(data.get("target_index", 0))
	m.range_in_min = float(data.get("range_in_min", 0.0))
	m.range_in_max = float(data.get("range_in_max", 1.0))
	m.range_out_min = float(data.get("range_out_min", 0.0))
	m.range_out_max = float(data.get("range_out_max", 1.0))
	var curve_path: String = str(data.get("curve_path", "")).strip_edges()
	if not curve_path.is_empty() and ResourceLoader.exists(curve_path):
		var res: Resource = load(curve_path)
		m.curve = res as Curve
	return m
