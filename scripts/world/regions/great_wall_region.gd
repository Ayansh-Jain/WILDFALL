class_name GreatWallRegion
extends WorldRegion
## R03-AG | Great Wall + Great Gate — monumental defensive barrier.
## 1,000 m (EW) × 500 m region between War Plains (south) and Frostcrest (north).
## Features: 800 m wall with flanking towers every 60 m, twin-tower Great Gate,
## barbican forecourt, battlemented wall-walk, royal banners.

const HALF_X := 500.0
const HALF_Z := 250.0
const CELL   := 2.0

const WALL_HEIGHT := 12.0
const WALL_THICK  := 4.0
const WALL_LENGTH := 800.0
const TOWER_DIA   := 9.0
const TOWER_HEIGHT := 18.0
const GATE_WIDTH   := 8.0
const GATE_HEIGHT  := 12.0
const GATE_TOWER_HEIGHT := 24.0


func _init() -> void:
	region_id         = "great_wall"
	region_half_size  = maxf(HALF_X, HALF_Z)
	cell_size         = CELL
	default_profile   = "great_wall_dusk"


func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": region_half_size, "playable_half": region_half_size * 0.88,
			"cell": CELL, "water_level": -50.0, "base_height": 2.0, "chunk_cells": 34
		},
		"trails": [{
			"name": "MilitaryRoadApproach", "half_width": 6.0,
			"points": [[0, 240], [0, 60], [0, 0], [0, -60], [0, -240]]
		}]
	}


func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 40241
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 180.0
	nb.fractal_octaves = 3

	# Terrain: flat approach plain (south), escarpment line at z=0, cliff/slope north
	for j in td.n:
		for i in td.n:
			var lx := td.origin + i * cell_size
			var lz := td.origin + j * cell_size
			var base_h := (nb.get_noise_2d(lx, lz) + 1.0) * 0.5 * 4.0 + 1.5
			# Escarpment: rises sharply going north of wall line (z < 0)
			var cliff := 0.0
			if lz < -10.0:
				cliff = minf((-lz - 10.0) * 0.6, 25.0)
			# Smooth approach plain to south
			var south_flat := maxf(0.0, (lz - 20.0) * 0.08)
			td.heights[j * td.n + i] = base_h + cliff - south_flat

	# Flat military road through gate
	_flatten_area(0.0, 100.0, 30.0, 2.0)
	_flatten_area(0.0, -60.0, 30.0, 2.0)
	_flatten_area(0.0, 0.0, 15.0, 2.0)


func _build_structures() -> void:
	var root := structures_root
	_build_great_wall(root)
	_build_great_gate(root)
	_build_wall_towers(root)
	_build_barbican(root)
	_build_banners(root)
	_build_guard_structures(root)


func _build_great_wall(parent: Node3D) -> void:
	# 800 m wall running E-W along z=0 line, broken by gate at x=0
	# Left half: -400 to -GATE_WIDTH/2  Right half: GATE_WIDTH/2 to +400
	var kit  := MeshKit.new(hash("gw_wall"), 0.04)
	var STONE_C  := Color(0.38, 0.36, 0.33)
	var MORTAR_C := Color(0.30, 0.29, 0.27)
	var WALK_C   := Color(0.42, 0.40, 0.37)
	var half_len := WALL_LENGTH * 0.5

	for side in [-1, 1]:
		var x_start := side * GATE_WIDTH * 0.5
		var x_end   := side * half_len
		var seg_len  := absf(x_end - x_start)
		var ctr_x    := (x_start + x_end) * 0.5

		# Main wall body
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(ctr_x, WALL_HEIGHT * 0.5, 0.0)),
			Vector3(seg_len, WALL_HEIGHT, WALL_THICK), STONE_C)

		# Wall-walk floor (top surface)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(ctr_x, WALL_HEIGHT + 0.1, 0.0)),
			Vector3(seg_len, 0.25, WALL_THICK + 0.4), WALK_C)

		# Merlons (battlements): 0.9 m wide, 1.4 m gap, every 2.3 m
		var merlon_w := 0.9; var gap := 1.4; var period := merlon_w + gap
		var num_merlons := int(seg_len / period)
		for m in num_merlons:
			var mx := x_start + side * (m * period + merlon_w * 0.5)
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(mx, WALL_HEIGHT + 0.75, -WALL_THICK * 0.5 - 0.05)),
				Vector3(merlon_w, 1.5, 0.45), STONE_C)
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(mx, WALL_HEIGHT + 0.75, WALL_THICK * 0.5 + 0.05)),
				Vector3(merlon_w, 1.5, 0.45), STONE_C)

	var mi := MeshInstance3D.new()
	mi.mesh = kit.build()
	mi.material_override = STONE_MAT
	parent.add_child(mi)

	# Collision for wall halves
	for side in [-1, 1]:
		var x_start := side * GATE_WIDTH * 0.5
		var x_end   := side * WALL_LENGTH * 0.5
		var seg_len  := absf(x_end - x_start)
		var ctr_x    := (x_start + x_end) * 0.5
		var body := StaticBody3D.new()
		var cs   := CollisionShape3D.new()
		var box  := BoxShape3D.new()
		box.size  = Vector3(seg_len, WALL_HEIGHT + 1.5, WALL_THICK)
		cs.shape  = box; cs.position = Vector3(ctr_x, (WALL_HEIGHT + 1.5) * 0.5, 0)
		body.add_child(cs); body.collision_layer = Layers.WORLD
		parent.add_child(body)


func _build_great_gate(parent: Node3D) -> void:
	var kit  := MeshKit.new(hash("gw_gate"), 0.04)
	var DARK  := Color(0.32, 0.30, 0.28)
	var STONE_C := Color(0.40, 0.38, 0.35)
	var GH    := GATE_TOWER_HEIGHT
	var TD    := 10.0  # tower diameter
	var ARCH_THICK := WALL_THICK + 4.0

	# Left tower
	for s in 8:
		var a0 := TAU * s / 8; var a1 := TAU * (s + 1) / 8
		for seg in 12:
			var yb := float(seg) * (GH / 12.0)
			var yt := float(seg + 1) * (GH / 12.0)
			kit.add_quad(
				Vector3(-GATE_WIDTH * 0.5 - TD * 0.5 + cos(a0) * TD * 0.5, yb, sin(a0) * TD * 0.5),
				Vector3(-GATE_WIDTH * 0.5 - TD * 0.5 + cos(a1) * TD * 0.5, yb, sin(a1) * TD * 0.5),
				Vector3(-GATE_WIDTH * 0.5 - TD * 0.5 + cos(a1) * TD * 0.5, yt, sin(a1) * TD * 0.5),
				Vector3(-GATE_WIDTH * 0.5 - TD * 0.5 + cos(a0) * TD * 0.5, yt, sin(a0) * TD * 0.5),
				DARK)
	# Right tower
	for s in 8:
		var a0 := TAU * s / 8; var a1 := TAU * (s + 1) / 8
		for seg in 12:
			var yb := float(seg) * (GH / 12.0)
			var yt := float(seg + 1) * (GH / 12.0)
			kit.add_quad(
				Vector3(GATE_WIDTH * 0.5 + TD * 0.5 + cos(a0) * TD * 0.5, yb, sin(a0) * TD * 0.5),
				Vector3(GATE_WIDTH * 0.5 + TD * 0.5 + cos(a1) * TD * 0.5, yb, sin(a1) * TD * 0.5),
				Vector3(GATE_WIDTH * 0.5 + TD * 0.5 + cos(a1) * TD * 0.5, yt, sin(a1) * TD * 0.5),
				Vector3(GATE_WIDTH * 0.5 + TD * 0.5 + cos(a0) * TD * 0.5, yt, sin(a0) * TD * 0.5),
				DARK)

	# Connecting header block above arch
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, GATE_HEIGHT + (GH - GATE_HEIGHT) * 0.5, 0)),
		Vector3(GATE_WIDTH + TD * 2 + 1.0, GH - GATE_HEIGHT, ARCH_THICK), STONE_C)

	# Arch outline (simplified: rectangular opening with bevelled top)
	# Left wall panel
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-GATE_WIDTH * 0.5 - 1.5, GATE_HEIGHT * 0.5, 0)),
		Vector3(3.0, GATE_HEIGHT, ARCH_THICK), DARK)
	# Right wall panel
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(GATE_WIDTH * 0.5 + 1.5, GATE_HEIGHT * 0.5, 0)),
		Vector3(3.0, GATE_HEIGHT, ARCH_THICK), DARK)

	# Portcullis groove indicators (decorative channels)
	for side_x: float in [-1.0, 1.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(side_x * GATE_WIDTH * 0.5 * 0.6, GATE_HEIGHT * 0.5, -ARCH_THICK * 0.4)),
			Vector3(0.3, GATE_HEIGHT, 0.3), Color(0.18, 0.17, 0.16))

	# Tower battlements
	for tower_x : float in [-GATE_WIDTH * 0.5 - TD * 0.5, GATE_WIDTH * 0.5 + TD * 0.5]:
		for s in 8:
			var a := TAU * s / 8 + (TAU / 8) * 0.5
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(tower_x + cos(a) * TD * 0.5, GH + 0.75, sin(a) * TD * 0.5)),
				Vector3(0.7, 1.5, 0.7), STONE_C)
		# Tower roof cap
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(tower_x, GH + 0.12, 0)),
			Vector3(TD + 0.5, 0.25, TD + 0.5), STONE_C)

	var mi := MeshInstance3D.new()
	mi.mesh = kit.build()
	mi.material_override = STONE_MAT
	parent.add_child(mi)

	# Collision for gate towers
	for tower_x : float in [-GATE_WIDTH * 0.5 - TD * 0.5, GATE_WIDTH * 0.5 + TD * 0.5]:
		var body := StaticBody3D.new()
		var cs   := CollisionShape3D.new()
		var cyl  := CylinderShape3D.new()
		cyl.radius = TD * 0.5; cyl.height = GH
		cs.shape = cyl; cs.position = Vector3(tower_x, GH * 0.5, 0)
		body.add_child(cs); body.collision_layer = Layers.WORLD
		parent.add_child(body)


func _build_wall_towers(parent: Node3D) -> void:
	var kit  := MeshKit.new(hash("gw_towers"), 0.05)
	var STONE_C := Color(0.38, 0.36, 0.34)
	var ROOF_C  := Color(0.26, 0.22, 0.18)
	var spacing := 60.0
	var num_each := int((WALL_LENGTH * 0.5 - GATE_WIDTH * 0.5) / spacing)

	for side in [-1, 1]:
		for t in num_each:
			var tx : float = side * (GATE_WIDTH * 0.5 + (t + 0.5) * spacing + 15.0)
			if absf(tx) > WALL_LENGTH * 0.5:
				continue
			var dia := TOWER_DIA
			var h   := TOWER_HEIGHT
			for s in 8:
				var a0 := TAU * s / 8; var a1 := TAU * (s + 1) / 8
				for seg in 9:
					var yb := float(seg) * (h / 9.0)
					var yt := float(seg + 1) * (h / 9.0)
					kit.add_quad(
						Vector3(tx + cos(a0) * dia * 0.5, yb, sin(a0) * dia * 0.5),
						Vector3(tx + cos(a1) * dia * 0.5, yb, sin(a1) * dia * 0.5),
						Vector3(tx + cos(a1) * dia * 0.5, yt, sin(a1) * dia * 0.5),
						Vector3(tx + cos(a0) * dia * 0.5, yt, sin(a0) * dia * 0.5),
						STONE_C)
			# Tower battlements
			for s in 8:
				var a := TAU * s / 8 + TAU / 16.0
				kit.add_box(Transform3D(Basis.IDENTITY, Vector3(tx + cos(a) * dia * 0.5, h + 0.75, sin(a) * dia * 0.5)),
					Vector3(0.6, 1.4, 0.6), STONE_C)
			# Conical tower roof
			for s in 8:
				var a0 := TAU * s / 8; var a1 := TAU * (s + 1) / 8
				kit.add_tri(
					Vector3(tx + cos(a0) * dia * 0.55, h, sin(a0) * dia * 0.55),
					Vector3(tx + cos(a1) * dia * 0.55, h, sin(a1) * dia * 0.55),
					Vector3(tx, h + 5.0, 0),
					ROOF_C)

	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_barbican(parent: Node3D) -> void:
	# 30 m deep forecourt on the southern (War Plains) side
	var kit  := MeshKit.new(hash("gw_barbican"), 0.04)
	var STONE_C := Color(0.40, 0.38, 0.35)
	var w := GATE_WIDTH + 24.0  # forecourt width
	var d := 30.0

	# Side walls
	for side_x : float in [-w * 0.5, w * 0.5]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(side_x, 6.0, d * 0.5 + 0.3)),
			Vector3(0.6, 12.0, d + 0.6), STONE_C)
	# Front gate arch (simplified)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(-w * 0.5 + 1.5, 5.5, d + 0.3)),
		Vector3(3.0, 11.0, 0.6), STONE_C)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(w * 0.5 - 1.5, 5.5, d + 0.3)),
		Vector3(3.0, 11.0, 0.6), STONE_C)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 10.5, d + 0.3)),
		Vector3(w, 2.0, 0.6), STONE_C)
	# Cobbled surface indicator (colour-coded floor)
	kit.add_quad(
		Vector3(-w * 0.5, 0.05, 0.3), Vector3(w * 0.5, 0.05, 0.3),
		Vector3(w * 0.5, 0.05, d + 0.3), Vector3(-w * 0.5, 0.05, d + 0.3),
		Color(0.36, 0.34, 0.32))

	var mi := MeshInstance3D.new()
	mi.mesh = kit.build(); mi.material_override = STONE_MAT
	parent.add_child(mi)


func _build_banners(parent: Node3D) -> void:
	# Animated royal banners on gate towers (shader-animated via foliage_card sway)
	var GOLD   := Color(0.80, 0.68, 0.22, 1.0)
	var BANNER_H := 3.5; var BANNER_W := 1.4
	for tower_x : float in [-GATE_WIDTH * 0.5 - 5.0, GATE_WIDTH * 0.5 + 5.0]:
		var kit := MeshKit.new(hash("gw_banner" + str(tower_x)), 0.0)
		var ty  := GATE_TOWER_HEIGHT - 1.0
		# Banner quad (using sway UV so foliage shader animates it)
		kit.add_tri(
			Vector3(tower_x, ty + BANNER_H, -1.0),
			Vector3(tower_x + BANNER_W, ty + BANNER_H, -1.0),
			Vector3(tower_x + BANNER_W, ty, -1.0),
			GOLD, 0.0, 0.0, 1.0)
		kit.add_tri(
			Vector3(tower_x, ty + BANNER_H, -1.0),
			Vector3(tower_x + BANNER_W, ty, -1.0),
			Vector3(tower_x, ty, -1.0),
			GOLD, 0.0, 1.0, 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = kit.build()
		parent.add_child(mi)


func _build_guard_structures(parent: Node3D) -> void:
	# Small guardhouses flanking the southern barbican entrance
	for side_x : float in [-18.0, 18.0]:
		var gnd := height_at_local(side_x, 32.0)
		_add_simple_house(parent, Vector3(side_x, gnd, 32.0),
			deg_to_rad(90 * signf(side_x)),
			5.0, 4.0, 3.5, 1.5, Color(0.42, 0.40, 0.37), Color(0.28, 0.24, 0.18))
	# Lantern posts at barbican entrance
	for side_x : float in [-12.0, 12.0]:
		var gnd := height_at_local(side_x, 31.0)
		_add_lantern_post(parent, Vector3(side_x, gnd, 31.0), 1.6)


func _build_vegetation() -> void:
	var veg := vegetation_root
	var rng := RandomNumberGenerator.new(); rng.seed = 40261

	# Scrub and grass on the approach plain (south)
	for _i in 800:
		var lx  := rng.randf_range(-HALF_X * 0.9, HALF_X * 0.9)
		var lz  := rng.randf_range(30.0, HALF_Z * 0.9)  # only south side
		var gnd := height_at_local(lx, lz)
		var kind := "grass_tall" if rng.randf() > 0.6 else "grass"
		var grp  := MeshInstance3D.new()
		grp.mesh = PropMeshes.grass(kind, rng.randf_range(0.7, 1.1))
		grp.position = Vector3(lx, gnd, lz)
		veg.add_child(grp)

	# Sparse trees at far south edges (depth framing)
	for _i in 60:
		var lx  := rng.randf_range(-HALF_X * 0.9, HALF_X * 0.9)
		var lz  := rng.randf_range(HALF_Z * 0.6, HALF_Z * 0.9)
		var gnd := height_at_local(lx, lz)
		var mi  := MeshInstance3D.new()
		mi.mesh = PropMeshes.tree("pine", rng.randf_range(0.9, 1.4))
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
		["great_gate_entry",         "gate_anchor",    Vector3(0,   2.2, 32)],
		["great_gate_field_west",    "gate_anchor",    Vector3(-80, 2.0, 60)],
		["great_gate_field_east",    "gate_anchor",    Vector3(80,  2.0, 60)],
		["great_wall_west_end",      "gate_anchor",    Vector3(-400, WALL_HEIGHT, 0)],
		["great_wall_east_anchor",   "gate_anchor",    Vector3(400,  WALL_HEIGHT, 0)],
		["great_gate_overlook",      "viewpoint",      Vector3(0, GATE_TOWER_HEIGHT, 0)],
	]
	for p in pts:
		var lpos : Vector3 = p[2]
		_add_marker(p[0], p[1], lpos)
