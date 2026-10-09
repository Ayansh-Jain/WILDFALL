class_name SightProbe
extends Node3D
## Developer tool: a floating "watcher" eye that continuously tests whether it
## can see a target body, drawing a ray to each sample point (green = blocked,
## red = visible). Drop one with the debug key, then hide behind something.

signal target_visibility_changed(visible: bool, fraction: float)

@export var target_height := 1.8
@export var eye_radius := 0.25

var target: PlayerController
var is_target_visible := false
var fraction := 0.0

var _eye_mat := StandardMaterial3D.new()
var _lines := ImmediateMesh.new()
var _line_mat := StandardMaterial3D.new()


func _ready() -> void:
	var eye := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = eye_radius
	sphere.height = eye_radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	eye.mesh = sphere
	_eye_mat.emission_enabled = true
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.material_override = _eye_mat
	add_child(eye)
	var lines := MeshInstance3D.new()
	lines.mesh = _lines
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	lines.material_override = _line_mat
	lines.top_level = true
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)


func _physics_process(_delta: float) -> void:
	if target == null:
		return
	var space := get_world_3d().direct_space_state
	var res := LineOfSight.can_see(space, global_position, Vector3.FORWARD, target.global_position,
			target.current_height(), {"exclude": [target.get_rid()]})
	fraction = res["fraction"]
	if res["visible"] != is_target_visible:
		is_target_visible = res["visible"]
		target_visibility_changed.emit(is_target_visible, fraction)
	var col := Color(1.0, 0.25, 0.2) if is_target_visible else Color(0.3, 1.0, 0.45)
	_eye_mat.albedo_color = col
	_eye_mat.emission = col
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in res["points"]:
		var seen: bool = res["clear_points"].has(p)
		_lines.surface_set_color(Color(1, 0.3, 0.2) if seen else Color(0.3, 1, 0.45, 0.6))
		_lines.surface_add_vertex(global_position)
		_lines.surface_add_vertex(p)
	_lines.surface_end()
