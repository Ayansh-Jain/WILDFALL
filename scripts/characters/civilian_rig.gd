class_name CivilianRig
extends CharacterRig
## Non-combat story characters in the same low-poly language as HumanRig:
## "queen" (gown, fur-collared cloak, braided hair, thin circlet), "elder"
## (hunched, headscarf, shawl and apron) and "child" (tunic and trousers).
## Faces -Z like the other rigs. Poses: idle, "gaze" (looking up at the sky),
## "worried" (hands at the chest) and a "talk" gesture via play("talk", t).

const CASTLE_PROPS_MAT := preload("res://assets/materials/castle_props.tres")
const CLOTH := 0.3

var style := "queen"


func _cloth(c: Color) -> Color:
	return Color(c.r, c.g, c.b, CLOTH)


func _build() -> void:
	var s := {"queen": 0.96, "elder": 0.88, "child": 0.66}.get(style, 1.0) as float
	scale = Vector3.ONE * s
	var skin := Color(0.78, 0.62, 0.53) if style == "queen" else (Color(0.66, 0.5, 0.42) if style == "elder" else Color(0.74, 0.57, 0.47))
	var hair := {"queen": Color(0.3, 0.12, 0.06), "elder": Color(0.62, 0.6, 0.57), "child": Color(0.36, 0.25, 0.14)}[style] as Color
	var dress := {"queen": Color(0.11, 0.12, 0.19), "elder": Color(0.24, 0.26, 0.21), "child": Color(0.5, 0.38, 0.18)}[style] as Color
	var over := {"queen": Color(0.07, 0.065, 0.075), "elder": Color(0.33, 0.24, 0.16), "child": Color(0.27, 0.19, 0.12)}[style] as Color
	var trim := Color(0.62, 0.62, 0.64) if style == "queen" else Color(0.55, 0.5, 0.42)

	add_part("body", "", Vector3(0, 0.0, 0))
	add_part("hips", "body", Vector3(0, 0.95, 0))
	add_part("spine", "hips", Vector3(0, 0.05, 0))
	add_part("head", "spine", Vector3(0, 0.56, 0))
	for sd in [-1.0, 1.0]:
		var side := "l" if sd < 0 else "r"
		add_part("arm_" + side, "spine", Vector3(0.21 * sd, 0.46, 0))
		add_part("forearm_" + side, "arm_" + side, Vector3(0, -0.27, 0))

	# Lower body: a long skirt for the queen and the elder, legs for the child.
	var k := MeshKit.new(301, 0.04)
	if style == "child":
		for sd in [-1.0, 1.0]:
			CharacterRig.cyl_down(k, Vector3(0.09 * sd, 0.95, 0), 0.08, 0.06, 0.82, 6, Color(0.3, 0.22, 0.15))
			k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.09 * sd, 0.07, -0.04)), Vector3(0.1, 0.12, 0.2), Color(0.25, 0.16, 0.1))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.88, 0)), Vector3(0.36, 0.26, 0.24), _cloth(dress))
	else:
		k.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0)), 0.36 if style == "queen" else 0.3, 0.17, 0.97, 10, _cloth(dress))
		k.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0)), 0.365 if style == "queen" else 0.305, 0.36 if style == "queen" else 0.3, 0.06, 10, _cloth(trim * 0.8))
		if style == "elder":
			k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.06), Vector3(0, 0.5, -0.22)), Vector3(0.34, 0.8, 0.03), _cloth(Color(0.58, 0.54, 0.46)))
	add_mesh("body", k, CASTLE_PROPS_MAT)

	# Torso, collar and outer garment.
	k = MeshKit.new(302, 0.04)
	var tw := 0.34 if style != "child" else 0.3
	k.add_cylinder(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.7)), Vector3(0, -0.05, 0)), tw * 0.5, tw * 0.6, 0.55, 8, _cloth(dress))
	if style == "queen":
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.12, -0.12)), Vector3(0.05, 0.36, 0.02), _cloth(trim))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), Vector3(tw + 0.02, 0.05, 0.25), _cloth(trim * 0.9))
		# Cloak falling from the shoulders to the floor, with a fur collar.
		for i in 7:
			var x := -0.24 + float(i) * 0.08
			var l := 1.42 + 0.04 * sin(float(i) * 1.7)
			k.add_box(Transform3D(Basis(Vector3.RIGHT, -0.05), Vector3(x, 0.48 - l * 0.5, 0.15 + absf(x) * 0.15)), Vector3(0.085, l, 0.03), _cloth(over * (0.9 + 0.1 * float(i % 2))))
		k.add_cylinder(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.82)), Vector3(0, 0.42, 0.02)), 0.24, 0.13, 0.13, 10, _cloth(Color(0.42, 0.39, 0.35)))
	elif style == "elder":
		k.add_cylinder(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.8)), Vector3(0, 0.18, 0.0)), 0.26, 0.14, 0.32, 9, _cloth(over))
		k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.1, -0.16)), Vector3(0.12, 0.2, 0.03), _cloth(over * 0.85))
	else:
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0)), Vector3(tw + 0.03, 0.05, 0.22), _cloth(Color(0.3, 0.2, 0.12)))
	add_mesh("spine", k, CASTLE_PROPS_MAT)

	# Head, face and hair.
	k = MeshKit.new(303, 0.03)
	k.add_cylinder(Transform3D.IDENTITY, 0.045, 0.045, 0.07, 6, skin)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.16, 0)), Vector3(0.17, 0.21, 0.19), skin)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.145, -0.1)), Vector3(0.028, 0.045, 0.03), skin * 0.95)
	for sd in [-1.0, 1.0]:
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.04 * sd, 0.18, -0.096)), Vector3(0.03, 0.014, 0.01), Color(0.05, 0.04, 0.04))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.04 * sd, 0.2, -0.097)), Vector3(0.04, 0.01, 0.01), hair * 0.8)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.085, -0.096)), Vector3(0.05, 0.012, 0.01), Color(skin.r * 0.6, skin.g * 0.6, skin.b * 0.6))
	if style == "elder":
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0.015)), Vector3(0.2, 0.08, 0.22), _cloth(Color(0.5, 0.46, 0.4)))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.17, 0.09)), Vector3(0.2, 0.22, 0.06), _cloth(Color(0.5, 0.46, 0.4)))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.22, -0.075)), Vector3(0.16, 0.03, 0.02), hair)
	else:
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0.01)), Vector3(0.19, 0.07, 0.21), hair)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.18, 0.09)), Vector3(0.18, 0.2, 0.05), hair)
		for sd in [-1.0, 1.0]:
			k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.09 * sd, 0.17, 0.0)), Vector3(0.02, 0.16, 0.13), hair)
		if style == "queen":
			# Long braid down the back and a thin silver circlet.
			for i in 5:
				k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.08 - float(i) * 0.09, 0.13)), Vector3(0.06 - float(i) * 0.006, 0.09, 0.05), hair * (0.92 + 0.08 * float(i % 2)))
			k.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.255, 0.005)), 0.104, 0.104, 0.018, 12, Color(0.66, 0.66, 0.7, 0.4), 0.0, 0.0, false)
	add_mesh("head", k, CASTLE_PROPS_MAT)

	for sd in [-1.0, 1.0]:
		var side := "l" if sd < 0 else "r"
		k = MeshKit.new(310 + int(sd), 0.03)
		CharacterRig.cyl_down(k, Vector3.ZERO, 0.055, 0.05, 0.27, 6, _cloth(dress))
		add_mesh("arm_" + side, k, CASTLE_PROPS_MAT)
		k = MeshKit.new(320 + int(sd), 0.03)
		CharacterRig.cyl_down(k, Vector3.ZERO, 0.05, 0.065 if style == "queen" else 0.045, 0.21, 6, _cloth(dress if style != "queen" else trim * 0.6))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.25, 0)), Vector3(0.06, 0.08, 0.07), skin)
		add_mesh("forearm_" + side, k, CASTLE_PROPS_MAT)


func _pose(_delta: float) -> void:
	var p: Dictionary = parts
	var breath := sin(_time * 1.7) * 0.012
	p["spine"].rotation.x += breath
	p["arm_l"].rotation.z = -0.08
	p["arm_r"].rotation.z = 0.08
	if style == "elder":
		_set_x("spine", 0.32)
		_set_x("head", -0.25)
	match mood:
		"gaze":
			_set_x("head", -0.32 + sin(_time * 0.3) * 0.03)
			p["head"].rotation.y += sin(_time * 0.21) * 0.08
			_set_x("arm_l", 0.35); _set_x("arm_r", 0.35)
			p["arm_l"].rotation.z = 0.3; p["arm_r"].rotation.z = -0.3
			_set_x("forearm_l", 0.9); _set_x("forearm_r", 0.9)
		"worried":
			_set_x("arm_l", 0.75); _set_x("arm_r", 0.75)
			p["arm_l"].rotation.z = 0.45; p["arm_r"].rotation.z = -0.45
			_set_x("forearm_l", 1.25); _set_x("forearm_r", 1.25)
			p["head"].rotation.y += sin(_time * 2.3) * 0.12
		_:
			_set_x("arm_l", 0.06); _set_x("arm_r", 0.06)
	if _one_shot == "talk":
		var t := one_shot_p()
		_set_x("forearm_r", 0.9 * bell(t))
		_set_x("arm_r", 0.4 * bell(t))
		p["head"].rotation.x += 0.06 * sin(t * TAU * 2.0)


func _set_x(part_name: String, x: float) -> void:
	parts[part_name].rotation.x = _rest_rot[part_name].x + x
