extends RefCounted
class_name CodaSpatialVoiceRuntime

## Applies simple distance attenuation before the output bus (3D routing stage).

const MIN_DISTANCE := 1.0
const MAX_DISTANCE := 100.0


static func apply_distance_attenuation(
	player: AudioStreamPlayer, distance: float, base_volume_db: float
) -> void:
	if player == null:
		return
	var d: float = maxf(0.0, distance)
	if d <= MIN_DISTANCE:
		player.volume_db = base_volume_db
		return
	var t: float = clampf((d - MIN_DISTANCE) / maxf(0.001, MAX_DISTANCE - MIN_DISTANCE), 0.0, 1.0)
	var atten_db: float = lerpf(0.0, -24.0, t)
	player.volume_db = base_volume_db + atten_db


static func apply_from_meta(player: AudioStreamPlayer, base_volume_db: float) -> void:
	if player == null or not player.has_meta(&"_coda_spatial_distance"):
		return
	var distance: float = float(player.get_meta(&"_coda_spatial_distance", 0.0))
	apply_distance_attenuation(player, distance, base_volume_db)
