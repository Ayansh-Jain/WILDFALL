class_name LineOfSight
extends RefCounted
## Raycast-based line-of-sight queries, shared by interaction, stealth and
## (later) combat code. Stateless: pass the physics space you want to query.
##
## Solid world geometry (layer "world") blocks sight. Bushes and canopy live on
## "foliage_sight", which blocks sight but not movement; include or exclude it
## with the mask argument.

const DEFAULT_MASK := Layers.SIGHT_BLOCKERS

## Fractions of body height sampled by visibility(): head, chest, knees.
const BODY_SAMPLES := [0.92, 0.62, 0.25]


static func raycast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		exclude: Array = [], mask: int = DEFAULT_MASK) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = exclude
	q.collide_with_areas = false
	q.hit_back_faces = true
	return space.intersect_ray(q)


static func is_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		exclude: Array = [], mask: int = DEFAULT_MASK) -> bool:
	return raycast(space, from, to, exclude, mask).is_empty()


## World-space sample points on an upright body whose origin is at its feet.
static func body_points(feet: Vector3, height: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for f in BODY_SAMPLES:
		pts.append(feet + Vector3.UP * height * f)
	return pts


## Fraction (0..1) of the given points visible from `eye`.
static func visible_fraction(space: PhysicsDirectSpaceState3D, eye: Vector3, points: PackedVector3Array,
		exclude: Array = [], mask: int = DEFAULT_MASK) -> float:
	if points.is_empty():
		return 0.0
	var clear := 0
	for p in points:
		if is_clear(space, eye, p, exclude, mask):
			clear += 1
	return float(clear) / points.size()


## Full sight test from an observer to an upright body.
## Returns {visible, fraction, distance, in_view_cone, points, clear_points}.
static func can_see(space: PhysicsDirectSpaceState3D, eye: Vector3, eye_forward: Vector3,
		target_feet: Vector3, target_height: float, options: Dictionary = {}) -> Dictionary:
	var fov_deg: float = options.get("fov", 360.0)
	var max_distance: float = options.get("max_distance", INF)
	var min_fraction: float = options.get("min_fraction", 0.34)
	var exclude: Array = options.get("exclude", [])
	var mask: int = options.get("mask", DEFAULT_MASK)

	var pts := body_points(target_feet, target_height)
	var centre := target_feet + Vector3.UP * target_height * 0.6
	var dist := eye.distance_to(centre)
	var in_cone := fov_deg >= 360.0 or rad_to_deg(eye_forward.angle_to(centre - eye)) <= fov_deg * 0.5
	var result := {"visible": false, "fraction": 0.0, "distance": dist, "in_view_cone": in_cone,
		"points": pts, "clear_points": []}
	if dist > max_distance or not in_cone:
		return result
	var clear_pts: Array = []
	for p in pts:
		if is_clear(space, eye, p, exclude, mask):
			clear_pts.append(p)
	result["clear_points"] = clear_pts
	result["fraction"] = float(clear_pts.size()) / pts.size()
	result["visible"] = result["fraction"] >= min_fraction
	return result
