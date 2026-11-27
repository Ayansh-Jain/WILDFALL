class_name CommanderSecondary
extends SkeletonModifier3D
## Post-animation layer for the commander (runs after the AnimationTree):
##
## Dual-sword sprint ("blades-back" charge): while he sprints with both swords drawn
## the torso leans hard into the run, the head counters to keep the gaze level, and
## both arms extend straight back behind the body with nearly locked elbows; each
## wrist turns so its blade trails behind, roughly parallel to the direction of
## travel and a little outward (pointing back, not sideways and not into the ground).
## The legs stay on the authored run clip, so the feet keep their contacts.
## The arm targets are solved per bone (upper arm, forearm, then the hand by the
## sword's own long axis in that hand), blended in and out by `_weight`, so the swords
## - which ride the hand bones - stay in the fists throughout.
##
## Ordinary walking/running: a slight chest-up, shoulders-set carriage.

var speed := 0.0
var sprint_allowed := false
var action_active := false
var sprint_input := false
## Sword long axis expressed in each hand bone's frame (set by CommanderRig).
var blade_in_hand_r := Vector3.UP
var blade_in_hand_l := Vector3.UP

## Skeleton space: the model faces +Z, its left is +X, up is +Y.
## Targets for the left side; the right side mirrors x.
const UPPER_ARM_DIR := Vector3(0.3, -0.6, -0.74)
const FOREARM_DIR := Vector3(0.27, -0.46, -0.85)
const BLADE_DIR := Vector3(0.2, 0.06, -0.98)
## Torso lean (pelvis -> neck, from vertical) the charge settles at, whatever lean the
## run clip brings (it already leans ~42 degrees at full speed), and the head's gaze
## (radians below horizontal).
const CHARGE_LEAN := deg_to_rad(34.0)
const GAZE_PITCH := deg_to_rad(8.0)
const LEAN_SHARE := [["spine_01", 0.35], ["spine_02", 0.35], ["spine_03", 0.3]]

## Torso lean after this layer, last frame (diagnostics).
var last_lean := 0.0
var _weight := 0.0
var _carriage := 0.0
var _bones := {}
var _cloak_roots: Array[String] = []


func _ready() -> void:
	_cache_bones()


func _cache_bones() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for bone in ["spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "clavicle_r",
			"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]:
		_bones[bone] = sk.find_bone(bone)
	var chain := 0
	while sk.find_bone("cloak_%d_0" % chain) >= 0:
		_cloak_roots.append("cloak_%d_0" % chain)
		chain += 1


func weight() -> float:
	return _weight


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.is_empty():
		_cache_bones()
	var target := 1.0 if sprint_input and sprint_allowed and speed > 5.2 and not action_active else 0.0
	# Ease into the charge quickly, and out a little more slowly.
	_weight = move_toward(_weight, target, delta * (3.2 if target > _weight else 2.6))
	_carriage = move_toward(_carriage, 1.0 if speed > 0.6 and not action_active else 0.0, delta * 2.0)
	var w := smoothstep(0.0, 1.0, _weight)
	if _carriage > 0.001 and w < 0.999:
		# Chest up, shoulders set: a soldier's carriage rather than a stroll.
		var c := _carriage * (1.0 - w)
		_rotate(sk, "spine_03", Vector3.RIGHT, -0.05 * c)
		_rotate(sk, "clavicle_l", Vector3.UP, 0.05 * c)
		_rotate(sk, "clavicle_r", Vector3.UP, -0.05 * c)
		_rotate(sk, "head", Vector3.RIGHT, 0.04 * c)
	if w < 0.001:
		return
	# Lean the torso to the charge angle, measured rather than added: the run clip's
	# own lean varies through the stride.
	var lean := _lean(sk)
	var fix := clampf(CHARGE_LEAN - lean, -0.6, 0.4) * w
	for l in LEAN_SHARE:
		_rotate(sk, l[0], Vector3.RIGHT, fix * float(l[1]))
	# Upper spine bones turn only part of the pelvis-to-neck line: take up the rest at
	# the lower back, which carries the whole chain.
	_rotate(sk, "spine_01", Vector3.RIGHT, clampf(CHARGE_LEAN - _lean(sk), -0.4, 0.3) * w)
	last_lean = _lean(sk)
	# Neck and head bring the gaze back to just below the horizon.
	var head: int = _bones.get("head", -1)
	if head >= 0:
		var look := (sk.get_bone_global_pose(head).basis * Vector3.BACK).normalized()
		var pitch := asin(clampf(-look.y, -1.0, 1.0))
		var level := clampf(GAZE_PITCH - pitch, -0.7, 0.7) * w
		_rotate(sk, "neck_01", Vector3.RIGHT, level * 0.5)
		_rotate(sk, "head", Vector3.RIGHT, level * 0.5)
	for side in ["l", "r"]:
		var mx := 1.0 if side == "l" else -1.0
		var m := Vector3(mx, 1.0, 1.0)
		_aim(sk, "upperarm_" + side, Vector3.UP, (UPPER_ARM_DIR * m).normalized(), w)
		_aim(sk, "lowerarm_" + side, Vector3.UP, (FOREARM_DIR * m).normalized(), w)
		_aim(sk, "hand_" + side, blade_in_hand_l if side == "l" else blade_in_hand_r, (BLADE_DIR * m).normalized(), w)
	# The cloak streams back in the airflow; the spring simulator adds the lag.
	for root in _cloak_roots:
		_rotate(sk, root, Vector3.RIGHT, 0.35 * w)


## Forward lean of the torso (pelvis to neck) from vertical, in radians.
func _lean(sk: Skeleton3D) -> float:
	var a: int = _bones.get("spine_01", -1)
	var b: int = _bones.get("neck_01", -1)
	if a < 0 or b < 0:
		return CHARGE_LEAN
	var v := sk.get_bone_global_pose(b).origin - sk.get_bone_global_pose(a).origin
	return atan2(v.z, v.y)


## Turns `bone` (in skeleton space) so that its local `axis` points along `want`,
## by `w` of the way, with the shortest rotation (children follow).
func _aim(sk: Skeleton3D, bone_name: String, axis: Vector3, want: Vector3, w: float) -> void:
	var bone: int = _bones.get(bone_name, -1)
	if bone < 0:
		return
	var pose := sk.get_bone_global_pose(bone)
	var cur := (pose.basis * axis).normalized()
	var to := cur.slerp(want, w).normalized()
	if cur.dot(to) > 0.99999:
		return
	var q := Quaternion(cur, to)
	pose.basis = Basis(q) * pose.basis
	sk.set_bone_global_pose(bone, pose)


func _rotate(sk: Skeleton3D, bone_name: String, axis: Vector3, angle: float) -> void:
	var bone: int = _bones.get(bone_name, -1)
	if bone < 0 or absf(angle) < 0.0001:
		return
	var pose := sk.get_bone_global_pose(bone)
	pose.basis = Basis(axis, angle) * pose.basis
	sk.set_bone_global_pose(bone, pose)
