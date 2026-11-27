class_name Horse
extends CharacterBody3D
## The commander's warhorse: a ridden animal with discrete gaits (walk, trot, canter,
## gallop), natural acceleration and stopping, steering whose rate falls with speed,
## turning on the spot and backing up. It follows the terrain (body pitched to the
## slope, kept out of deep water) and collides with the world and with people.
##
## Steering comes from `drive` (a Dictionary set by the Rider each physics frame, or
## by tests): {"move": Vector2, "sprint": bool}. Without a rider it stands, grazes
## now and then, and can be called to the player (come_to).
##
## Presentation (model, animation, tack, reins) lives in HorseRig; it only reads
## `speed`, `gait`, `turn_rate` and the slope fields here.

signal gait_changed(gait: int)
signal rider_changed(rider: Node)

enum Gait { STAND, WALK, TROT, CANTER, GALLOP, BACK }

## Ground speeds (m/s). Walk, trot and gallop match the stride lengths of the clips
## (measured from the hoof contacts in Art/horse/pipeline/01_base.py); the canter is
## the gallop clip played slower.
const GAIT_SPEED := {Gait.WALK: 1.75, Gait.TROT: 3.4, Gait.CANTER: 6.2, Gait.GALLOP: 9.6, Gait.BACK: -0.9}
const GAIT_NAMES := {Gait.STAND: "stand", Gait.WALK: "walk", Gait.TROT: "trot", Gait.CANTER: "canter",
	Gait.GALLOP: "gallop", Gait.BACK: "back"}

@export_group("Movement")
@export var accel := 2.6            ## m/s² when asking for more speed
@export var gallop_accel := 3.4
@export var decel := 3.8            ## m/s² when slowing (a gallop stops in about 2.5 s)
@export var brake_decel := 6.0      ## m/s² when the rider pulls back
## Degrees per second when steering, by gait.
@export var turn_rate_stand := 75.0
@export var turn_rate_walk := 85.0
@export var turn_rate_trot := 70.0
@export var turn_rate_canter := 52.0
@export var turn_rate_gallop := 38.0
@export var gravity_scale := 1.4
## Water deeper than this (at the hooves) stops the horse, like a wall.
@export var max_wade_depth := 1.1
## Ledges up to this height are stepped over instead of stopping the horse.
@export var step_height := 0.4
## Sleep (no physics, animation or secondary motion) when idle and far from the camera.
## On for the Commander's own horse; the company's horses are managed by Army.
@export var self_dormancy := false
@export var dormancy_distance := 70.0

@export_group("Stamina")
@export var max_stamina := 100.0
@export var gallop_drain := 9.0     ## per second
@export var canter_drain := 2.0
@export var stamina_regen := 6.0

## Seconds the rider has to hold sprint at a canter before the horse gallops.
@export var canter_to_gallop := 1.1

var rider: Node = null
var drive = null
## Signed forward speed (negative when backing).
var speed := 0.0
var gait: int = Gait.STAND
var turn_rate := 0.0                ## current yaw rate, rad/s (+ = left)
var stamina := 100.0
## Cruise gait for plain forward input (toggled by the rider: walk or trot).
var cruise: int = Gait.TROT
var slope_pitch := 0.0              ## radians, nose up positive
## Metres to lower the model so the hooves meet the ground under them (the body's
## collision margin, bumps and dips between fore and hind hooves); negative raises it.
var body_drop := 0.0
var water_level := 0.0
var _sprint_time := 0.0
var _gravity := 9.8
var _come_target := Vector3.INF

@onready var rig: HorseRig = get_node_or_null("Rig") as HorseRig
@onready var mount_point: Interactable = get_node_or_null("MountPoint") as Interactable


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity")) * gravity_scale
	collision_layer = Layers.CREATURE
	collision_mask = Layers.WORLD | Layers.PLAYER
	floor_max_angle = deg_to_rad(42.0)
	floor_snap_length = 0.6
	stamina = max_stamina
	add_to_group("horses")
	if mount_point:
		mount_point.interacted.connect(_on_mount_requested)
	if self_dormancy:
		enable_self_dormancy()


func enable_self_dormancy() -> void:
	self_dormancy = true
	if has_node("DormancyClock"):
		return
	var clock := Timer.new()
	clock.name = "DormancyClock"
	clock.wait_time = 0.75
	clock.autostart = true
	clock.timeout.connect(check_dormancy)
	add_child(clock)


## Sleeps an idle, riderless, grounded horse the camera is far from; wakes it otherwise.
func check_dormancy() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var far := camera.global_position.distance_to(global_position) > dormancy_distance
	var idle := rider == null and drive == null and not is_recalled() and absf(speed) < 0.05
	set_dormant(idle and far and (dormant or is_on_floor()))


func is_recalled() -> bool:
	return _come_target != Vector3.INF


func stop_recall() -> void:
	_come_target = Vector3.INF
	recall_path = PackedVector3Array()


func _on_mount_requested(by: Node) -> void:
	var r := by.get_node_or_null("Rider") as Rider
	if r:
		r.mount(self)


func set_rider(r: Node) -> void:
	set_dormant(false)
	if rider and rider != r and is_instance_valid(rider):
		remove_collision_exception_with(rider)
	rider = r
	drive = null
	_come_target = Vector3.INF
	if r:
		# Carry the rider without being pushed by its (disabled) body.
		add_collision_exception_with(r)
	if mount_point:
		mount_point.enabled = r == null
	rider_changed.emit(r)


func is_ridden() -> bool:
	return rider != null


func forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized()


func gait_name() -> String:
	return GAIT_NAMES[gait]


## A riderless horse standing far from the camera can sleep: no animation, no
## secondary motion, no physics, until something needs it (the company's spare horses).
var dormant := false
var recall_path := PackedVector3Array()
var _recall_refresh := 0.0
var _recall_last := Vector3.INF


func set_dormant(on: bool) -> void:
	if on == dormant:
		return
	dormant = on
	set_physics_process(not on)
	if rig:
		rig.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT


## Walk to a point (the rider whistled). Cancelled by mounting.
func come_to(p: Vector3) -> void:
	set_dormant(false)
	if rider == null:
		drive = null
		if _come_target == Vector3.INF or _come_target.distance_to(p) > 5.0:
			recall_path = _recall_route(p)
			_recall_last = Vector3.INF
			_recall_refresh = 1.2
		_come_target = p


func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO
	speed = 0.0
	gait = Gait.STAND
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	_recall_refresh -= delta
	if _come_target != Vector3.INF and _recall_refresh <= 0.0:
		_recall_refresh = 1.2
		if _recall_last != Vector3.INF and global_position.distance_to(_recall_last) < 0.5:
			recall_path = _recall_route(_come_target)
		_recall_last = global_position
	var inp := _drive_input()
	var move: Vector2 = inp.get("move", Vector2.ZERO)
	var sprint: bool = inp.get("sprint", false)

	# --- desired speed --------------------------------------------------------------
	var want := 0.0
	var rate := decel
	if move.y > 0.2:
		if sprint and stamina > 5.0:
			_sprint_time += delta
			want = GAIT_SPEED[Gait.GALLOP] if (_sprint_time > canter_to_gallop and stamina > 15.0) else GAIT_SPEED[Gait.CANTER]
			rate = gallop_accel
		else:
			_sprint_time = 0.0
			want = GAIT_SPEED[cruise] * clampf(move.y, 0.5, 1.0) if cruise == Gait.WALK else GAIT_SPEED[cruise]
			rate = accel if speed < want else decel
	elif move.y < -0.2:
		_sprint_time = 0.0
		if speed > 0.25:
			want = 0.0
			rate = brake_decel
		else:
			want = GAIT_SPEED[Gait.BACK]
			rate = 1.2
	else:
		_sprint_time = 0.0
	speed = move_toward(speed, want, rate * delta)
	if absf(speed) < 0.02 and want == 0.0:
		speed = 0.0
	_update_gait(want)
	_update_stamina(delta)

	# --- steering ---------------------------------------------------------------------
	var steer := -move.x
	var target_rate := deg_to_rad(_turn_rate_for(absf(speed))) * steer
	if speed < -0.05:
		target_rate = -target_rate * 0.6  # backing: the haunches swing the other way
	turn_rate = move_toward(turn_rate, target_rate, delta * 4.0)
	rotate_y(turn_rate * delta)

	# --- motion -------------------------------------------------------------------------
	var fwd := forward()
	var horiz := fwd * speed
	if speed > 0.0 and _water_depth_at(global_position + fwd * 1.6) > max_wade_depth:
		horiz = Vector3.ZERO
		speed = 0.0
	if speed > 0.1 and is_on_floor() and _drop_ahead(fwd):
		horiz = Vector3.ZERO
		speed = 0.0
	velocity.x = horiz.x
	velocity.z = horiz.z
	if is_on_floor() and horiz.length_squared() > 0.01:
		_try_step_up(horiz * delta)
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	# A wall or tree stops the horse rather than letting it grind along at full speed.
	var real := Vector2(get_real_velocity().x, get_real_velocity().z).length()
	if absf(speed) > 1.0 and real < absf(speed) * 0.35 and get_slide_collision_count() > 0:
		speed = move_toward(speed, 0.0, brake_decel * 2.0 * delta)
	_update_slope(delta)


func _drive_input() -> Dictionary:
	if drive is Dictionary:
		return drive
	if _come_target != Vector3.INF:
		while not recall_path.is_empty() and CampaignUtil.flat_dist(global_position, recall_path[0]) < 2.5:
			recall_path.remove_at(0)
		var goal := recall_path[0] if not recall_path.is_empty() else _come_target
		var to := goal - global_position
		to.y = 0.0
		if recall_path.is_empty() and to.length() < 1.8:
			_come_target = Vector3.INF
			return {}
		var ang := forward().signed_angle_to(to.normalized(), Vector3.UP)
		var steer := clampf(-ang * 2.0, -1.0, 1.0)
		# Local feelers steer around trunks without suppressing physical collision.
		var space := get_world_3d().direct_space_state
		var ahead := global_position + Vector3.UP * 0.9
		if not LineOfSight.is_clear(space, ahead, ahead + forward() * 3.5, [get_rid()], Layers.WORLD):
			var left_clear := LineOfSight.is_clear(space, ahead, ahead + global_basis.x * -3.0, [get_rid()], Layers.WORLD)
			steer = -1.0 if left_clear else 1.0
			ang = 2.0
		var fast := to.length() > 25.0
		cruise = Gait.TROT
		return {"move": Vector2(steer, 1.0 if absf(ang) < 1.2 else 0.0), "sprint": fast}
	return {}


func _turn_rate_for(spd: float) -> float:
	if spd < 0.3:
		return turn_rate_stand
	if spd < 2.5:
		return turn_rate_walk
	if spd < 4.5:
		return turn_rate_trot
	if spd < 7.5:
		return turn_rate_canter
	return turn_rate_gallop


func _update_gait(want: float) -> void:
	var g: int
	var s := speed
	if s < -0.1:
		g = Gait.BACK
	elif s < 0.15 and want <= 0.0:
		g = Gait.STAND
	elif s < 2.5:
		g = Gait.WALK
	elif s < 4.6:
		g = Gait.TROT
	elif s < 7.6:
		g = Gait.CANTER
	else:
		g = Gait.GALLOP
	if g != gait:
		gait = g
		gait_changed.emit(g)


func _update_stamina(delta: float) -> void:
	match gait:
		Gait.GALLOP:
			stamina = maxf(0.0, stamina - gallop_drain * delta)
		Gait.CANTER:
			stamina = maxf(0.0, stamina - canter_drain * delta)
		_:
			stamina = minf(max_stamina, stamina + stamina_regen * delta)


## True when the ground just ahead falls away: the horse will not run off a cliff,
## a bridge side or a high wall. Slopes it can walk are well inside the allowance.
func _drop_ahead(fwd: Vector3) -> bool:
	var ahead := 1.7 + absf(speed) * 0.2
	var from := global_position + fwd * ahead + Vector3.UP * 1.2
	var allowed := 1.0 + ahead * 0.85
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (1.2 + allowed), Layers.WORLD, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Lifts the horse over kerbs and rubble that its rounded legs would catch on.
func _try_step_up(motion: Vector3) -> void:
	var probe := motion.normalized() * maxf(motion.length(), 0.08)
	var hit := KinematicCollision3D.new()
	# Ledges only: never climb onto people or other animals.
	if not test_move(global_transform, probe, hit) or hit.get_normal().y > 0.7 or hit.get_collider() is CharacterBody3D:
		return
	var t := global_transform
	var up := Vector3.UP * step_height
	if test_move(t, up):
		return
	t.origin += up
	var ahead := motion.normalized() * 0.3
	if test_move(t, ahead):
		return
	t.origin += ahead
	var down := KinematicCollision3D.new()
	if not test_move(t, -up - Vector3.UP * 0.05, down) or down.get_normal().y < 0.7 or down.get_collider() is CharacterBody3D:
		return
	var lift := t.origin.y + down.get_travel().y - global_position.y
	if lift > 0.03:
		global_position.y += lift + 0.01


func water_depth_here() -> float:
	return _water_depth_at(global_position)


func _water_depth_at(p: Vector3) -> float:
	if not PlayerController.terrain_height_query.is_valid():
		return 0.0
	var h := float(PlayerController.terrain_height_query.call(p.x, p.z))
	# Bridge decks and solid shallow crossings are above the submerged terrain.
	# Sample the reachable surface near hoof height, never a roof high overhead.
	var ground := _ground_at(get_world_3d().direct_space_state, p)
	if not is_nan(ground):
		h = maxf(h, ground)
	return maxf(0.0, water_level - h)


## Pitch the body to the ground under the fore and hind hooves (presentation only;
## the collision body stays upright).
func _update_slope(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var fwd := forward()
	var hf := _ground_at(space, global_position + fwd * 1.0)
	var hb := _ground_at(space, global_position - fwd * 1.0)
	var target := 0.0
	var drop := 0.0
	if not is_nan(hf) and not is_nan(hb):
		target = clampf(atan2(hf - hb, 2.0), deg_to_rad(-22.0), deg_to_rad(22.0))
		# The body rests on its collision margin, and on a bump or in a dip its middle is
		# off the line between the hooves: sit the model on the ground under the hooves.
		drop = clampf(global_position.y - (hf + hb) * 0.5, -0.15, 0.3)
	slope_pitch = lerp_angle(slope_pitch, target, clampf(delta * 6.0, 0.0, 1.0))
	body_drop = lerpf(body_drop, drop, clampf(delta * 6.0, 0.0, 1.0))


func _ground_at(space: PhysicsDirectSpaceState3D, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.2, p + Vector3.DOWN * 1.6, Layers.WORLD, [get_rid()])
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if not hit.is_empty() else NAN


func _recall_route(target: Vector3) -> PackedVector3Array:
	# Clear sight across deep water is not a traversable direct route.
	var steps:=maxi(1,int(global_position.distance_to(target)/4.0))
	for i in range(1,steps):
		if _water_depth_at(global_position.lerp(target,float(i)/steps))>max_wade_depth and Battlefield.route:
			return Battlefield.route.route(global_position,target)
	return Battlefield.route_to(global_position,target)
