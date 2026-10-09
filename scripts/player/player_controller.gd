class_name PlayerController
extends CharacterBody3D
## First-person avatar: mouse look, walk/sprint/crouch/jump, wading and
## swimming, small step-up for rubble, optional head bob and footsteps.
## Phase 2 adds forms (human / revealed monster), stamina, dash, leap,
## knockback, status effects, defeat camera and remote (non-local) avatars.
##
## Movement is read through _read_input(), which uses either the keyboard or
## `input_override` (a Dictionary set by tests, bots or a future network layer).
## Combat rules live in the Combat authority; this script only moves the body.

signal fell_out_of_world

@export_group("Identity")
@export var display_name := "Player"
## The player on this machine (camera, HUD, input). Bots and future peers are not local.
@export var is_local := true
@export var is_bot := false
## Registers with GameState / Combat on ready. Off only for preview scenes.
@export var auto_register := true

@export_group("Movement")
@export var walk_speed := 4.6
@export var sprint_speed := 7.4
@export var crouch_speed := 2.3
@export var ground_accel := 11.0
@export var ground_decel := 14.0
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
@export var sprint_fov_bonus := 4.0

@export_group("Debug")
@export var noclip_speed := 22.0

var player_id := -1
var input_override = null
var controls_enabled := true
var noclip := false
var is_crouching := false
var is_sprinting := false
var is_swimming := false
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
var _shake := 0.0
var _fov_bonus := 0.0
var _cam_tween: Tween

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
	Settings.settings_changed.connect(func() -> void: camera.fov = Settings.fov + _fov_bonus)
	if is_local:
		camera.cull_mask &= ~CharacterRig.SELF_LAYER
	else:
		camera.current = false
		var interactor := get_node_or_null("Interactor")
		if interactor:
			interactor.monitoring = false
			interactor.process_mode = Node.PROCESS_MODE_DISABLED
	if auto_register:
		player_id = GameState.register_player(display_name, is_local, is_bot)
		Combat.register(self)


func _exit_tree() -> void:
	if auto_register and player_id >= 0:
		Combat.unregister(player_id)
		GameState.unregister_player(player_id)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or not controls_enabled or is_defeated or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		look(event.relative)


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
	global_position = pos
	velocity = Vector3.ZERO
	_override_time = 0.0
	_leaping = false
	if not is_nan(yaw):
		set_look(yaw, 0.0)
	reset_physics_interpolation()


func eye_position() -> Vector3:
	return camera.global_position


func is_camera_underwater() -> bool:
	return camera.global_position.y < water_level - 0.05


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
	_shake = maxf(_shake, amount)


func on_defeated() -> void:
	is_defeated = true
	is_sprinting = false
	_leaping = false
	_override_time = 0.0
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel()
	_cam_tween.tween_property(head, "position:y", 0.35, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_cam_tween.tween_property(head, "rotation:z", 1.1, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func on_respawned() -> void:
	if _cam_tween:
		_cam_tween.kill()
	is_defeated = false
	head.rotation.z = 0.0
	head.position.y = stand_eye
	set_look(rotation.y, 0.0)
	velocity = Vector3.ZERO
	stamina = max_stamina
	exhausted = false


# --- simulation ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var inp := _read_input()
	if noclip:
		_noclip_move(inp, delta)
		return

	water_depth = maxf(0.0, water_level - global_position.y)
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
	if water_depth > 0.15:
		speed *= wade_speed_multiplier
	speed *= combatant.speed_multiplier()
	if Combat.is_transforming(player_id):
		speed *= 0.5

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
		var rate := (ground_accel if wish.length() > 0.01 else ground_decel) if on_floor else air_accel
		horiz = horiz.move_toward(target, rate * speed * delta) if on_floor else horiz.lerp(target, clampf(air_accel * delta, 0.0, 1.0))
		velocity.x = horiz.x
		velocity.z = horiz.z
		if on_floor:
			_try_step_up(delta)
	move_and_slide()
	_footsteps(delta)


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
	move_and_slide()
	_stride += horiz.length() * delta
	if _stride > 2.4:
		_stride = 0.0
		_play_step(true, -14.0)


func _update_stamina(delta: float) -> void:
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
func _try_step_up(delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z) * delta
	if horiz.length() < 0.0005:
		return
	var dir := horiz.normalized()
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, dir * maxf(horiz.length(), 0.06), hit):
		return
	if hit.get_normal().y > 0.72:
		return
	var up := Vector3.UP * step_height
	var t := global_transform
	if test_move(t, up):
		return
	# Probe a capsule-width ahead so the landing test hits the ledge top, not its edge.
	var ahead := dir * (capsule.radius * 0.8)
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
	_shake = maxf(0.0, _shake - delta * 2.5)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.06
	camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.06
	if is_defeated:
		return
	var t := inverse_lerp(crouch_height, stand_height, _current_height) if stand_height > crouch_height else 1.0
	var eye := lerpf(crouch_eye, stand_eye, clampf(t, 0.0, 1.0))
	var bob := 0.0
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if Settings.head_bob and is_on_floor() and horiz_speed > 0.5 and not is_swimming:
		_bob_phase += horiz_speed * delta * head_bob_frequency * TAU
		bob = sin(_bob_phase) * head_bob_amount * clampf(horiz_speed / walk_speed, 0.3, 1.4)
	else:
		_bob_phase = 0.0
	head.position.y = lerpf(head.position.y, eye + bob, clampf(delta * (6.0 if Combat.is_transforming(player_id) else 14.0), 0.0, 1.0))
	var fov_target := Settings.fov + _fov_bonus + (sprint_fov_bonus if is_sprinting and horiz_speed > walk_speed else 0.0)
	camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 6.0, 0.0, 1.0))


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


const _NO_INPUT := {"move": Vector2.ZERO, "jump": false, "jump_pressed": false, "sprint": false, "crouch": false}


func _read_input() -> Dictionary:
	if is_defeated or (combatant and combatant.is_stunned()):
		return _NO_INPUT.duplicate()
	if input_override is Dictionary:
		var o: Dictionary = input_override
		var jp: bool = o.get("jump_pressed", false)
		o["jump_pressed"] = false  # one-shot, like is_action_just_pressed
		return {
			"move": o.get("move", Vector2.ZERO), "jump": o.get("jump", false), "jump_pressed": jp,
			"sprint": o.get("sprint", false), "crouch": o.get("crouch", false),
		}
	if not controls_enabled or not is_local:
		return _NO_INPUT.duplicate()
	return {
		"move": Input.get_vector("move_left", "move_right", "move_back", "move_forward"),
		"jump": Input.is_action_pressed("jump"),
		"jump_pressed": Input.is_action_just_pressed("jump"),
		"sprint": Input.is_action_pressed("sprint"),
		"crouch": Input.is_action_pressed("crouch"),
	}
