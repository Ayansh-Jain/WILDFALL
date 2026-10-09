class_name Synth
extends RefCounted
## Procedural placeholder sounds (mono, 16-bit). Used by tools/generate_audio.gd
## to write assets/audio/*.wav, and by AudioLib as a fallback if a file is missing.

const RATE := 22050

## name -> [method, looping]
const SOUNDS := {
	"wind_loop": ["_wind", true],
	"leaves_loop": ["_leaves", true],
	"crickets_loop": ["_crickets", true],
	"water_loop": ["_water", true],
	"waterfall_loop": ["_waterfall", true],
	"scroll_hum_loop": ["_scroll_hum", true],
	"owl": ["_owl", false],
	"night_bird": ["_night_bird", false],
	"wolf_distant": ["_wolf", false],
	"scroll_pickup": ["_scroll_pickup", false],
	"footstep_1": ["_footstep_1", false],
	"footstep_2": ["_footstep_2", false],
	"footstep_3": ["_footstep_3", false],
	"footstep_water": ["_footstep_water", false],
	"cave_drip": ["_cave_drip", false],
	"transform": ["_transform", false],
	"roar": ["_roar", false],
	"claw_swipe": ["_claw_swipe", false],
	"heavy_slam": ["_heavy_slam", false],
	"pounce": ["_pounce", false],
	"sword_swing": ["_sword_swing", false],
	"dodge": ["_dodge", false],
	"ward": ["_ward", false],
	"hit": ["_hit", false],
	"defeat": ["_defeat", false],
	"power_up": ["_power_up", false],
}

var rng := RandomNumberGenerator.new()


func make(sound_name: String) -> AudioStreamWAV:
	var spec: Array = SOUNDS[sound_name]
	rng.seed = hash(sound_name)
	var samples: PackedFloat32Array = call(spec[0])
	return to_wav(samples, spec[1])


static func to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


# --- helpers -----------------------------------------------------------------

## Generates `seconds` + fade of raw audio, then crossfades the tail into the
## head so the loop point is seamless.
func _seamless(seconds: float, gen: Callable, fade := 0.5) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var f := int(fade * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + f)
	for i in n + f:
		raw[i] = gen.call(i, float(i) / RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		if i < f:
			var w := float(i) / f
			out[i] = raw[i] * w + raw[n + i] * (1.0 - w)
		else:
			out[i] = raw[i]
	return out


func _normalize(s: PackedFloat32Array, peak := 0.8) -> PackedFloat32Array:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	for i in s.size():
		s[i] = s[i] / m * peak
	return s


func _buffer(seconds: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(seconds * RATE))
	s.fill(0.0)
	return s


func _tone(s: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float,
		attack := 0.01, harmonics := [1.0], vibrato := 0.0) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	for i in n:
		if i0 + i >= s.size():
			break
		var t := float(i) / n
		var f := lerpf(f0, f1, t) * (1.0 + vibrato * sin(float(i) / RATE * TAU * 5.5))
		phase += TAU * f / RATE
		var env := minf(1.0, float(i) / (attack * RATE + 1.0)) * pow(1.0 - t, 1.5)
		var v := 0.0
		for h in harmonics.size():
			v += sin(phase * (h + 1)) * harmonics[h]
		s[i0 + i] += v * env * amp


# --- sounds --------------------------------------------------------------------

func _wind() -> PackedFloat32Array:
	var lp := [0.0, 0.0]
	var brown := [0.0]
	var s := _seamless(8.0, func(_i: int, t: float) -> float:
		brown[0] = (brown[0] + rng.randf_range(-1, 1) * 0.08) * 0.995
		lp[0] += 0.03 * (brown[0] - lp[0])
		lp[1] += 0.18 * (rng.randf_range(-1, 1) - lp[1])
		var gust := 0.55 + 0.25 * sin(t * TAU * 0.125) + 0.2 * sin(t * TAU * 0.375 + 1.3)
		return (lp[0] * 1.6 + lp[1] * 0.18 * gust) * gust)
	return _normalize(s, 0.7)


func _leaves() -> PackedFloat32Array:
	var lp := [0.0, 0.0]
	var env := [0.0]
	var s := _seamless(6.0, func(_i: int, t: float) -> float:
		var x := rng.randf_range(-1, 1)
		lp[0] += 0.25 * (x - lp[0])
		lp[1] += 0.04 * (lp[0] - lp[1])
		var hp: float = lp[0] - lp[1]
		var target := 0.25 + 0.75 * maxf(0.0, sin(t * TAU * 0.5) * sin(t * TAU * 1.5 + 0.7))
		env[0] += 0.0005 * (target - env[0])
		var crackle := 1.0 + (2.5 if rng.randf() < 0.002 else 0.0)
		return hp * env[0] * crackle)
	return _normalize(s, 0.6)


func _crickets() -> PackedFloat32Array:
	var s := _buffer(4.0)
	for c in 2:
		var f := 4300.0 if c == 0 else 3850.0
		var t := 0.05 + c * 0.23
		while t < 3.8:
			for p in 3:
				_tone(s, t + p * 0.045, 0.028, f, f * 0.98, 0.25 - c * 0.08, 0.004)
			t += 0.52 + rng.randf_range(-0.04, 0.04) + c * 0.07
	return _normalize(s, 0.5)


func _water() -> PackedFloat32Array:
	# Gentle, continuous river current: broad soft noise with overlapping eddies.
	var lp := [0.0, 0.0, 0.0, 0.0]
	var s := _seamless(6.0, func(_i: int, t: float) -> float:
		var x := rng.randf_range(-1, 1)
		lp[0] += 0.22 * (x - lp[0])
		lp[1] += 0.035 * (lp[0] - lp[1])
		lp[2] += 0.003 * (rng.randf_range(-1, 1) - lp[2])
		lp[3] += 0.11 * (rng.randf_range(-1, 1) - lp[3])
		var eddies := 0.72 + 0.16 * sin(t * TAU * 0.31 + lp[2] * 17.0) + 0.12 * sin(t * TAU * 0.73)
		return ((lp[0] - lp[1]) * 0.72 + lp[1] * 0.24 + lp[3] * 0.12) * eddies)
	return _normalize(s, 0.42)


func _waterfall() -> PackedFloat32Array:
	# The heavier low body and steady spray distinguish the fall from the river bed.
	var lp := [0.0, 0.0, 0.0]
	var s := _seamless(7.0, func(_i: int, t: float) -> float:
		var x := rng.randf_range(-1.0, 1.0)
		lp[0] += 0.38 * (x - lp[0])
		lp[1] += 0.055 * (lp[0] - lp[1])
		lp[2] += 0.012 * (rng.randf_range(-1.0, 1.0) - lp[2])
		var surge := 0.82 + 0.12 * sin(t * TAU * 0.19) + 0.06 * sin(t * TAU * 0.43 + lp[2] * 8.0)
		return ((lp[0] - lp[1]) * 0.72 + lp[1] * 0.58 + lp[2] * 0.16) * surge)
	return _normalize(s, 0.56)


func _scroll_hum() -> PackedFloat32Array:
	var s := _buffer(4.0)
	var freqs := [220.0, 277.25, 329.5, 440.25]
	var amps := [0.5, 0.3, 0.3, 0.15]
	for i in s.size():
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t) * amps[k]
		s[i] = v * (0.75 + 0.25 * sin(TAU * 0.5 * t))
	var ping := 0.2
	while ping < 3.5:
		_tone(s, ping, 0.4, 1760.0 * rng.randf_range(0.9, 1.3), 1700.0, 0.12, 0.002, [1.0, 0.0, 0.3])
		ping += rng.randf_range(0.25, 0.6)
	return _normalize(s, 0.55)


func _owl() -> PackedFloat32Array:
	var s := _buffer(1.8)
	_tone(s, 0.0, 0.45, 390.0, 360.0, 0.6, 0.06, [1.0, 0.15])
	_tone(s, 0.62, 0.22, 380.0, 360.0, 0.5, 0.04, [1.0, 0.15])
	_tone(s, 0.9, 0.6, 385.0, 340.0, 0.55, 0.05, [1.0, 0.15], 0.01)
	return _normalize(s, 0.7)


func _night_bird() -> PackedFloat32Array:
	var s := _buffer(1.3)
	var t := 0.0
	for i in 4:
		_tone(s, t, 0.09, 2600.0 + i * 120.0, 3500.0, 0.4, 0.005, [1.0, 0.2])
		t += 0.16 + rng.randf_range(0.0, 0.08)
	_tone(s, t + 0.1, 0.25, 3300.0, 2400.0, 0.35, 0.01, [1.0])
	return _normalize(s, 0.6)


func _wolf() -> PackedFloat32Array:
	var s := _buffer(4.0)
	var phase := 0.0
	var n := int(3.2 * RATE)
	for i in n:
		var t := float(i) / RATE
		var f: float
		if t < 0.9:
			f = lerpf(300.0, 540.0, smoothstep(0.0, 0.9, t))
		elif t < 2.4:
			f = 540.0 - (t - 0.9) * 25.0
		else:
			f = lerpf(500.0, 360.0, (t - 2.4) / 0.8)
		f *= 1.0 + 0.012 * sin(t * TAU * 5.0)
		phase += TAU * f / RATE
		var env := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(2.6, 3.2, t))
		s[i] = (sin(phase) + 0.3 * sin(phase * 2.0) + 0.08 * sin(phase * 3.0)) * env
	var lp := 0.0
	for i in s.size():
		lp += 0.25 * (s[i] - lp)
		s[i] = lp
	for i in range(s.size() - 1, int(0.3 * RATE), -1):
		s[i] += s[i - int(0.3 * RATE)] * 0.35
	return _normalize(s, 0.6)


func _scroll_pickup() -> PackedFloat32Array:
	var s := _buffer(2.2)
	var notes := [440.0, 554.4, 659.3, 880.0, 1108.7, 1318.5]
	for k in notes.size():
		_tone(s, k * 0.07, 1.4 - k * 0.1, notes[k], notes[k], 0.35, 0.003, [1.0, 0.0, 0.0, 0.25])
	var lp := 0.0
	for i in int(0.8 * RATE):
		var t := float(i) / (0.8 * RATE)
		lp += (0.02 + t * 0.3) * (rng.randf_range(-1, 1) - lp)
		s[i] += lp * sin(t * PI) * 0.5
	return _normalize(s, 0.75)


func _footstep(seed_offset: int) -> PackedFloat32Array:
	rng.seed = 991 + seed_offset
	var s := _buffer(0.25)
	var low := 0.0
	var mid := 0.0
	var grit := 0.0
	var impact := rng.randf_range(0.0, 0.012)
	var heel := rng.randf_range(0.045, 0.065)
	for i in s.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		low += 0.075 * (noise - low)
		mid += 0.32 * (noise - mid)
		grit += 0.72 * (noise - grit)
		var first := exp(-maxf(0.0, t - impact) * 38.0) if t >= impact else 0.0
		var second := exp(-maxf(0.0, t - heel) * 54.0) if t >= heel else 0.0
		var thud := sin(TAU * (72.0 + seed_offset * 5.0) * t + 0.7) * first * 0.5
		var crunch := (mid - low) * first * 0.72 + (grit - mid) * second * 0.22
		var body := low * first * 0.9 + low * second * 0.38
		s[i] = (body + crunch + thud) * minf(1.0, t * 500.0)
	return _normalize(s, rng.randf_range(0.48, 0.63))


func _footstep_1() -> PackedFloat32Array:
	return _footstep(1)


func _footstep_2() -> PackedFloat32Array:
	return _footstep(2)


func _footstep_3() -> PackedFloat32Array:
	return _footstep(3)


func _footstep_water() -> PackedFloat32Array:
	var s := _buffer(0.4)
	var lp := [0.0, 0.0, 0.0]
	for i in s.size():
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp[0] += 0.35 * (noise - lp[0])
		lp[1] += 0.07 * (lp[0] - lp[1])
		lp[2] += 0.012 * (rng.randf_range(-1.0, 1.0) - lp[2])
		var entry := exp(-t * 16.0) * minf(1.0, t * 250.0)
		var second_slosh := exp(-maxf(0.0, t - 0.09) * 24.0) if t >= 0.09 else 0.0
		s[i] = ((lp[0] - lp[1]) * entry * 0.8 + lp[2] * entry * 0.3 + (lp[0] - lp[1]) * second_slosh * 0.24)
	# Uneven small droplets trail the main splash instead of pitched chirps.
	for drop in 4:
		var at := rng.randf_range(0.045, 0.26)
		var amp := rng.randf_range(0.035, 0.09)
		var drop_lp := 0.0
		for i in range(int(at * RATE), mini(s.size(), int((at + 0.035) * RATE))):
			drop_lp += 0.65 * (rng.randf_range(-1.0, 1.0) - drop_lp)
			s[i] += drop_lp * amp * exp(-float(i - int(at * RATE)) / RATE * 110.0)
	return _normalize(s, 0.52)


func _cave_drip() -> PackedFloat32Array:
	var s := _buffer(1.2)
	for e in 4:
		_tone(s, e * 0.19, 0.16, 1900.0, 1150.0, 0.6 * pow(0.45, e), 0.001, [1.0, 0.2])
	return _normalize(s, 0.6)


# --- combat sounds -----------------------------------------------------------------

## Filtered noise sweep (whooshes). f0/f1 are low-pass coefficients over time.
func _whoosh(seconds: float, f0: float, f1: float, amp := 1.0) -> PackedFloat32Array:
	var s := _buffer(seconds)
	var lp := 0.0
	var lp2 := 0.0
	for i in s.size():
		var t := float(i) / s.size()
		var a := lerpf(f0, f1, t)
		lp += a * (rng.randf_range(-1, 1) - lp)
		lp2 += a * 0.5 * (lp - lp2)
		s[i] = (lp - lp2 * 0.5) * sin(t * PI) * amp
	return s


## Growl: buzzy low tone with jitter, the base of the beast's voice.
func _growl(s: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float) -> void:
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		if i0 + i >= s.size():
			break
		var t := float(i) / n
		var f := lerpf(f0, f1, t) * (1.0 + 0.03 * sin(float(i) / RATE * TAU * 7.0) + rng.randf_range(-0.02, 0.02))
		phase += f / RATE
		var saw := fmod(phase, 1.0) * 2.0 - 1.0
		var env := smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.7, 1.0, t))
		lp += 0.15 * (saw + rng.randf_range(-0.6, 0.6) - lp)
		s[i0 + i] += lp * env * amp


func _roar() -> PackedFloat32Array:
	var s := _buffer(2.7)
	# Start with a breathy explosive bark, open into a rasping mid growl, then fall
	# back into a low rumble. Independent, detuned throats keep it from sounding tonal.
	_growl(s, 0.08, 2.25, 104.0, 58.0, 1.0)
	_growl(s, 0.1, 2.0, 218.0, 126.0, 0.55)
	_growl(s, 0.18, 1.45, 326.0, 178.0, 0.22)
	var w := _whoosh(2.25, 0.16, 0.035, 0.8)
	for i in w.size():
		var t := float(i) / RATE
		var attack := smoothstep(0.0, 0.12, t)
		var release := 1.0 - smoothstep(1.75, 2.25, t)
		s[i] += w[i] * attack * release
	# A coarse, filtered snarl adds the noisy vocal edge missing from the old buzz.
	var lp := 0.0
	var env := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var target := smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(1.8, 2.5, t))
		env += 0.0015 * (target - env)
		lp += 0.24 * (rng.randf_range(-1.0, 1.0) - lp)
		s[i] += (lp - lp * 0.3) * env * 0.9
	return _normalize(s, 0.5)


func _transform() -> PackedFloat32Array:
	var s := _buffer(2.0)
	_growl(s, 0.3, 1.6, 60.0, 110.0, 0.9)
	var w := _whoosh(1.2, 0.01, 0.3, 0.8)
	for i in w.size():
		s[i] += w[i]
	for k in 18:
		var t := rng.randf_range(0.0, 1.6)
		_tone(s, t, 0.05, rng.randf_range(1500, 3000), 800.0, 0.15, 0.001)
	return _normalize(s, 0.85)


func _claw_swipe() -> PackedFloat32Array:
	var s := _whoosh(0.35, 0.05, 0.6, 1.0)
	return _normalize(s, 0.7)


func _sword_swing() -> PackedFloat32Array:
	var s := _whoosh(0.28, 0.2, 0.7, 1.0)
	_tone(s, 0.0, 0.25, 2400.0, 2200.0, 0.06, 0.01)
	return _normalize(s, 0.55)


func _dodge() -> PackedFloat32Array:
	return _normalize(_whoosh(0.3, 0.08, 0.3, 1.0), 0.5)


func _pounce() -> PackedFloat32Array:
	var s := _whoosh(0.6, 0.03, 0.15, 0.8)
	_tone(s, 0.0, 0.25, 70.0, 45.0, 0.9, 0.005)
	_growl(s, 0.05, 0.4, 120.0, 90.0, 0.4)
	return _normalize(s, 0.8)


func _heavy_slam() -> PackedFloat32Array:
	var s := _buffer(1.2)
	_tone(s, 0.0, 0.6, 60.0, 30.0, 1.0, 0.002, [1.0, 0.4])
	var lp := 0.0
	for i in int(0.9 * RATE):
		var t := float(i) / RATE
		lp += 0.08 * (rng.randf_range(-1, 1) - lp)
		s[i] += lp * exp(-t * 4.0) * 1.4
	return _normalize(s, 0.9)


func _ward() -> PackedFloat32Array:
	var s := _buffer(1.4)
	for k in 4:
		_tone(s, k * 0.04, 1.2, [880.0, 1320.0, 1760.0, 2640.0][k], [900.0, 1340.0, 1790.0, 2700.0][k], 0.25, 0.002, [1.0, 0.0, 0.2])
	var w := _whoosh(0.5, 0.3, 0.05, 0.5)
	for i in w.size():
		s[i] += w[i]
	return _normalize(s, 0.7)


func _hit() -> PackedFloat32Array:
	var s := _buffer(0.3)
	_tone(s, 0.0, 0.15, 160.0, 70.0, 0.9, 0.001)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		lp += 0.35 * (rng.randf_range(-1, 1) - lp)
		s[i] += lp * exp(-t * 25.0) * 0.9
	return _normalize(s, 0.8)


func _defeat() -> PackedFloat32Array:
	var s := _buffer(1.2)
	_tone(s, 0.0, 0.5, 90.0, 40.0, 0.9, 0.002)
	_tone(s, 0.15, 1.0, 220.0, 110.0, 0.25, 0.05, [1.0, 0.3])
	return _normalize(s, 0.75)


func _power_up() -> PackedFloat32Array:
	var s := _buffer(0.7)
	_tone(s, 0.0, 0.5, 660.0, 660.0, 0.3, 0.003, [1.0, 0.0, 0.2])
	_tone(s, 0.09, 0.55, 990.0, 990.0, 0.3, 0.003, [1.0, 0.0, 0.2])
	return _normalize(s, 0.55)
