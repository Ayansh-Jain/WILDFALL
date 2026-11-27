class_name VarethRegion
extends WorldRegion
## R03-AG | Vareth — enemy territory foundation.
## 800 m × 600 m harsh angular terrain beyond the War Plains.
## Features: distant fortress silhouette, 2 enemy watchtowers, enemy banners,
## darker/cooler visual identity contrasting Eldoria's warmth.

const HALF_X := 400.0
const HALF_Z := 300.0
const CELL   := 2.0


func _init() -> void:
	region_id         = "vareth"
	region_half_size  = maxf(HALF_X, HALF_Z)
	cell_size         = CELL
	default_profile   = "vareth"


func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": region_half_size, "playable_half": region_half_size * 0.88,
			"cell": CELL, "water_level": -100.0, "base_height": 3.0, "chunk_cells": 34
		},
		"trails": [{
			"name": "EnemyRoad", "half_width": 3.0,
			"points": [[0, -290], [0, -150], [0, 0], [-40, 150], [-80, 290]]
		}]
	}


func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 100241
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 100.0; nb.fractal_octaves = 4

	var nr := FastNoiseLite.new()
	nr.seed = 100247
	nr.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nr.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	nr.frequency  = 1.0 / 55.0; nr.fractal_octaves = 3

	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			# More angular, harsher than Eldoria
			var base_h := (nb.get_noise_2d(lx, lz) + 1.0) * 0.5 * 15.0 + 3.0
			var ridged  := (nr.get_noise_2d(lx, lz) + 1.0) * 0.5 * 10.0
			# Northern fortress hill
			var fortress_dist := Vector2(lx + 80.0, lz - 220.0).length()
			var fortress_h    := maxf(0.0, 25.0 - fortress_dist * 0.1)
			td.heights[j * td.n + i] = base_h + ridged * 0.6 + fortress_h

	# Flatten fortress base plateau
	_flatten_area(-80.0, 220.0, 50.0, 30.0)
	# Flatten approach road
	for lz in range(-290, 290, 20):
		_flatten_area(-lz * 0.07, float(lz), 12.0, 3.5)

	# Watchtower ridge positions
	_flatten_area(-200.0, 100.0, 15.0, 20.0)
	_flatten_area(200.0, 50.0, 15.0, 18.0)


func _build_structures() -> void:
	var root := structures_root
	# Distant fortress silhouette (LOD-only beyond 300 m)
	_build_vareth_fortress(root, Vector3(-80, 30, 220))
	# Enemy watchtowers on ridge
	_build_enemy_tower(root, Vector3(-200, 20, 100))
	_build_enemy_tower(root, Vector3(200, 18, 50))
	# Enemy banners (crimson)
	_build_enemy_banner(root, Vector3(-210, 20, 100))
	_build_enemy_banner(root, Vector3(210, 18, 50))
	# Stone-paved enemy road sections
	_build_enemy_road(root)


func _build_vareth_fortress(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("vr_fortress"), 0.04)
	var DARK  := Color(0.22, 0.20, 0.19)
	var MID   := Color(0.28, 0.26, 0.24)

	# Main keep (40 × 60 × 40 m block tower cluster)
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 20, 0)), Vector3(40, 40, 60), DARK)
	# Corner towers
	for cx : float in [-22.0, 22.0]:
		for cz : float in [-32.0, 32.0]:
			kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(cx, 25, cz)),
				Vector3(10, 50, 10), MID)
	# Courtyard wall
	for side_x : float in [-30.0, 30.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(side_x, 8, 0)),
			Vector3(0.6, 16, 70), DARK)
	# Battlement silhouette strip
	for m in 20:
		var mx := float(m) * 4.0 - 38.0
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(mx, 42, -31)),
			Vector3(1.6, 3, 0.8), MID)

	var mi := MeshInstance3D.new()
	mi.mesh = kit.build()
	mi.material_override = STONE_MAT
	# LOD: only visible up to any distance (simplification — no LOD_begin since it's already simplified)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	parent.add_child(mi)

	# Collision (simplified)
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(50, 40, 70); cs.position = base + Vector3(0, 20, 0)
	cs.shape = box; body.add_child(cs); body.collision_layer = Layers.WORLD; parent.add_child(body)


func _build_enemy_tower(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("vr_tower" + str(lpos)), 0.05)
	var DARK := Color(0.26, 0.24, 0.22)
	# Cylindrical tower
	for s in 8:
		var a0 := TAU * s / 8; var a1 := TAU * (s + 1) / 8
		for seg in 8:
			var yb := float(seg) * 1.5; var yt := float(seg + 1) * 1.5
			kit.add_quad(
				base + Vector3(cos(a0)*3.0, yb, sin(a0)*3.0),
				base + Vector3(cos(a1)*3.0, yb, sin(a1)*3.0),
				base + Vector3(cos(a1)*3.0, yt, sin(a1)*3.0),
				base + Vector3(cos(a0)*3.0, yt, sin(a0)*3.0),
				DARK)
	# Battlement ring
	for s in 8:
		var a := TAU * s / 8 + TAU / 16
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(cos(a)*3.0, 12.75, sin(a)*3.0)),
			Vector3(0.6, 1.4, 0.6), DARK)
	# Flat roof
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 12.1, 0)), Vector3(6.5, 0.2, 6.5), DARK)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var cyl := CylinderShape3D.new()
	cyl.radius = 3.0; cyl.height = 12.0; cs.shape = cyl; cs.position = base + Vector3(0, 6, 0)
	body.add_child(cs); body.collision_layer = Layers.WORLD; parent.add_child(body)


func _build_enemy_banner(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd + 12.0, 0)
	var kit  := MeshKit.new(hash("vr_banner" + str(lpos)), 0.0)
	var CRIMSON := Color(0.72, 0.08, 0.08)
	kit.add_tri(base, base + Vector3(1.4, 0, 0), base + Vector3(1.4, -3.5, 0), CRIMSON, 0.0, 0.0, 1.0)
	kit.add_tri(base, base + Vector3(1.4, -3.5, 0), base + Vector3(0, -3.5, 0), CRIMSON, 0.0, 1.0, 1.0)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build()
	parent.add_child(mi)


func _build_enemy_road(parent: Node3D) -> void:
	# Stone-paved darker road through terrain
	var kit := MeshKit.new(hash("vr_road"), 0.04)
	var PAVE := Color(0.28, 0.26, 0.24)  # darker than royal roads
	var pts  := [Vector2(0, -290), Vector2(0, 0), Vector2(-80, 290)]
	for s in pts.size() - 1:
		var pa := pts[s]; var pb := pts[s + 1]
		var len := pa.distance_to(pb)
		var steps := int(len / 6.0)
		var dir := (pb - pa).normalized()
		var perp := Vector2(-dir.y, dir.x)
		for step in steps:
			var t := float(step) / steps
			var cp := pa.lerp(pb, t + 0.5 / steps)
			var gnd := height_at_local(cp.x, cp.y)
			kit.add_quad(
				Vector3((cp + perp * 3.0).x, gnd + 0.08, (cp + perp * 3.0).y),
				Vector3((cp - perp * 3.0).x, gnd + 0.08, (cp - perp * 3.0).y),
				Vector3((pa.lerp(pb, (step + 1.0) / steps) - perp * 3.0).x, gnd + 0.08, (pa.lerp(pb, (step + 1.0) / steps) - perp * 3.0).y),
				Vector3((pa.lerp(pb, (step + 1.0) / steps) + perp * 3.0).x, gnd + 0.08, (pa.lerp(pb, (step + 1.0) / steps) + perp * 3.0).y),
				PAVE)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_vegetation() -> void:
	var veg := vegetation_root
	var rng := RandomNumberGenerator.new(); rng.seed = 100261
	# Sparse, darker trees (mostly dead-looking fir, some pine)
	for _i in 400:
		var lx  := rng.randf_range(-HALF_X * 0.85, HALF_X * 0.85)
		var lz  := rng.randf_range(-HALF_Z * 0.85, HALF_Z * 0.85)
		# Skip fortress area
		if Vector2(lx + 80, lz - 220).length() < 60: continue
		var gnd := height_at_local(lx, lz)
		if gnd < 2.0: continue
		var kind := "fir" if rng.randf() > 0.4 else "pine"
		var mi   := MeshInstance3D.new()
		mi.mesh = PropMeshes.tree(kind, rng.randf_range(0.7, 1.1))
		mi.position = Vector3(lx, gnd, lz)
		veg.add_child(mi)


func _build_all() -> void:
	_setup_layout()
	_build_terrain()
	_build_structures()
	_build_vegetation()
	_place_markers()
	_publish_markers()


func _place_markers() -> void:
	var pts := [
		["vareth_south_entry",    "route_waypoint", Vector3(0, 0, -290)],
		["vareth_fortress_gate",  "landmark",       Vector3(-80, 30, 180)],
		["vareth_watchtower_w",   "landmark",       Vector3(-200, 20, 100)],
		["vareth_watchtower_e",   "landmark",       Vector3(200, 18, 50)],
	]
	for p in pts:
		var lpos : Vector3 = p[2]
		lpos.y = height_at_local(lpos.x, lpos.z)
		_add_marker(p[0], p[1], lpos)
