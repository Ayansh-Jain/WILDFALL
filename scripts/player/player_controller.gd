class_name PlayerController
extends CharacterBody3D
## Third-person avatar: mouse look, walk/sprint/crouch/jump, wading and
## swimming, small step-up for rubble, footsteps, and the follow camera.
## Phase 2 adds forms (human / revealed monster), stamina, dash, leap,
## knockback, status effects, defeat camera and remote (non-local) avatars.
##
## Movement is read through _read_input(), which uses either the keyboard or
## `input_override` (a Dictionary set by tests, bots or a future network layer).
## Combat rules live in the Combat authority; this script only moves the body.

signal fell_out_of_world
## P06: emitted when the coarse locomotion state changes (see `Loco`, `locomotion_state()`).
signal locomotion_changed(new_state: int, old_state: int)

## P06: coarse, read-only locomotion state for the rig, camera (P07), combat (P08-P10),
## horse (P13) and cinematics (P37). The controller is the single writer.
enum Loco { IDLE, WALK, RUN, SPRINT, CROUCH, SWIM, AIR, DASH, MOUNTED, SITTING, LOCKED, DEAD }

@export_group("Identity")
@export var display_name := "Player"
## The player on this machine (camera, HUD, input). Bots and future peers are not local.
@export var is_local := true
@export var is_bot := false
## Registers with GameState / Combat on ready. Off only for preview scenes.
@export var auto_register := true
## Body for non-local avatars: "" (the explorer), or "soldier:<faction>[:<variant>]"
## for campaign soldiers (SoldierRig, one sword).
@export var body_style := ""

@export_group("Movement")
@export var walk_speed := 4.6
@export var sprint_speed := 7.4
@export var crouch_speed := 2.3
## Deliberate walk (hold "walk"); analog sticks scale between this and `walk_speed`.
@export var slow_walk_speed := 2.6
@export var ground_accel := 11.0
@export var ground_decel := 14.0
## P06 time-based ground feel, used by the local (non-bot) avatar only; soldiers and bots
## keep ground_accel / ground_decel so army behaviour is unchanged.
@export var smooth_locomotion := true
## Seconds from rest to `walk_speed`.
@export var accel_time := 0.22
## Extra seconds from `walk_speed` to `sprint_speed`.
@export var sprint_ramp_time := 0.4
## Seconds to stop from any ground speed.
@export var stop_time := 0.16
## Braking multiplier when the input opposes the current velocity (sharp reversals).
@export var reverse_brake_scale := 1.6
## Radians per second the travel heading may swing toward a new input direction.
@export var turn_rate := 14.0
@export var air_accel := 2.5
@export var jump_velocity := 5.6
@export var gravity_scale := 1.55
@export var step_height := 0.4
@export var coyote_time := 0.12
@export var jump_buffer := 0.12

@export_group("Crouch")
@export var stand_height := 1.8
@export var crouch_height := 1.15
@export var stand_eye := 1.62
@export var crouch_eye := 1.0
@export var crouch_transition_speed := 10.0

@export_group("Water")
@export var water_level := 0.0
@export var swim_speed := 2.6
@export var wade_speed_multiplier := 0.72
## Water depth at the feet where the player starts swimming.
@export var swim_depth := 1.3
## How far below the surface the feet float while swimming.
@export var float_depth := 1.4

@export_group("Camera")
@export var max_pitch := 88.0
@export var head_bob_amount := 0.03
@export var head_bob_frequency := 0.55  ## Bob cycles per metre travelled.
@export var sprint_fov_bonus := 5.0

@export_group("Third person")
## Exploration framing from the orbit pivot (upper torso): right, up, back. The other
## framings (sprint, combat, interiors...) are derived from it in PlayerCamera.
@export var third_person_offset := Vector3(0.5, 0.47, 4.4)
## How far below the eyes the orbit pivot sits (upper torso / shoulders, not the eyes).
@export var third_person_pivot_drop := 0.2
## Extra downward tilt (degrees) so the body and the ground ahead stay in view.
@export var third_person_pitch_bias := 7.0
@export var third_person_min_distance := 0.6
## Radius of the probe that keeps the camera (and its near plane) out of walls.
@export var third_person_probe_radius := 0.22
## Closer than this to the pivot, the body is hidden so the camera never shows its inside.
@export var third_person_hide_distance := 0.9
## Metres per second the camera eases back out after an obstruction clears.
@export var third_person_return_speed := 3.5
## Third-person offset while riding: higher and farther back to frame horse and rider.
@export var riding_camera_offset := Vector3(0.5, 0.65, 5.4)

@export_group("Debug")
@export var noclip_speed := 22.0

var player_id := -1
## Follow-camera framing and the cinematic hand-over (local player only).
var cam: PlayerCamera
## Contract C-08: token-based control restrictions. Empty by default,
## in which case nothing changes; `controls_enabled` keeps working beside it.
var locks := ControlLock.new()
var _loco := Loco.IDLE
var _scripted_arrived := false
var _down_ray: PhysicsRayQueryParameters3D
var _cmd_vel := Vector3.ZERO  ## P06 free ground velocity (see _walk); synced when not smoothing.
var _smooth_frame := -10
var _pre_speed := 0.0  ## horizontal speed commanded this tick (before collision)
var _wedged := 0  ## consecutive ticks pressing on the floor with almost no progress
var _lifted := false  ## `_try_step_up` raised the body this tick (step-down must not undo it).
var input_override = null
var controls_enabled := true
var look_when_locked := false
var noclip := false
var is_crouching := false
var is_sprinting := false
var is_swimming := false
var is_sitting := false
## Terrain height at (x, z), set by World. Water only counts where the terrain
## is below the water line, so cellars under dry ground (the castle crypt) are dry.
static var terrain_height_query: Callable
## Whether the terrain has a hole at (x, z) (cave mouths, the lift throat), set by World.
static var terrain_hole_query: Callable
var water_depth := 0.0  ## How far the feet are below the water surface (0 when dry).
var form: FormDefinition
var can_crouch := true
var stamina := 100.0
var max_stamina := 100.0
var exhausted := false
var is_defeated := false

var _pitch := 0.0
var _bob_phase := 0.0
var _stride := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _current_height := 1.8
var _gravity: float
var _regen_wait := 0.0
var _override_time := 0.0
var _override_vel := Vector3.ZERO
var _leaping := false
var _leap_time := 0.0
var _fov_bonus := 0.0
var _cam_tween: Tween
## The game is third person only (the first-person / eye view was removed): the camera
## always follows behind and above the body. Aiming, interaction and combat use the
## body's facing; only the camera moves.
var third_person := true
var _tp_blend := 1.0
## Extra pitch (radians) the camera takes to find room under a low ceiling (eased).
var _tp_pitch_adjust := 0.0
var _tp_dist := -1.0  ## Current (collision-limited, smoothed) camera distance; <0 = unset.
var _tp_pivot_y := NAN  ## Smoothed pivot height (world), so step-ups and stairs do not jolt the view.
var _tp_probe: SphereShape3D
## Set by the Rider while mounted (or mounting): the horse carries the body, this script
## only looks around and places the camera at `ride_eye` (the rider's head, local).
var riding := false
var portable_lamp_on := true
var ride_eye := Vector3(0.0, 1.62, 0.0)
var _seat_return_position := Vector3.ZERO
var _seat_controls_before := true
var _seat_eye_height := 1.05
var _seat_tween: Tween
## Bots far from the camera move every Nth physics tick with an N-times step (set by
## their brain; 1 = every tick). Speeds are unchanged; only collision work is saved.
var physics_lod := 1
var _lod_tick := 0
var _lod_scale := 1.0

const SIT_MIN_NORMAL_Y := 0.94

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var capsule: CapsuleShape3D = collision.shape
@onready var footsteps: AudioStreamPlayer3D = $Footsteps
@onready var combatant: Combatant = $Combatant


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity")) * gravity_scale
	capsule = capsule.duplicate()
	collision.shape = capsule
	_set_height(stand_height)
	head.position.y = stand_eye
	camera.fov = Settings.fov
	cam = PlayerCamera.new(self)
	Settings.settings_changed.connect(func() -> void: camera.fov = Settings.fov + _fov_bonus)
	if not is_local:
		camera.current = false
		var interactor := get_node_or_null("Interactor")
		if interactor:
			interactor.monitoring = false
			interactor.process_mode = Node.PROCESS_MODE_DISABLED
	if auto_register:
		player_id = GameState.register_player(display_name, is_local, is_bot)
		Combat.register(self)
	if is_local:
		set_third_person(true)
		if not is_bot:
			# P06: Godot stops a grounded body dead when it meets a wall within 15 degrees of
			# head-on; the Commander should slide along it instead of freezing.
			wall_min_slide_angle = 0.0


func _exit_tree() -> void:
	if cam:
		cam.abort_cinematic()
	if auto_register and player_id >= 0:
		Combat.unregister(player_id)
		GameState.unregister_player(player_id)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or is_defeated:
		return
	if event.is_action_pressed("sit") and not event.is_echo():
		if is_sitting:
			stand_from_seat()
		elif controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			sit_at()
		get_viewport().set_input_as_handled()
		return
	if (not controls_enabled and not is_sitting and not look_when_locked) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		look(event.relative)


## The movement input this frame (keyboard, or input_override); the Rider steers the horse with it.
func read_input() -> Dictionary:
	return _read_input()


## Applies a mouse delta (pixels) using the player's sensitivity settings.
func look(relative: Vector2) -> void:
	var sens := deg_to_rad(Settings.mouse_sensitivity)
	rotate_y(-relative.x * sens)
	var dy := relative.y * (-1.0 if Settings.invert_y else 1.0)
	_pitch = clampf(_pitch - dy * sens, deg_to_rad(-max_pitch), deg_to_rad(max_pitch))
	head.rotation.x = _pitch


## Sets the view direction directly (spawn, teleports, bots).
func set_look(yaw: float, pitch := 0.0) -> void:
	rotation.y = yaw
	_pitch = pitch
	head.rotation.x = pitch


func teleport(pos: Vector3, yaw := NAN) -> void:
	var rider := get_node_or_null("Rider") as Rider
	if rider and rider.is_busy():
		rider.force_dismount()
	global_position = pos
	velocity = Vector3.ZERO
	_smooth_frame = -10
	_override_time = 0.0
	_leaping = false
	if not is_nan(yaw):
		set_look(yaw, 0.0)
	snap_camera()
	reset_physics_interpolation()


## Drops all camera smoothing, so the next frame frames the new place directly.
func snap_camera() -> void:
	_tp_dist = -1.0
	_tp_pivot_y = NAN
	_tp_pitch_adjust = 0.0
	if cam:
		cam.snap()


## A short, controlled step along the facing direction for an attack animation. Control
## returns by itself when it ends; knockback, dodge, stun and mounting take precedence.
func request_attack_motion(distance: float, duration: float) -> bool:
	if is_defeated or riding or is_sitting or _leaping or _override_time > 0.0 or not is_on_floor():
		return false
	if combatant.is_stunned() or locks.blocks(ControlLock.MOVE) or duration <= 0.0:
		return false
	duration = minf(duration, 0.6)
	_override_vel = forward() * (clampf(distance, -3.0, 3.0) / duration)
	_override_time = duration
	return true


func eye_position() -> Vector3:
	# Line of sight and story framing use the eyes, not the third-person camera.
	return head.global_position if third_person else camera.global_position


## Kept for callers that re-assert the follow view. There is no first-person mode any
## more, so `false` is refused and the view stays third person.
func set_third_person(_enabled := true) -> void:
	third_person = true
	_tp_blend = 1.0
	if is_local:
		camera.cull_mask |= CharacterRig.SELF_LAYER


func is_camera_underwater() -> bool:
	return camera.global_position.y < water_level - 0.05 and _over_water(camera.global_position)


func _over_water(p: Vector3) -> bool:
	return not terrain_height_query.is_valid() or float(terrain_height_query.call(p.x, p.z)) < water_level + 0.2


func current_height() -> float:
	return _current_height


func forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


# --- forms and combat hooks (called by the Combat authority) ------------------------------

func apply_form(f: FormDefinition) -> void:
	form = f
	walk_speed = f.walk_speed
	sprint_speed = f.sprint_speed
	jump_velocity = f.jump_velocity
	stand_height = f.stand_height
	stand_eye = f.stand_eye
	can_crouch = f.can_crouch
	capsule.radius = f.capsule_radius
	is_crouching = false
	_set_height(stand_height)
	max_stamina = f.max_stamina
	stamina = minf(stamina, max_stamina) if stamina > 0.0 else max_stamina
	_fov_bonus = f.fov_bonus


## Whether a body of this form fits where we stand (used before transforming).
func can_fit(f: FormDefinition) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = f.capsule_radius
	shape.height = f.stand_height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (f.stand_height * 0.5 + 0.06))
	q.collision_mask = Layers.WORLD
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func spend_stamina(amount: float) -> bool:
	if is_local and not is_bot and not GameState.is_revealed(player_id):
		return true
	if stamina < amount:
		return false
	stamina -= amount
	_regen_wait = form.regen_delay if form else 0.8
	return true


## Direction of a dodge: the movement input, or straight back with no input.
func dash_direction() -> Vector3:
	var move := Vector2.ZERO
	if input_override is Dictionary:
		move = input_override.get("move", Vector2.ZERO)
	elif is_local and controls_enabled:
		move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var dir := Basis(Vector3.UP, rotation.y) * Vector3(move.x, 0.0, -move.y)
	if dir.length() < 0.1:
		dir = -forward()
	return dir.normalized()


## Fast horizontal move for `duration`. Uses move_and_slide, so walls stop it.
func start_dash(distance: float, duration: float) -> void:
	_override_vel = dash_direction() * (distance / maxf(duration, 0.01))
	_override_time = duration


func start_leap(distance: float, height: float) -> void:
	var v_up := sqrt(2.0 * _gravity * maxf(height, 0.1))
	var flight := 2.0 * v_up / _gravity
	var f := forward() * (distance / flight)
	velocity = Vector3(f.x, v_up, f.z)
	_leaping = true
	_leap_time = 0.0


func is_leaping() -> bool:
	return _leaping


func apply_knockback(v: Vector3) -> void:
	_override_vel = Vector3(v.x, 0.0, v.z)
	_override_time = 0.2
	velocity.y = maxf(velocity.y, 2.0)


func add_shake(amount: float) -> void:
	if cam:
		cam.add_shake(amount)


func on_defeated() -> void:
	if is_sitting:
		cancel_sitting()
	is_defeated = true
	if cam:
		cam.abort_cinematic()
	is_sprinting = false
	_leaping = false
	_override_time = 0.0
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel()
	_cam_tween.tween_property(head, "position:y", 0.35, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_cam_tween.tween_property(head, "rotation:z", 1.1, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func on_respawned() -> void:
	if is_sitting:
		cancel_sitting()
	if _cam_tween:
		_cam_tween.kill()
	is_defeated = false
	head.rotation.z = 0.0
	head.position.y = stand_eye
	set_look(rotation.y, 0.0)
	velocity = Vector3.ZERO
	stamina = max_stamina
	exhausted = false
	snap_camera()


func can_offer_sit_prompt() -> bool:
	if is_sitting:
		return true
	if not is_local or is_defeated or riding or noclip or not controls_enabled:
		return false
	if not is_on_floor() or not sit_slope_is_safe(get_floor_normal()) or is_swimming or is_crouching or is_leaping():
		return false
	if water_depth > 0.05 or Combat.is_busy(player_id) or Combat.is_transforming(player_id):
		return false
	var visual := get_node_or_null("AvatarVisual") as AvatarVisual
	return visual != null and visual.human_rig is CommanderRig and visual.form_rig == null


func _sitting_state_allowed() -> bool:
	if not is_local or is_defeated or riding or noclip or is_sitting:
		return false
	if not is_on_floor() or is_swimming or is_crouching or is_leaping() or water_depth > 0.05:
		return false
	if Combat.is_busy(player_id) or Combat.is_transforming(player_id):
		return false
	var visual := get_node_or_null("AvatarVisual") as AvatarVisual
	if visual == null or not (visual.human_rig is CommanderRig) or visual.form_rig != null:
		return false
	var rig := visual.human_rig as CommanderRig
	return not rig.is_acting() and rig.current_hold() == ""


func _sit_ground_pose() -> Dictionary:
	if not _sitting_state_allowed() or not sit_slope_is_safe(get_floor_normal()):
		return {}
	var space := get_world_3d().direct_space_state
	var right := global_transform.basis.x
	var fwd := -global_transform.basis.z
	right.y = 0.0
	fwd.y = 0.0
	right = right.normalized()
	fwd = fwd.normalized()
	var offsets := [Vector3.ZERO, right * 0.28, -right * 0.28, fwd * 0.34, -fwd * 0.34]
	var heights: Array[float] = []
	var center_hit: Dictionary = {}
	for i in offsets.size():
		var offset: Vector3 = offsets[i]
		var from := global_position + offset + Vector3.UP * 0.45
		var to := global_position + offset - Vector3.UP * 0.8
		var ray := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD, [get_rid()])
		ray.collide_with_areas = false
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return {}
		var normal: Vector3 = hit["normal"]
		if not sit_slope_is_safe(normal):
			return {}
		var point: Vector3 = hit["position"]
		heights.append(point.y)
		if i == 0:
			center_hit = hit
	if heights.max() - heights.min() > 0.16:
		return {}
	var ground: Vector3 = center_hit["position"]
	if absf(ground.y - global_position.y) > 0.3:
		return {}
	# Reject a low ceiling or an obstruction around the seated torso without
	# requiring an object or a predefined marker at the player's location.
	var clearance := CapsuleShape3D.new()
	clearance.radius = 0.25
	clearance.height = 0.82
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = clearance
	query.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 0.48)
	query.collision_mask = Layers.WORLD
	query.exclude = [get_rid()]
	if not space.intersect_shape(query, 1).is_empty():
		return {}
	return {"position": ground + Vector3.UP * 0.02}


func can_sit_anywhere() -> bool:
	return not _sit_ground_pose().is_empty()


static func sit_slope_is_safe(normal: Vector3) -> bool:
	return normal.y >= SIT_MIN_NORMAL_Y


func sit_at() -> bool:
	var pose := _sit_ground_pose()
	if pose.is_empty():
		return false
	var visual := get_node("AvatarVisual") as AvatarVisual
	var rig := visual.human_rig as CommanderRig
	var duration := rig.sit_down()
	if duration <= 0.0:
		return false
	_seat_return_position = global_position
	_seat_controls_before = controls_enabled
	is_sitting = true
	controls_enabled = false
	is_sprinting = false
	_leaping = false
	_override_time = 0.0
	velocity = Vector3.ZERO
	collision.set_deferred("disabled", true)
	var target_position: Vector3 = pose["position"]
	if _seat_tween:
		_seat_tween.kill()
	_seat_tween = create_tween().set_parallel()
	_seat_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_seat_tween.tween_property(self, "global_position", target_position, duration)
	_seat_eye_height = 1.02
	return true


func stand_from_seat(animate := true) -> void:
	if not is_sitting:
		return
	var visual := get_node_or_null("AvatarVisual") as AvatarVisual
	var rig := visual.human_rig as CommanderRig if visual else null
	var duration := rig.stand_up() if animate and rig else 0.25
	if duration <= 0.0:
		duration = 0.25
	if _seat_tween:
		_seat_tween.kill()
	_seat_tween = create_tween().set_parallel()
	_seat_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_seat_tween.tween_property(self, "global_position", _seat_return_position, duration)
	_seat_tween.tween_property(self, "_seat_eye_height", stand_eye, duration)
	_seat_tween.chain().tween_callback(_finish_standing)


func _finish_standing() -> void:
	is_sitting = false
	controls_enabled = _seat_controls_before
	_seat_eye_height = stand_eye
	velocity = Vector3.ZERO
	collision.set_deferred("disabled", false)


func cancel_sitting() -> void:
	if not is_sitting:
		return
	if _seat_tween:
		_seat_tween.kill()
	var visual := get_node_or_null("AvatarVisual") as AvatarVisual
	if visual and visual.human_rig is CommanderRig:
		(visual.human_rig as CommanderRig).release()
	is_sitting = false
	controls_enabled = _seat_controls_before
	_seat_eye_height = stand_eye
	head.position.y = stand_eye
	velocity = Vector3.ZERO
	collision.set_deferred("disabled", false)


# --- simulation ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if riding:
		_set_loco(Loco.MOUNTED)
		_update_camera(delta)
		return
	if is_sitting:
		velocity = Vector3.ZERO
		_set_loco(Loco.SITTING)
		_update_camera(delta)
		return
	if is_bot and physics_lod > 1:
		_lod_tick += 1
		if _lod_tick % physics_lod != 0:
			return
		delta *= physics_lod
	_lod_scale = float(physics_lod) if is_bot else 1.0
	var inp := _read_input()
	if not locks.active_scripted().is_empty():
		_drive_scripted(inp, delta)
	if noclip:
		_noclip_move(inp, delta)
		return

	water_depth = maxf(0.0, water_level - global_position.y) if _over_water(global_position) else 0.0
	is_swimming = water_depth > swim_depth or (is_swimming and water_depth > swim_depth - 0.25)

	_update_crouch(inp["crouch"] and not is_swimming and can_crouch and not is_defeated, delta)

	var move: Vector2 = inp["move"]
	var basis_flat := Basis(Vector3.UP, rotation.y)
	var wish := basis_flat * Vector3(move.x, 0.0, -move.y)
	if wish.length() > 1.0:
		wish = wish.normalized()

	if is_swimming:
		_swim(inp, wish, delta)
	else:
		_walk(inp, wish, delta)

	_update_stamina(delta)
	_update_loco(inp, wish)
	_update_camera(delta)
	if global_position.y < -40.0:
		fell_out_of_world.emit()


func _walk(inp: Dictionary, wish: Vector3, delta: float) -> void:
	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else maxf(_coyote - delta, 0.0)
	_jump_buffer = jump_buffer if inp["jump_pressed"] else maxf(_jump_buffer - delta, 0.0)

	if exhausted and stamina >= (form.exhausted_threshold if form else 30.0):
		exhausted = false
	var wants_sprint: bool = inp["sprint"] and not is_crouching and inp["move"].y > 0.1 and not combatant.is_shaken()
	is_sprinting = wants_sprint and not exhausted and stamina > 0.0
	var speed := sprint_speed if is_sprinting else walk_speed
	if is_crouching:
		speed = crouch_speed
	elif inp.get("walk", false) and not is_sprinting:
		speed = minf(slow_walk_speed, walk_speed)
	if water_depth > 0.15:
		speed *= wade_speed_multiplier
	speed *= combatant.speed_multiplier()
	if Combat.is_transforming(player_id):
		speed *= 0.5
	# R02 sword combat: a committed cut or a raised guard has weight.
	if is_local and not is_bot and Combat.swords.actors.has(player_id):
		if Combat.swords.attacks.has(player_id):
			speed *= 0.35
			is_sprinting = false
		elif bool(Combat.swords.actors[player_id].guard):
			speed = minf(speed, walk_speed * 0.5)
			is_sprinting = false

	if not on_floor:
		velocity.y -= _gravity * delta
	if _jump_buffer > 0.0 and _coyote > 0.0 and not _leaping:
		velocity.y = jump_velocity * (0.8 if is_crouching else 1.0)
		_jump_buffer = 0.0
		_coyote = 0.0

	if _leaping:
		_leap_time += delta
		if on_floor and _leap_time > 0.1:
			_leaping = false
	elif _override_time > 0.0:
		_override_time -= delta
		velocity.x = _override_vel.x
		velocity.z = _override_vel.z
		if _override_time <= 0.0:
			# Leave a dash at normal speed instead of sliding on.
			var out := Vector2(velocity.x, velocity.z).limit_length(walk_speed)
			velocity.x = out.x
			velocity.z = out.y
	else:
		var horiz := Vector3(velocity.x, 0.0, velocity.z)
		var target := wish * speed
		if on_floor and smooth_locomotion and is_local and not is_bot:
			# Ramp a free (collision-independent) velocity: sliding along a wall or door
			# frame removes speed from `velocity` every tick and a gentle ramp could never
			# win it back, so the commanded velocity is what accelerates, not the result.
			var pf := Engine.get_physics_frames()
			if _smooth_frame != pf - 1:
				_cmd_vel = horiz  # resuming after swim / ride / sit / air / teleport: start from reality
			_smooth_frame = pf
			_cmd_vel = _ground_step(_cmd_vel, target, wish.length() > 0.01, delta)
			horiz = _cmd_vel
		else:
			var rate := (ground_accel if wish.length() > 0.01 else ground_decel) if on_floor else air_accel
			horiz = horiz.move_toward(target, rate * speed * delta) if on_floor else horiz.lerp(target, clampf(air_accel * delta, 0.0, 1.0))
		velocity.x = horiz.x
		velocity.z = horiz.z
		# Bots only probe for a step when they are actually pressing into something.
		_lifted = false
		_pre_speed = horiz.length()
		if on_floor and (is_local or get_slide_collision_count() > 0):
			_try_step_up(delta, _wedged >= 2 and smooth_locomotion and is_local and not is_bot)
	if not (on_floor and smooth_locomotion and is_local and not is_bot) or _leaping or _override_time > 0.0:
		_cmd_vel = Vector3(velocity.x, 0.0, velocity.z)  # keep the free velocity in step with reality
	_slide()
	if on_floor and _pre_speed > 1.0 and Vector2(velocity.x, velocity.z).length() < _pre_speed * 0.2:
		_wedged += 1
	else:
		_wedged = 0
	_pre_speed = 0.0
	if on_floor and smooth_locomotion and is_local and not is_bot and not is_on_floor() and not _lifted \
			and velocity.y <= 0.0 and not _leaping and _override_time <= 0.0:
		_try_step_down()
	_footsteps(delta)


## P06 ground acceleration in m/s^2 (time-based): walk_speed in `accel_time`, then up to
## sprint_speed over `sprint_ramp_time`; any stop takes `stop_time`; reversals brake harder.
func _ground_rate(cur: Vector3, target: Vector3, has_input: bool) -> float:
	var cur_len := cur.length()
	if not has_input:
		return maxf(cur_len, walk_speed) / maxf(stop_time, 0.01)
	var rate := walk_speed / maxf(accel_time, 0.01)
	if target.length() > walk_speed * 1.02 and cur_len >= walk_speed * 0.98:
		rate = maxf(sprint_speed - walk_speed, 0.5) / maxf(sprint_ramp_time, 0.01)
	if cur_len > 0.5 and cur.dot(target) < 0.0:
		rate *= reverse_brake_scale
	return rate


## P06: walking off a kerb or down stairs. The capsule's rounded foot catches the edge's
## vertical face, which defeats the engine's floor snap, so the body would fall every step.
## One short ray from the capsule axis, only on the tick ground contact is lost, finds the
## lower floor within `step_height`; the body is lowered onto it. Local avatar only.
func _try_step_down() -> void:
	if _down_ray == null:
		_down_ray = PhysicsRayQueryParameters3D.new()
		_down_ray.collision_mask = Layers.WORLD
		_down_ray.collide_with_areas = false
	_down_ray.exclude = [get_rid()]
	_down_ray.from = global_position + Vector3.UP * 0.1
	_down_ray.to = global_position + Vector3.DOWN * (step_height + 0.05)
	var hit := get_world_3d().direct_space_state.intersect_ray(_down_ray)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.72:
		return
	var drop := global_position.y - (hit["position"] as Vector3).y
	if drop > 0.005:
		global_position.y -= drop
	velocity.y = 0.0
	apply_floor_snap()


## One tick of P06 ground velocity. The *magnitude* ramps (accel / sprint ramp / stop time);
## the *direction* follows the input at `turn_rate` so corners, doorways and switchback
## stairs stay precise instead of drifting on the old heading. A near-reversal brakes along
## the current heading first, then leaves in the new one.
func _ground_step(cur: Vector3, target: Vector3, has_input: bool, delta: float) -> Vector3:
	var cur_len := cur.length()
	var rate := _ground_rate(cur, target, has_input)
	if not has_input or target.length_squared() < 0.0001:
		return cur.normalized() * maxf(cur_len - rate * delta, 0.0) if cur_len > 0.0001 else Vector3.ZERO
	var tgt_len := target.length()
	var tdir := target / tgt_len
	if cur_len < 0.3:
		return tdir * move_toward(cur_len, tgt_len, rate * delta)
	var cdir := cur / cur_len
	if cdir.dot(tdir) < -0.35:
		return cdir * maxf(cur_len - rate * delta, 0.0)  # brake first (rate already includes the reversal boost)
	var ang := cdir.signed_angle_to(tdir, Vector3.UP)
	var step := turn_rate * delta
	var ndir := tdir if absf(ang) <= step else cdir.rotated(Vector3.UP, signf(ang) * step)
	return ndir * move_toward(cur_len, tgt_len, rate * delta)


## Scripted movement (a ControlLock token holding MOVE): walk the body to the target.
## Drives the same movement path as the player; callers cancel by releasing the token.
func _drive_scripted(inp: Dictionary, delta: float) -> void:
	var rec := locks.active_scripted()
	var to: Vector3 = rec["target"] - global_position
	to.y = 0.0
	if to.length() < 0.35:
		var token := locks.active_scripted_token()
		locks.end_scripted_move(token)
		_scripted_arrived = true
		inp["move"] = Vector2.ZERO
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), clampf(delta * 8.0, 0.0, 1.0))
	inp["move"] = Vector2(0.0, clampf(float(rec["speed"]) / maxf(walk_speed, 0.1), 0.2, 1.0))
	inp["sprint"] = false
	inp["jump_pressed"] = false


## True once after a scripted move reached its target (cleared by reading).
func consume_scripted_arrival() -> bool:
	var a := _scripted_arrived
	_scripted_arrived = false
	return a


func locomotion_state() -> int:
	return _loco


func locomotion_name() -> String:
	return Loco.keys()[_loco]


## Horizontal ground speed (m/s), the value rigs and animation should use.
func ground_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _set_loco(s: int) -> void:
	if s != _loco:
		var old := _loco
		_loco = s
		locomotion_changed.emit(s, old)


## The state follows the *intended* gait (input and chosen speed), not the instantaneous
## speed, so a hard reversal (speed passes through zero) does not flicker IDLE/WALK/RUN.
func _update_loco(inp: Dictionary, wish: Vector3) -> void:
	var s := Loco.IDLE
	var v := ground_speed()
	var intent := wish.length() > 0.05
	if is_defeated:
		s = Loco.DEAD
	elif is_swimming:
		s = Loco.SWIM
	elif _override_time > 0.0:
		s = Loco.DASH
	elif not is_on_floor():
		s = Loco.AIR
	elif is_crouching:
		s = Loco.CROUCH
	elif not intent:
		# Coasting to a stop keeps the previous gait until (nearly) at rest.
		var moving := _loco == Loco.WALK or _loco == Loco.RUN or _loco == Loco.SPRINT
		s = _loco if v >= 0.3 and moving else Loco.IDLE
	elif is_sprinting:
		s = Loco.SPRINT
	elif inp.get("walk", false) or wish.length() * walk_speed < walk_speed * 0.8:
		s = Loco.WALK
	else:
		s = Loco.RUN
	# Restricted and standing still: report LOCKED (moving restricted bodies keep their gait).
	if s == Loco.IDLE and (not controls_enabled or locks.blocks(ControlLock.MOVE)) and input_override == null:
		s = Loco.LOCKED
	_set_loco(s)


## move_and_slide over this tick's (possibly LOD-scaled) step.
func _slide() -> void:
	if _lod_scale > 1.0:
		velocity *= _lod_scale
		move_and_slide()
		velocity /= _lod_scale
	else:
		move_and_slide()


func _swim(inp: Dictionary, wish: Vector3, delta: float) -> void:
	is_sprinting = false
	_coyote = 0.0
	_leaping = false
	var target_y := water_level - float_depth
	var vy := clampf((target_y - global_position.y) * 2.5, -2.0, 2.0)
	if inp["jump"]:
		vy = 2.2
	elif inp["crouch"]:
		vy = -1.8
	velocity.y = move_toward(velocity.y, vy, 8.0 * delta)
	var target := wish * swim_speed * combatant.speed_multiplier()
	if _override_time > 0.0:
		_override_time -= delta
		target = _override_vel * 0.5
	var horiz := Vector3(velocity.x, 0.0, velocity.z).move_toward(target, 6.0 * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	_slide()
	_stride += horiz.length() * delta
	if _stride > 2.4:
		_stride = 0.0
		_play_step(true, -14.0)


func _update_stamina(delta: float) -> void:
	if is_local and not is_bot and not GameState.is_revealed(player_id):
		stamina = max_stamina
		exhausted = false
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.5
	if is_sprinting and moving:
		var drain: float = form.sprint_drain if form else 22.0
		stamina = maxf(0.0, stamina - drain * delta)
		_regen_wait = form.regen_delay if form else 0.8
		if stamina <= 0.0:
			exhausted = true
	elif _regen_wait > 0.0:
		_regen_wait -= delta
	else:
		stamina = minf(max_stamina, stamina + (form.stamina_regen if form else 16.0) * delta)


## Lifts the body over small ledges (rubble, kerbs, roots) that move_and_slide
## would treat as walls.
func _try_step_up(delta: float, force := false) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z) * delta
	if horiz.length() < 0.0005:
		return
	var dir := horiz.normalized()
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, dir * maxf(horiz.length(), 0.06), hit):
		return
	# A "walkable-looking" normal is normally a slope, not a ledge. `force` (set after the body
	# has pressed on without progress) lets a wedge on a riser corner step up anyway.
	if hit.get_normal().y > 0.72 and not force:
		return
	var up := Vector3.UP * step_height
	var t := global_transform
	if test_move(t, up):
		return
	# Probe a capsule-width ahead so the landing test hits the ledge top, not its edge.
	# A wedged capsule rests on its rounded foot a little short of the riser, so look further.
	var ahead := dir * (capsule.radius * (1.4 if force else 0.8))
	t.origin += up
	if test_move(t, ahead):
		return
	t.origin += ahead
	var down := KinematicCollision3D.new()
	if not test_move(t, -up - Vector3.UP * 0.05, down):
		return
	if down.get_normal().y < 0.72:
		return
	var lift := t.origin.y + down.get_travel().y - global_position.y
	if lift > 0.02:
		# Lift vertically only; move_and_slide then carries the body onto the ledge.
		global_position.y += lift + 0.01
		_lifted = true


func _update_crouch(want_crouch: bool, delta: float) -> void:
	if want_crouch:
		is_crouching = true
	elif is_crouching:
		# Only stand if there is headroom.
		var needed := stand_height - _current_height
		if needed <= 0.01 or not test_move(global_transform, Vector3.UP * needed):
			is_crouching = false
	var target := crouch_height if is_crouching else stand_height
	if absf(_current_height - target) > 0.001:
		_set_height(move_toward(_current_height, target, crouch_transition_speed * delta))


func _set_height(h: float) -> void:
	_current_height = h
	capsule.height = maxf(h, capsule.radius * 2.0)
	collision.position.y = capsule.height * 0.5


func _update_camera(delta: float) -> void:
	if not is_local:
		return  # Bots and soldiers have no active camera: skip the follow-camera sweeps.
	if is_defeated:
		return
	cam.update(delta)
	var t := inverse_lerp(crouch_height, stand_height, _current_height) if stand_height > crouch_height else 1.0
	var eye := _seat_eye_height if is_sitting else lerpf(crouch_eye, stand_eye, clampf(t, 0.0, 1.0))
	var bob := 0.0
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if Settings.head_bob and not Settings.reduce_motion and is_on_floor() and horiz_speed > 0.5 and not is_swimming:
		_bob_phase += horiz_speed * delta * head_bob_frequency * TAU
		bob = sin(_bob_phase) * head_bob_amount * clampf(horiz_speed / walk_speed, 0.3, 1.4)
	else:
		_bob_phase = 0.0
	if riding:
		# Follow the rider's head, smoothed so the saddle's bounce does not shake the view.
		head.position = head.position.lerp(ride_eye, clampf(delta * 10.0, 0.0, 1.0))
	else:
		head.position.x = move_toward(head.position.x, 0.0, delta)
		head.position.z = move_toward(head.position.z, 0.0, delta)
		head.position.y = lerpf(head.position.y, eye + bob, clampf(delta * (6.0 if Combat.is_transforming(player_id) else 14.0), 0.0, 1.0))
	_update_third_person(delta)
	camera.fov = lerpf(camera.fov, cam.target_fov(_fov_bonus), PlayerCamera.blend(8.0, delta))
	cam.update_cinematic(delta)


## Third-person follow camera: orbits an upper-torso pivot with the body's yaw and the look
## pitch (plus a small downward bias), sits over the right shoulder, pulls in at once when
## walls/trees/terrain block it and eases back out, and never drops below terrain or water.
## Only the camera moves: aiming, interaction and combat still use the head/body facing.
##
## Underground (the cave, the castle crypt) the terrain heightfield is the ROOF above the
## body, not the ground, so the terrain/water floor clamps are skipped there (and over the
## terrain's holes: cave mouths, the lift throat); the sphere probe against the real
## walls, floors and ceilings keeps the camera inside with the commander. Under a low
## ceiling the camera also eases to a flatter angle when that leaves it farther out.
func _update_third_person(delta: float) -> void:
	_tp_blend = 1.0
	var offset := cam.offset
	var pivot := head.global_position
	if not riding:
		var py := global_position.y + head.position.y - third_person_pivot_drop
		if is_nan(_tp_pivot_y) or absf(py - _tp_pivot_y) > 2.0:
			_tp_pivot_y = py
		_tp_pivot_y = lerpf(_tp_pivot_y, py, PlayerCamera.blend(13.0, delta))
		pivot.y = _tp_pivot_y
	var base_pitch := _pitch - cam.pitch_bias
	var full := offset.length()
	var space := get_world_3d().direct_space_state
	if _tp_probe == null:
		_tp_probe = SphereShape3D.new()
	_tp_probe.radius = third_person_probe_radius

	# Room at the preferred angle; when cramped, look for a flatter angle with more room.
	var target_adjust := 0.0
	var preferred := _tp_clear_distance(space, pivot, _tp_orbit(base_pitch), offset, full)
	if preferred < full * 0.8:
		var best := preferred
		for k in [1, 2, 3]:
			var adj := 0.16 * float(k)
			var d := _tp_clear_distance(space, pivot, _tp_orbit(base_pitch + adj), offset, full)
			if d > best + 0.4:
				best = d
				target_adjust = adj
	_tp_pitch_adjust = move_toward(_tp_pitch_adjust, target_adjust, delta * 0.9)
	var orbit := _tp_orbit(base_pitch + _tp_pitch_adjust)
	var dir := orbit * (offset / maxf(full, 0.001))
	var allowed := _tp_clear_distance(space, pivot, orbit, offset, full)
	if _tp_dist < 0.0 or allowed < _tp_dist:
		_tp_dist = allowed
	else:
		_tp_dist = move_toward(_tp_dist, allowed, delta * third_person_return_speed)

	var cam_pos := pivot + dir * _tp_dist
	var underground := is_underground(pivot)
	if terrain_height_query.is_valid() and not underground and not _terrain_hole(cam_pos):
		cam_pos.y = maxf(cam_pos.y, float(terrain_height_query.call(cam_pos.x, cam_pos.z)) + 0.35)
	if not is_swimming and not underground and _over_water(cam_pos):
		cam_pos.y = maxf(cam_pos.y, water_level + 0.25)
	if is_local:
		if cam_pos.distance_to(pivot) < third_person_hide_distance:
			camera.cull_mask &= ~CharacterRig.SELF_LAYER
		else:
			camera.cull_mask |= CharacterRig.SELF_LAYER
	camera.global_transform = Transform3D(orbit, cam_pos)


func _tp_orbit(pitch: float) -> Basis:
	return Basis(Vector3.UP, rotation.y) * Basis(Vector3.RIGHT, clampf(pitch, deg_to_rad(-max_pitch), deg_to_rad(max_pitch)))


## How far the camera can sit from the pivot along `orbit * offset` before touching
## world geometry (sphere probe; a ray when the probe starts inside something).
func _tp_clear_distance(space: PhysicsDirectSpaceState3D, pivot: Vector3, orbit: Basis, offset: Vector3, full: float) -> float:
	var dir := orbit * (offset / maxf(full, 0.001))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _tp_probe
	q.transform = Transform3D(Basis.IDENTITY, pivot)
	q.motion = dir * full
	q.collision_mask = Layers.WORLD
	q.exclude = [get_rid()]
	var frac := space.cast_motion(q)
	var allowed := full * (frac[0] if frac.size() > 0 else 1.0)
	if frac.size() > 1 and frac[1] <= 0.0:
		# The probe already touches something at the pivot (tight rooms): fall back to a ray.
		var rq := PhysicsRayQueryParameters3D.create(pivot, pivot + dir * full, Layers.WORLD, [get_rid()])
		var hit := space.intersect_ray(rq)
		allowed = full if hit.is_empty() else pivot.distance_to(hit["position"]) - third_person_probe_radius
	return clampf(allowed, minf(third_person_min_distance, full), full)


## True when the terrain surface is above `p` (inside the cave or the crypt).
func is_underground(p: Vector3) -> bool:
	return terrain_height_query.is_valid() and float(terrain_height_query.call(p.x, p.z)) > p.y + 0.6


func _terrain_hole(p: Vector3) -> bool:
	return terrain_hole_query.is_valid() and bool(terrain_hole_query.call(p.x, p.z))


func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.4:
		return
	_stride += speed * delta
	var stride_len := 2.6 if is_sprinting else (1.5 if is_crouching else 2.0)
	if _stride >= stride_len:
		_stride = 0.0
		var vol := -6.0 if is_sprinting else (-20.0 if is_crouching else -11.0)
		_play_step(water_depth > 0.1, vol)


func _play_step(wet: bool, volume_db: float) -> void:
	var lib := AudioLib.get_instance()
	if lib == null:
		return
	footsteps.stream = lib.footstep(wet)
	footsteps.volume_db = volume_db + (4.0 if stand_height > 2.0 else 0.0)
	var base_pitch := 0.65 if stand_height > 2.0 else 1.0
	footsteps.pitch_scale = base_pitch * randf_range(0.9, 1.1)
	footsteps.play()


func _noclip_move(inp: Dictionary, delta: float) -> void:
	var move: Vector2 = inp["move"]
	var dir := camera.global_transform.basis * Vector3(move.x, 0.0, -move.y)
	if inp["jump"]:
		dir += Vector3.UP
	if inp["crouch"]:
		dir += Vector3.DOWN
	var spd := noclip_speed * (2.5 if inp["sprint"] else 1.0)
	global_position += dir.normalized() * spd * delta if dir.length() > 0.01 else Vector3.ZERO
	velocity = Vector3.ZERO


func set_noclip(enabled: bool) -> void:
	noclip = enabled
	collision.disabled = enabled


const _NO_INPUT := {"move": Vector2.ZERO, "jump": false, "jump_pressed": false, "sprint": false, "crouch": false, "walk": false}


func _read_input() -> Dictionary:
	if is_defeated or (combatant and combatant.is_stunned()):
		return _NO_INPUT.duplicate()
	var d: Dictionary
	if input_override is Dictionary:
		var o: Dictionary = input_override
		var jp: bool = o.get("jump_pressed", false)
		o["jump_pressed"] = false  # one-shot, like is_action_just_pressed
		d = {
			"move": o.get("move", Vector2.ZERO), "jump": o.get("jump", false), "jump_pressed": jp,
			"sprint": o.get("sprint", false), "crouch": o.get("crouch", false), "walk": o.get("walk", false),
		}
	elif not controls_enabled or not is_local:
		return _NO_INPUT.duplicate()
	else:
		d = {
			"move": Input.get_vector("move_left", "move_right", "move_back", "move_forward"),
			"jump": Input.is_action_pressed("jump"),
			"jump_pressed": Input.is_action_just_pressed("jump"),
			"sprint": Input.is_action_pressed("sprint"),
			"crouch": Input.is_action_pressed("crouch"),
			"walk": Input.is_action_pressed("walk"),
		}
	if locks.mask() & (ControlLock.MOVE | ControlLock.PAUSE):
		d["move"] = Vector2.ZERO
		d["jump"] = false
		d["jump_pressed"] = false
		d["sprint"] = false
		d["walk"] = false
	return d
