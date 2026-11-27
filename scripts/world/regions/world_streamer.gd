class_name WorldStreamer
extends Node3D
## Streams WorldRegion scenes in and out based on player distance.
## Uses simple distance-based add_child / queue_free with VisibilityNotifier3D.
##
## Regions are defined as an Array of Dictionaries:
##   { "id": String, "scene": PackedScene, "world_offset": Vector3, "radius": float }
##
## Codex integration: exposes get_active_regions() and get_region_bounds(id) for
## streaming cell activation (Contract C-15 — PROPOSED).

signal region_loaded(region_id: String)
signal region_unloaded(region_id: String)

@export var stream_radius    : float = 1200.0
@export var unload_margin    : float = 200.0
@export var check_interval_s : float = 2.0

## Filled by the host scene or by register_region() calls.
var region_defs : Array[Dictionary] = []

var _active      : Dictionary = {}  # region_id -> Node3D instance
var _check_timer : float = 0.0
var _player_ref  : Node3D = null


func _process(delta: float) -> void:
	_check_timer += delta
	if _check_timer < check_interval_s:
		return
	_check_timer = 0.0
	_update_regions()


func register_region(region_id: String, scene: PackedScene,
		world_offset: Vector3, radius: float) -> void:
	region_defs.append({
		"id"           : region_id,
		"scene"        : scene,
		"world_offset" : world_offset,
		"radius"       : radius
	})


func set_player(player: Node3D) -> void:
	_player_ref = player


## Returns list of currently active region ids.
func get_active_regions() -> Array[String]:
	var result : Array[String] = []
	for id in _active.keys():
		result.append(id)
	return result


## Returns the AABB of a region (in world space) if active, else an empty AABB.
func get_region_bounds(region_id: String) -> AABB:
	if not _active.has(region_id):
		return AABB()
	var node := _active[region_id] as Node3D
	if not is_instance_valid(node):
		return AABB()
	var r := 0.0
	for def in region_defs:
		if def["id"] == region_id:
			r = float(def["radius"])
			break
	var o := node.global_position
	return AABB(o - Vector3(r, 100, r), Vector3(r * 2, 200, r * 2))


# ---------------------------------------------------------------------------
func _update_regions() -> void:
	var player_pos := _get_player_pos()

	for def in region_defs:
		var region_id : String = def["id"]
		var offset    : Vector3 = def["world_offset"]
		var radius    : float   = def["radius"]
		var dist := player_pos.distance_to(offset)

		if dist < stream_radius + radius:
			if not _active.has(region_id):
				_load_region(def)
		else:
			if _active.has(region_id) and dist > stream_radius + radius + unload_margin:
				_unload_region(region_id)


func _load_region(def: Dictionary) -> void:
	var region_id : String = def["id"]
	var scene     : PackedScene = def["scene"]
	var offset    : Vector3 = def["world_offset"]
	if scene == null:
		push_warning("[WorldStreamer] No scene for region: " + region_id)
		return
	var node := scene.instantiate() as Node3D
	node.position = offset
	add_child(node)
	_active[region_id] = node
	region_loaded.emit(region_id)
	print("[WorldStreamer] Loaded region: ", region_id, " at ", offset)


func _unload_region(region_id: String) -> void:
	var node := _active[region_id] as Node3D
	if is_instance_valid(node):
		node.queue_free()
	_active.erase(region_id)
	region_unloaded.emit(region_id)
	print("[WorldStreamer] Unloaded region: ", region_id)


func _get_player_pos() -> Vector3:
	if is_instance_valid(_player_ref):
		return _player_ref.global_position
	# Fallback: try PlayerController autoload
	if Engine.has_singleton("PlayerController"):
		var pc := Engine.get_singleton("PlayerController") as Node3D
		if is_instance_valid(pc):
			return pc.global_position
	return Vector3.ZERO
