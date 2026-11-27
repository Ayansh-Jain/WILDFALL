class_name GreatHelm
extends RefCounted
## A closed-face medieval great helm (13th-14th century barrel helm), built to fit the
## commander model's head. Coordinates are the HEAD BONE frame (+Y up the skull, +Z
## forward). Measured from the model (tools/inspect_commander.gd), head and hair occupy
## x -0.095..0.095, y -0.115..0.175, z -0.115..0.135; the shell clears that by 2-3 cm
## everywhere (nose to visor 3 cm), so it never touches the face, which it hides entirely.
##
## Shell: an oval barrel with a slightly flared lower lip and a near-flat crown. Face:
## a recessed eye slit (ocularium) and breath holes, drawn as dark recesses on the
## plate (the face plate is solid: no opening shows the face behind it), a brow band and
## a vertical reinforcing strip forming the cross, rivets, and a rim at the lip.
## kingdom: bright steel with brass fittings. enemy: blackened steel, dark iron fittings.
## One single-surface mesh per look (parts told apart by vertex colour), shared by
## every soldier of that look: one draw call per helm.

const SEGMENTS := 32
const RX := 0.122
const RZ_FRONT := 0.16
const RZ_BACK := 0.142
const CZ := 0.006
## Rings from the lower lip to the crown: [y, radius scale].
const RINGS := [[-0.135, 1.05], [-0.118, 1.02], [-0.09, 1.0], [0.05, 1.0], [0.15, 0.985],
	[0.19, 0.94], [0.21, 0.82], [0.222, 0.55], [0.227, 0.0]]

static var _cache := {}


static func mesh(faction: String, variant := "") -> ArrayMesh:
	var key := faction + "/" + variant
	if _cache.has(key):
		return _cache[key]
	var enemy := faction == "enemy"
	# One surface, one draw call: the parts differ by vertex colour on one metal.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.17, 0.17, 0.19) if enemy else Color(0.6, 0.61, 0.64))
	st.set_smooth_group(0)
	_shell(st)
	st.set_smooth_group(0xFFFFFFFF)
	st.set_color(Color(0.3, 0.3, 0.32) if enemy else Color(0.7, 0.5, 0.22))
	_trims(st)
	st.set_color(Color(0.012, 0.012, 0.014))
	_recesses(st)
	st.set_color(Color(0.05, 0.04, 0.035))
	_lining(st)
	if variant == "captain":
		st.set_color(Color(0.45, 0.04, 0.04))
		_plume(st)
	st.generate_normals()
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.8 if enemy else 0.86
	mat.roughness = 0.5 if enemy else 0.36
	mat.metallic_specular = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(0, mat)
	m.resource_name = "GreatHelm_" + key
	_cache[key] = m
	return m


## A point on the shell at angle `a` (0 = straight ahead, +Z) and height `y`, pushed out
## along the surface by `out` metres.
static func point(a: float, y: float, out := 0.0) -> Vector3:
	var s := _scale_at(y)
	var rz := RZ_FRONT if cos(a) >= 0.0 else RZ_BACK
	var p := Vector3(RX * s * sin(a), y, CZ + rz * s * cos(a))
	var n := Vector3(sin(a) / RX, 0.0, cos(a) / rz).normalized()
	return p + n * out


static func _scale_at(y: float) -> float:
	for i in RINGS.size() - 1:
		var a: Array = RINGS[i]
		var b: Array = RINGS[i + 1]
		if y <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), inverse_lerp(float(a[0]), float(b[0]), y))
	return 0.0


static func _shell(st: SurfaceTool) -> void:
	for r in RINGS.size() - 1:
		var y0: float = RINGS[r][0]
		var y1: float = RINGS[r + 1][0]
		for i in SEGMENTS:
			var a0 := TAU * i / SEGMENTS
			var a1 := TAU * (i + 1) / SEGMENTS
			var p00 := point(a0, y0)
			var p01 := point(a1, y0)
			var p10 := point(a0, y1)
			var p11 := point(a1, y1)
			# Outward-facing winding (counter-clockwise seen from outside).
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)


## A band hugging the shell between heights y0..y1 over angles a0..a1, raised by `out`.
static func _band(st: SurfaceTool, a0: float, a1: float, y0: float, y1: float, out: float, steps := 0) -> void:
	var n := steps if steps > 0 else maxi(2, int(absf(a1 - a0) / TAU * SEGMENTS * 2.0))
	for i in n:
		var u0 := lerpf(a0, a1, float(i) / n)
		var u1 := lerpf(a0, a1, float(i + 1) / n)
		var p00 := point(u0, y0, out)
		var p01 := point(u1, y0, out)
		var p10 := point(u0, y1, out)
		var p11 := point(u1, y1, out)
		st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
		st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
		# Edges down to the shell so the band has thickness when seen side-on.
		if i == 0:
			_quad(st, point(u0, y0, 0.0), point(u0, y1, 0.0), p10, p00)
		if i == n - 1:
			_quad(st, p01, p11, point(u1, y1, 0.0), point(u1, y0, 0.0))
	_quad(st, point(a0, y1, 0.0), point(a1, y1, 0.0), point(a1, y1, out), point(a0, y1, out))
	_quad(st, point(a0, y0, out), point(a1, y0, out), point(a1, y0, 0.0), point(a0, y0, 0.0))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


static func _trims(st: SurfaceTool) -> void:
	# Rim at the lower lip and a brow band right round the helm.
	_band(st, 0.0, TAU, -0.135, -0.118, 0.004)
	_band(st, 0.0, TAU, 0.066, 0.08, 0.004)
	# The reinforcing cross: a vertical strip down the face plate, through the slit.
	var w := 0.075  # radians either side of centre
	_band(st, -w, w, -0.118, 0.066, 0.005, 2)
	_band(st, -w, w, 0.08, 0.205, 0.005, 2)
	# Rivets along the brow band and the rim.
	for i in 12:
		var a := TAU * i / 12.0 + 0.13
		_rivet(st, a, 0.073)
		_rivet(st, a + 0.13, -0.126)


static func _rivet(st: SurfaceTool, a: float, y: float) -> void:
	var h := 0.006
	var da := h / RX
	_band(st, a - da, a + da, y - h, y + h, 0.009, 1)


## The eye slit (a dark recess either side of the cross strip) and breath holes on the
## right cheek plate: drawn just proud of the solid plate, so nothing behind shows.
static func _recesses(st: SurfaceTool) -> void:
	for side in [-1.0, 1.0]:
		var a0: float = 0.085 * side
		var a1: float = 1.05 * side
		_band(st, minf(a0, a1), maxf(a0, a1), 0.036, 0.052, 0.0015)
	for row in 3:
		for col in 4:
			var a := 0.22 + col * 0.13
			var y := -0.07 + row * 0.022
			var h := 0.0045
			_band(st, a - h / RX, a + h / RX, y - h, y + h, 0.0015, 1)


## A ring of padding inside the lower lip, closing in toward the neck.
static func _lining(st: SurfaceTool) -> void:
	var y_out := -0.128
	var y_in := -0.105
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var o0 := point(a0, y_out, -0.003)
		var o1 := point(a1, y_out, -0.003)
		var i0 := _inner(a0, y_in)
		var i1 := _inner(a1, y_in)
		_quad(st, o0, o1, i1, i0)


static func _inner(a: float, y: float) -> Vector3:
	# The neck opening: about 6 cm either side, a little forward of the bone.
	return Vector3(0.062 * sin(a), y, 0.02 + 0.07 * cos(a))


static func _plume(st: SurfaceTool) -> void:
	for i in 6:
		var z := -0.06 + i * 0.024
		var top := 0.3 - absf(i - 2.5) * 0.02
		var x := 0.012
		var p := [Vector3(-x, 0.22, z), Vector3(x, 0.22, z), Vector3(x, top, z + 0.01), Vector3(-x, top, z + 0.01)]
		_quad(st, p[0], p[1], p[2], p[3])
		_quad(st, p[1], p[0], p[3], p[2])
