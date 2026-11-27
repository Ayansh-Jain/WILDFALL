class_name KingRig
extends CharacterRig
## The King, seated on the old lord's chair in the great hall (same low-poly
## language as CivilianRig): a crimson robe with gold trim under an ermine
## mantle, a gold crown, a grey beard, rings of office. The origin is the dais
## floor in front of the chair; `seat_height` is the seat above it.
## Poses: seated idle (slow breathing, hands on the chair arms), "talk" gestures
## (an open right hand), "listen" (head inclined toward the speaker).

const CASTLE_PROPS_MAT := preload("res://assets/materials/castle_props.tres")
const CLOTH := 0.3
const IRON := 0.4

const SKIN := Color(0.66, 0.5, 0.41)
const ROBE := Color(0.42, 0.06, 0.08)
const TRIM := Color(0.72, 0.56, 0.22)
const ERMINE := Color(0.86, 0.84, 0.8)
const SPOT := Color(0.06, 0.06, 0.06)
const BEARD := Color(0.62, 0.6, 0.57)
const GOLD := Color(0.8, 0.62, 0.22)
const BOOT := Color(0.18, 0.11, 0.07)

## Seat height above the origin (the old lord's chair stands on the dais).
var seat_height := 0.57
## Used only for the short morning audience at the castle entrance.
var seated := true


func _c(c: Color, tag := CLOTH) -> Color:
	return Color(c.r, c.g, c.b, tag)


func _build() -> void:
	# Hips sit on the seat; the rest hangs from them.
	add_part("body", "", Vector3(0, 0, 0))
	add_part("hips", "body", Vector3(0, seat_height, 0.04))
	add_part("spine", "hips", Vector3(0, 0.06, 0))
	add_part("head", "spine", Vector3(0, 0.6, 0))
	for sd in [-1.0, 1.0]:
		var side := "l" if sd < 0 else "r"
		add_part("arm_" + side, "spine", Vector3(0.23 * sd, 0.5, 0))
		add_part("forearm_" + side, "arm_" + side, Vector3(0, -0.28, 0))
		add_part("thigh_" + side, "hips", Vector3(0.11 * sd, 0.0, 0), Vector3(PI * 0.5, 0, 0))
		add_part("shin_" + side, "thigh_" + side, Vector3(0, -0.44, 0), Vector3(-PI * 0.5, 0, 0))

	# Lap and legs: the robe falls over the thighs and down to the boots.
	var k := MeshKit.new(601, 0.04)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0.0)), Vector3(0.42, 0.22, 0.3), _c(ROBE))
	add_mesh("hips", k, CASTLE_PROPS_MAT)
	for sd in [-1.0, 1.0]:
		var side := "l" if sd < 0 else "r"
		k = MeshKit.new(610 + int(sd), 0.04)
		CharacterRig.cyl_down(k, Vector3.ZERO, 0.11, 0.1, 0.46, 7, _c(ROBE * 0.95))
		add_mesh("thigh_" + side, k, CASTLE_PROPS_MAT)
		k = MeshKit.new(620 + int(sd), 0.04)
		# The robe's skirt hangs to the ankle; boots show beneath.
		CharacterRig.cyl_down(k, Vector3(0, 0.04, -0.02), 0.13, 0.15, 0.44, 7, _c(ROBE * 0.9))
		k.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.44, -0.02)), 0.152, 0.152, 0.04, 7, _c(TRIM, IRON))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.5, -0.07)), Vector3(0.11, 0.08, 0.24), BOOT)
		add_mesh("shin_" + side, k, CASTLE_PROPS_MAT)

	# Torso: robe, a gold-trimmed placket and belt, the ermine mantle and its collar.
	k = MeshKit.new(602, 0.04)
	k.add_cylinder(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.72)), Vector3(0, -0.02, 0)), 0.2, 0.19, 0.58, 9, _c(ROBE))
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, -0.145)), Vector3(0.06, 0.5, 0.02), _c(TRIM, IRON))
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), Vector3(0.42, 0.06, 0.31), _c(TRIM * 0.8, IRON))
	k.add_blob(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, -0.16)), 0.035, _c(GOLD, IRON))
	# Mantle over the shoulders and down the back to the seat.
	k.add_cylinder(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.85)), Vector3(0, 0.36, 0.02)), 0.28, 0.17, 0.2, 12, _c(ERMINE))
	for i in 9:
		var a := -1.0 + i * 0.25
		var sp := Vector3(sin(a) * 0.25, 0.42 + absf(a) * -0.04, cos(a) * 0.2 * 0.85 + 0.02)
		k.add_box(Transform3D(Basis.IDENTITY, sp), Vector3(0.02, 0.03, 0.01), SPOT)
	for i in 7:
		var x := -0.24 + i * 0.08
		k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(x, 0.05, 0.19)), Vector3(0.085, 0.62, 0.03), _c(ROBE * (0.85 + 0.08 * float(i % 2))))
	add_mesh("spine", k, CASTLE_PROPS_MAT)

	# Head: face, grey hair and a full beard, and the crown.
	k = MeshKit.new(603, 0.03)
	k.add_cylinder(Transform3D.IDENTITY, 0.05, 0.05, 0.08, 6, SKIN)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.17, 0)), Vector3(0.18, 0.22, 0.2), SKIN)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.16, -0.105)), Vector3(0.03, 0.05, 0.03), SKIN * 0.94)
	for sd in [-1.0, 1.0]:
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.043 * sd, 0.19, -0.101)), Vector3(0.033, 0.014, 0.01), Color(0.05, 0.04, 0.04))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.043 * sd, 0.214, -0.102)), Vector3(0.045, 0.014, 0.012), BEARD * 0.9)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.096 * sd, 0.16, 0.02)), Vector3(0.025, 0.2, 0.15), BEARD)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0.01)), Vector3(0.2, 0.07, 0.22), BEARD)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.17, 0.095)), Vector3(0.19, 0.22, 0.05), BEARD)
	# Beard and moustache.
	k.add_box(Transform3D(Basis(Vector3.RIGHT, -0.15), Vector3(0, 0.05, -0.085)), Vector3(0.17, 0.17, 0.07), BEARD)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.125, -0.108)), Vector3(0.1, 0.02, 0.02), BEARD * 0.95)
	# Crown: a gold band with points and three stones.
	k.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0.01)), 0.115, 0.118, 0.06, 12, _c(GOLD, IRON))
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector3(sin(a) * 0.112, 0.33, cos(a) * 0.112 + 0.01)
		CharacterRig.spike(k, p, Vector3.UP, 0.07, 0.02, _c(GOLD, IRON), 4)
	for i in 3:
		var a := PI + (i - 1) * 0.6
		k.add_blob(Transform3D(Basis.IDENTITY, Vector3(sin(a) * 0.12, 0.3, cos(a) * 0.12 + 0.01)), 0.012, [Color(0.6, 0.05, 0.08), Color(0.1, 0.25, 0.6), Color(0.6, 0.05, 0.08)][i])
	add_mesh("head", k, CASTLE_PROPS_MAT)

	for sd in [-1.0, 1.0]:
		var side := "l" if sd < 0 else "r"
		k = MeshKit.new(630 + int(sd), 0.03)
		CharacterRig.cyl_down(k, Vector3.ZERO, 0.07, 0.065, 0.28, 7, _c(ROBE))
		add_mesh("arm_" + side, k, CASTLE_PROPS_MAT)
		k = MeshKit.new(640 + int(sd), 0.03)
		CharacterRig.cyl_down(k, Vector3.ZERO, 0.062, 0.085, 0.2, 7, _c(ROBE * 0.95))
		k.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0)), 0.088, 0.088, 0.035, 7, _c(ERMINE))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.27, 0)), Vector3(0.06, 0.09, 0.075), SKIN)
		k.add_blob(Transform3D(Basis.IDENTITY, Vector3(0.025 * sd, -0.28, -0.03)), 0.012, _c(GOLD, IRON))
		add_mesh("forearm_" + side, k, CASTLE_PROPS_MAT)


func _pose(_delta: float) -> void:
	var p: Dictionary = parts
	var breath := sin(_time * 1.3) * 0.012
	_set_x("spine", -0.05 + breath)
	# Forearms resting along the chair arms, hands at their ends.
	for side in ["l", "r"]:
		var sd := -1.0 if side == "l" else 1.0
		_set_x("arm_" + side, 0.3)
		p["arm_" + side].rotation.z = 0.12 * sd
		_set_x("forearm_" + side, 1.2)
		_set_x("thigh_" + side, 0.0)
		p["thigh_" + side].rotation.z = 0.05 * sd
	if not seated:
		p["hips"].position.y = 0.98
		for side in ["l", "r"]:
			p["thigh_" + side].rotation.x = 0
			p["shin_" + side].rotation.x = 0
			p["arm_" + side].rotation.x = 0
			p["forearm_" + side].rotation.x = 0.12
	match mood:
		"listen":
			p["head"].rotation.z += 0.08
			_set_x("head", 0.06)
		_:
			p["head"].rotation.y += sin(_time * 0.25) * 0.06
	if _one_shot == "talk":
		var t := one_shot_p()
		_set_x("arm_r", 0.3 + 0.45 * bell(t))
		p["arm_r"].rotation.z = 0.12 + 0.2 * bell(t)
		_set_x("forearm_r", 1.2 + 0.25 * sin(t * PI * 2.0))
		p["head"].rotation.x += 0.05 * sin(t * TAU * 2.0)


func _set_x(part_name: String, x: float) -> void:
	parts[part_name].rotation.x = _rest_rot[part_name].x + x
