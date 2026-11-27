class_name Escort
extends Node
## The Commander's called escort (R02). Event driven: positions are worked out once when a
## command is given, never from the Commander's movement afterwards. It only moves soldiers
## that already exist; it never creates, heals or revives anyone.
##
## Commands: hold, advance(point), engage, defend(point), retreat(point), regroup, dismiss.
## Army-versus-army only: nothing here takes part in the Commander's attack token.

signal command_issued(command: String)

const SIZE := 4
## (right, back) metres from the Commander: two by two, behind the follow camera.
const BLOCK := [Vector2(-0.9, 5.4), Vector2(0.9, 5.4), Vector2(-0.9, 7.0), Vector2(0.9, 7.0)]
## Tried in turn when the block does not fit (bridges, alleys, walls behind).
const FALLBACK := [Vector2(0, 5.4), Vector2(0, 7.0), Vector2(0, 8.6), Vector2(-1.8, 5.4), Vector2(1.8, 5.4),
	Vector2(0, 3.8), Vector2(0, 2.4), Vector2(-1.6, 3.4), Vector2(1.6, 3.4), Vector2(-2.2, 1.2), Vector2(2.2, 1.2)]
const SLEEP_DISTANCE := 70.0
const WAKE_DISTANCE := 60.0

var leader: PlayerController
var water_level := 0.0
## Campaign battles march with routing (SoldierBrain.ADVANCE); labs walk straight.
var use_routes := false
## Soldiers currently called (SoldierBrain).
var members: Array = []
var _asleep := {}  ## brain -> true
var _tick := 0.0


func setup(p_leader: PlayerController, water := 0.0) -> void:
	leader = p_leader
	water_level = water


func living() -> Array:
	var out := []
	for b in members:
		if is_instance_valid(b) and b.is_alive():
			out.append(b)
	return out


func active() -> bool:
	return not living().is_empty()


## Up to `count` safe standing spots around `origin`, none inside walls, water, drops or people.
static func plan_formation(space: PhysicsDirectSpaceState3D, origin: Vector3, yaw: float, count: int,
		water := 0.0, avoid: Array = [], exclude: Array[RID] = []) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var basis := Basis(Vector3.UP, yaw)
	# A wide block first; each further rank of four stands behind the previous one.
	var offsets: Array = []
	for rank in ceili(count / 4.0):
		for o in BLOCK:
			offsets.append(o + Vector2(0, rank * 3.2))
	offsets.append_array(FALLBACK)
	for o: Vector2 in offsets:
		if out.size() >= count:
			break
		var want := origin + basis * Vector3(o.x, 0.0, o.y)
		var spot := SafeSpot.standing(space, want, origin + Vector3.UP, water, exclude)
		if spot == Vector3.INF or absf(spot.y - origin.y) > 1.6:
			continue
		# No gap or river between him and the spot.
		var middle := SafeSpot.ground(space, origin.lerp(spot, 0.5), 1.5, 3.0, exclude)
		if middle.is_empty() or SafeSpot.water_depth(middle["position"], water) > 0.7:
			continue
		var taken := false
		for p: Vector3 in out + avoid:
			if Vector2(p.x - spot.x, p.z - spot.z).length() < 1.1:
				taken = true
				break
		if not taken:
			out.append(spot)
	return out


## Calls up to SIZE of `candidates` (the healthiest first) into a holding formation.
func summon(candidates: Array) -> Dictionary:
	if active():
		return {"ok": false, "reason": "The escort is already with you.", "count": 0}
	var pool := candidates.filter(func(b) -> bool: return is_instance_valid(b) and b.is_alive())
	if pool.is_empty():
		return {"ok": false, "reason": "No living soldiers to call.", "count": 0}
	pool.sort_custom(func(a, b) -> bool:
		var ha: int = a.avatar.combatant.health
		var hb: int = b.avatar.combatant.health
		return a.soldier_id < b.soldier_id if ha == hb else ha > hb)
	pool = pool.slice(0, SIZE)
	var spots := _spots(leader.global_position, leader.rotation.y, pool)
	if spots.is_empty():
		return {"ok": false, "reason": "No room for your soldiers here.", "count": 0}
	members = pool.slice(0, spots.size())
	for i in members.size():
		_place(members[i], spots[i], leader.rotation.y)
	command_issued.emit("summon")
	return {"ok": true, "reason": "", "count": members.size()}


## Adds soldiers who are already where they should be (retry, reinforcements).
func adopt(brains: Array) -> void:
	for b in brains:
		if not members.has(b):
			members.append(b)


func command(order: String, point := Vector3.INF) -> bool:
	var company := living()
	if company.is_empty():
		return false
	for b in company:
		wake(b)
	match order:
		"hold":
			for b in company:
				_stand(b, b.avatar.global_position)
		"engage":
			for b in company:
				b.weapons_free = true
				b.alert(-1)
		"regroup":
			var spots := _spots(leader.global_position, leader.rotation.y, company)
			if spots.is_empty():
				return false
			for i in company.size():
				if i >= spots.size():
					_stand(company[i], company[i].avatar.global_position)
					continue
				# Near: walk. Far and unseen: reposition without route planning.
				if company[i].avatar.global_position.distance_to(spots[i]) > 40.0 and not _seen(company[i], spots[i]):
					_place(company[i], spots[i], leader.rotation.y)
				else:
					_stand(company[i], spots[i])
		"advance", "defend", "retreat":
			if point == Vector3.INF:
				return false
			var yaw := _yaw_toward(company, point)
			for i in company.size():
				var b = company[i]
				var slot := point + Basis(Vector3.UP, yaw) * Vector3((i % 4 - 1.5) * 1.8, 0.0, (i / 4) * 2.0)
				b.weapons_free = order != "retreat" and b.weapons_free
				if order == "advance" and use_routes:
					b.hold_pos = slot
					b.advance_target = slot
					b.set_order(SoldierBrain.Mode.ADVANCE)
				else:
					_stand(b, slot)
		"dismiss":
			members.clear()
		_:
			return false
	command_issued.emit(order)
	return true


func clear() -> void:
	members.clear()
	for b in _asleep.keys():
		if is_instance_valid(b):
			wake(b)
	_asleep.clear()


# --- distant soldiers cost nothing ------------------------------------------------------------

func sleeping_count() -> int:
	return _asleep.size()


func sleep(b) -> void:
	if _asleep.has(b):
		return
	_asleep[b] = true
	b.avatar.visible = false
	b.avatar.process_mode = Node.PROCESS_MODE_DISABLED


func wake(b) -> void:
	if not _asleep.erase(b):
		return
	b.avatar.process_mode = Node.PROCESS_MODE_INHERIT
	b.avatar.visible = true


func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or leader == null:
		return
	_tick = 0.5
	for b in _asleep.keys():
		if not is_instance_valid(b) or b.avatar.global_position.distance_to(leader.global_position) < WAKE_DISTANCE:
			if is_instance_valid(b):
				wake(b)
			else:
				_asleep.erase(b)
	for b in living():
		if _asleep.has(b) or b.weapons_free or b.mode != SoldierBrain.Mode.HOLD:
			continue
		var far: bool = b.avatar.global_position.distance_to(leader.global_position) > SLEEP_DISTANCE
		if far and not _seen(b, b.avatar.global_position):
			sleep(b)


# --- helpers ---------------------------------------------------------------------------------

func _spots(origin: Vector3, yaw: float, company: Array) -> Array[Vector3]:
	var exclude: Array[RID] = [leader.get_rid()]
	var avoid: Array = [origin]
	var mine := {}
	for b in company:
		mine[b.avatar] = true
	for id in Combat.actor_ids():
		var av := Combat.avatar(id)
		if av and av != leader and not mine.has(av) and not av.is_defeated and av.global_position.distance_to(origin) < 16.0:
			avoid.append(av.global_position)
	return plan_formation(leader.get_world_3d().direct_space_state, origin, yaw, company.size(), water_level, avoid, exclude)


func _place(b, spot: Vector3, yaw: float) -> void:
	wake(b)
	if b.horse:
		b.dismount()
	b.avatar.teleport(spot + Vector3.UP * 0.05, yaw)
	_stand(b, spot)
	b.hold_yaw = yaw


func _stand(b, at: Vector3) -> void:
	b.hold_pos = at
	b.hold_yaw = NAN
	b.set_order(SoldierBrain.Mode.HOLD)
	if b.mode != SoldierBrain.Mode.COMBAT:
		b._enter(SoldierBrain.Mode.HOLD)


func _yaw_toward(company: Array, point: Vector3) -> float:
	var from: Vector3 = company[0].avatar.global_position
	var d := point - from
	return atan2(-d.x, -d.z) if Vector2(d.x, d.z).length() > 0.5 else 0.0


func _seen(b, at: Vector3) -> bool:
	return CampaignUtil.in_view(leader, b.avatar.global_position + Vector3.UP, 400.0) or CampaignUtil.in_view(leader, at + Vector3.UP, 400.0)
