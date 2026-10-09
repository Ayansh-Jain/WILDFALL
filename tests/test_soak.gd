extends Node
## Free-running fight: a hunter and five wanderers (mixed brave/timid) for
## three simulated minutes, checking state invariants on every player each
## second (scenario 9: defeat never leaves an invalid state).


func run(t) -> void:
	var k := CombatKit.new(t)
	k.place(k.local, Vector3(0, 0, -60), 0.0)
	var actors: Array[PlayerController] = []
	for i in 5:
		var a := TAU * i / 5.0
		var bot: PlayerController = t.main.spawn_bot(k.center + Vector3(cos(a), 0, sin(a)) * 9.0, SimBot.Role.WANDERER, i % 2 == 0)
		k.spawned.append(bot)
		actors.append(bot)
	var hunter: PlayerController = t.main.spawn_bot(k.center, SimBot.Role.HUNTER)
	k.spawned.append(hunter)
	actors.append(hunter)

	var counts := {"defeats": 0, "respawns": 0, "transforms": 0, "hits": 0, "power": 0}
	var on_def := func(_e: Dictionary) -> void: counts["defeats"] += 1
	var on_resp := func(_id: int) -> void: counts["respawns"] += 1
	var on_tr := func(_id: int, _m: String, _d: float) -> void: counts["transforms"] += 1
	var on_hit := func(_e: Dictionary) -> void: counts["hits"] += 1
	var on_pow := func(_id: int, _v: int, _d: int, _r: String) -> void: counts["power"] += 1
	Combat.player_defeated.connect(on_def)
	Combat.player_respawned.connect(on_resp)
	Combat.transform_started.connect(on_tr)
	Combat.damage_dealt.connect(on_hit)
	PowerScore.power_changed.connect(on_pow)

	var violations: PackedStringArray = []
	for second in 180:
		await k.seconds(1.0)
		for av in actors:
			var why := _invariant(av)
			if why != "":
				violations.append("t=%ds %s: %s" % [second, av.display_name, why])
		# Keep the hunter's prey close so encounters keep happening.
		for av in actors:
			if av != hunter and av.global_position.distance_to(k.center) > 60.0 and not av.is_defeated:
				av.teleport(k.center + Vector3(randf_range(-10, 10), 2.0, randf_range(-10, 10)))
	Combat.player_defeated.disconnect(on_def)
	Combat.player_respawned.disconnect(on_resp)
	Combat.transform_started.disconnect(on_tr)
	Combat.damage_dealt.disconnect(on_hit)
	PowerScore.power_changed.disconnect(on_pow)
	print("    soak: ", counts)
	t.check(violations.is_empty(), "no invalid player state in 3 minutes of free combat", "; ".join(violations.slice(0, 3)))
	t.check(counts["hits"] > 10 and counts["defeats"] >= 1, "the soak produced real fights", str(counts))
	t.check(counts["respawns"] >= counts["defeats"] - actors.size(), "defeated players come back", str(counts))
	t.check(GameState.has_monster(hunter.player_id), "the hunter keeps its monster powers through defeats")
	await k.cleanup()


func _invariant(av: PlayerController) -> String:
	var id := av.player_id
	var st := GameState.get_state(id)
	var c := av.combatant
	if st < 0 or st > PlayerState.State.RESPAWNING:
		return "unknown state %d" % st
	if is_nan(av.global_position.x) or av.global_position.y < -30.0:
		return "bad position %s" % av.global_position
	if PlayerState.is_alive_state(st):
		if c.health <= 0:
			return "alive with %d health" % c.health
		if av.is_defeated:
			return "alive but flagged defeated"
	elif st == PlayerState.State.DEFEATED and not av.is_defeated:
		return "defeated but controllable"
	if st == PlayerState.State.MONSTER_REVEALED:
		if not GameState.has_monster(id):
			return "revealed without powers"
		if not is_equal_approx(av.stand_height, 2.5) or c.max_health != 250:
			return "revealed with a human body"
	elif not is_equal_approx(av.stand_height, 1.8) or c.max_health != 100:
		return "human state with beast body (%s, %d hp)" % [av.stand_height, c.max_health]
	if c.health > c.max_health:
		return "health above max"
	return ""
