class_name PropMeshes
extends RefCounted
## Procedural low-poly meshes for repeated props, cached by name. Each entry
## also describes its collision so scattering code can stay generic.
## Swap any of these for imported models later by returning a loaded Mesh.

const FOLIAGE_MAT := preload("res://assets/materials/foliage.tres")
const STONE_MAT := preload("res://assets/materials/stone.tres")
const GLOW_MAT := preload("res://assets/materials/glow_magic.tres")

const BARK := Color(0.24, 0.17, 0.12)
const BARK_DARK := Color(0.16, 0.12, 0.09)
const PINE := Color(0.075, 0.16, 0.11)
const FIR := Color(0.06, 0.13, 0.10)
const LEAF := Color(0.13, 0.21, 0.09)
const BIRCH_BARK := Color(0.62, 0.62, 0.58)
const BIRCH_LEAF := Color(0.2, 0.3, 0.2)
const ROCK := Color(0.33, 0.34, 0.36)
const MOSS := Color(0.17, 0.25, 0.12)

static var _cache := {}


static func get_mesh(prop: String) -> Mesh:
	if not _cache.has(prop):
		var mesh: Mesh
		match prop.rstrip("0123456789"):
			"pine": mesh = _build_pine(prop)
			"fir": mesh = _build_fir(prop)
			"oak": mesh = _build_oak(prop)
			"dead_tree": mesh = _build_dead_tree(prop)
			"birch": mesh = _build_birch(prop)
			"bush": mesh = _build_bush(prop)
			"fern": mesh = _build_fern(prop)
			"grass": mesh = _build_grass(prop)
			"reeds": mesh = _build_reeds(prop)
			"rock": mesh = _build_rock(prop)
			"log": mesh = _build_log(prop)
			"mushrooms": mesh = _build_mushrooms(prop)
			_: push_error("PropMeshes: unknown prop '%s'" % prop)
		_cache[prop] = mesh
	return _cache[prop]


## Trunk collision radius at scale 1 (0 = no movement collision).
const TRUNK_RADIUS := {
	"pine": 0.3, "fir": 0.42, "oak": 0.48, "dead_tree": 0.3, "birch": 0.22,
}


static func _variant(prop: String) -> int:
	var digits := ""
	for ch in prop:
		if ch.is_valid_int():
			digits += ch
	return int(digits) if digits != "" else 0


static func _build_pine(_p: String) -> Mesh:
	var k := MeshKit.new(11, 0.08)
	k.add_cylinder(Transform3D.IDENTITY, 0.32, 0.12, 9.0, 6, BARK, 0.0, 0.3)
	for i in 4:
		var y := 2.4 + i * 1.85
		var r := 2.5 - i * 0.48
		k.add_cylinder(Transform3D(Basis(Vector3.UP, i * 0.6), Vector3(0, y, 0)), r, 0.0, 3.1, 7,
				PINE * (1.0 + i * 0.06), 0.15 + i * 0.2, 0.4 + i * 0.25)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_fir(_p: String) -> Mesh:
	var k := MeshKit.new(12, 0.08)
	k.add_cylinder(Transform3D.IDENTITY, 0.45, 0.14, 13.0, 7, BARK_DARK, 0.0, 0.3)
	for i in 6:
		var y := 2.8 + i * 1.75
		var r := 2.6 - i * 0.36
		k.add_cylinder(Transform3D(Basis(Vector3.UP, i * 0.9), Vector3(0, y, 0)), r, 0.0, 2.9, 8,
				FIR * (1.0 + i * 0.05), 0.1 + i * 0.15, 0.3 + i * 0.2)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_oak(_p: String) -> Mesh:
	var k := MeshKit.new(13, 0.1)
	k.add_cylinder(Transform3D.IDENTITY, 0.5, 0.3, 4.2, 7, BARK)
	k.add_cylinder(Transform3D(Basis(Vector3.FORWARD, 0.7), Vector3(0, 3.0, 0)), 0.22, 0.1, 2.6, 5, BARK, 0.0, 0.3)
	k.add_cylinder(Transform3D(Basis(Vector3.FORWARD, -0.6).rotated(Vector3.UP, 1.2), Vector3(0, 3.3, 0)), 0.2, 0.1, 2.4, 5, BARK, 0.0, 0.3)
	var blobs := [[Vector3(0, 5.6, 0), 2.6], [Vector3(1.7, 4.9, 0.4), 1.9], [Vector3(-1.4, 5.0, -0.8), 2.0], [Vector3(0.2, 4.6, 1.6), 1.7]]
	for b in blobs:
		k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.78, 1)), b[0]), b[1], LEAF, true, 0.18, 0.7)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_dead_tree(_p: String) -> Mesh:
	var k := MeshKit.new(14, 0.06)
	var grey := Color(0.27, 0.25, 0.23)
	k.add_cylinder(Transform3D.IDENTITY, 0.34, 0.1, 7.5, 6, grey)
	var branches := [[2.8, 0.9, 0.0, 2.6], [3.8, -0.8, 2.0, 2.2], [4.9, 0.7, 3.9, 1.8], [5.8, -0.6, 5.2, 1.4]]
	for b in branches:
		var basis := Basis(Vector3.UP, b[2]) * Basis(Vector3.FORWARD, b[1])
		k.add_cylinder(Transform3D(basis, Vector3(0, b[0], 0)), 0.12, 0.03, b[3], 4, grey, 0.0, 0.2)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_birch(_p: String) -> Mesh:
	var k := MeshKit.new(15, 0.08)
	k.add_cylinder(Transform3D.IDENTITY, 0.22, 0.1, 8.0, 6, BIRCH_BARK, 0.0, 0.4)
	for b in [[Vector3(0, 7.4, 0), 1.6], [Vector3(0.6, 6.2, 0.3), 1.3], [Vector3(-0.5, 5.4, -0.2), 1.2]]:
		k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.25, 1)), b[0]), b[1], BIRCH_LEAF, false, 0.15, 0.8)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_bush(p: String) -> Mesh:
	var v := _variant(p)
	var k := MeshKit.new(20 + v, 0.12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 200 + v
	for i in 3 + v:
		var off := Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.45, 0.8), rng.randf_range(-0.6, 0.6))
		k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.75, 1)), off), rng.randf_range(0.55, 0.85),
				Color(0.1, 0.19, 0.09) * rng.randf_range(0.85, 1.2), false, 0.2, 0.6)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_fern(_p: String) -> Mesh:
	var k := MeshKit.new(30, 0.1)
	for i in 7:
		var a := TAU * i / 7.0
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.9)
		var t := Transform3D(basis, Vector3.ZERO)
		var l := 0.75
		k.add_tri(t * Vector3(-0.09, 0, 0), t * Vector3(0.09, 0, 0), t * Vector3(0, 0, -l), Color(0.12, 0.24, 0.1), 0.0, 0.0, 0.8)
		k.add_tri(t * Vector3(0.09, 0, 0), t * Vector3(-0.09, 0, 0), t * Vector3(0, 0, -l), Color(0.1, 0.2, 0.08), 0.0, 0.0, 0.8)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_grass(_p: String) -> Mesh:
	var k := MeshKit.new(31, 0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 6:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.25)
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var side := Vector3(cos(a + 1.57), 0, sin(a + 1.57)) * 0.05
		var tip := base + Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.35, 0.6), rng.randf_range(-0.1, 0.1))
		var col := Color(0.15, 0.23, 0.1) * rng.randf_range(0.8, 1.2)
		k.add_tri(base - side, base + side, tip, col, 0.0, 0.0, 1.0)
		k.add_tri(base + side, base - side, tip, col, 0.0, 0.0, 1.0)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_reeds(_p: String) -> Mesh:
	var k := MeshKit.new(32, 0.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 32
	for i in 9:
		var p := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		var t := Transform3D(Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15)), p)
		k.add_cylinder(t, 0.025, 0.0, rng.randf_range(1.0, 1.7), 3, Color(0.2, 0.24, 0.12), 0.0, 1.0, false)
		if i % 3 == 0:
			k.add_cylinder(t.translated_local(Vector3(0, 1.1, 0)), 0.045, 0.045, 0.22, 4, Color(0.25, 0.17, 0.1), 0.8, 1.0)
	return k.to_mesh(FOLIAGE_MAT)


## Boulders: jittered icospheres with moss on upward faces.
static func _build_rock(p: String) -> Mesh:
	var v := _variant(p)
	var k := MeshKit.new(40 + v, 0.07)
	var scale: Vector3 = [Vector3(1.0, 0.7, 0.85), Vector3(1.2, 0.6, 1.0), Vector3(0.8, 0.9, 0.8), Vector3(1.3, 0.5, 0.9)][v % 4]
	var tmp := MeshKit.new(40 + v)
	tmp.add_blob(Transform3D(Basis.IDENTITY.scaled(scale), Vector3(0, 0.35, 0)), 1.0, ROCK, v % 2 == 0, 0.28)
	for i in range(0, tmp.verts.size(), 3):
		var a := tmp.verts[i]
		var b := tmp.verts[i + 2]
		var c := tmp.verts[i + 1]
		var nrm := (b - a).cross(c - a).normalized()
		var col := ROCK.lerp(MOSS, smoothstep(0.55, 0.9, nrm.y) * 0.8)
		k.add_tri(a, b, c, col)
	var mesh := k.to_mesh(STONE_MAT)
	mesh.set_meta("hull", tmp.verts)
	return mesh


static func _build_log(_p: String) -> Mesh:
	var k := MeshKit.new(50, 0.08)
	var t := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(3.0, 0.35, 0))
	k.add_cylinder(t, 0.36, 0.3, 6.0, 7, BARK_DARK, 0, 0, true, Color(0.42, 0.33, 0.22))
	k.add_cylinder(Transform3D(Basis(Vector3.FORWARD, 1.0), Vector3(-1.0, 0.45, 0)), 0.1, 0.03, 1.1, 4, BARK_DARK)
	k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 0.3, 0.7)), Vector3(0.5, 0.68, 0)), 0.45, MOSS, false, 0.2)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_mushrooms(_p: String) -> Mesh:
	var k := MeshKit.new(60)
	var rng := RandomNumberGenerator.new()
	rng.seed = 60
	for i in 5:
		var p := Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35))
		var h := rng.randf_range(0.12, 0.3)
		k.add_cylinder(Transform3D(Basis.IDENTITY, p), 0.025, 0.02, h, 4, Color(0.5, 0.6, 0.6))
		k.add_cylinder(Transform3D(Basis.IDENTITY, p + Vector3(0, h, 0)), rng.randf_range(0.06, 0.12), 0.0, 0.07, 6, Color(1, 1, 1))
	return k.to_mesh(GLOW_MAT)


static func rock_hull(prop: String, scale: float) -> PackedVector3Array:
	var pts: PackedVector3Array = get_mesh(prop).get_meta("hull")
	var out := PackedVector3Array()
	# Every third vertex is enough for a hull and keeps shapes light.
	for i in range(0, pts.size(), 2):
		out.append(pts[i] * scale)
	return out
