extends Node
## Ember Beast abilities against the real hit validation (scenario 6), plus
## camera control during combat animations (scenario 5).

var k: CombatKit
var me: PlayerController
var id := -1


func run(t) -> void:
	k = CombatKit.new(t)
	me = k.local
	id = me.player_id
	k.place(me, Vector3.ZERO, 0.0)
	await k.reveal(me)
	var tgt := k.dummy(Vector3(0, 0, -2.0))
	await k.frames(3)

	# Claw: telegraphed, exact damage, cooldown. The monster faces -Z throughout.
	_reset(tgt, Vector3(0, 0, -2.0))
	k.place(me, Vector3.ZERO, 0.0)
	var r := Combat.request_action(id, "attack")
	t.check(r["ok"], "claw starts when a target is in range")
	t.check(tgt.combatant.health == 100, "no damage before the claw wind-up completes")
	await k.seconds(0.3)
	t.check(tgt.combatant.health == 82, "claw deals exactly 18 damage", str(tgt.combatant.health))
	await k.seconds(0.15)
	r = Combat.request_action(id, "attack")
	t.check(not r["ok"] and r["reason"] == "cooldown", "claw cannot be reused during its cooldown", r["reason"])
	await k.seconds(0.45)
	t.check(Combat.request_action(id, "attack")["ok"], "claw is usable again after its 0.7 s cooldown")
	await k.seconds(0.9)

	# Range, facing and walls.
	k.place(me, Vector3.ZERO, 0.0)
	_reset(tgt, Vector3(0, 0, -4.6))
	await _claw_and_wait()
	t.check(tgt.combatant.health == 100, "claw misses a target out of range (4.6 m)")
	_reset(tgt, Vector3(0, 0, 2.0))
	await _claw_and_wait()
	t.check(tgt.combatant.health == 100, "claw misses a target behind the attacker")
	_reset(tgt, Vector3(0, 0, -2.6))
	var wall := k.wall(Vector3(0, 0, -1.35), Vector3(3, 3.5, 0.3))
	await k.frames(3)
	await _claw_and_wait()
	t.check(tgt.combatant.health == 100, "claw cannot hit through a wall")
	wall.queue_free()
	await k.frames(3)

	# Passive proximity never hurts.
	_reset(tgt, Vector3(0, 0, -1.6))
	await k.seconds(3.0)
	t.check(tgt.combatant.health == 100, "standing next to a monster deals no damage without an attack")

	# Heavy Strike: wind-up, damage, stun; dodge; step out; interruption.
	k.place(me, Vector3.ZERO, 0.0)
	_reset(tgt, Vector3(0, 0, -2.5))
	r = Combat.request_action(id, "heavy_attack")
	t.check(r["ok"] and Combat.pending_ability(id) == "heavy_strike", "heavy strike begins a wind-up")
	await k.seconds(0.5)
	t.check(tgt.combatant.health == 100, "heavy strike has not landed mid wind-up")
	await k.seconds(0.5)
	t.check(tgt.combatant.health == 55, "heavy strike deals 45 damage", str(tgt.combatant.health))
	t.check(tgt.combatant.stunned_until > Combat.now() - 0.2, "heavy strike briefly staggers the target")
	await k.seconds(4.2)
	_reset(tgt, Vector3(0, 0, -2.5))
	var dodged := [false]
	var on_dodge := func(target_id: int, _s: int, ab: String) -> void:
		if target_id == tgt.player_id and ab == "heavy_strike":
			dodged[0] = true
	Combat.attack_dodged.connect(on_dodge)
	# The target faces the beast and dodges backwards into a wall, so it stays in
	# range: only the dodge's invulnerability frames can save it.
	tgt.set_look(PI)
	var backstop := k.wall(Vector3(0, 0, -3.5), Vector3(4, 3, 0.3))
	await k.frames(3)
	Combat.request_action(id, "heavy_attack")
	await k.seconds(0.7)
	t.check(Combat.request_action(tgt.player_id, "ability_1")["ok"], "the target dodges during the wind-up")
	await k.seconds(0.4)
	Combat.attack_dodged.disconnect(on_dodge)
	t.check(dodged[0] and tgt.combatant.health == 100, "a well-timed dodge avoids the heavy strike (invulnerability frames)")
	backstop.queue_free()
	await k.seconds(4.2)
	_reset(tgt, Vector3(0, 0, -2.5))
	Combat.request_action(id, "heavy_attack")
	await k.seconds(0.4)
	k.place(tgt, Vector3(0, 0, -7.0))
	await k.seconds(0.7)
	t.check(tgt.combatant.health == 100, "stepping out of range during the wind-up avoids the heavy strike")
	await k.seconds(4.2)
	_reset(tgt, Vector3(0, 0, -2.5))
	var interrupted := [false]
	var on_int := func(actor: int, ab: String) -> void:
		if actor == id and ab == "heavy_strike":
			interrupted[0] = true
	Combat.ability_interrupted.connect(on_int)
	Combat.request_action(id, "heavy_attack")
	await k.seconds(0.3)
	t.check(Combat.request_action(tgt.player_id, "ability_2")["ok"], "the target answers with a ward")
	await k.seconds(0.8)
	t.check(interrupted[0] and tgt.combatant.health == 100, "a ward stun interrupts the heavy strike")
	await k.seconds(4.2)
	interrupted[0] = false
	_reset(tgt, Vector3(0, 0, -2.5))
	me.combatant.stunned_until = -INF
	Combat.request_action(id, "heavy_attack")
	await k.seconds(0.3)
	Combat.apply_damage(id, 16, tgt.player_id, "sword_strike")
	await k.seconds(0.8)
	t.check(interrupted[0] and tgt.combatant.health == 100, "taking 15+ damage during the wind-up interrupts it")
	Combat.ability_interrupted.disconnect(on_int)

	# Stunned players cannot act.
	me.combatant.stunned_until = Combat.now() + 1.0
	r = Combat.request_action(id, "attack")
	t.check(not r["ok"] and r["reason"] == "stunned", "a stunned monster cannot attack")
	me.combatant.stunned_until = -INF
	await k.seconds(1.0)

	# Pounce: leap, landing hit, walls stop it, cooldown.
	k.place(me, Vector3(0, 0, 4), 0.0)
	_reset(tgt, Vector3(0, 0, -4.5))
	await k.frames(5)
	var z0 := me.global_position.z
	r = Combat.request_action(id, "ability_1")
	t.check(r["ok"], "pounce starts")
	await k.seconds(1.6)
	var leap := z0 - me.global_position.z
	t.check(leap > 6.0 and leap < 11.0, "pounce leaps forward about 9 m", "%.1f m" % leap)
	t.check(tgt.combatant.health == 85, "pounce landing hits a nearby target for 15", str(tgt.combatant.health))
	r = Combat.request_action(id, "ability_1")
	t.check(not r["ok"] and r["reason"] == "cooldown", "pounce has a cooldown")
	await k.seconds(8.0)
	k.place(me, Vector3(0, 0, 4), 0.0)
	_reset(tgt, Vector3(8, 0, 0))
	var barrier := k.wall(Vector3(0, 0, 0), Vector3(8, 6, 0.5))
	await k.frames(5)
	Combat.request_action(id, "ability_1")
	await k.seconds(1.6)
	t.check(me.global_position.z > k.center.z + 0.25 + me.capsule.radius - 0.05, "pounce cannot pass through a wall",
		"z %.2f, wall face %.2f" % [me.global_position.z, k.center.z + 0.25])
	barrier.queue_free()
	await k.frames(3)

	# Roar: pressure nearby, reveal positions privately, no global exposure.
	k.place(me, Vector3.ZERO, 0.0)
	_reset(tgt, Vector3(0, 0, -6))
	var far := k.dummy(Vector3(0, 0, -18))
	var very_far := k.dummy(Vector3(-34, 0, 0))
	await k.frames(5)
	var marks := []
	var on_marks := func(actor: int, pos: PackedVector3Array, _d: float) -> void: marks.append([actor, pos.size()])
	Combat.roar_marks.connect(on_marks)
	Combat.request_action(id, "ability_2")
	await k.seconds(0.6)
	Combat.roar_marks.disconnect(on_marks)
	t.check(tgt.combatant.speed_multiplier() < 1.0 and tgt.combatant.is_shaken(), "roar slows and shakes players within 10 m")
	t.check(far.combatant.speed_multiplier() == 1.0, "players beyond the pressure radius are not slowed")
	t.check(marks.size() == 1 and marks[0][0] == id and marks[0][1] == 2, "roar marks 2 nearby players, for the roaring player only", str(marks))
	t.check(tgt.combatant.health == 100, "roar deals no damage")

	# Humans fight with light weapons.
	_reset(tgt, Vector3(4, 0, 0))
	var h2 := far
	k.place(h2, Vector3(4, 0, 1.8))
	k.face(h2, tgt.global_position)
	await k.frames(3)
	Combat.request_action(h2.player_id, "attack")
	await k.seconds(0.3)
	t.check(tgt.combatant.health == 88, "a human sword strike deals 12", str(tgt.combatant.health))

	# Camera control after combat animations.
	var yaw0 := me.rotation.y
	me.look(Vector2(50, 0))
	t.check(absf(me.head.rotation.z) < 0.001 and absf(me.rotation.y - yaw0) > 0.01, "camera stays level and responsive after attacks")
	await k.cleanup()


func _reset(tgt: PlayerController, offset: Vector3) -> void:
	k.place(tgt, offset)
	tgt.combatant.set_health(tgt.combatant.max_health)
	tgt.combatant.reset_status()
	tgt.combatant.invulnerable_until = -INF
	tgt.stamina = tgt.max_stamina
	tgt.input_override = {}


func _claw_and_wait() -> void:
	await k.frames(3)
	Combat.request_action(id, "attack")
	await k.seconds(0.9)
