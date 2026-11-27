class_name WarPlainsRegion
extends WorldRegion
## R03-AG | War Plains — large battle staging ground beyond the Great Wall.
## 1,000 m × 600 m predominantly flat terrain with military infrastructure.
## Provides siege positions, formation spawns, retreat corridors for Codex.

const HALF_X := 500.0
const HALF_Z := 300.0
const CELL   := 2.0


func _init() -> void:
	region_id         = "war_plains"
	region_half_size  = maxf(HALF_X, HALF_Z)
	cell_size         = CELL
	default_profile   = "war_plains"


func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": region_half_size, "playable_half": region_half_size * 0.88,
			"cell": CELL, "water_level": -50.0, "base_height": 2.0, "chunk_cells": 34
		},
		"trails": [
			{"name": "MilitaryRoad", "half_width": 6.0,
			 "points": [[0, -290], [0, -150], [0, 0], [0, 150], [0, 290]]},
			{"name": "EastFlank",    "half_width": 2.0,
			 "points": [[200, -280], [200, -150], [200, 0], [200, 150], [200, 280]]},
			{"name": "WestFlank",    "half_width": 2.0,
			 "points": [[-200, -280], [-200, -150], [-200, 0], [-200, 150], [-200, 280]]}
		]
	}


func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 90241
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 300.0; nb.fractal_octaves = 3

	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			# Near-flat with gentle south slope, tiny variation
			var base_h := (nb.get_noise_2d(lx, lz) + 1.0) * 0.5 * 3.0 + 1.5
			var south_slope := lz * 0.004  # very gentle south incline
			td.heights[j * td.n + i] = base_h + south_slope

	# Flatten military road corridor
	for lz in range(-290, 290, 20):
		_flatten_area(0.0, float(lz), 15.0, 2.0)

	# 3 siege machine platforms (20×20 m flat cleared)
	for siege_p : Vector2 in [Vector2(-180, 80), Vector2(0, 100), Vector2(180, 80)]:
		_flatten_area(siege_p.x, siege_p.y, 18.0, 2.5)

	# Forest/scrub boundary — elevated rims at edges
	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			var edge_x := maxf(0.0, absf(lx) - HALF_X * 0.72)
			var edge_z := maxf(0.0, absf(lz) - HALF_Z * 0.72)
			var rim    := (edge_x + edge_z) * 0.06
			td.heights[j * td.n + i] += rim


func _build_structures() -> void:
	var root := structures_root

	# 3 siege staging platforms with markers
	_build_siege_platform(root, Vector3(-180, 0, 80))
	_build_siege_platform(root, Vector3(0, 0, 100))
	_build_siege_platform(root, Vector3(180, 0, 80))

	# Military road waypost
	_build_waypost(root, Vector3(0, 0, -150))
	_build_waypost(root, Vector3(0, 0, 150))

	# 2 field watch posts on flanks
	_build_field_tower(root, Vector3(400, 0, 0))
	_build_field_tower(root, Vector3(-400, 0, 0))


func _build_siege_platform(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("wp_siege" + str(lpos)), 0.04)
	var EARTH := Color(0.26, 0.22, 0.17)
	var PLANK := Color(0.36, 0.28, 0.18)
	# Earthen rampart ring
	kit.add_quad(
		base + Vector3(-10, 0.15, -10), base + Vector3(10, 0.15, -10),
		base + Vector3(10, 0.15, 10),   base + Vector3(-10, 0.15, 10),
		EARTH)
	# Timber reinforcement strips
	for strip : float in [-8.0, 0.0, 8.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 0.3, strip)),
			Vector3(20.0, 0.12, 0.6), PLANK)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)


func _build_waypost(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("wp_post" + str(lpos)), 0.05)
	var WOOD := Color(0.34, 0.26, 0.17)
	var STONE_C := Color(0.44, 0.42, 0.38)
	# Stone plinth
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 0.3, 0)), Vector3(0.9, 0.6, 0.9), STONE_C)
	# Wooden post
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 1.8, 0)), Vector3(0.22, 2.4, 0.22), WOOD)
	# Crossarm
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 2.6, 0)), Vector3(1.4, 0.16, 0.16), WOOD)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)


func _build_field_tower(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("wp_ftower" + str(lpos)), 0.05)
	var WOOD := Color(0.34, 0.27, 0.18)
	var PLANK := Color(0.42, 0.33, 0.22)
	# Legs (4 corner posts)
	for cx : float in [-2.0, 2.0]:
		for cz : float in [-2.0, 2.0]:
			kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(cx, 3.0, cz)),
				Vector3(0.3, 6.0, 0.3), WOOD)
	# Platform
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 6.2, 0)),
		Vector3(5.0, 0.3, 5.0), PLANK)
	# Railing
	for side_x : float in [-2.5, 2.5]:
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(side_x, 6.75, 0)),
			Vector3(0.14, 1.0, 5.0), WOOD)
	for side_z : float in [-2.5, 2.5]:
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 6.75, side_z)),
			Vector3(5.0, 1.0, 0.14), WOOD)
	# Ladder
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(2.2, 3.0, 0)),
		Vector3(0.6, 6.0, 0.14), WOOD)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(5.0, 0.4, 5.0); cs.position = base + Vector3(0, 6.2, 0)
	cs.shape = box; body.add_child(cs); body.collision_layer = Layers.WORLD; parent.add_child(body)


func _build_vegetation() -> void:
	var veg := vegetation_root
	var rng := RandomNumberGenerator.new(); rng.seed = 90261
	# Minimal vegetation in battle area, denser at edges
	for _i in 1200:
		var lx  := rng.randf_range(-HALF_X * 0.9, HALF_X * 0.9)
		var lz  := rng.randf_range(-HALF_Z * 0.9, HALF_Z * 0.9)
		# Skip open battle ground (central 60% area)
		if absf(lx) < HALF_X * 0.6 and absf(lz) < HALF_Z * 0.6: continue
		var gnd := height_at_local(lx, lz)
		var kind := "pine" if (rng.randf() > 0.7 and absf(lx) > HALF_X * 0.5) else \
		            ("grass_tall" if rng.randf() > 0.5 else "grass")
		var mi   := MeshInstance3D.new()
		if kind in ["pine"]:
			mi.mesh = PropMeshes.tree(kind, rng.randf_range(0.8, 1.3))
		else:
			mi.mesh = PropMeshes.grass(kind, rng.randf_range(0.7, 1.1))
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
	# Battle-critical markers (Codex integration via C-13)
	var pts := [
		# Siege positions (kind: "siege_position")
		["wp_siege_west",        "siege_position",  Vector3(-180, 0, 80)],
		["wp_siege_centre",      "siege_position",  Vector3(0,    0, 100)],
		["wp_siege_east",        "siege_position",  Vector3(180,  0, 80)],
		# Formation spawns (kind: "formation_spawn") — 5 east, 5 west grid
		["wp_formation_e1",      "formation_spawn", Vector3(100,  0, -200)],
		["wp_formation_e2",      "formation_spawn", Vector3(200,  0, -200)],
		["wp_formation_e3",      "formation_spawn", Vector3(300,  0, -200)],
		["wp_formation_e4",      "formation_spawn", Vector3(100,  0, -100)],
		["wp_formation_e5",      "formation_spawn", Vector3(200,  0, -100)],
		["wp_formation_w1",      "formation_spawn", Vector3(-100, 0, -200)],
		["wp_formation_w2",      "formation_spawn", Vector3(-200, 0, -200)],
		["wp_formation_w3",      "formation_spawn", Vector3(-300, 0, -200)],
		["wp_formation_w4",      "formation_spawn", Vector3(-100, 0, -100)],
		["wp_formation_w5",      "formation_spawn", Vector3(-200, 0, -100)],
		# Retreat corridors
		["wp_retreat_east",      "retreat_route",   Vector3(400, 0, -280)],
		["wp_retreat_west",      "retreat_route",   Vector3(-400, 0, -280)],
		# Route waypoints
		["wp_great_wall_south",  "route_waypoint",  Vector3(0, 0, -290)],
		["wp_vareth_approach",   "route_waypoint",  Vector3(0, 0, 290)],
	]
	for p in pts:
		var lpos : Vector3 = p[2]
		lpos.y = height_at_local(lpos.x, lpos.z)
		_add_marker(p[0], p[1], lpos)
