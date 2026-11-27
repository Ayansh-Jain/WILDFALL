class_name WhisperingWoodsRegion
extends WorldRegion
## R03-AG | Whispering Woods — dense ancient forest, NW of Eldoria.
## 900 m × 900 m with uneven 4-12 m elevation, 3 density zones,
## winding forest path, log bridges, abandoned camp, ruined foundations.

const HALF := 450.0
const CELL := 2.0


func _init() -> void:
	region_id         = "whispering_woods"
	region_half_size  = HALF
	cell_size         = CELL
	default_profile   = "whispering_woods"


func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": HALF, "playable_half": HALF * 0.88,
			"cell": CELL, "water_level": -50.0, "base_height": 5.0, "chunk_cells": 34
		},
		"trails": [
			{"name": "ForestMainPath", "half_width": 2.0,
			 "points": [[440, 100], [300, 60], [140, 20], [0, 0], [-140, -30], [-300, -80], [-430, -120]]},
			{"name": "ClearingPath",   "half_width": 1.6,
			 "points": [[0, 0], [-30, -60], [-60, -120], [-50, -180], [0, -200]]},
			{"name": "NorthLoop",      "half_width": 1.4,
			 "points": [[-140, -30], [-180, 60], [-200, 180], [-160, 260], [-80, 290], [0, 260]]}
		],
		"rivers": [{
			"name": "ForestStream",   "half_width": 2.5, "depth": 1.0, "bank": 5.0,
			"points": [[-100, -440], [-80, -300], [-60, -180], [-40, -60], [-20, 60], [0, 180]]
		}, {
			"name": "NorthStream",    "half_width": 2.0, "depth": 0.8, "bank": 4.0,
			"points": [[100, 440], [60, 320], [30, 200], [10, 100], [-10, 20]]
		}]
	}


func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 70241
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 100.0; nb.fractal_octaves = 5

	var nr := FastNoiseLite.new()
	nr.seed = 70247; nr.frequency = 1.0 / 40.0; nr.fractal_octaves = 3

	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			var base_h := (nb.get_noise_2d(lx, lz) + 1.0) * 0.5 * 10.0 + 4.0
			var detail  := (nr.get_noise_2d(lx, lz) + 1.0) * 0.5 * 2.5
			td.heights[j * td.n + i] = base_h + detail

	# Central clearing (flat)
	_flatten_area(0.0, -200.0, 40.0, 7.5)
	# Stream corridors
	for lz : float in [-440, -300, -180, -60, 60, 180]:
		for jj in td.n:
			for ii in td.n:
				var wx := td.origin + ii * cell_size; var wz := td.origin + jj * cell_size
				var d := Vector2(wx - (-80.0 + lz * 0.1), wz - lz).length()
				if d < 6.0:
					var t := smoothstep(6.0, 2.0, d)
					td.heights[jj * td.n + ii] = lerpf(td.heights[jj * td.n + ii], 4.0, t)


func _build_structures() -> void:
	var root := structures_root

	# Abandoned camp in central clearing
	_build_abandoned_camp(root, Vector3(0, 0, -200))

	# 2 ruined stone foundations
	_build_ruined_foundation(root, Vector3(-220, 0, 80))
	_build_ruined_foundation(root, Vector3(160, 0, -120))

	# 6 large mossy boulder formations
	for bp : Vector3 in [
		Vector3(-180, 0, -60), Vector3(80, 0, 100), Vector3(-60, 0, 180),
		Vector3(260, 0, -40),  Vector3(-300, 0, 200), Vector3(120, 0, -300)
	]:
		var gnd := height_at_local(bp.x, bp.z)
		_build_boulder_formation(root, bp + Vector3(0, gnd, 0))

	# 2 stream crossings (narrow log bridges)
	_build_log_bridge(root, Vector3(-50.0, 0, -60.0), Vector3(-30.0, 0, -60.0))
	_build_log_bridge(root, Vector3(5.0, 0, 110.0), Vector3(25.0, 0, 110.0))


func _build_abandoned_camp(parent: Node3D, center_local: Vector3) -> void:
	var gnd := height_at_local(center_local.x, center_local.z)
	var base := center_local + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("ww_camp"), 0.08)
	var ASH  := Color(0.26, 0.24, 0.22)
	var WOOD := Color(0.28, 0.22, 0.14)
	# Stone fire ring
	for s in 10:
		var a := TAU * s / 10
		var stone_p := base + Vector3(cos(a) * 1.2, 0.2, sin(a) * 1.2)
		kit.add_box(Transform3D(Basis.from_euler(Vector3(0, a, 0)), stone_p),
			Vector3(0.4, 0.3, 0.35), Color(0.44, 0.42, 0.40))
	# Ash/char centre
	kit.add_quad(
		base + Vector3(-0.9, 0.08, -0.9), base + Vector3(0.9, 0.08, -0.9),
		base + Vector3(0.9, 0.08, 0.9),  base + Vector3(-0.9, 0.08, 0.9),
		ASH)
	# 2 collapsed lean-tos
	for side : float in [-1.0, 1.0]:
		var lean_base := base + Vector3(side * 4.5, 0, 1.0)
		# Fallen horizontal pole
		kit.add_box(Transform3D(Basis.from_euler(Vector3(0, side * 0.3, 0.6)), lean_base + Vector3(0, 1.0, 0)),
			Vector3(0.14, 3.5, 0.14), WOOD)
		# Roof panel lying at angle
		kit.add_quad(
			lean_base + Vector3(-1.2, 0.3, -1.0), lean_base + Vector3(1.2, 0.3, -1.0),
			lean_base + Vector3(1.2, 1.4, 1.0),   lean_base + Vector3(-1.2, 1.4, 1.0),
			WOOD * Color(0.85, 0.85, 0.85))
	# Fallen log
	kit.add_box(Transform3D(Basis.from_euler(Vector3(0, 0.8, 0.1)), base + Vector3(2.0, 0.3, 2.5)),
		Vector3(0.4, 0.4, 2.8), Color(0.32, 0.26, 0.18))
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)


func _build_ruined_foundation(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("ww_ruin" + str(lpos)), 0.09)
	var STONE_C := Color(0.42, 0.41, 0.38)
	var MOSS_C  := Color(0.26, 0.38, 0.22)
	# 3 partial walls (L + stub)
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 0.6, -5.0)), Vector3(10.0, 1.2, 0.5), STONE_C)
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(-4.75, 0.6, -1.5)), Vector3(0.5, 1.2, 7.0), STONE_C)
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(2.0, 0.4, 2.0)), Vector3(4.0, 0.8, 0.5), STONE_C)
	# Moss ground cover
	kit.add_quad(
		base + Vector3(-5.0, 0.08, -5.0), base + Vector3(5.0, 0.08, -5.0),
		base + Vector3(5.0, 0.08, 5.0), base + Vector3(-5.0, 0.08, 5.0),
		MOSS_C)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_boulder_formation(parent: Node3D, pos: Vector3) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = hash("ww_bld" + str(pos))
	for b in 3:
		var offset := Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
		var sc := Vector3(rng.randf_range(1.5, 3.5), rng.randf_range(1.0, 2.5), rng.randf_range(1.2, 3.0))
		_add_boulder(parent, pos + offset, sc)


func _build_log_bridge(parent: Node3D, a_local: Vector3, b_local: Vector3) -> void:
	var gnd_a := height_at_local(a_local.x, a_local.z)
	var gnd_b := height_at_local(b_local.x, b_local.z)
	var a3 := a_local + Vector3(0, gnd_a + 0.3, 0)
	var b3 := b_local + Vector3(0, gnd_b + 0.3, 0)
	var len := a3.distance_to(b3)
	var kit := MeshKit.new(hash("ww_log" + str(a_local)), 0.06)
	var WOOD := Color(0.30, 0.24, 0.16)
	# Two parallel logs
	var dir  := (b3 - a3).normalized()
	var perp := dir.cross(Vector3.UP)
	for side : float in [-0.4, 0.4]:
		var log_ctr := (a3 + b3) * 0.5 + perp * side
		kit.add_box(Transform3D(Basis(perp, Vector3.UP, dir), log_ctr), Vector3(0.28, 0.28, len), WOOD)
	# Plank strips
	var seg_count := maxi(3, int(len / 0.6))
	for s in seg_count:
		var t := float(s) / seg_count
		var plank_ctr := a3.lerp(b3, t + 0.5 / seg_count)
		kit.add_box(Transform3D(Basis(perp, Vector3.UP, dir), plank_ctr),
			Vector3(1.0, 0.1, 0.55), Color(0.34, 0.26, 0.17))
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)
	# Collision
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.3, len)
	var ctr := (a3 + b3) * 0.5; cs.position = ctr
	cs.shape = box; body.add_child(cs); body.collision_layer = Layers.WORLD; parent.add_child(body)


func _build_vegetation() -> void:
	var veg := vegetation_root
	var rng := RandomNumberGenerator.new(); rng.seed = 70261

	# Deep forest (central) — fir and pine dense pack
	for _i in 2000:
		var lx := rng.randf_range(-HALF * 0.75, HALF * 0.75)
		var lz := rng.randf_range(-HALF * 0.75, HALF * 0.75)
		# Skip central clearing
		if Vector2(lx, lz + 200).length() < 50.0: continue
		# Skip main trail
		if absf(lz - lx * 0.3) < 12.0 and absf(lx) < 400.0: continue
		var gnd := height_at_local(lx, lz)
		if gnd < 2.0: continue
		var dist_ctr := Vector2(lx, lz).length() / HALF
		var density := 1.0 - dist_ctr * 0.4
		if rng.randf() > density: continue
		var kind := "fir" if rng.randf() > 0.4 else ("pine" if rng.randf() > 0.5 else "birch")
		var sc   := rng.randf_range(0.7, 1.4)
		var mi   := MeshInstance3D.new()
		mi.mesh = PropMeshes.tree(kind, sc)
		mi.position = Vector3(lx, gnd, lz)
		veg.add_child(mi)

	# Fern carpet near clearing
	for _i in 400:
		var lx := rng.randf_range(-120.0, 120.0)
		var lz := rng.randf_range(-320.0, -80.0)
		var gnd := height_at_local(lx, lz)
		var mi  := MeshInstance3D.new()
		mi.mesh = PropMeshes.grass("grass_tall", rng.randf_range(0.6, 1.0))
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
		["ww_east_entrance",    "route_waypoint",  Vector3(440, 0, 100)],
		["ww_west_exit",        "route_waypoint",  Vector3(-430, 0, -120)],
		["ww_abandoned_camp",   "landmark",        Vector3(0, 0, -200)],
		["ww_deep_viewpoint",   "viewpoint",       Vector3(-160, 0, 160)],
		["ww_north_loop_crest", "viewpoint",       Vector3(-160, 0, 260)],
	]
	for p in pts:
		var lpos : Vector3 = p[2]
		lpos.y = height_at_local(lpos.x, lpos.z)
		_add_marker(p[0], p[1], lpos)
