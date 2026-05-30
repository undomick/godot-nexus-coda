@tool
class_name CodaTrackEffect
extends RefCounted

## Serializable effect slot for track / clip / bus chains. Godot [AudioEffect] instances are
## built at runtime via [CodaEffectCatalog] — nothing here is a persisted Resource reference.

enum Type {
	GAIN = 0,
	COMPRESSOR = 1,
	LIMITER = 2,
	EQ_3BAND = 3,
	LOWPASS = 4,
	HIGHPASS = 5,
	BANDPASS = 6,
	NOTCH = 7,
	REVERB = 8,
	DELAY = 9,
	CHORUS = 10,
	PHASER = 11,
	DISTORTION = 12,
	PITCH_SHIFT = 13,
	PANNER = 14,
	STEREO_ENHANCE = 15,
}

var id: String
var type: Type = Type.GAIN
var bypass: bool = false
var params: Dictionary = {}


func _init() -> void:
	id = _generate_id()


static func _generate_id() -> String:
	return "efx_%d_%d" % [Time.get_ticks_usec(), randi()]


func clone_new_id() -> CodaTrackEffect:
	var e := CodaTrackEffect.new()
	e.type = type
	e.bypass = bypass
	e.params = params.duplicate(true)
	return e


func clone_keep_id() -> CodaTrackEffect:
	var e := CodaTrackEffect.new()
	e.id = id
	e.type = type
	e.bypass = bypass
	e.params = params.duplicate(true)
	return e


func to_dictionary() -> Dictionary:
	return {"id": id, "type": int(type), "bypass": bypass, "params": params.duplicate(true)}


static func from_dictionary(data: Dictionary) -> CodaTrackEffect:
	var e := CodaTrackEffect.new()
	var sid: String = str(data.get("id", "")).strip_edges()
	if not sid.is_empty():
		e.id = sid
	e.type = clampi(int(data.get("type", 0)), 0, int(Type.STEREO_ENHANCE)) as Type
	e.bypass = bool(data.get("bypass", false))
	var pr: Variant = data.get("params", {})
	if pr is Dictionary:
		e.params = (pr as Dictionary).duplicate(true)
	else:
		e.params = {}
	return e
