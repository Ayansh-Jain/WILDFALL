class_name CommanderRig
extends CharacterRig
## The commander: a realistic skinned model (assets/characters/commander, built by
## Art/commander/pipeline) driven through the same API as the procedural rigs, so
## AvatarVisual, combat events and the monster transformation work unchanged.
##
## - Locomotion: the walk, jog and run clips share one normalised gait cycle (their
##   foot contacts line up at the same phase), so they blend without the legs fighting;
##   the blend picks a stride for the speed (long, grounded strides; a real cadence)
##   and the cycle rate is speed / stride, so the planted foot does not slide. Idle
##   blends in below walking pace; crouch, swim and airborne states; the body turns
##   toward the direction of travel.
## - Actions: one-shots for sword attacks (alternating light cuts, a heavier third
##   cut), block, dodge roll, hits, landings; holds for defeat and story poses.
## - Swords: the commander ALWAYS fights with two swords (rule; soldiers carry one).
##   Both hang at the belt and are drawn together - the right in the weapon socket,
##   the left in the mirror image of that grip - when combat starts, danger is near
##   or X is pressed; sheathed together after a quiet spell (unless drawn by hand).
##   A trail follows each blade during a cut.
## - Face: ARKit blend shapes for blinking, expressions and talking.
## - Cloak: spring-bone chains with leg and body colliders.

## Keep the original animated scene as the animation/skeleton authority. Blender's
## round-trip export of the unrigged replacement reduced several action tracks to
## single keys, so the replacement is used for its skinned visual mesh only.
const MODEL := preload("res://assets/characters/commander/commander.glb")
const REPLACEMENT_MODEL := preload("res://assets/characters/commander/commander_v3.glb")
const META_PATH := "res://assets/characters/commander/commander_anim.json"
## Riding clips (seated gaits, mount, dismount) authored against the horse's saddle
## (Art/horse/pipeline/08_rider.py); they replace the placeholder ride_* clips.
const RIDE_PATH := "res://assets/characters/commander/commander_ride.glb"
const RIDE_META_PATH := "res://assets/characters/commander/commander_ride.json"
const COMMANDER_SECONDARY := preload("res://scripts/characters/commander_secondary.gd")
const RIDE_GAITS := ["ride_idle", "ride_walk", "ride_trot", "ride_canter", "ride_gallop"]
## Visual comparison switch used by the commander tour; the original animated GLB
## remains available as a lower-cost, fully blend-shaped body.
static var use_replacement_body := false

## Expressions as ARKit blend-shape weights.
const EXPRESSIONS := {
	"neutral": {},
	"determined": {"browDownLeft": 0.35, "browDownRight": 0.35, "mouthPressLeft": 0.3, "mouthPressRight": 0.3,
		"eyeSquintLeft": 0.15, "eyeSquintRight": 0.15, "jawForward": 0.08},
	"angry": {"browDownLeft": 0.75, "browDownRight": 0.75, "noseSneerLeft": 0.35, "noseSneerRight": 0.35,
		"mouthFrownLeft": 0.3, "mouthFrownRight": 0.3, "eyeSquintLeft": 0.35, "eyeSquintRight": 0.35,
		"mouthPressLeft": 0.45, "mouthPressRight": 0.45},
	"hurt": {"browInnerUp": 0.65, "eyeSquintLeft": 0.6, "eyeSquintRight": 0.6, "mouthStretchLeft": 0.45,
		"mouthStretchRight": 0.45, "jawOpen": 0.15, "eyeBlinkLeft": 0.25, "eyeBlinkRight": 0.25},
	"tired": {"eyeBlinkLeft": 0.38, "eyeBlinkRight": 0.38, "browInnerUp": 0.3, "mouthFrownLeft": 0.15,
		"mouthFrownRight": 0.15, "mouthShrugLower": 0.1},
	"smirk": {"mouthSmileLeft": 0.45, "cheekSquintLeft": 0.25, "browOuterUpRight": 0.15, "mouthPressRight": 0.12,
		"eyeSquintLeft": 0.12},
	"worried": {"browInnerUp": 0.55, "mouthFrownLeft": 0.2, "mouthFrownRight": 0.2, "mouthPressLeft": 0.15,
		"mouthPressRight": 0.15},
}
## The sword stance is layered on the arms only: the library's guard is a deep
## crouch, and taking its spine would hunch him over while he walks.
const SWORD_BONES := ["clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
	"hand_l", "hand_r", "thumb_01_r", "thumb_02_r", "thumb_03_r", "index_01_r", "index_02_r", "index_03_r",
	"middle_01_r", "middle_02_r", "middle_03_r", "ring_01_r", "ring_02_r", "ring_03_r", "pinky_01_r",
	"pinky_02_r", "pinky_03_r"]

## World-space velocity of the body (set by AvatarVisual each frame).
var velocity := Vector3.ZERO
var swimming := false
## Who the eyes and head follow (dialogue partner), or null.
var look_target: Node3D
## Optional override of the automatic expression ("" = automatic).
var expression := ""
var talking := false
var stamina_ratio := 1.0
var danger := false

var model: Node3D
var skeleton: Skeleton3D
var player_anim: AnimationPlayer
var tree: AnimationTree
var head_mesh: MeshInstance3D
var sword: Node3D
var offhand_sword: Node3D
var sword_drawn := false
## The commander's rule: two swords whenever he fights. Always true (kept as a field
## for the HUD and tests); there is no single-sword state.
var dual_wield := true
## Drawn with the draw/sheath key: stays drawn until sheathed the same way.
var manual_draw := false
## Blade trails (right, left), shown while a cut plays.
var trails: Array = []
## Sword long axis in the right / left hand bone frames (for the sprint pose).
var blade_in_hand_r := Vector3.UP
var blade_in_hand_l := Vector3.UP
var _meta := {}
var _hand_socket: BoneAttachment3D
var _hip_socket: BoneAttachment3D
var _offhand_socket: BoneAttachment3D
var _offhand_hip_socket: BoneAttachment3D
var _pivot: Node3D
var _yaw := 0.0
## R02: set by the player's combat adapter while cutting or guarding, so the body squares
## up to where the blades actually hit instead of turning into a sidestep.
var face_forward := false
## P06: backward-gait latch with hysteresis, so a path hovering near the 110 degree flip
## cannot reverse the gait clip every frame.
var _backing := false
var _queue: Array = []        ## pending one-shots: [anim, speed]
var _shot_time := 0.0
var _shot_len := 0.0
var _swap_at := -1.0          ## one-shot time at which the sword changes socket
var _swap_to_hand := false
var _strike := -1
var _quiet := 0.0
var _was_grounded := true
var _air_time := 0.0
var _min_vy := 0.0
var _blink_t := 2.0
var _blink := 0.0
var _face := {}               ## current blend-shape weights
var _hurt_t := 0.0
var _anger_t := 0.0
var _hold_anim := ""
var _hold_blend := 0.0
var _talk_phase := 0.0
## Riding (set by the Rider): the body sits in the saddle facing `ride_basis` (world),
## playing the seated clip for `ride_gait` at `ride_rate`.
var riding := false
var sprinting := false
var ride_basis := Basis.IDENTITY
var ride_gait := "ride_idle"
var ride_rate := 1.0
var ride_meta := {}
var _hand_sockets := {}
var _saddle_col: SpringBoneCollisionCapsule3D
var _secondary
var _sit_idle_pending := false
var _gait := 0.0
var _move_blend := 0.0


func _build() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f:
		_meta = JSON.parse_string(f.get_as_text())
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	model = MODEL.instantiate()
	# The glTF character faces +Z; the game's rigs face -Z.
	model.rotation.y = PI
	_pivot.add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	player_anim = model.find_child("AnimationPlayer", true, false)
	if use_replacement_body:
		_replace_body_visual()
	for clip in _meta.get("clips", {}):
		if player_anim.has_animation(clip):
			player_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if _meta["clips"][clip].get("loop", false) else Animation.LOOP_NONE
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.set_meta("casts", true)
		_meshes.append(m)
		if m.name == "Longsword":
			sword = m
		if m.mesh is ArrayMesh and (m.mesh as ArrayMesh).get_blend_shape_count() > 0:
			head_mesh = m
	CommanderMaterials.apply(model)
	_load_ride_clips()
	_setup_sockets()
	_setup_lantern()
	_setup_tree()
	_setup_secondary()
	_setup_cloak()
	_setup_look()


## Replace only the rendered body. Keep the original Skeleton3D and
## AnimationPlayer intact so the existing full-length animation keys remain
## authoritative; the v3 GLB supplies only its weighted body mesh/materials.
func _replace_body_visual() -> void:
	if skeleton == null or player_anim == null:
		push_error("Commander animation scene is missing its skeleton or AnimationPlayer")
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var old_mesh := node as MeshInstance3D
		if old_mesh.name == "Longsword":
			sword = old_mesh
			continue
		old_mesh.get_parent().remove_child(old_mesh)
		old_mesh.queue_free()

	var replacement := REPLACEMENT_MODEL.instantiate()
	replacement.rotation.y = PI
	_pivot.add_child(replacement)
	var body := replacement.find_child("Body", true, false) as MeshInstance3D
	if body == null:
		push_error("Replacement Commander GLB has no Body mesh")
		replacement.queue_free()
		return
	var target_parent := skeleton.get_parent()
	body.reparent(target_parent, true)
	body.skeleton = body.get_path_to(skeleton)
	body.set_meta("casts", true)
	_meshes.append(body)
	head_mesh = null # the supplied mesh has no facial blend shapes
	replacement.queue_free()


# --- sword sockets -----------------------------------------------------------------------------

func _setup_sockets() -> void:
	_hand_socket = BoneAttachment3D.new()
	_hand_socket.name = "HandSocket"
	skeleton.add_child(_hand_socket)
	_hand_socket.bone_name = "weapon_r"
	_hip_socket = BoneAttachment3D.new()
	_hip_socket.name = "HipSocket"
	skeleton.add_child(_hip_socket)
	_hip_socket.bone_name = "pelvis"
	_offhand_socket = BoneAttachment3D.new()
	_offhand_socket.name = "OffhandSocket"
	skeleton.add_child(_offhand_socket)
	_offhand_socket.bone_name = "weapon_l" if skeleton.find_bone("weapon_l") >= 0 else "hand_l"
	_offhand_hip_socket = BoneAttachment3D.new()
	_offhand_hip_socket.name = "OffhandHipSocket"
	skeleton.add_child(_offhand_hip_socket)
	_offhand_hip_socket.bone_name = "pelvis"
	_make_scabbard(_hip_socket, -1.0)
	_make_scabbard(_offhand_hip_socket, 1.0)
	_left_grip = _mirrored_grip()
	if sword:
		# The second blade: a slightly shorter companion sword for the left fist.
		offhand_sword = sword.duplicate() as Node3D
		offhand_sword.name = "OffhandSword"
		sword.reparent(_hip_socket, false)
		sword.transform = Transform3D.IDENTITY
		_offhand_hip_socket.add_child(offhand_sword)
		offhand_sword.transform = Transform3D.IDENTITY.scaled(Vector3.ONE * 0.84)
		# Both hang hidden at the belt; the outfit already shows two scabbards.
		sword.visible = false
		offhand_sword.visible = false
		for blade in [sword, offhand_sword]:
			var trail := BladeTrail.new()
			trail.name = "Trail"
			trail.blade = blade
			trail.color = Color(1.0, 0.015, 0.025, 0.9)
			trail.length = 0.95 * (0.84 if blade == offhand_sword else 1.0)
			add_child(trail)
			trails.append(trail)
	var wr := skeleton.find_bone("weapon_r")
	if wr >= 0:
		blade_in_hand_r = (skeleton.get_bone_rest(wr).basis * Vector3.UP).normalized()
	blade_in_hand_l = (_left_grip.basis * Vector3.UP).normalized()


var _left_grip := Transform3D.IDENTITY


## The left hand has no weapon bone: hold the second sword in the mirror image of the
## right hand's grip (hand -> weapon_r rest), reflected across the body's midline. The
## skeleton's left bones are exact mirrors of the right ones, so this lands the hilt in
## the left fist with the blade leaving it the same way.
func _mirrored_grip() -> Transform3D:
	var wr := skeleton.find_bone("weapon_r")
	if wr < 0 or skeleton.find_bone("weapon_l") >= 0:
		return Transform3D.IDENTITY
	var grip := skeleton.get_bone_rest(wr)  # weapon_r relative to hand_r
	var m := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	return Transform3D(m * grip.basis * m, m * grip.origin)


func _make_scabbard(socket: BoneAttachment3D, side: float) -> void:
	# The original animated model carries its sheath socket but not a second scabbard.
	# Add a restrained leather-and-bronze sheath at each belt socket for the paired set.
	var root := Node3D.new()
	root.name = "Scabbard"
	# Hung from the belt at a rearward slant (as a sword belt carries a long blade),
	# so the tips trail behind the legs instead of hanging to the ground beside them.
	root.rotation = Vector3(deg_to_rad(30.0), 0.0, deg_to_rad(8.0) * side)
	root.position = Vector3(side * 0.22, -0.08, 0.18)
	socket.add_child(root)
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.09, 0.055, 0.035)
	leather.roughness = 0.82
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.34, 0.23, 0.11)
	bronze.metallic = 0.62
	bronze.roughness = 0.48
	for spec in [[0.0, 0.72, 0.024, leather], [-0.12, 0.035, 0.03, bronze], [-0.5, 0.035, 0.026, bronze], [-0.73, 0.04, 0.022, bronze]]:
		var mesh := CylinderMesh.new()
		mesh.top_radius = spec[2]
		mesh.bottom_radius = spec[2] * (0.82 if spec[1] > 0.1 else 1.0)
		mesh.height = spec[1]
		mesh.radial_segments = 8
		mesh.material = spec[3]
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.position.y = spec[0] - (spec[1] * 0.5 if spec[1] > 0.1 else 0.0)
		part.set_meta("casts", true)
		root.add_child(part)
		_meshes.append(part)


## A small horn lantern hangs from the belt on the right hip: the player's belt
## light (created by the view model) shines from it instead of from inside the coat.
var _lantern: Node3D


func _setup_lantern() -> void:
	var att := BoneAttachment3D.new()
	att.name = "LanternSocket"
	skeleton.add_child(att)
	att.bone_name = "pelvis"
	_lantern = Node3D.new()
	_lantern.name = "Lantern"
	att.add_child(_lantern)
	# Pelvis bone space: +Y up the spine, +Z forward; his right is -X.
	_lantern.position = Vector3(-0.2, -0.13, 0.13)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.13, 0.11, 0.09)
	metal.metallic = 0.7
	metal.roughness = 0.45
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.72, 0.42)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.62, 0.3)
	glass.emission_energy_multiplier = 2.2
	for spec in [[CylinderMesh.new(), Vector3(0, 0, 0), 0.045, 0.1, glass], [CylinderMesh.new(), Vector3(0, 0.058, 0), 0.05, 0.018, metal],
			[CylinderMesh.new(), Vector3(0, -0.058, 0), 0.05, 0.018, metal], [TorusMesh.new(), Vector3(0, 0.085, 0), 0.02, 0.0, metal]]:
		var mi := MeshInstance3D.new()
		var mesh: PrimitiveMesh = spec[0]
		if mesh is CylinderMesh:
			(mesh as CylinderMesh).top_radius = spec[2]
			(mesh as CylinderMesh).bottom_radius = spec[2]
			(mesh as CylinderMesh).height = spec[3]
			(mesh as CylinderMesh).radial_segments = 10
		else:
			(mesh as TorusMesh).inner_radius = 0.012
			(mesh as TorusMesh).outer_radius = 0.022
			mi.rotation.x = PI * 0.5
		mesh.material = spec[4]
		mi.mesh = mesh
		mi.position = spec[1]
		_lantern.add_child(mi)
		mi.set_meta("casts", false)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_meshes.append(mi)


func _carry_belt_light() -> void:
	var light := get_node_or_null("../../BeltLantern") as OmniLight3D
	var player := get_node_or_null("../..") as PlayerController
	var enabled := player == null or player.portable_lamp_on
	if _lantern:
		_lantern.visible = enabled
	if light:
		light.visible = enabled and is_visible_in_tree()
	if light and _lantern and enabled and is_visible_in_tree():
		# Just outside the glass, away from the body, so it lights the ground and the
		# lantern's surroundings rather than the inside of the coat.
		light.global_position = _lantern.global_position + global_transform.basis.z * -0.12 + Vector3.DOWN * 0.05


func set_lamp_enabled(enabled: bool) -> void:
	var player := get_node_or_null("../..") as PlayerController
	if player:
		player.portable_lamp_on = enabled
	if _lantern:
		_lantern.visible = enabled
	var light := get_node_or_null("../../BeltLantern") as OmniLight3D
	if light:
		light.visible = enabled and is_visible_in_tree()


func _put_sword(in_hand: bool) -> void:
	sword_drawn = in_hand
	if sword:
		var target: Node3D = _hand_socket if in_hand else _hip_socket
		if sword.get_parent() != target:
			if sword.get_parent():
				sword.reparent(target, false)
			else:
				target.add_child(sword)
			sword.transform = Transform3D.IDENTITY
		sword.visible = in_hand
	if offhand_sword:
		var target: Node3D = _offhand_socket if in_hand else _offhand_hip_socket
		if offhand_sword.get_parent() != target:
			if offhand_sword.get_parent():
				offhand_sword.reparent(target, false)
			else:
				target.add_child(offhand_sword)
		var grip := _left_grip if in_hand else Transform3D.IDENTITY
		offhand_sword.transform = grip.scaled_local(Vector3.ONE * 0.84)
		# Two swords, always together: never one blade in hand and one at the belt.
		offhand_sword.visible = in_hand


## The draw / sheath key: both swords come out together, or go back together.
## A press during a draw or sheath queues the opposite move behind it (no blade jumps
## sockets halfway through an animation); a press while a move is still queued cancels it.
func toggle_swords() -> void:
	_quiet = 0.0
	var active_clip: String = (tree.tree_root.get_node("act_clip") as AnimationNodeAnimation).animation if is_acting() else ""
	# Where the swords will be once what is playing now ends, and once the queue has run.
	var now_drawn := (sword_drawn and active_clip != "sword_sheath") or active_clip == "sword_draw"
	var intent := now_drawn
	for q in _queue:
		if q[0] in ["sword_draw", "sword_sheath"]:
			intent = q[0] == "sword_draw"
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i][0] in ["sword_draw", "sword_sheath"]:
			_queue.remove_at(i)
	var want := not intent
	manual_draw = want
	if want == now_drawn:
		return  # cancelling the queued move is enough
	if is_acting() or _swap_at >= 0.0:
		_shot("sword_draw" if want else "sword_sheath", 0.0, false)
		return
	_shot("sword_draw" if want else "sword_sheath")


## Old name of the draw / sheath toggle (the commander always holds two swords).
func toggle_dual_wield() -> void:
	toggle_swords()


## Swords currently in his hands (2 while drawn, 0 sheathed).
func swords_in_hand() -> int:
	var n := 0
	for b in [sword, offhand_sword]:
		if b and b.visible and b.get_parent() in [_hand_socket, _offhand_socket]:
			n += 1
	return n


# --- animation tree ---------------------------------------------------------------------------

func _clip_speed(clip: String, fallback: float) -> float:
	return float(_meta.get("clips", {}).get(clip, {}).get("speed", fallback))


func _anim_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n


func _space(points: Array) -> AnimationNodeBlendSpace1D:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 12.0
	for p in points:
		bs.add_blend_point(_anim_node(p[0]), p[1], -1, p[0])
	return bs


## Gait clips on one normalised cycle: walk, jog and run each stretched to a
## 1-second timeline (their left-foot contacts all fall near 0.1 of the cycle, see
## tools/analyze_gait.gd), blended by "gait" (0 walk, 1 jog, 2 run) and driven by one
## rate in cycles per second, so blending never puts the feet out of step. Idle has its
## own clock and fades in below walking pace.
const GAIT_CLIPS := ["walk", "jog", "run"]


func _ground_tree() -> AnimationNodeBlendTree:
	var g := AnimationNodeBlendTree.new()
	g.add_node("idle", _anim_node("idle"), Vector2(0, 0))
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = 2.0
	space.sync = true
	for i in GAIT_CLIPS.size():
		var n := _anim_node(GAIT_CLIPS[i])
		n.use_custom_timeline = true
		n.timeline_length = 1.0
		n.stretch_time_scale = true
		n.loop_mode = Animation.LOOP_LINEAR
		space.add_blend_point(n, float(i), -1, GAIT_CLIPS[i])
	g.add_node("gait", space, Vector2(0, 200))
	g.add_node("gait_rate", AnimationNodeTimeScale.new(), Vector2(200, 200))
	g.connect_node("gait_rate", 0, "gait")
	g.add_node("move", AnimationNodeBlend2.new(), Vector2(400, 100))
	g.connect_node("move", 0, "idle")
	g.connect_node("move", 1, "gait_rate")
	g.connect_node("output", 0, "move")
	return g


## Cycle stride (metres per full two-step cycle) of each gait clip at natural speed.
func _stride(clip: String) -> float:
	return _clip_speed(clip, 1.0) * _clip_length(clip)


## For a ground speed: [gait blend 0..2, cycles per second]. The stride follows a
## natural cadence (about 1.35 s per cycle walking down to 0.68 s sprinting), and the
## rate is speed / blended stride, so the planted foot stays put.
func gait_for_speed(v: float) -> Array:
	var sw := _stride("walk")
	var sj := _stride("jog")
	var sr := _stride("run")
	var g := 0.0
	if v <= 5.5:
		var cycle := lerpf(_clip_length("walk"), 0.76, clampf((v - 1.1) / 3.9, 0.0, 1.0))
		g = clampf(inverse_lerp(sw, sj, v * cycle), 0.0, 1.0)
	else:
		g = 1.0 + smoothstep(5.5, 8.5, v)
	var stride := lerpf(sw, sj, g) if g <= 1.0 else lerpf(sj, sr, g - 1.0)
	return [g, v / maxf(stride, 0.01)]


func _setup_tree() -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(player_anim)
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("ground", _ground_tree(), Vector2(0, 0))
	bt.add_node("crouch", _space([["crouch_idle", 0.0], ["crouch_walk", _clip_speed("crouch_walk", 1.2)]]), Vector2(0, 200))
	bt.add_node("swim", _space([["swim_idle", 0.0], ["swim", _clip_speed("swim", 1.3)]]), Vector2(0, 400))
	bt.add_node("air", _anim_node("fall"), Vector2(0, 600))
	# Seated gaits on horseback.
	var ride := AnimationNodeTransition.new()
	ride.xfade_time = 0.4
	for i in RIDE_GAITS.size():
		var clip: String = RIDE_GAITS[i]
		if not player_anim.has_animation(clip):
			clip = "ride_trot" if clip == "ride_canter" else "ride_idle"
		bt.add_node(RIDE_GAITS[i], _anim_node(clip), Vector2(-200, 800 + i * 100))
		ride.add_input(RIDE_GAITS[i])
	bt.add_node("ride", ride, Vector2(0, 800))
	for i in RIDE_GAITS.size():
		bt.connect_node("ride", i, RIDE_GAITS[i])
	var mode := AnimationNodeTransition.new()
	for s in ["ground", "crouch", "swim", "air", "ride"]:
		mode.add_input(s)
	mode.xfade_time = 0.22
	bt.add_node("mode", mode, Vector2(300, 200))
	for i in 5:
		bt.connect_node("mode", i, ["ground", "crouch", "swim", "air", "ride"][i])
	var loco_speed := AnimationNodeTimeScale.new()
	bt.add_node("loco_speed", loco_speed, Vector2(500, 200))
	bt.connect_node("loco_speed", 0, "mode")
	# Sword stance on the upper body while the sword is drawn.
	bt.add_node("sword_pose", _anim_node("sword_idle"), Vector2(500, 400))
	var arms := AnimationNodeBlend2.new()
	arms.filter_enabled = true
	for b in SWORD_BONES:
		# Track paths are relative to the AnimationPlayer's root node (the model).
		arms.set_filter_path(NodePath("%s:%s" % [model.get_path_to(skeleton), b]), true)
	bt.add_node("sword_arms", arms, Vector2(700, 200))
	bt.connect_node("sword_arms", 0, "loco_speed")
	bt.connect_node("sword_arms", 1, "sword_pose")
	# Held poses (defeat, story).
	bt.add_node("hold_clip", _anim_node("idle"), Vector2(700, 400))
	var hold_node := AnimationNodeBlend2.new()
	bt.add_node("hold", hold_node, Vector2(900, 200))
	bt.connect_node("hold", 0, "sword_arms")
	bt.connect_node("hold", 1, "hold_clip")
	# One-shot actions (full body).
	bt.add_node("act_clip", _anim_node("sword_light"), Vector2(900, 400))
	var act_speed := AnimationNodeTimeScale.new()
	bt.add_node("act_speed", act_speed, Vector2(1100, 400))
	bt.connect_node("act_speed", 0, "act_clip")
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.08
	shot.fadeout_time = 0.18
	bt.add_node("action", shot, Vector2(1300, 200))
	bt.connect_node("action", 0, "hold")
	bt.connect_node("action", 1, "act_speed")
	bt.connect_node("output", 0, "action")
	tree.tree_root = bt
	tree.active = true
	tree.set("parameters/mode/transition_request", "ground")


func _clip_length(clip: String) -> float:
	if player_anim and player_anim.has_animation(clip):
		return player_anim.get_animation(clip).length
	return 0.5


## Queues a one-shot clip; `duration` <= 0 plays at natural speed.
func _shot(clip: String, duration := 0.0, interrupt := true) -> void:
	if player_anim == null or not player_anim.has_animation(clip):
		return
	var natural := _clip_length(clip)
	var spd := natural / duration if duration > 0.0 else 1.0
	if interrupt:
		_queue.clear()
		_fire(clip, spd)
	else:
		_queue.append([clip, spd])


func _fire(clip: String, spd: float) -> void:
	(tree.tree_root.get_node("act_clip") as AnimationNodeAnimation).animation = clip
	tree.set("parameters/act_speed/scale", spd)
	tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_shot_time = 0.0
	_shot_len = _clip_length(clip) / maxf(spd, 0.01)
	var ev: Dictionary = _meta.get("clips", {}).get(clip, {})
	_swap_at = -1.0
	if ev.has("sword_to_hand"):
		_swap_at = float(ev["sword_to_hand"]) * _shot_len
		_swap_to_hand = true
	elif ev.has("sword_to_hip"):
		_swap_at = float(ev["sword_to_hip"]) * _shot_len
		_swap_to_hand = false


func is_acting() -> bool:
	return tree != null and bool(tree.get("parameters/action/active"))


# --- CharacterRig API -----------------------------------------------------------------------------

func play(anim: String, length: float) -> void:
	super.play(anim, length)
	_quiet = 0.0
	match anim:
		"attack":
			if riding:
				if not sword_drawn:
					_put_sword(true)
				_shot("sword_light", maxf(length, 0.55))
				return
			if not sword_drawn:
				_put_sword(true)
			_anger_t = 1.2
			# Two compact alternating cuts, a linked dual-sword combo, then a
			# heavier finisher with anticipation and recovery. AnimationTree's
			# full-body one-shot cleanly suspends locomotion during each action.
			_strike = (_strike + 1) % 4
			match _strike:
				0:
					_shot("sword_light", maxf(length * 0.6, 0.22))
					_shot("sword_light_rec", 0.55, false)
				1:
					_shot("sword_light_b", maxf(length * 0.65, 0.24))
					_shot("sword_light_b_rec", 0.55, false)
				2:
					_shot("sword_combo", 1.05)
				3:
					_shot("sword_heavy", 1.15)
		"finisher":
			if not sword_drawn:
				_put_sword(true)
			_strike = 0
			_anger_t = 1.6
			_shot("sword_heavy", maxf(length, 0.9))
		"mounted_attack":
			if not sword_drawn:
				_put_sword(true)
			_shot("sword_light", maxf(length, 0.55))
		"dodge":
			_shot("roll", 0.6)
		"ward":
			_shot("sword_block" if sword_drawn else "spell_cast", 0.7)
		"hurt":
			_hurt_t = 1.2
			if not is_acting():
				_shot(["hit_chest", "hit_head"][randi() % 2], 0.45)
		"stagger":
			_hurt_t = 1.5
			_shot("hit_knockback", 0.75)
		"transform":
			pass
		_:
			if player_anim and player_anim.has_animation(anim):
				_shot(anim, length)


func hold(anim: String, length := 1.0) -> void:
	super.hold(anim, length)
	var clip := anim
	match anim:
		"defeat":
			clip = "death"
			_queue.clear()
			tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	if player_anim and player_anim.has_animation(clip):
		(tree.tree_root.get_node("hold_clip") as AnimationNodeAnimation).animation = clip
		# Restart the held clip from its first frame.
		tree.set("parameters/hold/blend_amount", 0.0)
		_hold_anim = clip
		_hold_blend = 0.0


func release() -> void:
	super.release()
	_hold_anim = ""
	_sit_idle_pending = false


## Uses the imported, in-place sit animations through the existing action layer.
func sit_down() -> float:
	if not player_anim or not player_anim.has_animation("sit_enter") or not player_anim.has_animation("sit_idle"):
		return 0.0
	release()
	_sit_idle_pending = true
	_shot("sit_enter")
	return _clip_length("sit_enter")


func stand_up() -> float:
	_sit_idle_pending = false
	release()
	if not player_anim or not player_anim.has_animation("sit_exit"):
		return 0.0
	_shot("sit_exit")
	return _clip_length("sit_exit")


## Story beats: a looping or held pose ("study_map", "lean_window", "moon_gaze",
## "talk", "fold_arms") until stop_story(), or a one-shot ("nod_yes", "draw_sword").
func play_story(clip: String, looping := true) -> void:
	if not player_anim or not player_anim.has_animation(clip):
		return
	if looping:
		hold(clip)
	else:
		_shot(clip)


func stop_story() -> void:
	release()


## Draw / sheath; queued behind an action that is still playing.
func draw_sword() -> void:
	if not sword_drawn and not _queued("sword_draw"):
		_shot("sword_draw", 0.0, not is_acting())


func sheath_sword() -> void:
	if sword_drawn and not _queued("sword_sheath"):
		_shot("sword_sheath", 0.0, not is_acting())


func _queued(clip: String) -> bool:
	for q in _queue:
		if q[0] == clip:
			return true
	return is_acting() and (tree.tree_root.get_node("act_clip") as AnimationNodeAnimation).animation == clip


# --- per frame --------------------------------------------------------------------------------------

func _pose(delta: float) -> void:
	if tree == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if _secondary:
		_secondary.speed = speed
		_secondary.sprint_allowed = sword_drawn and dual_wield and grounded and not swimming and not crouching
		_secondary.sprint_input = sprinting
		_secondary.action_active = is_acting() or _hold_anim != ""
		_secondary.blade_in_hand_r = blade_in_hand_r
		_secondary.blade_in_hand_l = blade_in_hand_l
	if riding:
		_pose_riding(delta)
		return
	_set_saddle_collider(false)
	# Mode.
	var mode := "ground"
	if swimming:
		mode = "swim"
	elif not grounded:
		_air_time += delta
		_min_vy = minf(_min_vy, velocity.y)
		if _air_time > 0.18:
			mode = "air"
	elif crouching:
		mode = "crouch"
	if grounded and not _was_grounded and not swimming:
		_landed()
	if not grounded and _was_grounded and velocity.y > 1.0 and not swimming:
		_shot("jump_start", 0.35)
	if grounded:
		_air_time = 0.0
		_min_vy = 0.0
	_was_grounded = grounded
	if tree.get("parameters/mode/current_state") != mode:
		tree.set("parameters/mode/transition_request", mode)

	# Facing: turn the body toward the direction of travel; walk backwards facing ahead.
	var local_v := global_transform.basis.inverse() * velocity
	local_v.y = 0.0
	var target_yaw := 0.0
	var dir_sign := 1.0
	if speed > 0.6 and _hold_anim == "" and not face_forward:
		var ang := atan2(-local_v.x, -local_v.z)
		_backing = absf(ang) > deg_to_rad(100.0 if _backing else 120.0)
		if _backing:
			dir_sign = -1.0
			target_yaw = wrapf(ang + PI, -PI, PI)
		else:
			# The complete rig (torso, hips and feet) tracks lateral movement too.
			# Reducing this turn during combat left the commander looking sideways.
			target_yaw = ang
	_yaw = lerp_angle(_yaw, target_yaw, clampf(delta * 8.0, 0.0, 1.0))
	# Upright on foot: riding hands the pivot the horse's full (slope-pitched) basis.
	_pivot.rotation = Vector3(0.0, _yaw, 0.0)

	# Locomotion: gait blend and cycle rate from the ground speed (no foot sliding).
	var gait: Array = gait_for_speed(speed)
	_gait = lerpf(_gait, float(gait[0]), clampf(delta * 6.0, 0.0, 1.0))
	tree.set("parameters/ground/gait/blend_position", _gait)
	tree.set("parameters/ground/gait_rate/scale", float(gait[1]) * dir_sign if speed > 0.05 else 0.6)
	_move_blend = move_toward(_move_blend, smoothstep(0.15, 0.9, speed), delta * 5.0)
	tree.set("parameters/ground/move/blend_amount", _move_blend)
	tree.set("parameters/crouch/blend_position", speed)
	tree.set("parameters/swim/blend_position", speed)
	var nominal := _nominal_speed(speed, mode)
	var rate := 1.0 if mode == "ground" or speed < 0.3 or nominal <= 0.01 else clampf(speed / nominal, 0.55, 1.8)
	tree.set("parameters/loco_speed/scale", rate * (dir_sign if mode != "ground" else 1.0))
	_update_trails()

	# Sword stance and the quiet timer that sheathes it.
	_quiet += delta
	if danger:
		_quiet = 0.0
		if not sword_drawn and grounded:
			draw_sword()
	elif sword_drawn and not manual_draw and _quiet > 9.0 and not is_acting() and grounded and _hold_anim == "":
		sheath_sword()
	var arms_target := 1.0 if sword_drawn and mode == "ground" and speed < 5.0 else 0.0
	var arms: float = tree.get("parameters/sword_arms/blend_amount")
	tree.set("parameters/sword_arms/blend_amount", move_toward(arms, arms_target, delta * 4.0))

	# Held poses blend in and out.
	_hold_blend = move_toward(_hold_blend, 1.0 if _hold_anim != "" else 0.0, delta * 3.0)
	tree.set("parameters/hold/blend_amount", _hold_blend)

	# One-shot queue and sword socket events.
	if is_acting():
		_shot_time += delta
		if _swap_at >= 0.0 and _shot_time >= _swap_at:
			_put_sword(_swap_to_hand)
			_swap_at = -1.0
	elif not _queue.is_empty():
		var nxt: Array = _queue.pop_front()
		_fire(nxt[0], nxt[1])
	elif _sit_idle_pending:
		_sit_idle_pending = false
		hold("sit_idle")
	_face_update(delta)
	_look_update(delta)
	_carry_belt_light()


func _set_saddle_collider(on: bool) -> void:
	if _saddle_col == null:
		return
	_saddle_col.radius = 0.34 if on else 0.001
	_saddle_col.position_offset = Vector3(0.0, -0.46, -0.4) if on else Vector3(0.0, -2.0, -0.35)


func _pose_riding(delta: float) -> void:
	_set_saddle_collider(true)
	if tree.get("parameters/mode/current_state") != "ride":
		tree.set("parameters/mode/transition_request", "ride")
	if tree.get("parameters/ride/current_state") != ride_gait:
		tree.set("parameters/ride/transition_request", ride_gait)
	tree.set("parameters/loco_speed/scale", ride_rate)
	tree.set("parameters/sword_arms/blend_amount", 0.0)
	# The body sits square in the saddle, whichever way the rider looks.
	_pivot.global_basis = ride_basis
	_yaw = _pivot.rotation.y
	_was_grounded = true
	_air_time = 0.0
	_hold_blend = move_toward(_hold_blend, 1.0 if _hold_anim != "" else 0.0, delta * 3.0)
	tree.set("parameters/hold/blend_amount", _hold_blend)
	if is_acting():
		_shot_time += delta
	elif not _queue.is_empty():
		var nxt: Array = _queue.pop_front()
		_fire(nxt[0], nxt[1])
	_update_trails()
	_face_update(delta)
	_look_update(delta)
	_carry_belt_light()


const CUT_CLIPS := ["sword_light", "sword_light_b", "sword_combo", "sword_heavy", "sword_heavy_combo", "sword_dash"]


## Trails follow both blades while a cut plays (not during draws, blocks or recoveries).
func _update_trails() -> void:
	var cutting := false
	if is_acting() and sword_drawn:
		var clip: String = (tree.tree_root.get_node("act_clip") as AnimationNodeAnimation).animation
		cutting = clip in CUT_CLIPS and _shot_time >= 0.16 and _shot_time <= 0.48
	for tr in trails:
		(tr as BladeTrail).active = cutting


## Riding clips from commander_ride.glb, added to the model's own clips (same skeleton
## and node names, so the tracks apply as they are).
func _load_ride_clips() -> void:
	if not ResourceLoader.exists(RIDE_PATH):
		return
	# The riding clips and their metadata are read from disk once for every rig (a crowd of
	# soldiers used to instantiate the whole ride model each).
	if _ride_clip_cache.is_empty():
		var src: Node = (load(RIDE_PATH) as PackedScene).instantiate()
		var ap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			for n in ap.get_animation_list():
				_ride_clip_cache[n] = ap.get_animation(n).duplicate() as Animation
		src.free()
		var f := FileAccess.open(RIDE_META_PATH, FileAccess.READ)
		if f:
			_ride_meta_cache = JSON.parse_string(f.get_as_text())
	var lib := player_anim.get_animation_library("")
	if lib:
		for n in _ride_clip_cache:
			if lib.has_animation(n) and lib.get_animation(n) == _ride_clip_cache[n]:
				continue
			if lib.has_animation(n):
				lib.remove_animation(n)
			lib.add_animation(n, _ride_clip_cache[n])
	if not _ride_meta_cache.is_empty():
		ride_meta = _ride_meta_cache
		for clip in ride_meta.get("clips", {}):
			if player_anim.has_animation(clip):
				player_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if ride_meta["clips"][clip].get("loop", false) else Animation.LOOP_NONE


static var _ride_clip_cache := {}
static var _ride_meta_cache := {}


## A node that follows a bone (created on first use): reins in the fists, stirrups...
func bone_socket(bone: String) -> Node3D:
	if _hand_sockets.has(bone):
		return _hand_sockets[bone]
	var att := BoneAttachment3D.new()
	att.name = "Socket_" + bone
	skeleton.add_child(att)
	att.bone_name = bone
	var grip := Node3D.new()
	att.add_child(grip)
	_hand_sockets[bone] = grip
	return grip


func bone_world(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin


## Between the eyes (the first-person camera rides here).
func eye_world() -> Vector3:
	var i := skeleton.find_bone("head")
	var g := skeleton.global_transform * skeleton.get_bone_global_pose(i)
	# Head bone space: +Y up the skull, +Z forward.
	return g * Vector3(0.0, 0.095, 0.1)


## Plays a one-shot (mount / dismount) and returns its length in seconds (0 if missing).
func play_once(clip: String) -> float:
	if player_anim == null or not player_anim.has_animation(clip):
		return 0.0
	_shot(clip)
	return _clip_length(clip)


func _nominal_speed(speed: float, mode: String) -> float:
	match mode:
		"crouch":
			return _clip_speed("crouch_walk", 1.2)
		"swim":
			return _clip_speed("swim", 1.3)
	var pts := [[0.0, 0.0], [_clip_speed("walk", 1.45), _clip_speed("walk", 1.45)],
		[_clip_speed("jog", 3.3), _clip_speed("jog", 3.3)], [_clip_speed("run", 6.2), _clip_speed("run", 6.2)]]
	for i in range(1, pts.size()):
		if speed <= pts[i][0]:
			var t := inverse_lerp(pts[i - 1][0], pts[i][0], speed)
			return lerpf(maxf(pts[i - 1][1], pts[1][1]), pts[i][1], t)
	return pts[-1][1]


func _landed() -> void:
	var vy := _min_vy
	if _air_time < 0.25:
		return
	if vy < -13.0:
		_hurt_t = 2.0
		_shot("land_hard")
	elif vy < -8.0:
		_shot("land_hard", 0.9)
	else:
		_shot("land", 0.45)


# --- face -------------------------------------------------------------------------------------------

func _face_update(delta: float) -> void:
	if head_mesh == null:
		return
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_anger_t = maxf(0.0, _anger_t - delta)
	var key := expression
	if key == "":
		if _hold == "defeat":
			key = "hurt"
		elif _hurt_t > 0.0:
			key = "hurt"
		elif _anger_t > 0.0:
			key = "angry"
		elif sword_drawn or danger:
			key = "determined"
		elif stamina_ratio < 0.25:
			key = "tired"
		else:
			key = "neutral"
	var target: Dictionary = EXPRESSIONS.get(key, {}).duplicate()
	# Blinks every few seconds (fewer when tired eyes are already half shut).
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 1.0
		_blink_t = randf_range(2.0, 5.5)
	_blink = maxf(0.0, _blink - delta / 0.14)
	var b := sin(_blink * PI) if _blink > 0.0 else 0.0
	for side in ["Left", "Right"]:
		var k: String = "eyeBlink" + side
		target[k] = maxf(float(target.get(k, 0.0)), b)
	if talking:
		_talk_phase += delta * 11.0
		var open := 0.12 + 0.12 * sin(_talk_phase) + 0.06 * sin(_talk_phase * 2.3)
		target["jawOpen"] = maxf(float(target.get("jawOpen", 0.0)), open)
		target["mouthFunnel"] = 0.08 * maxf(0.0, sin(_talk_phase * 0.7))
	var k_rate := clampf(delta * 8.0, 0.0, 1.0)
	var names := {}
	for n in _face:
		names[n] = true
	for n in target:
		names[n] = true
	for n in names:
		var cur: float = _face.get(n, 0.0)
		var tgt: float = target.get(n, 0.0)
		var v := lerpf(cur, tgt, 1.0 if n.begins_with("eyeBlink") else k_rate)
		_face[n] = v
		var idx := head_mesh.find_blend_shape_by_name(n)
		if idx >= 0:
			head_mesh.set_blend_shape_value(idx, v)


# --- cloak and gaze -----------------------------------------------------------------------------------

func _setup_cloak() -> void:
	if skeleton == null or skeleton.find_bone("cloak_0_0") < 0:
		return
	var sim := SpringBoneSimulator3D.new()
	sim.name = "CloakSprings"
	skeleton.add_child(sim)
	# Colliders on the bones (capsules run along each bone's +Y): pelvis, back, thighs,
	# calves and the scabbard side, so the legs push the cloak aside when walking.
	for spec in [["pelvis", 0.20, 0.48, 0.08], ["spine_01", 0.19, 0.48, 0.14],
			["spine_02", 0.22, 0.62, 0.12], ["clavicle_l", 0.105, 0.34, 0.04],
			["clavicle_r", 0.105, 0.34, 0.04], ["thigh_l", 0.09, 0.52, 0.22],
			["thigh_r", 0.085, 0.5, 0.22], ["calf_l", 0.07, 0.46, 0.22], ["calf_r", 0.07, 0.46, 0.22]]:
		var cap := SpringBoneCollisionCapsule3D.new()
		cap.name = "Col_" + spec[0]
		sim.add_child(cap)
		cap.bone_name = spec[0]
		cap.radius = spec[1]
		cap.height = spec[2]
		cap.position_offset = Vector3(0, spec[3], 0)
	# The horse's back and croup under the rider (only while riding): the cloak drapes
	# over them instead of hanging through. Pelvis bone space: +Y up the spine, +Z forward.
	_saddle_col = SpringBoneCollisionCapsule3D.new()
	_saddle_col.name = "Col_horse_back"
	sim.add_child(_saddle_col)
	_saddle_col.bone_name = "pelvis"
	_saddle_col.radius = 0.001
	_saddle_col.height = 1.9
	_saddle_col.rotation_offset = Quaternion(Vector3.RIGHT, PI * 0.5)
	_saddle_col.position_offset = Vector3(0.0, -2.0, -0.35)
	var chains := 0
	while skeleton.find_bone("cloak_%d_0" % chains) >= 0:
		chains += 1
	sim.setting_count = chains
	for i in chains:
		var last := 0
		while skeleton.find_bone("cloak_%d_%d" % [i, last + 1]) >= 0:
			last += 1
		sim.set_root_bone_name(i, "cloak_%d_0" % i)
		sim.set_end_bone_name(i, "cloak_%d_%d" % [i, last])
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, 0.12)
		sim.set_radius(i, 0.035)
		# Lower stiffness and moderate drag let the cloak lag behind a sprint,
		# while the expanded body capsules keep the simulated cloth outside the rig.
		sim.set_stiffness(i, 1.65)
		sim.set_drag(i, 0.68)
		sim.set_gravity(i, 4.6)
		sim.set_enable_all_child_collisions(i, true)


func _setup_secondary() -> void:
	if skeleton == null:
		return
	_secondary = COMMANDER_SECONDARY.new()
	_secondary.name = "SprintPose"
	skeleton.add_child(_secondary)


var _look: LookAtModifier3D
var _look_infl := 0.0


## The head turns toward look_target (dialogue partners), within natural limits.
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
	_look.primary_limit_angle = deg_to_rad(110.0)
	_look.secondary_limit_angle = deg_to_rad(60.0)
	_look.duration = 0.4
	_look.influence = 0.0


func _look_update(delta: float) -> void:
	if _look == null:
		return
	var want := look_target != null and is_instance_valid(look_target)
	if want:
		_look.target_node = _look.get_path_to(look_target)
	_look_infl = move_toward(_look_infl, 0.85 if want else 0.0, delta * 2.0)
	_look.influence = _look_infl
	_look.active = _look_infl > 0.001
