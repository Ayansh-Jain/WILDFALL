class_name FirstPersonArms
extends RefCounted
## Builds the human first-person meshes: a gloved right hand wrapped around a
## longsword grip, an open gloved left hand, leather bracers, and the sword
## itself (diamond-section blade, curved bronze guard, wrapped grip, pommel).
## Leather uses the photo-textured triplanar shader in object space so the
## texture does not swim as the arms move.

const STONE_TRI := preload("res://assets/materials/stone_tri.gdshader")
const LEATHER_TEX := preload("res://assets/textures/brown_leather_diff.jpg")
const LEATHER_NRM := preload("res://assets/textures/brown_leather_nor.jpg")

const GLOVE := Color(0.24, 0.2, 0.17)
const GLOVE_DARK := Color(0.15, 0.12, 0.1)
const BRACER := Color(0.4, 0.3, 0.22)
const GRIP := Color(0.16, 0.11, 0.08)

static var _leather: ShaderMaterial
static var _steel: StandardMaterial3D
static var _bronze: StandardMaterial3D


static func leather() -> ShaderMaterial:
	if _leather == null:
		_leather = ShaderMaterial.new()
		_leather.shader = STONE_TRI
		_leather.set_shader_parameter("stone_tex", LEATHER_TEX)
		_leather.set_shader_parameter("stone_nrm", LEATHER_NRM)
		_leather.set_shader_parameter("object_space", true)
		_leather.set_shader_parameter("scale", 9.0)
		_leather.set_shader_parameter("moss_amount", 0.0)
		_leather.set_shader_parameter("tint_strength", 0.45)
		_leather.set_shader_parameter("normal_strength", 0.55)
		_leather.set_shader_parameter("brightness", 1.15)
		_leather.set_shader_parameter("saturation", 0.5)
	return _leather


static func steel() -> StandardMaterial3D:
	if _steel == null:
		_steel = StandardMaterial3D.new()
		_steel.albedo_color = Color(0.56, 0.58, 0.62)
		_steel.metallic = 0.75
		_steel.roughness = 0.36
		_steel.metallic_specular = 0.7
		_steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _steel


static func bronze() -> StandardMaterial3D:
	if _bronze == null:
		_bronze = StandardMaterial3D.new()
		_bronze.albedo_color = Color(0.66, 0.5, 0.3)
		_bronze.metallic = 0.85
		_bronze.roughness = 0.38
	return _bronze


static func _seg(k: MeshKit, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, sides := 7) -> void:
	var d := b - a
	if d.length() < 0.0001:
		return
	k.add_cylinder(Transform3D(Landmark.basis_y(d), a), r0, r1, d.length(), sides, col, 0.0, 0.0, false)


static func _joint(k: MeshKit, p: Vector3, r: float, col: Color) -> void:
	k.add_blob(Transform3D(Basis.IDENTITY, p), r, col, true)


static func _mi(parent: Node3D, k: MeshKit, mat: Material, smooth := true) -> MeshInstance3D:
	if smooth:
		k.smooth_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = k.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Forearm from `wrist` to `elbow` with a flared glove cuff and a strapped bracer.
static func _forearm(k: MeshKit, wrist: Vector3, elbow: Vector3) -> void:
	var d := (elbow - wrist).normalized()
	_seg(k, wrist, wrist + d * 0.06, 0.03, 0.044, GLOVE)
	_seg(k, wrist + d * 0.055, elbow, 0.046, 0.054, BRACER, 9)
	for t: float in [0.2, 0.5, 0.8]:
		var p := (wrist + d * 0.055).lerp(elbow, t)
		_seg(k, p - d * 0.006, p + d * 0.006, 0.0505 + t * 0.008, 0.0505 + t * 0.008, GLOVE_DARK, 9)


## Right hand closed around a grip along +Y at the origin; back of hand toward +X/+Z.
static func sword_hand() -> Node3D:
	var root := Node3D.new()
	root.name = "SwordHand"
	var k := MeshKit.new(901)
	k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.75, 1.25, 0.9)), Vector3(0.034, -0.008, 0.016)), 0.036, GLOVE, true)
	var ys := [0.03, 0.006, -0.018, -0.04]
	var rs := [0.0105, 0.011, 0.0102, 0.0088]
	for i in 4:
		var y: float = ys[i]
		var r: float = rs[i]
		var pts: Array[Vector3] = []
		for step in [[8.0, 0.044], [70.0, 0.031], [125.0, 0.027], [172.0, 0.024]]:
			var th := deg_to_rad(step[0])
			pts.append(Vector3(cos(th) * step[1], y, -sin(th) * step[1]))
		for s in 3:
			_seg(k, pts[s], pts[s + 1], r * (1.0 - s * 0.08), r * (0.92 - s * 0.08), GLOVE)
			_joint(k, pts[s + 1], r * (0.92 - s * 0.08), GLOVE)
		_joint(k, pts[0], r * 1.15, GLOVE_DARK)
	var thumb := [Vector3(0.03, 0.02, 0.026), Vector3(0.012, 0.05, 0.024), Vector3(-0.012, 0.058, 0.012), Vector3(-0.026, 0.056, -0.004)]
	for s in 3:
		_seg(k, thumb[s], thumb[s + 1], 0.0125 - s * 0.0012, 0.0115 - s * 0.0012, GLOVE)
		_joint(k, thumb[s + 1], 0.0115 - s * 0.0012, GLOVE)
	_forearm(k, Vector3(0.04, -0.06, 0.03), Vector3(0.13, -0.34, 0.26))
	_mi(root, k, leather())
	root.add_child(longsword())
	return root


## Open left hand, palm down, fingers reaching forward (-Z) from the wrist at the origin.
static func open_hand() -> Node3D:
	var root := Node3D.new()
	root.name = "OpenHand"
	var k := MeshKit.new(902)
	k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.36, 1.15)), Vector3(0, 0, -0.05)), 0.045, GLOVE, true)
	var lengths := [[0.04, 0.026, 0.022], [0.045, 0.03, 0.024], [0.042, 0.028, 0.023], [0.034, 0.022, 0.019]]
	for i in 4:
		var x := -0.028 + i * 0.019
		var p := Vector3(x, 0.002, -0.094 + absf(i - 1.5) * 0.004)
		var dir := Vector3((x) * 0.6, -0.12, -1.0).normalized()
		var r := 0.0098 - i * 0.0004
		_joint(k, p, r * 1.1, GLOVE_DARK)
		for s in 3:
			var q: Vector3 = p + dir * lengths[i][s]
			_seg(k, p, q, r, r * 0.9, GLOVE)
			_joint(k, q, r * 0.9, GLOVE)
			p = q
			dir = dir.rotated(Vector3.RIGHT, -0.2)
			r *= 0.9
	var thumb := [Vector3(0.035, -0.006, -0.03), Vector3(0.055, -0.012, -0.058), Vector3(0.062, -0.016, -0.085)]
	for s in 2:
		_seg(k, thumb[s], thumb[s + 1], 0.0125, 0.011, GLOVE)
		_joint(k, thumb[s + 1], 0.011, GLOVE)
	_forearm(k, Vector3(0, -0.004, 0.01), Vector3(-0.06, -0.14, 0.3))
	_mi(root, k, leather())
	return root


## Longsword with its grip centred on the origin and the blade along +Y.
static func longsword() -> Node3D:
	var root := Node3D.new()
	root.name = "Longsword"
	var grip := MeshKit.new(903)
	_seg(grip, Vector3(0, -0.075, 0), Vector3(0, 0.062, 0), 0.0145, 0.0135, GRIP, 10)
	for i in 6:
		var y := -0.065 + i * 0.023
		_seg(grip, Vector3(0, y, 0), Vector3(0, y + 0.007, 0), 0.0156, 0.0156, GRIP * 0.8, 10)
	_mi(root, grip, leather())

	var b := MeshKit.new(904)
	b.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.3, 1.0)), Vector3(0, -0.092, 0)), 0.021, Color.WHITE, true)
	b.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.072, 0)), Vector3(0.042, 0.03, 0.03), Color.WHITE)
	for s: float in [-1.0, 1.0]:
		var prev := Vector3(0.018 * s, 0.072, 0)
		for i in 5:
			var t := float(i + 1) / 5.0
			var p := Vector3(s * (0.018 + 0.095 * t), 0.072 + 0.018 * t * t, 0)
			_seg(b, prev, p, 0.0115 - t * 0.003, 0.0105 - t * 0.003, Color.WHITE, 6)
			prev = p
		b.add_blob(Transform3D(Basis.IDENTITY, prev + Vector3(0.004 * s, 0.004, 0)), 0.012, Color.WHITE, true)
	_mi(root, b, bronze())

	# Blade: diamond cross-section with a central ridge, tapering to a point.
	var bl := MeshKit.new(905)
	var stations := [[0.086, 0.025, 0.0065], [0.13, 0.024, 0.006], [0.35, 0.022, 0.0055], [0.6, 0.019, 0.005],
		[0.8, 0.0145, 0.0042], [0.9, 0.008, 0.003], [0.95, 0.0, 0.0]]
	for i in stations.size() - 1:
		var s0: Array = stations[i]
		var s1: Array = stations[i + 1]
		var a := [Vector3(-s0[1], s0[0], 0), Vector3(0, s0[0], -s0[2]), Vector3(s0[1], s0[0], 0), Vector3(0, s0[0], s0[2])]
		var c := [Vector3(-s1[1], s1[0], 0), Vector3(0, s1[0], -s1[2]), Vector3(s1[1], s1[0], 0), Vector3(0, s1[0], s1[2])]
		for f in 4:
			var j := (f + 1) % 4
			bl.add_quad(a[j], a[f], c[f], c[j], Color.WHITE)
	_mi(root, bl, steel(), false)
	return root
