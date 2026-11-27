class_name HorseSecondary
extends SkeletonModifier3D
## Small layered motions on top of the horse's clips, applied after the AnimationTree:
## - Ears: each ear turns on its own every few seconds (listening), now and then
##   flicks; with a rider they turn back towards him more often.
## - Head and neck lead into a turn (the neck bends toward the new direction).
## - Tail: a swish against flies every so often, at rest and walking.
## Rotations are about skeleton-space axes (the skeleton stands upright in the rig).

var turn := 0.0      ## rad/s, + = turning left (set by HorseRig)
var speed := 0.0
var ridden := false
## While ridden: the rider's feet (the stirrup leathers point at them).
var stirrup_targets: Array = [null, null]

var _ear := [Vector2.ZERO, Vector2.ZERO]          ## current (back/forward, out/in) angles, radians
var _ear_goal := [Vector2.ZERO, Vector2.ZERO]
var _ear_t := [1.0, 2.5]
var _lead := 0.0
var _swish_t := 4.0
var _swish := 0.0
var _swish_dir := 1.0
var _swish_age := -1.0
var _bones := {}


func _ready() -> void:
	_cache_bones()


func _cache_bones() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in ["ear_1_l", "ear_1_r", "spine_5", "spine_6", "head", "tail_1", "stirrup_l", "stirrup_r"]:
		_bones[b] = sk.find_bone(b)


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.is_empty():
		_cache_bones()
	_update(delta)
	# Ears: rotate about the skeleton's left-right axis (back/forward) and the up axis (in/out).
	for i in 2:
		var b: int = _bones.get(["ear_1_l", "ear_1_r"][i], -1)
		if b < 0:
			continue
		var side := 1.0 if i == 0 else -1.0
		var e: Vector2 = _ear[i]
		_rotate(sk, b, Vector3.RIGHT, e.x)
		_rotate(sk, b, Vector3.UP, e.y * side)
	# Lead into turns: neck and head yaw.
	for spec in [["spine_5", 0.3], ["spine_6", 0.4], ["head", 0.3]]:
		var b: int = _bones.get(spec[0], -1)
		if b >= 0:
			_rotate(sk, b, Vector3.UP, _lead * spec[1])
	var t: int = _bones.get("tail_1", -1)
	if t >= 0 and absf(_swish) > 0.001:
		_rotate(sk, t, Vector3.UP, _swish)
	# Stirrups under the rider's feet (after the springs, which swing them when empty).
	for i in 2:
		var target = stirrup_targets[i]
		var b: int = _bones.get(["stirrup_l", "stirrup_r"][i], -1)
		if b < 0 or target == null or not is_instance_valid(target):
			continue
		var g := sk.get_bone_global_pose(b)
		var want: Vector3 = sk.global_transform.affine_inverse() * (target as Node3D).global_position - g.origin
		if want.length() < 0.05:
			continue
		var cur := g.basis.y.normalized()
		var axis := cur.cross(want.normalized())
		if axis.length() > 1e-4:
			g.basis = Basis(axis.normalized(), cur.angle_to(want.normalized())) * g.basis
			sk.set_bone_global_pose(b, g)


func _update(delta: float) -> void:
	for i in 2:
		_ear_t[i] -= delta
		if _ear_t[i] <= 0.0:
			var back := ridden and randf() < 0.35
			# x: + tips the ear back, - forward; y: + turns the opening outward.
			_ear_goal[i] = Vector2(randf_range(0.35, 0.6) if back else randf_range(-0.25, 0.15), randf_range(-0.2, 0.55))
			_ear_t[i] = randf_range(1.5, 5.0)
			if randf() < 0.15:
				_ear[i] = _ear_goal[i] + Vector2(0.3, 0.0)   # a flick
		var e: Vector2 = _ear[i]
		_ear[i] = e.lerp(_ear_goal[i], clampf(delta * 6.0, 0.0, 1.0))
	var lead_goal := clampf(turn * 0.35, -0.35, 0.35) * (1.0 - clampf(speed / 12.0, 0.0, 0.6))
	_lead = lerpf(_lead, lead_goal, clampf(delta * 3.0, 0.0, 1.0))
	# Tail swish: a decaying swing to one side and back, every few seconds at a walk or slower.
	_swish_t -= delta
	if _swish_t <= 0.0 and speed < 4.0:
		_swish_t = randf_range(3.0, 9.0)
		_swish_age = 0.0
		_swish_dir = 1.0 if randf() < 0.5 else -1.0
	if _swish_age >= 0.0:
		_swish_age += delta
		_swish = 0.5 * _swish_dir * sin(_swish_age * TAU * 1.4) * exp(-_swish_age * 2.0)
		if _swish_age > 1.8:
			_swish_age = -1.0
			_swish = 0.0


func _rotate(sk: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if absf(angle) < 1e-5:
		return
	var g := sk.get_bone_global_pose(bone)
	g.basis = Basis(axis, angle) * g.basis
	sk.set_bone_global_pose(bone, g)
