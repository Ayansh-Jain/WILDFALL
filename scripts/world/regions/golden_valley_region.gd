class_name GoldenValleyRegion
extends WorldRegion
## R03-AG | Golden Valley — primary visual showcase region.
## 1,200 m × 1,200 m valley south of Eldoria.
## Features: rolling golden hills, farmland terraces, winding river,
## stone bridge, forest edge, distant mountains, scenic viewpoints.

const HALF := 600.0
const CELL := 2.0

var _river_points : Array[Vector2] = [
	Vector2(-40, -560), Vector2(-30, -440), Vector2(0, -300),
	Vector2(20, -150),  Vector2(50, 0),     Vector2(80, 180),
	Vector2(130, 380),  Vector2(200, 560)
]


func _init() -> void:
	region_id         = "golden_valley"
	region_half_size  = HALF
	cell_size         = CELL
	default_profile   = "golden_day"


func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": HALF, "playable_half": HALF * 0.88,
			"cell": CELL, "water_level": 0.0, "base_height": 4.0, "chunk_cells": 34
		},
		"rivers": [{
			"name": "GoldenValleyRiver", "half_width": 7.5, "depth": 2.6, "bank": 10.0,
			"points": [[-40, -560], [-30, -440], [0, -300], [20, -150],
			           [50, 0], [80, 180], [130, 380], [200, 560]]
		}],
		"bridges": [{
			"name": "GoldenValleyBridge", "style": "stone",
			"a": [38.0, -18.0], "b": [66.0, -4.0], "width": 4.4
		}],
		"trails": [
			{"name": "ValleyRidgeTrail",  "half_width": 2.6,
			 "points": [[-540, 200], [-400, 150], [-260, 90], [-120, 40], [-20, -20], [38, -18]]},
			{"name": "AshfordApproach",   "half_width": 2.4,
			 "points": [[66, -4], [150, -40], [260, -120], [380, -200], [520, -300]]},
			{"name": "ForestEdgeTrail",   "half_width": 2.0,
			 "points": [[-300, -200], [-320, -100], [-340, 0], [-320, 120], [-280, 240]]},
			{"name": "FarmlandLane",      "half_width": 1.6,
			 "points": [[-80, 200], [-40, 220], [0, 240], [60, 260], [120, 270]]},
		],
		"hills": [
			{"name": "OverlookRidge",    "center": [-480, 180], "radius": 120, "height": 22, "rocky": 0.25},
			{"name": "CentralHumps",     "center": [80, -80],   "radius": 90,  "height": 10, "rocky": 0.15},
			{"name": "EastRise",         "center": [300, 100],  "radius": 80,  "height": 14, "rocky": 0.3},
			{"name": "NorthRidgeLine",   "center": [-200, -300], "radius": 110, "height": 18, "rocky": 0.4},
		]
	}


func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 30241
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 220.0
	nb.fractal_octaves = 5

	var nr := FastNoiseLite.new()
	nr.seed = 30247
	nr.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nr.frequency  = 1.0 / 55.0
	nr.fractal_octaves = 3

	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			# Base rolling valley: lower centre, higher at edges
			var dist_ctr := Vector2(lx, lz).length() / HALF
			var valley_shape := dist_ctr * dist_ctr * 28.0  # rim elevation
			var base_h := 3.5 + (nb.get_noise_2d(lx, lz) + 1.0) * 0.5 * 16.0
			var detail  := (nr.get_noise_2d(lx, lz) + 1.0) * 0.5 * 2.8
			# Valley floor: southern section is lower for river
			var south_dip := maxf(0.0, lz * 0.012)
			td.heights[j * td.n + i] = base_h + detail + valley_shape * 0.3 - south_dip

	# Flatten river corridor
	for pt in _river_points:
		for j in td.n:
			for i in td.n:
				var lx := td.origin + i * cell_size
				var lz := td.origin + j * cell_size
				var d := Vector2(lx - pt.x, lz - pt.y).length()
				if d < 18.0:
					var t := smoothstep(18.0, 6.0, d)
					td.heights[j * td.n + i] = lerpf(td.heights[j * td.n + i], -0.3, t)

	# Farmland terraces: 3 strips west of river
	for strip in [Vector2(-140, 180), Vector2(-140, 240), Vector2(-140, 300)]:
		_flatten_area(strip.x, strip.y, 55.0, 4.5)

	# Bridge crossing flat
	_flatten_area(52.0, -11.0, 20.0, 1.8)


func _build_structures() -> void:
	var root := structures_root

	# Watchtower on overlook ridge
	_build_watchtower(root, Vector3(-480, 0, 180))

	# Farm hamlet cluster
	_build_valley_hamlet(root, Vector3(-140, 0, 240))

	# Stone bridge (uses Bridge.build)
	_build_stone_bridge(root)

	# Ruined lookout post at forest edge
	_build_ruined_post(root, Vector3(-320, 0, -100))


func _build_watchtower(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("gv_tower"), 0.05)
	var STONE_C := Color(0.42, 0.40, 0.38)
	var ROOF_C  := Color(0.28, 0.24, 0.18)
	var dia := 4.5; var h := 14.0
	# Cylinder approximation: 8-sided polygon
	var sides := 8
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		for seg in 7:
			var yb := float(seg) * (h / 7.0)
			var yt := float(seg + 1) * (h / 7.0)
			kit.add_quad(
				base + Vector3(cos(a0) * dia * 0.5, yb, sin(a0) * dia * 0.5),
				base + Vector3(cos(a1) * dia * 0.5, yb, sin(a1) * dia * 0.5),
				base + Vector3(cos(a1) * dia * 0.5, yt, sin(a1) * dia * 0.5),
				base + Vector3(cos(a0) * dia * 0.5, yt, sin(a0) * dia * 0.5),
				STONE_C)
	# Battlement ring
	for s in sides:
		var a := TAU * s / sides + (TAU / sides) * 0.5
		kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(cos(a) * dia * 0.5, h + 0.5, sin(a) * dia * 0.5)),
			Vector3(0.6, 1.0, 0.6), STONE_C)
	# Conical roof
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		kit.add_tri(
			base + Vector3(cos(a0) * dia * 0.55, h, sin(a0) * dia * 0.55),
			base + Vector3(cos(a1) * dia * 0.55, h, sin(a1) * dia * 0.55),
			base + Vector3(0, h + 4.5, 0),
			ROOF_C)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build()
	mi.material_override = STONE_MAT
	parent.add_child(mi)
	# Collision
	var body := StaticBody3D.new()
	var cs   := CollisionShape3D.new()
	var cyl  := CylinderShape3D.new()
	cyl.radius = dia * 0.5; cyl.height = h
	cs.shape = cyl; cs.position = base + Vector3(0, h * 0.5, 0)
	body.add_child(cs); body.collision_layer = Layers.WORLD
	parent.add_child(body)
	# Lantern at top
	_add_lantern_post(parent, base + Vector3(0, h - 0.5, 0), 1.2)


func _build_valley_hamlet(parent: Node3D, center_local: Vector3) -> void:
	var THATCH  := Color(0.52, 0.42, 0.26)
	var PLASTER := Color(0.74, 0.70, 0.60)
	var BEAM    := Color(0.32, 0.26, 0.18)
	var configs := [
		[Vector3(-18, 0, -12), 0.0,          8.0, 6.0, 3.6, 2.0, PLASTER, THATCH],
		[Vector3(14, 0, -8),   deg_to_rad(25), 7.0, 5.5, 3.4, 1.8, PLASTER, THATCH],
		[Vector3(-10, 0, 14),  deg_to_rad(-10), 9.0, 6.0, 3.8, 2.0, BEAM, THATCH],
		[Vector3(22, 0, 16),   deg_to_rad(15), 12.0, 7.0, 3.5, 1.6, BEAM, Color(0.4, 0.3, 0.2)],
	]
	for cfg in configs:
		var lpos  : Vector3 = cfg[0]
		var rot_y : float   = cfg[1]
		var w     : float   = cfg[2]; var d  : float = cfg[3]
		var wh    : float   = cfg[4]; var rh : float = cfg[5]
		var wc    : Color   = cfg[6]; var rc : Color = cfg[7]
		var gnd := height_at_local(center_local.x + lpos.x, center_local.z + lpos.z)
		_add_simple_house(parent, center_local + lpos + Vector3(0, gnd, 0),
			rot_y, w, d, wh, rh, wc, rc)
	# Stone well
	var well_pos := center_local + Vector3(4, 0, 4)
	var gnd_w := height_at_local(well_pos.x, well_pos.z)
	_build_well(parent, well_pos + Vector3(0, gnd_w, 0))
	# Fence line around hamlet
	var fence_a := center_local + Vector3(-30, 0, -20)
	var fence_b := center_local + Vector3(35, 0, -20)
	var gnd_a := height_at_local(fence_a.x, fence_a.z)
	var gnd_b := height_at_local(fence_b.x, fence_b.z)
	_add_dry_stone_wall_segment(parent,
		fence_a + Vector3(0, gnd_a, 0), fence_b + Vector3(0, gnd_b, 0), 1.1)


func _build_well(parent: Node3D, pos: Vector3) -> void:
	var kit  := MeshKit.new(hash("gv_well"), 0.04)
	var STONE_C := Color(0.46, 0.44, 0.40)
	var WOOD_C  := Color(0.32, 0.25, 0.15)
	# Base ring
	for s in 8:
		var a0 := TAU * s / 8
		var a1 := TAU * (s + 1) / 8
		kit.add_quad(
			pos + Vector3(cos(a0) * 0.75, 0, sin(a0) * 0.75),
			pos + Vector3(cos(a1) * 0.75, 0, sin(a1) * 0.75),
			pos + Vector3(cos(a1) * 0.75, 0.9, sin(a1) * 0.75),
			pos + Vector3(cos(a0) * 0.75, 0.9, sin(a0) * 0.75),
			STONE_C)
	# Posts
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(-0.75, 1.5, 0)), Vector3(0.14, 1.2, 0.14), WOOD_C)
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0.75, 1.5, 0)),  Vector3(0.14, 1.2, 0.14), WOOD_C)
	# Crossbeam
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 2.1, 0)), Vector3(1.7, 0.14, 0.14), WOOD_C)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_stone_bridge(parent: Node3D) -> void:
	# Build a World proxy so Bridge.build() gets the right td
	var proxy := World.new()
	proxy.terrain_data = td
	proxy.water_level  = 0.0
	proxy.layout       = layout
	parent.add_child(proxy)  # needs to be in scene for Bridge
	var bridge_def : Dictionary = layout.list("bridges")[0] if layout.list("bridges").size() > 0 else {}
	if bridge_def.is_empty():
		bridge_def = {"name": "GoldenValleyBridge", "style": "stone",
		              "a": [38.0, -18.0], "b": [66.0, -4.0], "width": 4.4}
	Bridge.build(parent, proxy, bridge_def)
	proxy.queue_free()


func _build_ruined_post(parent: Node3D, lpos: Vector3) -> void:
	var gnd := height_at_local(lpos.x, lpos.z)
	var base := lpos + Vector3(0, gnd, 0)
	var kit  := MeshKit.new(hash("gv_ruin"), 0.10)
	var col  := Color(0.43, 0.41, 0.38)
	# Partial wall L-shape
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(0, 1.4, 0)), Vector3(6.0, 2.8, 0.6), col)
	kit.add_box(Transform3D(Basis.IDENTITY, base + Vector3(-2.7, 0.9, 1.5)), Vector3(0.6, 1.8, 3.6), col)
	# Fallen stone slab
	kit.add_box(Transform3D(Basis.from_euler(Vector3(0.3, 0.2, 0.0)), base + Vector3(2.0, 0.3, 1.5)),
		Vector3(2.4, 0.4, 1.0), col)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_vegetation() -> void:
	var veg    := vegetation_root
	var rng    := RandomNumberGenerator.new()
	rng.seed   = 30261

	# Distant mountain ring (inherited from golden_valley_showcase pattern)
	_build_distant_mountains(veg)

	# Forest edge along western ridge — dense pines and oaks
	for _i in 300:
		var angle  := rng.randf_range(2.4, 4.8)  # western arc
		var dist   := rng.randf_range(220.0, 560.0)
		var lx     := cos(angle) * dist
		var lz     := sin(angle) * dist
		if absf(lx) > HALF * 0.9 or absf(lz) > HALF * 0.9:
			continue
		var gnd    := height_at_local(lx, lz)
		var kind   := "pine" if rng.randf() > 0.4 else "fir"
		var sc     := rng.randf_range(0.9, 1.6)
		var tree   := MeshInstance3D.new()
		tree.mesh  = PropMeshes.tree(kind, sc)
		tree.position = Vector3(lx, gnd, lz)
		veg.add_child(tree)

	# Central valley grasses
	for _i in 2500:
		var lx := rng.randf_range(-HALF * 0.75, HALF * 0.75)
		var lz := rng.randf_range(-HALF * 0.75, HALF * 0.75)
		# Skip river corridor
		var river_dist := _river_distance(lx, lz)
		if river_dist < 12.0:
			continue
		var gnd := height_at_local(lx, lz)
		if gnd < 0.5:
			continue
		var kind := "grass_tall" if rng.randf() > 0.55 else "grass"
		var grp  := MeshInstance3D.new()
		grp.mesh = PropMeshes.grass(kind, rng.randf_range(0.8, 1.3))
		grp.position = Vector3(lx, gnd, lz)
		veg.add_child(grp)

	# Scattered boulders on hillsides
	for _i in 40:
		var lx  := rng.randf_range(-HALF * 0.8, HALF * 0.8)
		var lz  := rng.randf_range(-HALF * 0.8, HALF * 0.8)
		var gnd := height_at_local(lx, lz)
		if gnd < 2.0:
			continue
		_add_boulder(veg, Vector3(lx, gnd, lz),
			Vector3(rng.randf_range(1.2, 3.5), rng.randf_range(0.8, 2.0), rng.randf_range(1.0, 2.8)))


func _build_distant_mountains(parent: Node3D) -> void:
	var kit := MeshKit.new(90241, 0.0)
	var sides := 24
	var ring_r := 1480.0
	var SNOW  := Color(0.78, 0.80, 0.82)
	var MID   := Color(0.36, 0.38, 0.42)
	var BASE  := Color(0.14, 0.18, 0.12)
	for s in sides:
		var a0  := TAU * s / sides
		var a1  := TAU * (s + 1) / sides
		var h   := ring_r * 0.08 + randf_range(0, ring_r * 0.06) * sin(a0 * 3 + 1.2)
		kit.add_tri(
			Vector3(cos(a0) * ring_r, 0.0, sin(a0) * ring_r),
			Vector3(cos(a1) * ring_r, 0.0, sin(a1) * ring_r),
			Vector3((cos(a0) + cos(a1)) * 0.5 * ring_r * 0.95, h, (sin(a0) + sin(a1)) * 0.5 * ring_r * 0.95),
			BASE)
		# Snow cap
		var snow_base := h * 0.72
		kit.add_tri(
			Vector3((cos(a0) + cos(a1)) * 0.5 * ring_r * 0.95, h, (sin(a0) + sin(a1)) * 0.5 * ring_r * 0.95),
			Vector3(cos(a0) * ring_r * 0.92, snow_base, sin(a0) * ring_r * 0.92),
			Vector3(cos(a1) * ring_r * 0.92, snow_base, sin(a1) * ring_r * 0.92),
			SNOW)
	var mi := MeshInstance3D.new()
	mi.name             = "DistantMountains"
	mi.mesh             = kit.build()
	mi.material_override = DISTANT_MOUNTAIN_MAT
	mi.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = 0.0
	mi.visibility_range_end   = 0.0  # always visible
	parent.add_child(mi)


func _build_markers() -> void:
	# This is called from base _build_all after _build_vegetation
	pass


# Override _build_all to also call markers
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
		["gv_overlook_vista",    "viewpoint",        Vector3(-480, 0, 180)],
		["gv_stone_bridge",      "landmark",         Vector3(52,  0, -11)],
		["gv_hamlet_mill",       "settlement",       Vector3(-140, 0, 240)],
		["gv_combat_clearing",   "combat_arena",     Vector3(280, 0, -180)],
		["gv_ashford_approach",  "route_waypoint",   Vector3(520, 0, -300)],
		["gv_forest_entrance",   "route_waypoint",   Vector3(-300, 0, -100)],
		["gv_river_ford",        "route_waypoint",   Vector3(50,  0, 0)],
		["gv_valley_viewpoint",  "viewpoint",        Vector3(-200, 0, -300)],
	]
	for p in pts:
		var gnd := height_at_local(float((p[2] as Vector3).x), float((p[2] as Vector3).z))
		var lpos : Vector3 = p[2]
		lpos.y = gnd
		_add_marker(p[0], p[1], lpos)


func _river_distance(lx: float, lz: float) -> float:
	var min_d := 1e9
	for s in _river_points.size() - 1:
		var a := _river_points[s]
		var b := _river_points[s + 1]
		var ab := b - a
		var ap := Vector2(lx, lz) - a
		var t  := clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
		min_d  = minf(min_d, ap.distance_to(ab * t))
	return min_d
