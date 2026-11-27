extends Node3D
## One pooled multimesh flock crossing the sky at long, quiet intervals.
## Each bird is a three-triangle silhouette; wing motion is vertex-shader driven.

const FLOCK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

void vertex() {
	float side = COLOR.r;
	if (side > 0.25) {
		float cycle = fract(TIME * (1.15 + INSTANCE_CUSTOM.g * 0.35) + INSTANCE_CUSTOM.r);
		float flap = cycle < 0.35
			? mix(-0.55, 1.0, smoothstep(0.0, 0.35, cycle))
			: mix(1.0, -0.55, smoothstep(0.35, 1.0, cycle));
		float span = abs(VERTEX.z);
		float angle = flap * 1.05;
		VERTEX.y += sin(angle) * span;
		float wing_side = side < 0.75 ? -1.0 : 1.0;
		VERTEX.z = wing_side * cos(angle) * span;
	}
}

void fragment() {
	ALBEDO = vec3(0.025, 0.033, 0.045);
}
"""

const FORMATION := [
	Vector2(0.0, 0.0),
	Vector2(-5.0, -4.0), Vector2(-5.0, 4.0),
	Vector2(-10.0, -8.0), Vector2(-10.0, 8.0),
	Vector2(-15.0, 0.0),
]

@export_group("Flight")
@export_range(20.0, 120.0, 1.0) var quiet_interval_min := 42.0
@export_range(30.0, 180.0, 1.0) var quiet_interval_max := 92.0
@export_range(6.0, 20.0, 0.5) var flight_speed_min := 9.0
@export_range(6.0, 24.0, 0.5) var flight_speed_max := 13.0

var _rng := RandomNumberGenerator.new()
var _world: World
var _flock: MultiMeshInstance3D
var _multimesh: MultiMesh
var _material: ShaderMaterial
var _wait := 36.0
var _flying := false
var _progress := 0.0
var _speed := 10.0
var _distance := 260.0
var _start := Vector3.ZERO
var _direction := Vector3.RIGHT
var _side_axis := Vector3.FORWARD
var _altitude := 28.0
var _bird_data: Array[Dictionary] = []


func _ready() -> void:
	_world = get_parent() as World
	_rng.seed = GameState.world_seed * 104729 + 619
	_wait = _rng.randf_range(28.0, 58.0)
	_build_pool()


func _process(delta: float) -> void:
	if _flying:
		_advance_flock(delta)
		return
	_wait -= delta
	if _wait <= 0.0:
		_try_spawn_flock()


func _build_pool() -> void:
	var shader := Shader.new()
	shader.code = FLOCK_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = _make_bird_mesh()
	_multimesh.instance_count = FORMATION.size()
	_flock = MultiMeshInstance3D.new()
	_flock.name = "DistantFlock"
	_flock.multimesh = _multimesh
	_flock.material_override = _material
	_flock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flock.visibility_range_end = 280.0
	_flock.visible = false
	add_child(_flock)


func _make_bird_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	_add_triangle(vertices, colors, Vector3(-0.72, 0.0, -0.11), Vector3(0.76, 0.0, 0.0), Vector3(-0.72, 0.0, 0.11), 0.0)
	_add_triangle(vertices, colors, Vector3(-0.56, 0.0, 0.0), Vector3(-1.14, 0.0, -0.18), Vector3(-0.9, 0.0, 0.0), 0.0)
	_add_triangle(vertices, colors, Vector3(-0.56, 0.0, 0.0), Vector3(-0.9, 0.0, 0.0), Vector3(-1.14, 0.0, 0.18), 0.0)
	_add_triangle(vertices, colors, Vector3(0.1, 0.0, 0.0), Vector3(0.36, 0.0, -1.22), Vector3(-0.88, 0.0, -0.86), 0.5)
	_add_triangle(vertices, colors, Vector3(0.1, 0.0, 0.0), Vector3(-0.88, 0.0, 0.86), Vector3(0.36, 0.0, 1.22), 1.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_triangle(vertices: PackedVector3Array, colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, side: float) -> void:
	var marker := Color(side, 0.0, 0.0, 1.0)
	vertices.append_array([a, b, c])
	colors.append_array([marker, marker, marker])


func _try_spawn_flock() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		_wait = 4.0
		return
	var cycle := _world.get_node_or_null("DayNightCycle") as DayNightCycle
	if cycle and cycle.daylight_strength < 0.28:
		_wait = 8.0
		return

	var camera_right := camera.global_basis.x
	camera_right.y = 0.0
	if camera_right.length_squared() < 0.001:
		camera_right = Vector3.RIGHT
	camera_right = camera_right.normalized()
	var camera_forward := -camera.global_basis.z
	camera_forward.y = 0.0
	if camera_forward.length_squared() < 0.001:
		camera_forward = Vector3.FORWARD
	camera_forward = camera_forward.normalized()
	var direction_sign := -1.0 if _rng.randf() < 0.5 else 1.0
	_direction = camera_right * direction_sign
	_direction = Basis(Vector3.UP, _rng.randf_range(-0.075, 0.075)) * _direction
	_side_axis = camera_forward
	var view_size := get_viewport().get_visible_rect().size
	var aspect := view_size.x / maxf(view_size.y, 1.0)
	var forward_distance := _rng.randf_range(110.0, 150.0)
	var half_width := forward_distance * tan(deg_to_rad(camera.fov * 0.5)) * aspect
	_distance = half_width * 2.0 + 54.0
	_speed = _rng.randf_range(flight_speed_min, flight_speed_max)
	_altitude = _rng.randf_range(22.0, 31.0)
	_start = camera.global_position + camera_forward * forward_distance
	_start.y += _altitude
	_start -= _direction * (half_width + 28.0)
	_progress = 0.0
	_flying = true
	_flock.visible = true
	_bird_data.clear()
	var count := _rng.randi_range(4, FORMATION.size())
	_multimesh.instance_count = count
	for i in count:
		var data := {
			"formation": FORMATION[i],
			"phase": _rng.randf(),
			"flap": _rng.randf(),
			"scale": _rng.randf_range(0.88, 1.42),
			"yaw": _rng.randf_range(-0.055, 0.055),
			"bob": _rng.randf_range(0.0, TAU),
		}
		_bird_data.append(data)
		_multimesh.set_instance_custom_data(i, Color(data.phase, data.flap, 0.0, 0.0))
		_update_bird_transform(i, data, 0.0)


func _advance_flock(delta: float) -> void:
	_progress += _speed * delta / _distance
	if _progress >= 1.0:
		_flying = false
		_flock.visible = false
		_wait = _rng.randf_range(quiet_interval_min, quiet_interval_max)
		return
	for i in _bird_data.size():
		_update_bird_transform(i, _bird_data[i], _progress)


func _update_bird_transform(index: int, data: Dictionary, progress: float) -> void:
	var formation: Vector2 = data.formation
	var pos := _start + _direction * (progress * _distance + formation.x)
	pos += _side_axis * formation.y
	pos.y += sin(progress * TAU + data.bob) * 1.2 + formation.y * 0.12
	if _world and _world.terrain_data:
		pos.y = maxf(pos.y, _world.terrain_height(pos.x, pos.z) + 18.0)
	var heading := Basis(Vector3.UP, data.yaw) * _direction
	var x_axis := heading.normalized()
	var y_axis := Vector3.UP
	var z_axis := x_axis.cross(y_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	basis = basis * Basis(Vector3.RIGHT, sin(progress * TAU + data.phase * TAU) * 0.035)
	basis = basis.scaled(Vector3.ONE * data.scale)
	_multimesh.set_instance_transform(index, Transform3D(basis, pos))
