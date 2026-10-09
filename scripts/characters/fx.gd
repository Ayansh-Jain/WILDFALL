class_name Fx
extends RefCounted
## One-shot visual effects (bursts, rings, flashes, slashes, telegraphs).
## Each effect frees itself. Purely cosmetic: combat never depends on these.


static func _additive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	return m


static func _free_later(n: Node, seconds: float) -> void:
	# Bound to the node itself, so the connection vanishes if it was freed early.
	n.get_tree().create_timer(seconds, false).timeout.connect(n.queue_free)


static func burst(parent: Node, pos: Vector3, col: Color, amount := 24, speed := 3.0, size := 0.06, lifetime := 0.8, gravity := -4.0, spread := 180.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	parent.add_child(p)
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = _additive(col)
	p.mesh = mesh
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.emitting = true
	_free_later(p, lifetime + 0.5)
	return p


static func smoke(parent: Node, pos: Vector3, amount := 14, radius := 0.8, lifetime := 1.8, col := Color(0.1, 0.08, 0.08, 0.2)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	parent.add_child(p)
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = amount
	p.lifetime = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 60.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 1.2
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	mesh.material = m
	p.mesh = mesh
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = curve
	p.emitting = true
	_free_later(p, lifetime + 0.5)
	return p


## Expanding flat ring on the ground (roar shockwave, slam, ward).
static func ring(parent: Node, pos: Vector3, col: Color, max_radius: float, duration := 0.6, thickness := 0.25) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.0 - thickness
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 4
	var mat := _additive(col)
	mat.vertex_color_use_as_albedo = false
	torus.material = mat
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3(0.3, 0.2, 0.3)
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(max_radius, 0.4, max_radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	_free_later(mi, duration + 0.1)


static func flash(parent: Node, pos: Vector3, col: Color, energy := 3.0, light_range := 8.0, duration := 0.35) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = light_range
	parent.add_child(l)
	l.global_position = pos
	l.create_tween().tween_property(l, "light_energy", 0.0, duration)
	_free_later(l, duration + 0.05)


## A curved glowing ribbon (claw / sword slash) in `xform` space.
static func slash(parent: Node, xform: Transform3D, col: Color, radius := 1.6, arc_deg := 120.0, width := 0.25, duration := 0.22) -> void:
	var kit := MeshKit.new()
	var steps := 10
	var a0 := deg_to_rad(-arc_deg * 0.5)
	for i in steps:
		var t0 := a0 + deg_to_rad(arc_deg) * float(i) / steps
		var t1 := a0 + deg_to_rad(arc_deg) * float(i + 1) / steps
		var p0 := Vector3(sin(t0), 0, -cos(t0))
		var p1 := Vector3(sin(t1), 0, -cos(t1))
		var fade := float(i) / steps
		var c := Color(col.r, col.g, col.b, 0.25 + 0.75 * fade)
		kit.add_quad(p0 * (radius - width), p1 * (radius - width), p1 * radius, p0 * radius, c)
	var mi := MeshInstance3D.new()
	var mat := _additive(col)
	mi.mesh = kit.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_transform = xform
	mi.create_tween().tween_property(mat, "albedo_color:a", 0.0, duration)
	_free_later(mi, duration + 0.05)


## Ground warning sector for a wind-up (readable by every player nearby).
static func telegraph(parent: Node, origin: Vector3, yaw: float, hit_range: float, arc_deg: float, duration: float) -> MeshInstance3D:
	var kit := MeshKit.new()
	var steps := 12
	var a0 := deg_to_rad(-arc_deg * 0.5)
	var col := Color(1.0, 0.25, 0.1, 0.6)
	for i in steps:
		var t0 := a0 + deg_to_rad(arc_deg) * float(i) / steps
		var t1 := a0 + deg_to_rad(arc_deg) * float(i + 1) / steps
		kit.add_tri(Vector3.ZERO, Vector3(sin(t1), 0, -cos(t1)) * hit_range, Vector3(sin(t0), 0, -cos(t0)) * hit_range, col)
	var mi := MeshInstance3D.new()
	var mat := _additive(Color(1, 0.3, 0.1, 0.0))
	mi.mesh = kit.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = origin + Vector3.UP * 0.08
	mi.rotation.y = yaw
	mi.create_tween().tween_property(mat, "albedo_color:a", 0.55, duration)
	_free_later(mi, duration + 0.05)
	return mi
