class_name SoldierBrain
extends Node
## Drives one campaign soldier, allied or enemy, the way SimBot drives a wanderer:
## movement through the avatar's input_override and every blow through Combat
## requests, so soldiers obey the same rules (cooldowns, stamina, cones, walls)
## as the commander. Lives as the "Brain" child of a bot PlayerController.
##
## Modes
##   HOLD      stand at hold_pos; defend yourself, then return
##   FOLLOW    keep a formation slot behind the commander (the Army gives the slot)
##   REGROUP   walk a route back to the commander from far away
##   DORMANT   enemy waiting at its post until the encounter starts
##   PATROL    spy walking its route; detects, alerts nearby spies, then fights
##   ADVANCE   enemy marching on a point; fights anything that comes close
##   COMBAT    pick a target (spread over enemies, help hurt friends), close in,
##             cut, sidestep around the press, dodge a raised blade, fall back
##             briefly when badly hurt
##   RETREAT   stop fighting and run for an escape point
##   MOUNT     walk to an assigned horse and climb into the saddle
##   MOUNTED   ride (the horse steers to the slot)
##   DEAD

enum Mode { HOLD, FOLLOW, REGROUP, DORMANT, PATROL, ADVANCE, COMBAT, RETREAT, MOUNT, MOUNTED, DEAD }

const MODE_NAMES := ["hold", "follow", "regroup", "dormant", "patrol", "advance", "combat", "retreat", "mount", "mounted", "dead"]

## Living brains, for quick queries (alerts, tests). Spatial queries, target slots and
## target choice live in Battlefield; who may target whom lives in Factions.
static var all: Array[SoldierBrain] = []
## target id -> recent strike times; the commander is never mobbed by more than
## `max_attackers_on_leader` blades at once (the rest circle and wait their turn).
static var _strikes := {}
static var max_attackers_on_leader := 1

signal died(brain: SoldierBrain)

var team := "kingdom"
var mode: int = Mode.HOLD
## The order to return to after a fight (HOLD or FOLLOW for allies; ADVANCE/PATROL for enemies).
var order: int = Mode.HOLD
var avatar: PlayerController
var army: Node          ## Army (allies)
var encounter: Node     ## Encounter (enemies)
var soldier_id := -1    ## roster id (allies) / spawn index (enemies)
## AI flavour and identity: "line" (the commander's army), "guard" (garrison post),
## "spy", "captain", "raider". `mission_id` ties an enemy to its campaign mission (-1 = none).
var role := "line"
var mission_id := -1

@export var sight_range := 26.0
@export var fov_degrees := 120.0
@export var hear_range := 6.0
## Allies engage hostiles this close to themselves (or to the commander).
@export var engage_radius := 28.0
## Enemies in a battle know where the defenders are; they look this far.
@export var battle_awareness := 70.0
@export var aggression := 0.6
@export var alert_radius := 24.0

var hold_pos := Vector3.INF
var hold_yaw := NAN
var patrol := PackedVector3Array()
var advance_target := Vector3.INF
var retreat_target := Vector3.INF
var target_id := -1
var horse: Horse
var paused := false
var weapons_free := true
## Approach slot held around `slot_target` (-1 = none), and whether the soldier is
## waiting for one because the target is already surrounded.
var slot_idx := -1
var slot_target := -1
var waiting := false
## The friend this soldier is going to help (-1 = none).
var assist_of := -1
## Where an enemy marching in lines up relative to the defenders (spreads the approach).
var lane_offset := Vector3.ZERO

var _exclude := {}       ## target id -> time until which it is off my list (stayed ringed)
var _retarget_at := 0.0
var _force_retarget := true
var _wait_t := 0.0
var _slot_check := 0.0
var _attack_t := 0.0
var _push := Vector3.ZERO
var _push_t := 0.0
var _nav_t := 0.0
var _rng := RandomNumberGenerator.new()
var _think := 0.0
var _goal := Vector3.INF
var _face := Vector3.INF
var _sprint := false
var _strafe := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _patrol_i := 0
var _patrol_dir := 1
var _stuck_t := 0.0
var _check_pos := Vector3.ZERO
var _check_t := 0.0
var _sidestep := 0.0
var _fallback_until := -INF
var _last_hurt := -INF
var _mount_t := -1.0
var _mount_from := Vector3.ZERO


func _ready() -> void:
	avatar = get_parent()
	avatar.input_override = {}
	_rng.seed = hash(avatar.display_name) + soldier_id * 7919
	_think = _rng.randf() * 0.25
	process_physics_priority = 20  # after horses move, so a rider sits in the moved saddle
	all.append(self)
	Combat.damage_dealt.connect(_on_damage)
	Combat.player_defeated.connect(_on_defeated)


func _exit_tree() -> void:
	all.erase(self)
	_set_target(-1)


func mode_name() -> String:
	return MODE_NAMES[mode]


func is_alive() -> bool:
	return mode != Mode.DEAD and avatar != null and not avatar.is_defeated


func rig() -> SoldierRig:
	var v := avatar.get_node_or_null("AvatarVisual") as AvatarVisual
	return v.human_rig as SoldierRig if v else null


# --- orders --------------------------------------------------------------------------------------

func set_order(m: int) -> void:
	if mode == Mode.DEAD:
		return
	order = m
	if mode == Mode.MOUNTED or mode == Mode.MOUNT:
		if m == Mode.HOLD:
			dismount()
		else:
			return
	if mode != Mode.COMBAT or m == Mode.RETREAT:
		_enter(m)


func _enter(m: int) -> void:
	if mode == Mode.DEAD:
		return
	mode = m
	_path = PackedVector3Array()
	_path_i = 0
	_goal = Vector3.INF
	_face = Vector3.INF
	if m != Mode.COMBAT:
		_set_target(-1)
	var r := rig()
	if r:
		r.combat_ready = m == Mode.COMBAT


func _set_target(id: int) -> void:
	if id == target_id:
		return
	Battlefield.release(self)
	Battlefield.note_target(avatar.player_id, target_id, id)
	target_id = id
	waiting = false
	_wait_t = 0.0
	_slot_check = 0.0
	if id < 0:
		assist_of = -1


## Stop fighting and run for `point` (spies after the kill target), along `path`.
func retreat_to(point: Vector3, path := PackedVector3Array()) -> void:
	if mode == Mode.DEAD:
		return
	if mode == Mode.MOUNTED or mode == Mode.MOUNT:
		dismount()
	order = Mode.RETREAT
	_enter(Mode.RETREAT)
	retreat_target = point
	_path = path
	_path_i = 0
	_goal = point
	_sprint = true


## Alerted by a friend (spies) or by being hit.
func alert(threat_id: int, direct := false) -> void:
	if not weapons_free or mode in [Mode.DEAD, Mode.RETREAT, Mode.MOUNT] or paused:
		return
	if mode == Mode.MOUNTED:
		dismount()
	if mode != Mode.COMBAT:
		_enter(Mode.COMBAT)
		# Choose among the threats on the next think (staggered), not all the same one.
		_force_retarget = true
		_think = minf(_think, _rng.randf_range(0.0, 0.25))
	if target_id < 0 and threat_id >= 0 and _valid_target(threat_id) and (direct or Battlefield.occupancy(threat_id) < Battlefield.cap_for(threat_id)):
		_set_target(threat_id)
		_force_retarget = false
		_retarget_at = Combat.now() + 1.5


# --- frame ---------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if avatar == null or not is_instance_valid(avatar):
		return
	if mode == Mode.DEAD or avatar.is_defeated or not PlayerState.is_alive_state(GameState.get_state(avatar.player_id)):
		avatar.input_override = {}
		return
	if paused:
		avatar.input_override = {}
		if mode == Mode.MOUNTED and horse:
			horse.drive = {}
			_sit_in_saddle()
		return
	if mode == Mode.COMBAT and target_id == GameState.local_player_id and Combat.are_hostile(avatar.player_id, target_id):
		Combat.direct_enemy(avatar, "mission.%d" % mission_id, "elite" if role == "captain" else "standard")
		return
	if mode == Mode.MOUNTED:
		_ride(delta)
		return
	if mode == Mode.MOUNT and _mount_t >= 0.0:
		_climb(delta)
		return
	_think -= delta
	if _think <= 0.0:
		_decide()
		# Physics level of detail by distance from the camera (never while fighting up close).
		var cam := avatar.get_viewport().get_camera_3d()
		var dc := cam.global_position.distance_to(avatar.global_position) if cam else 0.0
		avatar.physics_lod = 1 if dc < 30.0 else (2 if dc < 80.0 else 3)
		_think = _think_interval(dc)
	# Blows are timed on their own clock, so hits stay reliable however seldom the brain thinks.
	if mode == Mode.COMBAT and target_id >= 0:
		_attack_t -= delta
		if _attack_t <= 0.0:
			_attack_t = 0.12
			_try_attack()
	_steer(delta)


## AI update rate: quick while a blade is near, slower for marchers, slowest for idle or
## distant soldiers (the camera distance `dc` and the fight decide).
func _think_interval(dc: float) -> float:
	var jitter := _rng.randf_range(0.0, 0.05)
	match mode:
		Mode.COMBAT:
			if target_id >= 0 and waiting:
				return 0.3 + jitter
			var t := Combat.avatar(target_id)
			if t != null and _flat(t.global_position) < 6.0:
				return 0.2 + jitter
			return 0.3 + jitter
		Mode.HOLD, Mode.FOLLOW, Mode.DORMANT, Mode.PATROL:
			return (0.4 if dc < 60.0 else (0.7 if dc < 140.0 else 1.0)) + jitter
	return 0.25 + jitter


func _decide() -> void:
	match mode:
		Mode.HOLD:
			var threat := _nearest_hostile(14.0, false) if weapons_free else -1
			if threat >= 0:
				alert(threat)
				return
			_goal = hold_pos if hold_pos != Vector3.INF else Vector3.INF
			_sprint = false
			# A sentry back on its post turns to face its watch direction.
			if not is_nan(hold_yaw) and hold_pos != Vector3.INF and _flat(hold_pos) < 0.8:
				_face = avatar.global_position + Vector3(-sin(hold_yaw), 0.0, -cos(hold_yaw)) * 10.0
			else:
				_face = Vector3.INF
		Mode.FOLLOW, Mode.REGROUP:
			var threat := _nearest_hostile(engage_radius, false) if weapons_free else -1
			if weapons_free and threat < 0 and army and army.leader:
				var lp: Vector3 = army.leader.global_position
				var t2 := _nearest_hostile_to(lp, 22.0)
				if t2 >= 0 and _flat(lp) < 45.0:
					threat = t2
			if threat >= 0:
				alert(threat)
				return
			_decide_follow()
		Mode.DORMANT:
			_goal = Vector3.INF
		Mode.PATROL:
			var seen := _detect() if weapons_free else -1
			if seen >= 0:
				alert(seen)
				_alert_friends(seen)
				return
			_decide_patrol()
		Mode.ADVANCE:
			var threat := _nearest_hostile(20.0, false)
			if threat >= 0:
				alert(threat)
				return
			_goal = advance_target
			_sprint = false
			var now := Combat.now()
			if now >= _nav_t and _flat(advance_target) > 12.0:
				_nav_t = now + 2.0
				if Battlefield.open_line(avatar.global_position, advance_target):
					_path = PackedVector3Array()
				else:
					_path = Battlefield.route_to(avatar.global_position, advance_target)
					_path_i = 0
		Mode.COMBAT:
			_decide_combat()
		Mode.RETREAT:
			_goal = retreat_target
			_sprint = true
		Mode.MOUNT:
			_decide_mount()


# --- perception -----------------------------------------------------------------------------------

func _valid_target(id: int) -> bool:
	if id < 0 or not Combat.are_hostile(avatar.player_id, id):
		return false
	if not PlayerState.is_alive_state(GameState.get_state(id)):
		return false
	var av := Combat.avatar(id)
	return av != null and not av.is_defeated


func _nearest_hostile(radius: float, need_sight: bool) -> int:
	return _nearest_hostile_to(avatar.global_position, radius, need_sight)


func _nearest_hostile_to(p: Vector3, radius: float, _need_sight := false) -> int:
	return Battlefield.nearest_hostile(self, radius, p)


func _sees(other: PlayerController) -> bool:
	var space := avatar.get_world_3d().direct_space_state
	var eye := avatar.global_position + Vector3.UP * 1.6
	var res := LineOfSight.can_see(space, eye, avatar.forward(), other.global_position, other.current_height(),
		{"max_distance": sight_range, "exclude": [avatar.get_rid(), other.get_rid()]})
	return res["visible"]


## A spy notices someone: close enough to hear, or in its view cone with a clear line.
func _detect() -> int:
	for id in Battlefield.near_ids(avatar.global_position, sight_range):
		if not Battlefield.engageable(self, id) or not _valid_target(id):
			continue
		var av := Combat.avatar(id)
		var to := av.global_position - avatar.global_position
		var d := Vector2(to.x, to.z).length()
		if d > sight_range or absf(to.y) > 6.0:
			continue
		if d < hear_range and _clear_line(av.global_position):
			return id
		var ang := rad_to_deg(avatar.forward().angle_to(Vector3(to.x, 0, to.z).normalized()))
		if ang <= fov_degrees * 0.5 and _sees(av):
			return id
	return -1


func _alert_friends(threat_id: int) -> void:
	for b in all:
		if b == self or b.team != team or not b.is_alive():
			continue
		if b.avatar.global_position.distance_to(avatar.global_position) < alert_radius:
			b.alert(threat_id)


func _on_damage(e: Dictionary) -> void:
	if avatar == null or e["target"] != avatar.player_id or mode == Mode.DEAD:
		return
	_last_hurt = Combat.now()
	var src: int = e["source"]
	if mode == Mode.RETREAT:
		return
	alert(src, true)
	if mode == Mode.COMBAT and src >= 0 and src != target_id and _valid_target(src):
		var cur := Combat.avatar(target_id)
		var att := Combat.avatar(src)
		if cur == null or (att and _flat(att.global_position) + 1.5 < _flat(cur.global_position)):
			_set_target(src)
	if team != Factions.KINGDOM:
		_alert_friends(src)


func _on_defeated(e: Dictionary) -> void:
	if avatar == null:
		return
	if e["victim"] == avatar.player_id:
		if mode == Mode.MOUNTED or mode == Mode.MOUNT:
			_leave_horse(true)
		_set_target(-1)
		mode = Mode.DEAD
		avatar.input_override = {}
		var r := rig()
		if r:
			r.combat_ready = false
		died.emit(self)
	elif e["victim"] == target_id:
		# The fight is over: look for another, or for a friend who still needs a hand.
		_set_target(-1)
		_force_retarget = true
		_think = minf(_think, _rng.randf_range(0.0, 0.3))
	elif mode == Mode.COMBAT:
		# Somebody nearby fell (a friend, or an enemy that was hounding one): reassess.
		var v := Combat.avatar(int(e["victim"]))
		if v != null and _flat(v.global_position) < 30.0:
			_force_retarget = true
			_think = minf(_think, _rng.randf_range(0.1, 0.6))


# --- following -------------------------------------------------------------------------------------

func _decide_follow() -> void:
	if army == null or army.leader == null:
		_goal = Vector3.INF
		return
	var slot: Vector3 = army.slot_position(self)
	var d := _flat(slot)
	if mode == Mode.REGROUP:
		if d < 10.0:
			_enter(Mode.FOLLOW)
		elif _path.is_empty() or _path_i >= _path.size() or _path[_path.size() - 1].distance_to(slot) > 25.0:
			# His own footsteps when one is in reach (a walked, known-good path); else a route.
			_path = army.crumbs_from(avatar.global_position)
			if _path.is_empty() or _path[_path.size() - 1].distance_to(slot) > 25.0:
				_path = army.route_to(avatar.global_position, slot)
			_path_i = 0
			_goal = slot
		_sprint = true
		return
	if d > 45.0:
		_enter(Mode.REGROUP)
		return
	if d > 6.0 and not _clear_line(slot):
		# Walls in the way: walk the commander's own footsteps.
		var crumbs: PackedVector3Array = army.crumbs_from(avatar.global_position)
		if crumbs.size() > 0:
			_path = crumbs
			_path_i = 0
			_goal = crumbs[0]
			_sprint = d > 8.0
			return
	_path = PackedVector3Array()
	_goal = slot if d > 1.2 else Vector3.INF
	if _goal == Vector3.INF and army.leader:
		_face = avatar.global_position - Basis(Vector3.UP, army.travel_yaw).z * 20.0
	var lead_speed: float = Vector2(army.leader.velocity.x, army.leader.velocity.z).length()
	_sprint = d > 7.0 or lead_speed > avatar.walk_speed + 0.5


func _clear_line(p: Vector3) -> bool:
	var space := avatar.get_world_3d().direct_space_state
	var a := avatar.global_position + Vector3.UP * 1.0
	var b := p + Vector3.UP * 1.0
	return LineOfSight.is_clear(space, a, b, [avatar.get_rid()], Layers.WORLD)


# --- patrol -----------------------------------------------------------------------------------------

func _decide_patrol() -> void:
	_sprint = false
	if patrol.is_empty():
		_goal = Vector3.INF
		return
	var p := patrol[_patrol_i]
	if _flat(p) < 2.0:
		if patrol.size() > 1:
			if _patrol_i + _patrol_dir < 0 or _patrol_i + _patrol_dir >= patrol.size():
				_patrol_dir = -_patrol_dir
			_patrol_i += _patrol_dir
		p = patrol[_patrol_i]
	_goal = p


# --- combat -----------------------------------------------------------------------------------------

func _decide_combat() -> void:
	var now := Combat.now()
	var radius := engage_radius + 8.0 if team == Factions.KINGDOM else battle_awareness
	var t := Combat.avatar(target_id) if target_id >= 0 else null
	var d_now := _flat(t.global_position) if t else INF
	var lost := not _valid_target(target_id) or not Battlefield.engageable(self, target_id)
	# Keep a fight in progress; look around only on loss, on an event (a death nearby), or
	# now and then when not yet locked in melee.
	var rescue := team == Factions.KINGDOM and Battlefield.leader_critical()
	if lost or _force_retarget or (now >= _retarget_at and (d_now > 3.2 or rescue)):
		_force_retarget = false
		_retarget_at = now + _rng.randf_range(1.4, 2.8)
		if target_id >= 0 and lost:
			_set_target(-1)
		var pick := Battlefield.pick_target(self, radius, _exclude)
		var helping := false
		if pick < 0:
			pick = Battlefield.find_assist(self)
			helping = pick >= 0
		if not helping:
			assist_of = -1
		if pick != target_id:
			_set_target(pick)
	if target_id < 0:
		_end_combat()
		return
	t = Combat.avatar(target_id)
	var tp := t.global_position
	var d := _flat(tp)
	if team == Factions.KINGDOM and army and army.leader and order == Mode.FOLLOW:
		# Do not chase a runner across the kingdom: stay near the commander.
		if Vector2(tp.x - army.leader.global_position.x, tp.z - army.leader.global_position.z).length() > engage_radius + 20.0 and d > 12.0:
			_set_target(-1)
			_end_combat()
			return
	_face = tp
	var hurt := avatar.combatant.health < avatar.combatant.max_health * 0.25
	if hurt and now - _last_hurt < 2.0 and now > _fallback_until + 6.0 and _rng.randf() < 0.35:
		_fallback_until = now + 2.2
	if now < _fallback_until:
		var away := avatar.global_position - tp
		away.y = 0.0
		_goal = avatar.global_position + away.normalized() * 6.0
		_path = PackedVector3Array()
		_sprint = true
		return
	# Hold an approach slot around the target (not its exact position), at weapon range.
	if slot_idx < 0 or slot_target != target_id or now >= _slot_check:
		var had := slot_idx
		slot_idx = Battlefield.claim(self, target_id)
		slot_target = target_id if slot_idx >= 0 else -1
		_slot_check = now + _rng.randf_range(0.6, 1.0)
		if had >= 0 and slot_idx >= 0 and had != slot_idx:
			_path = PackedVector3Array()
	waiting = slot_idx < 0
	var dest: Vector3
	if waiting:
		_wait_t += _think_dt()
		dest = Battlefield.wait_spot(self, target_id)
		# Still ringed after a while: leave it to the others and find another fight; if
		# there is none, keep waiting for a slot to open.
		if _wait_t > 2.5:
			var tid := target_id
			_exclude[tid] = now + 6.0
			var alt := Battlefield.pick_target(self, radius, _exclude)
			if alt >= 0:
				_set_target(alt)
				return
			_exclude.erase(tid)
			_wait_t = 0.0
	else:
		_wait_t = 0.0
		dest = Battlefield.slot_pos(target_id, slot_idx)
	var dd := _flat(dest)
	if dd > 0.6 or d > Battlefield.attack_range:
		_goal = dest
		_sprint = d > 6.0
		_strafe = 0.0
		# Walls in the way: go round through the route network.
		if dd > 7.0 and now >= _nav_t:
			_nav_t = now + 1.2
			if Battlefield.open_line(avatar.global_position, dest):
				_path = PackedVector3Array()
			else:
				_path = Battlefield.route_to(avatar.global_position, dest)
				_path_i = 0
		elif dd <= 7.0:
			_path = PackedVector3Array()
	else:
		_goal = Vector3.INF
		_path = PackedVector3Array()
		_strafe = (1.0 if soldier_id % 2 == 0 else -1.0) * 0.2
	if d < 1.1:
		var back := avatar.global_position - tp
		back.y = 0.0
		_goal = avatar.global_position + back.normalized() * 1.0
		_sprint = false


func _think_dt() -> float:
	return maxf(_think, 0.2)


## Cut, or raise the guard against a coming blow; run on a short clock of its own.
func _try_attack() -> void:
	if target_id == GameState.local_player_id and Combat.are_hostile(avatar.player_id, target_id):
		Combat.direct_enemy(avatar, "mission.%d" % mission_id, "elite" if role == "captain" else "standard")
		return
	var me := avatar.player_id
	if Combat.is_busy(me) or Combat.is_transforming(me) or not _valid_target(target_id):
		return
	var t := Combat.avatar(target_id)
	var d := _flat(t.global_position)
	var pending := Combat.pending_ability(target_id)
	if d < 3.0 and pending in ["sword_strike", "sword_finisher", "claw", "heavy_strike"] and avatar.stamina > 40.0 and _rng.randf() < 0.09:
		Combat.request_action(me, "ability_1")
		return
	if d < Battlefield.attack_range and Combat.cooldown_remaining(me, "sword_strike") <= 0.0 and _rng.randf() < aggression * 0.45:
		if not _strike_allowed(target_id):
			return
		_face_now(t.global_position)
		if Combat.request_action(me, "attack")["ok"]:
			_note_strike(target_id)


func _strike_allowed(tid: int) -> bool:
	if tid != GameState.local_player_id:
		return true
	var now := Combat.now()
	var recent := 0
	for t in _strikes.get(tid, []):
		if now - float(t) < 1.1:
			recent += 1
	return recent < max_attackers_on_leader


func _note_strike(tid: int) -> void:
	var now := Combat.now()
	var keep: Array = []
	for t in _strikes.get(tid, []):
		if now - float(t) < 1.1:
			keep.append(t)
	keep.append(now)
	_strikes[tid] = keep


func _end_combat() -> void:
	_enter(order if order != Mode.COMBAT else Mode.HOLD)
	if mode == Mode.HOLD and hold_pos == Vector3.INF:
		hold_pos = avatar.global_position


# --- mounting ---------------------------------------------------------------------------------------

## The Army assigns a free horse; the soldier walks to its near side and climbs up.
func mount(h: Horse) -> void:
	if mode == Mode.DEAD or h == null:
		return
	horse = h
	# The horse stands and waits for its rider (no longer trailing the company).
	h.set_dormant(false)
	h.drive = {}
	_mount_t = -1.0
	_enter(Mode.MOUNT)


func _decide_mount() -> void:
	if horse == null or not is_instance_valid(horse) or (horse.rider != null and horse.rider != avatar):
		horse = null
		_enter(order)
		return
	var spot := horse.global_transform * Vector3(-0.95, 0.0, -0.3)
	_goal = spot
	_sprint = _flat(spot) > 6.0
	if _flat(spot) < 1.0:
		_start_climb()


func _start_climb() -> void:
	horse.set_rider(avatar)
	horse.drive = {}
	avatar.input_override = {}
	avatar.riding = true
	avatar.collision.set_deferred("disabled", true)
	avatar.velocity = Vector3.ZERO
	_mount_from = avatar.global_position
	_mount_t = 0.0
	var r := rig()
	if r:
		r.hold("mount", 0.8)


func _climb(delta: float) -> void:
	_mount_t += delta
	var u := clampf(_mount_t / 0.8, 0.0, 1.0)
	var rr := rig()
	if rr:
		rr.ride_with(horse)
	var seat := _seat_point()
	avatar.global_position = _mount_from.lerp(seat, smoothstep(0.0, 1.0, u)) + Vector3.UP * sin(u * PI) * 0.3
	avatar.rotation.y = lerp_angle(avatar.rotation.y, horse.rotation.y, u)
	if u >= 1.0:
		_mount_t = -1.0
		mode = Mode.MOUNTED
		var r := rig()
		if r:
			r.hold("ride")


## Where the avatar must stand for its pelvis to sit on the saddle (the same rule the
## commander's Rider uses: the pelvis a little above the horse's seat point).
func _seat_point() -> Vector3:
	var hr := horse.get_node_or_null("Rig") as HorseRig
	if hr == null or hr.seat == null:
		return horse.global_position + Vector3.UP * 0.7
	var seat := hr.seat.global_transform
	var want_pelvis := seat.origin + seat.basis.y * Rider.PELVIS_ABOVE_SEAT
	var r := rig()
	if r == null or r.skeleton == null:
		return seat.origin - Vector3.UP * 0.52
	return avatar.global_position + (want_pelvis - r.bone_world("pelvis"))


func _sit_in_saddle() -> void:
	if horse == null or not is_instance_valid(horse):
		return
	var r := rig()
	if r:
		r.ride_with(horse)
	avatar.global_position = _seat_point()
	avatar.rotation.y = horse.rotation.y
	avatar.velocity = horse.velocity


func _ride(delta: float) -> void:
	if horse == null or not is_instance_valid(horse):
		_leave_horse(false)
		return
	_think -= delta
	if _think <= 0.0:
		_think = 0.25
		var threat := _nearest_hostile(engage_radius * 0.8, false) if weapons_free else -1
		if threat >= 0:
			dismount()
			alert(threat)
			return
	var drive := {}
	if army and army.leader and order == Mode.FOLLOW:
		var slot: Vector3 = army.slot_position(self)
		var to := slot - horse.global_position
		to.y = 0.0
		if to.length() > 2.5:
			var ang := horse.forward().signed_angle_to(to.normalized(), Vector3.UP)
			var steer := clampf(-ang * 2.0, -1.0, 1.0)
			var lead_speed: float = Vector2(army.leader.velocity.x, army.leader.velocity.z).length()
			horse.cruise = Horse.Gait.TROT if lead_speed > 2.4 or to.length() > 8.0 else Horse.Gait.WALK
			drive = {"move": Vector2(steer, 1.0 if absf(ang) < 1.3 else 0.15), "sprint": to.length() > 10.0 or lead_speed > 5.0}
	horse.drive = drive
	_sit_in_saddle()
	avatar.input_override = {}


func dismount() -> void:
	if mode == Mode.MOUNT and _mount_t < 0.0:
		horse = null
		_enter(order)
		return
	if mode != Mode.MOUNTED and mode != Mode.MOUNT:
		return
	_leave_horse(false)
	_enter(order)


func _leave_horse(dead: bool) -> void:
	var h := horse
	horse = null
	_mount_t = -1.0
	avatar.riding = false
	avatar.collision.set_deferred("disabled", false)
	var r := rig()
	if r and not dead:
		r.release()
	if h and is_instance_valid(h):
		if h.rider == avatar:
			h.set_rider(null)
		h.drive = null
		var side := h.global_transform * Vector3(-1.0, 0.0, -0.2)
		var ground := side
		var space := avatar.get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(side + Vector3.UP * 2.0, side - Vector3.UP * 4.0, Layers.WORLD))
		if not hit.is_empty():
			ground = hit["position"]
		avatar.global_position = ground + Vector3.UP * 0.05
		avatar.velocity = Vector3.ZERO


# --- steering ---------------------------------------------------------------------------------------

func _steer(delta: float) -> void:
	var goal := _goal
	if not _path.is_empty() and _path_i < _path.size():
		goal = _path[_path_i]
		var reach := 3.0 if _path_i < _path.size() - 1 else 1.4
		if _flat(goal) < reach:
			_path_i += 1
			goal = _path[_path_i] if _path_i < _path.size() else _goal
	var move := Vector3.ZERO
	if goal != Vector3.INF:
		var to := goal - avatar.global_position
		to.y = 0.0
		if to.length() > 0.6:
			move = to.normalized()
	# Keep personal space between friends (refreshed ten times a second, applied every frame).
	_push_t -= delta
	if _push_t <= 0.0:
		_push_t = 0.1
		_push = _separation()
	var push := _push
	var face := _face if _face != Vector3.INF else (goal if goal != Vector3.INF else Vector3.INF)
	if mode == Mode.COMBAT and target_id >= 0:
		var t := Combat.avatar(target_id)
		if t:
			face = t.global_position
			if move == Vector3.ZERO and _strafe != 0.0:
				var side := (t.global_position - avatar.global_position).cross(Vector3.UP).normalized()
				move = side * _strafe
	move += push * 1.2
	if move.length() < 0.05 and face == Vector3.INF:
		avatar.input_override = {}
		_check_t = 0.0
		return
	if face != Vector3.INF and not Combat.is_busy(avatar.player_id):
		var d := face - avatar.global_position
		if Vector2(d.x, d.z).length() > 0.05:
			var yaw := atan2(-d.x, -d.z)
			avatar.set_look(lerp_angle(avatar.rotation.y, yaw, clampf(delta * 8.0, 0.0, 1.0)), 0.0)
	# Stuck: sidestep and hop.
	_check_t += delta
	if _check_t >= 0.8:
		var moved := avatar.global_position.distance_to(_check_pos)
		_stuck_t = _stuck_t + _check_t if (moved < 0.4 and move.length() > 0.3) else 0.0
		_check_pos = avatar.global_position
		_check_t = 0.0
		if _stuck_t > 2.0:
			_sidestep = 0.9
			_stuck_t = 0.0
			if mode == Mode.PATROL and patrol.size() > 1:
				_patrol_dir = -_patrol_dir
	var local := Basis(Vector3.UP, avatar.rotation.y).inverse() * move.limit_length(1.0)
	var m := Vector2(local.x, -local.z)
	if _sidestep > 0.0:
		_sidestep -= delta
		m = Vector2(1.0 if soldier_id % 2 == 0 else -1.0, 0.5)
	avatar.input_override = {"move": m, "sprint": _sprint and m.y > 0.3, "jump": avatar.is_swimming,
		"jump_pressed": _sidestep > 0.6, "crouch": false}


## Push away from friends closer than the personal-space radius (tighter once in a
## fight slot, where slots are about a metre apart).
func _separation() -> Vector3:
	var push := Vector3.ZERO
	var mp := avatar.global_position
	var space := Battlefield.personal_space
	if mode == Mode.COMBAT and slot_idx >= 0:
		space = minf(space, 0.85)
	for id in Battlefield.near_ids(mp, space):
		var b := Battlefield.brain_of(id)
		if b == null or b == self or b.team != team or b.mode == Mode.MOUNTED:
			continue
		var off := mp - b.avatar.global_position
		off.y = 0.0
		var dl := off.length()
		if dl < space and dl > 0.01:
			push += off / dl * (space - dl)
	return push


func _face_now(p: Vector3) -> void:
	var d := p - avatar.global_position
	if Vector2(d.x, d.z).length() > 0.05:
		avatar.set_look(atan2(-d.x, -d.z), 0.0)


func _flat(p: Vector3) -> float:
	return Vector2(p.x - avatar.global_position.x, p.z - avatar.global_position.z).length()
