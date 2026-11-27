class_name AshfordRegion
extends WorldRegion
## R03-AG | Ashford — rural agricultural village.
## 600 m × 600 m gently rolling farmland, east of Golden Valley.
## Future-damage-ready: buildings under AshfordBuildings node, roads under AshfordRoads.

const HALF := 300.0
const CELL := 2.0


func _init() -> void:
	region_id         = "ashford"
	region_half_size  = HALF
	cell_size         = CELL
	default_profile   = "golden_day"


func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": HALF, "playable_half": HALF * 0.88,
			"cell": CELL, "water_level": 0.0, "base_height": 3.5, "chunk_cells": 34
		},
		"rivers": [{
			"name": "AshfordMill Stream", "half_width": 3.0, "depth": 1.2, "bank": 5.0,
			"points": [[-20, -280], [-10, -180], [0, -80], [10, 0], [20, 100], [30, 240], [40, 290]]
		}],
		"trails": [
			{"name": "GoldenValleyRoad", "half_width": 2.6,
			 "points": [[-280, 60], [-200, 40], [-120, 20], [-40, 0], [0, -10], [60, -20]]},
			{"name": "NorthmereTrack",   "half_width": 2.0,
			 "points": [[60, -20], [120, -60], [180, -120], [240, -180], [290, -260]]},
			{"name": "VillageLane",      "half_width": 1.6,
			 "points": [[-30, 60], [-10, 70], [20, 80], [60, 70], [80, 50]]}
		]
	}


func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 50241
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 150.0
	nb.fractal_octaves = 4
	var nr := FastNoiseLite.new()
	nr.seed = 50247; nr.frequency = 1.0 / 50.0

	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			var base_h := (nb.get_noise_2d(lx, lz) + 1.0) * 0.5 * 10.0 + 3.0
			var detail  := (nr.get_noise_2d(lx, lz) + 1.0) * 0.5 * 1.5
			td.heights[j * td.n + i] = base_h + detail

	# Flatten village green
	_flatten_area(20.0, 60.0, 60.0, 5.5)
	# Flatten farmland strips (3 strips)
	for strip_z : float in [-80.0, -20.0, 40.0]:
		_flatten_area(-80.0, strip_z, 50.0, 5.0)
	# Mill stream corridor
	for lz : float in [-280, -200, -100, 0, 100, 240]:
		for j in td.n:
			for i in td.n:
				var wx := td.origin + i * cell_size
				var wz := td.origin + j * cell_size
				var d  := Vector2(wx - 10.0, wz - lz).length()
				if d < 7.0:
					var t := smoothstep(7.0, 2.5, d)
					td.heights[j * td.n + i] = lerpf(td.heights[j * td.n + i], -0.2, t)


func _build_structures() -> void:
	var bldgs := Node3D.new(); bldgs.name = "AshfordBuildings"; structures_root.add_child(bldgs)
	var roads  := Node3D.new(); roads.name  = "AshfordRoads";  structures_root.add_child(roads)

	# Farmhouses
	var THATCH  := Color(0.52, 0.42, 0.26)
	var PLASTER := Color(0.74, 0.70, 0.60)
	var BEAM    := Color(0.34, 0.27, 0.18)
	var configs := [
		[Vector3(-60, 0, 50),  0.0,              9.0, 6.0, 3.6, 2.0, PLASTER, THATCH],
		[Vector3(-30, 0, 80),  deg_to_rad(20),   8.0, 5.5, 3.4, 1.8, PLASTER, THATCH],
		[Vector3(40, 0, 70),   deg_to_rad(-15),  10.0, 6.5, 3.8, 2.0, BEAM, THATCH],
		[Vector3(80, 0, 40),   deg_to_rad(35),   8.5, 5.0, 3.5, 1.8, PLASTER, THATCH],
		[Vector3(-80, 0, -20), deg_to_rad(-5),   7.0, 5.0, 3.3, 1.7, BEAM, THATCH],
		[Vector3(60, 0, -40),  deg_to_rad(10),   7.5, 5.0, 3.4, 1.8, PLASTER, THATCH],
	]
	for cfg in configs:
		var lpos  : Vector3 = cfg[0]
		var rot_y : float   = cfg[1]
		var gnd := height_at_local(lpos.x, lpos.z)
		_add_simple_house(bldgs, lpos + Vector3(0, gnd, 0), rot_y, cfg[2], cfg[3], cfg[4], cfg[5], cfg[6], cfg[7])

	# Two barns
	for barn_pos : Vector3 in [Vector3(-100, 0, 70), Vector3(110, 0, 20)]:
		var gnd := height_at_local(barn_pos.x, barn_pos.z)
		_add_simple_house(bldgs, barn_pos + Vector3(0, gnd, 0), deg_to_rad(5),
			14.0, 7.5, 4.0, 1.4, BEAM, Color(0.40, 0.30, 0.20))

	# Stone well (village green)
	var well_gnd := height_at_local(20.0, 65.0)
	_build_well(bldgs, Vector3(20, well_gnd, 65))

	# Animal pens
	for pen_ctr : Vector3 in [Vector3(-120, 0, -60), Vector3(90, 0, -20), Vector3(-60, 0, 110)]:
		var gnd := height_at_local(pen_ctr.x, pen_ctr.z)
		_build_animal_pen(bldgs, pen_ctr + Vector3(0, gnd, 0), 12.0, 8.0)

	# Farmland strips (flat geometry)
	_build_farmland(bldgs)


func _build_well(parent: Node3D, pos: Vector3) -> void:
	var kit := MeshKit.new(hash("ash_well"), 0.04)
	var STONE_C := Color(0.46, 0.44, 0.40)
	var WOOD_C  := Color(0.32, 0.25, 0.15)
	for s in 8:
		var a0 := TAU * s / 8; var a1 := TAU * (s + 1) / 8
		kit.add_quad(
			pos + Vector3(cos(a0)*0.7, 0, sin(a0)*0.7),
			pos + Vector3(cos(a1)*0.7, 0, sin(a1)*0.7),
			pos + Vector3(cos(a1)*0.7, 0.9, sin(a1)*0.7),
			pos + Vector3(cos(a0)*0.7, 0.9, sin(a0)*0.7),
			STONE_C)
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(-0.7, 1.5, 0)), Vector3(0.14, 1.2, 0.14), WOOD_C)
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0.7, 1.5, 0)),  Vector3(0.14, 1.2, 0.14), WOOD_C)
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 2.1, 0)),    Vector3(1.6, 0.14, 0.14), WOOD_C)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_animal_pen(parent: Node3D, center: Vector3, w: float, d: float) -> void:
	# 4-sided dry-stone fence
	var hw := w * 0.5; var hd := d * 0.5
	var corners := [
		center + Vector3(-hw, 0, -hd), center + Vector3(hw, 0, -hd),
		center + Vector3(hw, 0, hd),   center + Vector3(-hw, 0, hd)
	]
	for s in 4:
		_add_dry_stone_wall_segment(parent, corners[s], corners[(s + 1) % 4], 1.1)


func _build_farmland(parent: Node3D) -> void:
	var kit := MeshKit.new(hash("ash_farm"), 0.03)
	var SOIL := Color(0.30, 0.25, 0.18)
	var CROP := Color(0.52, 0.48, 0.28)
	# 3 strips of alternating soil/crop rows
	for strip in 3:
		var base_z := float(strip) * 60.0 - 100.0
		for row in 8:
			var col := CROP if (row % 2 == 0) else SOIL
			var rz  := base_z + float(row) * 5.0
			kit.add_quad(
				Vector3(-130, 0.08, rz), Vector3(-40, 0.08, rz),
				Vector3(-40, 0.08, rz + 4.0), Vector3(-130, 0.08, rz + 4.0),
				col)
	var mi := MeshInstance3D.new(); mi.mesh = kit.build(); mi.material_override = PROPS_MAT
	parent.add_child(mi)


func _build_vegetation() -> void:
	var veg := vegetation_root
	var rng := RandomNumberGenerator.new(); rng.seed = 50261

	# Hedgerows along field boundaries
	for _i in 120:
		var lx  := rng.randf_range(-140.0, -30.0)
		var lz  := rng.randf_range(-120.0, 120.0)
		if int((lz + 120.0) / 60.0) != int((lz + 60.0) / 60.0):
			continue  # near strip boundaries
		var gnd := height_at_local(lx, lz)
		var mi  := MeshInstance3D.new()
		mi.mesh = PropMeshes.tree("oak", rng.randf_range(0.4, 0.7))
		mi.position = Vector3(lx, gnd, lz)
		veg.add_child(mi)

	# Village oaks and grasses
	for _i in 600:
		var lx  := rng.randf_range(-HALF * 0.8, HALF * 0.8)
		var lz  := rng.randf_range(-HALF * 0.8, HALF * 0.8)
		if absf(lx - 20) < 60 and absf(lz - 60) < 60:
			continue  # skip village green
		var gnd := height_at_local(lx, lz)
		if gnd < 1.0: continue
		var kind := "oak" if rng.randf() > 0.85 else ("grass_tall" if rng.randf() > 0.4 else "grass")
		var sc  := rng.randf_range(0.7, 1.2)
		var mi  := MeshInstance3D.new()
		if kind in ["pine", "oak", "fir", "birch"]:
			mi.mesh = PropMeshes.tree(kind, sc)
		else:
			mi.mesh = PropMeshes.grass(kind, sc)
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
		["ashford_village_green",  "settlement",    Vector3(20, 0, 65)],
		["ashford_north_approach", "route_waypoint", Vector3(0, 0, -280)],
		["ashford_east_road",      "route_waypoint", Vector3(290, 0, -260)],
		["ashford_combat_field",   "combat_arena",  Vector3(200, 0, 180)],
	]
	for p in pts:
		var lpos : Vector3 = p[2]
		lpos.y = height_at_local(lpos.x, lpos.z)
		_add_marker(p[0], p[1], lpos)
