class_name SpawnValidator
extends RefCounted
## Finds safe standing positions near a requested point: solid ground, above
## water, walkable slope, inside the playable area, with room for a standing
## player. Used for player spawns, the scroll and debug teleports.

const PLAYER_RADIUS := 0.4
const PLAYER_HEIGHT := 1.8


## Returns {ok: bool, position: Vector3, reason: String, tries: int}.
## `from_y` = height to cast down from (NAN = from the sky). Set it below a roof
## to find a floor inside caves or under platforms.
static func find(world: World, xz: Vector2, from_y := NAN, search_radius := 14.0, options := {}) -> Dictionary:
	var max_slope: float = options.get("max_slope_deg", 32.0)
	var min_above_water: float = options.get("min_above_water", 0.4)
	var edge_margin: float = options.get("edge_margin", 12.0)
	var last_reason := "no candidate"
	var tries := 0
	var rings := int(ceil(search_radius / 2.0))
	for ring in rings + 1:
		var r := ring * 2.0
		var steps := 1 if ring == 0 else 8 + ring * 2
		for s in steps:
			var ang := TAU * float(s) / steps + ring * 0.37
			var p := xz + Vector2(cos(ang), sin(ang)) * r
			tries += 1
			var res := check(world, p, from_y, max_slope, min_above_water, edge_margin)
			if res["ok"]:
				res["tries"] = tries
				return res
			last_reason = res["reason"]
	return {"ok": false, "position": Vector3(xz.x, 0, xz.y), "reason": last_reason, "tries": tries}


static func check(world: World, p: Vector2, from_y: float, max_slope: float, min_above_water: float, edge_margin: float) -> Dictionary:
	var fail := func(reason: String) -> Dictionary:
		return {"ok": false, "position": Vector3(p.x, 0, p.y), "reason": reason}
	if not world.terrain_data.in_playable(p.x, p.y, edge_margin):
		return fail.call("outside playable area")
	var top := 400.0 if is_nan(from_y) else from_y
	var hit := world.ground_ray(p.x, p.y, top, top + 100.0)
	if hit.is_empty():
		return fail.call("no ground")
	var pos: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if pos.y < world.water_level + min_above_water:
		return fail.call("under or too close to water")
	if normal.y < cos(deg_to_rad(max_slope)):
		return fail.call("slope too steep")
	var space := world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = PLAYER_RADIUS
	capsule.height = PLAYER_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * (PLAYER_HEIGHT * 0.5 + 0.15))
	q.collision_mask = Layers.WORLD
	if not space.intersect_shape(q, 1).is_empty():
		return fail.call("blocked by geometry")
	return {"ok": true, "position": pos, "reason": "", "normal": normal}
