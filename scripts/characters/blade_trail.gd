class_name BladeTrail
extends MeshInstance3D
## A fading ribbon behind one sword while it cuts: each frame the blade's base and
## tip (world space) are recorded, and the last `lifetime` seconds are drawn as a
## strip whose alpha falls off with age. `active` is set by the rig during cuts; the
## ribbon drains away on its own after a cut ends.

var blade: Node3D
## Blade length from the grip along the sword's +Y axis (metres, before scale).
var length := 0.95
var active := false
var lifetime := 0.14
var color := Color(0.85, 0.9, 1.0, 0.55)

var sparks: GPUParticles3D
static var energy_material: ShaderMaterial
var _samples: Array = []  ## [time, base, tip]
var _time := 0.0
var _im := ImmediateMesh.new()


func _ready() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if color.r > 0.95 and color.g < 0.1 else BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	material_override = mat
	if color.r > 0.95 and color.g < 0.1:
		if energy_material == null:
			energy_material = ShaderMaterial.new()
			energy_material.shader = preload("res://assets/materials/crimson_trail.gdshader")
		material_override = energy_material
		sparks = GPUParticles3D.new()
		sparks.amount = 12
		sparks.lifetime = 0.22
		sparks.emitting = false
		sparks.local_coords = false
		sparks.visibility_aabb = AABB(Vector3(-3,-3,-3),Vector3(6,6,6))
		var particle := ParticleProcessMaterial.new()
		particle.direction = Vector3(0,1,0)
		particle.spread = 80
		particle.initial_velocity_min = 1.5
		particle.initial_velocity_max = 3.0
		particle.gravity = Vector3(0,-3,0)
		particle.scale_min = 0.4
		particle.scale_max = 1.0
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color(1,0.65,0.25),Color(1,0.08,0.01),Color(0.3,0,0,0)])
		gradient.offsets = PackedFloat32Array([0,0.35,1])
		var ramp := GradientTexture1D.new()
		ramp.gradient = gradient
		particle.color_ramp = ramp
		sparks.process_material = particle
		var ember := SphereMesh.new()
		ember.radius = 0.025
		ember.height = 0.05
		ember.radial_segments = 4
		ember.rings = 2
		ember.material = mat
		sparks.draw_pass_1 = ember
		# Sibling emitter drains after the ribbon mesh becomes invisible.
		get_parent().add_child.call_deferred(sparks)
	global_transform = Transform3D.IDENTITY


func sample_count() -> int:
	return _samples.size()


func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(sparks) and sparks.is_inside_tree():
		sparks.emitting = active and is_instance_valid(blade) and blade.is_visible_in_tree()
		if is_instance_valid(blade):
			sparks.global_position = blade.global_transform * Vector3(0,length,0)
	global_transform = Transform3D.IDENTITY
	if active and blade and is_instance_valid(blade) and blade.is_visible_in_tree():
		var xf := blade.global_transform
		_samples.append([_time, xf * Vector3(0, 0.12, 0), xf * Vector3(0, length, 0)])
	while not _samples.is_empty() and _time - float(_samples[0][0]) > lifetime:
		_samples.pop_front()
	_im.clear_surfaces()
	if _samples.size() < 2:
		visible = false
		return
	visible = true
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in _samples:
		var a := clampf(1.0 - (_time - float(s[0])) / lifetime, 0.0, 1.0)
		var c := Color(color.r, color.g, color.b, color.a * a * a)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(a,0))
		_im.surface_add_vertex(s[1])
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(a,1))
		_im.surface_add_vertex(s[2])
	_im.surface_end()
