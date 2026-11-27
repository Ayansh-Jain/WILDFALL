extends Node
## Phase 4 group combat: the faction rules, approach slots (spread, caps, open positions),
## independent engagements, assist, no blows on the dead, no friendly fire, and
## skirmishes of 5 / ~20 / ~40 / ~100 combatants on open ground with their per-frame cost.
## Skirmishes run on the Great Gate Field with the garrison frozen, both sides marching
## on each other (no campaign state is touched).

var t
var main: Node
var c: CampaignDirector
var player: PlayerController
var world: World
var arena: Node3D
var _serial := 0
var _frozen: Array[SoldierBrain] = []
var _friendly_fire := 0
var _dumped := false
var _field := Vector3(-232.0, 0.0, 108.0)


func run(runner) -> void:
	t = runner
	main = t.main
	c = main.campaign
	player = main.player
	world = t.world
	if not t.check(c != null, "the campaign exists"):
		return
	c.speed = 0.05
	arena = Node3D.new()
	arena.name = "BattlefieldArena"
	main.add_child(arena)
	_field.y = world.terrain_height(_field.x, _field.z)
	for g in c.garrison.guards:
		if g.is_alive():
			g.paused = true
			_frozen.append(g)
	Combat.damage_dealt.connect(_on_damage)
	await _factions()
	await _slots()
	await _skirmish("5 combatants", 2, 2, 14.0)
	await _skirmish("20 combatants", 9, 10, 22.0)
	await _skirmish("40 combatants", 19, 20, 32.0)
	await _skirmish("100 combatants", 49, 50, 48.0)
	await _assist()
	Combat.damage_dealt.disconnect(_on_damage)
	t.check(_friendly_fire == 0, "no soldier ever struck a friend in any skirmish", "%d friendly blows" % _friendly_fire)
	for g in _frozen:
		if is_instance_valid(g):
			g.paused = false
	_clear()
	arena.queue_free()
	player.teleport(main.player_spawns[0] + Vector3.UP * 0.1)
	await _frames(10)


# --- rules --------------------------------------------------------------------------------------

func _factions() -> void:
	var a := _make("kingdom", _field, 1)
	var b := _make("kingdom", _field + Vector3(4, 0, 0), 2)
	var e1 := _make("enemy", _field + Vector3(0, 0, 8), 3)
	var e2 := _make("enemy", _field + Vector3(4, 0, 8), 4)
	var ia := a.avatar.player_id
	var ib := b.avatar.player_id
	var ie := e1.avatar.player_id
	var pid := player.player_id
	t.check(Factions.allied(ia, ib) and not Factions.hostile(ia, ib), "allied soldiers are never hostile to each other")
	t.check(Factions.allied(ia, pid) and Factions.allied(ib, pid), "allied soldiers and the commander are one team")
	t.check(Factions.hostile(ie, ia) and Factions.hostile(ie, pid) and Factions.hostile(ia, ie), "enemy soldiers are hostile to the commander and to allied soldiers")
	t.check(Factions.allied(ie, e2.avatar.player_id), "enemy soldiers are not hostile to each other")
	t.check(Battlefield.nearest_hostile(a, 30.0) == ie or Battlefield.nearest_hostile(a, 30.0) == e2.avatar.player_id,
		"target search only ever returns a hostile")
	t.check(Battlefield.pick_target(a, 40.0) in [ie, e2.avatar.player_id], "target choice picks an enemy, never a friend or the commander")
	Combat.apply_damage(ie, 999, ia, "test")
	await _frames(3)
	t.check(Battlefield.nearest_hostile(a, 30.0) == e2.avatar.player_id, "a dead soldier leaves target selection at once")
	t.check(Battlefield.pick_target(a, 40.0) == e2.avatar.player_id, "...and target choice")
	_clear()


## One dummy enemy that stands still, eight allies sent to attack it.
func _slots() -> void:
	var dummy := _make("enemy", _field, 100, 100000)
	dummy.paused = true
	var attackers: Array[SoldierBrain] = []
	for i in 9:
		var ang := TAU * float(i) / 9.0
		var b := _make("kingdom", _field + Vector3(cos(ang), 0.0, sin(ang)) * 9.0, 200 + i)
		b._enter(SoldierBrain.Mode.COMBAT)
		b._set_target(dummy.avatar.player_id)
		attackers.append(b)
	await _frames(60 * 8)
	var tid := dummy.avatar.player_id
	var near := 0
	var waiting := 0
	var sectors := [0, 0, 0, 0]
	var pts: Array[Vector3] = []
	var dists: Array[float] = []
	for b in attackers:
		if not b.is_alive():
			continue
		var d := CampaignUtil.flat_dist(b.avatar.global_position, dummy.avatar.global_position)
		if d < 3.0:
			near += 1
			var off := b.avatar.global_position - dummy.avatar.global_position
			sectors[clampi(int((atan2(off.z, off.x) + PI) / TAU * 4.0), 0, 3)] += 1
			pts.append(b.avatar.global_position)
			dists.append(d)
		if b.waiting or b.target_id != tid:
			waiting += 1
	var min_gap := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_gap = minf(min_gap, CampaignUtil.flat_dist(pts[i], pts[j]))
	var cap := Battlefield.cap_for(tid)
	t.check(near <= cap + 1 and near >= 3, "a lone target is attacked by at most the cap and at least three blades", "%d at melee range, cap %d" % [near, cap])
	t.check(Battlefield.occupancy(tid) <= cap, "slot occupancy never exceeds the cap", "%d / %d" % [Battlefield.occupancy(tid), cap])
	t.check(Battlefield.slot_count - Battlefield.occupancy(tid) >= Battlefield.open_slots, "approach positions stay open around a target", "%d free of %d" % [Battlefield.slot_count - Battlefield.occupancy(tid), Battlefield.slot_count])
	t.check(sectors.max() <= Battlefield.max_per_sector + 1, "no more than two come from the same direction", str(sectors))
	t.check(min_gap > 0.65, "attackers do not pile into one point", "closest pair %.2f m" % min_gap)
	var dmax := 0.0
	for d in dists:
		dmax = maxf(dmax, d)
	t.check(dmax <= Battlefield.attack_range + 0.9, "attackers stand within weapon range", "farthest %.2f m, reach %.2f" % [dmax, Battlefield.attack_range])
	t.check(waiting >= attackers.size() - cap - 1, "the surplus waits (or looks elsewhere) instead of crowding in", "%d waiting" % waiting)
	# Ring the commander: only the leader cap of enemies can hold slots on him.
	var lid := player.player_id
	var enemies: Array[SoldierBrain] = []
	player.teleport(_field + Vector3(20, 0.2, 0))
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var e := _make("enemy", player.global_position + Vector3(cos(ang), 0.0, sin(ang)) * 8.0, 300 + i)
		e._enter(SoldierBrain.Mode.COMBAT)
		e._set_target(lid)
		enemies.append(e)
	for i in 60 * 6:
		await t.get_tree().physics_frame
		Combat.heal_player(lid, 100)
	t.check(Battlefield.occupancy(lid) <= Battlefield.max_per_leader, "the commander is ringed by at most the leader cap", "%d slots held" % Battlefield.occupancy(lid))
	_clear()


# --- skirmishes ------------------------------------------------------------------------------------

func _skirmish(label: String, allies: int, enemies: int, half_gap: float) -> void:
	var total := allies + enemies + 1
	var east := _field + Vector3(half_gap, 0, 0)
	var west := _field - Vector3(half_gap, 0, 0)
	player.teleport(west + Vector3(-4, 0.2, 0))
	var sp0 := Time.get_ticks_usec()
	var a_list := _formation("kingdom", allies, west, 1000)
	var e_list := _formation("enemy", enemies, east, 2000)
	var spawn_ms := (Time.get_ticks_usec() - sp0) / 1000.0
	var first0 := Time.get_ticks_usec()
	await t.get_tree().physics_frame
	await t.get_tree().physics_frame
	var first_ms := (Time.get_ticks_usec() - first0) / 1000.0
	print("  [battlefield] %s spawn: %.0f ms to create %d soldiers, %.0f ms for the next two frames" % [label, spawn_ms, allies + enemies, first_ms])
	for b in a_list:
		b.advance_target = east
		b.order = SoldierBrain.Mode.ADVANCE
		b._enter(SoldierBrain.Mode.ADVANCE)
	for b in e_list:
		b.advance_target = west
		b.order = SoldierBrain.Mode.ADVANCE
		b._enter(SoldierBrain.Mode.ADVANCE)
	Battlefield.profiling = true
	Battlefield.prof.clear()
	var secs := 30.0
	var samples: Array[Dictionary] = []
	var worst_ms := 0.0
	var probe := label.begins_with("100")
	var probe_t0 := 0
	var probe_ms := 0.0
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var assisting_seen := 0
	var max_on_one := 0
	var max_holding := 0
	var dead_target := 0
	var on_commander := 0
	var on_allies := 0
	for f in int(secs * 60.0):
		var s0 := Time.get_ticks_usec()
		await t.get_tree().physics_frame
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - s0) / 1000.0)
		frames += 1
		Combat.heal_player(player.player_id, 100)
		if probe and f == 600:
			probe_t0 = Time.get_ticks_usec()
			for b in SoldierBrain.all:
				if b.get_parent().get_parent() == arena:
					b.process_mode = Node.PROCESS_MODE_DISABLED
		if probe and f == 780:
			probe_ms = (Time.get_ticks_usec() - probe_t0) / 1000.0 / 180.0
			for b in SoldierBrain.all:
				if b.get_parent().get_parent() == arena:
					b.process_mode = Node.PROCESS_MODE_INHERIT
		if f % 60 == 30:
			var st := Battlefield.stats()
			samples.append(st)
			assisting_seen = maxi(assisting_seen, int(st["assisting"]))
			max_on_one = maxi(max_on_one, int(st["most_on_one"]))
			max_holding = maxi(max_holding, int(st["most_holding"]))
			if int(st["most_holding"]) > Battlefield.max_per_target and not _dumped:
				_dumped = true
				_dump_mobbed()
			for b in SoldierBrain.all:
				if not b.is_alive() or b.mode != SoldierBrain.Mode.COMBAT or b.target_id < 0:
					continue
				if b.get_parent().get_parent() != arena:
					continue
				if not Factions.targetable(b.target_id) and Combat.avatar(b.target_id) != null:
					dead_target += 1
				if b.team == Factions.ENEMY:
					if b.target_id == player.player_id:
						on_commander += 1
					else:
						on_allies += 1
	var avg_ms := (Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	var alive_a := 0
	var alive_e := 0
	for b in a_list:
		if b.is_alive():
			alive_a += 1
	for b in e_list:
		if b.is_alive():
			alive_e += 1
	Battlefield.profiling = false
	if probe:
		print("  [battlefield] %s: with every brain switched off for 3 s mid-fight a tick costs %.1f ms (bodies, animation and physics alone)" % [label, probe_ms])
	var prof_text := ""
	for k in Battlefield.prof:
		prof_text += " %s %.2f ms/tick (%d calls)" % [k, float(Battlefield.prof[k][0]) / 1000.0 / float(frames), int(Battlefield.prof[k][1])]
	print("  [battlefield] %s profile:%s" % [label, prof_text])
	var spread := _spread_report(a_list + e_list)
	var peak: Dictionary = samples[0]
	for st in samples:
		if int(st["targets"]) > int(peak["targets"]):
			peak = st
	print("  [battlefield] %-14s avg %.1f ms/tick (worst %.0f), engaged peak %d on %d targets, most on one target %d, assist seen %d, waiting peak %d, allies left %d/%d, enemies left %d/%d, pile %.2f, crowd(max 1.5m) %d" % [
		label, avg_ms, worst_ms, int(peak["engaged"]), int(peak["targets"]), max_on_one, assisting_seen,
		_peak(samples, "waiting"), alive_a, allies, alive_e, enemies, spread["pile"], spread["max_crowd"]])
	t.check(int(peak["targets"]) >= mini(total / 6, 6) or total <= 6, "%s: many separate engagements form, not one brawl" % label,
		"%d targets with attackers" % int(peak["targets"]))
	t.check(max_holding <= Battlefield.max_per_target, "%s: never more than the cap attack one target" % label, "%d held slots on one target (%d chose it, the rest wait)" % [max_holding, max_on_one])
	t.check(spread["max_crowd"] <= 8 and spread["pile"] < 0.1, "%s: no pile-ups (most friends within 1.5 m of a fighter)" % label, "%d" % spread["max_crowd"])
	t.check(dead_target == 0, "%s: nobody keeps a defeated target" % label, "%d stale" % dead_target)
	if enemies >= 8:
		t.check(on_allies > 0 and (on_commander == 0 or float(on_commander) < float(on_allies + on_commander) * 0.6),
			"%s: enemies split their attention between the commander and the army" % label, "%d on the commander, %d on soldiers" % [on_commander, on_allies])
	t.check(alive_a + alive_e < total - 1 or total <= 6, "%s: fighters fall (individual health and death)" % label, "%d fell" % (allies + enemies - alive_a - alive_e))
	if label.begins_with("100"):
		t.check(avg_ms < 1000.0 / 20.0, "100 combatants stay playable headless (under 50 ms per tick)", "%.1f ms" % avg_ms)
	_clear()
	await _frames(10)


func _dump_mobbed() -> void:
	var per := {}
	for b in SoldierBrain.all:
		if b.is_alive() and b.mode == SoldierBrain.Mode.COMBAT and b.target_id >= 0:
			(per.get_or_add(b.target_id, []) as Array).append(b)
	for tid in per:
		if (per[tid] as Array).size() > Battlefield.max_per_target + 2:
			var tp := Battlefield.position_of(tid)
			var line := "  [dump] target %d cap %d occupancy %d:" % [tid, Battlefield.cap_for(tid), Battlefield.occupancy(tid)]
			for b in per[tid]:
				line += " (d=%.1f slot=%d wait=%s wt=%.1f)" % [CampaignUtil.flat_dist(b.avatar.global_position, tp), b.slot_idx, b.waiting, b._wait_t]
			print(line)


func _peak(samples: Array[Dictionary], key: String) -> int:
	var m := 0
	for s in samples:
		m = maxi(m, int(s[key]))
	return m


## Pile metric: mean number of friends within 0.55 m (should be ~0); max_crowd = most
## friends inside 1.5 m of one fighter.
func _spread_report(list: Array[SoldierBrain]) -> Dictionary:
	var alive: Array[SoldierBrain] = []
	for b in list:
		if b.is_alive():
			alive.append(b)
	var pile := 0
	var max_crowd := 0
	for i in alive.size():
		var near := 0
		for j in alive.size():
			if i == j or alive[i].team != alive[j].team:
				continue
			var d := CampaignUtil.flat_dist(alive[i].avatar.global_position, alive[j].avatar.global_position)
			if d < 0.55:
				pile += 1
			if d < 1.5:
				near += 1
		max_crowd = maxi(max_crowd, near)
	return {"pile": float(pile) / maxf(alive.size(), 1.0), "max_crowd": max_crowd}


## A free soldier whose fight is over helps a friend who is outnumbered, and the free
## soldiers do not all pick the same fight.
func _assist() -> void:
	var center := _field + Vector3(0, 0, -30)
	var pairs: Array = []
	# Three duels on a line, one of them 2 v 1 against the friend (the outnumbered one).
	var friends: Array[SoldierBrain] = []
	var foes: Array[SoldierBrain] = []
	for i in 3:
		var x := center + Vector3(-12.0 + 12.0 * i, 0.0, 0.0)
		var f := _make("kingdom", x, 400 + i, 100000)
		var e := _make("enemy", x + Vector3(0, 0, 1.8), 410 + i, 100000)
		f.advance_target = e.avatar.global_position
		f._enter(SoldierBrain.Mode.COMBAT)
		f._set_target(e.avatar.player_id)
		e._enter(SoldierBrain.Mode.COMBAT)
		e._set_target(f.avatar.player_id)
		friends.append(f)
		foes.append(e)
		pairs.append([f, e])
	# A second foe piles onto friend 1: it is outnumbered.
	var extra := _make("enemy", center + Vector3(0.0, 0.0, 6.0), 420, 100000)
	extra._enter(SoldierBrain.Mode.COMBAT)
	extra._set_target(friends[1].avatar.player_id)
	# Free soldiers with no enemies of their own, close behind the line.
	var helpers: Array[SoldierBrain] = []
	for i in 4:
		var h := _make("kingdom", center + Vector3(-6.0 + 4.0 * i, 0.0, -14.0), 430 + i)
		h._enter(SoldierBrain.Mode.COMBAT)
		helpers.append(h)
	await _frames(60 * 8)
	var helping := 0
	var on_enemy := {}
	for h in helpers:
		if h.target_id >= 0:
			helping += 1
			on_enemy[h.target_id] = int(on_enemy.get(h.target_id, 0)) + 1
	t.check(helping >= 3, "free soldiers find a friend who is still fighting and join in", "%d of 4 helping" % helping)
	t.check(on_enemy.size() >= 2, "...and spread over several fights, not one", "%d different enemies: %s" % [on_enemy.size(), str(on_enemy)])
	var onto_outnumbered := 0
	for h in helpers:
		if h.target_id == extra.avatar.player_id or h.target_id == foes[1].avatar.player_id:
			onto_outnumbered += 1
	t.check(onto_outnumbered >= 1, "the outnumbered friend gets help first", "%d went to its fight" % onto_outnumbered)
	# The one fight ends: its winner takes up a new one.
	Combat.apply_damage(foes[0].avatar.player_id, 999999, friends[0].avatar.player_id, "test")
	await _frames(60 * 4)
	t.check(friends[0].target_id != foes[0].avatar.player_id and friends[0].target_id != -1 or friends[0].mode != SoldierBrain.Mode.COMBAT,
		"a soldier whose target falls looks for the next fight", "now %d, mode %s" % [friends[0].target_id, friends[0].mode_name()])
	_clear()


# --- helpers -----------------------------------------------------------------------------------------

func _formation(faction: String, n: int, center: Vector3, id0: int) -> Array[SoldierBrain]:
	var out: Array[SoldierBrain] = []
	var cols := maxi(3, int(ceil(sqrt(float(n)))) + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = id0
	for i in n:
		var row := i / cols
		var col := i % cols
		var p := center + Vector3(rng.randf_range(-0.6, 0.6) + (row - n / cols * 0.5) * 3.4, 0.0, (col - (cols - 1) * 0.5) * 3.2 + rng.randf_range(-0.6, 0.6))
		p.y = world.terrain_height(p.x, p.z)
		out.append(_make(faction, p, id0 + i))
	return out


func _make(faction: String, pos: Vector3, id: int, health := 100) -> SoldierBrain:
	_serial += 1
	var b := SoldierFactory.spawn(arena, world, {"faction": faction, "name": "T%d" % _serial, "node_name": "T_%d" % _serial,
		"id": id, "pos": pos, "yaw": 0.0, "mode": SoldierBrain.Mode.HOLD, "max_health": health, "role": "line"})
	return b


func _clear() -> void:
	for ch in arena.get_children():
		ch.queue_free()
	Battlefield.reset()


func _on_damage(e: Dictionary) -> void:
	var s: int = e["source"]
	var v: int = e["target"]
	if s >= 0 and v >= 0 and s != v and Factions.allied(s, v):
		_friendly_fire += 1


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame
