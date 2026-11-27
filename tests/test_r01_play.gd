extends Node
## R01: camera framing and cinematic hand-over, safe mounting / dismounting, horse
## terrain behaviour, recall rules. Hazards are built on a platform high above the map.

const LAB := Vector3(0.0, 220.0, 0.0)

var t
var player: PlayerController
var horse: Horse
var rider: Rider
var made: Array[Node] = []


func run(runner) -> void:
	t = runner
	player = t.main.player
	if t.main.horse == null:
		t.main.spawn_horse_near(player)
	horse = t.main.horse
	rider = player.get_node("Rider")
	var home := player.global_position
	rider.force_dismount()
	horse.stop_recall()
	var shake := Settings.camera_shake
	var reduce := Settings.reduce_motion
	await _lab_floor()
	await _camera()
	await _cinematic()
	await _mounting()
	await _horse_terrain()
	await _recall()
	Settings.camera_shake = shake
	Settings.reduce_motion = reduce
	rider.force_dismount()
	horse.drive = null
	for n in made:
		if is_instance_valid(n):
			n.queue_free()
	player.input_override = null
	player.teleport(home + Vector3.UP * 0.1, 0.0)
	t.main.spawn_horse_near(player)
	await t.physics_frames(30)


func _box(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	t.main.add_child(body)
	body.global_position = centre
	made.append(body)
	return body


func _lab_floor() -> void:
	_box(LAB + Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	await t.physics_frames(2)


func _place(p: Vector3) -> void:
	player.input_override = {"move": Vector2.ZERO}
	player.teleport(p + Vector3.UP * 0.05, 0.0)
	await t.physics_frames(30)


func _cam_distance() -> float:
	return player.camera.global_position.distance_to(player.global_position + Vector3.UP * 1.4)


func _camera() -> void:
	await _place(LAB)
	t.check(player.cam.mode == PlayerCamera.Mode.EXPLORE, "open ground uses the exploration framing", player.cam.mode_name())
	var explore := _cam_distance()
	var explore_fov := player.camera.fov
	t.check(explore > 3.9, "exploration keeps the Commander small enough to see the land", "%.2f m" % explore)

	player.input_override = {"move": Vector2(0, 1), "sprint": true}
	await t.physics_frames(75)
	t.check(player.cam.mode == PlayerCamera.Mode.SPRINT and player.camera.fov > explore_fov + 2.0, "sprinting widens the view a little",
		"%s fov %.1f -> %.1f" % [player.cam.mode_name(), explore_fov, player.camera.fov])
	Settings.reduce_motion = true
	await t.physics_frames(75)
	t.check(absf(player.camera.fov - Settings.fov) < 0.8, "reduce motion removes the speed FOV change", "%.1f" % player.camera.fov)
	player.add_shake(1.0)
	await t.physics_frames(1)
	t.check(player.camera.h_offset == 0.0 and player.camera.v_offset == 0.0, "reduce motion removes shake")
	Settings.reduce_motion = false
	Settings.camera_shake = 0.0
	player.add_shake(1.0)
	await t.physics_frames(1)
	t.check(is_zero_approx(player.camera.h_offset), "shake strength 0 removes shake")
	Settings.camera_shake = 1.0
	player.add_shake(1.0)
	await t.physics_frames(3)
	t.check(absf(player.camera.h_offset) + absf(player.camera.v_offset) > 0.001, "full shake strength shakes")
	await _place(LAB)

	var yaw := player.rotation.y
	player.combatant.last_combat_time = Combat.now()
	await t.physics_frames(45)
	t.check(player.cam.mode == PlayerCamera.Mode.COMBAT and _cam_distance() > explore, "a fight pulls the camera back and up",
		"%s %.2f m" % [player.cam.mode_name(), _cam_distance()])
	t.check(is_equal_approx(player.rotation.y, yaw), "the combat camera never turns the view")
	player.combatant.last_combat_time = -100.0
	await t.physics_frames(300)
	t.check(player.cam.mode == PlayerCamera.Mode.EXPLORE, "and settles back afterwards", player.cam.mode_name())

	var roof := _box(LAB + Vector3(0, 3.0, 0), Vector3(14, 0.3, 14))
	await t.physics_frames(60)
	t.check(player.cam.mode == PlayerCamera.Mode.TIGHT, "a low ceiling tightens the framing", player.cam.mode_name())
	t.check(player.camera.global_position.y < roof.global_position.y - 0.15, "the camera stays under the ceiling",
		"%.2f" % (player.camera.global_position.y - LAB.y))
	roof.global_position = LAB + Vector3(0, 7.0, 0)
	await t.physics_frames(60)
	t.check(player.cam.mode == PlayerCamera.Mode.HALL, "a high ceiling uses the hall framing", player.cam.mode_name())
	made.erase(roof)
	roof.free()

	var wall := _box(LAB + Vector3(0, 2, 1.6), Vector3(10, 4, 0.4))
	await t.physics_frames(30)
	t.check(player.camera.global_position.z < wall.global_position.z - 0.2, "a wall behind pulls the camera in front of it",
		"%.2f" % player.camera.global_position.z)
	made.erase(wall)
	wall.free()
	player.teleport(LAB + Vector3(12, 0.05, 12), 0.0)
	await t.physics_frames(1)
	t.check(player.camera.global_position.distance_to(player.global_position) < 7.0, "after a teleport the camera is already there")


func _cinematic() -> void:
	await _place(LAB)
	var cine := player.cam.begin_cinematic("test_scene")
	t.check(cine != null and cine.current and player.cam.in_cinematic(), "a cinematic takes the view")
	t.check(player.cam.begin_cinematic("other") == null, "a second owner cannot take it")
	player.input_override = {"move": Vector2(0, 1)}
	var p0 := player.global_position
	await t.physics_frames(30)
	t.check(player.global_position.distance_to(p0) < 0.05, "the Commander holds still during it")
	t.check(not player.cam.end_cinematic("other"), "only the owner can end it")
	player.cam.end_cinematic("test_scene", 0.3)
	await t.physics_frames(40)
	t.check(player.camera.current and not player.cam.in_cinematic() and player.locks.token_count() == 0, "the view and control come back")
	await t.physics_frames(20)
	t.check(player.global_position.distance_to(p0) > 0.3, "and he moves again")
	player.cam.begin_cinematic("test_scene")
	player.on_defeated()
	t.check(player.camera.current and player.locks.token_count() == 0, "defeat aborts a cinematic cleanly")
	player.on_respawned()
	await _place(LAB)

	var from := player.global_position
	t.check(player.request_attack_motion(1.0, 0.25), "an attack may request a short step")
	t.check(not player.request_attack_motion(1.0, 0.25), "but cannot stack one on another")
	await t.physics_frames(40)
	var moved := player.global_position.distance_to(from)
	t.check(moved > 0.7 and moved < 1.4 and player.ground_speed() < 0.1, "the step ends by itself", "%.2f m" % moved)


func _mount_now() -> bool:
	if not rider.mount(horse):
		return false
	for i in 400:
		await t.get_tree().physics_frame
		if rider.is_riding():
			return true
	return false


func _wait_off() -> bool:
	for i in 400:
		await t.get_tree().physics_frame
		if rider.state == Rider.State.NONE:
			return true
	return false


func _stage_horse(at: Vector3) -> void:
	rider.force_dismount()
	horse.teleport(at + Vector3.UP * 0.05, 0.0)
	horse.drive = {}
	await _place(at + Vector3(-2.0, 0, 0))


func _mounting() -> void:
	await _stage_horse(LAB)
	t.check(await _mount_now(), "mounting in the open")
	t.check(player.cam.mode == PlayerCamera.Mode.MOUNTED, "riding uses the mounted framing", player.cam.mode_name())

	# Wall along the near (left, -X) side: step down on the other side.
	var left := _box(LAB + Vector3(-0.95, 1.5, 0), Vector3(0.4, 3, 7))
	await t.physics_frames(5)
	t.check(rider.dismount() and await _wait_off(), "dismounting beside a wall")
	var local := horse.to_local(player.global_position)
	t.check(local.x > 0.3, "he steps down on the clear side, not into the wall", str(local))

	# Boxed in on every side: refused, and a forced dismount still ends somewhere valid.
	horse.teleport(LAB + Vector3.UP * 0.05, 0.0)
	await t.physics_frames(3)
	t.check(await _mount_now(), "mounting again with the near side walled (lift, no clip through)")
	var walls := [_box(LAB + Vector3(0.95, 1.5, 0), Vector3(0.4, 3, 7)), _box(LAB + Vector3(0, 1.5, 2.0), Vector3(3, 3, 0.4)),
		_box(LAB + Vector3(0, 1.5, -2.4), Vector3(3, 3, 0.4))]
	await t.physics_frames(5)
	t.check(not rider.dismount() and rider.is_riding(), "no dismount when there is no room")
	rider.force_dismount()
	t.check(rider.state == Rider.State.NONE and not player.riding and not player.collision.disabled, "a forced dismount always restores control")
	t.check(Vector2(player.global_position.x - horse.global_position.x, player.global_position.z - horse.global_position.z).length() < 0.5,
		"and never places him beyond the walls")
	for w in walls + [left]:
		made.erase(w)
		w.free()

	# Defeat in the middle of mounting.
	await _stage_horse(LAB)
	rider.mount(horse)
	await t.physics_frames(8)
	player.is_defeated = true
	await t.physics_frames(3)
	t.check(rider.state == Rider.State.NONE and not player.riding and horse.rider == null, "defeat while mounting releases the horse")
	player.on_respawned()
	await t.physics_frames(3)
	t.check(not player.collision.disabled and player.camera.current, "control and camera are restored")


func _horse_terrain() -> void:
	# The lab floor ends at x = +/-30: ride at the edge.
	await _stage_horse(LAB + Vector3(20, 0, 10))
	horse.teleport(LAB + Vector3(18, 0.05, 10), -PI * 0.5)  # facing +X
	for i in 360:
		horse.drive = {"move": Vector2(0, 1), "sprint": true}
		await t.get_tree().physics_frame
	t.check(horse.global_position.y > LAB.y - 0.5 and horse.global_position.x < 30.0, "the horse will not gallop off a drop",
		str(horse.global_position - LAB))

	var kerb := _box(LAB + Vector3(0, 0.15, -8), Vector3(8, 0.3, 4))
	horse.teleport(LAB + Vector3(0, 0.05, 0), 0.0)
	var top := 0.0
	for i in 420:
		horse.drive = {"move": Vector2(0, 1), "sprint": false}
		await t.get_tree().physics_frame
		top = maxf(top, horse.global_position.y - LAB.y)
	t.check(horse.global_position.z < -11.0 and top > 0.2, "a 0.3 m ledge is stepped over", "z %.1f, rose %.2f" % [horse.global_position.z - LAB.z, top])
	made.erase(kerb)
	kerb.free()

	horse.drive = null
	horse.teleport(LAB + Vector3(0, 0.05, 0), 0.0)
	await t.physics_frames(20)
	var far_cam := Camera3D.new()
	t.main.add_child(far_cam)
	far_cam.global_position = LAB + Vector3(200, 10, 0)
	far_cam.make_current()
	horse.check_dormancy()
	t.check(horse.dormant and not horse.is_physics_processing(), "an idle distant horse sleeps")
	player.camera.make_current()
	horse.check_dormancy()
	t.check(not horse.dormant and horse.is_physics_processing(), "and wakes when the Commander is near")
	far_cam.free()


func _recall() -> void:
	await _stage_horse(LAB + Vector3(0, 0, 18))
	await _place(LAB + Vector3(0, 0, -6))
	var horses: int = t.get_tree().get_nodes_in_group("horses").size()
	var d0: float = horse.global_position.distance_to(player.global_position)
	t.main.call_horse()
	t.main.call_horse()
	t.main.call_horse()
	horse.drive = null
	await t.physics_frames(420)
	t.check(t.get_tree().get_nodes_in_group("horses").size() == horses, "repeated whistles never create another horse")
	var d1: float = horse.global_position.distance_to(player.global_position)
	t.check(d1 < 6.0 and d1 < d0 - 10.0, "the horse trots over", "%.1f -> %.1f m" % [d0, d1])
	var roof := _box(player.global_position + Vector3(0, 5, 0), Vector3(8, 0.3, 8))
	await t.physics_frames(3)
	t.check(t.main.recall.refusal().begins_with("Your horse cannot"), "no recall indoors", t.main.recall.refusal())
	made.erase(roof)
	roof.free()
	var token := player.locks.acquire("test", ControlLock.MOVE)
	t.check(t.main.recall.refusal() == "busy", "no recall while control is held")
	player.locks.release(token)

	horse.teleport(LAB + Vector3(300, 0, 0), 0.0)
	await t.main.call_horse()
	t.check(horse.global_position.distance_to(player.global_position) < 8.0 and player.locks.token_count() == 0,
		"a far horse arrives under a fade and control returns", "%.1f m" % horse.global_position.distance_to(player.global_position))
