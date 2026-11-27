extends Node
## The commander's warhorse: model contents, gaits and their ground speeds, steering,
## backing, stopping; mounting, riding (seat, stirrups, reins, steering through the
## player's input) and dismounting; refusals; teleports; the whistle.

const SPOT := Vector2(150, -62)  ## North Meadow: open, flat ground
const CLIPS := ["idle", "walk", "trot", "gallop", "turn_left", "rear", "death", "graze", "startle", "head_shake", "stamp"]
const RIDE_CLIPS := ["ride_idle", "ride_walk", "ride_trot", "ride_canter", "ride_gallop", "mount", "dismount"]

var t
var player: PlayerController
var horse: Horse
var rig: HorseRig
var rider: Rider


func run(runner) -> void:
	t = runner
	var main: Node = t.main
	player = main.player
	horse = main.horse
	if not t.check(horse != null and is_instance_valid(horse), "a horse is saddled beside the player at the start"):
		return
	t.main.spawn_horse_near(player)
	await t.physics_frames(5)
	t.check(horse.global_position.distance_to(player.global_position) < 8.0, "the horse is brought beside the commander",
		"%.1f m" % horse.global_position.distance_to(player.global_position))
	rig = horse.get_node("Rig") as HorseRig
	rider = player.get_node("Rider") as Rider
	var w: World = t.world
	var ground := Vector3(SPOT.x, w.terrain_height(SPOT.x, SPOT.y), SPOT.y)
	await _reset(ground)

	# --- model ---------------------------------------------------------------------------------------
	var sk := rig.skeleton
	t.check(sk != null and sk.get_bone_count() >= 70, "the horse has a full quadruped skeleton", "%d bones" % sk.get_bone_count())
	for b in ["hips", "spine_4", "head", "ear_1_l", "front_leg_foot_l", "back_leg_toe_r", "tail_leaf", "saddle", "stirrup_l", "bit_r", "mane_2_1"]:
		t.check(sk.find_bone(b) >= 0, "bone %s exists" % b)
	var missing := []
	for c in CLIPS:
		if not rig.player_anim.has_animation(c):
			missing.append(c)
	t.check(missing.is_empty(), "the horse's clips are present", str(missing))
	t.check(rig.player_anim.get_animation("walk").loop_mode == Animation.LOOP_LINEAR and rig.player_anim.get_animation("rear").loop_mode == Animation.LOOP_NONE,
		"gaits loop, one-shots do not")
	var walk := rig.player_anim.get_animation("walk")
	var hips := walk.find_track("Horse/Skeleton3D:hips", Animation.TYPE_ROTATION_3D)
	var q0: Quaternion = walk.rotation_track_interpolate(hips, 0.0)
	t.check(q0.angle_to(walk.rotation_track_interpolate(hips, walk.length)) < 0.01 and q0.angle_to(walk.rotation_track_interpolate(hips, 1.0 / 30.0)) > 0.001,
		"the walk loop closes without a held frame")
	var tris := 0
	var meshes := 0
	for mi in rig.model.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		meshes += 1
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	t.check(tris < 45000, "horse and tack stay within the real-time budget", "%d triangles in %d meshes" % [tris, meshes])
	var withers := rig.bone_world("spine_4").y - horse.global_position.y
	t.check(withers > 1.45 and withers < 1.75, "a warhorse's height at the withers", "%.2f m" % withers)
	# Hooves on the ground at rest (the lowest hoof bone tip within a few cm of the terrain).
	var lowest := INF
	for b in HorseRig.HOOF_TIPS:
		var p := rig.bone_world(b)
		lowest = minf(lowest, p.y - w.terrain_height(p.x, p.z))
	t.check(lowest > 0.0 and lowest < 0.035, "the hooves stand on the ground, neither floating nor sunk", "lowest hoof tip %.3f m" % lowest)

	# --- gaits ----------------------------------------------------------------------------------------
	horse.cruise = Horse.Gait.WALK
	await _drive(Vector2(0, 1), false, 150)
	t.check(horse.gait == Horse.Gait.WALK and rig.current_state() == "walk", "forward at the walk cruise plays the walk",
		"%s, %.2f m/s" % [horse.gait_name(), horse.speed])
	_check_no_slide("walk", "walk")
	horse.cruise = Horse.Gait.TROT
	await _drive(Vector2(0, 1), false, 120)
	t.check(horse.gait == Horse.Gait.TROT and rig.current_state() == "trot", "the trot is a separate gait, not a faster walk")
	_check_no_slide("trot", "trot")
	await _drive(Vector2(0, 1), true, 50)
	t.check(rig.current_state() == "canter", "sprint first canters", "%s %.1f m/s" % [rig.current_state(), horse.speed])
	await _drive(Vector2(0, 1), true, 150)
	t.check(horse.gait == Horse.Gait.GALLOP and rig.current_state() == "gallop", "held, the horse breaks into a gallop", "%.1f m/s" % horse.speed)
	_check_no_slide("gallop", "gallop")
	var y0 := horse.rotation.y
	await _drive(Vector2(-1, 1), true, 40)
	t.check(angle_difference(y0, horse.rotation.y) > 0.3, "steering left turns the horse")
	# Natural stop: no input, it slows over a couple of seconds, not instantly.
	horse.drive = {}
	await t.physics_frames(20)
	t.check(horse.speed > 2.0, "letting go slows the horse gradually", "%.1f m/s after 0.33 s" % horse.speed)
	await t.physics_frames(200)
	t.check(horse.gait == Horse.Gait.STAND and absf(horse.speed) < 0.05, "and it comes to a stop", horse.gait_name())
	await _drive(Vector2(1, 0), false, 30)
	t.check(rig.current_state() == "turn" and absf(horse.turn_rate) > 0.3, "standing, the horse turns on the spot by stepping")
	horse.drive = {}
	await t.physics_frames(30)
	var p0 := horse.global_position
	await _drive(Vector2(0, -1), false, 90)
	var back := (horse.global_position - p0).dot(horse.forward())
	t.check(horse.gait == Horse.Gait.BACK and rig.current_state() == "back" and back < -0.3, "backing up slowly", "%.2f m" % back)
	t.check(float(rig.tree.get("parameters/back_ts/scale")) < 0.0, "backing plays the walk in reverse")
	horse.drive = {}
	await t.physics_frames(30)
	rig.play("startle")
	await t.physics_frames(10)
	t.check(rig.is_acting(), "the startle reaction plays as a one-shot")
	await t.physics_frames(100)

	# --- mounting -------------------------------------------------------------------------------------
	await _reset(ground)
	player.teleport(horse.global_transform * Vector3(-1.3, 0.1, -0.25), horse.rotation.y - PI * 0.5)
	player.set_look(horse.rotation.y - PI * 0.5, deg_to_rad(-10.0))
	await t.physics_frames(10)
	var interactor := player.get_node("Interactor") as PlayerInteractor
	t.check(interactor.focused == horse.mount_point and horse.mount_point.prompt_text == "Mount", "beside the horse the prompt offers to mount")
	t.check(interactor.try_interact(), "interacting mounts")
	t.check(rider.state == Rider.State.MOUNTING and player.riding and horse.rider == player, "the mount sequence starts and the horse waits")
	t.check(player.collision.disabled, "the commander's own body stops colliding while he mounts")
	var c := rider.commander()
	await t.physics_frames(30)
	t.check(c.is_acting() and (c.tree.tree_root.get_node("act_clip") as AnimationNodeAnimation).animation == "mount", "the mount clip plays")
	var still := horse.global_position
	for i in 300:
		await t.get_tree().physics_frame
		if rider.state == Rider.State.RIDING:
			break
	t.check(rider.state == Rider.State.RIDING, "the commander ends in the saddle")
	t.check(horse.global_position.distance_to(still) < 0.05, "the horse stood still while he mounted")
	await t.physics_frames(20)
	_check_seat("seated at rest")
	t.check(c.riding and c.ride_gait == "ride_idle", "the body plays the seated clip")
	t.check(rig.hand_l != null and rig.hand_l.global_position.distance_to(c.bone_world("hand_l")) < 0.15, "the reins run to his hands")
	for side in ["l", "r"]:
		var foot := c.bone_world("ball_" + side)
		var stir := rig.bone_world("stirrup_" + side)
		t.check(foot.y < rig.seat.global_position.y - 0.5 and foot.distance_to(stir) < 0.75, "%s foot down by the stirrup" % side,
			"%.2f m from the stirrup bar" % foot.distance_to(stir))
	t.check(not player.get_node("Head/Camera3D/ViewModel").visible, "the on-foot hands are hidden on horseback")
	t.check(player.camera.global_position.y > horse.global_position.y + 2.2, "the view rides at the rider's eyes",
		"%.2f m above the ground" % (player.camera.global_position.y - horse.global_position.y))
	var target_pos := player.global_position + horse.forward() * 2.0
	target_pos.y = w.terrain_height(target_pos.x, target_pos.z) + 0.05
	var mounted_target: PlayerController = t.main.spawn_bot(target_pos, SimBot.Role.WANDERER)
	mounted_target.get_node("Brain").process_mode = Node.PROCESS_MODE_DISABLED
	mounted_target.input_override = {}
	await t.physics_frames(3)
	var mounted_stand := Combat.request_mounted_attack(player.player_id)
	await t.physics_frames(18)
	t.check(mounted_stand.ok and mounted_target.combatant.health == 82,
		"a mounted slash hits a close target while standing", "health %d" % mounted_target.combatant.health)
	var repeat_mounted := Combat.request_mounted_attack(player.player_id)
	t.check(not repeat_mounted.ok, "mounted attacks are rate-limited")
	await t.physics_frames(60)
	mounted_target.combatant.set_health(mounted_target.combatant.max_health)
	target_pos = horse.global_position + horse.global_transform.basis.x.normalized() * 6.0
	target_pos.y = w.terrain_height(target_pos.x, target_pos.z) + 0.05
	mounted_target.teleport(target_pos, horse.rotation.y)

	# --- riding -----------------------------------------------------------------------------------------
	player.input_override = {"move": Vector2(0, 1), "sprint": false}
	await t.physics_frames(150)
	t.check(horse.speed > 2.5 and c.ride_gait == "ride_trot", "the player's forward input rides on at a trot", "%.1f m/s, %s" % [horse.speed, c.ride_gait])
	target_pos = player.global_position + horse.forward() * 2.0
	target_pos.y = w.terrain_height(target_pos.x, target_pos.z) + 0.05
	mounted_target.teleport(target_pos, horse.rotation.y)
	mounted_target.combatant.set_health(mounted_target.combatant.max_health)
	await t.physics_frames(2)
	var mounted_trot := Combat.request_mounted_attack(player.player_id)
	await t.physics_frames(18)
	t.check(mounted_trot.ok and mounted_target.combatant.health == 82,
		"the mounted slash also connects at a trot", "health %d" % mounted_target.combatant.health)
	_check_seat("seated at the trot")
	target_pos = horse.global_position + horse.global_transform.basis.x.normalized() * 6.0
	target_pos.y = w.terrain_height(target_pos.x, target_pos.z) + 0.05
	mounted_target.teleport(target_pos, horse.rotation.y)
	player.input_override = {"move": Vector2(0, 1), "sprint": false, "crouch": true}
	await t.physics_frames(2)
	player.input_override = {"move": Vector2(0, 1), "sprint": false}
	await t.physics_frames(120)
	t.check(horse.cruise == Horse.Gait.WALK and horse.gait == Horse.Gait.WALK, "crouch switches the cruising gait to a walk")
	target_pos = player.global_position + horse.forward() * 2.0
	target_pos.y = w.terrain_height(target_pos.x, target_pos.z) + 0.05
	mounted_target.teleport(target_pos, horse.rotation.y)
	await t.physics_frames(2)
	var mounted_walk := Combat.request_mounted_attack(player.player_id)
	await t.physics_frames(18)
	t.check(mounted_walk.ok and mounted_target.combatant.health == 82,
		"the mounted slash connects at a slow walk", "health %d" % mounted_target.combatant.health)
	t.main.bots.erase(mounted_target)
	mounted_target.queue_free()
	player.input_override = {"move": Vector2(0, 1), "sprint": true}
	await t.physics_frames(200)
	t.check(horse.gait == Horse.Gait.GALLOP and c.ride_gait == "ride_gallop", "sprint gallops, the rider in a half seat")
	_check_seat("seated at the gallop", 0.06)
	t.check(not rider.dismount(), "no dismounting at a gallop")
	var yaw0 := horse.rotation.y
	player.input_override = {"move": Vector2(1, 1), "sprint": false}
	await t.physics_frames(60)
	t.check(angle_difference(yaw0, horse.rotation.y) < -0.3, "steering right through the player's input")
	t.check(c._pivot.global_basis.z.dot(horse.global_basis.z) > 0.95, "the rider faces the horse's way")
	player.input_override = {"move": Vector2.ZERO}
	for i in 300:
		await t.get_tree().physics_frame
		if horse.gait == Horse.Gait.STAND:
			break
	t.check(horse.gait == Horse.Gait.STAND, "with no input the horse stops")

	# --- dismounting ------------------------------------------------------------------------------------
	t.check(rider.dismount(), "at a stand the commander dismounts")
	for i in 300:
		await t.get_tree().physics_frame
		if rider.state == Rider.State.NONE:
			break
	t.check(rider.state == Rider.State.NONE and not player.riding and not c.riding, "he is back on foot")
	t.check(not player.collision.disabled and horse.rider == null, "his body collides again and the horse is free")
	var side := horse.to_local(player.global_position)
	t.check(side.x < -0.3 and side.length() < 1.6, "he stands beside the horse's near side", str(side))
	var gy := w.terrain_height(player.global_position.x, player.global_position.z)
	t.check(absf(player.global_position.y - gy) < 0.35, "on the ground", "%.2f m" % (player.global_position.y - gy))
	player.input_override = {"move": Vector2(0, 1)}
	var pp := player.global_position
	await t.physics_frames(40)
	t.check(player.global_position.distance_to(pp) > 1.0, "and walks again")
	player.input_override = {"move": Vector2.ZERO}
	t.check(rig.hand_l == null, "the reins lie back over the neck")

	# --- refusals, teleports, whistle --------------------------------------------------------------------
	await _reset(ground)
	t.check(rider.mount(horse), "mount again")
	await t.physics_frames(5)
	player.teleport(ground + Vector3(20, 1, 0))
	await t.physics_frames(5)
	t.check(rider.state == Rider.State.NONE and not player.riding and horse.rider == null, "a teleport takes him off the horse first")
	GameState.grant_monster_for_testing(player.player_id)
	Combat.request_transform(player.player_id)
	await t.physics_frames(150)
	t.check(rider.mount_refusal(horse) != "", "the horse shies away from the revealed beast", rider.mount_refusal(horse))
	# A reveal lasts a minimum time before the beast may return to human form.
	for i in 1200:
		if Combat.transform_status(player.player_id)["phase"] == "revealed_free":
			break
		await t.get_tree().physics_frame
	Combat.request_revert(player.player_id)
	await t.physics_frames(30)
	GameState.reset_match()
	await t.physics_frames(10)
	await _reset(ground)
	var far := Vector3(ground.x + 12.0, 0.0, ground.z + 36.0)
	far.y = w.terrain_height(far.x, far.z) + 0.1
	player.teleport(far)
	await t.physics_frames(5)
	var d0 := horse.global_position.distance_to(player.global_position)
	t.main.call_horse()
	await t.physics_frames(300)
	var d1 := horse.global_position.distance_to(player.global_position)
	t.check(d1 < d0 - 5.0, "the whistle brings the horse", "%.1f -> %.1f m" % [d0, d1])
	await _reset(ground)


func _reset(ground: Vector3) -> void:
	rider.force_dismount()
	player.input_override = {"move": Vector2.ZERO}
	player.teleport(ground + Vector3(-3, 0.1, 0), 0.0)
	horse.teleport(ground + Vector3.UP * 0.05, 0.0)
	horse.drive = {}
	horse.cruise = Horse.Gait.TROT
	await t.physics_frames(40)


func _drive(move: Vector2, sprint: bool, frames: int) -> void:
	for i in frames:
		horse.drive = {"move": move, "sprint": sprint}
		await t.get_tree().physics_frame


## The hooves keep pace with the ground: clip stride speed x playback rate ~ the body's speed.
func _check_no_slide(state: String, clip: String) -> void:
	var rate := absf(float(rig.tree.get("parameters/%s_ts/scale" % state)))
	var clip_speed := rig.clip_speed(clip, 1.0)
	var feet := clip_speed * rate
	var body := Vector2(horse.get_real_velocity().x, horse.get_real_velocity().z).length()
	t.check(absf(feet - body) / maxf(body, 0.1) < 0.12, "%s: hooves keep pace with the ground (no sliding)" % state,
		"hooves %.2f vs body %.2f m/s" % [feet, body])


func _check_seat(label: String, tol := 0.04) -> void:
	var c := rider.commander()
	var want := rig.seat.global_transform.origin + rig.seat.global_transform.basis.y * Rider.PELVIS_ABOVE_SEAT
	var d := c.bone_world("pelvis").distance_to(want)
	t.check(d < tol, "%s: hips on the saddle" % label, "%.3f m off" % d)
