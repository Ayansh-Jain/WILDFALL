class_name NorthmereRegion
extends WorldRegion
## R03-AG | Northmere — riverside trade settlement.
## 700 m × 700 m river-delta terrain, east of Eldoria.
## Features: main river (20 m wide), wooden bridge, 7 waterside buildings, dock.

const HALF := 350.0
const CELL := 2.0

var _river_x := 160.0  # river runs N-S at this local X


func _init() -> void:
	region_id         = "northmere"
	region_half_size  = HALF
	cell_size         = CELL
	default_profile   = "misty_valley"


func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": HALF, "playable_half": HALF * 0.88,
			"cell": CELL, "water_level": 0.0, "base_height": 2.5, "chunk_cells": 34
		},
		"rivers": [{
			"name": "NorthmereRiver", "half_width": 10.0, "depth": 2.8, "bank": 12.0,
			"points": [[160, -340], [158, -200], [155, -80], [150, 60], [148, 200], [145, 340]]
		}],
		"bridges": [{
			"name": "NorthmereWoodBridge", "style": "wood",
			"a": [120.0, 40.0], "b": [186.0, 40.0], "width": 3.6
		}],
		"trails": [
			{"name": "SouthernTradeRoad", "half_width": 2.6,
			 "points": [[0, 340], [20, 220], [60, 120], [100, 60], [120, 40]]},
			{"name": "NorthPassRoute",    "half_width": 2.2,
			 "points": [[186, 40], [200, -60], [220, -180], [240, -300]]},
			{"name": "DocksLane",         "half_width": 1.8,
			 "points": [[120, 40], [130, 20], [140, 0], [148, -20]]}
		]
	}


func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 60241
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 160.0; nb.fractal_octaves = 4
	var nr := FastNoiseLite.new()
	nr.seed = 60247; nr.frequency = 1.0 / 50.0

	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			var base_h := (nb.get_noise_2d(lx, lz) + 1.0) * 0.5 * 8.0 + 2.0
			var detail  := (nr.get_noise_2d(lx, lz) + 1.0) * 0.5 * 1.5
			# Flood plain: lower near river
			var r_dist := absf(lx - _river_x)
			var flat_w := 40.0
			if r_dist < flat_w:
				var t := smoothstep(flat_w, 8.0, r_dist)
				base_h = lerpf(base_h, -0.3, t)
			td.heights[j * td.n + i] = base_h + detail

	# Flatten dockside area
	_flatten_area(130.0, 10.0, 35.0, 1.6)
	# Flatten bridge approaches
	_flatten_area(120.0, 40.0, 18.0, 1.4)
	_flatten_area(186.0, 40.0, 18.0, 1.4)


func _build_structures() -> void:
	var root := structures_root
	var PLANK  := Color(0.34, 0.26, 0.17)
	var STONE_B := Color(0.42, 0.40, 0.37)
	var THATCH := Color(0.50, 0.40, 0.25)
	var TILE   := Color(0.46, 0.33, 0.24)

	# Fishing huts (2)
	for pos : Vector3 in [Vector3(100, 0, 20), Vector3(90, 0, -10)]:
		var gnd := height_at_local(pos.x, pos.z)
		_add_simple_house(root, pos + Vector3(0, gnd, 0), deg_to_rad(80),
			6.0, 4.5, 2.8, 1.5, PLANK, THATCH)

	# Trade buildings (2)
	for pos : Vector3 in [Vector3(70, 0, 50), Vector3(55, 0, 20)]:
		var gnd := height_at_local(pos.x, pos.z)
		_add_simple_house(root, pos + Vector3(0, gnd, 0), deg_to_rad(-10),
			9.0, 6.0, 4.5, 1.8, STONE_B, TILE)

	# Inn (larger, 2-storey approximation)
	var inn_gnd := height_at_local(50.0, 60.0)
	_build_inn(root, Vector3(50, inn_gnd, 60))

	# Waterside market stalls (2)
	for pos : Vector3 in [Vector3(105, 0, 60), Vector3(118, 0, 50)]:
		var gnd := height_at_local(pos.x, pos.z)
		_build_stall(root, pos + Vector3(0, gnd, 0))

	# Dock platform
	_build_dock(root, Vector3(_river_x - 12.0, 0, 10.0))

	# Wood bridge (via Bridge.build)
	_build_wooden_bridge(root)

	# Reeds along riverbank
	_build_reeds(root)


func _build_inn(parent: Node3D, pos: Vector3) -> void:
	var kit  := MeshKit.new(hash("nm_inn"), 0.05)
	var WALL := Color(0.68, 0.64, 0.55)
	var BEAM := Color(0.30, 0.24, 0.16)
	var ROOF := Color(0.44, 0.33, 0.22)
	# Ground floor
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 2.2, 0)), Vector3(12.0, 4.4, 8.0), WALL)
	# Timber framing overlay
	for beam_x : float in [-5.0, -1.5, 1.5, 5.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(beam_x, 2.2, -4.05)), Vector3(0.2, 4.4, 0.2), BEAM)
	# Upper floor (slightly cantilevered)
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 5.8, 0)), Vector3(12.8, 2.8, 8.4), BEAM)
	# Gabled roof
	for s in [-1.0, 1.0]:
		kit.add_tri(
			pos + Vector3(-6.4, 7.2, s * 4.2),
			pos + Vector3(6.4, 7.2, s * 4.2),
			pos + Vector3(0, 10.0, s * 4.2),
			ROOF)
	kit.add_quad(
		pos + Vector3(-6.4, 7.2, -4.2), pos + Vector3(-6.4, 7.2, 4.2),
		pos + Vector3(0, 10.0, 4.2),    pos + Vector3(0, 10.0, -4.2),
		ROOF * Color(0.9, 0.9, 0.9))
	kit.add_quad(
		pos + Vector3(6.4, 7.2, 4.2),   pos + Vector3(6.4, 7.2, -4.2),
		pos + Vector3(0, 10.0, -4.2),   pos + Vector3(0, 10.0, 4.2),
		ROOF * Color(0.9, 0.9, 0.9))
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(12.0, 10.0, 8.0); cs.shape = box; cs.position = pos + Vector3(0, 5.0, 0)
	body.add_child(cs); body.collision_layer = Layers.WORLD; parent.add_child(body)
	# Sign post
	_add_lantern_post(parent, pos + Vector3(-6.5, 0, 0), 1.3)


func _build_stall(parent: Node3D, pos: Vector3) -> void:
	var kit  := MeshKit.new(hash("nm_stall" + str(pos)), 0.06)
	var WOOD := Color(0.36, 0.28, 0.18)
	var ROOF := Color(0.52, 0.42, 0.26)
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.5, 0)), Vector3(4.0, 0.14, 2.5), ROOF)
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(-1.9, 0.75, 0)), Vector3(0.14, 1.5, 2.5), WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(1.9, 0.75, 0)),  Vector3(0.14, 1.5, 2.5), WOOD)
	# Goods display surface
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.0, 0)), Vector3(3.8, 0.1, 2.3), Color(0.44, 0.35, 0.22))
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)


func _build_dock(parent: Node3D, dock_pos: Vector3) -> void:
	var kit  := MeshKit.new(hash("nm_dock"), 0.05)
	var PLANK := Color(0.32, 0.25, 0.16)
	var DARK  := Color(0.22, 0.17, 0.11)
	# Platform 24 m × 8 m
	kit.add_quad(
		dock_pos + Vector3(0, 0.6, 0), dock_pos + Vector3(24, 0.6, 0),
		dock_pos + Vector3(24, 0.6, 8), dock_pos + Vector3(0, 0.6, 8),
		PLANK)
	# Planks
	for p in 12:
		var px := float(p) * 2.0
		kit.add_box(Transform3D(Basis.IDENTITY, dock_pos + Vector3(px + 1.0, 0.65, 4.0)),
			Vector3(1.9, 0.08, 7.8), PLANK)
	# Support posts into water
	for pp in 6:
		var px := float(pp) * 4.0 + 2.0
		for pz : float in [0.5, 7.5]:
			kit.add_box(Transform3D(Basis.IDENTITY, dock_pos + Vector3(px, 0.0, pz)),
				Vector3(0.22, 1.2, 0.22), DARK)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)
	# Collision
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var box := BoxShape3D.new()
	box.size = Vector3(24, 0.6, 8); cs.position = dock_pos + Vector3(12, 0.3, 4)
	cs.shape = box; body.add_child(cs); body.collision_layer = Layers.WORLD; parent.add_child(body)


func _build_wooden_bridge(parent: Node3D) -> void:
	var proxy := World.new()
	proxy.terrain_data = td; proxy.water_level = 0.0; proxy.layout = layout
	parent.add_child(proxy)
	var bridge_def : Dictionary = {"name": "NorthmereWoodBridge", "style": "wood",
	                               "a": [120.0, 40.0], "b": [186.0, 40.0], "width": 3.6}
	var defs := layout.list("bridges")
	if defs.size() > 0:
		bridge_def = defs[0]
	Bridge.build(parent, proxy, bridge_def)
	proxy.queue_free()


func _build_reeds(parent: Node3D) -> void:
	var kit := MeshKit.new(hash("nm_reeds"), 0.08)
	var REED := Color(0.44, 0.52, 0.28)
	var rng  := RandomNumberGenerator.new(); rng.seed = 60280
	for _i in 200:
		var lz   := rng.randf_range(-HALF * 0.8, HALF * 0.8)
		var lx   := _river_x - 12.0 + rng.randf_range(-8.0, 8.0)
		var gnd  := height_at_local(lx, lz)
		var h    := rng.randf_range(1.2, 2.2)
		# Simple vertical quad pair for reed
		for rot_y : float in [0.0, PI * 0.5]:
			kit.add_quad(
				Vector3(lx - 0.1, gnd, lz) + Vector3(cos(rot_y), 0, sin(rot_y)) * 0.1,
				Vector3(lx + 0.1, gnd, lz) + Vector3(cos(rot_y), 0, sin(rot_y)) * -0.1,
				Vector3(lx + 0.1, gnd + h, lz) + Vector3(cos(rot_y), 0, sin(rot_y)) * -0.1,
				Vector3(lx - 0.1, gnd + h, lz) + Vector3(cos(rot_y), 0, sin(rot_y)) * 0.1,
				REED, 0.6)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)


func _build_vegetation() -> void:
	var veg := vegetation_root
	var rng := RandomNumberGenerator.new(); rng.seed = 60261
	for _i in 500:
		var lx  := rng.randf_range(-HALF * 0.8, HALF * 0.8)
		var lz  := rng.randf_range(-HALF * 0.8, HALF * 0.8)
		if absf(lx - _river_x) < 15.0: continue
		var gnd := height_at_local(lx, lz)
		if gnd < 0.5: continue
		var kind := "oak" if rng.randf() > 0.85 else ("grass_tall" if rng.randf() > 0.5 else "grass")
		var mi := MeshInstance3D.new()
		if kind == "oak":
			mi.mesh = PropMeshes.tree("oak", rng.randf_range(0.8, 1.3))
		else:
			mi.mesh = PropMeshes.grass(kind, rng.randf_range(0.8, 1.2))
		mi.position = Vector3(lx, gnd, lz)
		veg.add_child(mi)


func _build_all() -> void:
	_setup_layout()
	_build_terrain()
	_build_water_plane()
	_build_structures()
	_build_vegetation()
	_place_markers()
	_publish_markers()


func _place_markers() -> void:
	var pts := [
		["northmere_docks",         "landmark",       Vector3(130, 0, 10)],
		["northmere_bridge",        "landmark",       Vector3(153, 0, 40)],
		["northmere_south_arrival", "route_waypoint", Vector3(0, 0, 340)],
		["northmere_north_road",    "route_waypoint", Vector3(240, 0, -300)],
	]
	for p in pts:
		var lpos : Vector3 = p[2]
		lpos.y = height_at_local(lpos.x, lpos.z)
		_add_marker(p[0], p[1], lpos)
