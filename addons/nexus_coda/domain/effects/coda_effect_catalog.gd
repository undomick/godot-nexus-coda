@tool
class_name CodaEffectCatalog
extends RefCounted

## Single source of truth for effect picker UI and [AudioEffect] materialization (Godot native only).

const _CAT_DYN := "Dynamics"
const _CAT_EQ := "EQ / Filter"
const _CAT_TIME := "Time"
const _CAT_MOD := "Modulation"
const _CAT_PITCH := "Pitch / Stereo"
const _CAT_SPAT := "Spatial"


static func category_for_type(t: CodaTrackEffect.Type) -> String:
	match t:
		CodaTrackEffect.Type.GAIN, CodaTrackEffect.Type.COMPRESSOR, CodaTrackEffect.Type.LIMITER:
			return _CAT_DYN
		CodaTrackEffect.Type.EQ_3BAND, CodaTrackEffect.Type.LOWPASS, CodaTrackEffect.Type.HIGHPASS, \
		CodaTrackEffect.Type.BANDPASS, CodaTrackEffect.Type.NOTCH:
			return _CAT_EQ
		CodaTrackEffect.Type.REVERB, CodaTrackEffect.Type.DELAY:
			return _CAT_TIME
		CodaTrackEffect.Type.CHORUS, CodaTrackEffect.Type.PHASER, CodaTrackEffect.Type.DISTORTION:
			return _CAT_MOD
		CodaTrackEffect.Type.PITCH_SHIFT, CodaTrackEffect.Type.STEREO_ENHANCE:
			return _CAT_PITCH
		CodaTrackEffect.Type.PANNER:
			return _CAT_SPAT
		_:
			return _CAT_DYN


static func display_name_for_type(t: CodaTrackEffect.Type) -> String:
	match t:
		CodaTrackEffect.Type.GAIN:
			return "Gain (Amplify)"
		CodaTrackEffect.Type.COMPRESSOR:
			return "Compressor"
		CodaTrackEffect.Type.LIMITER:
			return "Limiter"
		CodaTrackEffect.Type.EQ_3BAND:
			return "3-Band EQ"
		CodaTrackEffect.Type.LOWPASS:
			return "Low-pass"
		CodaTrackEffect.Type.HIGHPASS:
			return "High-pass"
		CodaTrackEffect.Type.BANDPASS:
			return "Band-pass"
		CodaTrackEffect.Type.NOTCH:
			return "Notch"
		CodaTrackEffect.Type.REVERB:
			return "Reverb"
		CodaTrackEffect.Type.DELAY:
			return "Delay"
		CodaTrackEffect.Type.CHORUS:
			return "Chorus"
		CodaTrackEffect.Type.PHASER:
			return "Phaser"
		CodaTrackEffect.Type.DISTORTION:
			return "Distortion"
		CodaTrackEffect.Type.PITCH_SHIFT:
			return "Pitch shift"
		CodaTrackEffect.Type.PANNER:
			return "Panner"
		CodaTrackEffect.Type.STEREO_ENHANCE:
			return "Stereo enhance"
		_:
			return "Effect"


static func all_types_sorted() -> Array[CodaTrackEffect.Type]:
	var out: Array[CodaTrackEffect.Type] = []
	for i in range(int(CodaTrackEffect.Type.STEREO_ENHANCE) + 1):
		out.append(i as CodaTrackEffect.Type)
	return out


static func default_params(t: CodaTrackEffect.Type) -> Dictionary:
	match t:
		CodaTrackEffect.Type.GAIN:
			return {"volume_db": 0.0}
		CodaTrackEffect.Type.COMPRESSOR:
			return {"threshold": -12.0, "ratio": 4.0, "attack_us": 20.0, "release_ms": 250.0, "gain": 0.0, "mix": 1.0}
		CodaTrackEffect.Type.LIMITER:
			return {"threshold_db": 0.0, "ceiling_db": -0.1, "soft_clip_db": 2.0, "soft_clip_ratio": 10.0}
		CodaTrackEffect.Type.EQ_3BAND:
			return {"low_db": 0.0, "mid_db": 0.0, "high_db": 0.0}
		CodaTrackEffect.Type.LOWPASS:
			return {"cutoff_hz": 5000.0, "resonance": 0.5}
		CodaTrackEffect.Type.HIGHPASS:
			return {"cutoff_hz": 80.0, "resonance": 0.5}
		CodaTrackEffect.Type.BANDPASS:
			return {"cutoff_hz": 1000.0, "resonance": 0.5}
		CodaTrackEffect.Type.NOTCH:
			return {"cutoff_hz": 1000.0, "resonance": 0.3}
		CodaTrackEffect.Type.REVERB:
			return {"room_size": 0.5, "damp": 0.5, "spread": 1.0, "hipass": 0.0, "dry": 1.0, "wet": 0.2}
		CodaTrackEffect.Type.DELAY:
			return {"dry": 1.0, "tap1_active": true, "tap1_delay_ms": 250.0, "tap1_pan": 0.0, "tap1_level_db": -6.0, "feedback_active": true, "feedback_delay_ms": 250.0, "feedback_level_db": -12.0}
		CodaTrackEffect.Type.CHORUS:
			return {"dry": 0.5, "wet": 0.5, "voices": 3, "delay_ms": 15.0, "depth_ms": 2.0, "spread_ms": 0.5, "lfo_hz": 2.0}
		CodaTrackEffect.Type.PHASER:
			return {
				"rate_hz": 0.5,
				"depth": 1.0,
				"feedback": 0.7,
				"range_min_hz": 440.0,
				"range_max_hz": 1600.0,
			}
		CodaTrackEffect.Type.DISTORTION:
			return {"mode": 0, "pre_gain": 0.0, "drive": 0.2, "post_gain": 0.0}
		CodaTrackEffect.Type.PITCH_SHIFT:
			return {"pitch_scale": 1.0, "fft_size": 3, "oversampling": 4}
		CodaTrackEffect.Type.PANNER:
			return {"pan": 0.0}
		CodaTrackEffect.Type.STEREO_ENHANCE:
			return {"pan_pullout": 1.0, "time_pullout_ms": 0.0, "surround": 0.0}
		_:
			return {}


static func param_specs(t: CodaTrackEffect.Type) -> Array[Dictionary]:
	match t:
		CodaTrackEffect.Type.GAIN:
			return [
				_spec("volume_db", -80.0, 24.0, 0.5, "dB", "Output gain."),
			]
		CodaTrackEffect.Type.COMPRESSOR:
			return [
				_spec("threshold", -60.0, 0.0, 0.5, "dB", "Compression threshold."),
				_spec("ratio", 1.0, 48.0, 0.5, ":1", "Compression ratio."),
				_spec("attack_us", 20.0, 2000.0, 10.0, "µs", "Attack time."),
				_spec("release_ms", 20.0, 2000.0, 5.0, "ms", "Release time."),
				_spec("gain", -24.0, 24.0, 0.5, "dB", "Make-up gain."),
				_spec("mix", 0.0, 1.0, 0.01, "", "Dry/wet mix."),
			]
		CodaTrackEffect.Type.LIMITER:
			return [
				_spec("threshold_db", -30.0, 0.0, 0.1, "dB", "Limiter onset threshold."),
				_spec("ceiling_db", -20.0, -0.1, 0.1, "dB", "Output ceiling."),
				_spec("soft_clip_db", 0.0, 6.0, 0.1, "dB", "Soft clip gain."),
				_spec("soft_clip_ratio", 1.0, 20.0, 0.5, "", "Soft clip ratio."),
			]
		CodaTrackEffect.Type.EQ_3BAND:
			return [
				_spec("low_db", -60.0, 24.0, 0.5, "dB", "Low shelf (~100 Hz)."),
				_spec("mid_db", -60.0, 24.0, 0.5, "dB", "Mid band (~1 kHz)."),
				_spec("high_db", -60.0, 24.0, 0.5, "dB", "High shelf (~3.2 kHz)."),
			]
		CodaTrackEffect.Type.LOWPASS, CodaTrackEffect.Type.HIGHPASS:
			return [
				_spec("cutoff_hz", 10.0, 20500.0, 1.0, "Hz", "Cutoff frequency."),
				_spec("resonance", 0.0, 1.0, 0.01, "", "Resonance amount."),
			]
		CodaTrackEffect.Type.BANDPASS, CodaTrackEffect.Type.NOTCH:
			return [
				_spec("cutoff_hz", 10.0, 20500.0, 1.0, "Hz", "Center frequency."),
				_spec("resonance", 0.0, 1.0, 0.01, "", "Resonance / sharpness."),
			]
		CodaTrackEffect.Type.REVERB:
			return [
				_spec("room_size", 0.0, 1.0, 0.01, "", "Room size."),
				_spec("damp", 0.0, 1.0, 0.01, "", "High-frequency damping."),
				_spec("spread", 0.0, 1.0, 0.01, "", "Stereo spread."),
				_spec("hipass", 0.0, 1.0, 0.01, "", "High-pass mix."),
				_spec("dry", 0.0, 1.0, 0.01, "", "Dry level."),
				_spec("wet", 0.0, 1.0, 0.01, "", "Wet level."),
			]
		CodaTrackEffect.Type.DELAY:
			return [
				_spec("dry", 0.0, 1.0, 0.01, "", "Dry level."),
				_spec("tap1_delay_ms", 1.0, 2000.0, 1.0, "ms", "First tap delay."),
				_spec("tap1_pan", -1.0, 1.0, 0.01, "", "First tap pan."),
				_spec("tap1_level_db", -80.0, 24.0, 0.5, "dB", "First tap level."),
				_spec("feedback_delay_ms", 1.0, 2000.0, 1.0, "ms", "Feedback delay."),
				_spec("feedback_level_db", -80.0, 0.0, 0.5, "dB", "Feedback level."),
			]
		CodaTrackEffect.Type.CHORUS:
			return [
				_spec("dry", 0.0, 1.0, 0.01, "", "Dry level."),
				_spec("wet", 0.0, 1.0, 0.01, "", "Wet level."),
				_spec("voices", 1.0, 5.0, 1.0, "", "Voice count."),
				_spec("delay_ms", 0.1, 50.0, 0.1, "ms", "Base delay."),
				_spec("depth_ms", 0.0, 20.0, 0.05, "ms", "LFO depth."),
				_spec("lfo_hz", 0.1, 20.0, 0.05, "Hz", "LFO rate."),
			]
		CodaTrackEffect.Type.PHASER:
			return [
				_spec("rate_hz", 0.1, 10.0, 0.05, "Hz", "LFO sweep rate."),
				_spec("depth", 0.1, 4.0, 0.05, "", "How high the sweep reaches."),
				_spec("feedback", 0.1, 0.9, 0.01, "", "Feedback amount."),
				_spec("range_min_hz", 10.0, 10000.0, 1.0, "Hz", "Minimum swept frequency."),
				_spec("range_max_hz", 10.0, 10000.0, 1.0, "Hz", "Maximum swept frequency."),
			]
		CodaTrackEffect.Type.DISTORTION:
			return [
				_spec("mode", 0.0, 4.0, 1.0, "", "Distortion mode (0–4)."),
				_spec("pre_gain", -60.0, 60.0, 0.5, "dB", "Pre gain."),
				_spec("drive", 0.0, 1.0, 0.01, "", "Drive amount."),
				_spec("post_gain", -60.0, 60.0, 0.5, "dB", "Post gain."),
			]
		CodaTrackEffect.Type.PITCH_SHIFT:
			return [
				_spec("pitch_scale", 0.25, 4.0, 0.01, "×", "Pitch multiplier."),
				_spec("fft_size", 0.0, 4.0, 1.0, "", "FFT buffer size (0=256 … 4=4096)."),
				_spec("oversampling", 1.0, 16.0, 1.0, "×", "Quality / CPU tradeoff."),
			]
		CodaTrackEffect.Type.PANNER:
			return [_spec("pan", -1.0, 1.0, 0.01, "", "Stereo pan.")]
		CodaTrackEffect.Type.STEREO_ENHANCE:
			return [
				_spec("pan_pullout", 0.0, 1.0, 0.01, "", "Pan pullout."),
				_spec("time_pullout_ms", 0.0, 20.0, 0.1, "ms", "Time pullout."),
				_spec("surround", 0.0, 1.0, 0.01, "", "Surround width."),
			]
		_:
			return []


static func merged_params(t: CodaTrackEffect.Type, params: Dictionary) -> Dictionary:
	var d: Dictionary = default_params(t).duplicate(true)
	for k in params.keys():
		d[k] = params[k]
	return d


static func build_audio_effect_from_slot(effect: CodaTrackEffect) -> AudioEffect:
	return build_audio_effect(effect.type, effect.params)


static func build_audio_effect(t: CodaTrackEffect.Type, params: Dictionary) -> AudioEffect:
	var p: Dictionary = merged_params(t, params)
	match t:
		CodaTrackEffect.Type.GAIN:
			var a := AudioEffectAmplify.new()
			a.volume_db = float(p.get("volume_db", 0.0))
			return a
		CodaTrackEffect.Type.COMPRESSOR:
			var c := AudioEffectCompressor.new()
			c.threshold = float(p.get("threshold", -12.0))
			c.ratio = float(p.get("ratio", 4.0))
			c.attack_us = float(p.get("attack_us", 20.0))
			c.release_ms = float(p.get("release_ms", 250.0))
			c.gain = float(p.get("gain", 0.0))
			c.mix = float(p.get("mix", 1.0))
			return c
		CodaTrackEffect.Type.LIMITER:
			var l := AudioEffectLimiter.new()
			l.threshold_db = float(p.get("threshold_db", 0.0))
			l.ceiling_db = float(p.get("ceiling_db", -0.1))
			l.soft_clip_db = float(p.get("soft_clip_db", 2.0))
			l.soft_clip_ratio = float(p.get("soft_clip_ratio", 10.0))
			return l
		CodaTrackEffect.Type.EQ_3BAND:
			var q := AudioEffectEQ6.new()
			# EQ6 bands: 1=32Hz, 2=100Hz, 3=320Hz, 4=1kHz, 5=3.2kHz, 6=10kHz.
			# Map UI low/mid/high to the audible ~100 Hz / 1 kHz / 3.2 kHz bands.
			q.set_band_gain_db(1, float(p.get("low_db", 0.0)))
			q.set_band_gain_db(3, float(p.get("mid_db", 0.0)))
			q.set_band_gain_db(4, float(p.get("high_db", 0.0)))
			return q
		CodaTrackEffect.Type.LOWPASS:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = float(p.get("cutoff_hz", 5000.0))
			lp.resonance = float(p.get("resonance", 0.5))
			return lp
		CodaTrackEffect.Type.HIGHPASS:
			var hp := AudioEffectHighPassFilter.new()
			hp.cutoff_hz = float(p.get("cutoff_hz", 80.0))
			hp.resonance = float(p.get("resonance", 0.5))
			return hp
		CodaTrackEffect.Type.BANDPASS:
			var bp := AudioEffectBandPassFilter.new()
			bp.cutoff_hz = float(p.get("cutoff_hz", 1000.0))
			bp.resonance = float(p.get("resonance", 0.5))
			return bp
		CodaTrackEffect.Type.NOTCH:
			var n := AudioEffectNotchFilter.new()
			n.cutoff_hz = float(p.get("cutoff_hz", 1000.0))
			n.resonance = float(p.get("resonance", 0.5))
			return n
		CodaTrackEffect.Type.REVERB:
			var r := AudioEffectReverb.new()
			r.room_size = float(p.get("room_size", 0.5))
			r.damping = float(p.get("damping", p.get("damp", 0.5)))
			r.spread = float(p.get("spread", 1.0))
			r.hipass = float(p.get("hipass", 0.0))
			r.dry = float(p.get("dry", 1.0))
			r.wet = float(p.get("wet", 0.2))
			return r
		CodaTrackEffect.Type.DELAY:
			var dly := AudioEffectDelay.new()
			dly.dry = float(p.get("dry", 1.0))
			dly.tap1_active = bool(p.get("tap1_active", true))
			dly.tap1_delay_ms = float(p.get("tap1_delay_ms", 250.0))
			dly.tap1_pan = float(p.get("tap1_pan", 0.0))
			dly.tap1_level_db = float(p.get("tap1_level_db", -6.0))
			dly.feedback_active = bool(p.get("feedback_active", true))
			dly.feedback_delay_ms = float(p.get("feedback_delay_ms", 250.0))
			dly.feedback_level_db = float(p.get("feedback_level_db", -12.0))
			return dly
		CodaTrackEffect.Type.CHORUS:
			var ch := AudioEffectChorus.new()
			ch.dry = float(p.get("dry", 0.5))
			ch.wet = float(p.get("wet", 0.5))
			ch.voice_count = clampi(int(p.get("voices", 3)), 1, 5)
			var dms: float = float(p.get("delay_ms", 15.0))
			var dep: float = float(p.get("depth_ms", 2.0))
			var r: float = float(p.get("lfo_hz", 2.0))
			for vi in range(ch.voice_count):
				ch.set_voice_delay_ms(vi, dms + float(vi) * 2.0)
				ch.set_voice_depth_ms(vi, dep)
				ch.set_voice_rate_hz(vi, r)
			return ch
		CodaTrackEffect.Type.PHASER:
			var ph := AudioEffectPhaser.new()
			ph.rate_hz = float(p.get("rate_hz", 0.5))
			ph.depth = clampf(float(p.get("depth", 1.0)), 0.1, 4.0)
			ph.feedback = clampf(float(p.get("feedback", 0.7)), 0.1, 0.9)
			var rmin: float = float(p.get("range_min_hz", 440.0))
			var rmax: float = float(p.get("range_max_hz", 1600.0))
			if rmax <= rmin:
				rmax = rmin + 100.0
			ph.range_min_hz = clampf(rmin, 10.0, 10000.0)
			ph.range_max_hz = clampf(rmax, ph.range_min_hz + 10.0, 10000.0)
			return ph
		CodaTrackEffect.Type.DISTORTION:
			var di := AudioEffectDistortion.new()
			di.mode = int(p.get("mode", 0))
			di.pre_gain = float(p.get("pre_gain", 0.0))
			di.drive = float(p.get("drive", 0.2))
			di.post_gain = float(p.get("post_gain", 0.0))
			return di
		CodaTrackEffect.Type.PITCH_SHIFT:
			var ps := AudioEffectPitchShift.new()
			ps.pitch_scale = clampf(float(p.get("pitch_scale", 1.0)), 0.01, 16.0)
			var fft_i: int = clampi(int(p.get("fft_size", 3)), 0, 4)
			match fft_i:
				0:
					ps.fft_size = AudioEffectPitchShift.FFT_SIZE_256
				1:
					ps.fft_size = AudioEffectPitchShift.FFT_SIZE_512
				2:
					ps.fft_size = AudioEffectPitchShift.FFT_SIZE_1024
				3:
					ps.fft_size = AudioEffectPitchShift.FFT_SIZE_2048
				_:
					ps.fft_size = AudioEffectPitchShift.FFT_SIZE_4096
			ps.oversampling = clampi(int(p.get("oversampling", 4)), 1, 16)
			return ps
		CodaTrackEffect.Type.PANNER:
			var pn := AudioEffectPanner.new()
			pn.pan = float(p.get("pan", 0.0))
			return pn
		CodaTrackEffect.Type.STEREO_ENHANCE:
			var se := AudioEffectStereoEnhance.new()
			se.pan_pullout = float(p.get("pan_pullout", 0.0))
			se.time_pullout_ms = float(p.get("time_pullout_ms", 0.0))
			se.surround = float(p.get("surround", 0.0))
			return se
		_:
			var fallback := AudioEffectAmplify.new()
			fallback.volume_db = 0.0
			return fallback


static func estimate_chain_tail_seconds(effects: Array) -> float:
	var max_tail: float = 0.0
	for eff in effects:
		if not eff is CodaTrackEffect:
			continue
		var e: CodaTrackEffect = eff as CodaTrackEffect
		if e.bypass:
			continue
		var p: Dictionary = merged_params(e.type, e.params)
		match e.type:
			CodaTrackEffect.Type.REVERB:
				if float(p.get("wet", 0.2)) > 0.001:
					var room: float = float(p.get("room_size", 0.5))
					var damp: float = float(p.get("damping", p.get("damp", 0.5)))
					var rev_tail: float = lerpf(1.5, 3.0, room) * lerpf(1.0, 0.6, damp)
					max_tail = maxf(max_tail, rev_tail)
			CodaTrackEffect.Type.DELAY:
				var tap_ms: float = float(p.get("tap1_delay_ms", 250.0))
				var fb_ms: float = float(p.get("feedback_delay_ms", 250.0))
				var delay_s: float = maxf(tap_ms, fb_ms) / 1000.0
				if bool(p.get("feedback_active", true)):
					max_tail = maxf(max_tail, delay_s * 4.0 + 0.5)
				elif bool(p.get("tap1_active", true)):
					max_tail = maxf(max_tail, delay_s + 0.1)
			CodaTrackEffect.Type.CHORUS:
				if float(p.get("wet", 0.5)) > 0.001:
					max_tail = maxf(max_tail, 0.15)
			CodaTrackEffect.Type.PHASER:
				max_tail = maxf(max_tail, 0.1)
			_:
				pass
	if max_tail <= 0.0:
		return 0.0
	return clampf(max_tail, 0.05, 5.0)


static func _spec(
	p_name: String, p_min: float, p_max: float, p_step: float, p_unit: String, p_tip: String
) -> Dictionary:
	return {
		"name": p_name,
		"min": p_min,
		"max": p_max,
		"step": p_step,
		"unit": p_unit,
		"tooltip": p_tip,
	}
