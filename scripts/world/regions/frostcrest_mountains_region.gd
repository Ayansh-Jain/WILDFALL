class_name FrostcrestMountainsRegion
extends WorldRegion
## R03-AG | Frostcrest Mountains — dramatic mountain range north of Eldoria.
## 1,200 m (EW) × 600 m (NS). Steep ridges 40-120 m elevation, 2 traversable
## passes, 3 waterfalls, cave mouth, scenic overlooks.

const HALF_X := 600.0
const HALF_Z := 300.0
const CELL   := 2.0


func _init() -> void:
	region_id         = "frostcrest_mountains"
	region_half_size  = maxf(HALF_X, HALF_Z)
	cell_size         = CELL
	default_profile   = "frostcrest"


func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": region_half_size, "playable_half": region_half_size * 0.88,
			"cell": CELL, "water_level": -100.0, "base_height": 8.0, "chunk_cells": 34
		},
		"trails": [
			{"name": "WestPass",   "half_width": 2.8,
			 "points": [[-600, 280], [-480, 180], [-320, 80], [-180, 20], [-60, -60], [80, -120], [220, -200], [360, -260], [600, -290]]},
			{"name": "EastPass",   "half_width": 2.6,
			 "points": [[200, 280], [220, 180], [240, 80], [260, -60], [280, -180], [300, -290]]},
			{"name": "RidgeTrail", "half_width": 1.6,
			 "points": [[-180, 20], [-100, 60], [0, 80], [100, 60], [200, 20]]}
		]
	}


func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 80241
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 150.0; nb.fractal_octaves = 5

	var nr := FastNoiseLite.new()
	nr.seed = 80247
	nr.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nr.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	nr.frequency  = 1.0 / 80.0; nr.fractal_octaves = 4

	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			# Base ridge height: peaks along z=0 corridor
			var ridge_factor := 1.0 - absf(lz) / HALF_Z
			var ridge_h := ridge_factor * ridge_factor * 100.0
			var noise_h  := (nb.get_noise_2d(lx, lz) + 1.0) * 0.5 * 30.0
			var ridge_n  := (nr.get_noise_2d(lx, lz) + 1.0) * 0.5 * 20.0
			td.heights[j * td.n + i] = 8.0 + noise_h + ridge_h + ridge_n

	# Carve west pass (NW to SE)
	var pass_w_pts := [Vector2(-600, 280), Vector2(-320, 80), Vector2(-60, -60), Vector2(220, -200)]
	for s in pass_w_pts.size() - 1:
		var pa := pass_w_pts[s]; var pb := pass_w_pts[s + 1]
		var seg_len := pa.distance_to(pb)
		var steps := int(seg_len / 4.0)
		for step in steps:
			var t  := float(step) / steps
			var cp := pa.lerp(pb, t)
			# Grade: starts at ~40, ends at ~15
			var target_h := lerpf(40.0, 12.0, t + float(s) / (pass_w_pts.size() - 1))
			_flatten_area(cp.x, cp.y, 25.0, target_h)

	# Carve east pass
	for pz : float in [280, 180, 80, -60, -180, -290]:
		_flatten_area(240.0, pz, 20.0, lerpf(35.0, 10.0, (pz + 290.0) / 580.0))

	# 3 waterfall locations: flatten top plateau, let lower terrain steepen naturally
	for wf : Vector2 in [Vector2(-200, -60), Vector2(100, 50), Vector2(400, -100)]:
		_flatten_area(wf.x, wf.y - 30.0, 15.0, 55.0)  # top flat pool
		# Lower section stays steep naturally

	# Cave mouth area
	_flatten_area(-100.0, 50.0, 18.0, 28.0)  # approach ledge


func _build_structures() -> void:
	var root := structures_root

	# 3 waterfalls
	_build_waterfall(root, Vector3(-200, 0, -60))
	_build_waterfall(root, Vector3(100,  0,  50))
	_build_waterfall(root, Vector3(400,  0, -100))

	# Cave mouth
	_build_cave_mouth(root, Vector3(-100, 0, 50))

	# Viewpoint cairns
	_build_cairn(root, Vector3(-60, 0, -60))
	_build_cairn(root, Vector3(240, 0, 10))


func _build_waterfall(parent: Node3D, lpos: Vector3) -> void:
	var gnd_top := height_at_local(lpos.x, lpos.z - 25.0)
	var gnd_bot := height_at_local(lpos.x, lpos.z + 25.0)
	var drop    := gnd_top - gnd_bot - 2.0
	if drop < 4.0: drop = 10.0

	var kit := MeshKit.new(hash("fc_wfall" + str(lpos)), 0.04)
	var WATER_C := Color(0.60, 0.74, 0.88, 0.85)
	var FOAM_C  := Color(0.90, 0.95, 1.00, 0.95)
	var base    := lpos + Vector3(0, gnd_top - 2.0, -20.0)

	# Waterfall curtain (3 overlapping quads)
	for layer : float in [0.0, 0.08, 0.16]:
		kit.add_quad(
			base + Vector3(-2.0, 0, layer),    base + Vector3(2.0, 0, layer),
			base + Vector3(2.0, -drop, layer), base + Vector3(-2.0, -drop, layer),
			WATER_C, 0.9)
	# Foam at base
	kit.add_quad(
		base + Vector3(-2.5, -drop, -1.0), base + Vector3(2.5, -drop, -1.0),
		base + Vector3(2.5, -drop, 2.5),   base + Vector3(-2.5, -drop, 2.5),
		FOAM_C)
	# Framing rocks
	for side : float in [-1.0, 1.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(side * 2.4, -drop * 0.5, 0.0)),
			Vector3(0.9, drop * 0.6, 1.4), Color(0.42, 0.40, 0.38))

	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_cave_mouth(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("fc_cave"), 0.06)
	var STONE_C := Color(0.38, 0.36, 0.34)
	var DARK_C  := Color(0.08, 0.07, 0.07)
	# Rock arch sides
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(-3.0, 2.5, 0)), Vector3(1.5, 5.0, 2.5), STONE_C)
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(3.0, 2.5, 0)),  Vector3(1.5, 5.0, 2.5), STONE_C)
	# Arch top
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 5.5, 0)), Vector3(7.5, 1.5, 2.5), STONE_C)
	# Dark interior hint
	kit.add_quad(
		base + Vector3(-2.2, 0.1, -0.1), base + Vector3(2.2, 0.1, -0.1),
		base + Vector3(2.2, 4.8, -0.1), base + Vector3(-2.2, 4.8, -0.1),
		DARK_C)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_cairn(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("fc_cairn" + str(lpos)), 0.08)
	var col  := Color(0.46, 0.44, 0.40)
	for layer in 5:
		var sc := 1.0 - float(layer) * 0.15
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, float(layer) * 0.35 + 0.2, 0)),
			Vector3(sc * 0.9, 0.3, sc * 0.75), col)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_vegetation() -> void:
	var veg := vegetation_root
	var rng := RandomNumberGenerator.new(); rng.seed = 80261
	# Alpine trees on lower slopes (below 50 m)
	for _i in 600:
		var lx  := rng.randf_range(-HALF_X * 0.9, HALF_X * 0.9)
		var lz  := rng.randf_range(-HALF_Z * 0.9, HALF_Z * 0.9)
		var gnd := height_at_local(lx, lz)
		if gnd > 50.0 or gnd < 10.0: continue
		var kind := "fir" if rng.randf() > 0.4 else "pine"
		var mi   := MeshInstance3D.new()
		mi.mesh = PropMeshes.tree(kind, rng.randf_range(0.6, 1.1))
		mi.position = Vector3(lx, gnd, lz)
		veg.add_child(mi)
	# Rocky scrub
	for _i in 300:
		var lx  := rng.randf_range(-HALF_X * 0.9, HALF_X * 0.9)
		var lz  := rng.randf_range(-HALF_Z * 0.9, HALF_Z * 0.9)
		var gnd := height_at_local(lx, lz)
		if gnd < 15.0: continue
		_add_boulder(veg, Vector3(lx, gnd, lz),
			Vector3(rng.randf_range(0.8, 2.5), rng.randf_range(0.5, 1.6), rng.randf_range(0.7, 2.0)))


func _build_all() -> void:
	_setup_layout()
	_build_terrain()
	_build_structures()
	_build_vegetation()
	_place_markers()
	_publish_markers()


func _place_markers() -> void:
	var pts := [
		["frostcrest_pass_north",    "route_waypoint", Vector3(-60, 0, -60)],
		["frostcrest_overlook_east", "viewpoint",      Vector3(240, 0, 10)],
		["frostcrest_cave_mouth",    "landmark",       Vector3(-100, 0, 50)],
		["frostcrest_west_entry",    "route_waypoint", Vector3(-600, 0, 280)],
	]
	for p in pts:
		var lpos : Vector3 = p[2]
		lpos.y = height_at_local(lpos.x, lpos.z)
		_add_marker(p[0], p[1], lpos)
