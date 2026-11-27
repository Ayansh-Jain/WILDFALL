class_name Rider
extends Node
## Mounting, riding and dismounting the commander's horse. Lives on the player
## (PlayerController stays the one controller: while mounted it only looks around,
## and its movement input steers the horse).
##
## Mount (interact with the horse): the commander steps to the stirrup on the
## horse's near (left) side, the horse stands still, the mount clip swings him up and
## he settles into the saddle. Riding: his hips are held on the seat (so the saddle's
## motion carries him), his body faces the horse's way whatever the camera does, the
## first-person view rides at his eyes, the reins run from the bit to his fists and
## his seated clip follows the horse's gait. Dismount (interact again, below a walk):
## he swings off the near side and stands beside the shoulder.
##
## Controls while mounted: forward/back = go/slow and back up, left/right = steer,
## sprint = canter, held = gallop, crouch = toggle walk / trot as the cruising gait,
## interact = dismount.

signal transition_started(mounting: bool)
signal mounted(horse: Horse)
signal dismounted(horse: Horse)

enum State { NONE, MOUNTING, RIDING, DISMOUNTING }

## Where the commander stands to mount: near (left) side, at the stirrup, in the
## horse's frame (game axes: -X is the horse's left, -Z its front).
const MOUNT_SPOT := Vector3(-0.68, 0.0, -0.32)
const PELVIS_ABOVE_SEAT := 0.1
const ALIGN_TIME := 0.45

var state: int = State.NONE
var horse: Horse
var _t := 0.0
var _len := 0.0
var _from := Transform3D()
var _crouch_was := false
var _idle_look := 0.0
var _hand_l: Node3D
var _hand_r: Node3D
## Set when the authored mount/dismount clip cannot be used (blocked near side).
var _lift := false
var _dismount_spot := Vector3.ZERO

@onready var player: PlayerController = get_parent()


func _ready() -> void:
	# After the horse has moved and its skeleton is posed.
	process_priority = 100
	process_physics_priority = 100


func is_riding() -> bool:
	return state == State.RIDING


func is_busy() -> bool:
	return state != State.NONE


func commander() -> CommanderRig:
	var av := player.get_node_or_null("AvatarVisual") as AvatarVisual
	return av.human_rig as CommanderRig if av else null


## Why mounting is refused right now ("" = allowed).
func mount_refusal(h: Horse) -> String:
	if state != State.NONE:
		return "busy"
	if player.is_defeated:
		return "defeated"
	if GameState.is_revealed(player.player_id) or Combat.is_transforming(player.player_id):
		return "The horse shies away from the beast."
	if h.rider != null:
		return "taken"
	if absf(h.speed) > 1.0:
		return "The horse is moving."
	return ""


func mount(h: Horse) -> bool:
	var why := mount_refusal(h)
	if why != "":
		_toast(why if why.length() > 10 else "")
		return false
	horse = h
	var near_side := _ground(h.global_transform * MOUNT_SPOT)
	_lift = SafeSpot.standing(_space(), near_side, h.global_position + Vector3.UP * 1.2, h.water_level, _excluded(h)) == Vector3.INF
	transition_started.emit(true)
	state = State.MOUNTING
	_t = 0.0
	_from = player.global_transform
	player.riding = true
	player.velocity = Vector3.ZERO
	player.collision.disabled = true
	horse.set_rider(player)
	horse.drive = {}
	var rig := horse.get_node("Rig") as HorseRig
	rig.grazing = false
	var c := commander()
	_len = 0.0
	if c:
		c.riding = false
	return true


func dismount() -> bool:
	if state != State.RIDING:
		return false
	if absf(horse.speed) > 1.0:
		_toast("Slow to a walk to dismount.")
		return false
	var found := find_dismount_spot()
	if found.is_empty():
		_toast("There is no room to dismount here.")
		return false
	_dismount_spot = found["position"]
	_lift = not found["near_side"]
	transition_started.emit(false)
	state = State.DISMOUNTING
	_t = 0.0
	horse.drive = {}
	var c := commander()
	# The authored clip swings down the near side only.
	_len = c.play_once("dismount") if c and not _lift else 0.0
	if c:
		c.riding = false
	_release_reins()
	return true


## Immediately off the horse (defeat, teleports, story cuts), standing beside it.
func force_dismount() -> void:
	if state == State.NONE:
		return
	var h := horse if is_instance_valid(horse) else null
	var spot := Vector3.INF
	if h:
		var found := find_dismount_spot()
		# Nowhere clear: stand where the horse is (known to be inside the world).
		spot = found["position"] if not found.is_empty() else h.global_position + Vector3.UP * 0.05
	_finish_dismount()
	if spot != Vector3.INF:
		player.global_position = spot


## A clear place to step down to: the near side first, then the other side, then behind
## and ahead. Returns {position, near_side} or {} when the horse is boxed in.
func find_dismount_spot() -> Dictionary:
	if horse == null or not is_instance_valid(horse):
		return {}
	var options: Array[Vector3] = [MOUNT_SPOT, Vector3(0.9, 0.0, -0.32), Vector3(-1.5, 0.0, 0.3), Vector3(1.5, 0.0, 0.3), Vector3(0.0, 0.0, 2.3), Vector3(0.0, 0.0, -2.6)]
	var from := horse.global_position + Vector3.UP * 1.2
	for i in options.size():
		var want := horse.global_transform * options[i]
		var g := SafeSpot.standing(_space(), want, from, horse.water_level, _excluded(horse))
		if g != Vector3.INF and absf(g.y - horse.global_position.y) < 1.2:
			return {"position": g, "near_side": i == 0}
	return {}


func _space() -> PhysicsDirectSpaceState3D:
	return player.get_world_3d().direct_space_state


func _excluded(h: Horse) -> Array[RID]:
	return [player.get_rid(), h.get_rid()]


func _unhandled_input(event: InputEvent) -> void:
	if not player.controls_enabled or state != State.RIDING or not player.is_local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			or player.locks.blocks(ControlLock.PAUSE):
		return
	if event is InputEventMouseMotion:
		_idle_look = 0.0
	if event.is_action_pressed("attack") and not event.is_echo() and not player.locks.blocks(ControlLock.COMBAT):
		Combat.request_mounted_attack(player.player_id)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and not event.is_echo() and not player.locks.blocks(ControlLock.MOUNT):
		dismount()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	match state:
		State.MOUNTING:
			_mounting(delta)
		State.RIDING:
			_riding(delta)
		State.DISMOUNTING:
			_dismounting(delta)


func _physics_process(_delta: float) -> void:
	if state != State.NONE:
		# Defeat or a vanished horse interrupts any stage of mounting or riding.
		if player.is_defeated:
			force_dismount()
			return
		if not is_instance_valid(horse):
			_finish_dismount()
			return
	if state == State.RIDING:
		var inp := player.read_input()
		var crouch: bool = inp.get("crouch", false)
		if crouch and not _crouch_was:
			horse.cruise = Horse.Gait.WALK if horse.cruise == Horse.Gait.TROT else Horse.Gait.TROT
			_toast("Walk" if horse.cruise == Horse.Gait.WALK else "Trot", 1.2)
		_crouch_was = crouch
		horse.drive = {"move": inp.get("move", Vector2.ZERO), "sprint": inp.get("sprint", false)}
	elif state != State.NONE and horse:
		horse.drive = {}


# --- mounting ---------------------------------------------------------------------------------------

func _mounting(delta: float) -> void:
	_t += delta
	var c := commander()
	var spot := horse.global_transform * MOUNT_SPOT
	spot = _ground(spot)
	# Facing the saddle (the horse's right, +X in its frame).
	var face := Basis(Vector3.UP, horse.global_rotation.y - PI * 0.5)
	if _t <= ALIGN_TIME:
		# Step to the stirrup.
		var k := smoothstep(0.0, 1.0, _t / ALIGN_TIME)
		player.global_position = _from.origin.lerp(spot, k)
		if c:
			c.riding = false
			c._pivot.global_basis = Basis(Quaternion(c._pivot.global_basis.orthonormalized()).slerp(Quaternion(face), k))
		return
	if _len == 0.0:
		_len = c.play_once("mount") if c and not _lift else 0.0
		if _len == 0.0:
			_len = 1.2   # no clip: a plain lift into the saddle
	var p := clampf((_t - ALIGN_TIME) / _len, 0.0, 1.0)
	if c and not _lift and c.player_anim.has_animation("mount"):
		# The clip carries the body from the ground into the saddle and turns it to face
		# forward, all in the frame of the spot (facing the horse); its last frame is the
		# seated pose, so the hand-over to the seat does not jump.
		player.global_position = spot
		c._pivot.global_basis = face
	else:
		var seat := _seat_target()
		player.global_position = spot.lerp(seat, smoothstep(0.0, 1.0, p)) + Vector3.UP * sin(p * PI) * 0.35
		if c:
			c._pivot.global_basis = face.slerp(_seat_basis(), smoothstep(0.2, 1.0, p))
	if p >= 1.0:
		state = State.RIDING
		_grip_reins()
		if c:
			c.riding = true
		mounted.emit(horse)


# --- riding -----------------------------------------------------------------------------------------

func _riding(delta: float) -> void:
	var c := commander()
	var rig := horse.get_node("Rig") as HorseRig
	if c:
		c.riding = true
		c.ride_basis = _seat_basis()
		var gait: String = {Horse.Gait.WALK: "ride_walk", Horse.Gait.TROT: "ride_trot", Horse.Gait.CANTER: "ride_canter",
			Horse.Gait.GALLOP: "ride_gallop", Horse.Gait.BACK: "ride_walk"}.get(horse.gait, "ride_idle")
		c.ride_gait = gait
		# The seated clips have the horse's stride lengths: play them at the horse's rate.
		var st := rig.current_state()
		c.ride_rate = absf(float(rig.tree.get("parameters/%s_ts/scale" % st))) if st in ["walk", "trot", "canter", "gallop", "back"] else 1.0
	player.global_position = _seat_target()
	if c:
		player.ride_eye = player.to_local(c.eye_world())
	# With nobody steering the view, the camera drifts back behind the horse's head.
	_idle_look += delta
	if absf(horse.speed) > 2.0 and _idle_look > 1.5:
		var target := horse.global_rotation.y
		player.rotation.y = lerp_angle(player.rotation.y, target, clampf(delta * 1.2, 0.0, 1.0))


## Where the player's origin goes so that the commander's hips sit on the saddle.
func _seat_target() -> Vector3:
	var rig := horse.get_node("Rig") as HorseRig
	var seat := rig.seat.global_transform
	var want_pelvis := seat.origin + seat.basis.y * PELVIS_ABOVE_SEAT
	var c := commander()
	if c == null:
		return seat.origin
	var pelvis := c.bone_world("pelvis")
	return player.global_position + (want_pelvis - pelvis)


func _seat_basis() -> Basis:
	var rig := horse.get_node("Rig") as HorseRig
	return rig.seat.global_transform.basis.orthonormalized()


func _grip_reins() -> void:
	var c := commander()
	if c == null:
		return
	_hand_l = c.bone_socket("hand_l")
	_hand_r = c.bone_socket("hand_r")
	# The reins leave the fist on the thumb side, a few centimetres from the wrist.
	_hand_l.position = Vector3(0.0, 0.08, 0.03)
	_hand_r.position = Vector3(0.0, 0.08, 0.03)
	var rig := horse.get_node("Rig") as HorseRig
	rig.hand_l = _hand_l
	rig.hand_r = _hand_r
	rig.secondary.stirrup_targets = [c.bone_socket("ball_l"), c.bone_socket("ball_r")]


func _release_reins() -> void:
	var rig := horse.get_node("Rig") as HorseRig
	rig.hand_l = null
	rig.hand_r = null
	rig.secondary.stirrup_targets = [null, null]


# --- dismounting ------------------------------------------------------------------------------------

func _dismounting(delta: float) -> void:
	_t += delta
	var c := commander()
	var spot := _dismount_spot
	var face := Basis(Vector3.UP, horse.global_rotation.y - PI * 0.5)
	if _len > 0.0:
		# The clip swings him down from the saddle to the spot beside the horse.
		var p := clampf(_t / _len, 0.0, 1.0)
		player.global_position = spot
		if c:
			c._pivot.global_basis = face
		if p >= 1.0:
			_finish_dismount()
	else:
		var p := clampf(_t / 0.9, 0.0, 1.0)
		var seat := _seat_target()
		player.global_position = seat.lerp(spot, smoothstep(0.0, 1.0, p)) + Vector3.UP * sin(p * PI) * 0.25
		if c:
			c._pivot.global_basis = _seat_basis().slerp(face, smoothstep(0.0, 0.6, p))
		if p >= 1.0:
			_finish_dismount()


func _finish_dismount() -> void:
	var h: Horse = horse if is_instance_valid(horse) else null
	var c := commander()
	if c:
		c.riding = false
	if h:
		h.set_rider(null)
		h.drive = null
		_release_reins()
	player.riding = false
	player.collision.disabled = false
	player.velocity = Vector3.ZERO
	state = State.NONE
	horse = null
	dismounted.emit(h)


# --- helpers ----------------------------------------------------------------------------------------

func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 3.0, Layers.WORLD)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else p


func _toast(text: String, seconds := 2.5) -> void:
	if text == "":
		return
	var hud := player.get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast(text, seconds)
