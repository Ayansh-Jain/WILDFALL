extends Node
## Line of sight is blocked by trunks, rocks, walls, terrain and bushes, and a
## player standing behind cover is reported hidden.


func run(t) -> void:
	var w: World = t.world
	var space := w.get_world_3d().direct_space_state
	var player: PlayerController = t.main.player
	var drv := PlayerDriver.new(player)

	# Open ground: clear sight.
	var meadow := WorldLayout.v2(w.layout.find_site("Hunter's Camp")["center"]) + Vector2(0, 8)
	var gy := w.terrain_height(meadow.x, meadow.y)
	t.check(LineOfSight.is_clear(space, Vector3(meadow.x - 3, gy + 1.6, meadow.y), Vector3(meadow.x + 3, gy + 1.6, meadow.y)),
		"sight is clear across open ground")

	# Citadel wall blocks sight.
	var c := WorldLayout.v2(w.layout.find_site("Old Citadel")["center"])
	var hc := w.site_height("Old Citadel")
	var inside := Vector3(c.x + 4, hc + 1.6, c.y - 20)
	var outside := Vector3(c.x + 4, hc + 1.6, c.y - 30)
	t.check(not LineOfSight.is_clear(space, inside, outside), "citadel wall blocks sight")

	# A tree trunk blocks sight: find one with a horizontal ray through the forest.
	var trunk := _find_trunk(w, space)
	t.check(not trunk.is_empty(), "found a tree trunk in the deep forest")
	if not trunk.is_empty():
		var hit: Vector3 = trunk["position"]
		var dir: Vector3 = trunk["dir"]
		t.check(not LineOfSight.is_clear(space, hit - dir * 1.5, hit + dir * 1.5, [], Layers.WORLD), "tree trunk blocks sight")

	# Terrain hill blocks sight (Watcher's Hill).
	var hill := Vector2(-200, 190)
	var a := Vector3(hill.x - 70, w.terrain_height(hill.x - 70, hill.y) + 1.6, hill.y)
	var b := Vector3(hill.x + 70, w.terrain_height(hill.x + 70, hill.y) + 1.6, hill.y)
	t.check(not LineOfSight.is_clear(space, a, b, [], Layers.WORLD), "terrain (Watcher's Hill) blocks sight")

	# Bushes: block sight but not movement.
	var bush := _find_layer_hit(w, space, Layers.FOLIAGE_SIGHT)
	t.check(not bush.is_empty(), "found a sight-blocking bush")
	if not bush.is_empty():
		var p: Vector3 = bush["position"]
		var d: Vector3 = bush["dir"]
		t.check(not LineOfSight.is_clear(space, p - d * 1.0, p + d * 2.5), "bush blocks sight with the default mask")
		var solid_hit := LineOfSight.raycast(space, p - d * 1.0, p + d * 2.5, [], Layers.WORLD)
		t.check(solid_hit.is_empty() or solid_hit["rid"] != bush["rid"], "bush is ignored when foliage is excluded from the mask")
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.8
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, p)
		q.collision_mask = player.collision_mask
		var blockers := space.intersect_shape(q, 4)
		var foliage_blocks_movement := false
		for r in blockers:
			if r["collider"] == null:
				continue
			var obj: Object = r["collider"]
			if obj is CollisionObject3D and (obj.collision_layer & Layers.FOLIAGE_SIGHT) != 0:
				foliage_blocks_movement = true
		t.check(not foliage_blocks_movement and (player.collision_mask & Layers.FOLIAGE_SIGHT) == 0, "player movement ignores bush colliders")

	# Hiding: a watcher in the courtyard sees the player in the open, but not behind the hall wall.
	var watcher := Vector3(c.x - 6, hc + 1.7, c.y + 13)
	var open_spot := SpawnValidator.find(w, Vector2(c.x - 2, c.y + 13), hc + 3.0, 3.0)
	player.teleport(open_spot["position"])
	await drv.frames(5)
	var seen := LineOfSight.can_see(space, watcher, Vector3.RIGHT, player.global_position, player.current_height(), {"exclude": [player.get_rid()]})
	t.check(seen["visible"], "watcher sees a player standing in the open", "%d%% visible" % int(seen["fraction"] * 100))
	# Behind the collapsed hall's west... use the east wall of the hall (local x = 19).
	var behind := SpawnValidator.find(w, Vector2(c.x + 21.5, c.y + 13), hc + 3.0, 2.0)
	t.check(behind["ok"], "found a hiding spot behind the hall wall")
	player.teleport(behind["position"])
	await drv.frames(5)
	var hidden := LineOfSight.can_see(space, watcher, Vector3.RIGHT, player.global_position, player.current_height(), {"exclude": [player.get_rid()]})
	t.check(not hidden["visible"], "player behind the wall is hidden from the watcher", "%d%% visible" % int(hidden["fraction"] * 100))
	var cone := LineOfSight.can_see(space, watcher, Vector3.LEFT, open_spot["position"], 1.8, {"fov": 90.0})
	t.check(not cone["visible"] and not cone["in_view_cone"], "view cone excludes targets behind the watcher")

	# SightProbe (the in-game demo tool) agrees.
	var probe := SightProbe.new()
	w.add_child(probe)
	probe.global_position = watcher
	probe.target = player
	await drv.frames(3)
	t.check(not probe.is_target_visible, "sight probe reports the hidden player as hidden")
	player.teleport(open_spot["position"])
	await drv.frames(5)
	t.check(probe.is_target_visible, "sight probe sees the player after stepping out")
	probe.queue_free()
	drv.release()


func _find_trunk(w: World, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var veg := w.get_node("Props/Vegetation")
	for i in 60:
		var x := -205.0 + i * 2.0
		var z := 60.0
		var y := w.terrain_height(x, z) + 1.0
		var from := Vector3(x, y, z - 30)
		var to := Vector3(x, y, z + 30)
		var q := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit["collider"] == veg:
			return {"position": hit["position"], "dir": Vector3(0, 0, 1)}
	return {}


func _find_layer_hit(w: World, space: PhysicsDirectSpaceState3D, mask: int) -> Dictionary:
	for i in 80:
		var x := -230.0 + i * 3.0
		var z := 40.0
		var y := w.terrain_height(x, z) + 0.6
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, y, z - 40), Vector3(x, y, z + 40), mask)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return {"position": hit["position"], "dir": Vector3(0, 0, 1), "rid": hit["rid"]}
	return {}
