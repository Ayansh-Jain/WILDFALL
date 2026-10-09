class_name Ambience
extends Node
## Environmental audio and mood: wind/leaves/crickets beds, positional water,
## random distant wildlife, and the cave transition (darker ambient light,
## reverb, drips). Also muffles audio while the camera is underwater.

@export var wildlife_interval := Vector2(7.0, 18.0)
@export var cave_ambient_energy := 0.45
@export var cave_fog_energy := 0.25

var world: World
var player: PlayerController
var cave: Cave
var in_cave := false

var _lib: AudioLib
var _wind: AudioStreamPlayer
var _leaves: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _next_call := 5.0
var _next_drip := 3.0
var _reverb_idx := -1
var _lowpass_idx := -1
var _base_ambient := 0.9
var _base_fog_energy := 1.0
var _base_sky := 0.35
var _mood_tween: Tween
var _rng := RandomNumberGenerator.new()


func setup(w: World, p: PlayerController) -> void:
	world = w
	player = p
	_lib = AudioLib.get_instance()
	_rng.randomize()
	var env := world.environment
	_base_ambient = env.ambient_light_energy
	_base_fog_energy = env.fog_light_energy
	_base_sky = env.ambient_light_sky_contribution
	_wind = _bed("wind_loop", -15.0)
	_leaves = _bed("leaves_loop", -22.0)
	_crickets = _bed("crickets_loop", -27.0)
	_water_emitters()
	_setup_bus_effects()
	cave = world.get_node_or_null("Sites/Cave")
	if cave:
		cave.player_entered.connect(_on_cave_entered)
		cave.player_exited.connect(_on_cave_exited)


func _bed(sound: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _lib.get_stream(sound)
	p.volume_db = volume
	p.autoplay = false
	add_child(p)
	p.play(_rng.randf() * 2.0)
	return p


func _water_emitters() -> void:
	for river in world.layout.list("rivers"):
		var pts := WorldLayout.points(river["points"])
		var carry := 0.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			var d := carry
			while d < seg:
				var p := a.lerp(b, d / seg)
				_positional("water_loop", Vector3(p.x, world.water_level + 0.5, p.y), -7.0, 7.0, 34.0)
				d += 55.0
			carry = d - seg
	var wf := world.layout.dict("waterfall")
	if not wf.is_empty():
		var b := WorldLayout.v2(wf["bottom"])
		_positional("waterfall_loop", Vector3(b.x, world.water_level + 4.0, b.y), -3.0, 8.0, 22.0)


func _positional(sound: String, pos: Vector3, volume: float, unit: float, max_dist: float, pitch := 1.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _lib.get_stream(sound)
	p.volume_db = volume
	p.unit_size = unit
	p.max_distance = max_dist
	p.pitch_scale = pitch
	p.attenuation_filter_cutoff_hz = 6000.0
	world.add_child(p)
	p.global_position = pos
	p.play(_rng.randf() * 3.0)
	return p


func _setup_bus_effects() -> void:
	var master := 0
	for i in AudioServer.get_bus_effect_count(master):
		var fx := AudioServer.get_bus_effect(master, i)
		if fx is AudioEffectReverb:
			_reverb_idx = i
		elif fx is AudioEffectLowPassFilter:
			_lowpass_idx = i
	if _reverb_idx < 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.75
		rv.damping = 0.4
		rv.wet = 0.35
		AudioServer.add_bus_effect(master, rv)
		_reverb_idx = AudioServer.get_bus_effect_count(master) - 1
	if _lowpass_idx < 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 700.0
		AudioServer.add_bus_effect(master, lp)
		_lowpass_idx = AudioServer.get_bus_effect_count(master) - 1
	AudioServer.set_bus_effect_enabled(master, _reverb_idx, false)
	AudioServer.set_bus_effect_enabled(master, _lowpass_idx, false)


func _process(delta: float) -> void:
	if player == null:
		return
	var pos := player.global_position
	# Leaves rustle louder under the canopy.
	var f := world.terrain_data.sample(world.terrain_data.forest, pos.x, pos.z)
	var target_leaves := -34.0 if in_cave else lerpf(-28.0, -15.0, f)
	_leaves.volume_db = lerpf(_leaves.volume_db, target_leaves, delta * 1.5)
	_wind.volume_db = lerpf(_wind.volume_db, -36.0 if in_cave else -15.0 + clampf((pos.y - 10.0) / 6.0, 0.0, 6.0), delta * 1.5)
	_crickets.volume_db = lerpf(_crickets.volume_db, -40.0 if in_cave else -27.0, delta * 1.5)
	AudioServer.set_bus_effect_enabled(0, _lowpass_idx, player.is_camera_underwater())

	_next_call -= delta
	if _next_call <= 0.0 and not in_cave:
		_next_call = _rng.randf_range(wildlife_interval.x, wildlife_interval.y)
		_wildlife_call(pos)
	if in_cave:
		_next_drip -= delta
		if _next_drip <= 0.0:
			_next_drip = _rng.randf_range(2.5, 6.0)
			var p := _random_cave_point()
			_one_shot("cave_drip", p, -8.0, 4.0, 30.0)


func _wildlife_call(around: Vector3) -> void:
	var roll := _rng.randf()
	var sound := "owl" if roll < 0.45 else ("night_bird" if roll < 0.85 else "wolf_distant")
	var dist := _rng.randf_range(25.0, 70.0) if sound != "wolf_distant" else _rng.randf_range(90.0, 160.0)
	var a := _rng.randf() * TAU
	var p := around + Vector3(cos(a) * dist, 6.0, sin(a) * dist)
	_one_shot(sound, p, -4.0 if sound != "wolf_distant" else 2.0, 12.0, 220.0, _rng.randf_range(0.92, 1.08))


func _one_shot(sound: String, pos: Vector3, volume: float, unit: float, max_dist: float, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = _lib.get_stream(sound)
	p.volume_db = volume
	p.unit_size = unit
	p.max_distance = max_dist
	p.pitch_scale = pitch
	world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _random_cave_point() -> Vector3:
	var keys: Array = cave.info["cells"].keys()
	var k: Vector2i = keys[_rng.randi_range(0, keys.size() - 1)]
	return cave.cell_center_world(k) + Vector3(0, 3.0, 0)


func _on_cave_entered() -> void:
	in_cave = true
	AudioServer.set_bus_effect_enabled(0, _reverb_idx, true)
	_tween_mood(cave_ambient_energy, cave_fog_energy, 0.0)


func _on_cave_exited() -> void:
	in_cave = false
	AudioServer.set_bus_effect_enabled(0, _reverb_idx, false)
	_tween_mood(_base_ambient, _base_fog_energy, _base_sky)


func _tween_mood(ambient: float, fog_energy: float, sky: float) -> void:
	var env := world.environment
	if _mood_tween:
		_mood_tween.kill()
	_mood_tween = create_tween().set_parallel()
	_mood_tween.tween_property(env, "ambient_light_energy", ambient, 1.2)
	_mood_tween.tween_property(env, "fog_light_energy", fog_energy, 1.2)
	_mood_tween.tween_property(env, "ambient_light_sky_contribution", sky, 1.2)
