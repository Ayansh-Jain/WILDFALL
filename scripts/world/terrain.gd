class_name Terrain
extends Node3D
## Turns TerrainData into chunked meshes and matching concave collision.
## Chunks let the renderer frustum-cull the 680 m terrain in pieces.

const TERRAIN_MAT := preload("res://assets/materials/terrain.tres")

var data: TerrainData


func build(p_data: TerrainData) -> void:
	data = p_data
	var chunk := data.layout.chunk_cells
	var cells := data.n - 1
	var chunks := int(ceil(float(cells) / chunk))
	var normals := _vertex_normals()
	for cz in chunks:
		for cx in chunks:
			_build_chunk(cx * chunk, cz * chunk, mini(chunk, cells - cx * chunk), mini(chunk, cells - cz * chunk), normals)


func _vertex_normals() -> PackedVector3Array:
	var n := data.n
	var out := PackedVector3Array()
	out.resize(n * n)
	var h := data.heights
	for j in n:
		for i in n:
			var l := h[data.idx(maxi(i - 1, 0), j)]
			var r := h[data.idx(mini(i + 1, n - 1), j)]
			var d := h[data.idx(i, maxi(j - 1, 0))]
			var u := h[data.idx(i, mini(j + 1, n - 1))]
			out[data.idx(i, j)] = Vector3(l - r, 2.0 * data.cell, d - u).normalized()
	return out


func _build_chunk(i0: int, j0: int, w: int, d: int, normals: PackedVector3Array) -> void:
	var n := data.n
	var row := w + 1
	var count := row * (d + 1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(count)
	norms.resize(count)
	cols.resize(count)
	var v := 0
	for j in range(j0, j0 + d + 1):
		var z := data.vx(j)
		for i in range(i0, i0 + w + 1):
			var k := j * n + i
			verts[v] = Vector3(data.vx(i), data.heights[k], z)
			norms[v] = normals[k]
			cols[v] = Color(1.0 - smoothstep(-0.6, 0.9, data.trail_dist[k]), data.forest[k], data.wet[k], data.paving[k])
			v += 1
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	indices.resize(w * d * 6)
	faces.resize(w * d * 6)
	var q := 0
	for j in range(d):
		for i in range(w):
			if data.holes[(j0 + j) * (n - 1) + i0 + i] == 1:
				continue
			var a := j * row + i
			var b := a + 1
			var c := a + row + 1
			var e := a + row
			indices[q] = a; indices[q + 1] = b; indices[q + 2] = c
			indices[q + 3] = a; indices[q + 4] = c; indices[q + 5] = e
			faces[q] = verts[a]; faces[q + 1] = verts[b]; faces[q + 2] = verts[c]
			faces[q + 3] = verts[a]; faces[q + 4] = verts[c]; faces[q + 5] = verts[e]
			q += 6
	indices.resize(q)
	faces.resize(q)
	if indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, TERRAIN_MAT)
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [i0, j0]
	mi.mesh = mesh
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "Collision_%d_%d" % [i0, j0]
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
