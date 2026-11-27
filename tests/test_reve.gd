extends Node
## Princess Reve: model contents (skeleton, face shapes, clips, spring chains,
## materials, triangle budget), her height against the commander, moods and
## expressions, blinking and speech, head look-at, the walk blend and the step-turn,
## and per-line expressions through the real dialogue system.

const REQUIRED_CLIPS := ["idle", "idle_talk", "walk", "walk_casual", "moon_gaze", "listen", "concern", "turn_step",
	"nod_yes", "shake_no", "lean_rail", "sit_idle", "interact"]
const SPOT := Vector2(152, -58)  ## North Meadow: open, flat ground


func run(t) -> void:
	var w: World = t.world
	var main: Node = t.main
	var player: PlayerController = main.player
	var story: StoryDirector = main.story
	var ground := Vector3(SPOT.x, w.terrain_height(SPOT.x, SPOT.y), SPOT.y)
	var npc := StoryNPC.new()
	npc.name = "ReveTest"
	w.add_child(npc)
	npc.setup("reve", "Speak with Princess Reve", 1.63)
	npc.global_position = ground
	var rig := npc.rig as ReveRig
	if not t.check(rig != null, "style \"reve\" builds the realistic ReveRig"):
		npc.queue_free()
		return
	await _frames(t, 20)

	# --- model --------------------------------------------------------------------------
	var sk := rig.skeleton
	t.check(sk != null and sk.get_bone_count() >= 150, "the model has a full skeleton with hair and skirt chains", "%d bones" % (sk.get_bone_count() if sk else 0))
	for b in ["pelvis", "spine_03", "head", "neck_01", "upperarm_l", "hand_r", "thigh_l", "calf_r", "eye_l", "eye_r",
			"hair_0_0", "hair_8_5", "skirt_0_0", "skirt_11_4"]:
		t.check(sk.find_bone(b) >= 0, "bone %s exists" % b)
	var face := rig.face_mesh
	var shapes_ok := face != null
	for sh in ["eyeBlinkLeft", "eyeBlinkRight", "jawOpen", "mouthSmileLeft", "browInnerUp", "eyeLookOutLeft", "mouthFrownRight"]:
		shapes_ok = shapes_ok and face.find_blend_shape_by_name(sh) >= 0
	t.check(shapes_ok, "the face has ARKit blend shapes for blinks, speech, smiles, brows and gaze")
	var missing := []
	for c in REQUIRED_CLIPS:
		if not rig.player_anim.has_animation(c):
			missing.append(c)
	t.check(missing.is_empty(), "all required animation clips are present", str(missing))
	t.check(rig.player_anim.get_animation("idle").loop_mode == Animation.LOOP_LINEAR and rig.player_anim.get_animation("nod_yes").loop_mode == Animation.LOOP_NONE,
		"poses loop, gestures do not")
	var tris := 0
	var mats := {}
	for mi in rig.model.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var mat := (mi as MeshInstance3D).get_surface_override_material(s)
			if mat:
				mats[mat.resource_name] = mat
	t.check(tris < 90000, "she stays within the real-time budget", "%d triangles" % tris)
	for key in ["Skin", "Hair", "DressCrepe", "BeltLeather", "EyeletMetal", "Gold", "BagLeather", "Eye"]:
		t.check(mats.has(key), "material %s is present and tuned" % key)
	if mats.has("Hair"):
		t.check((mats["Hair"] as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, "hair cards are alpha-tested (no sorting problems)")
	if mats.has("EyeletMetal") and mats.has("BeltLeather"):
		t.check((mats["EyeletMetal"] as BaseMaterial3D).metallic > 0.5 and (mats["BeltLeather"] as BaseMaterial3D).metallic < 0.1,
			"eyelets are metal, the belt leather is not")

	# --- scale ----------------------------------------------------------------------------
	var head_y := rig.bone_world("head").y - ground.y
	t.check(head_y > 1.42 and head_y < 1.56, "head bone at a 1.63 m woman's height", "%.2f m" % head_y)
	var cmd := story.commander()
	if cmd:
		var cmd_head := cmd.skeleton.get_bone_global_pose(cmd.skeleton.find_bone("head")).origin.y
		var ratio := head_y / cmd_head
		t.check(ratio > 0.82 and ratio < 0.94, "she stands about a head shorter than the 1.85 m commander", "ratio %.2f" % ratio)
	var feet := rig.bone_world("ball_l").y - ground.y
	t.check(absf(feet) < 0.06, "her feet are on the ground", "%.3f m" % feet)

	# --- springs ------------------------------------------------------------------------
	t.check(rig.spring_chain_count() == 21, "hair (9) and skirt (12) spring chains are simulated", "%d chains" % rig.spring_chain_count())
	var hair_tip_rest := rig.bone_world("hair_2_5")
	npc.rotation.y += 1.2
	await _frames(t, 4)
	npc.rotation.y -= 1.2
	await _frames(t, 40)
	var hair_tip := rig.bone_world("hair_2_5")
	t.check(hair_tip.distance_to(hair_tip_rest) < 0.12, "the hair settles back after a sharp turn", "%.3f m" % hair_tip.distance_to(hair_tip_rest))
	var pelvis := rig.bone_world("pelvis")
	var skirt_tip := rig.bone_world("skirt_0_4")
	t.check(skirt_tip.y < pelvis.y - 0.5 and skirt_tip.y > ground.y - 0.05, "the skirt hangs from the hips toward the floor", "tip %.2f m above ground" % (skirt_tip.y - ground.y))

	# --- moods, face, look ---------------------------------------------------------------
	rig.mood = "gaze"
	await _frames(t, 10)
	t.check(rig.current_pose() == "moon_gaze", "the gaze mood plays the moon-gaze pose")
	rig.mood = ""
	var saw_blink := false
	for i in 400:
		await t.get_tree().process_frame
		if rig.face_weight("eyeBlinkLeft") > 0.8:
			saw_blink = true
			break
	t.check(saw_blink, "she blinks naturally")
	rig.expression = "soft_smile"
	await _frames(t, 60)
	t.check(rig.face_weight("mouthSmileLeft") > 0.18 and rig.face_weight("mouthSmileLeft") < 0.4, "a gentle smile, not a grin", "%.2f" % rig.face_weight("mouthSmileLeft"))
	rig.expression = "concern"
	await _frames(t, 60)
	t.check(rig.face_weight("browInnerUp") > 0.3 and rig.face_weight("mouthSmileLeft") < 0.05, "concern raises the inner brows and drops the smile")
	rig.expression = ""
	rig.play("talk", 1.0)
	var jaw := 0.0
	for i in 40:
		await t.get_tree().process_frame
		jaw = maxf(jaw, rig.face_weight("jawOpen"))
	t.check(jaw > 0.1 and jaw < 0.35, "speaking moves the jaw, restrained", "max %.2f" % jaw)
	t.check(rig.current_pose() == "idle_talk", "speaking uses the restrained talking pose")
	await _frames(t, 40)
	var mark := Node3D.new()
	w.add_child(mark)
	var head_pos := rig.bone_world("head")
	var right := npc.global_transform.basis.x
	mark.global_position = head_pos + right * 2.0 + Vector3.UP * 0.1
	var fwd_before := _head_forward(rig)
	rig.look_target = mark
	await _frames(t, 120)
	var fwd_after := _head_forward(rig)
	var to_mark := (mark.global_position - head_pos).normalized()
	t.check(fwd_after.dot(to_mark) > fwd_before.dot(to_mark) + 0.25, "the head turns toward the look target", "%.2f -> %.2f" % [fwd_before.dot(to_mark), fwd_after.dot(to_mark)])
	t.check(rig.face_weight("eyeLookInRight") > 0.1 or rig.face_weight("eyeLookOutLeft") > 0.1 or rig.face_weight("eyeLookOutRight") > 0.1 or rig.face_weight("eyeLookInLeft") > 0.1,
		"the eyes follow the target too")
	rig.look_target = null
	mark.queue_free()

	# --- walking and turning ---------------------------------------------------------------
	var tw := npc.create_tween()
	tw.tween_property(npc, "global_position", ground + npc.global_transform.basis.z * -2.0, 3.0)
	await _frames(t, 60)
	var wb: float = rig.tree.get("parameters/loco/blend_amount")
	t.check(wb > 0.6, "moving her blends in the walk", "blend %.2f" % wb)
	var rate: float = rig.tree.get("parameters/walk_rate/scale")
	t.check(rate > 0.6 and rate < 1.4, "walk playback follows her speed (no foot sliding)", "rate %.2f" % rate)
	await tw.finished
	await _frames(t, 60)
	t.check(float(rig.tree.get("parameters/loco/blend_amount")) < 0.2, "she settles back to standing when she stops")
	npc.face_yaw(npc.rotation.y + PI * 0.6, 1.2)
	await _frames(t, 6)
	t.check(rig.is_acting(), "a large turn takes a small step instead of pivoting")
	await _frames(t, 80)

	# --- dialogue: per-line expressions, listening -----------------------------------------
	var old_speed := story.speed
	story.speed = 0.25
	var seen := {}
	var watch := func() -> void:
		seen[rig.expression] = true
		if rig.mood == "listen":
			seen["(listening)"] = true
	t.get_tree().process_frame.connect(watch)
	await story.play_dialogue([
		["Reve", "And if it does not?", "concern"],
		["Commander", "Then we fall back to the walls."],
		["Reve", "Then I will be there when you do.", "soft_smile"],
	], npc, npc)
	t.get_tree().process_frame.disconnect(watch)
	story.speed = old_speed
	t.check(seen.has("concern") and seen.has("soft_smile"), "her lines carry their own expressions", str(seen.keys()))
	t.check(seen.has("(listening)"), "she listens while the commander speaks")
	t.check(rig.mood == "", "listening ends with the dialogue")
	t.check(player.controls_enabled, "controls return after the dialogue")
	npc.queue_free()
	await _frames(t, 2)


func _head_forward(rig: ReveRig) -> Vector3:
	return rig.head_transform().basis.z.normalized()


func _frames(t, n: int) -> void:
	for i in n:
		await t.get_tree().process_frame
