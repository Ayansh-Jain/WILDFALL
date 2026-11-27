class_name Atmosphere
extends Node
## Atmosphere & Wind controller (Integration Contract C-14).
## Loads data-driven lighting/fog/grading/wind profiles from res://data/atmosphere/*.json
## and applies them smoothly across Environment, DirectionalLight3D, Sky, Water, and
## foliage/cloth materials.

signal profile_applied(profile_id: String)
signal wind_changed(direction: Vector2, strength: float, speed: float)

const PROFILE_DIR := "res://data/atmosphere/"
const WATER_MAT := preload("res://assets/materials/water.tres")
const FOLIAGE_CARD_MATS := [
	preload("res://assets/materials/leaves.tres"),
	preload("res://assets/materials/needles.tres"),
	preload("res://assets/materials/grass_card.tres"),
	preload("res://assets/materials/fern.tres"),
]
const LOWPOLY_MATS := [
	preload("res://assets/materials/foliage.tres"),
	preload("res://assets/materials/props.tres"),
]

static var instance: Atmosphere = null
static var wind_direction := Vector2(0.85, 0.52).normalized()
static var wind_strength := 1.0
static var wind_speed := 1.35
static var wind_gust := 0.42

var _current_id := ""
var _current_data: Dictionary = {}
var _profiles: Dictionary = {}
var _env: Environment
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _lamp_lights: Array[Light3D] = []
var _lamp_base_energy: Dictionary = {}
var _tween: Tween


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func bind_environment(p_env: Environment, p_sun: DirectionalLight3D, p_sky: ShaderMaterial = null) -> void:
	_env = p_env
	_sun = p_sun
	if p_sky:
		_sky_mat = p_sky
	elif _env and _env.sky and _env.sky.sky_material is ShaderMaterial:
		_sky_mat = _env.sky.sky_material as ShaderMaterial


func register_lamps(lamps: Array) -> void:
	_lamp_lights.clear()
	_lamp_base_energy.clear()
	for node in lamps:
		if node is Light3D:
			_lamp_lights.append(node)
			_lamp_base_energy[node.get_instance_id()] = node.light_energy


func current() -> String:
	return _current_id


func load_profile(profile_id: String) -> Dictionary:
	if _profiles.has(profile_id):
		return _profiles[profile_id]
	var path := "%s%s.json" % [PROFILE_DIR, profile_id]
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	_profiles[profile_id] = parsed
	return parsed


func apply(profile_id: String, fade_s: float = 1.0) -> Dictionary:
	var data := load_profile(profile_id)
	if data.is_empty():
		return {"ok": false, "reason": "unknown_profile", "data": {"id": profile_id}}
	if _tween and _tween.is_valid():
		_tween.kill()
	if fade_s <= 0.02 or _current_data.is_empty():
		_apply_dict(data)
	else:
		var from_data := _current_data.duplicate(true)
		_tween = create_tween()
		_tween.set_trans(Tween.TRANS_SINE)
		_tween.set_ease(Tween.EASE_IN_OUT)
		_tween.tween_method(func(t: float) -> void:
			_apply_dict(_lerp_profiles(from_data, data, t))
		, 0.0, 1.0, fade_s)
		_tween.finished.connect(func() -> void:
			_current_data = data.duplicate(true)
		)
	_current_id = profile_id
	_current_data = data.duplicate(true)
	profile_applied.emit(profile_id)
	return {"ok": true, "reason": "", "data": {"id": profile_id}}


static func get_wind_vector() -> Vector3:
	return Vector3(wind_direction.x, 0.0, wind_direction.y) * wind_strength


static func push_wind_to_materials(dir: Vector2, strength: float, speed: float, gust: float = 0.35) -> void:
	var n := dir.normalized() if dir.length_squared() > 0.0001 else Vector2(0.85, 0.52).normalized()
	wind_direction = n
	wind_strength = strength
	wind_speed = speed
	wind_gust = gust
	for mat in FOLIAGE_CARD_MATS:
		if mat:
			mat.set_shader_parameter("wind_dir", n)
			mat.set_shader_parameter("wind_speed", speed)
			mat.set_shader_parameter("gust_strength", gust * strength)
	for mat in LOWPOLY_MATS:
		if mat:
			mat.set_shader_parameter("wind_dir", n)
			mat.set_shader_parameter("wind_speed", speed)
	if instance:
		instance.wind_changed.emit(n, strength, speed)


func set_wind(dir: Vector2, strength: float, speed: float = 1.2, gust: float = 0.35) -> void:
	push_wind_to_materials(dir, strength, speed, gust)


func _apply_dict(d: Dictionary) -> void:
	var sun_d: Dictionary = d.get("sun", {})
	var amb_d: Dictionary = d.get("ambient", {})
	var sky_d: Dictionary = d.get("sky", {})
	var fog_d: Dictionary = d.get("fog", {})
	var grd_d: Dictionary = d.get("grading", {})
	var wat_d: Dictionary = d.get("water", {})
	var wnd_d: Dictionary = d.get("wind", {})

	var elev := float(sun_d.get("elevation_deg", 24.0))
	var azim := float(sun_d.get("azimuth_deg", 132.0))
	var sun_col := _col(sun_d.get("color", [1.0, 0.9, 0.72]))
	var sun_eng := float(sun_d.get("energy", 1.3))

	if _sun:
		_sun.rotation_degrees = Vector3(-elev, azim, 0.0)
		_sun.light_color = sun_col
		_sun.light_energy = sun_eng

	if _env:
		_env.ambient_light_color = _col(amb_d.get("color", [0.46, 0.57, 0.74]))
		_env.ambient_light_energy = float(amb_d.get("energy", 0.92))
		_env.ambient_light_sky_contribution = float(amb_d.get("sky_contribution", 0.4))
		_env.fog_enabled = bool(fog_d.get("enabled", true))
		_env.fog_light_color = _col(fog_d.get("color", [0.62, 0.68, 0.75]))
		_env.fog_light_energy = float(fog_d.get("energy", 0.95))
		_env.fog_density = float(fog_d.get("density", 0.00042))
		_env.fog_sky_affect = float(fog_d.get("sky_affect", 0.14))
		_env.fog_aerial_perspective = float(fog_d.get("aerial_perspective", 0.16))
		_env.fog_height = float(fog_d.get("height", 2.5))
		_env.fog_height_density = float(fog_d.get("height_density", 0.0022))
		_env.tonemap_exposure = float(grd_d.get("exposure", 1.04))
		_env.adjustment_enabled = true
		_env.adjustment_saturation = float(grd_d.get("saturation", 1.04))
		_env.adjustment_contrast = float(grd_d.get("contrast", 1.08))
		_env.glow_intensity = float(grd_d.get("glow_intensity", 0.35))
		_env.glow_hdr_threshold = float(grd_d.get("glow_threshold", 1.18))

	var zenith := _col(sky_d.get("zenith", [0.11, 0.30, 0.62]))
	var horizon := _col(sky_d.get("horizon", [0.68, 0.74, 0.80]))
	var celestial := _col(sky_d.get("celestial", [1.0, 0.92, 0.74]))
	var daylight := float(sky_d.get("daylight_factor", 1.0))

	if _sky_mat:
		_sky_mat.set_shader_parameter("zenith_color", zenith)
		_sky_mat.set_shader_parameter("horizon_color", horizon)
		_sky_mat.set_shader_parameter("ground_color", _col(sky_d.get("ground", [0.22, 0.23, 0.21])))
		_sky_mat.set_shader_parameter("celestial_color", celestial)
		_sky_mat.set_shader_parameter("cloud_dark", _col(sky_d.get("cloud_dark", [0.24, 0.30, 0.40])))
		_sky_mat.set_shader_parameter("cloud_lit", _col(sky_d.get("cloud_lit", [0.98, 0.92, 0.82])))
		_sky_mat.set_shader_parameter("cloud_cover", float(sky_d.get("cloud_cover", 0.56)))
		_sky_mat.set_shader_parameter("cloud_speed", float(sky_d.get("cloud_speed", 0.0028)))
		_sky_mat.set_shader_parameter("star_amount", float(sky_d.get("star_amount", 0.0)))
		_sky_mat.set_shader_parameter("daylight_factor", daylight)
		_sky_mat.set_shader_parameter("sun_glow", float(sky_d.get("sun_glow", 0.85)))
		_sky_mat.set_shader_parameter("moon_size", lerpf(0.99992, 0.99975, daylight))

	if WATER_MAT:
		WATER_MAT.set_shader_parameter("sky_zenith", zenith)
		WATER_MAT.set_shader_parameter("sky_horizon", horizon)
		WATER_MAT.set_shader_parameter("moon_color", celestial)
		WATER_MAT.set_shader_parameter("shallow_color", _col(wat_d.get("shallow", [0.06, 0.22, 0.21])))
		WATER_MAT.set_shader_parameter("deep_color", _col(wat_d.get("deep", [0.02, 0.09, 0.12])))
		if _sun:
			WATER_MAT.set_shader_parameter("moon_dir", _sun.global_transform.basis.z)

	var sun_fwd := Vector3(0.4, 0.5, 0.4).normalized()
	if _sun:
		sun_fwd = _sun.global_transform.basis.z
	for mat in FOLIAGE_CARD_MATS:
		if mat:
			mat.set_shader_parameter("sun_dir", sun_fwd)
			mat.set_shader_parameter("sun_color", sun_col)

	var dir_arr: Array = wnd_d.get("direction", [0.85, 0.52])
	push_wind_to_materials(
		Vector2(float(dir_arr[0]), float(dir_arr[1])),
		float(wnd_d.get("strength", 1.0)),
		float(wnd_d.get("speed", 1.35)),
		float(wnd_d.get("gust", 0.42))
	)

	var lamp_scale := float(d.get("night_lamps", 0.0))
	for light in _lamp_lights:
		if not is_instance_valid(light):
			continue
		var base := float(_lamp_base_energy.get(light.get_instance_id(), light.light_energy))
		light.light_energy = base * lamp_scale
		light.visible = lamp_scale > 0.02


static func _col(v) -> Color:
	if v is Color:
		return v
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
	return Color.WHITE


func _lerp_profiles(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in b:
		if a.has(k):
			var va = a[k]
			var vb = b[k]
			if va is Dictionary and vb is Dictionary:
				out[k] = _lerp_profiles(va, vb, t)
			elif va is Array and vb is Array and va.size() == vb.size():
				var arr := []
				for i in va.size():
					arr.append(lerpf(float(va[i]), float(vb[i]), t))
				out[k] = arr
			elif (va is float or va is int) and (vb is float or vb is int):
				out[k] = lerpf(float(va), float(vb), t)
			else:
				out[k] = vb
		else:
			out[k] = b[k]
	return out
