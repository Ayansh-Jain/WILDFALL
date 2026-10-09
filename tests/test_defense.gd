extends Node
## Human defensive options and escaping a monster (scenario 7).

var k: CombatKit
var me: PlayerController
var id := -1


func run(t) -> void:
	k = CombatKit.new(t)
	me = k.local
	id = me.player_id
	var drv := PlayerDriver.new(me)

	# Stamina-limited sprint (circle so we stay on the meadow).
	k.place(me, Vector3.ZERO, 0.0)
	me.stamina = me.max_stamina
	await k.frames(5)
	var yaw := 0.0
	var sprint_speed := 0.0
	for i in 120:
		yaw += 0.02
		me.set_look(yaw)
		drv.set_input(Vector2(0, 1), true)
		await k.frames(1)
		if i == 90:
			sprint_speed = Vector2(me.velocity.x, me.velocity.z).length()
	t.check(me.stamina < 60.0 and me.is_sprinting, "sprinting drains stamina", "%.0f left" % me.stamina)
	t.check(sprint_speed > me.walk_speed + 1.5, "sprint is faster than walking while stamina lasts", "%.1f m/s" % sprint_speed)
	for i in 200:
		yaw += 0.02
		me.set_look(yaw)
		drv.set_input(Vector2(0, 1), true)
		await k.frames(1)
	var tired_speed := Vector2(me.velocity.x, me.velocity.z).length()
	t.check(me.exhausted and not me.is_sprinting, "an empty stamina bar stops sprinting")
	t.check(tired_speed < me.walk_speed + 0.4, "exhausted players move at walking speed", "%.1f m/s" % tired_speed)
	drv.set_input()
	var low := me.stamina
	await k.seconds(2.5)
	t.check(me.stamina > low + 15.0, "stamina regenerates at rest", "%.0f -> %.0f" % [low, me.stamina])

	# Dodge: distance, cost, brief invulnerability.
	me.stamina = me.max_stamina
	k.place(me, Vector3.ZERO, 0.0)
	await k.frames(5)
	var p0 := me.global_position
	drv.set_input(Vector2(0, 1))
	var r := Combat.request_action(id, "ability_1")
	await k.frames(6)
	t.check(r["ok"] and me.combatant.is_invulnerable(), "dodge grants brief invulnerability")
	t.check(absf(me.stamina - 75.0) < 2.0, "dodge costs 25 stamina", "%.0f" % me.stamina)
	await k.seconds(0.3)
	drv.set_input()
	var dist := Vector2(me.global_position.x - p0.x, me.global_position.z - p0.z).length()
	t.check(dist > 3.8 and dist < 6.5, "dodge covers about 5 m", "%.1f m" % dist)
	t.check(not me.combatant.is_invulnerable(), "invulnerability ends right after the dodge")
	await k.seconds(1.5)
	k.place(me, Vector3.ZERO, 0.0)
	var block := k.wall(Vector3(0, 0, -2.0), Vector3(6, 3, 0.4))
	await k.frames(5)
	drv.set_input(Vector2(0, 1))
	Combat.request_action(id, "ability_1")
	await k.seconds(0.5)
	drv.set_input()
	t.check(me.global_position.z > k.center.z - 2.0 + 0.2, "dodge cannot pass through a wall", "z %.2f" % (me.global_position.z - k.center.z))
	block.queue_free()
	# Spamming dodge never gives continuous invulnerability.
	var inv_frames := 0
	for i in 300:
		me.stamina = me.max_stamina
		Combat.request_action(id, "ability_1")
		await k.frames(1)
		if me.combatant.is_invulnerable():
			inv_frames += 1
	t.check(inv_frames < 300 * 0.3, "spamming dodge is limited by its cooldown", "%d%% of frames invulnerable" % int(inv_frames / 3.0))

	# Ward: stuns revealed monsters only, needs line of sight, limited charges.
	k.place(me, Vector3.ZERO, 0.0)
	var beast := k.dummy(Vector3(0, 0, -3.0), SimBot.Role.HUNTER)
	await k.reveal(beast)
	await k.frames(3)
	var bd0 := beast.global_position.distance_to(me.global_position)
	var bh0 := beast.combatant.health
	r = Combat.request_action(id, "ability_2")
	await k.frames(8)
	t.check(r["ok"] and beast.combatant.is_stunned(), "ward stuns a revealed monster")
	t.check(beast.combatant.health == bh0 - 10, "ward scorches it for 10")
	t.check(beast.global_position.distance_to(me.global_position) > bd0 + 1.0, "ward knocks the monster back")
	await k.seconds(8.2)
	k.place(beast, Vector3(0, 0, -3.0))
	var shield := k.wall(Vector3(0, 0, -1.5), Vector3(4, 4, 0.4))
	beast.combatant.stunned_until = -INF
	await k.frames(5)
	r = Combat.request_action(id, "ability_2")
	await k.frames(5)
	t.check(r["ok"] and not beast.combatant.is_stunned(), "ward does not work through walls")
	shield.queue_free()
	await k.seconds(8.2)
	r = Combat.request_action(id, "ability_2")
	t.check(not r["ok"] and r["reason"] == "no charges", "ward has 2 uses per life", r["reason"])
	var hidden := k.dummy(Vector3(3, 0, -2), SimBot.Role.HUNTER)
	t.check(Combat._radius_targets(id, 6.0, true).has(beast.player_id) and not Combat._radius_targets(id, 6.0, true).has(hidden.player_id),
		"a ward ignores hidden monsters (it cannot be used to unmask them)")
	await k.cleanup()

	# Humans out-run the revealed beast, and a ward stun opens a real gap.
	var beast_def := GameState.monster_definition("ember_beast")
	t.check(GameState.HUMAN_FORM.sprint_speed > beast_def.sprint_speed, "a sprinting human is faster than a sprinting beast",
		"%.1f vs %.1f m/s" % [GameState.HUMAN_FORM.sprint_speed, beast_def.sprint_speed])
	k.place(me, Vector3(0, 0, 0), PI)
	var chaser := k.dummy(Vector3(0, 0, -2.5), SimBot.Role.HUNTER)
	await k.reveal(chaser)
	var cb: SimBot = chaser.get_node("Brain")
	cb.process_mode = Node.PROCESS_MODE_INHERIT
	me.stamina = me.max_stamina
	Combat.request_action(id, "ability_2")
	var gap0 := me.global_position.distance_to(chaser.global_position)
	for i in 120:
		drv.set_input(Vector2(0, 1), true)
		await k.frames(1)
	drv.set_input()
	var gap1 := me.global_position.distance_to(chaser.global_position)
	t.check(gap1 > gap0 + 6.0, "a ward stun lets a sprinting human open a gap", "%.1f -> %.1f m" % [gap0, gap1])
	await k.cleanup()

	# Breaking line of sight shakes off a hunter.
	k.place(me, Vector3(0, 0, 0), 0.0)
	var hunter := k.dummy(Vector3(0, 0, -14), SimBot.Role.HUNTER)
	var brain: SimBot = hunter.get_node("Brain")
	brain.process_mode = Node.PROCESS_MODE_INHERIT
	k.face(hunter, me.global_position)
	await k.seconds(1.0)
	t.check(brain.mode == "hunt" and brain.target_id == id, "a hunter that can see you starts hunting", brain.mode)
	k.wall(Vector3(0, 0, -6), Vector3(14, 6, 0.6))
	k.place(me, Vector3(0, 0, 2), 0.0)
	await k.seconds(brain.lose_target_after + 1.5)
	t.check(brain.mode != "hunt", "out of sight behind cover, the hunter loses track", brain.mode)
	await k.cleanup()

	# End-to-end chase: same hunter, two humans. One stands still, one flees
	# using the bot's escape behaviour (sprint, dodge, ward, cover).
	k.place(me, Vector3(0, 0, -40), 0.0)
	var still := k.dummy(Vector3(10, 0, 10))
	var hunter2 := k.dummy(Vector3(10, 0, 2), SimBot.Role.HUNTER)
	hunter2.get_node("Brain").process_mode = Node.PROCESS_MODE_INHERIT
	var defeated_still := false
	var still_time := 30.0
	for i in 30 * 60:
		await k.frames(1)
		if GameState.get_state(still.player_id) == PlayerState.State.DEFEATED:
			defeated_still = true
			still_time = i / 60.0
			break
	t.check(defeated_still, "a human who does nothing is caught and defeated by a hunter", "%.1f s" % still_time)
	await k.cleanup()
	# Deep forest west, where trunks and bushes can break line of sight.
	var forest := Vector3(-205, 0, 62) - k.center
	k.place(me, forest, 0.0)
	var hunter3 := k.dummy(forest + Vector3(0, 0, -10), SimBot.Role.HUNTER)
	hunter3.get_node("Brain").process_mode = Node.PROCESS_MODE_INHERIT
	var escaper := SimBot.new()
	escaper.name = "TestEscapeBrain"
	me.add_child(escaper)
	var survived := true
	var survive_time := 30.0
	var tools_used := {}
	var on_start := func(actor: int, ab: String, _w: float) -> void:
		if actor == id:
			tools_used[ab] = true
	Combat.ability_started.connect(on_start)
	var hb: SimBot = hunter3.get_node("Brain")
	var lost_track := false
	for i in 30 * 60:
		await k.frames(1)
		if hb.mode != "hunt":
			lost_track = true
		if i % 30 == 0 and OS.get_cmdline_user_args().has("--trace"):
			print("    t=%4.1f dist %4.1f hp %3d st %3.0f %s | beast %s st %3.0f spr %s pend %s" % [i / 60.0, me.global_position.distance_to(hunter3.global_position), me.combatant.health, me.stamina, escaper.mode, hb.mode, hunter3.stamina, hunter3.is_sprinting, Combat.pending_ability(hunter3.player_id)])
		if not PlayerState.is_alive_state(GameState.get_state(id)):
			survived = false
			survive_time = i / 60.0
			break
	Combat.ability_started.disconnect(on_start)
	var gap := me.global_position.distance_to(hunter3.global_position)
	t.check(survive_time >= maxf(15.0, still_time * 3.0) and tools_used.has("dodge") and tools_used.has("ward"),
		"sprint, dodge and ward keep a hunted human alive far longer (%.1f s vs %.1f s standing still)" % [survive_time, still_time],
		"health %d, gap %.0f m, used %s, hunter lost track: %s" % [me.combatant.health, gap, str(tools_used.keys()), lost_track])
	me.remove_child(escaper)
	escaper.queue_free()
	drv.release()
	await k.cleanup()
