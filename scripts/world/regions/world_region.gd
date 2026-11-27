class_name WorldRegion
extends Node3D
## Base class for all R03 world regions.
## Each concrete region extends this, overrides _build_terrain/_build_structures/_build_vegetation,
## and is loaded/unloaded by WorldStreamer based on player proximity.
##
## Coordinate system: each region has its own local origin at the region centre.
## The region root node should be placed at the world offset position.

signal region_built(region_id: String)

const TERRAIN_MAT  := preload("res://assets/materials/terrain.tres")
const WATER_MAT    := preload("res://assets/materials/water.tres")
const STONE_MAT    := preload("res://assets/materials/stone.tres")
const PROPS_MAT    := preload("res://assets/materials/props.tres")
const DISTANT_MOUNTAIN_MAT := preload("res://assets/materials/distant_mountain.tres")

## --- Exports ---
@export var region_id    : String  = "unnamed"
@export var region_half_size : float = 300.0
@export var cell_size    : float   = 2.0
@export var spawn_hour   : float   = 10.0
@export var water_level  : float   = 0.0
@export var default_profile : String = "golden_day"

## --- Runtime ---
var td       : TerrainData
var layout   : WorldLayout
var atmosphere : Atmosphere

var _sun     : DirectionalLight3D
var _env_node: WorldEnvironment
var _lamps   : Array[Light3D] = []
var _flicker : Array[Dictionary] = []
var _flicker_t : float = 0.0
var _markers_root : Node3D

@onready var terrain_node   : Terrain       = $Terrain
@onready var structures_root: Node3D        = $Structures
@onready var vegetation_root: Node3D        = $Vegetation
@onready var markers_root   : Node3D        = $WorldMarkers
@onready var world_env      : WorldEnvironment = $WorldEnvironment
@onready var sun            : DirectionalLight3D = $Sun


# ---------------------------------------------------------------------------
func _ready() -> void:
	_markers_root = markers_root
	_build_all()
	_setup_atmosphere()
	region_built.emit(region_id)


func _process(delta: float) -> void:
	_flicker_t += delta
	for f in _flicker:
		var light := f["light"] as Light3D
		if is_instance_valid(light) and light.visible:
			var base := float(f["base"])
			var ph   := float(f["phase"])
			light.light_energy = base * (1.0 + 0.08 * sin(_flicker_t * 8.1 + ph) + 0.05 * sin(_flicker_t * 17.5 + ph * 2.3))


# ---------------------------------------------------------------------------
# Virtual — override in each region
# ---------------------------------------------------------------------------
func _build_terrain() -> void:
	pass

func _build_structures() -> void:
	pass

func _build_vegetation() -> void:
	pass


# ---------------------------------------------------------------------------
# Internal build pipeline
# ---------------------------------------------------------------------------
func _build_all() -> void:
	_setup_layout()
	_build_terrain()
	_build_water_plane()
	_build_structures()
	_build_vegetation()
	_publish_markers()


func _setup_layout() -> void:
	layout = WorldLayout.new()
	layout.half_size      = region_half_size
	layout.playable_half  = region_half_size * 0.88
	layout.cell           = cell_size
	layout.water_level    = water_level
	layout.base_height    = 4.0
	layout.chunk_cells    = 34
	layout.data           = _layout_data()

	var n := int(round(region_half_size * 2.0 / cell_size)) + 1
	td = TerrainData.new()
	td.layout      = layout
	td.cell        = cell_size
	td.origin      = -region_half_size
	td.water_level = water_level
	td.n           = n
	var count := n * n
	td.heights.resize(count)
	td.trail_dist.resize(count); td.trail_dist.fill(1e6)
	td.forest.resize(count);    td.forest.fill(0.0)
	td.wet.resize(count);       td.wet.fill(0.0)
	td.paving.resize(count);    td.paving.fill(0.0)
	td.water_influence.resize(count); td.water_influence.fill(0.0)
	td.holes.resize((n - 1) * (n - 1)); td.holes.fill(0)

	_generate_heights()
	terrain_node.build(td)


## Override to return region-specific layout data dict (rivers, trails, bridges, etc.)
func _layout_data() -> Dictionary:
	return {
		"world": {
			"half_size": region_half_size, "playable_half": region_half_size * 0.88,
			"cell": cell_size, "water_level": water_level, "base_height": 4.0, "chunk_cells": 34
		}
	}


## Override to fill td.heights with appropriate terrain.
## Default: gently rolling hills.
func _generate_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = hash(region_id) & 0xFFFFFF
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency  = 1.0 / 180.0
	nb.fractal_octaves = 4

	var nr := FastNoiseLite.new()
	nr.seed = (hash(region_id) + 7) & 0xFFFFFF
	nr.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nr.frequency  = 1.0 / 60.0

	for j in td.n:
		for i in td.n:
			var wx := td.origin + i * cell_size
			var wz := td.origin + j * cell_size
			var base_h := (nb.get_noise_2d(wx, wz) + 1.0) * 0.5 * 14.0 + 3.5
			var detail  := (nr.get_noise_2d(wx, wz) + 1.0) * 0.5 * 2.5
			td.heights[j * td.n + i] = base_h + detail


# ---------------------------------------------------------------------------
# Water plane
# ---------------------------------------------------------------------------
func _build_water_plane() -> void:
	var plane := PlaneMesh.new()
	plane.size     = Vector2.ONE * region_half_size * 2.0
	plane.material = WATER_MAT
	var mi := MeshInstance3D.new()
	mi.name            = "Water"
	mi.mesh            = plane
	mi.position.y      = water_level
	mi.cast_shadow     = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------------------
# Atmosphere setup
# ---------------------------------------------------------------------------
func _setup_atmosphere() -> void:
	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	if world_env and world_env.environment and sun:
		atmosphere.bind_environment(world_env.environment, sun, null)
	atmosphere.register_lamps(_lamps)
	atmosphere.apply(default_profile, 0.0)


# ---------------------------------------------------------------------------
# Marker helpers
# ---------------------------------------------------------------------------
func _add_marker(marker_id: String, kind: String, pos: Vector3) -> Node3D:
	var m := Node3D.new()
	m.name           = marker_id
	m.global_position = to_global(pos)
	m.set_meta("wf_id",   marker_id)
	m.set_meta("wf_kind", kind)
	m.set_meta("wf_region", region_id)
	m.add_to_group("wf_marker")
	_markers_root.add_child(m)
	return m


func _publish_markers() -> void:
	# Markers are already added to the wf_marker group by _add_marker.
	pass


# ---------------------------------------------------------------------------
# Terrain query helpers (local space)
# ---------------------------------------------------------------------------
func height_at_local(lx: float, lz: float) -> float:
	return td.height_at(lx, lz)


func height_at_world(wx: float, wz: float) -> float:
	var lpos := to_local(Vector3(wx, 0, wz))
	return td.height_at(lpos.x, lpos.z)


# ---------------------------------------------------------------------------
# Shared geometry helpers
# ---------------------------------------------------------------------------
func _add_lantern_post(parent: Node3D, pos: Vector3, energy: float = 1.4) -> void:
	var kit := MeshKit.new(hash(str(pos)), 0.05)
	var STONE_C := Color(0.4, 0.38, 0.35)
	var IRON_C  := Color(0.18, 0.17, 0.16)
	# Post
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 1.4, 0)),
		Vector3(0.14, 2.8, 0.14), STONE_C)
	# Lamp housing
	kit.add_box(Transform3D(Basis.IDENTITY, pos + Vector3(0, 3.0, 0)),
		Vector3(0.32, 0.4, 0.32), IRON_C)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build()
	mi.material_override = STONE_MAT
	parent.add_child(mi)
	# Flame point light
	var light := OmniLight3D.new()
	light.position        = pos + Vector3(0, 3.1, 0)
	light.light_color     = Color(1.0, 0.72, 0.38)
	light.light_energy    = energy
	light.omni_range      = 7.5
	light.shadow_enabled  = false
	parent.add_child(light)
	_lamps.append(light)
	_flicker.append({"light": light, "base": energy, "phase": randf_range(0.0, TAU)})


func _add_simple_house(parent: Node3D, pos: Vector3, rot_y: float,
		width: float, depth: float, wall_h: float,
		roof_h: float, wall_col: Color, roof_col: Color) -> void:
	var kit := MeshKit.new(hash(str(pos) + str(rot_y)), 0.06)
	var basis := Basis.from_euler(Vector3(0, rot_y, 0))

	# Walls
	var wall_ctr := pos + Vector3(0, wall_h * 0.5, 0)
	kit.add_box(Transform3D(basis, wall_ctr), Vector3(width, wall_h, depth), wall_col)

	# Roof (gabled approximation via two quads)
	var ridge_h := wall_h + roof_h
	var hw := width * 0.5; var hd := depth * 0.5
	var ridge_ctr := pos + Vector3(0, ridge_h, 0)
	# Front gable tri
	kit.add_tri(
		basis * Vector3(-hw, wall_h, -hd) + pos,
		basis * Vector3(hw, wall_h, -hd)  + pos,
		basis * Vector3(0, ridge_h, -hd)  + pos,
		roof_col)
	kit.add_tri(
		basis * Vector3(hw, wall_h, hd)   + pos,
		basis * Vector3(-hw, wall_h, hd)  + pos,
		basis * Vector3(0, ridge_h, hd)   + pos,
		roof_col)
	# Left slope
	kit.add_quad(
		basis * Vector3(-hw, wall_h, -hd) + pos,
		basis * Vector3(-hw, wall_h, hd)  + pos,
		basis * Vector3(0, ridge_h, hd)   + pos,
		basis * Vector3(0, ridge_h, -hd)  + pos,
		roof_col * Color(0.88, 0.88, 0.88))
	# Right slope
	kit.add_quad(
		basis * Vector3(hw, wall_h, hd)   + pos,
		basis * Vector3(hw, wall_h, -hd)  + pos,
		basis * Vector3(0, ridge_h, -hd)  + pos,
		basis * Vector3(0, ridge_h, hd)   + pos,
		roof_col * Color(0.88, 0.88, 0.88))

	var mi := MeshInstance3D.new()
	mi.mesh = kit.build()
	mi.material_override = PROPS_MAT
	parent.add_child(mi)

	# Simple collision
	var body := StaticBody3D.new()
	var cs   := CollisionShape3D.new()
	var box  := BoxShape3D.new()
	box.size  = Vector3(width, wall_h + roof_h, depth)
	cs.shape  = box
	cs.position = pos + Vector3(0, (wall_h + roof_h) * 0.5, 0)
	body.add_child(cs)
	body.collision_layer = Layers.WORLD
	parent.add_child(body)


func _add_dry_stone_wall_segment(parent: Node3D, a: Vector3, b: Vector3,
		height: float = 1.2) -> void:
	var kit  := MeshKit.new(hash(str(a) + str(b)), 0.08)
	var col  := Color(0.46, 0.44, 0.40)
	var dir  := (b - a).normalized()
	var perp := dir.cross(Vector3.UP)
	var len  := a.distance_to(b)
	var segs := maxi(1, int(len / 1.5))
	for s in segs:
		var t0 := float(s) / segs
		var t1 := float(s + 1) / segs
		var p0  := a.lerp(b, t0)
		var p1  := a.lerp(b, t1)
		var ctr := (p0 + p1) * 0.5 + Vector3(0, height * 0.5, 0)
		var seg_len := p0.distance_to(p1)
		kit.add_box(Transform3D(
			Basis(perp, Vector3.UP, dir), ctr),
			Vector3(0.45, height, seg_len), col)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build()
	mi.material_override = STONE_MAT
	parent.add_child(mi)


func _add_boulder(parent: Node3D, pos: Vector3, scale_v: Vector3) -> void:
	var kit := MeshKit.new(hash(str(pos)), 0.12)
	var col := Color(0.42, 0.41, 0.39)
	# Simple irregular polyhedron from 3 stacked quads
	var h := scale_v.y; var w := scale_v.x; var d := scale_v.z
	kit.add_box(Transform3D(Basis.from_euler(Vector3(0, randf_range(0, TAU), 0)), pos + Vector3(0, h * 0.5, 0)),
		scale_v, col)
	# Top cap
	kit.add_quad(
		pos + Vector3(-w * 0.3, h, -d * 0.3),
		pos + Vector3(w * 0.3, h, -d * 0.4),
		pos + Vector3(w * 0.4, h, d * 0.3),
		pos + Vector3(-w * 0.35, h, d * 0.4),
		col * Color(1.08, 1.08, 1.08))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.build()
	mi.material_override = STONE_MAT
	parent.add_child(mi)


func _flatten_area(cx: float, cz: float, radius: float, target_h: float) -> void:
	for j in td.n:
		for i in td.n:
			var wx := td.origin + i * cell_size
			var wz := td.origin + j * cell_size
			var d  := Vector2(wx - cx, wz - cz).length()
			if d < radius:
				var t := smoothstep(radius, radius * 0.6, d)
				td.heights[j * td.n + i] = lerpf(td.heights[j * td.n + i], target_h, t)
