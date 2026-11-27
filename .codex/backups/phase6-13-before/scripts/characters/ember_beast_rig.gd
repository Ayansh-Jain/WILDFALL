class_name EmberBeastRig
extends CharacterRig
## The Ember Beast, after the reference sheet: a hunched volcanic brute with
## charcoal armour plates, glowing ember cracks, burning eyes and mouth, swept
## horns, spiked back and tail, and long red claws. Ember sparks and dark smoke
## drift off it while revealed. About 3 m tall.

const GLOW_EMBER := preload("res://assets/materials/glow_ember.tres")
const GLOW_EYES := preload("res://assets/materials/glow_beacon.tres")

const CHAR := Color(0.2, 0.17, 0.18)
const CHAR2 := Color(0.29, 0.22, 0.22)
const MAROON := Color(0.42, 0.09, 0.1)
const CLAW := Color(0.62, 0.12, 0.08)
const BONE := Color(0.78, 0.66, 0.52)

var light: OmniLight3D
var embers: CPUParticles3D
var smoke: CPUParticles3D
## 0..1 extra glow while winding up a heavy strike.
var charge := 0.0


func _build() -> void:
	scale = Vector3.ONE * 1.15
	add_part("body", "", Vector3(0, 1.25, 0))
	add_part("chest", "body", Vector3(0, 0.15, 0), Vector3(-0.55, 0, 0))
	add_part("head", "chest", Vector3(0, 0.95, -0.35), Vector3(0.55, 0, 0))
	add_part("jaw", "head", Vector3(0, -0.06, -0.15))
	for s in [-1.0, 1.0]:
		var side := "l" if s < 0 else "r"
		add_part("arm_" + side, "chest", Vector3(0.68 * s, 0.72, -0.05), Vector3(0.55, 0, 0.15 * s))
		add_part("forearm_" + side, "arm_" + side, Vector3(0, -0.7, 0), Vector3(0.35, 0, 0))
		add_part("hand_" + side, "forearm_" + side, Vector3(0, -0.62, 0), Vector3(0.2, 0, 0))
		add_part("thigh_" + side, "body", Vector3(0.34 * s, -0.05, 0.05), Vector3(0.45, 0, 0))
		add_part("shin_" + side, "thigh_" + side, Vector3(0, -0.62, 0), Vector3(-0.95, 0, 0))
		add_part("foot_" + side, "shin_" + side, Vector3(0, -0.6, 0), Vector3(0.5, 0, 0))
	var prev := "body"
	var curl := [1.95, -0.15, -0.2, -0.25, -0.3, -0.3]
	for i in 6:
		var n := "tail%d" % i
		add_part(n, prev, Vector3(0, 0.05, 0.45) if i == 0 else Vector3(0, 0.42, 0), Vector3(curl[i], 0, 0))
		prev = n

	var k := MeshKit.new(201, 0.1)
	var g := MeshKit.new(202)
	k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.25, 0.75, 1.05)), Vector3(0, 0, 0.05)), 0.42, CHAR, true, 0.22)
	k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 0.2, 0.3)), Vector3(0.5, 0.12, 0.35), CHAR2)
	add_mesh("body", k)

	# Chest: massive hunched torso, plates, ember cracks, back spikes.
	k = MeshKit.new(203, 0.12)
	g = MeshKit.new(204)
	k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.45, 1.15, 1.1)), Vector3(0, 0.5, 0)), 0.55, CHAR, true, 0.25)
	k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.1, 1.2, 0.6)), Vector3(0, 0.35, -0.27)), 0.35, CHAR2, false, 0.2)
	for i in 7:
		var a := -1.2 + i * 0.4
		k.add_box(Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.4), Vector3(sin(a) * 0.5, 0.82 + 0.05 * (i % 2), 0.1 + cos(a) * 0.15)), Vector3(0.32, 0.12, 0.38), MAROON if i % 3 == 0 else CHAR2)
	for i in 6:
		var y := 0.25 + i * 0.13
		spike(k, Vector3(0, y, 0.45 - i * 0.02), Vector3(0, 0.55, 1.0), 0.32 + 0.1 * sin(i * 1.3 + 1.0) + 0.12, 0.1, CHAR, 5)
		spike(g, Vector3(0, y + 0.18, 0.75), Vector3(0, 0.55, 1.0), 0.08, 0.03, Color(1, 0.6, 0.3), 4)
	for crack in [[Vector3(-0.25, 0.45, -0.42), 0.4], [Vector3(0.18, 0.6, -0.43), -0.5], [Vector3(0.05, 0.25, -0.4), 0.9],
			[Vector3(-0.55, 0.55, -0.15), 0.2], [Vector3(0.55, 0.45, -0.18), -0.3], [Vector3(0.3, 0.8, -0.3), 1.2]]:
		g.add_box(Transform3D(Basis(Vector3.BACK, crack[1]), crack[0]), Vector3(0.018, 0.24, 0.02), Color(1, 1, 1))
	add_mesh("chest", k)
	add_mesh("chest", g, GLOW_EMBER, false)

	# Head: wedge skull, brow, snout, horns, burning eyes and mouth.
	k = MeshKit.new(205, 0.1)
	g = MeshKit.new(206)
	var eyes := MeshKit.new(207)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -0.12)), Vector3(0.44, 0.34, 0.46), CHAR)
	k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.24, -0.33)), Vector3(0.5, 0.1, 0.15), CHAR2)
	k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(0, 0.04, -0.5)), Vector3(0.3, 0.2, 0.36), CHAR)
	k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.16, -0.5)), Vector3(0.18, 0.06, 0.3), CHAR2)
	for s in [-1.0, 1.0]:
		spike(k, Vector3(0.17 * s, 0.26, -0.05), Vector3(0.35 * s, 0.6, 1.0), 0.7, 0.085, CHAR2, 6)
		spike(k, Vector3(0.22 * s, 0.1, 0.02), Vector3(0.9 * s, 0.1, 0.6), 0.35, 0.06, CHAR, 5)
		spike(k, Vector3(0.12 * s, 0.32, 0.12), Vector3(0.2 * s, 1.0, 0.6), 0.25, 0.05, MAROON, 4)
		eyes.add_box(Transform3D(Basis(Vector3.BACK, 0.25 * s), Vector3(0.12 * s, 0.14, -0.36)), Vector3(0.08, 0.035, 0.02), Color(1, 1, 1))
		for t in 3:
			spike(k, Vector3((0.05 + t * 0.045) * s, -0.06, -0.62 + t * 0.06), Vector3.DOWN, 0.07, 0.018, BONE, 4)
	g.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.07, -0.42)), Vector3(0.16, 0.03, 0.22), Color(1, 0.55, 0.35))
	add_mesh("head", k)
	add_mesh("head", g, GLOW_EMBER, false)
	add_mesh("head", eyes, GLOW_EYES, false)
	k = MeshKit.new(208, 0.08)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.06, -0.28)), Vector3(0.28, 0.09, 0.42), CHAR2)
	for s in [-1.0, 1.0]:
		for t in 3:
			spike(k, Vector3((0.05 + t * 0.04) * s, -0.01, -0.45 + t * 0.07), Vector3.UP, 0.06, 0.016, BONE, 4)
	add_mesh("jaw", k)

	for s in [-1.0, 1.0]:
		var side := "l" if s < 0 else "r"
		k = MeshKit.new(210 + int(s), 0.1)
		g = MeshKit.new(212 + int(s))
		k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.2, 0.8, 1.1)), Vector3(0, 0.02, 0)), 0.3, CHAR2, false, 0.25)
		spike(k, Vector3(0.12 * s, 0.18, 0.05), Vector3(0.6 * s, 1.0, 0.3), 0.32, 0.07, CHAR, 5)
		spike(k, Vector3(0.22 * s, 0.05, 0.1), Vector3(1.0 * s, 0.5, 0.3), 0.24, 0.06, MAROON, 4)
		cyl_down(k, Vector3.ZERO, 0.21, 0.17, 0.7, 7, CHAR)
		g.add_box(Transform3D(Basis(Vector3.FORWARD, 0.2 * s), Vector3(0.05 * s, -0.35, -0.19)), Vector3(0.016, 0.26, 0.02), Color(1, 1, 1))
		add_mesh("arm_" + side, k)
		add_mesh("arm_" + side, g, GLOW_EMBER, false)
		k = MeshKit.new(214 + int(s), 0.1)
		g = MeshKit.new(216 + int(s))
		cyl_down(k, Vector3.ZERO, 0.19, 0.15, 0.62, 7, CHAR)
		for i in 3:
			spike(k, Vector3(0.14 * s, -0.12 - i * 0.18, 0.06), Vector3(0.8 * s, 0.4, 0.6), 0.2, 0.05, CHAR2, 4)
		g.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.02 * s, -0.3, -0.16)), Vector3(0.016, 0.3, 0.02), Color(1, 1, 1))
		add_mesh("forearm_" + side, k)
		add_mesh("forearm_" + side, g, GLOW_EMBER, false)
		k = MeshKit.new(218 + int(s), 0.08)
		g = MeshKit.new(220 + int(s))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.06, -0.04)), Vector3(0.26, 0.14, 0.27), CHAR2)
		for c in 4:
			var x := (c - 1.5) * 0.065
			spike(k, Vector3(x, -0.1, -0.14), Vector3(0, -0.6, -1.0), 0.38, 0.035, CLAW, 4)
			spike(g, Vector3(x, -0.3, -0.45), Vector3(0, -0.6, -1.0), 0.06, 0.016, Color(1, 0.7, 0.5), 4)
		add_mesh("hand_" + side, k)
		add_mesh("hand_" + side, g, GLOW_EMBER, false)
		k = MeshKit.new(222 + int(s), 0.1)
		cyl_down(k, Vector3.ZERO, 0.22, 0.16, 0.62, 7, CHAR2)
		k.add_blob(Transform3D(Basis.IDENTITY, Vector3(0, -0.6, -0.06)), 0.14, CHAR, false, 0.2)
		spike(k, Vector3(0, -0.6, -0.15), Vector3(0, 0.3, -1.0), 0.18, 0.05, CHAR2, 4)
		add_mesh("thigh_" + side, k)
		k = MeshKit.new(224 + int(s), 0.1)
		g = MeshKit.new(226 + int(s))
		cyl_down(k, Vector3.ZERO, 0.16, 0.11, 0.6, 6, CHAR)
		g.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.3, -0.13)), Vector3(0.016, 0.26, 0.02), Color(1, 1, 1))
		add_mesh("shin_" + side, k)
		add_mesh("shin_" + side, g, GLOW_EMBER, false)
		k = MeshKit.new(228 + int(s), 0.08)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.04, -0.12)), Vector3(0.26, 0.12, 0.34), CHAR2)
		for c in 3:
			spike(k, Vector3((c - 1) * 0.08, -0.06, -0.28), Vector3(0, -0.2, -1.0), 0.18, 0.04, CLAW, 4)
		add_mesh("foot_" + side, k)

	for i in 6:
		k = MeshKit.new(240 + i, 0.08)
		g = MeshKit.new(250 + i)
		var r0 := 0.2 - i * 0.03
		k.add_cylinder(Transform3D.IDENTITY, r0, r0 - 0.03, 0.44, 6, CHAR if i % 2 == 0 else CHAR2)
		spike(k, Vector3(0, 0.2, -r0 * 0.8), Vector3(0, 0.4, -1.0), 0.22 - i * 0.02, 0.05, CHAR2, 4)
		g.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.22, r0 * 0.85)), Vector3(0.016, 0.24, 0.016), Color(1, 1, 1))
		add_mesh("tail%d" % i, k)
		add_mesh("tail%d" % i, g, GLOW_EMBER, false)

	_build_fx()


func _build_fx() -> void:
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.42, 0.15)
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = Vector3(0, 1.5, -1.1)
	add_child(light)
	embers = CPUParticles3D.new()
	embers.amount = 40
	embers.lifetime = 2.2
	embers.position = Vector3(0, 1.5, 0)
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(0.7, 0.9, 0.9)
	embers.direction = Vector3.UP
	embers.spread = 40.0
	embers.gravity = Vector3(0, 0.6, 0)
	embers.initial_velocity_min = 0.2
	embers.initial_velocity_max = 0.8
	var em := BoxMesh.new()
	em.size = Vector3.ONE * 0.03
	em.material = GLOW_EMBER
	embers.mesh = em
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(1, 0))
	embers.scale_amount_curve = fade
	add_child(embers)
	smoke = CPUParticles3D.new()
	smoke.amount = 10
	smoke.lifetime = 2.8
	smoke.position = Vector3(0, 1.0, 0.1)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.8
	smoke.direction = Vector3.UP
	smoke.spread = 50.0
	smoke.gravity = Vector3(0, 0.25, 0)
	smoke.initial_velocity_min = 0.1
	smoke.initial_velocity_max = 0.4
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.09, 0.06, 0.06, 0.16)
	sm.material = smat
	smoke.mesh = sm
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 1.8))
	smoke.scale_amount_curve = grow
	add_child(smoke)


func _apply_shadow_mode() -> void:
	super._apply_shadow_mode()
	# The local player keeps the ember light but not the smoke filling the camera.
	if light:
		light.visible = true
	if smoke:
		smoke.visible = not shadow_only
	if embers:
		embers.visible = not shadow_only


func _stride_rate() -> float:
	return 1.1


func _pose(_delta: float) -> void:
	var s := move_speed
	var run := smoothstep(5.5, 8.0, s)
	var a := clampf(s / 5.0, 0.0, 1.0) * 0.5 + run * 0.2
	var ph := _phase
	var p: Dictionary = parts
	_add_x("thigh_l", sin(ph) * a)
	_add_x("thigh_r", -sin(ph) * a)
	_add_x("shin_l", -maxf(0.0, cos(ph)) * a * 0.8)
	_add_x("shin_r", -maxf(0.0, -cos(ph)) * a * 0.8)
	_add_x("arm_l", -sin(ph) * a * 0.9 + run * 0.6)
	_add_x("arm_r", sin(ph) * a * 0.9 + run * 0.6)
	_add_x("chest", -run * 0.25 + sin(_time * 1.8) * 0.03)
	_add_x("jaw", 0.08 + 0.05 * sin(_time * 1.8))
	p["body"].position.y -= absf(sin(ph)) * 0.06 * a
	p["head"].rotation.y = sin(_time * 0.5) * 0.15 * (1.0 - a)
	for i in 6:
		p["tail%d" % i].rotation.y = sin(_time * 1.4 - i * 0.5) * 0.12 * (1.0 + run)
	if not grounded and _hold != "leap":
		_add_x("thigh_l", 0.4); _add_x("thigh_r", 0.2)

	var t := one_shot_p()
	match _one_shot:
		"claw":
			if t < 0.35:
				var w := t / 0.35
				_add_x("arm_r", 1.6 * w)
				p["arm_r"].rotation.z += 0.8 * w
				p["chest"].rotation.y += 0.3 * w
			else:
				var w := clampf((t - 0.35) / 0.25, 0.0, 1.0)
				_add_x("arm_r", lerpf(1.6, -0.2, w) * (1.0 - clampf((t - 0.7) / 0.3, 0.0, 1.0)))
				p["arm_r"].rotation.z += lerpf(0.8, -0.5, w)
				p["chest"].rotation.y += lerpf(0.3, -0.35, w)
		"heavy_slam":
			var w := clampf(t / 0.3, 0.0, 1.0)
			var back := 1.0 - clampf((t - 0.5) / 0.5, 0.0, 1.0)
			_add_x("arm_l", lerpf(2.6, -0.3, w) * back)
			_add_x("arm_r", lerpf(2.6, -0.3, w) * back)
			_add_x("chest", -0.35 * w * back)
			p["body"].position.y -= 0.15 * w * back
		"roar":
			var w := clampf(t / 0.25, 0.0, 1.0) * (1.0 - clampf((t - 0.8) / 0.2, 0.0, 1.0))
			_add_x("head", 0.6 * w)
			_add_x("jaw", 0.55 * w)
			p["arm_l"].rotation.z -= 0.7 * w
			p["arm_r"].rotation.z += 0.7 * w
			_add_x("arm_l", -0.3 * w); _add_x("arm_r", -0.3 * w)
			_add_x("chest", 0.25 * w)
		"transform":
			var w := bell(t)
			_add_x("head", 0.5 * w)
			_add_x("jaw", 0.6 * w)
			p["arm_l"].rotation.z -= 0.9 * w
			p["arm_r"].rotation.z += 0.9 * w
			_add_x("chest", 0.3 * w)
		"hurt", "stagger":
			_add_x("chest", 0.3 * (1.0 - t))
			_add_x("head", 0.2 * (1.0 - t))
	match _hold:
		"heavy_windup":
			var w := hold_p()
			_add_x("arm_l", 2.6 * w); _add_x("arm_r", 2.6 * w)
			_add_x("chest", 0.35 * w)
			_add_x("head", -0.2 * w)
		"pounce_windup":
			var w := hold_p()
			p["body"].position.y -= 0.25 * w
			_add_x("thigh_l", 0.4 * w); _add_x("thigh_r", 0.4 * w)
			_add_x("shin_l", -0.5 * w); _add_x("shin_r", -0.5 * w)
			_add_x("chest", -0.2 * w)
		"leap":
			_add_x("arm_l", 1.3); _add_x("arm_r", 1.3)
			_add_x("thigh_l", -0.5); _add_x("thigh_r", -0.4)
			_add_x("chest", -0.15)
			for i in 3:
				_add_x("tail%d" % i, -0.15)
		"defeat":
			var d := clampf(_hold_t / 1.0, 0.0, 1.0)
			p["body"].position.y = lerpf(p["body"].position.y, 0.55, d)
			p["body"].rotation.z = 1.35 * d
			_add_x("jaw", 0.4 * d)
	var glow := 1.0 + charge * 1.5 + (0.6 if _one_shot == "roar" else 0.0)
	light.light_energy = (1.6 + 0.25 * sin(_time * 7.0)) * glow


func _add_x(part_name: String, x: float) -> void:
	parts[part_name].rotation.x += x
