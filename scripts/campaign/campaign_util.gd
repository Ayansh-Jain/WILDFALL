class_name CampaignUtil
extends RefCounted
## Small helpers shared by the campaign scripts.


## Whether the local player's camera can see `p`: in the view frustum, within
## `max_dist`, and not behind a wall. Soldiers and spies are only ever removed when
## this is false, so nobody vanishes in front of the player.
static func in_view(viewer: PlayerController, p: Vector3, max_dist := 150.0) -> bool:
	if viewer == null or not is_instance_valid(viewer):
		return false
	var cam := viewer.camera
	if cam == null or not cam.is_inside_tree():
		return false
	if cam.global_position.distance_to(p) > max_dist:
		return false
	if not cam.is_position_in_frustum(p):
		return false
	var space := cam.get_world_3d().direct_space_state
	return LineOfSight.is_clear(space, cam.global_position, p, [viewer.get_rid()], Layers.WORLD)


static func v3(world: World, p: Variant) -> Vector3:
	var v := WorldLayout.v2(p)
	return Vector3(v.x, world.terrain_height(v.x, v.y), v.y)


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
