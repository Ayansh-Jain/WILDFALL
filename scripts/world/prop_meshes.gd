class_name PropMeshes
extends RefCounted
## Procedural low-poly meshes for repeated props, cached by name. Each entry
## also describes its collision so scattering code can stay generic.
## Swap any of these for imported models later by returning a loaded Mesh.

const FOLIAGE_MAT := preload("res://assets/materials/foliage.tres")
const STONE_MAT := preload("res://assets/materials/stone.tres")
const ROCK_MAT := preload("res://assets/materials/rock.tres")
const BARK_MAT := preload("res://assets/materials/bark.tres")
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
		var far := prop.ends_with("_far")
		var base := prop.trim_suffix("_far")
		var detail := 0.4 if far else 1.0
		match base.rstrip("0123456789"):
			"pine": mesh = FoliageMeshes.conifer(10.4, 0.3, 2.6, 1.0, 11, detail)
			"fir": mesh = FoliageMeshes.conifer(14.0, 0.44, 3.0, 0.78, 12, detail)
			"oak": mesh = FoliageMeshes.broadleaf(4.4, 0.5, Vector3(0, 5.8, 0), Vector3(2.9, 2.1, 2.9), 46, Color(0.95, 1.0, 0.9), false, 13, detail)
			"birch": mesh = FoliageMeshes.broadleaf(6.0, 0.22, Vector3(0, 7.0, 0), Vector3(1.7, 2.6, 1.7), 30, Color(1.08, 1.12, 0.82), true, 15, detail)
			"dead_tree": mesh = FoliageMeshes.dead_tree(14)
			"bush": mesh = FoliageMeshes.bush(_variant(base), detail)
			"fern": mesh = FoliageMeshes.fern()
			"grass": mesh = FoliageMeshes.grass()
			"grass_tall": mesh = FoliageMeshes.grass_tall()
			"reeds": mesh = _build_reeds(prop)
			"rock": mesh = _build_rock(base)
			"pebble": mesh = _build_rock("rock1")
			"log": mesh = _build_log(prop)
			"mushrooms": mesh = _build_mushrooms(prop)
			"flower": mesh = _build_flower(prop)
			"rush": mesh = _build_rush(prop)
			"mosspatch": mesh = _build_moss_patch(prop)
			"branch": mesh = _build_branch(prop)
			_: push_error("PropMeshes: unknown prop '%s'" % prop)
		_cache[prop] = mesh
	return _cache[prop]


## Props with a lighter far-distance mesh ("<prop>_far").
static func has_lod(prop: String) -> bool:
	return prop.rstrip("0123456789") in ["pine", "fir", "oak", "birch", "bush"]

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


## Stratified angular cliff boulders with mossy upward shelves.
static func _build_rock(p: String) -> Mesh:
	var v := _variant(p)
	var k := MeshKit.new(40 + v, 0.08)
	var rng := RandomNumberGenerator.new()
	rng.seed = 400 + v * 17
	var scale: Vector3 = [Vector3(1.15, 0.68, 0.90), Vector3(1.35, 0.56, 1.05), Vector3(0.88, 1.05, 0.85), Vector3(1.42, 0.48, 0.96)][v % 4]
	var tmp := MeshKit.new(40 + v)
	tmp.add_blob(Transform3D(Basis.IDENTITY.scaled(scale), Vector3(0, 0.34, 0)), 1.0, ROCK, true, 0.34)
	# Add a smaller fractured shoulder outcrop on larger rock variants.
	if v % 2 == 1:
		var off := Vector3(rng.randf_range(0.55, 0.85), 0.14, rng.randf_range(-0.35, 0.35))
		tmp.add_blob(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(scale * 0.58), off), 0.9, ROCK, false, 0.32)
	for i in range(0, tmp.verts.size(), 3):
		var a := tmp.verts[i]
		var b := tmp.verts[i + 2]
		var c := tmp.verts[i + 1]
		# Subtle terrace flattening for natural sedimentary rock look.
		a.y = lerpf(a.y, snappedf(a.y, 0.24), 0.25)
		b.y = lerpf(b.y, snappedf(b.y, 0.24), 0.25)
		c.y = lerpf(c.y, snappedf(c.y, 0.24), 0.25)
		var nrm := (b - a).cross(c - a).normalized()
		var col := ROCK.lerp(MOSS, smoothstep(0.58, 0.92, nrm.y) * 0.85)
		k.add_tri(a, b, c, col)
	k.smooth_normals()
	var mesh := k.to_mesh(ROCK_MAT)
	mesh.set_meta("hull", tmp.verts)
	return mesh


static func _build_log(_p: String) -> Mesh:
	var k := MeshKit.new(50, 0.08)
	var t := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(3.0, 0.35, 0))
	k.add_cylinder(t, 0.36, 0.3, 6.0, 9, Color(0.8, 0.75, 0.7), 0, 0, true, Color(1.0, 0.85, 0.65))
	k.add_cylinder(Transform3D(Basis(Vector3.FORWARD, 1.0), Vector3(-1.0, 0.45, 0)), 0.1, 0.03, 1.1, 5, Color(0.8, 0.75, 0.7))
	k.smooth_normals()
	return k.to_mesh(BARK_MAT)


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


static func _basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


## Riverbank and meadow flowers: a clump of stems, leaves and small blossoms.
## 0 white umbels, 1 blue, 2 buttercup yellow, 3 purple loosestrife spikes, 4 deep red.
static func _build_flower(p: String) -> Mesh:
	var v := _variant(p) % 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + v
	var k := MeshKit.new(700 + v, 0.12)
	var petal: Color = [Color(0.86, 0.85, 0.78), Color(0.27, 0.33, 0.68), Color(0.86, 0.66, 0.1), Color(0.52, 0.2, 0.48), Color(0.5, 0.08, 0.07)][v]
	var heart: Color = [Color(0.78, 0.74, 0.42), Color(0.8, 0.76, 0.46), Color(0.58, 0.42, 0.08), Color(0.36, 0.13, 0.32), Color(0.1, 0.07, 0.05)][v]
	var stem := Color(0.15, 0.26, 0.1)
	var count: int = [7, 6, 9, 4, 4][v]
	var hr: Vector2 = [Vector2(0.35, 0.6), Vector2(0.22, 0.42), Vector2(0.14, 0.28), Vector2(0.7, 1.1), Vector2(0.4, 0.62)][v]
	for i in count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.02, 0.3)
		var base := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := rng.randf_range(hr.x, hr.y)
		var tip := base + Vector3(rng.randf_range(-0.07, 0.07), h, rng.randf_range(-0.07, 0.07))
		k.add_cylinder(Transform3D(_basis_y(tip - base), base), 0.011, 0.006, (tip - base).length(), 3, stem, 0.0, 1.0, false)
		for j in 2:
			var la := a + float(j) * PI + rng.randf_range(-0.5, 0.5)
			var lp := base + Vector3(cos(la), 0, sin(la)) * 0.12 + Vector3(0, h * 0.25, 0)
			var side := Vector3(-sin(la), 0, cos(la)) * 0.025
			k.add_tri(base - side, base + side, lp, stem * 1.15, 0.0, 0.0, 0.5)
			k.add_tri(base + side, base - side, lp, stem * 1.15, 0.0, 0.0, 0.5)
		if v == 3:
			for j in 7:
				var sp := base.lerp(tip, 0.55 + float(j) * 0.065)
				k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.022, 0.03, 0.022) * (1.0 - float(j) * 0.08)), sp), 1.0, petal * rng.randf_range(0.85, 1.1), false, 0.0, 0.9)
		elif v == 0:
			for j in 5:
				var fa := TAU * float(j) / 5.0
				var fp := tip + Vector3(cos(fa) * 0.035, -0.01, sin(fa) * 0.035)
				k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.022, 0.01, 0.022)), fp), 1.0, petal, false, 0.0, 1.0)
		else:
			var pr: float = [0.0, 0.035, 0.028, 0.0, 0.05][v]
			var cup: float = [0.0, 0.25, 0.55, 0.0, 0.45][v]
			for j in 5:
				var pa := TAU * float(j) / 5.0 + rng.randf() * 0.3
				var e1 := Vector3(cos(pa - 0.38), cup, sin(pa - 0.38)).normalized() * pr
				var e2 := Vector3(cos(pa + 0.38), cup, sin(pa + 0.38)).normalized() * pr
				k.add_tri(tip, tip + e1, tip + e2, petal, 1.0, 1.0, 1.0)
				k.add_tri(tip, tip + e2, tip + e1, petal * 0.85, 1.0, 1.0, 1.0)
			k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * pr * 0.32), tip + Vector3(0, 0.005, 0)), 1.0, heart, false, 0.0, 1.0)
	return k.to_mesh(FOLIAGE_MAT)


## Soft rush: a dense clump of thin, slightly arching stems with brown tufts.
static func _build_rush(_p: String) -> Mesh:
	var k := MeshKit.new(720, 0.12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 720
	for i in 16:
		var p := Vector3(rng.randf_range(-0.18, 0.18), 0, rng.randf_range(-0.18, 0.18))
		var dir := Vector3(p.x * 1.6 + rng.randf_range(-0.15, 0.15), 1.0, p.z * 1.6 + rng.randf_range(-0.15, 0.15))
		var h := rng.randf_range(0.55, 1.0)
		k.add_cylinder(Transform3D(_basis_y(dir), p), 0.012, 0.004, h, 3, Color(0.2, 0.29, 0.13) * rng.randf_range(0.85, 1.15), 0.0, 1.0, false)
		if i % 4 == 0:
			k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.02, 0.04, 0.02)), p + dir.normalized() * h * 0.82), 1.0, Color(0.32, 0.22, 0.12), false, 0.0, 0.85)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_moss_patch(_p: String) -> Mesh:
	var k := MeshKit.new(730, 0.15)
	k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.6, 0.05, 0.45)), Vector3(0, 0.0, 0)), 1.0, Color(0.15, 0.24, 0.09), true, 0.3)
	k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.35, 0.05, 0.3)), Vector3(0.4, 0.0, 0.25)), 1.0, Color(0.18, 0.27, 0.1), false, 0.3)
	return k.to_mesh(FOLIAGE_MAT)


static func _build_branch(_p: String) -> Mesh:
	var k := MeshKit.new(740, 0.08)
	var col := Color(0.62, 0.56, 0.5)
	k.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.8, 0.05, 0)), 0.05, 0.025, 1.6, 5, col)
	k.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, 0.6), Vector3(0.2, 0.05, 0.02)), 0.025, 0.008, 0.5, 4, col)
	k.add_cylinder(Transform3D(Basis(Vector3.FORWARD, -PI * 0.5) * Basis(Vector3.RIGHT, -0.5), Vector3(-0.3, 0.05, 0)), 0.02, 0.006, 0.4, 4, col)
	return k.to_mesh(BARK_MAT)


static func rock_hull(prop: String, scale: float) -> PackedVector3Array:
	var pts: PackedVector3Array = get_mesh(prop).get_meta("hull")
	var out := PackedVector3Array()
	# Every third vertex is enough for a hull and keeps shapes light.
	for i in range(0, pts.size(), 2):
		out.append(pts[i] * scale)
	return out
