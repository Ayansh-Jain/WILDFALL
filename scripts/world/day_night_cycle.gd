class_name DayNightCycle
extends Node
## Drives the world's single directional light, sky, water reflections, distant
## atmosphere and foliage sun-backlight through a continuous 24-hour cycle.
## Story code can freeze and temporarily set the hour.

signal phase_changed(phase_name: String, hour: float)

@export_group("Clock")
@export_range(60.0, 7200.0, 30.0, "or_greater") var cycle_duration_seconds := 1200.0
@export_range(0.0, 24.0, 0.1) var start_hour := 8.5
@export var start_automatically := true
@export_range(0.25, 12.0, 0.25) var story_blend_seconds := 3.0
@export_group("Performance")
@export_range(0.05, 1.0, 0.05) var lighting_update_interval := 0.1

const WATER_MATERIAL := preload("res://assets/materials/water.tres")
const DISTANT_MOUNTAIN_MAT := preload("res://assets/materials/distant_mountain.tres")
const FOLIAGE_MATS := [
	preload("res://assets/materials/leaves.tres"),
	preload("res://assets/materials/needles.tres"),
	preload("res://assets/materials/grass_card.tres"),
	preload("res://assets/materials/fern.tres"),
]

const KEYS := [
	{"hour": 0.0, "phase": "night", "elev": 18.0, "energy": 0.56, "day": 0.0, "night": 1.0,
		"light": Color(0.62, 0.74, 0.98), "ambient": 0.95, "ambient_color": Color(0.27, 0.35, 0.52), "sky_mix": 0.32,
		"zenith": Color(0.015, 0.032, 0.085), "horizon": Color(0.11, 0.16, 0.28), "ground": Color(0.03, 0.04, 0.065), "celestial": Color(0.86, 0.91, 1.0), "stars": 0.38, "fog": Color(0.11, 0.16, 0.26), "fog_energy": 0.82, "fog_density": 0.00056, "sun_glow": 0.28, "water_s": Color(0.025, 0.085, 0.12), "water_d": Color(0.01, 0.035, 0.065)},
	{"hour": 4.3, "phase": "pre_dawn", "elev": 4.0, "energy": 0.34, "day": 0.04, "night": 0.88,
		"light": Color(0.66, 0.72, 0.90), "ambient": 0.72, "ambient_color": Color(0.24, 0.28, 0.40), "sky_mix": 0.24,
		"zenith": Color(0.035, 0.058, 0.13), "horizon": Color(0.28, 0.24, 0.34), "ground": Color(0.05, 0.06, 0.09), "celestial": Color(0.80, 0.85, 0.98), "stars": 0.22, "fog": Color(0.21, 0.22, 0.31), "fog_energy": 0.86, "fog_density": 0.00068, "sun_glow": 0.40, "water_s": Color(0.03, 0.09, 0.13), "water_d": Color(0.015, 0.04, 0.07)},
	{"hour": 5.5, "phase": "dawn", "elev": 7.0, "energy": 0.68, "day": 0.36, "night": 0.42,
		"light": Color(1.0, 0.68, 0.44), "ambient": 0.80, "ambient_color": Color(0.40, 0.40, 0.48), "sky_mix": 0.34,
		"zenith": Color(0.11, 0.20, 0.39), "horizon": Color(0.90, 0.50, 0.34), "ground": Color(0.12, 0.14, 0.18), "celestial": Color(1.0, 0.78, 0.56), "stars": 0.03, "fog": Color(0.58, 0.42, 0.38), "fog_energy": 0.92, "fog_density": 0.00072, "sun_glow": 1.05, "water_s": Color(0.045, 0.14, 0.16), "water_d": Color(0.02, 0.06, 0.10)},
	{"hour": 8.5, "phase": "morning", "elev": 24.0, "energy": 1.32, "day": 0.90, "night": 0.0,
		"light": Color(1.0, 0.91, 0.74), "ambient": 0.94, "ambient_color": Color(0.46, 0.57, 0.74), "sky_mix": 0.44,
		"zenith": Color(0.11, 0.30, 0.62), "horizon": Color(0.68, 0.74, 0.80), "ground": Color(0.22, 0.23, 0.21), "celestial": Color(1.0, 0.92, 0.74), "stars": 0.0, "fog": Color(0.62, 0.68, 0.75), "fog_energy": 0.95, "fog_density": 0.00040, "sun_glow": 0.85, "water_s": Color(0.06, 0.22, 0.21), "water_d": Color(0.02, 0.09, 0.12)},
	{"hour": 12.0, "phase": "midday", "elev": 58.0, "energy": 1.38, "day": 1.0, "night": 0.0,
		"light": Color(1.0, 0.96, 0.88), "ambient": 1.02, "ambient_color": Color(0.52, 0.64, 0.79), "sky_mix": 0.48,
		"zenith": Color(0.10, 0.33, 0.70), "horizon": Color(0.62, 0.75, 0.86), "ground": Color(0.23, 0.27, 0.29), "celestial": Color(1.0, 0.97, 0.90), "stars": 0.0, "fog": Color(0.58, 0.68, 0.79), "fog_energy": 0.96, "fog_density": 0.00032, "sun_glow": 0.70, "water_s": Color(0.065, 0.24, 0.23), "water_d": Color(0.02, 0.10, 0.14)},
	{"hour": 15.5, "phase": "afternoon", "elev": 34.0, "energy": 1.28, "day": 0.92, "night": 0.0,
		"light": Color(1.0, 0.88, 0.69), "ambient": 0.96, "ambient_color": Color(0.50, 0.59, 0.74), "sky_mix": 0.45,
		"zenith": Color(0.11, 0.29, 0.62), "horizon": Color(0.70, 0.72, 0.76), "ground": Color(0.22, 0.24, 0.24), "celestial": Color(1.0, 0.88, 0.70), "stars": 0.0, "fog": Color(0.63, 0.66, 0.72), "fog_energy": 0.95, "fog_density": 0.00040, "sun_glow": 0.85, "water_s": Color(0.06, 0.21, 0.20), "water_d": Color(0.02, 0.09, 0.12)},
	{"hour": 17.2, "phase": "golden_hour", "elev": 14.0, "energy": 1.16, "day": 0.65, "night": 0.0,
		"light": Color(1.0, 0.60, 0.34), "ambient": 0.82, "ambient_color": Color(0.40, 0.40, 0.56), "sky_mix": 0.38,
		"zenith": Color(0.11, 0.19, 0.42), "horizon": Color(0.95, 0.48, 0.28), "ground": Color(0.17, 0.15, 0.17), "celestial": Color(1.0, 0.68, 0.38), "stars": 0.0, "fog": Color(0.72, 0.46, 0.36), "fog_energy": 0.90, "fog_density": 0.00054, "sun_glow": 1.25, "water_s": Color(0.05, 0.16, 0.17), "water_d": Color(0.02, 0.07, 0.11)},
	{"hour": 18.4, "phase": "sunset", "elev": 5.0, "energy": 0.72, "day": 0.30, "night": 0.18,
		"light": Color(1.0, 0.46, 0.28), "ambient": 0.76, "ambient_color": Color(0.38, 0.35, 0.48), "sky_mix": 0.32,
		"zenith": Color(0.14, 0.17, 0.36), "horizon": Color(0.92, 0.36, 0.30), "ground": Color(0.13, 0.12, 0.16), "celestial": Color(1.0, 0.58, 0.40), "stars": 0.02, "fog": Color(0.65, 0.38, 0.35), "fog_energy": 0.88, "fog_density": 0.00058, "sun_glow": 1.20, "water_s": Color(0.04, 0.13, 0.16), "water_d": Color(0.015, 0.05, 0.09)},
	{"hour": 19.5, "phase": "dusk", "elev": 4.0, "energy": 0.45, "day": 0.08, "night": 0.64,
		"light": Color(0.68, 0.72, 0.90), "ambient": 0.72, "ambient_color": Color(0.28, 0.32, 0.48), "sky_mix": 0.26,
		"zenith": Color(0.04, 0.09, 0.23), "horizon": Color(0.38, 0.26, 0.40), "ground": Color(0.07, 0.08, 0.13), "celestial": Color(0.78, 0.83, 1.0), "stars": 0.14, "fog": Color(0.28, 0.26, 0.38), "fog_energy": 0.85, "fog_density": 0.00062, "sun_glow": 0.45, "water_s": Color(0.03, 0.10, 0.14), "water_d": Color(0.012, 0.04, 0.08)},
	{"hour": 20.7, "phase": "night", "elev": 18.0, "energy": 0.56, "day": 0.0, "night": 1.0,
		"light": Color(0.62, 0.74, 0.98), "ambient": 0.95, "ambient_color": Color(0.27, 0.35, 0.52), "sky_mix": 0.32,
		"zenith": Color(0.015, 0.032, 0.085), "horizon": Color(0.11, 0.16, 0.28), "ground": Color(0.03, 0.04, 0.065), "celestial": Color(0.86, 0.91, 1.0), "stars": 0.38, "fog": Color(0.11, 0.16, 0.26), "fog_energy": 0.82, "fog_density": 0.00056, "sun_glow": 0.28, "water_s": Color(0.025, 0.085, 0.12), "water_d": Color(0.01, 0.035, 0.065)},
	{"hour": 24.0, "phase": "night", "elev": 18.0, "energy": 0.56, "day": 0.0, "night": 1.0,
		"light": Color(0.62, 0.74, 0.98), "ambient": 0.95, "ambient_color": Color(0.27, 0.35, 0.52), "sky_mix": 0.32,
		"zenith": Color(0.015, 0.032, 0.085), "horizon": Color(0.11, 0.16, 0.28), "ground": Color(0.03, 0.04, 0.065), "celestial": Color(0.86, 0.91, 1.0), "stars": 0.38, "fog": Color(0.11, 0.16, 0.26), "fog_energy": 0.82, "fog_density": 0.00056, "sun_glow": 0.28, "water_s": Color(0.025, 0.085, 0.12), "water_d": Color(0.01, 0.035, 0.065)},
]

var time_of_day := 8.5
var phase_name := "morning"
var daylight_strength := 0.90
var night_strength := 0.0
var override_active := false
var _override_hour := 8.5
var _override_target := 8.5
var _returning_to_clock := false
var _transition_seconds := 3.0
var _update_t := 0.0
var _lamp_scan_t := 0.0
var _lamps: Array[OmniLight3D] = []
var _lamp_energy: Dictionary = {}

@onready var world: World = get_parent() as World
@onready var sun: DirectionalLight3D = world.get_node("Moon") as DirectionalLight3D
@onready var env: Environment = (world.get_node("WorldEnvironment") as WorldEnvironment).environment
@onready var sky_material := env.sky.sky_material as ShaderMaterial


func _ready() -> void:
	process_priority = 100
	time_of_day = fposmod(start_hour, 24.0)
	_override_hour = time_of_day
	_override_target = time_of_day
	_transition_seconds = story_blend_seconds
	Atmosphere.push_wind_to_materials(Vector2(0.85, 0.52), 1.0, 1.35, 0.42)
	_apply_sample(_sample(time_of_day))


func _process(delta: float) -> void:
	if start_automatically:
		time_of_day = fposmod(time_of_day + 24.0 * delta / maxf(cycle_duration_seconds, 60.0), 24.0)
	if override_active or _returning_to_clock:
		var target := _override_target if override_active else time_of_day
		_override_hour = move_toward(_override_hour, _wrapped_target(target, _override_hour), delta * 24.0 / maxf(_transition_seconds, 0.25))
		if _returning_to_clock and absf(_wrapped_target(time_of_day, _override_hour) - _override_hour) < 0.02:
			_returning_to_clock = false
	else:
		_override_hour = time_of_day
	var display_hour := fposmod(_override_hour if override_active or _returning_to_clock else time_of_day, 24.0)
	_update_t += delta
	if _update_t >= lighting_update_interval:
		_update_t = 0.0
		_apply_sample(_sample(display_hour))
	_update_lamps(delta)
	var next_phase: String = _sample(display_hour)["phase"]
	if next_phase != phase_name:
		phase_name = next_phase
		phase_changed.emit(phase_name, display_hour)


func set_time_override(hour: float, blend_seconds := -1.0) -> void:
	var from_hour := get_hour()
	override_active = true
	_returning_to_clock = false
	_override_hour = from_hour
	_override_target = fposmod(hour, 24.0)
	_transition_seconds = story_blend_seconds if blend_seconds < 0.0 else maxf(blend_seconds, 0.25)


func clear_time_override(blend_seconds := -1.0) -> void:
	override_active = false
	_returning_to_clock = true
	_transition_seconds = story_blend_seconds if blend_seconds < 0.0 else maxf(blend_seconds, 0.25)


func advance_to_hour(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	if not override_active:
		_override_hour = time_of_day
		_returning_to_clock = false
	_update_t = lighting_update_interval
	_apply_sample(_sample(get_hour()))


func get_hour() -> float:
	return fposmod(_override_hour if override_active or _returning_to_clock else time_of_day, 24.0)


func _wrapped_target(target: float, current: float) -> float:
	var difference := fposmod(target - current + 12.0, 24.0) - 12.0
	return current + difference


func _sample(hour: float) -> Dictionary:
	var h := fposmod(hour, 24.0)
	for i in range(KEYS.size() - 1):
		var a: Dictionary = KEYS[i]
		var b: Dictionary = KEYS[i + 1]
		if h <= float(b["hour"]):
			var t := smoothstep(float(a["hour"]), float(b["hour"]), h)
			var out := {"phase": a["phase"] if t < 0.5 else b["phase"]}
			for key in ["elev", "energy", "day", "night", "ambient", "sky_mix", "fog_energy", "fog_density", "stars", "sun_glow"]:
				out[key] = lerpf(float(a[key]), float(b[key]), t)
			for key in ["light", "ambient_color", "zenith", "horizon", "ground", "celestial", "fog", "water_s", "water_d"]:
				out[key] = Color(a[key]).lerp(Color(b[key]), t)
			return out
	return KEYS[0].duplicate()


func _apply_sample(s: Dictionary) -> void:
	daylight_strength = float(s["day"])
	night_strength = float(s["night"])
	var azimuth := (get_hour() / 24.0) * 360.0 - 90.0
	var elevation := maxf(float(s["elev"]), 8.0)
	sun.rotation_degrees = Vector3(-90.0 + elevation, azimuth, 0.0)
	sun.light_color = s["light"]
	sun.light_energy = float(s["energy"])
	var overlay: Dictionary = {}
	var ambience := world.get_node_or_null("Ambience") as Ambience
	if ambience:
		overlay = ambience.environment_overlay()
	env.ambient_light_energy = float(s["ambient"]) * float(overlay.get("ambient", 1.0))
	env.ambient_light_color = Color(s["ambient_color"]) * Color(overlay.get("tint", Color.WHITE))
	env.ambient_light_sky_contribution = float(s["sky_mix"]) * float(overlay.get("sky", 1.0))
	env.fog_light_color = s["fog"]
	env.fog_light_energy = float(s["fog_energy"])
	env.fog_density = float(s["fog_density"]) * float(overlay.get("fog_density", 1.0))
	env.fog_aerial_perspective = lerpf(0.08, 0.18, daylight_strength)
	env.fog_height_density = 0.0026 * float(overlay.get("height", 1.0))
	env.adjustment_saturation = lerpf(0.94, 1.04, daylight_strength)
	env.adjustment_contrast = 1.08
	if sky_material:
		sky_material.set_shader_parameter("zenith_color", s["zenith"])
		sky_material.set_shader_parameter("horizon_color", s["horizon"])
		sky_material.set_shader_parameter("ground_color", s["ground"])
		sky_material.set_shader_parameter("celestial_color", s["celestial"])
		sky_material.set_shader_parameter("moon_size", lerpf(0.99992, 0.99976, daylight_strength))
		sky_material.set_shader_parameter("cloud_dark", Color(0.22, 0.27, 0.37).lerp(Color(0.045, 0.065, 0.115), night_strength))
		sky_material.set_shader_parameter("cloud_lit", Color(0.94, 0.89, 0.80).lerp(Color(0.36, 0.43, 0.58), night_strength))
		sky_material.set_shader_parameter("star_amount", float(s["stars"]))
		sky_material.set_shader_parameter("cloud_speed", 0.0024)
		sky_material.set_shader_parameter("cloud_cover", 0.56)
		sky_material.set_shader_parameter("daylight_factor", daylight_strength)
		sky_material.set_shader_parameter("sun_glow", float(s["sun_glow"]))
	var sun_fwd := sun.global_transform.basis.z
	WATER_MATERIAL.set_shader_parameter("moon_dir", sun_fwd)
	WATER_MATERIAL.set_shader_parameter("sky_zenith", s["zenith"])
	WATER_MATERIAL.set_shader_parameter("sky_horizon", s["horizon"])
	WATER_MATERIAL.set_shader_parameter("moon_color", s["celestial"])
	WATER_MATERIAL.set_shader_parameter("shallow_color", s["water_s"])
	WATER_MATERIAL.set_shader_parameter("deep_color", s["water_d"])
	if DISTANT_MOUNTAIN_MAT:
		DISTANT_MOUNTAIN_MAT.set_shader_parameter("haze_color", Color(s["fog"]).lerp(Color(s["horizon"]), 0.4))
		DISTANT_MOUNTAIN_MAT.set_shader_parameter("foothill_color", Color(0.15, 0.22, 0.14).lerp(Color(0.06, 0.09, 0.12), night_strength))
		DISTANT_MOUNTAIN_MAT.set_shader_parameter("ridge_color", Color(0.36, 0.39, 0.44).lerp(Color(0.18, 0.22, 0.30), night_strength))
	for mat in FOLIAGE_MATS:
		if mat:
			mat.set_shader_parameter("sun_dir", sun_fwd)
			mat.set_shader_parameter("sun_color", s["light"])


func _update_lamps(delta: float) -> void:
	_lamp_scan_t -= delta
	if _lamp_scan_t <= 0.0:
		_lamp_scan_t = 1.0
		_lamps.clear()
		for node in get_tree().get_nodes_in_group("day_night_lights"):
			if node is OmniLight3D:
				_lamps.append(node)
				var instance_id := node.get_instance_id()
				if not _lamp_energy.has(instance_id):
					_lamp_energy[instance_id] = node.light_energy
	for lamp in _lamps:
		if not is_instance_valid(lamp):
			continue
		var base := float(_lamp_energy.get(lamp.get_instance_id(), lamp.light_energy))
		var intensity := lerpf(0.0, 1.0, smoothstep(0.06, 0.52, night_strength))
		lamp.light_energy = base * intensity
		lamp.visible = intensity > 0.015
