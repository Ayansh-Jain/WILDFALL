class_name Battlefield
extends RefCounted
## The lightweight battlefield manager for group combat (Phase 4). Soldiers keep their own
## brains; this class holds what they must share, so nobody scans everybody:
##
##   * a per-physics-frame spatial grid of every living fighter (soldiers, the commander,
##     anything else registered with Combat) - range queries touch only nearby cells;
##   * the approach slots around each target (several fixed positions at weapon range, a
##     cap per target, a cap per direction, a few always left open) and who holds them;
##   * target scoring: distance, faction, who is hurting me or my friends, how crowded the
##     target already is, whether I can reach it, and a bias toward the fight I am in;
##   * assist: where a free soldier should go when its fight is over;
##   * path helpers that route around walls through the kingdom's route network.
## Who may target whom is decided in Factions (and enforced by Combat). All tunables
## come from the "battlefield" block of data/campaign.json (configure()).

const CELL := 4.0

# --- tunables --------------------------------------------------------------------------------
## Preferred personal space between friends (m).
static var personal_space := 1.3
## Approach slots around a target and their distance from it (m). The distance is
## clamped under the sword's reach so a soldier standing in its slot can always cut.
static var slot_count := 10
static var slot_radius := 1.6
## Most blades on one target, and on the commander; most from one 90 degree direction.
static var max_per_target := 5
static var max_per_leader := 3
static var max_per_sector := 2
## Slots that always stay free (so a target is never fully ringed).
static var open_slots := 2
## A free soldier looks this far for a friend who is still fighting (m).
static var assist_radius := 45.0
## Soldiers waiting for a slot hold this distance from the target (m).
static var wait_radius := 4.6
## Weapon reach: a soldier cuts at or inside this distance (m).
static var attack_range := 2.2
## The commander counts as "in danger" below this health fraction.
static var leader_danger := 0.4

static var world: World
static var route: RouteGraph
static var settings := {}

# --- per-frame snapshot -----------------------------------------------------------------------
static var _frame := -1
static var _cells := {}      ## Vector2i -> Array[int] fighter ids
static var _pos := {}        ## id -> Vector3
static var _team := {}       ## id -> String
static var _brain_of := {}   ## id -> SoldierBrain
static var _hurt := {}       ## attacker id -> Array[victim ids] (hurt in the last 2 s)
static var _targeters := {}  ## target id -> Array[brain ids]
static var _assisters := {}  ## friend id -> number of soldiers sent to help
static var _slots := {}      ## target id -> Array[int] slot -> attacker id (-1 free)
static var _blocked := {}    ## slot key -> [expire_frame, blocked]
static var _wired := false
## Counters for tests and reports.
static var stat_deaths := 0
## Microseconds spent per call kind while `profiling` is on (perf reports).
static var profiling := false
static var prof := {}


static func _p(kind: String, t0: int) -> void:
	var e: Array = prof.get(kind, [0, 0])
	e[0] += Time.get_ticks_usec() - t0
	e[1] += 1
	prof[kind] = e


static func setup(p_world: World, p_route: RouteGraph, cfg := {}) -> void:
	world = p_world
	route = p_route
	settings = cfg
	personal_space = float(cfg.get("personal_space", 1.3))
	slot_count = clampi(int(cfg.get("slot_count", 10)), 4, 16)
	max_per_target = int(cfg.get("max_per_target", 5))
	max_per_leader = int(cfg.get("max_per_leader", 3))
	max_per_sector = int(cfg.get("max_per_sector", 2))
	open_slots = int(cfg.get("open_slots", 2))
	assist_radius = float(cfg.get("assist_radius", 45.0))
	wait_radius = float(cfg.get("wait_radius", 4.6))
	leader_danger = float(cfg.get("leader_danger", 0.4))
	var reach := 2.3
	var ab := load("res://data/abilities/sword_strike.tres") as AbilityDefinition
	if ab:
		reach = ab.hit_range
	attack_range = reach - 0.1
	slot_radius = minf(float(cfg.get("slot_radius", 1.6)), attack_range - 0.5)
	reset()
	if not _wired:
		_wired = true
		Combat.player_defeated.connect(_on_death)


static func setting(key: String, default: float) -> float:
	return float(settings.get(key, default))


## Forgets every slot and cache (a mission reset or retry).
static func reset() -> void:
	_slots.clear()
	_blocked.clear()
	_frame = -1
	stat_deaths = 0


static func _on_death(e: Dictionary) -> void:
	var id: int = e["victim"]
	stat_deaths += 1
	_slots.erase(id)
	_pos.erase(id)
	_brain_of.erase(id)
	_team.erase(id)


# --- snapshot ---------------------------------------------------------------------------------

static func refresh() -> void:
	var f := Engine.get_physics_frames()
	if f == _frame:
		return
	_frame = f
	var t0 := Time.get_ticks_usec() if profiling else 0
	_cells.clear()
	_pos.clear()
	_team.clear()
	_brain_of.clear()
	_hurt.clear()
	_targeters.clear()
	_assisters.clear()
	var now := Combat.now()
	for b in SoldierBrain.all:
		if not b.is_alive():
			continue
		var id := b.avatar.player_id
		_add(id, b.avatar.global_position, b.team)
		_brain_of[id] = b
		if b.target_id >= 0:
			if _targeters.has(b.target_id):
				(_targeters[b.target_id] as Array).append(id)
			else:
				_targeters[b.target_id] = [id]
		if b.assist_of >= 0:
			_assisters[b.assist_of] = int(_assisters.get(b.assist_of, 0)) + 1
		var ra: Dictionary = b.avatar.combatant.recent_attackers
		for aid in ra:
			if now - float(ra[aid]) < 2.0:
				if _hurt.has(aid):
					(_hurt[aid] as Array).append(id)
				else:
					_hurt[aid] = [id]
	# Everyone else registered with Combat (the commander, other players, wanderers).
	for id in Combat.actor_ids():
		if _pos.has(id) or not Factions.targetable(id):
			continue
		_add(id, Combat.avatar(id).global_position, Combat.team_of(id))
	if profiling:
		_p("refresh", t0)


static func _add(id: int, p: Vector3, team: String) -> void:
	_pos[id] = p
	_team[id] = team
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	if _cells.has(k):
		(_cells[k] as Array).append(id)
	else:
		_cells[k] = [id]


## Ids of every living fighter in the grid cells overlapping the square of half-width r.
static func near_ids(p: Vector3, r: float) -> Array:
	refresh()
	var out := []
	var x0 := floori((p.x - r) / CELL)
	var x1 := floori((p.x + r) / CELL)
	var z0 := floori((p.z - r) / CELL)
	var z1 := floori((p.z + r) / CELL)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var k := Vector2i(cx, cz)
			if _cells.has(k):
				out.append_array(_cells[k])
	return out


static func position_of(id: int) -> Vector3:
	refresh()
	return _pos.get(id, Vector3.INF)


static func brain_of(id: int) -> SoldierBrain:
	refresh()
	return _brain_of.get(id)


static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Friends of `b` (same team, living, not b) within `r` (flat, with a floor check).
static func friends_near(b: SoldierBrain, r: float) -> Array[SoldierBrain]:
	var out: Array[SoldierBrain] = []
	var mp := b.avatar.global_position
	for id in near_ids(mp, r):
		var o: SoldierBrain = _brain_of.get(id)
		if o == null or o == b or o.team != b.team:
			continue
		if flat(mp, _pos[id]) <= r:
			out.append(o)
	return out


# --- who can be engaged ----------------------------------------------------------------------

## A living hostile that `b` may choose to fight. Runners (retreating soldiers) are left
## to go; so are the dormant ones that have not joined the fight.
static func engageable(b: SoldierBrain, id: int) -> bool:
	refresh()
	if not _pos.has(id) or not Factions.hostile_teams(b.team, _team[id]):
		return false
	var cb: SoldierBrain = _brain_of.get(id)
	if cb != null and cb.mode == SoldierBrain.Mode.RETREAT and cb.target_id != b.avatar.player_id:
		return false
	return true


static func nearest_hostile(b: SoldierBrain, radius: float, around := Vector3.INF) -> int:
	refresh()
	var p := b.avatar.global_position if around == Vector3.INF else around
	var best := -1
	var best_d := radius
	var r := minf(radius, 12.0)
	while true:
		for id in near_ids(p, r):
			if not _team.has(id) or not Factions.hostile_teams(b.team, _team[id]):
				continue
			var q: Vector3 = _pos[id]
			var d := flat(p, q)
			if d < best_d and absf(q.y - p.y) < 6.0 and engageable(b, id):
				best_d = d
				best = id
		if best >= 0 or r >= radius:
			break
		r = minf(r * 2.2, radius)
	return best


# --- approach slots ----------------------------------------------------------------------------

static func cap_for(tid: int) -> int:
	var cap := max_per_leader if tid == GameState.local_player_id else max_per_target
	return maxi(1, mini(cap, slot_count - open_slots))


static func _slot_array(tid: int) -> Array:
	if not _slots.has(tid):
		var a := []
		a.resize(slot_count)
		a.fill(-1)
		_slots[tid] = a
	return _slots[tid]


static func _slot_angle(tid: int, i: int) -> float:
	return TAU * float(i) / float(slot_count) + float(absi(tid) % 9) * 0.11


static func slot_pos(tid: int, i: int) -> Vector3:
	var tp: Vector3 = position_of(tid)
	if tp == Vector3.INF:
		return tp
	var a := _slot_angle(tid, i)
	return tp + Vector3(cos(a), 0.0, sin(a)) * slot_radius


## Drops slots whose holder died, left, or turned to another target.
static func _clean(tid: int, arr: Array) -> void:
	for i in arr.size():
		var o: int = arr[i]
		if o < 0:
			continue
		var ob: SoldierBrain = _brain_of.get(o)
		if ob == null or ob.target_id != tid or ob.slot_idx != i:
			arr[i] = -1


static func occupancy(tid: int) -> int:
	refresh()
	if not _slots.has(tid):
		return 0
	var arr: Array = _slots[tid]
	_clean(tid, arr)
	var n := 0
	for o in arr:
		if o >= 0:
			n += 1
	return n


## A slot is unusable if it lies in water, has no ground within reach of the target's
## height, or a wall / house stands between it and the target. Cached for a second.
static func _slot_blocked(tid: int, i: int) -> bool:
	var key := tid * 32 + i
	var c: Array = _blocked.get(key, [])
	if not c.is_empty() and int(c[0]) > _frame:
		return bool(c[1])
	var tp: Vector3 = position_of(tid)
	var sp := slot_pos(tid, i)
	var bad := false
	if world != null and tp != Vector3.INF:
		if world.terrain_height(sp.x, sp.z) < world.water_level + 0.15 and tp.y > world.water_level + 0.3:
			bad = true
		else:
			var hit := world.ground_ray(sp.x, sp.z, tp.y + 1.6, 4.0)
			if hit.is_empty() or absf(float(hit["position"].y) - tp.y) > 1.6:
				bad = true
			else:
				var space := world.get_world_3d().direct_space_state
				bad = not LineOfSight.is_clear(space, tp + Vector3.UP, sp + Vector3.UP, [], Layers.WORLD)
	_blocked[key] = [_frame + 50 + (key % 17), bad]
	return bad


## Gives `b` a slot around `tid`: its current one if still good, otherwise the free
## unblocked slot nearest the direction it comes from, honouring the per-target and
## per-direction caps. -1 = the target is already surrounded (wait or choose another).
static func claim(b: SoldierBrain, tid: int) -> int:
	var t0 := Time.get_ticks_usec() if profiling else 0
	var r := _raw_claim(b, tid)
	if profiling:
		_p("claim", t0)
	return r


static func _raw_claim(b: SoldierBrain, tid: int) -> int:
	refresh()
	var me := b.avatar.player_id
	var tp: Vector3 = position_of(tid)
	if tp == Vector3.INF:
		return -1
	var arr := _slot_array(tid)
	_clean(tid, arr)
	var cur := arr.find(me)
	if cur >= 0:
		if not _slot_blocked(tid, cur):
			return cur
		arr[cur] = -1
	var used := 0
	var per_sector := [0, 0, 0, 0]
	for i in arr.size():
		if arr[i] >= 0:
			used += 1
			per_sector[_sector(i)] += 1
	if used >= cap_for(tid):
		return -1
	var from := b.avatar.global_position - tp
	var bearing := atan2(from.z, from.x)
	var order: Array = []
	for i in arr.size():
		if arr[i] < 0 and per_sector[_sector(i)] < max_per_sector:
			var diff := absf(wrapf(_slot_angle(tid, i) - bearing, -PI, PI))
			order.append([diff, i])
	order.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var tries := 0
	for o in order:
		var i: int = o[1]
		if _slot_blocked(tid, i):
			tries += 1
			if tries >= 4:
				break
			continue
		arr[i] = me
		return i
	return -1


static func _sector(i: int) -> int:
	return clampi(int(float(i) / float(slot_count) * 4.0), 0, 3)


## Keeps this frame's target lists current when a soldier changes target mid-frame.
static func note_target(me: int, old: int, new: int) -> void:
	if _frame != Engine.get_physics_frames():
		return
	if old >= 0 and _targeters.has(old):
		(_targeters[old] as Array).erase(me)
	if new >= 0:
		if _targeters.has(new):
			(_targeters[new] as Array).append(me)
		else:
			_targeters[new] = [me]


static func release(b: SoldierBrain) -> void:
	if b.slot_idx >= 0 and _slots.has(b.slot_target):
		var arr: Array = _slots[b.slot_target]
		if b.slot_idx < arr.size() and arr[b.slot_idx] == b.avatar.player_id:
			arr[b.slot_idx] = -1
	b.slot_idx = -1
	b.slot_target = -1


## Where a soldier waits while the target is fully ringed: on its own side, at a loose
## distance, spread by id so the waiters do not stack.
static func wait_spot(b: SoldierBrain, tid: int) -> Vector3:
	var tp: Vector3 = position_of(tid)
	var from := b.avatar.global_position - tp
	var ang := atan2(from.z, from.x) + float((b.soldier_id * 7) % 5 - 2) * 0.22
	return tp + Vector3(cos(ang), 0.0, sin(ang)) * (wait_radius + float(absi(b.soldier_id) % 3) * 0.8)


# --- target choice -------------------------------------------------------------------------------

static func leader_critical() -> bool:
	var av := Combat.avatar(GameState.local_player_id)
	if av == null or av.is_defeated:
		return false
	return float(av.combatant.health) < float(av.combatant.max_health) * leader_danger


static func _reachable(b: SoldierBrain, tp: Vector3) -> bool:
	var mp := b.avatar.global_position
	if absf(tp.y - mp.y) > 7.0:
		return false
	if flat(mp, tp) < 10.0 or world == null:
		return true
	if open_line(mp, tp):
		return true
	return route != null and route.nearest(mp, 60.0) >= 0 and route.nearest(tp, 60.0) >= 0


## The best enemy for `b` to fight now, or -1. `exclude` maps target id -> time until which
## it is off the list (a target that stayed surrounded).
static func pick_target(b: SoldierBrain, radius: float, exclude := {}) -> int:
	var t0 := Time.get_ticks_usec() if profiling else 0
	var r := _raw_pick_target(b, radius, exclude)
	if profiling:
		_p("pick", t0)
	return r


static func _raw_pick_target(b: SoldierBrain, radius: float, exclude := {}) -> int:
	refresh()
	var me := b.avatar.player_id
	var mp := b.avatar.global_position
	var now := Combat.now()
	var crit := b.team == Factions.KINGDOM and leader_critical()
	var lp: Vector3 = position_of(GameState.local_player_id)
	var scored: Array = []
	var r := minf(radius, 14.0)
	while true:
		scored.clear()
		for id in near_ids(mp, r):
			if id == me or not _team.has(id) or not Factions.hostile_teams(b.team, _team[id]):
				continue
			if float(exclude.get(id, 0.0)) > now or not engageable(b, id):
				continue
			var q: Vector3 = _pos[id]
			var d := flat(mp, q)
			if d > r or absf(q.y - mp.y) > 6.0:
				continue
			scored.append([_score(b, id, q, d, me, mp, now, crit, lp), id])
		var best_s := 1e9
		for s in scored:
			best_s = minf(best_s, s[0])
		if (not scored.is_empty() and best_s < 25.0) or r >= radius:
			break
		r = minf(r * 2.2, radius)
	if scored.is_empty():
		return -1
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var best := -1
	var best_score := INF
	for k in mini(3, scored.size()):
		var s: float = scored[k][0]
		var id: int = scored[k][1]
		if not _reachable(b, _pos[id]):
			s += 30.0
		if s < best_score:
			best_score = s
			best = id
	return best


static func _score(b: SoldierBrain, id: int, q: Vector3, d: float, me: int, mp: Vector3, now: float, crit: bool, lp: Vector3) -> float:
	var s := d
	# A target already ringed by friends is a poor choice; a lightly held one is fine.
	var occ := occupancy(id)
	if _slots.has(id) and (_slots[id] as Array).has(me):
		occ -= 1
	# Soldiers who have chosen it but are still on their way count too (intent, not only slots).
	var heading: Array = _targeters.get(id, [])
	occ = maxi(occ, heading.size() - (1 if heading.has(me) else 0))
	if occ >= cap_for(id):
		s += 40.0
	else:
		s += 2.5 * float(occ)
	# The fight I am already in.
	if id == b.target_id:
		s -= 5.0
	# Who is hurting me.
	var ra: Dictionary = b.avatar.combatant.recent_attackers
	if ra.has(id) and now - float(ra[id]) < 3.0:
		s -= 6.0
	var cb: SoldierBrain = _brain_of.get(id)
	if cb != null and cb.target_id == me:
		s -= 3.0
	# Who is hurting a friend close by, and who has a friend outnumbered.
	for v in _hurt.get(id, []):
		if v != me and _pos.has(v) and Factions.allied(me, v) and flat(mp, _pos[v]) < 12.0:
			s -= 3.0
			break
	if cb != null and cb.target_id >= 0 and Factions.allied(me, cb.target_id):
		s -= minf(1.5 * float((_targeters.get(cb.target_id, []) as Array).size()), 6.0)
	# The commander's life comes first when it is truly in danger (slots still apply).
	if crit and lp != Vector3.INF and flat(q, lp) < 10.0:
		s -= 10.0
	# Stable per-pair taste, so a crowd does not all prefer the same face.
	s += float((absi(b.soldier_id) * 31 + absi(id) * 17) % 7 - 3) * 0.5
	return s


## A free soldier looks for a friend who is still fighting and joins that fight:
## prefers friends who are outnumbered or hurt, whose enemy is not already ringed, and
## whom few others are already helping. Returns the enemy id (and sets b.assist_of).
static func find_assist(b: SoldierBrain) -> int:
	var t0 := Time.get_ticks_usec() if profiling else 0
	var r := _raw_find_assist(b)
	if profiling:
		_p("assist", t0)
	return r


static func _raw_find_assist(b: SoldierBrain) -> int:
	refresh()
	var me := b.avatar.player_id
	var mp := b.avatar.global_position
	var best_enemy := -1
	var best_friend := -1
	var best_score := INF
	for id in near_ids(mp, assist_radius):
		if id == me or not _team.has(id) or _team[id] != b.team:
			continue
		var fp: Vector3 = _pos[id]
		var fd := flat(mp, fp)
		if fd > assist_radius or absf(fp.y - mp.y) > 6.0:
			continue
		var threats: Array = []
		var fb: SoldierBrain = _brain_of.get(id)
		if fb != null and fb.mode == SoldierBrain.Mode.COMBAT and fb.target_id >= 0:
			threats.append(fb.target_id)
		# Enemies currently attacking this friend.
		for aid in _targeters.get(id, []):
			if not threats.has(aid):
				threats.append(aid)
		if threats.is_empty():
			continue
		var fav := Combat.avatar(id)
		var hp := 1.0
		if fav != null:
			hp = float(fav.combatant.health) / maxf(float(fav.combatant.max_health), 1.0)
		for eid in threats:
			if not _pos.has(eid) or not engageable(b, eid) or absf(_pos[eid].y - mp.y) > 6.0:
				continue
			var occ := occupancy(eid)
			if occ >= cap_for(eid):
				continue
			var pressure := (_targeters.get(id, []) as Array).size()
			var support := (_targeters.get(eid, []) as Array).size()
			var s := fd * 0.6 + float(occ) * 3.0 - 4.0 * float(maxi(pressure - support, 0)) - 6.0 * (1.0 - hp) \
				+ 7.0 * float(_assisters.get(id, 0)) + flat(mp, _pos[eid]) * 0.4
			if s < best_score:
				best_score = s
				best_enemy = eid
				best_friend = id
	b.assist_of = best_friend
	return best_enemy


# --- movement help -----------------------------------------------------------------------------

## No wall, house or rock between two points (checked above knee-high bumps).
static func open_line(a: Vector3, b: Vector3) -> bool:
	if world == null:
		return true
	var space := world.get_world_3d().direct_space_state
	for h in [1.2, 2.6]:
		if not LineOfSight.is_clear(space, a + Vector3.UP * h, b + Vector3.UP * h, [], Layers.WORLD):
			return false
	return true


## Waypoints from `from` to `to`: cross country when nothing solid stands between,
## along the route network (string-pulled) when walls or houses are in the way.
static func route_to(from: Vector3, to: Vector3) -> PackedVector3Array:
	var single := PackedVector3Array()
	single.append(to)
	if route == null or open_line(from, to):
		return single
	var path := route.route(from, to)
	var length := 0.0
	var prev := from
	for p in path:
		length += flat(prev, p)
		prev = p
	# A road far longer than the straight line: head for the open middle and let local
	# steering sort the rest out.
	if length > flat(from, to) * 2.2 and open_line(from, (from + to) * 0.5):
		var mid := PackedVector3Array()
		mid.append((from + to) * 0.5)
		mid.append(to)
		return mid
	return _pull(from, path)


static func _pull(from: Vector3, path: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cur := from
	var i := 0
	var guard := 0
	while i < path.size() and guard < 64:
		guard += 1
		var best := i
		var j := path.size() - 1
		while j > i:
			if open_line(cur, path[j]):
				best = j
				break
			j -= 3 if j - 3 > i else 1
		out.append(path[best])
		cur = path[best]
		i = best + 1
	return out


# --- reports ---------------------------------------------------------------------------------------

## Live numbers for tests and perf reports.
static func me_id(b: SoldierBrain) -> int:
	return b.avatar.player_id


static func stats() -> Dictionary:
	refresh()
	var engaged := 0
	var waiting := 0
	var assisting := 0
	var per_target := {}
	var holding := {}
	var fighting := 0
	for b in SoldierBrain.all:
		if not b.is_alive() or b.mode != SoldierBrain.Mode.COMBAT:
			continue
		fighting += 1
		if b.target_id >= 0:
			engaged += 1
			per_target[b.target_id] = int(per_target.get(b.target_id, 0)) + 1
			if b.slot_idx >= 0:
				holding[b.target_id] = int(holding.get(b.target_id, 0)) + 1
			if b.waiting:
				waiting += 1
			var tb: SoldierBrain = _brain_of.get(b.target_id)
			if b.assist_of >= 0 or (tb != null and tb.target_id >= 0 and tb.target_id != me_id(b) and Factions.allied(me_id(b), tb.target_id)):
				assisting += 1
	var most := 0
	for t in per_target:
		most = maxi(most, int(per_target[t]))
	var most_h := 0
	for t in holding:
		most_h = maxi(most_h, int(holding[t]))
	return {"most_holding": most_h, "fighters": fighting, "engaged": engaged, "targets": per_target.size(), "most_on_one": most,
		"waiting": waiting, "assisting": assisting, "tracked": _pos.size()}
