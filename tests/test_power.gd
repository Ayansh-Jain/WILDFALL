extends Node
## Power score rules applied exactly once (scenario 8) and defeat/respawn
## always ending in a valid state (scenario 9).

var k: CombatKit


func run(t) -> void:
	k = CombatKit.new(t)
	var me := k.local
	var id := me.player_id
	var rules := PowerScore.rules
	var events := []
	var on_defeat := func(e: Dictionary) -> void: events.append(e)
	Combat.player_defeated.connect(on_defeat)

	var prey := k.dummy(Vector3(0, 0, -2))
	t.check(PowerScore.score(prey.player_id) == rules.base_score, "players start at the base Power score", str(rules.base_score))
	var my0 := PowerScore.score(id)

	# Monster defeats a human.
	k.place(me, Vector3.ZERO, 0.0)
	await k.reveal(me)
	k.place(prey, Vector3(0, 0, -2))
	prey.combatant.set_health(10)
	Combat.request_action(id, "attack")
	await k.seconds(0.4)
	t.check(GameState.get_state(prey.player_id) == PlayerState.State.DEFEATED, "the claw defeats the weakened human")
	t.check(PowerScore.score(id) == my0 + rules.prey_reward, "monster gains Power for the defeat", "%d" % PowerScore.score(id))
	t.check(PowerScore.score(prey.player_id) == rules.base_score - rules.prey_penalty, "the defeated human loses a little Power")
	var e: Dictionary = events.back()
	PowerScore._on_defeated(e)
	PowerScore._on_defeated(e)
	t.check(PowerScore.score(id) == my0 + rules.prey_reward and PowerScore.score(prey.player_id) == rules.base_score - rules.prey_penalty,
		"replaying the same defeat event changes nothing (no duplicate rewards)")
	t.check(Combat.apply_damage(prey.player_id, 50, id, "claw") == 0, "a defeated player cannot be hit again")
	t.check(not Combat.request_action(prey.player_id, "attack")["ok"], "a defeated player cannot act")

	# Defeat -> respawn for a human ends HUMAN, healthy, protected.
	await k.seconds(Combat.defeat_duration + 0.2)
	t.check(GameState.get_state(prey.player_id) == PlayerState.State.RESPAWNING, "defeat moves to RESPAWNING after the delay")
	await k.seconds(Combat.respawn_delay + 0.2)
	t.check(GameState.get_state(prey.player_id) == PlayerState.State.HUMAN, "a defeated human respawns as HUMAN")
	t.check(prey.combatant.health == 100 and not prey.is_defeated, "respawned with full health and control")
	t.check(Combat.apply_damage(prey.player_id, 10, id, "claw") == 0, "respawn protection blocks damage briefly")
	t.check(prey.global_position.distance_to(me.global_position) > 30.0, "respawn point is away from the monster")

	# Humans defeat the monster: penalty, slayer and assist, once each.
	var a := k.dummy(Vector3(1.2, 0, -1.8))
	var b := k.dummy(Vector3(-1.2, 0, -1.8))
	k.face(a, me.global_position)
	k.face(b, me.global_position)
	await k.frames(3)
	var my1 := PowerScore.score(id)
	me.combatant.set_health(20)
	me.combatant.invulnerable_until = -INF
	Combat.request_action(a.player_id, "attack")
	await k.seconds(0.3)
	Combat.request_action(b.player_id, "attack")
	await k.seconds(0.3)
	t.check(GameState.get_state(id) == PlayerState.State.DEFEATED, "two sword strikes finish a weakened monster")
	t.check(PowerScore.score(id) == my1 - rules.monster_defeat_penalty, "the monster loses Power when defeated", "%d" % PowerScore.score(id))
	t.check(PowerScore.score(b.player_id) == rules.base_score + rules.monster_slayer_reward, "the slayer gains Power")
	t.check(PowerScore.score(a.player_id) == rules.base_score + rules.monster_assist_reward, "the assisting human gains Power")
	PowerScore._on_defeated(events.back())
	t.check(PowerScore.score(id) == my1 - rules.monster_defeat_penalty and PowerScore.score(b.player_id) == rules.base_score + rules.monster_slayer_reward,
		"monster defeat rewards are applied exactly once")
	var vis: AvatarVisual = me.get_node("AvatarVisual")
	await k.frames(2)
	t.check(vis.form_rig == null and is_equal_approx(me.capsule.height, 1.8), "the defeated monster drops back to its human body")
	await k.seconds(0.8)
	t.check(me.is_defeated and me.head.rotation.z > 0.3 and me.head.position.y < 1.0, "defeat camera plays (camera falls and tilts)")
	t.check(not Combat.request_transform(id)["ok"], "cannot transform while defeated")

	# Respawn: still the monster, but hidden, controllable and on cooldown.
	await k.seconds(Combat.defeat_duration + Combat.respawn_delay - 0.4)
	t.check(GameState.get_state(id) == PlayerState.State.MONSTER_HIDDEN, "a defeated monster respawns MONSTER_HIDDEN (keeps its powers)")
	t.check(me.combatant.health == 100 and me.combatant.max_health == 100, "respawns with full human health")
	t.check(not me.is_defeated and absf(me.head.rotation.z) < 0.001 and absf(me.head.position.y - me.stand_eye) < 0.05, "camera restored after respawn")
	var p0 := me.global_position
	var drv := PlayerDriver.new(me)
	drv.set_input(Vector2(0, 1))
	await k.seconds(0.6)
	drv.set_input()
	t.check(me.global_position.distance_to(p0) > 1.5, "movement works after respawn")
	drv.release()
	t.check(Combat.request_transform(id)["reason"] == "cooldown", "transform is on cooldown after respawning")

	# Escape reward: hit once, get clear, collect once.
	var runner := k.dummy(Vector3(0, 0, -2))
	Combat.respawn_point_provider = t.main._respawn_point
	me.combatant.invulnerable_until = -INF
	var cd = Combat._actors[id]
	cd.transform_ready_at = 0.0
	k.place(me, Vector3.ZERO, 0.0)
	await k.reveal(me)
	k.place(runner, Vector3(0, 0, -2))
	await k.frames(2)
	Combat.request_action(id, "attack")
	await k.seconds(0.4)
	t.check(runner.combatant.health == 82, "the monster wounds the runner")
	k.place(runner, Vector3(-35, 0, 0))
	await k.seconds(rules.escape_time + 0.5)
	t.check(PowerScore.score(runner.player_id) == rules.base_score + rules.escape_reward, "escaping the monster earns Power")
	await k.seconds(rules.escape_time + 0.5)
	t.check(PowerScore.score(runner.player_id) == rules.base_score + rules.escape_reward, "the escape reward is granted once")

	# Power is not combat strength.
	var claw := GameState.monster_definition("ember_beast").ability("claw")
	t.check(claw.damage == 18 and me.combatant.max_health == 250, "Power does not change damage or health")

	# The state machine refuses invalid transitions.
	t.check(not GameState.transition(runner.player_id, PlayerState.State.MONSTER_REVEALED), "HUMAN cannot jump to MONSTER_REVEALED")
	t.check(not GameState.transition(runner.player_id, PlayerState.State.RESPAWNING), "HUMAN cannot jump to RESPAWNING")
	t.check(not PlayerState.can_transition(PlayerState.State.RESPAWNING, PlayerState.State.HUMAN, true), "a monster cannot respawn as a plain HUMAN")
	t.check(not PlayerState.can_transition(PlayerState.State.DEFEATED, PlayerState.State.MONSTER_REVEALED, true), "DEFEATED cannot go straight back to revealed")
	Combat.player_defeated.disconnect(on_defeat)
	await k.cleanup()
