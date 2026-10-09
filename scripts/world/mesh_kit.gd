class_name MeshKit
extends RefCounted
## Accumulates flat-shaded low-poly geometry and turns it into one ArrayMesh.
##
## Every face gets its own vertices and face normal, which gives the faceted
## look without any shader tricks. UV.x carries a wind-sway weight (0 = rigid)
## that the foliage shader reads.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()

## Per-face brightness jitter, 0 disables. Gives hand-painted variation.
var color_jitter := 0.0
var rng := RandomNumberGenerator.new()


func _init(seed_value: int = 0, jitter: float = 0.0) -> void:
	rng.seed = seed_value
	color_jitter = jitter


func is_empty() -> bool:
	return verts.is_empty()


func add_tri(a: Vector3, b: Vector3, c: Vector3, color: Color, sa := 0.0, sb := 0.0, sc := 0.0) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	# Godot uses clockwise winding for front faces; callers pass counter-clockwise
	# when viewed from outside, so swap b/c and flip the normal accordingly.
	var col := color
	if color_jitter > 0.0:
		var j := 1.0 + rng.randf_range(-color_jitter, color_jitter)
		col = Color(color.r * j, color.g * j, color.b * j, color.a)
	verts.append(a); verts.append(c); verts.append(b)
	for i in 3:
		normals.append(n)
		colors.append(col)
	uvs.append(Vector2(sa, 0)); uvs.append(Vector2(sc, 0)); uvs.append(Vector2(sb, 0))


func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, sway := 0.0) -> void:
	add_tri(a, b, c, color, sway, sway, sway)
	add_tri(a, c, d, color, sway, sway, sway)


## Axis-aligned box centred on xform.origin before transform.
func add_box(xform: Transform3D, size: Vector3, color: Color, sway := 0.0) -> void:
	var h := size * 0.5
	var p := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	for i in p.size():
		p[i] = xform * p[i]
	add_quad(p[4], p[7], p[6], p[5], color, sway)  # top
	add_quad(p[0], p[1], p[2], p[3], color, sway)  # bottom
	add_quad(p[3], p[2], p[6], p[7], color, sway)  # +z
	add_quad(p[1], p[0], p[4], p[5], color, sway)  # -z
	add_quad(p[2], p[1], p[5], p[6], color, sway)  # +x
	add_quad(p[0], p[3], p[7], p[4], color, sway)  # -x


## Tapered cylinder from local y=0 to y=height. r_top = 0 makes a cone.
func add_cylinder(xform: Transform3D, r_bottom: float, r_top: float, height: float, sides: int,
		color: Color, sway_bottom := 0.0, sway_top := 0.0, caps := true, top_color := Color(0, 0, 0, 0)) -> void:
	var tc := color if top_color.a == 0.0 else top_color
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides:
		var ang := TAU * float(i) / sides
		var dir := Vector3(cos(ang), 0, sin(ang))
		bottom.append(xform * (dir * r_bottom))
		top.append(xform * (dir * r_top + Vector3(0, height, 0)))
	var cb := xform * Vector3.ZERO
	var ct := xform * Vector3(0, height, 0)
	for i in sides:
		var j := (i + 1) % sides
		if r_top <= 0.0001:
			add_tri(bottom[j], bottom[i], ct, color, sway_bottom, sway_bottom, sway_top)
		else:
			add_tri(bottom[j], bottom[i], top[i], color, sway_bottom, sway_bottom, sway_top)
			add_tri(bottom[j], top[i], top[j], color, sway_bottom, sway_top, sway_top)
			if caps:
				add_tri(ct, top[j], top[i], tc, sway_top, sway_top, sway_top)
		if caps:
			add_tri(cb, bottom[i], bottom[j], color, sway_bottom, sway_bottom, sway_bottom)


## Low-poly sphere (icosahedron, optionally subdivided once), with optional
## radial jitter for rocks and foliage blobs. Scale comes from xform.
func add_blob(xform: Transform3D, radius: float, color: Color, subdivide := false, jitter := 0.0, sway := 0.0) -> void:
	for tri in icosphere_tris(subdivide):
		var pts: Array[Vector3] = []
		for v in tri:
			var r := radius * (1.0 + jitter * _hash_noise(v))
			pts.append(xform * (v * r))
		add_tri(pts[0], pts[1], pts[2], color, sway, sway, sway)


## Deterministic per-direction noise so shared vertices stay welded after jitter.
func _hash_noise(v: Vector3) -> float:
	var h := sin(v.x * 12.9898 + v.y * 78.233 + v.z * 37.719 + float(rng.seed % 1000)) * 43758.5453
	return (h - floor(h)) * 2.0 - 1.0


static var _ico_cache := {}


static func icosphere_tris(subdivide: bool) -> Array:
	if _ico_cache.has(subdivide):
		return _ico_cache[subdivide]
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in v.size():
		v[i] = v[i].normalized()
	var f := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var tris := []
	for face in f:
		var a: Vector3 = v[face[0]]
		var b: Vector3 = v[face[1]]
		var c: Vector3 = v[face[2]]
		if subdivide:
			var ab := ((a + b) * 0.5).normalized()
			var bc := ((b + c) * 0.5).normalized()
			var ca := ((c + a) * 0.5).normalized()
			tris.append([a, ab, ca]); tris.append([b, bc, ab]); tris.append([c, ca, bc]); tris.append([ab, bc, ca])
		else:
			tris.append([a, b, c])
	# Faces above are counter-clockwise seen from outside; add_tri expects that.
	_ico_cache[subdivide] = tris
	return tris


## Averages normals of coincident vertices (smooth shading for trunks, rocks).
func smooth_normals() -> void:
	var sums := {}
	for i in verts.size():
		var key := Vector3i((verts[i] * 1000.0).round())
		sums[key] = sums.get(key, Vector3.ZERO) + normals[i]
	for i in verts.size():
		var key := Vector3i((verts[i] * 1000.0).round())
		var n: Vector3 = sums[key]
		if n.length_squared() > 1e-8:
			normals[i] = n.normalized()


func append(other: MeshKit) -> void:
	verts.append_array(other.verts)
	normals.append_array(other.normals)
	colors.append_array(other.colors)
	uvs.append_array(other.uvs)


func to_mesh(material: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material:
		mesh.surface_set_material(0, material)
	return mesh


## Collision faces matching the visual geometry (for concave static shapes).
func to_faces() -> PackedVector3Array:
	return verts
