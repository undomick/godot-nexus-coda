@tool
class_name CodaRuntimeGraphPlayback
extends RefCounted

## Graph plan helpers extracted from [CodaRuntime].


static func split_parallel_entries(entries: Array) -> Array:
	var out: Array = []
	var first_step: int = -1
	for i in entries.size():
		var entry: Dictionary = entries[i] as Dictionary
		var w: float = float(entry.get("blend_weight", 1.0))
		if w >= 1.0:
			if out.is_empty():
				out.append(entries[i])
			break
		var step: int = int(entry.get("blend_parallel_step", 0))
		if out.is_empty():
			first_step = step
			out.append(entries[i])
		elif step == first_step:
			out.append(entries[i])
		else:
			break
	if out.is_empty() and not entries.is_empty():
		out.append(entries[0])
	return out


static func plan_after_incomplete_parallel_step(
	parallel_entries: Array, started_indices: Dictionary, rest: Array
) -> Array:
	var out: Array = []
	for i in parallel_entries.size():
		if not started_indices.has(i):
			out.append(parallel_entries[i])
	out.append_array(rest)
	return out
