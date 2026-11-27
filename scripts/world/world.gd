class_name World
extends Node3D
## Owns world generation order and exposes world queries (ground height,
## regions, spawn points) to gameplay code.

signal generated

const WATER_MAT := preload("res://assets/materials/water.tres")

var layout: WorldLayout
var terrain_data: TerrainData
var water_level := 0.0
var is_generated := false
var timings := {}

@onready var terrain: Terrain = $Terrain
@onready var props_root: Node3D = $Props
@onready var sites_root: Node3D = $Sites
@onready var moon: DirectionalLight3D = $Moon
@onready var environment: Environment = $WorldEnvironment.environment

func generate() -> void:
	var t := Time.get_ticks_msec()
	layout = WorldLayout.load_default()
	water_level = layout.water_level
	terrain_data = TerrainData.new()
	terrain_data.generate(layout, GameState.world_seed)
	PlayerController.terrain_height_query = terrain_data.height_at
	PlayerController.terrain_hole_query = terrain_data.is_hole_at
	_mark("terrain_data", t)

	t = Time.get_ticks_msec()
	terrain.build(terrain_data)
	_build_water()
	_mark("terrain_mesh", t)

	t = Time.get_ticks_msec()
	for child in sites_root.get_children():
		if child.has_method("build"):
			child.build(self)
	_mark("sites", t)

	t = Time.get_ticks_msec()
	for child in props_root.get_children():
		if child.has_method("build"):
			child.build(self)
	_mark("props", t)

	is_generated = true
	var veg := props_root.get_node_or_null("Vegetation")
	print("[World] generated: ", timings, "  terrain steps: ", terrain_data.step_ms)
	print("[World] props: ", veg.counts if veg else {}, "  steps: ", veg.step_ms if veg else {})
	generated.emit()


func _mark(key: String, since: int) -> void:
	timings[key] = Time.get_ticks_msec() - since


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * layout.half_size * 2.0
	plane.material = WATER_MAT
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.position.y = water_level
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Queries ---------------------------------------------------------------

func terrain_height(x: float, z: float) -> float:
	return terrain_data.height_at(x, z)


## Physics ray straight down. Returns {} if nothing solid was hit.
func ground_ray(x: float, z: float, from_y := 400.0, depth := 800.0) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - depth, z), Layers.WORLD)
	return space.intersect_ray(q)


func region_name(pos: Vector3) -> String:
	return terrain_data.region_name(pos.x, pos.z) if terrain_data else ""


func site_height(site_name: String) -> float:
	return terrain_data.site_heights.get(site_name, 0.0)


## Resolves a layout y_hint ("cave_floor", "site:<name>:<offset>") to an absolute
## height to cast down from, or NAN to cast from the sky.
func resolve_y_hint(hint: String) -> float:
	if hint == "":
		return NAN
	if hint == "cave_floor":
		return float(terrain_data.cave.get("floor", 0.0)) + 2.0
	if hint.begins_with("site:"):
		var parts := hint.split(":")
		return site_height(parts[1]) + float(parts[2]) + 1.5
	return NAN
