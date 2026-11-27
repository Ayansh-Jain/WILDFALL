class_name SafeSpot
extends RefCounted
## "Can something stand here?" from physics alone, so it works in the kingdom, the
## showcase and test labs (no World dependency). Used by dismounting and horse recall.


## Ground under `p` (searching from `above` to `below` metres around it), or {}.
static func ground(space: PhysicsDirectSpaceState3D, p: Vector3, above := 1.5, below := 3.0, exclude: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * above, p + Vector3.DOWN * below, Layers.WORLD, exclude)
	return space.intersect_ray(q)


static func water_depth(p: Vector3, water_level: float) -> float:
	if PlayerController.terrain_height_query.is_valid() and float(PlayerController.terrain_height_query.call(p.x, p.z)) > water_level:
		return 0.0
	return maxf(0.0, water_level - p.y)


## A walkable spot for a standing person near height `p.y`. Returns the ground point,
## or Vector3.INF. `from` (optional) must have clear line to it: no stepping through walls.
static func standing(space: PhysicsDirectSpaceState3D, p: Vector3, from := Vector3.INF, water_level := 0.0, exclude: Array[RID] = []) -> Vector3:
	var hit := ground(space, p, 1.2, 2.2, exclude)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.72:
		return Vector3.INF
	var g: Vector3 = hit["position"]
	if water_depth(g, water_level) > 0.7:
		return Vector3.INF
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, g + Vector3.UP * 1.05)
	q.collision_mask = Layers.WORLD
	q.exclude = exclude
	if not space.intersect_shape(q, 1).is_empty():
		return Vector3.INF
	if from != Vector3.INF:
		var ray := PhysicsRayQueryParameters3D.create(from, g + Vector3.UP * 1.0, Layers.WORLD, exclude)
		if not space.intersect_ray(ray).is_empty():
			return Vector3.INF
	return g


## Open ground for a whole horse facing `yaw`. Returns the ground point or Vector3.INF.
static func horse_stand(space: PhysicsDirectSpaceState3D, p: Vector3, yaw: float, water_level := 0.0, exclude: Array[RID] = []) -> Vector3:
	var hit := ground(space, p, 3.0, 8.0, exclude)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.8:
		return Vector3.INF
	var g: Vector3 = hit["position"]
	if water_depth(g, water_level) > 0.5:
		return Vector3.INF
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.4, 3.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(Vector3.UP, yaw), g + Vector3.UP * 1.35)
	q.collision_mask = Layers.WORLD
	q.exclude = exclude
	if not space.intersect_shape(q, 1).is_empty():
		return Vector3.INF
	return g


## True when something solid is overhead (indoors, a cave, the crypt).
static func roofed(space: PhysicsDirectSpaceState3D, p: Vector3, height := 14.0, exclude: Array[RID] = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.8, p + Vector3.UP * height, Layers.WORLD, exclude)
	return not space.intersect_ray(q).is_empty()
