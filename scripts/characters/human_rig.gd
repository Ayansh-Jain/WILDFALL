class_name HumanRig
extends CharacterRig
## "The Explorer": the body every player shows. Low-poly take on the reference
## sheet: dark hair, red scarf and hood, grey tunic with leather harness, belt
## pouches and lantern, backpack with bedroll, tattered cloak, bracers, boots
## and a short sword. 1.8 m tall.

const GLOW_WARM := preload("res://assets/materials/glow_warm.tres")

const SKIN := Color(0.62, 0.46, 0.37)
const HAIR := Color(0.09, 0.07, 0.06)
const TUNIC := Color(0.25, 0.26, 0.29)
const SLEEVE := Color(0.19, 0.19, 0.22)
const LEATHER := Color(0.38, 0.24, 0.14)
const LEATHER_DARK := Color(0.23, 0.14, 0.09)
const SCARF := Color(0.45, 0.07, 0.09)
const CLOAK := Color(0.21, 0.13, 0.12)
const TROUSERS := Color(0.15, 0.15, 0.17)
const BOOT := Color(0.33, 0.2, 0.12)
const GLOVE := Color(0.13, 0.1, 0.08)
const METAL := Color(0.58, 0.6, 0.63)
const BEDROLL := Color(0.42, 0.36, 0.27)


func _build() -> void:
	add_part("body", "", Vector3(0, 0.55, 0))
	add_part("hips", "body", Vector3(0, 0.4, 0))
	add_part("spine", "hips", Vector3(0, 0.1, 0))
	add_part("head", "spine", Vector3(0, 0.58, 0))
	for s in [-1.0, 1.0]:
		var side := "l" if s < 0 else "r"
		add_part("arm_" + side, "spine", Vector3(0.26 * s, 0.47, 0))
		add_part("forearm_" + side, "arm_" + side, Vector3(0, -0.29, 0))
		add_part("thigh_" + side, "hips", Vector3(0.11 * s, -0.02, 0))
		add_part("shin_" + side, "thigh_" + side, Vector3(0, -0.43, 0))

	var k := MeshKit.new(101, 0.06)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(0.36, 0.2, 0.23), TROUSERS)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)), Vector3(0.39, 0.07, 0.26), LEATHER_DARK)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, -0.135)), Vector3(0.07, 0.06, 0.02), METAL * 0.8)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.17, 0.0, -0.09)), Vector3(0.09, 0.11, 0.07), LEATHER)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.19, 0.0, 0.02)), Vector3(0.07, 0.12, 0.1), LEATHER)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(-0.24, -0.1, -0.05)), Vector3(0.07, 0.11, 0.07), LEATHER_DARK)
	k.add_box(Transform3D(Basis(Vector3.BACK, 0.35), Vector3(0.21, -0.22, 0.1)), Vector3(0.05, 0.62, 0.07), LEATHER_DARK)
	k.add_box(Transform3D(Basis(Vector3.BACK, 0.35), Vector3(0.31, 0.08, 0.1)), Vector3(0.12, 0.03, 0.05), METAL * 0.7)
	for i in 4:
		var x := -0.14 + i * 0.093
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(x, -0.16 - (i % 2) * 0.03, -0.11)), Vector3(0.085, 0.2 + (i % 2) * 0.06, 0.02), TUNIC * 0.85)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(x, -0.17 - ((i + 1) % 2) * 0.04, 0.11)), Vector3(0.085, 0.22 + ((i + 1) % 2) * 0.06, 0.02), TUNIC * 0.8)
	add_mesh("hips", k)
	var lantern := MeshKit.new(102)
	lantern.add_blob(Transform3D(Basis.IDENTITY, Vector3(-0.24, -0.1, -0.05)), 0.035, Color(1, 1, 1))
	add_mesh("hips", lantern, GLOW_WARM, false)

	k = MeshKit.new(103, 0.06)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), Vector3(0.4, 0.5, 0.23), TUNIC)
	for s in [-1.0, 1.0]:
		k.add_box(Transform3D(Basis(Vector3.BACK, 0.45 * s), Vector3(0, 0.27, -0.12)), Vector3(0.05, 0.6, 0.02), LEATHER)
		k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.2, 0.7, 1.1)), Vector3(0.23 * s, 0.47, 0)), 0.09, LEATHER_DARK)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), Vector3(0.3, 0.1, 0.27), SCARF)
	k.add_box(Transform3D(Basis(Vector3.BACK, 0.15), Vector3(0.07, 0.33, -0.135)), Vector3(0.1, 0.28, 0.04), SCARF * 0.9)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.51, 0.13)), Vector3(0.28, 0.15, 0.12), SCARF * 0.6)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0.2)), Vector3(0.32, 0.36, 0.17), LEATHER)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.41, 0.2)), Vector3(0.33, 0.08, 0.18), LEATHER_DARK)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0.29)), Vector3(0.18, 0.12, 0.04), LEATHER_DARK)
	k.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.21, 0.5, 0.2)), 0.07, 0.07, 0.42, 7, BEDROLL)
	for i in 5:
		var x := -0.17 + i * 0.085
		var l := 0.78 + 0.12 * sin(i * 2.3)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.45 - l * 0.5, 0.3)), Vector3(0.085, l, 0.02), CLOAK * (0.9 + 0.1 * (i % 2)))
	add_mesh("spine", k)

	k = MeshKit.new(104, 0.04)
	k.add_cylinder(Transform3D.IDENTITY, 0.05, 0.05, 0.08, 6, SKIN)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.18, 0)), Vector3(0.19, 0.23, 0.21), SKIN)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, -0.097)), Vector3(0.18, 0.07, 0.02), SKIN * 0.72)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.165, -0.11)), Vector3(0.03, 0.05, 0.03), SKIN * 0.95)
	for s in [-1.0, 1.0]:
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.045 * s, 0.2, -0.106)), Vector3(0.035, 0.016, 0.01), Color(0.05, 0.04, 0.04))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.045 * s, 0.225, -0.106)), Vector3(0.045, 0.014, 0.012), HAIR)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.1 * s, 0.2, 0.0)), Vector3(0.02, 0.1, 0.12), HAIR)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.31, 0.01)), Vector3(0.215, 0.09, 0.235), HAIR)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.22, 0.1)), Vector3(0.2, 0.17, 0.05), HAIR)
	k.add_box(Transform3D(Basis(Vector3.BACK, 0.3), Vector3(-0.04, 0.27, -0.11)), Vector3(0.08, 0.06, 0.03), HAIR)
	k.add_box(Transform3D(Basis(Vector3.BACK, -0.2), Vector3(0.05, 0.28, -0.11)), Vector3(0.07, 0.05, 0.03), HAIR)
	add_mesh("head", k)

	for s in [-1.0, 1.0]:
		var side := "l" if s < 0 else "r"
		k = MeshKit.new(110 + int(s), 0.05)
		cyl_down(k, Vector3.ZERO, 0.066, 0.056, 0.29, 6, SLEEVE)
		add_mesh("arm_" + side, k)
		k = MeshKit.new(120 + int(s), 0.05)
		cyl_down(k, Vector3.ZERO, 0.058, 0.052, 0.12, 6, SLEEVE)
		cyl_down(k, Vector3(0, -0.06, 0), 0.064, 0.058, 0.17, 6, LEATHER)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.28, 0)), Vector3(0.08, 0.1, 0.09), GLOVE)
		if s > 0:
			var grip := Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, -0.3, 0))
			k.add_box(grip * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.04)), Vector3(0.03, 0.03, 0.12), LEATHER_DARK)
			k.add_box(grip * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.11)), Vector3(0.16, 0.025, 0.03), METAL * 0.7)
			k.add_box(grip * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.44)), Vector3(0.045, 0.012, 0.62), METAL)
		add_mesh("forearm_" + side, k)
		k = MeshKit.new(130 + int(s), 0.05)
		cyl_down(k, Vector3.ZERO, 0.088, 0.07, 0.43, 6, TROUSERS)
		add_mesh("thigh_" + side, k)
		k = MeshKit.new(140 + int(s), 0.05)
		cyl_down(k, Vector3.ZERO, 0.066, 0.06, 0.24, 6, TROUSERS)
		cyl_down(k, Vector3(0, -0.2, 0), 0.082, 0.075, 0.26, 6, BOOT)
		k.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.24, 0)), 0.092, 0.092, 0.05, 6, BOOT * 0.75)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.46, -0.05)), Vector3(0.12, 0.08, 0.23), BOOT)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.34, -0.08)), Vector3(0.13, 0.025, 0.02), LEATHER_DARK)
		add_mesh("shin_" + side, k)


func _stride_rate() -> float:
	return 1.55


func _pose(_delta: float) -> void:
	var s := move_speed
	var run := smoothstep(5.5, 7.2, s)
	var a := clampf(s / 4.6, 0.0, 1.0) * 0.5 + run * 0.35
	var ph := _phase
	var p: Dictionary = parts
	if not grounded:
		_set_x("thigh_l", 0.6); _set_x("thigh_r", 0.3)
		_set_x("shin_l", -0.9); _set_x("shin_r", -0.6)
		p["arm_l"].rotation.z = -0.35; p["arm_r"].rotation.z = 0.35
	elif crouching:
		p["body"].position.y -= 0.3
		for side in ["l", "r"]:
			_set_x("thigh_" + side, 1.15 + (sin(ph) * a * 0.4 if side == "l" else -sin(ph) * a * 0.4))
			_set_x("shin_" + side, -1.7)
		_set_x("spine", -0.35)
		_set_x("arm_l", 0.35); _set_x("arm_r", 0.35)
	else:
		_set_x("thigh_l", sin(ph) * a)
		_set_x("thigh_r", -sin(ph) * a)
		_set_x("shin_l", -maxf(0.0, -cos(ph)) * a * 1.3)
		_set_x("shin_r", -maxf(0.0, cos(ph)) * a * 1.3)
		_set_x("arm_l", -sin(ph) * a * 0.8)
		_set_x("arm_r", sin(ph) * a * 0.8)
		_set_x("forearm_l", 0.25 + run * 0.9)
		_set_x("forearm_r", 0.35 + run * 0.9)
		_set_x("spine", -run * 0.22 + sin(_time * 1.6) * 0.02)
		p["body"].position.y -= absf(sin(ph)) * 0.04 * a
		p["head"].rotation.y = sin(_time * 0.4) * 0.15 * (1.0 - a)

	var t := one_shot_p()
	match _one_shot:
		"attack":
			if t < 0.35:
				_set_x("arm_r", 2.4 * (t / 0.35))
			else:
				_set_x("arm_r", lerpf(2.4, 0.3, clampf((t - 0.35) / 0.25, 0.0, 1.0)))
			p["spine"].rotation.y = lerpf(0.35, -0.35, t)
			_set_x("forearm_r", 0.6)
		"dodge":
			p["body"].rotation.x = -TAU * t
			p["body"].position.y -= 0.25 * bell(t)
			for side in ["l", "r"]:
				_set_x("thigh_" + side, 1.4 * bell(t))
				_set_x("shin_" + side, -1.8 * bell(t))
				_set_x("arm_" + side, 1.0 * bell(t))
		"ward":
			_set_x("arm_l", 1.5 * bell(t)); _set_x("arm_r", 1.5 * bell(t))
			_set_x("spine", 0.12 * bell(t))
		"hurt", "stagger":
			_set_x("spine", 0.35 * (1.0 - t))
			_set_x("head", 0.25 * (1.0 - t))
			p["arm_l"].rotation.z = -0.35 * (1.0 - t); p["arm_r"].rotation.z = 0.35 * (1.0 - t)
	if _hold == "defeat":
		var d := clampf(_hold_t / 0.7, 0.0, 1.0)
		p["body"].rotation.x = 1.45 * d
		p["body"].position.y = lerpf(p["body"].position.y, 0.18, d)
		p["arm_l"].rotation.z = -1.0 * d; p["arm_r"].rotation.z = 1.0 * d


func _set_x(part_name: String, x: float) -> void:
	parts[part_name].rotation.x = _rest_rot[part_name].x + x
