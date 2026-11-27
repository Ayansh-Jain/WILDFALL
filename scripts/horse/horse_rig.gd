class_name HorseRig
extends Node3D
## The warhorse's model (assets/characters/horse, built by Art/horse/pipeline) and
## everything that makes it look alive:
## - AnimationTree: a gait transition (stand, walk, trot, canter, gallop, backing,
##   turning on the spot, grazing, dead) with each gait's playback rate matched to the
##   ground speed so the hooves do not slide, plus one-shots (startle, rear, head
##   shake, stamp).
## - HorseSecondary: ear flicks, the head leading into turns, tail swishes.
## - Spring bones: the tail, the mane and the empty stirrups swing with the motion.
## - Reins drawn each frame from the bit rings to the rider's hands, or lying over
##   the neck to the withers when nobody rides.
## - Slope: the body is pitched to the ground under the hooves (from Horse).

const MODEL := preload("res://assets/characters/horse/horse.glb")
const META_PATH := "res://assets/characters/horse/horse_anim.json"
## The seat on the saddle (lowest point of the seat surface) in skeleton space at rest,
## measured in Art/horse/pipeline (Blender (0, -0.231, 1.643) -> glTF axes).
const SEAT_REST := Vector3(0.0, 1.643, 0.231)
const STATES := ["idle", "walk", "trot", "canter", "gallop", "back", "turn", "graze", "dead"]
const STATE_CLIP := {"idle": "idle", "walk": "walk", "trot": "trot", "canter": "gallop", "gallop": "gallop",
	"back": "walk", "turn": "walk", "graze": "graze", "dead": "death"}

## Rein targets while ridden (the rider's hands), or null for reins over the neck.
var hand_l: Node3D
var hand_r: Node3D
var dead := false
var grazing := false
## Turns presentation extras off (tests, distant horses).
var lively := true

var model: Node3D
var skeleton: Skeleton3D
var player_anim: AnimationPlayer
var tree: AnimationTree
var seat: Node3D
var secondary: HorseSecondary
var springs: SpringBoneSimulator3D
var _meta := {}
var _pivot: Node3D
var _bit_l: BoneAttachment3D
var _bit_r: BoneAttachment3D
var _reins: MeshInstance3D
var _rein_mesh: ImmediateMesh
var _state := "idle"
var _extra_t := 8.0
var _still_t := 0.0
var _hoof_t := 0.0
var _hooves: AudioStreamPlayer3D
## Model height correction so the planted hooves rest on the ground (see _ground_hooves).
var _ground_fix := 0.0
const HOOF_TIPS := ["front_leg_leaf_l", "front_leg_leaf_r", "back_leg_leaf_l", "back_leg_leaf_r"]
## The hoof bones' tips sit this far above the sole at rest (measured on the model).
const TIP_ABOVE_SOLE := 0.015

@onready var horse: Horse = get_parent() as Horse


func _ready() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f:
		_meta = JSON.parse_string(f.get_as_text())
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	model = MODEL.instantiate()
	# The glTF horse faces +Z; the game faces -Z.
	model.rotation.y = PI
	_pivot.add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	player_anim = model.find_child("AnimationPlayer", true, false)
	for clip in _meta.get("clips", {}):
		if player_anim.has_animation(clip):
			player_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if _meta["clips"][clip].get("loop", false) else Animation.LOOP_NONE
	for clip in ["turn_left", "turn_right"]:
		if player_anim.has_animation(clip):
			player_anim.get_animation(clip).loop_mode = Animation.LOOP_NONE
	HorseMaterials.apply(model)
	_setup_tree()
	_setup_sockets()
	_setup_secondary()
	_setup_reins()
	_hooves = AudioStreamPlayer3D.new()
	_hooves.name = "Hooves"
	_hooves.unit_size = 6.0
	_hooves.max_distance = 60.0
	add_child(_hooves)


# --- animation tree --------------------------------------------------------------------------------

func clip_speed(clip: String, fallback: float) -> float:
	return float(_meta.get("clips", {}).get(clip, {}).get("speed", fallback))


func _anim(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


func _setup_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(player_anim)
	var bt := AnimationNodeBlendTree.new()
	var gait := AnimationNodeTransition.new()
	gait.xfade_time = 0.35
	for i in STATES.size():
		var s: String = STATES[i]
		bt.add_node(s, _anim(STATE_CLIP[s]), Vector2(0, i * 120))
		var ts := AnimationNodeTimeScale.new()
		bt.add_node(s + "_ts", ts, Vector2(200, i * 120))
		bt.connect_node(s + "_ts", 0, s)
		gait.add_input(s)
	bt.add_node("gait", gait, Vector2(450, 300))
	for i in STATES.size():
		bt.connect_node("gait", i, STATES[i] + "_ts")
	bt.add_node("act_clip", _anim("startle"), Vector2(450, 700))
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.25
	shot.fadeout_time = 0.35
	bt.add_node("act", shot, Vector2(700, 300))
	bt.connect_node("act", 0, "gait")
	bt.connect_node("act", 1, "act_clip")
	bt.connect_node("output", 0, "act")
	tree.tree_root = bt
	tree.active = true
	tree.set("parameters/gait/transition_request", "idle")


## One-shot: "startle", "rear", "head_shake", "stamp".
func play(clip: String) -> void:
	if not player_anim.has_animation(clip) or dead:
		return
	(tree.tree_root.get_node("act_clip") as AnimationNodeAnimation).animation = clip
	tree.set("parameters/act/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_extra_t = randf_range(8.0, 16.0)


func is_acting() -> bool:
	return bool(tree.get("parameters/act/active"))


func current_state() -> String:
	return _state


func _set_state(s: String) -> void:
	if s != _state:
		_state = s
		tree.set("parameters/gait/transition_request", s)


# --- sockets ---------------------------------------------------------------------------------------

func _setup_sockets() -> void:
	var att := BoneAttachment3D.new()
	att.name = "SaddleSocket"
	skeleton.add_child(att)
	att.bone_name = "saddle"
	seat = Node3D.new()
	seat.name = "Seat"
	att.add_child(seat)
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone("saddle"))
	# Facing the horse's (game) forward; the model is turned half round inside the rig.
	seat.transform = rest.affine_inverse() * Transform3D(Basis(Vector3.UP, PI), SEAT_REST)
	_bit_l = _socket("bit_l")
	_bit_r = _socket("bit_r")


func _socket(bone: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = bone.capitalize().replace(" ", "") + "Socket"
	skeleton.add_child(att)
	att.bone_name = bone
	return att


## World position of a bone (for the rider: stirrups, the seat...).
func bone_world(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin if i >= 0 else global_position


# --- secondary motion ------------------------------------------------------------------------------

func _setup_secondary() -> void:
	# Springs first, then the layered motions (which also hold the stirrups under a rider).
	springs = SpringBoneSimulator3D.new()
	springs.name = "Springs"
	skeleton.add_child(springs)
	secondary = HorseSecondary.new()
	secondary.name = "Secondary"
	skeleton.add_child(secondary)
	var chains: Array = []   # [root, end, extend length, stiffness, drag, gravity, radius]
	chains.append(["tail_2", "tail_leaf", 0.12, 0.9, 0.45, 6.0, 0.05])
	for k in 5:
		if skeleton.find_bone("mane_%d_0" % k) >= 0:
			chains.append(["mane_%d_0" % k, "mane_%d_1" % k, 0.04, 2.6, 0.6, 2.0, 0.03])
	for s in ["stirrup_l", "stirrup_r"]:
		chains.append([s, s, 0.0, 4.0, 0.75, 5.0, 0.03])
	springs.setting_count = chains.size()
	for i in chains.size():
		var c: Array = chains[i]
		springs.set_root_bone_name(i, c[0])
		springs.set_end_bone_name(i, c[1])
		springs.set_extend_end_bone(i, c[2] > 0.0)
		if c[2] > 0.0:
			springs.set_end_bone_length(i, c[2])
		springs.set_stiffness(i, c[3])
		springs.set_drag(i, c[4])
		springs.set_gravity(i, c[5])
		springs.set_radius(i, c[6])
		springs.set_enable_all_child_collisions(i, true)
	# The hind legs and quarters push the tail aside; the barrel keeps the stirrups out.
	for spec in [["back_leg_upper_l", 0.11, 0.5, 0.2], ["back_leg_upper_r", 0.11, 0.5, 0.2],
			["back_leg_lower_l", 0.08, 0.5, 0.2], ["back_leg_lower_r", 0.08, 0.5, 0.2], ["hips", 0.2, 0.6, 0.0],
			["spine_2", 0.3, 0.8, 0.15]]:
		var cap := SpringBoneCollisionCapsule3D.new()
		cap.name = "Col_" + spec[0]
		springs.add_child(cap)
		cap.bone_name = spec[0]
		cap.radius = spec[1]
		cap.height = spec[2]
		cap.position_offset = Vector3(0, spec[3], 0)


# --- reins -----------------------------------------------------------------------------------------

func _setup_reins() -> void:
	_rein_mesh = ImmediateMesh.new()
	_reins = MeshInstance3D.new()
	_reins.name = "Reins"
	_reins.mesh = _rein_mesh
	_reins.top_level = true
	_reins.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_reins.visibility_range_end = 60.0
	add_child(_reins)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.07, 0.045)
	mat.roughness = 0.62
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_reins.material_override = mat


func _draw_reins() -> void:
	_rein_mesh.clear_surfaces()
	if not _reins.is_visible_in_tree():
		return
	_reins.global_transform = Transform3D.IDENTITY
	var bl := _bit_l.global_position
	var br := _bit_r.global_position
	var paths: Array = []
	if hand_l and hand_r and is_instance_valid(hand_l) and is_instance_valid(hand_r):
		# To the rider's fists, a little slack between.
		for pair in [[bl, hand_l.global_position], [br, hand_r.global_position]]:
			var a: Vector3 = pair[0]
			var b: Vector3 = pair[1]
			var mid := a.lerp(b, 0.5) + Vector3.DOWN * (0.04 + 0.02 * a.distance_to(b))
			paths.append(_bezier(a, mid, b, 14))
	else:
		# Lying over the neck: down each side of the neck, meeting at the withers.
		var neck := bone_world("spine_6")
		var withers := bone_world("spine_4") + Vector3.UP * 0.2
		var side := global_transform.basis.x
		for s in [-1.0, 1.0]:
			var a: Vector3 = bl if s < 0 else br
			var m1: Vector3 = neck.lerp(withers, 0.25) + side * s * 0.15 + Vector3.DOWN * 0.08
			var path := _bezier(a, a.lerp(m1, 0.6) + Vector3.DOWN * 0.06, m1, 7)
			path.append_array(_bezier(m1, m1.lerp(withers, 0.5) + side * s * 0.1 + Vector3.DOWN * 0.03, withers, 8).slice(1))
			paths.append(path)
	_rein_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in paths:
		_strap(p, 0.018, 0.006)
	_rein_mesh.surface_end()


func _bezier(a: Vector3, c: Vector3, b: Vector3, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


func _strap(path: PackedVector3Array, w: float, h: float) -> void:
	var prev: Array = []
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side := t.cross(Vector3.UP)
		if side.length() < 0.2:
			side = t.cross(Vector3.FORWARD)
		side = side.normalized() * w * 0.5
		var up := side.cross(t).normalized() * h * 0.5
		var ring: Array[Vector3] = [path[i] - side - up, path[i] + side - up, path[i] + side + up, path[i] - side + up]
		if not prev.is_empty():
			for k in 4:
				var k2 := (k + 1) % 4
				var nrm: Vector3 = (ring[k] + ring[k2] - path[i] * 2.0).normalized()
				for v in [prev[k], prev[k2], ring[k2], prev[k], ring[k2], ring[k]]:
					_rein_mesh.surface_set_normal(nrm)
					_rein_mesh.surface_add_vertex(v)
		prev = ring


# --- per frame ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if horse == null or tree == null:
		return
	var spd := horse.speed
	var g := horse.gait
	var s := "idle"
	var rate := 1.0
	if dead:
		s = "dead"
	else:
		match g:
			Horse.Gait.WALK:
				s = "walk"
				rate = clampf(spd / clip_speed("walk", 1.715), 0.55, 1.45)
			Horse.Gait.TROT:
				s = "trot"
				rate = clampf(spd / clip_speed("trot", 3.008), 0.7, 1.35)
			Horse.Gait.CANTER:
				s = "canter"
				rate = clampf(spd / clip_speed("gallop", 8.396), 0.62, 0.92)
			Horse.Gait.GALLOP:
				s = "gallop"
				rate = clampf(spd / clip_speed("gallop", 8.396), 0.85, 1.2)
			Horse.Gait.BACK:
				s = "back"
				rate = -clampf(absf(spd) / clip_speed("walk", 1.715), 0.4, 0.8)
			_:
				if absf(horse.turn_rate) > 0.25:
					s = "turn"
					rate = 0.75
				elif grazing:
					s = "graze"
	_set_state(s)
	tree.set("parameters/%s_ts/scale" % s, rate)
	if s == "idle" or s == "graze":
		_still_t += delta
	else:
		_still_t = 0.0
	# Unridden, a standing horse grazes now and then; a rider (or a stop) lifts its head.
	if lively and not dead:
		if horse.rider == null and _still_t > 14.0 and not grazing and randf() < delta * 0.08:
			grazing = true
		if grazing and (horse.rider != null or g != Horse.Gait.STAND or randf() < delta * 0.06):
			grazing = false
		_extra_t -= delta
		if _extra_t <= 0.0 and s == "idle" and not is_acting():
			play("head_shake" if randf() < 0.6 else "stamp")
	# Slope and uneven ground, then the hooves onto the ground under them.
	_pivot.rotation.x = horse.slope_pitch
	_ground_hooves(delta, s)
	_pivot.position.y = -horse.body_drop + _ground_fix
	secondary.turn = horse.turn_rate
	secondary.speed = spd
	secondary.ridden = horse.rider != null
	_hoofbeats(delta, s, rate)
	_draw_reins()


## With a hoof planted (standing, walking, trotting, turning, backing), lowers or raises
## the model until the lowest hoof rests on the ground under it; held through the
## canter and gallop, whose suspension phases have no hoof down.
func _ground_hooves(delta: float, s: String) -> void:
	if not (s in ["idle", "walk", "trot", "back", "turn", "graze"]) or skeleton == null:
		return
	var space := get_world_3d().direct_space_state
	var lowest := INF
	for b in HOOF_TIPS:
		var p := bone_world(b)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.8, Layers.WORLD, [horse.get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			lowest = minf(lowest, p.y - float(hit["position"].y))
	if lowest == INF:
		return
	var err := lowest - TIP_ABOVE_SOLE
	_ground_fix = clampf(_ground_fix - err * clampf(delta * 5.0, 0.0, 1.0), -0.15, 0.1)


## Hoof falls per stride: four for the walk and gallop, two for the trot, three at the canter.
func _hoofbeats(delta: float, s: String, rate: float) -> void:
	var beats := {"walk": 4, "trot": 2, "canter": 3, "gallop": 4, "back": 2, "turn": 4}
	if not beats.has(s):
		return
	var clip: String = STATE_CLIP[s]
	var clip_length: float = player_anim.get_animation(clip).length
	_hoof_t += delta * absf(rate)
	var beat_length := clip_length / float(beats[s])
	if _hoof_t >= beat_length:
		_hoof_t = fmod(_hoof_t, beat_length)
		var lib := AudioLib.get_instance()
		if lib == null:
			return
		var wet := horse.water_depth_here() > 0.1
		var hoof_sound := "horse_hoof_water" if wet else "horse_hoof_%d" % randi_range(1, 3)
		_hooves.stream = lib.get_stream(hoof_sound)
		_hooves.volume_db = {"walk": -13.0, "trot": -9.0, "canter": -5.0, "gallop": -2.0}.get(s, -14.0)
		_hooves.pitch_scale = randf_range(0.92, 1.06)
		_hooves.play()
