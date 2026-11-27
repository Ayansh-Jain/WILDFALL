extends Node
## Arbitrary terrain sitting, slope rejection and reversible controls.


func run(t) -> void:
	var player: PlayerController = t.main.player
	var world: World = t.world
	t.check(world.get_node_or_null("GroundSitSpots") == null,
		"sitting no longer depends on generated markers")
	var vegetation := world.get_node_or_null("Props/Vegetation")
	t.check(vegetation == null or vegetation.find_children("LogRestSpot", "Node3D", true, false).is_empty(),
		"logs do not need seat interaction objects")
	t.check(Settings.DEFAULT_BINDINGS["sit"][1] == ["key:G"] and Settings.DEFAULT_BINDINGS["crouch"][1].has("key:C"),
		"the configurable sit key is distinct from crouch")
	t.check(PlayerController.sit_slope_is_safe(Vector3.UP)
		and not PlayerController.sit_slope_is_safe(Vector3(0.4, 0.8, 0.0).normalized()),
		"flat terrain is accepted and steep slopes are rejected")

	player.input_override = {"move": Vector2.ZERO}
	var centers := [Vector2(150, -62), Vector2(-128, -50), Vector2(38, 160)]
	var visited: Array[Vector3] = []
	for center in centers:
		var candidates := _flat_candidates(world, center)
		for point in candidates:
			player.teleport(Vector3(point.x, world.terrain_height(point.x, point.y) + 0.1, point.y))
			await t.physics_frames(10)
			if not player.can_sit_anywhere():
				continue
			visited.append(player.global_position)
			if visited.size() == 1:
				await _exercise_sprint_stop(t, player)
			else:
				await _exercise_sit(t, player, world)
			break
	t.check(visited.size() >= 2, "sitting works at multiple unrelated terrain locations", str(visited.size()))
	if visited.size() >= 2:
		t.check(visited[0].distance_to(visited[1]) > 15.0, "sitting locations are separated and marker-free")

	var steep := _steep_candidate(world)
	if steep != Vector2(INF, INF):
		player.teleport(Vector3(steep.x, world.terrain_height(steep.x, steep.y) + 0.1, steep.y))
		await t.physics_frames(10)
		t.check(not player.can_sit_anywhere(), "the actual terrain probe declines a steep location")
	else:
		t.check(not PlayerController.sit_slope_is_safe(Vector3(0.4, 0.8, 0.0).normalized()),
			"steep terrain is declined (no steep test cell in this world seed)")
	player.input_override = null


func _exercise_sit(t, player: PlayerController, world: World) -> void:
	var origin := player.global_position
	var rig := (player.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig
	t.check(player.sit_at(), "the sit action starts from ordinary terrain without a marker")
	await t.physics_frames(88)
	t.check(player.is_sitting and not player.controls_enabled and player.collision.disabled,
		"the seated state locks movement and disables the standing capsule")
	t.check(rig.current_hold() == "sit_idle", "sit-down transitions into relaxed ground-sitting idle")
	t.check(absf(player.global_position.y - world.terrain_height(player.global_position.x, player.global_position.z)) < 0.16,
		"the sitting pose stays aligned to the detected ground")
	var old_yaw := player.rotation.y
	player.look(Vector2(4.0, 0.0))
	t.check(not is_equal_approx(player.rotation.y, old_yaw), "camera look remains active while seated")
	player.stand_from_seat()
	await t.physics_frames(72)
	t.check(not player.is_sitting and player.controls_enabled and not player.collision.disabled,
		"standing restores movement and collision")
	t.check(player.global_position.distance_to(origin) < 0.16,
		"standing returns to the original position and immediately resumes play")


func _exercise_sprint_stop(t, player: PlayerController) -> void:
	player.input_override = {"move": Vector2(0, 0.15), "sprint": true}
	await t.physics_frames(3)
	t.check(player.is_sprinting, "a ground sprint can transition directly into sitting")
	t.check(t.main.hud.prompt_text().contains("Sit"), "the contextual sit hint appears without a marker")
	t.check(player.sit_at(), "sitting safely interrupts sprint movement")
	t.check(not player.is_sprinting and Vector2(player.velocity.x, player.velocity.z).length() < 0.01,
		"sitting cancels sprint momentum without a running slide")
	await t.physics_frames(88)
	t.check(t.main.hud.prompt_text().contains("Stand"), "the HUD changes to a stand-up hint while seated")
	player.stand_from_seat()
	await t.physics_frames(72)
	t.check(not player.is_sitting and player.controls_enabled and not player.collision.disabled,
		"standing after a sprint restores normal movement and collision")
	player.input_override = {"move": Vector2.ZERO}


func _flat_candidates(world: World, center: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var td := world.terrain_data
	for radius in range(0, 7):
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				if maxi(abs(dx), abs(dz)) != radius:
					continue
				var p := center + Vector2(dx, dz) * 2.0
				if not td.in_playable(p.x, p.y, -1.0):
					continue
				if td.normal_at(p.x, p.y).y < 0.97 or td.height_at(p.x, p.y) < world.water_level + 1.0:
					continue
				out.append(p)
	return out


func _steep_candidate(world: World) -> Vector2:
	var td := world.terrain_data
	for z in range(-180, 181, 8):
		for x in range(-180, 181, 8):
			if not td.in_playable(float(x), float(z), -1.0):
				continue
			var n := td.normal_at(float(x), float(z))
			if n.y >= 0.91 or n.y < 0.76:
				continue
			if td.height_at(float(x), float(z)) <= world.water_level + 1.0:
				continue
			return Vector2(x, z)
	return Vector2(INF, INF)
