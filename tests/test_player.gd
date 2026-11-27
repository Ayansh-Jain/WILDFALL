extends Node
## First-person controller behaviour, exercised through the real physics.


func run(t) -> void:
	var w: World = t.world
	var player: PlayerController = t.main.player
	var drv := PlayerDriver.new(player)
	var start := _flat_spot(w)
	t.check(start != Vector3.INF, "found a flat test area", str(start))

	# Grounding and gravity
	player.teleport(start + Vector3.UP * 3.0, 0.0)
	await drv.frames(90)
	t.check(player.is_on_floor(), "player falls and lands on the ground")
	t.check(absf(player.global_position.y - start.y) < 0.3, "player rests on the terrain surface", "%.2f vs %.2f" % [player.global_position.y, start.y])

	# Walk / sprint / crouch speeds
	var walk := await _measure_speed(drv, player, start, false, false)
	t.check(absf(walk - player.walk_speed) < 0.6, "walk speed ~%.1f m/s" % player.walk_speed, "%.2f" % walk)
	var sprint := await _measure_speed(drv, player, start, true, false)
	t.check(sprint > walk + 1.5 and absf(sprint - player.sprint_speed) < 0.8, "sprint is faster (~%.1f m/s)" % player.sprint_speed, "%.2f" % sprint)
	var crouch := await _measure_speed(drv, player, start, false, true)
	t.check(crouch < walk - 1.0, "crouch-walk is slower", "%.2f" % crouch)
	t.check(player.is_crouching and player.current_height() < 1.3, "crouching lowers the collision capsule", "%.2f m" % player.current_height())
	var eye_crouched := player.head.position.y
	drv.set_input()
	await drv.frames(30)
	t.check(not player.is_crouching and player.current_height() > 1.75, "player stands back up when crouch is released")
	t.check(player.head.position.y > eye_crouched + 0.4, "eye height rises when standing", "%.2f -> %.2f" % [eye_crouched, player.head.position.y])

	# Jump
	player.teleport(start, 0.0)
	await drv.frames(20)
	var y0 := player.global_position.y
	var apex := y0
	drv.set_input(Vector2.ZERO, false, false, true, true)
	for i in 70:
		await drv.frames(1)
		apex = maxf(apex, player.global_position.y)
		drv.set_input()
	var jump_h := apex - y0
	t.check(jump_h > 0.8 and jump_h < 1.3, "jump reaches about 1 m", "%.2f m" % jump_h)
	t.check(player.is_on_floor(), "player lands after jumping")

	# Mouse look
	player.set_look(0.0, 0.0)
	var sens := Settings.mouse_sensitivity
	player.look(Vector2(100, 0))
	t.check(absf(rad_to_deg(-player.rotation.y) - 100.0 * sens) < 0.01, "mouse look yaw follows sensitivity", "%.2f deg" % rad_to_deg(-player.rotation.y))
	player.look(Vector2(0, 10000))
	t.check(absf(rad_to_deg(player.head.rotation.x) + player.max_pitch) < 0.01, "pitch is clamped", "%.1f deg" % rad_to_deg(player.head.rotation.x))
	player.set_look(0.0, 0.0)

	# Crouch under a low ceiling: cannot stand up into geometry.
	var roof := _box(start + Vector3(0, 1.45 + 0.25, 0), Vector3(3, 0.5, 3))
	add_child(roof)
	player.teleport(start, 0.0)
	await drv.frames(5)
	drv.set_input(Vector2.ZERO, false, true)
	await drv.frames(40)
	drv.set_input()
	await drv.frames(40)
	t.check(player.is_crouching, "player stays crouched under a low ceiling")
	roof.queue_free()
	await drv.frames(5)
	await drv.frames(30)
	t.check(not player.is_crouching, "player stands once the ceiling is gone")

	# Step-up over small ledges, blocked by tall ones.
	var step_ok := await _try_obstacle(drv, player, start, 0.3)
	t.check(step_ok, "walks up a 0.3 m ledge without jumping")
	var wall_blocks := not await _try_obstacle(drv, player, start, 1.2)
	t.check(wall_blocks, "a 1.2 m wall blocks walking")

	# Solid collision: walking into the citadel wall never passes through.
	var c := WorldLayout.v2(w.layout.find_site("Old Citadel")["center"])
	var outside := Vector3(c.x + 4.0, 0, c.y - 30.0)
	var res := SpawnValidator.find(w, Vector2(outside.x, outside.z), NAN, 4.0)
	player.teleport(res["position"], 0.0)
	await drv.frames(10)
	drv.face(Vector3(c.x + 4.0, res["position"].y, c.y))
	drv.set_input(Vector2(0, 1), true)
	await drv.frames(150)
	drv.set_input()
	t.check(player.global_position.z < c.y - 24.0 + 0.2, "citadel north wall stops the player", "z %.2f, wall at %.1f" % [player.global_position.z, c.y - 24.0])

	# Water: swimming in the lake, wading at a ford.
	var lake := WorldLayout.v2(w.layout.dict("lake")["center"])
	player.teleport(Vector3(lake.x - 30, w.water_level - 1.0, lake.y), 0.0)
	await drv.frames(220)
	t.check(player.is_swimming, "player swims in deep water")
	t.check(absf(player.global_position.y - (w.water_level - player.float_depth)) < 0.35, "swimmer floats with eyes above the surface", "feet %.2f" % player.global_position.y)
	t.check(player.camera.global_position.y > w.water_level, "camera stays above water while floating")
	var ford := WorldLayout.v2(w.layout.list("fords")[0]["center"])
	player.teleport(Vector3(ford.x, 2.0, ford.y), 0.0)
	await drv.frames(60)
	t.check(not player.is_swimming and player.water_depth > 0.15, "ford is wadeable (not swimming)", "depth %.2f" % player.water_depth)

	# Falling out of the world triggers a respawn.
	var fired := [false]
	var cb := func() -> void: fired[0] = true
	player.fell_out_of_world.connect(cb)
	player.set_noclip(false)
	player.teleport(Vector3(0, -45, 0))
	await drv.frames(3)
	t.check(fired[0] and player.global_position.y > -10.0, "falling below the world respawns the player")
	player.fell_out_of_world.disconnect(cb)
	drv.release()


func _measure_speed(drv: PlayerDriver, player: PlayerController, start: Vector3, sprint: bool, crouch: bool) -> float:
	player.teleport(start, 0.0)
	await drv.frames(10)
	drv.set_input(Vector2(0, 1), sprint, crouch)
	await drv.frames(40)
	var p0 := player.global_position
	await drv.frames(60)
	var p1 := player.global_position
	drv.set_input(Vector2.ZERO, false, crouch)
	return Vector2(p1.x - p0.x, p1.z - p0.z).length()


func _try_obstacle(drv: PlayerDriver, player: PlayerController, start: Vector3, height: float) -> bool:
	var box := _box(start + Vector3(0, height * 0.5 - 0.05, -3.0), Vector3(4, height, 2))
	add_child(box)
	player.teleport(start, 0.0)
	await drv.frames(10)
	drv.set_input(Vector2(0, 1))
	await drv.frames(90)
	drv.set_input()
	var passed := player.global_position.z < start.z - 3.0
	box.queue_free()
	await drv.frames(2)
	return passed


func _box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = center
	return body


## A flat, open, dry spot (the west clearing) with nothing around it.
func _flat_spot(w: World) -> Vector3:
	for c in w.layout.list("clearings"):
		if c["name"] == "North Meadow":
			var p := WorldLayout.v2(c["center"])
			var res := SpawnValidator.find(w, p, NAN, 10.0, {"max_slope_deg": 8.0})
			if res["ok"]:
				return res["position"]
	return Vector3.INF
