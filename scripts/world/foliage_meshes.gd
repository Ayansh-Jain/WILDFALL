class_name FoliageMeshes
extends RefCounted
## Natural-looking trees, bushes, ferns and grass built from a smooth bark
## trunk (triplanar bark material) plus alpha-cut foliage cards. Each mesh has
## two surfaces: 0 = bark, 1 = cards. `detail` < 1 builds the far LOD with
## fewer cards. Trunk sizes match the old meshes, so collision is unchanged.

const LEAVES := preload("res://assets/materials/leaves.tres")
const NEEDLES := preload("res://assets/materials/needles.tres")
const GRASS := preload("res://assets/materials/grass_card.tres")
const FERN := preload("res://assets/materials/fern.tres")
const BARK := preload("res://assets/materials/bark.tres")
const BARK_PINE := preload("res://assets/materials/bark_pine.tres")


class CardKit:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()

	## Quad from four corners (bl, br, tr, tl) with matching UVs and normals.
	func quad(p: Array, uv: Array, n: Array, sway: Array, col: Color) -> void:
		for i in [0, 1, 2, 0, 2, 3]:
			verts.append(p[i])
			uvs.append(uv[i])
			normals.append(n[i])
			uv2s.append(Vector2(sway[i], 0))
			colors.append(col)

	func is_empty() -> bool:
		return verts.is_empty()


static func _arrays_from_kit(k: MeshKit) -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = k.verts
	a[Mesh.ARRAY_NORMAL] = k.normals
	a[Mesh.ARRAY_COLOR] = k.colors
	return a


static func _mesh(bark: MeshKit, bark_mat: Material, cards: CardKit, card_mat: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if bark and not bark.is_empty():
		bark.smooth_normals()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays_from_kit(bark))
		mesh.surface_set_material(mesh.get_surface_count() - 1, bark_mat)
	if cards and not cards.is_empty():
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = cards.verts
		a[Mesh.ARRAY_NORMAL] = cards.normals
		a[Mesh.ARRAY_COLOR] = cards.colors
		a[Mesh.ARRAY_TEX_UV] = cards.uvs
		a[Mesh.ARRAY_TEX_UV2] = cards.uv2s
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(mesh.get_surface_count() - 1, card_mat)
	return mesh


## A card spanning from `start` along `along` (full length), `half_w` across.
## UV u runs along the card (0 at start), v across. Normals point `n`.
static func _spray(c: CardKit, start: Vector3, along: Vector3, half_w: Vector3, n: Vector3, sway0: float, sway1: float, col: Color) -> void:
	var p := [start - half_w, start + along - half_w, start + along + half_w, start + half_w]
	c.quad(p, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], [n, n, n, n], [sway0, sway1, sway1, sway0], col)


## Upright card centred at `base` (bottom middle): v = 1 at the bottom.
static func _upright(c: CardKit, base: Vector3, right: Vector3, up: Vector3, n0: Vector3, n1: Vector3, sway0: float, sway1: float, col: Color) -> void:
	var p := [base - right, base + right, base + right + up, base - right + up]
	c.quad(p, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], [n0, n0, n1, n1], [sway0, sway0, sway1, sway1], col)


## Leaf-cluster card at `center` facing roughly `facing`; normals radiate from `canopy_c`.
static func _cluster(c: CardKit, center: Vector3, facing: Vector3, size: float, canopy_c: Vector3, rng: RandomNumberGenerator, sway: float, col: Color) -> void:
	var f := facing.normalized()
	var ref := Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	var right := f.cross(ref).normalized().rotated(f, rng.randf_range(-0.6, 0.6)) * size * 0.5
	var up := right.cross(f).normalized() * size * 0.5
	var corners := [center - right - up, center + right - up, center + right + up, center - right + up]
	var ns := []
	for p in corners:
		ns.append(((p - canopy_c).normalized() + Vector3.UP * 0.35).normalized())
	c.quad(corners, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], ns, [sway * 0.7, sway * 0.7, sway, sway], col)


# --- conifers ---------------------------------------------------------------------------

static func conifer(height: float, base_r: float, spread: float, dark: float, seed_value: int, detail: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.new(seed_value)
	bark.add_cylinder(Transform3D.IDENTITY, base_r, base_r * 0.18, height, 8 if detail > 0.6 else 6, Color(0.95, 0.9, 0.85), 0.0, 0.0, false)
	var c := CardKit.new()
	var y0 := height * 0.16
	var step := 0.5 if detail > 0.6 else 0.78
	var per := 5
	var whorl := 0
	var y := y0
	while y < height * 0.93:
		var t := (y - y0) / (height * 0.93 - y0)
		var length := (0.45 + spread * pow(1.0 - t, 1.05)) * (1.0 if detail > 0.6 else 1.12)
		var shade := (0.55 + 0.55 * t) * dark * rng.randf_range(0.9, 1.08)
		for i in per:
			var a := whorl * 2.399 + TAU * i / per + rng.randf_range(-0.25, 0.25)
			var flat := Vector3(cos(a), 0, sin(a))
			var dir := (flat + Vector3.UP * (-0.38 + 0.25 * t)).normalized()
			var start := Vector3(0, y, 0) + flat * base_r * (1.0 - t) * 0.6
			var side := dir.cross(Vector3.UP).normalized()
			var vert := dir.cross(side).normalized()
			var n := (flat * 0.85 + Vector3.UP * 0.25).normalized()
			var col := Color(shade, shade, shade)
			var w_mult := 0.42 if detail > 0.6 else 0.58
			_spray(c, start, dir * length, side * length * w_mult, n, 0.0, 0.25 + 0.75 * t, col)
			if detail > 0.6:
				_spray(c, start, dir * length * 0.9, vert * length * 0.28, n, 0.0, 0.25 + 0.75 * t, col * 0.92)
		whorl += 1
		y += step * rng.randf_range(0.85, 1.15)
	# Leader tuft at the top.
	var tip := Vector3(0, height * 0.9, 0)
	for k in 2:
		var r := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5)) * 0.45
		_spray(c, tip - Vector3.UP * 0.1, Vector3.UP * height * 0.14, r, Vector3.UP, 0.4, 1.0, Color(dark, dark, dark))
	return _mesh(bark, BARK_PINE, c, NEEDLES)


# --- broadleaf --------------------------------------------------------------------------------

static func broadleaf(trunk_h: float, base_r: float, canopy_c: Vector3, radii: Vector3, cards: int, leaf_tint: Color,
		birch: bool, seed_value: int, detail: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.new(seed_value)
	var bark_col := Color(1, 1, 1, 0.0) if birch else Color(0.95, 0.92, 0.88)
	var lean := Basis(Vector3(1, 0, 0.4).normalized(), rng.randf_range(-0.04, 0.04))
	bark.add_cylinder(Transform3D(lean, Vector3.ZERO), base_r, base_r * 0.55, trunk_h, 8 if detail > 0.6 else 6, bark_col, 0.0, 0.0, false)
	var branch_count := 5 if detail > 0.6 else 3
	for i in branch_count:
		var a := TAU * i / branch_count + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), rng.randf_range(0.7, 1.2), sin(a)).normalized()
		var start := lean * Vector3(0, trunk_h * rng.randf_range(0.6, 0.95), 0)
		var len := rng.randf_range(0.45, 0.7) * (radii.x + radii.y)
		bark.add_cylinder(Transform3D(Landmark.basis_y(dir), start), base_r * 0.42, base_r * 0.12, len, 5, bark_col, 0.0, 0.0, false)
	var c := CardKit.new()
	var n := int(cards * detail) + 4
	for i in n:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1)).normalized()
		var r := pow(rng.randf(), 0.45)
		var p := canopy_c + Vector3(dir.x * radii.x, dir.y * radii.y, dir.z * radii.z) * r
		var facing := (dir + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.6), rng.randf_range(-0.5, 0.5))).normalized()
		var shade := (0.55 + 0.5 * r) * (0.9 + 0.2 * clampf(dir.y, 0.0, 1.0)) * rng.randf_range(0.9, 1.1)
		var size := rng.randf_range(1.5, 2.3) * (radii.x / 2.8) * (1.0 / sqrt(maxf(detail, 0.3)) if detail < 0.6 else 1.0)
		_cluster(c, p, facing, size, canopy_c, rng, 0.5 + 0.5 * r, Color(leaf_tint.r * shade, leaf_tint.g * shade, leaf_tint.b * shade))
	return _mesh(bark, BARK, c, LEAVES)


static func dead_tree(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bark := MeshKit.new(seed_value)
	var grey := Color(0.72, 0.7, 0.68)
	bark.add_cylinder(Transform3D.IDENTITY, 0.34, 0.08, 7.5, 7, grey, 0.0, 0.0, false)
	for i in 7:
		var y := rng.randf_range(2.4, 6.4)
		var a := rng.randf() * TAU
		var dir := Vector3(cos(a), rng.randf_range(0.2, 0.9), sin(a)).normalized()
		var len := rng.randf_range(1.4, 2.8) * (1.0 - (y - 2.4) / 8.0)
		bark.add_cylinder(Transform3D(Landmark.basis_y(dir), Vector3(0, y, 0)), 0.12, 0.02, len, 5, grey, 0.0, 0.0, false)
		var sub := (dir + Vector3(rng.randf_range(-0.6, 0.6), 0.5, rng.randf_range(-0.6, 0.6))).normalized()
		bark.add_cylinder(Transform3D(Landmark.basis_y(sub), Vector3(0, y, 0) + dir * len * 0.6), 0.05, 0.01, len * 0.5, 4, grey, 0.0, 0.0, false)
	return _mesh(bark, BARK, null, null)


# --- undergrowth ---------------------------------------------------------------------------------

static func bush(variant: int, detail: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + variant
	var c := CardKit.new()
	var center := Vector3(0, 0.55, 0)
	var radii := Vector3(0.9, 0.55, 0.9) * (1.0 + variant * 0.12)
	var n := int((20 + variant * 3) * detail) + 4
	for i in n:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 1)).normalized()
		var r := pow(rng.randf(), 0.5)
		var p := center + Vector3(dir.x * radii.x, dir.y * radii.y, dir.z * radii.z) * r
		var shade := (0.6 + 0.45 * r) * rng.randf_range(0.88, 1.08)
		_cluster(c, p, (dir + Vector3.UP * 0.3).normalized(), rng.randf_range(0.95, 1.35), center - Vector3.UP * 0.3, rng, 0.4 + 0.6 * r,
			Color(0.82 * shade, 0.9 * shade, 0.78 * shade))
	return _mesh(null, null, c, LEAVES)


static func fern() -> ArrayMesh:
	var c := CardKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
		var flat := Vector3(cos(a), 0, sin(a))
		var side := flat.cross(Vector3.UP).normalized() * 0.17
		var p0 := Vector3.ZERO
		var p1 := flat * 0.38 + Vector3.UP * 0.38
		var p2 := flat * 0.8 + Vector3.UP * 0.32
		var n := Vector3.UP
		var col := Color.WHITE * rng.randf_range(0.85, 1.1)
		c.quad([p0 - side * 0.5, p0 + side * 0.5, p1 + side, p1 - side], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0.5), Vector2(0, 0.5)], [n, n, n, n], [0.0, 0.0, 0.5, 0.5], col)
		c.quad([p1 - side, p1 + side, p2 + side * 0.4, p2 - side * 0.4], [Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, 0), Vector2(0, 0)], [n, n, n, n], [0.5, 0.5, 1.0, 1.0], col)
	return _mesh(null, null, c, FERN)


static func grass() -> ArrayMesh:
	var c := CardKit.new()
	for i in 3:
		var a := PI * i / 3.0 + 0.25 * float(i)
		var right := Vector3(cos(a), 0, sin(a)) * 0.46
		_upright(c, Vector3.ZERO, right, Vector3.UP * 0.62, Vector3.UP, Vector3.UP, 0.0, 1.0, Color.WHITE)
	return _mesh(null, null, c, GRASS)


## Taller two-segment arching meadow grass for golden-valley wind waves.
static func grass_tall() -> ArrayMesh:
	var c := CardKit.new()
	for i in 3:
		var a := PI * i / 3.0 + 0.18 * float(i)
		var right := Vector3(cos(a), 0, sin(a)) * 0.56
		var lean := Vector3(-sin(a), 0, cos(a)) * 0.14
		var p0 := -right
		var p1 := right
		var m0 := -right * 0.92 + Vector3.UP * 0.48 + lean * 0.35
		var m1 := right * 0.92 + Vector3.UP * 0.48 + lean * 0.35
		var t0 := -right * 0.8 + Vector3.UP * 0.98 + lean
		var t1 := right * 0.8 + Vector3.UP * 0.98 + lean
		var shade_bot := Color(0.76, 0.78, 0.68)
		var shade_top := Color(1.05, 1.02, 0.90)
		c.quad([p0, p1, m1, m0], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0.5), Vector2(0, 0.5)],
			[Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP], [0.0, 0.0, 0.45, 0.45], shade_bot)
		c.quad([m0, m1, t1, t0], [Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, 0), Vector2(0, 0)],
			[Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP], [0.45, 0.45, 1.0, 1.0], shade_top)
	return _mesh(null, null, c, GRASS)
