extends RefCounted

## Editor-only peak envelope for timeline clip drawing. WAV (16-bit PCM) uses decoded
## peaks; other [AudioStream] types use a deterministic placeholder curve.

const INTERNAL_BUCKETS := 128
const MAX_SCAN_BYTES := 400000

static var _cache: Dictionary = {}  ## res_path -> PackedFloat32Array (INTERNAL_BUCKETS, 0..1)


static func peaks_for_clip_segment(
	res_path: String, offset_seconds: float, duration_seconds: float, out_buckets: int
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if res_path.is_empty() or duration_seconds <= 0.0001 or out_buckets < 4:
		return out
	out_buckets = mini(out_buckets, INTERNAL_BUCKETS)
	var full: PackedFloat32Array = _full_envelope(res_path)
	if full.is_empty():
		return _placeholder_segment(res_path, offset_seconds, duration_seconds, out_buckets)
	return _slice_by_time(full, res_path, offset_seconds, duration_seconds, out_buckets)


static func clear_cache() -> void:
	_cache.clear()


static func _full_envelope(res_path: String) -> PackedFloat32Array:
	if not res_path.begins_with("res://") or not ResourceLoader.exists(res_path):
		return PackedFloat32Array()
	if _cache.has(res_path):
		return _cache[res_path] as PackedFloat32Array
	var res: Resource = ResourceLoader.load(res_path)
	var peaks: PackedFloat32Array = PackedFloat32Array()
	if res is AudioStreamWAV:
		peaks = _peaks_from_wav(res as AudioStreamWAV)
	if peaks.is_empty() and res is AudioStream:
		peaks = _placeholder_full(res_path, res as AudioStream)
	if peaks.is_empty():
		return peaks
	_cache[res_path] = peaks
	return peaks


static func _placeholder_full(res_path: String, stream: AudioStream) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(abs(res_path.hash()))
	var len_s: float = stream.get_length()
	if len_s <= 0.0:
		len_s = 1.0
	var out := PackedFloat32Array()
	out.resize(INTERNAL_BUCKETS)
	for i in INTERNAL_BUCKETS:
		var t: float = float(i) / float(max(1, INTERNAL_BUCKETS - 1))
		var w: float = 0.35 + 0.45 * sin(t * TAU * (2.0 + rng.randf() * 3.0))
		w *= 0.5 + 0.5 * rng.randf()
		out[i] = clampf(w, 0.04, 1.0)
	return out


static func _peaks_from_wav(wav: AudioStreamWAV) -> PackedFloat32Array:
	var data: PackedByteArray = wav.data
	if data.is_empty():
		return PackedFloat32Array()
	if wav.format != AudioStreamWAV.FORMAT_16_BITS:
		return PackedFloat32Array()
	var stereo: bool = wav.stereo
	var rate: float = float(wav.mix_rate)
	if rate <= 0.0:
		rate = 44100.0
	var bytes_per_frame: int = 4 if stereo else 2
	var frame_count: int = data.size() / bytes_per_frame
	if frame_count <= 0:
		return PackedFloat32Array()
	var stride: int = maxi(1, int(ceil(float(data.size()) / float(MAX_SCAN_BYTES))))
	var eff_frames: int = frame_count / stride
	var frames_per_bucket: int = maxi(1, eff_frames / INTERNAL_BUCKETS)
	var out := PackedFloat32Array()
	out.resize(INTERNAL_BUCKETS)
	for b in INTERNAL_BUCKETS:
		var start_f: int = b * frames_per_bucket * stride
		var end_f: int = mini(frame_count, start_f + frames_per_bucket * stride)
		var peak: float = 0.0
		var f: int = start_f
		while f < end_f:
			var byte_i: int = f * bytes_per_frame
			if byte_i + bytes_per_frame > data.size():
				break
			var s: float = 0.0
			if stereo:
				var l: int = int(data.decode_s16(byte_i))
				var r: int = int(data.decode_s16(byte_i + 2))
				s = absf((float(l) + float(r)) * 0.5) / 32768.0
			else:
				var m: int = int(data.decode_s16(byte_i))
				s = absf(float(m)) / 32768.0
			peak = maxf(peak, s)
			f += stride
		out[b] = clampf(peak, 0.02, 1.0)
	return out


static func _slice_by_time(
	full: PackedFloat32Array,
	res_path: String,
	offset_seconds: float,
	duration_seconds: float,
	out_buckets: int
) -> PackedFloat32Array:
	var stream_len: float = _stream_length_seconds(res_path)
	var out := PackedFloat32Array()
	out.resize(out_buckets)
	if stream_len <= 0.0:
		for i in out_buckets:
			var idx: int = clampi(
				int(float(i) / float(max(1, out_buckets - 1)) * float(full.size() - 1)),
				0,
				full.size() - 1
			)
			out[i] = full[idx]
		return out
	var t0: float = clampf(offset_seconds / stream_len, 0.0, 1.0)
	var t1: float = clampf((offset_seconds + duration_seconds) / stream_len, t0 + 0.0001, 1.0)
	for i in out_buckets:
		var u: float = float(i) / float(max(1, out_buckets - 1))
		var g: float = lerpf(t0, t1, u)
		var idx: int = clampi(int(g * float(INTERNAL_BUCKETS - 1)), 0, INTERNAL_BUCKETS - 1)
		out[i] = full[idx]
	return out


static func _stream_length_seconds(res_path: String) -> float:
	if not ResourceLoader.exists(res_path):
		return 0.0
	var res: Resource = ResourceLoader.load(res_path)
	if res is AudioStream:
		return (res as AudioStream).get_length()
	return 0.0


static func _placeholder_segment(
	res_path: String, offset_seconds: float, duration_seconds: float, out_buckets: int
) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(abs(res_path.hash() + int(offset_seconds * 1000.0)))
	var out := PackedFloat32Array()
	out.resize(out_buckets)
	for i in out_buckets:
		var u: float = float(i) / float(max(1, out_buckets - 1))
		var w: float = 0.25 + 0.55 * sin((u + offset_seconds * 0.17) * TAU * 3.0)
		w *= 0.45 + 0.55 * rng.randf()
		out[i] = clampf(w, 0.05, 1.0)
	return out
