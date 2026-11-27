class_name ReveRig
extends CharacterRig
## Princess Reve: a realistic skinned model (assets/characters/reve, built by
## Art/reve/pipeline) for story scenes. Same API as the procedural rigs
## (play / hold / mood / move_speed), so StoryNPC and StoryDirector drive her
## like any other story character.
##
## - Body: an AnimationTree crossfades slowly between composed poses (idle, moon
##   gaze, listening, concern, restrained talking, rail lean) and blends in the
##   walk by speed; small one-shots (nod, head shake, a step-turn) layer on top.
## - Face: ARKit blend shapes for expressions, blinking, small eye movements, eyes
##   that follow the look target, and speech.
## - Head: turns toward look_target (a dialogue partner or the moon) within
##   natural limits.
## - Hair and skirt: spring-bone chains (9 hair, 12 skirt) with head, shoulder,
##   body and leg colliders, so the hair swings and the skirt clears her legs.

const MODEL := preload("res://assets/characters/reve/reve.glb")
const META_PATH := "res://assets/characters/reve/reve_anim.json"
## Mood -> held clip. "" is the plain idle.
const MOOD_CLIPS := {"": "idle", "gaze": "moon_gaze", "listen": "listen", "worried": "concern",
	"concern": "concern", "talk": "idle_talk", "lean": "lean_rail"}
const POSES := ["idle", "moon_gaze", "listen", "concern", "idle_talk", "lean_rail"]
## Expressions as ARKit blend-shape weights. Restrained on purpose.
const EXPRESSIONS := {
	# Calm, composed, a little mysterious: lips gently pressed, lids slightly lowered.
	"neutral": {"mouthPressLeft": 0.1, "mouthPressRight": 0.1, "eyeSquintLeft": 0.08, "eyeSquintRight": 0.08,
		"eyeBlinkLeft": 0.06, "eyeBlinkRight": 0.06},
	"listening": {"browInnerUp": 0.12, "eyeWideLeft": 0.05, "eyeWideRight": 0.05},
	"soft_smile": {"mouthSmileLeft": 0.28, "mouthSmileRight": 0.24, "cheekSquintLeft": 0.12, "cheekSquintRight": 0.1,
		"eyeSquintLeft": 0.16, "eyeSquintRight": 0.14, "browInnerUp": 0.06},
	"smile": {"mouthSmileLeft": 0.48, "mouthSmileRight": 0.44, "cheekSquintLeft": 0.25, "cheekSquintRight": 0.22,
		"eyeSquintLeft": 0.25, "eyeSquintRight": 0.22},
	"concern": {"browInnerUp": 0.45, "browDownLeft": 0.08, "browDownRight": 0.08, "mouthFrownLeft": 0.14,
		"mouthFrownRight": 0.14, "mouthPressLeft": 0.14, "mouthPressRight": 0.14},
	"sad": {"browInnerUp": 0.6, "mouthFrownLeft": 0.28, "mouthFrownRight": 0.26, "eyeBlinkLeft": 0.18,
		"eyeBlinkRight": 0.18, "eyeLookDownLeft": 0.2, "eyeLookDownRight": 0.2, "mouthShrugLower": 0.12},
	"resolve": {"browDownLeft": 0.18, "browDownRight": 0.18, "mouthPressLeft": 0.28, "mouthPressRight": 0.28,
		"jawForward": 0.05},
	"wistful": {"browInnerUp": 0.25, "mouthSmileLeft": 0.12, "mouthSmileRight": 0.08, "eyeBlinkLeft": 0.12,
		"eyeBlinkRight": 0.12},
}

## Who the head and eyes follow (dialogue partner, the moon), or null.
var look_target: Node3D
## Expression name ("" = calm neutral).
var expression := ""
var talking := false

var model: Node3D
var skeleton: Skeleton3D
var player_anim: AnimationPlayer
var tree: AnimationTree
var face_mesh: MeshInstance3D
var springs: SpringBoneSimulator3D
var _meta := {}
var _face := {}
var _blink_t := 1.5
var _blink := 0.0
var _talk_t := 0.0
var _talk_phase := 0.0
var _sacc_t := 0.0
var _sacc := Vector2.ZERO
var _walk_blend := 0.0
var _pose_name := "idle"
var _look: LookAtModifier3D
var _look_infl := 0.0
var _head_att: BoneAttachment3D


func _build() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f:
		_meta = JSON.parse_string(f.get_as_text())
	model = MODEL.instantiate()
	# The glTF character faces +Z; the game's rigs face -Z.
	model.rotation.y = PI
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	player_anim = model.find_child("AnimationPlayer", true, false)
	for clip in _meta.get("clips", {}):
		if player_anim.has_animation(clip):
			player_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if _meta["clips"][clip].get("loop", false) else Animation.LOOP_NONE
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.set_meta("casts", true)
		_meshes.append(m)
		if m.mesh and m.find_blend_shape_by_name("eyeBlinkLeft") >= 0:
			face_mesh = m
	ReveMaterials.apply(model)
	_setup_tree()
	_setup_springs()
	_setup_look()


# --- animation tree ------------------------------------------------------------------------------------

func _anim_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


func _setup_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(player_anim)
	var bt := AnimationNodeBlendTree.new()
	var poses := AnimationNodeTransition.new()
	poses.xfade_time = 0.9          # moods change slowly: nothing theatrical
	var i := 0
	for clip in POSES:
		if not player_anim.has_animation(clip):
			continue
		bt.add_node(clip, _anim_node(clip), Vector2(0, i * 120))
		poses.add_input(clip)
		i += 1
	bt.add_node("pose", poses, Vector2(300, 0))
	i = 0
	for clip in POSES:
		if player_anim.has_animation(clip):
			bt.connect_node("pose", i, clip)
			i += 1
	bt.add_node("walk", _anim_node("walk"), Vector2(300, 400))
	var walk_rate := AnimationNodeTimeScale.new()
	bt.add_node("walk_rate", walk_rate, Vector2(500, 400))
	bt.connect_node("walk_rate", 0, "walk")
	var loco := AnimationNodeBlend2.new()
	bt.add_node("loco", loco, Vector2(700, 0))
	bt.connect_node("loco", 0, "pose")
	bt.connect_node("loco", 1, "walk_rate")
	bt.add_node("act_clip", _anim_node("nod_yes"), Vector2(700, 400))
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.3
	shot.fadeout_time = 0.4
	bt.add_node("action", shot, Vector2(900, 0))
	bt.connect_node("action", 0, "loco")
	bt.connect_node("action", 1, "act_clip")
	bt.connect_node("output", 0, "action")
	tree.tree_root = bt
	tree.active = true
	tree.set("parameters/pose/transition_request", "idle")


func clip_speed(clip: String, fallback: float) -> float:
	return float(_meta.get("clips", {}).get(clip, {}).get("speed", fallback))


func is_acting() -> bool:
	return tree != null and bool(tree.get("parameters/action/active"))


## Small one-shot gestures: "nod_yes", "shake_no", "turn_step", "interact".
func gesture(clip: String) -> void:
	if tree == null or not player_anim.has_animation(clip):
		return
	(tree.tree_root.get_node("act_clip") as AnimationNodeAnimation).animation = clip
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func current_pose() -> String:
	return _pose_name


# --- CharacterRig API ----------------------------------------------------------------------------------

func play(anim: String, length: float) -> void:
	super.play(anim, length)
	match anim:
		"talk":
			_talk_t = maxf(_talk_t, length)
		"nod", "nod_yes":
			gesture("nod_yes")
		"shake", "shake_no":
			gesture("shake_no")
		_:
			gesture(anim)


func _pose(delta: float) -> void:
	if tree == null:
		return
	_talk_t = maxf(0.0, _talk_t - delta)
	var speaking := talking or _talk_t > 0.0
	# Body pose from the mood; speaking adds the restrained talking idle unless she
	# is gazing at the sky.
	var want: String = MOOD_CLIPS.get(mood, "idle")
	if speaking and (want == "idle" or want == "listen"):
		want = "idle_talk"
	if not player_anim.has_animation(want):
		want = "idle"
	if want != _pose_name:
		_pose_name = want
		tree.set("parameters/pose/transition_request", want)
	# Walk blend and rate matched to the ground speed (no foot sliding).
	var walk_v := clip_speed("walk", 0.67)
	_walk_blend = move_toward(_walk_blend, 1.0 if move_speed > 0.08 else 0.0, delta * 3.0)
	tree.set("parameters/loco/blend_amount", _walk_blend)
	tree.set("parameters/walk_rate/scale", clampf(move_speed / walk_v, 0.6, 1.6) if move_speed > 0.08 else 1.0)
	_face_update(delta, speaking)
	_look_update(delta)


# --- face ------------------------------------------------------------------------------------------------

func _face_update(delta: float, speaking: bool) -> void:
	if face_mesh == null:
		return
	var key := expression if expression != "" else ("listening" if mood == "listen" else ("concern" if mood == "worried" else "neutral"))
	var target: Dictionary = EXPRESSIONS.get(key, {}).duplicate()
	# Blinks every few seconds; a little more often while speaking.
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 1.0
		_blink_t = randf_range(1.8, 4.0) if speaking else randf_range(2.5, 6.0)
	_blink = maxf(0.0, _blink - delta / 0.15)
	var b := sin(_blink * PI) if _blink > 0.0 else 0.0
	for side in ["Left", "Right"]:
		var k: String = "eyeBlink" + side
		target[k] = maxf(float(target.get(k, 0.0)), b)
	# Eyes: follow the look target past the head turn, otherwise small saccades.
	var eye := _sacc
	_sacc_t -= delta
	if _sacc_t <= 0.0:
		_sacc_t = randf_range(0.7, 2.6)
		_sacc = Vector2(randf_range(-0.12, 0.12), randf_range(-0.08, 0.06))
	if look_target and is_instance_valid(look_target) and _head_att:
		# The attachment carries the final pose (after the look-at turned the head).
		var head_t := _head_att.global_transform
		var local := head_t.basis.inverse() * (look_target.global_position - head_t.origin)
		# Head bone space: +Z forward (the look modifier's axis), +Y up the head, +X her left.
		var yaw := atan2(local.x, local.z)
		var pitch := atan2(local.y, Vector2(local.x, local.z).length())
		eye = Vector2(clampf(yaw / 0.6, -1.0, 1.0) * 0.55, clampf(pitch / 0.5, -1.0, 1.0) * 0.5) + _sacc * 0.3
	# Her left eye (+X) looking to her left = "out"; her right eye looking left = "in".
	target["eyeLookOutLeft"] = maxf(float(target.get("eyeLookOutLeft", 0.0)), maxf(eye.x, 0.0))
	target["eyeLookInRight"] = maxf(float(target.get("eyeLookInRight", 0.0)), maxf(eye.x, 0.0))
	target["eyeLookInLeft"] = maxf(float(target.get("eyeLookInLeft", 0.0)), maxf(-eye.x, 0.0))
	target["eyeLookOutRight"] = maxf(float(target.get("eyeLookOutRight", 0.0)), maxf(-eye.x, 0.0))
	for side in ["Left", "Right"]:
		target["eyeLookUp" + side] = maxf(float(target.get("eyeLookUp" + side, 0.0)), maxf(eye.y, 0.0))
		target["eyeLookDown" + side] = maxf(float(target.get("eyeLookDown" + side, 0.0)), maxf(-eye.y, 0.0))
	if speaking:
		_talk_phase += delta * 10.0
		var open := 0.1 + 0.1 * sin(_talk_phase) + 0.05 * sin(_talk_phase * 2.3)
		target["jawOpen"] = maxf(float(target.get("jawOpen", 0.0)), open)
		target["mouthFunnel"] = 0.06 * maxf(0.0, sin(_talk_phase * 0.7))
		target["mouthPressLeft"] = 0.0
		target["mouthPressRight"] = 0.0
	var k_rate := clampf(delta * 5.0, 0.0, 1.0)     # expressions ease in slowly
	var names := {}
	for n in _face:
		names[n] = true
	for n in target:
		names[n] = true
	for n in names:
		var cur: float = _face.get(n, 0.0)
		var tgt: float = target.get(n, 0.0)
		var fast: bool = n.begins_with("eyeBlink") or n.begins_with("eyeLook") or n == "jawOpen"
		var v := lerpf(cur, tgt, clampf(delta * 18.0, 0.0, 1.0) if fast else k_rate)
		if n.begins_with("eyeBlink"):
			v = tgt
		_face[n] = v
		var idx := face_mesh.find_blend_shape_by_name(n)
		if idx >= 0:
			face_mesh.set_blend_shape_value(idx, v)


func face_weight(shape: String) -> float:
	return float(_face.get(shape, 0.0))


# --- springs and gaze ----------------------------------------------------------------------------------------

func _chains(prefix: String) -> Array:
	var out := []
	var c := 0
	while skeleton.find_bone("%s_%d_0" % [prefix, c]) >= 0:
		var last := 0
		while skeleton.find_bone("%s_%d_%d" % [prefix, c, last + 1]) >= 0:
			last += 1
		out.append(["%s_%d_0" % [prefix, c], "%s_%d_%d" % [prefix, c, last]])
		c += 1
	return out


func _setup_springs() -> void:
	if skeleton == null:
		return
	springs = SpringBoneSimulator3D.new()
	springs.name = "HairSkirtSprings"
	skeleton.add_child(springs)
	# Capsules run along each bone's +Y. Head and neck, the torso, shoulders and
	# upper arms keep the hair on the outside; hips and legs push the skirt aside.
	for spec in [["head", 0.1, 0.22, 0.08], ["neck_01", 0.065, 0.16, 0.06], ["spine_03", 0.15, 0.36, 0.08],
			["spine_02", 0.14, 0.3, 0.05], ["clavicle_l", 0.06, 0.18, 0.07], ["clavicle_r", 0.06, 0.18, 0.07],
			["upperarm_l", 0.055, 0.3, 0.13], ["upperarm_r", 0.055, 0.3, 0.13],
			["pelvis", 0.16, 0.38, 0.06], ["thigh_l", 0.085, 0.42, 0.19], ["thigh_r", 0.085, 0.42, 0.19],
			["calf_l", 0.065, 0.42, 0.2], ["calf_r", 0.065, 0.42, 0.2]]:
		var cap := SpringBoneCollisionCapsule3D.new()
		cap.name = "Col_" + spec[0]
		springs.add_child(cap)
		cap.bone_name = spec[0]
		cap.radius = spec[1]
		cap.height = spec[2]
		cap.position_offset = Vector3(0, spec[3], 0)
	var hair := _chains("hair")
	var skirt := _chains("skirt")
	springs.setting_count = hair.size() + skirt.size()
	var i := 0
	for ch in hair:
		springs.set_root_bone_name(i, ch[0])
		springs.set_end_bone_name(i, ch[1])
		springs.set_extend_end_bone(i, true)
		springs.set_end_bone_length(i, 0.06)
		springs.set_radius(i, 0.025)
		springs.set_stiffness(i, 1.4)
		springs.set_drag(i, 0.6)
		springs.set_gravity(i, 2.5)
		springs.set_enable_all_child_collisions(i, true)
		i += 1
	for ch in skirt:
		springs.set_root_bone_name(i, ch[0])
		springs.set_end_bone_name(i, ch[1])
		springs.set_extend_end_bone(i, true)
		springs.set_end_bone_length(i, 0.05)
		springs.set_radius(i, 0.03)
		springs.set_stiffness(i, 3.0)
		springs.set_drag(i, 0.8)
		springs.set_gravity(i, 1.5)
		springs.set_enable_all_child_collisions(i, true)
		i += 1


func spring_chain_count() -> int:
	return springs.setting_count if springs else 0


func _setup_look() -> void:
	if skeleton == null or skeleton.find_bone("head") < 0:
		return
	_look = LookAtModifier3D.new()
	_look.name = "HeadLook"
	skeleton.add_child(_look)
	_look.bone_name = "head"
	_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	_look.primary_rotation_axis = Vector3.AXIS_Y
	_look.use_angle_limitation = true
	_look.symmetry_limitation = true
	_look.primary_limit_angle = deg_to_rad(80.0)
	_look.secondary_limit_angle = deg_to_rad(45.0)
	_look.duration = 0.7
	_look.influence = 0.0
	# Before the springs, so the hair follows the turned head.
	skeleton.move_child(_look, 0)
	_head_att = BoneAttachment3D.new()
	_head_att.name = "HeadSocket"
	skeleton.add_child(_head_att)
	_head_att.bone_name = "head"


## The head's final world transform (after the look-at; +Z is where she faces).
func head_transform() -> Transform3D:
	return _head_att.global_transform if _head_att else global_transform


func _look_update(delta: float) -> void:
	if _look == null:
		return
	var want := look_target != null and is_instance_valid(look_target)
	if want:
		_look.target_node = _look.get_path_to(look_target)
	_look_infl = move_toward(_look_infl, 0.75 if want else 0.0, delta * 1.2)
	_look.influence = _look_infl
	_look.active = _look_infl > 0.001


func bone_world(bone: String) -> Vector3:
	var idx := skeleton.find_bone(bone)
	if idx < 0:
		return global_position
	return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin
