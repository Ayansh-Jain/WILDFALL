class_name SimBot
extends Node
## Simulated opponent for Phase 2 testing (no networking yet). Drives its
## avatar exactly like a player would: input_override for movement and Combat
## requests for actions, so every rule applies to bots too.
##
## WANDERER: explores along trails; flees revealed monsters using sprint,
##   dodge, ward and broken line of sight; `brave` ones fight back with swords.
## HUNTER: holds monster powers, stalks hidden, reveals when close, chases and
##   attacks; loses the target if line of sight stays broken.

enum Role { WANDERER, HUNTER }

## Shared walkable points (trail samples), set by Main.
static var waypoints := PackedVector3Array()

@export var role: Role = Role.WANDERER
@export var brave := false
## Night-time sight in the forest.
@export var sight_range := 28.0
## Seconds without line of sight before a hunter gives up the chase.
@export var lose_target_after := 4.0

var avatar: PlayerController
var mode := "wander"
var target_id := -1
var last_known := Vector3.INF

var _rng := RandomNumberGenerator.new()
var _goal := Vector3.INF
var _think := 0.0
var _last_seen_time := -INF
var _stuck_t := 0.0
var _check_pos := Vector3.ZERO
var _check_t := 0.0
var _sidestep := 0.0
var _calm_t := 0.0
var _threat_id := -1


func _ready() -> void:
	avatar = get_parent()
	avatar.input_override = {}
	_rng.seed = hash(avatar.display_name) + GameState.world_seed


func _physics_process(delta: float) -> void:
	if avatar.player_id < 0 or avatar.is_defeated or not PlayerState.is_alive_state(GameState.get_state(avatar.player_id)):
		avatar.input_override = {}
		mode = "wander"
		_goal = Vector3.INF
		return
	_think -= delta
	if _think <= 0.0:
		_think = 0.2
		if role == Role.HUNTER:
			_decide_hunter()
		else:
			_decide_wanderer()
	_steer(delta)


# --- perception -----------------------------------------------------------------------------

func _can_see(other: PlayerController) -> bool:
	var space := avatar.get_world_3d().direct_space_state
	var eye := avatar.global_position + Vector3.UP * avatar.current_height() * 0.9
	var res := LineOfSight.can_see(space, eye, avatar.forward(), other.global_position, other.current_height(),
		{"max_distance": sight_range, "exclude": [avatar.get_rid(), other.get_rid()]})
	return res["visible"]


func _others() -> Array:
	var out := []
	for id in Combat.actor_ids():
		if id == avatar.player_id:
			continue
		if PlayerState.is_alive_state(GameState.get_state(id)):
			out.append(id)
	return out


# --- wanderer -----------------------------------------------------------------------------------

func _decide_wanderer() -> void:
	var threat := -1
	var best := INF
	for id in _others():
		if not GameState.is_revealed(id):
			continue
		var other := Combat.avatar(id)
		var d := other.global_position.distance_to(avatar.global_position)
		var hurt_by := Combat.now() - float(avatar.combatant.recent_attackers.get(id, -INF)) < 3.0
		if d < best and (hurt_by or (d < 22.0 and _can_see(other))):
			best = d
			threat = id
	if threat < 0:
		_calm_t += 0.2
		if mode != "wander" and _calm_t > 3.0:
			mode = "wander"
			_goal = Vector3.INF
		if mode == "wander" and (_goal == Vector3.INF or _flat_dist(_goal) < 2.0):
			_goal = _random_waypoint(avatar.global_position, 8.0, 60.0)
		return
	_calm_t = 0.0
	_threat_id = threat
	var t := Combat.avatar(threat)
	var dist := t.global_position.distance_to(avatar.global_position)
	if brave and avatar.combatant.health > avatar.combatant.max_health * 0.4 and dist < 8.0:
		mode = "fight"
		target_id = threat
	else:
		mode = "flee"
		if _goal == Vector3.INF or _flat_dist(_goal) < 3.0 or _goal.distance_to(t.global_position) < 12.0:
			_goal = _escape_point(t.global_position)
	# Defensive tools, used when they matter: dodge any wind-up, ward when close.
	var pending := Combat.pending_ability(threat)
	if dist < 5.0 and pending in ["claw", "heavy_strike", "pounce"]:
		Combat.request_action(avatar.player_id, "ability_1")
	elif dist < 4.0:
		Combat.request_action(avatar.player_id, "ability_2")
	if mode == "fight":
		_face(t.global_position)
		if dist < 2.2:
			Combat.request_action(avatar.player_id, "attack")


func _escape_point(threat_pos: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_score := -INF
	var here := avatar.global_position
	for i in 24:
		var p := _random_waypoint(here, 12.0, 45.0)
		if i % 2 == 1:
			# Off-trail candidates: duck into the trees, away from the threat.
			var away_dir := (here - threat_pos)
			away_dir.y = 0.0
			var ang := atan2(away_dir.z, away_dir.x) + _rng.randf_range(-1.2, 1.2)
			p = here + Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(10.0, 25.0)
			p.y = here.y
		if p == Vector3.INF:
			continue
		var away := (p - here).normalized().dot((here - threat_pos).normalized())
		var score := p.distance_to(threat_pos) + away * 15.0
		if not _clear_between(threat_pos + Vector3.UP * 2.0, p + Vector3.UP * 1.2):
			score += 20.0  # cover between us and the threat
		if score > best_score:
			best_score = score
			best = p
	if best == Vector3.INF:
		var dir := (here - threat_pos)
		dir.y = 0
		best = here + dir.normalized() * 25.0
	return best


# --- hunter --------------------------------------------------------------------------------------

func _decide_hunter() -> void:
	var me := avatar.player_id
	var revealed := GameState.is_revealed(me)
	var best := -1
	var best_d := INF
	for id in _others():
		var other := Combat.avatar(id)
		var d := other.global_position.distance_to(avatar.global_position)
		if d < best_d and d < sight_range and _can_see(other):
			best_d = d
			best = id
	if best >= 0:
		target_id = best
		_last_seen_time = Combat.now()
		last_known = Combat.avatar(best).global_position
		mode = "hunt"
	elif mode == "hunt" and Combat.now() - _last_seen_time > lose_target_after:
		mode = "search"
		_goal = last_known
	elif mode == "search" and (_goal == Vector3.INF or _flat_dist(_goal) < 2.5):
		mode = "wander"
		target_id = -1
		_goal = Vector3.INF
	if mode == "wander":
		if _goal == Vector3.INF or _flat_dist(_goal) < 2.0:
			_goal = _random_waypoint(avatar.global_position, 10.0, 60.0)
		if revealed and Combat.transform_status(me)["phase"] == "revealed_free":
			Combat.request_revert(me)
		return
	if mode == "search":
		return
	var t := Combat.avatar(target_id)
	if t == null:
		mode = "wander"
		return
	_goal = t.global_position
	var dist := best_d if best >= 0 else t.global_position.distance_to(avatar.global_position)
	if not revealed:
		if dist < 12.0:
			Combat.request_transform(me)
		return
	if Combat.is_transforming(me) or Combat.is_busy(me):
		return
	_face(t.global_position)
	if dist < 2.6:
		if Combat.cooldown_remaining(me, "heavy_strike") <= 0.0 and _rng.randf() < 0.3:
			Combat.request_action(me, "heavy_attack")
		else:
			Combat.request_action(me, "attack")
	elif dist > 5.0 and dist < 9.0 and Combat.cooldown_remaining(me, "pounce") <= 0.0:
		Combat.request_action(me, "ability_1")
	elif dist < 9.0 and Combat.cooldown_remaining(me, "roar") <= 0.0 and _rng.randf() < 0.15:
		Combat.request_action(me, "ability_2")


# --- movement ------------------------------------------------------------------------------------

func _steer(delta: float) -> void:
	if _goal == Vector3.INF or Combat.is_busy(avatar.player_id) and mode == "fight":
		avatar.input_override = {}
		return
	var to := _goal - avatar.global_position
	to.y = 0.0
	if to.length() < 1.2 and mode != "hunt":
		avatar.input_override = {}
		return
	if mode == "hunt" and to.length() < 1.8:
		avatar.input_override = {}
		return
	if mode != "fight" and not (mode == "hunt" and Combat.is_busy(avatar.player_id)):
		_face(_goal)
	_check_t += delta
	if _check_t >= 0.8:
		var moved := avatar.global_position.distance_to(_check_pos)
		_stuck_t = _stuck_t + _check_t if moved < 0.5 else 0.0
		_check_pos = avatar.global_position
		_check_t = 0.0
		if _stuck_t > 2.4:
			_sidestep = 1.0
			_stuck_t = 0.0
			if mode == "wander":
				_goal = _random_waypoint(avatar.global_position, 6.0, 40.0)
	var move := Vector2(0, 1)
	if _sidestep > 0.0:
		_sidestep -= delta
		move = Vector2(1.0 if int(Combat.now()) % 2 == 0 else -1.0, 0.4)
	var sprint := mode in ["flee", "hunt", "search"]
	if mode == "flee" and avatar.stamina < 30.0 and _threat_distance() > 14.0:
		sprint = false  # keep a reserve for dodging
	avatar.input_override = {"move": move, "sprint": sprint, "jump": avatar.is_swimming,
		"jump_pressed": _stuck_t > 1.0, "crouch": false}


func _threat_distance() -> float:
	var t := Combat.avatar(_threat_id)
	return t.global_position.distance_to(avatar.global_position) if t else INF


func _clear_between(a: Vector3, b: Vector3) -> bool:
	return LineOfSight.is_clear(avatar.get_world_3d().direct_space_state, a, b, [avatar.get_rid()], Layers.SIGHT_BLOCKERS)


func _face(p: Vector3) -> void:
	var d := p - avatar.global_position
	if Vector2(d.x, d.z).length() > 0.05:
		avatar.set_look(atan2(-d.x, -d.z), 0.0)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - avatar.global_position.x, p.z - avatar.global_position.z).length()


func _random_waypoint(around: Vector3, min_d: float, max_d: float) -> Vector3:
	if waypoints.is_empty():
		var a := _rng.randf() * TAU
		return around + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(min_d, max_d)
	for i in 30:
		var p := waypoints[_rng.randi_range(0, waypoints.size() - 1)]
		var d := Vector2(p.x - around.x, p.z - around.z).length()
		if d >= min_d and d <= max_d:
			return p
	return waypoints[_rng.randi_range(0, waypoints.size() - 1)]
