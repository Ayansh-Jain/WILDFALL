extends Node
## The realistic commander body of the local player: model contents (skeleton,
## face shapes, animation clips, sockets), sword handling, locomotion and landing
## states, expressions and blinking, cloak springs, third-person camera, the
## monster transformation, and that bots keep the low-poly explorer body.

const REQUIRED_CLIPS := ["idle", "idle_talk", "walk", "jog", "run", "crouch_idle", "crouch_walk", "jump_start", "fall",
	"land", "land_hard", "roll", "swim", "swim_idle", "sword_idle", "sword_light", "sword_light_rec", "sword_light_b",
	"sword_heavy", "sword_block", "sword_draw", "sword_sheath", "hit_chest", "hit_head", "hit_knockback", "death",
	"get_up", "climb_ledge", "study_map", "lean_window", "moon_gaze", "nod_yes", "sit_enter", "sit_idle", "sit_exit", "ride_idle", "ride_walk", "ride_trot",
	"ride_gallop"]
const SPOT := Vector2(-232, 108)  ## Great Gate Field: open, flat ground (North Meadow is a hamlet now)


func run(t) -> void:
	var w: World = t.world
	var main: Node = t.main
	var player: PlayerController = main.player
	var visual: AvatarVisual = player.get_node("AvatarVisual")
	var rig := visual.human_rig as CommanderRig
	if not t.check(rig != null, "the local player's body is the commander"):
		return
	var belt_lantern := player.get_node_or_null("BeltLantern") as OmniLight3D
	t.check(belt_lantern != null and rig._lantern != null, "the portable lamp has a belt model and local light")
	if belt_lantern and rig._lantern:
		rig.set_lamp_enabled(false)
		await _frames(t, 2)
		t.check(not belt_lantern.visible and not rig._lantern.visible, "turning the lamp off hides both its light and model")
		rig.set_lamp_enabled(true)
		await _frames(t, 2)
		t.check(belt_lantern.visible and rig._lantern.visible, "turning the lamp on restores its light and model")
		var old_mouse := Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var toggle := InputEventAction.new()
		toggle.action = "toggle_lamp"
		toggle.pressed = true
		(player.get_node("Abilities") as PlayerAbilities)._unhandled_input(toggle)
		await _frames(t, 2)
		t.check(not player.portable_lamp_on and not belt_lantern.visible and not rig._lantern.visible,
			"the bound L action toggles the lamp model and local light together")
		toggle.pressed = false
		(player.get_node("Abilities") as PlayerAbilities)._unhandled_input(toggle)
		Input.mouse_mode = old_mouse
	t.check(Settings.DEFAULT_BINDINGS.has("toggle_weapons") and InputMap.has_action("toggle_weapons")
		and Settings.DEFAULT_BINDINGS["toggle_weapons"][1] == ["key:X"], "X is configurable for drawing and sheathing both swords")
	var ground := Vector3(SPOT.x, w.terrain_height(SPOT.x, SPOT.y), SPOT.y)
	player.set_noclip(false)
	player.teleport(ground + Vector3.UP * 0.1, 0.0)
	player.input_override = {"move": Vector2.ZERO}
	await _frames(t, 30)

	# --- model --------------------------------------------------------------------------
	var sk := rig.skeleton
	t.check(sk != null and sk.get_bone_count() >= 90, "the model has a full humanoid skeleton", "%d bones" % (sk.get_bone_count() if sk else 0))
	for b in ["pelvis", "spine_03", "head", "upperarm_l", "lowerarm_r", "hand_r", "thigh_l", "calf_r", "foot_l", "weapon_r", "sheath_l", "cloak_3_0", "eye_l"]:
		t.check(sk.find_bone(b) >= 0, "bone %s exists" % b)
	var head := rig.head_mesh
	t.check(head != null and head.find_blend_shape_by_name("eyeBlinkLeft") >= 0 and head.find_blend_shape_by_name("jawOpen") >= 0,
		"the face has blink and jaw blend shapes")
	var missing := []
	for c in REQUIRED_CLIPS:
		if not rig.player_anim.has_animation(c):
			missing.append(c)
	t.check(missing.is_empty(), "all required animation clips are present", str(missing))
	t.check(rig.player_anim.get_animation("walk").loop_mode == Animation.LOOP_LINEAR and rig.player_anim.get_animation("death").loop_mode == Animation.LOOP_NONE,
		"locomotion loops, one-shots do not")
	var tris := 0
	for mi in rig.model.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	t.check(tris < 90000, "the commander stays within the real-time budget", "%d triangles" % tris)
	var height := sk.get_bone_global_pose(sk.find_bone("head")).origin.y
	t.check(height > 1.6 and height < 1.8, "head bone at a 1.85 m man's height", "%.2f m" % height)

	# --- swords: the commander always fights with two ---------------------------------------
	t.check(rig.sword != null and rig.sword.get_parent().name == "HipSocket", "the right sword starts sheathed on the hip")
	t.check(rig.offhand_sword != null and rig.offhand_sword.get_parent().name == "OffhandHipSocket", "the left sword starts sheathed on the other hip")
	t.check(rig._hip_socket.get_node_or_null("Scabbard") != null
		and rig._offhand_hip_socket.get_node_or_null("Scabbard") != null,
		"each belt side has a scabbard")
	t.check(rig.dual_wield, "the dual-sword rule is always on")
	rig.draw_sword()
	await _frames(t, 75)
	t.check(rig.sword_drawn and rig.sword.get_parent().name == "HandSocket" and rig.offhand_sword.get_parent().name == "OffhandSocket"
		and rig.swords_in_hand() == 2, "drawing brings BOTH swords into the hands", "%d in hand" % rig.swords_in_hand())
	var grip := rig.sword.global_position
	var hand := rig.bone_socket("hand_r").global_position
	t.check(grip.distance_to(hand) < 0.16, "the right grip sits in the fist", "%.3f m from the wrist" % grip.distance_to(hand))
	var left_grip := rig.offhand_sword.global_position
	var left_hand := rig.bone_socket("hand_l").global_position
	t.check(left_grip.distance_to(left_hand) < 0.16, "the left grip sits in the left fist (mirrored grip)", "%.3f m from the wrist" % left_grip.distance_to(left_hand))
	# Mirrored grip: the left blade leaves its fist as the right one does, reflected.
	var inv := rig.model.global_transform.basis.inverse()
	var rb: Vector3 = (inv * (rig.sword.global_transform.basis * Vector3.UP)).normalized()
	var rh: Vector3 = (inv * (rig.bone_socket("hand_r").global_transform.basis * Vector3.UP)).normalized()
	var lb: Vector3 = (inv * (rig.offhand_sword.global_transform.basis * Vector3.UP)).normalized()
	var lh: Vector3 = (inv * (rig.bone_socket("hand_l").global_transform.basis * Vector3.UP)).normalized()
	t.check(absf(rb.angle_to(rh) - lb.angle_to(lh)) < 0.15, "both blades leave their fists at the same angle",
		"right %.0f, left %.0f deg" % [rad_to_deg(rb.angle_to(rh)), rad_to_deg(lb.angle_to(lh))])
	rig.sheath_sword()
	await _frames(t, 75)
	t.check(not rig.sword_drawn and rig.swords_in_hand() == 0 and rig.sword.get_parent().name == "HipSocket"
		and rig.offhand_sword.get_parent().name == "OffhandHipSocket", "sheathing returns both to their scabbards")
	rig.toggle_swords()
	await _frames(t, 75)
	t.check(rig.sword_drawn and rig.swords_in_hand() == 2 and rig.manual_draw, "the draw key draws both swords together")
	var combat_hud := main.get_node("CombatHUD") as CombatHUD
	combat_hud._update_weapon_controls()
	t.check(combat_hud._controls_panel.visible and combat_hud._controls_label.text.contains("DUAL")
		and combat_hud._controls_label.text.contains("RMB"), "dual HUD controls follow the drawn weapon state")
	var old_mouse_mode := Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	(player.get_node("Abilities") as PlayerAbilities)._unhandled_input(right_click)
	await _frames(t, 3)
	t.check(rig.is_acting(), "right mouse triggers the alternate dual-sword cut")
	Input.mouse_mode = old_mouse_mode
	# Every frame of a full four-cut combo: both blades stay in their fists (never
	# floating, never duplicated), and trails follow both blades.
	var lost := 0
	var trail_frames := 0
	for k in 4:
		await _frames(t, 12)
		Combat.request_action(player.player_id, "attack")
		for i in 40:
			await t.get_tree().physics_frame
			var bad := rig.swords_in_hand() != 2
			bad = bad or rig.sword.global_position.distance_to(rig.bone_socket("hand_r").global_position) > 0.2
			bad = bad or rig.offhand_sword.global_position.distance_to(rig.bone_socket("hand_l").global_position) > 0.2
			if bad:
				lost += 1
			if (rig.trails[0] as BladeTrail).sample_count() > 1 and (rig.trails[1] as BladeTrail).sample_count() > 1:
				trail_frames += 1
	var blades := 0
	for n in rig.find_children("*", "MeshInstance3D", true, false):
		if n.name == "Longsword" or n.name == "OffhandSword":
			blades += 1
	t.check(lost == 0 and blades == 2, "through a whole combo both swords stay attached (never floating, never duplicated)",
		"%d bad frames, %d blade meshes" % [lost, blades])
	t.check(trail_frames > 10, "both blades leave trails while cutting", "%d frames" % trail_frames)
	await _frames(t, 60)
	rig.toggle_swords()
	await _frames(t, 75)
	combat_hud._update_weapon_controls()
	t.check(not rig.sword_drawn and rig.swords_in_hand() == 0 and combat_hud._controls_label.text.contains("EXPLORE"),
		"the draw key sheathes both swords and restores exploration controls")
	rig.toggle_swords()
	await _frames(t, 5)
	rig.toggle_swords()
	await _frames(t, 170)
	t.check(not rig.sword_drawn and rig.sword.get_parent().name == "HipSocket" and rig.offhand_sword.get_parent().name == "OffhandHipSocket",
		"a sheath request during the draw queues safely behind the animation")
	Combat.request_action(player.player_id, "attack")
	await _frames(t, 4)
	t.check(rig.sword_drawn and rig.is_acting() and rig.swords_in_hand() == 2, "attacking draws both swords and plays a cut")
	await _frames(t, 50)

	# --- locomotion and air --------------------------------------------------------------
	player.input_override = {"move": Vector2.ZERO}
	await _frames(t, 40)
	t.check(float(rig.tree.get("parameters/ground/move/blend_amount")) < 0.05, "standing still plays the idle, not a running cycle")
	player.input_override = {"move": Vector2(0, 1)}
	await _frames(t, 45)
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	var gp: float = rig.tree.get("parameters/ground/gait/blend_position")
	var rate: float = rig.tree.get("parameters/ground/gait_rate/scale")
	t.check(gp > 0.2 and gp < 1.0, "the default pace blends walk into jog (a long, grounded stride)", "gait %.2f at %.1f m/s" % [gp, v])
	var stride := lerpf(rig._stride("walk"), rig._stride("jog"), gp)
	t.check(absf(rate * stride - v) < 0.25, "cycle rate x stride matches the ground speed (no foot sliding)",
		"%.2f cycles/s x %.2f m = %.2f m/s vs %.2f" % [rate, stride, rate * stride, v])
	t.check(1.0 / rate > 0.7 and 1.0 / rate < 0.95, "a natural cadence at the default pace", "%.2f s per stride cycle" % (1.0 / rate))
	player.input_override = {"move": Vector2(1, 0)}
	await _frames(t, 45)
	var travel := Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
	# The GLB faces +Z before the import correction; after the 180 degree root
	# correction its forward direction is the model's transformed +Z axis.
	var body_forward := rig.model.global_transform.basis.z.normalized()
	t.check(body_forward.dot(travel) > 0.85, "the full rig turns to face lateral travel",
		"alignment %.2f" % body_forward.dot(travel))
	if not rig.sword_drawn:
		rig.toggle_swords()
		await _frames(t, 100)
	player.input_override = {"move": Vector2(0, 1), "sprint": true}
	await _frames(t, 40)
	var sprint_layer := rig.skeleton.get_node("SprintPose") as CommanderSecondary
	t.check(player.is_sprinting and rig.sprinting and player.velocity.length() > 5.2
		and sprint_layer.weight() > 0.8, "the dual-sword sprint pose activates at sprint speed")
	t.check(player.sprint_speed >= 8.1 and player.velocity.length() > 7.7,
		"human sprint speed increases by about eleven percent")
	t.check(is_equal_approx(player.walk_speed, 4.6), "ordinary walking speed remains unchanged")
	var sg: Array = rig.gait_for_speed(player.velocity.length())
	t.check(float(sg[0]) > 1.5, "sprinting uses the run clip", "gait %.2f" % float(sg[0]))
	# The charge: torso leaning into the run, both arms extended back, both blades
	# trailing behind parallel to the run (not sideways, not into the ground).
	# Bone sockets see the final pose; create them a frame before sampling.
	for b in ["neck_01", "spine_01", "hand_l", "hand_r", "upperarm_l", "upperarm_r"]:
		rig.bone_socket(b)
	await _frames(t, 2)
	var fwd := player.forward()
	var worst := 1.0
	var lean_min := 90.0
	var lean_max := 0.0
	var arms_back := true
	var attached := true
	for i in 30:
		await t.get_tree().physics_frame
		for b in [rig.sword, rig.offhand_sword]:
			var bd: Vector3 = ((b as Node3D).global_transform.basis * Vector3.UP).normalized()
			worst = minf(worst, bd.dot(-fwd))
		var spine := (rig.bone_socket("neck_01").global_position - rig.bone_socket("spine_01").global_position).normalized()
		var lean := rad_to_deg(acos(clampf(spine.dot(Vector3.UP), -1.0, 1.0)))
		if sprint_layer.weight() > 0.99:
			lean_min = minf(lean_min, lean)
			lean_max = maxf(lean_max, lean)
		for side in ["l", "r"]:
			var hand_pos := rig.bone_socket("hand_" + side).global_position
			var sh := rig.bone_socket("upperarm_" + side).global_position
			if (hand_pos - sh).dot(fwd) > -0.25:
				arms_back = false
		if rig.swords_in_hand() != 2:
			attached = false
	t.check(worst > 0.9, "both blades trail straight back along the run", "worst alignment %.2f" % worst)
	t.check(lean_min > 22.0 and lean_max < 45.0, "the torso leans into the charge without folding over (pose fully in)",
		"%.0f-%.0f deg" % [lean_min, lean_max])
	t.check(arms_back, "both hands stay behind the shoulders (arms extended back)")
	t.check(attached, "both swords stay in the fists through the sprint cycle")
	var inverse_model: Transform3D = rig.model.global_transform.affine_inverse()
	var left_elbow := inverse_model * rig.bone_socket("lowerarm_l").global_position
	var right_elbow := inverse_model * rig.bone_socket("lowerarm_r").global_position
	t.check(maxf(absf(left_elbow.x), absf(right_elbow.x)) < 0.7,
		"sprint elbows stay within the torso's athletic silhouette",
		"left %.2f, right %.2f" % [left_elbow.x, right_elbow.x])
	player.input_override = {"move": Vector2(0, 1), "sprint": false}
	await _frames(t, 35)
	t.check(not player.is_sprinting and sprint_layer.weight() < 0.1,
		"releasing sprint fades back to ordinary locomotion")
	player.input_override = {"move": Vector2.ZERO}
	await _frames(t, 30)
	player.teleport(player.global_position + Vector3.UP * 9.0)
	await _frames(t, 20)
	t.check(rig.tree.get("parameters/mode/current_state") == "air", "falling plays the airborne loop")
	var landed_hard := false
	for i in 120:
		await t.get_tree().physics_frame
		if player.is_on_floor() and rig.is_acting():
			landed_hard = true
			break
	t.check(landed_hard, "a long fall ends in a landing animation, not a backflip")
	await _frames(t, 60)

	# --- face ---------------------------------------------------------------------------
	var blink := head.find_blend_shape_by_name("eyeBlinkLeft") if head != null else -1
	var blinked := false
	if head != null and blink >= 0:
		for i in 400:
			await t.get_tree().process_frame
			if head.get_blend_shape_value(blink) > 0.5:
				blinked = true
				break
		t.check(blinked, "the commander blinks")
		rig.expression = "angry"
		await _frames(t, 40)
		t.check(head.get_blend_shape_value(head.find_blend_shape_by_name("browDownLeft")) > 0.4, "expressions drive the brows")
		rig.expression = ""

	# --- cloak --------------------------------------------------------------------------
	var springs := sk.get_node_or_null("CloakSprings") as SpringBoneSimulator3D
	t.check(springs != null and springs.setting_count == 7, "the cloak hangs on 7 spring-bone chains")

	# --- third person only ---------------------------------------------------------------
	await _frames(t, 40)
	t.check(player.camera.cull_mask & CharacterRig.SELF_LAYER, "the follow camera shows the body")
	t.check(player.camera.position.length() > 1.5, "the camera sits back behind the shoulder", "%.2f m" % player.camera.position.length())
	t.check(not player.get_node("Head/Camera3D/ViewModel").visible, "no first-person hands are drawn")
	player.set_third_person(false)
	await _frames(t, 40)
	t.check(player.third_person and player.camera.position.length() > 1.5 and (player.camera.cull_mask & CharacterRig.SELF_LAYER),
		"there is no first-person mode: the eye view cannot be switched on")
	t.check(not InputMap.has_action("toggle_view") and not Settings.DEFAULT_BINDINGS.has("toggle_view"),
		"the first/third person toggle and its key binding are gone")

	# --- transformation -----------------------------------------------------------------
	GameState.grant_monster_for_testing(player.player_id)
	Combat.request_transform(player.player_id)
	await _frames(t, 120)
	t.check(visual.form_rig != null and not rig.visible, "transforming hides the commander behind the revealed form")
	# A reveal lasts a minimum time before the beast may return to human form.
	for i in 1200:
		if Combat.transform_status(player.player_id)["phase"] == "revealed_free":
			break
		await t.get_tree().physics_frame
	var res: Dictionary = Combat.request_revert(player.player_id)
	t.check(res["ok"], "the revealed form can revert", res.get("reason", ""))
	await _frames(t, 30)
	t.check(rig.visible and rig.scale.is_equal_approx(Vector3.ONE), "reverting brings the commander back")
	GameState.reset_match()
	await _frames(t, 10)

	# --- bots ---------------------------------------------------------------------------
	var bot: PlayerController = main.spawn_bot(ground + Vector3(4, 0.5, 0), SimBot.Role.WANDERER)
	await _frames(t, 5)
	t.check((bot.get_node("AvatarVisual") as AvatarVisual).human_rig is HumanRig, "bots keep the low-poly explorer body")
	bot.queue_free()
	main.bots.erase(bot)
	player.input_override = null


func _frames(t, n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame
