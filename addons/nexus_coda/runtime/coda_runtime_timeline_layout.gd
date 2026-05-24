@tool
class_name CodaRuntimeTimelineLayout
extends RefCounted

## Timeline layout fingerprints for editor preview resync.


static func layout_signature(timeline: CodaEventTimeline) -> String:
	if timeline == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for tr in timeline.tracks:
		var bus_id: String = String(tr.output_bus_id)
		var track_fx: String = fx_chain_signature(tr.effects)
		for clip in tr.clips:
			parts.append(
				"%s|%s|%s|%.6f|%.6f|%s|fx:%s|tfx:%s"
				% [
					clip.id,
					tr.id,
					clip.audio_path,
					clip.start_seconds,
					clip.duration_seconds,
					bus_id,
					fx_chain_signature(clip.effects),
					track_fx,
				]
			)
	parts.sort()
	return "%.6f|%s" % [timeline.length_seconds, "|".join(parts)]


static func fx_chain_signature(effects: Array) -> String:
	if effects.is_empty():
		return ""
	var fx_parts: PackedStringArray = PackedStringArray()
	for eff in effects:
		if eff is CodaTrackEffect:
			var e: CodaTrackEffect = eff as CodaTrackEffect
			fx_parts.append(
				"%s|%d|%s|%s"
				% [e.id, int(e.type), str(e.bypass), JSON.stringify(e.params)]
			)
	fx_parts.sort()
	return ",".join(fx_parts)
