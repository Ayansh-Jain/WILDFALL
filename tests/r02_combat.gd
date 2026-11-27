extends Node
var passed := 0
var failed := 0
var arena: Node3D
var p: PlayerController
var e: PlayerController
var events := []

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS ",label)
	else:
		failed += 1
		print("FAIL ",label)

func step(seconds: float) -> void:
	Combat._physics_process(seconds)

func clean() -> void:
	Combat.cancel_attack(p.player_id, "test reset")
	Combat.cancel_attack(e.player_id, "test reset")
	Combat.revive(p.player_id, Vector3(0,0.1,0), 0.0)
	Combat.revive(e.player_id, Vector3(0,0.1,-1.7), PI)
	Combat.configure_sword_actor(p.player_id)
	Combat.configure_sword_actor(e.player_id,true)
	Combat.swords.allocate(e.player_id)
	p.combatant.invulnerable_until = -INF
	e.combatant.invulnerable_until = -INF
	p.input_override = {}
	e.input_override = {}
	events.clear()

func _ready() -> void:
	arena = preload("res://scenes/battle/battle_demo.tscn").instantiate()
	add_child(arena)
	arena.director.enabled = false
	p = arena.player
	e = arena.enemies[0]
	for i in 5:
		await get_tree().physics_frame
	Combat.set_physics_process(false)
	Combat.swords.event.connect(func(data: Dictionary) -> void: events.append(data))
	clean()
	var result: Dictionary = Combat.request_action(p.player_id,"attack")
	check(result.ok,"attack requested")
	check(p.get_node("AvatarVisual").human_rig.swords_in_hand() == 2,"attack starting sheathed equips both visible blades")
	step(0.1)
	check(e.combatant.health == 100,"startup has no damage")
	step(0.13)
	check(e.combatant.health == 50,"active hit deals baseline 50")
	check(not Combat.swords.resolve_hit(p.player_id,result.instance,0),"duplicate marker rejected")
	check(not Combat.request_action(p.player_id,"attack").ok,"early combo input rejected")
	step(0.20)
	check(Combat.request_action(p.player_id,"attack").get("buffered",false),"late input buffers one follow-up")
	check(not Combat.request_action(p.player_id,"attack").ok,"second buffered input rejected")
	step(0.22)
	check(Combat.pending_ability(p.player_id) == "dual_left","buffer advances to left sword")
	clean()
	result = Combat.request_action(p.player_id,"attack")
	Combat.cancel_attack(p.player_id,"cinematic")
	step(0.4)
	check(e.combatant.health == 100 and not Combat.swords.resolve_hit(p.player_id,result.instance,0),"cancellation rejects delayed damage and stale identity")
	clean()
	e.teleport(Vector3(0,0.2,-7))
	Combat.request_action(p.player_id,"attack")
	step(0.3)
	check(e.combatant.health == 100,"out of range misses")
	for x in [-1.7,1.7]:
		clean()
		e.teleport(Vector3(x,0.2,0))
		Combat.request_action(p.player_id,"attack")
		step(0.3)
		check(e.combatant.health == 100,"both sides outside facing arc miss %s" % x)
	clean()
	Combat.set_team(e.player_id,"kingdom")
	check(Combat.apply_damage(e.player_id,50,p.player_id,"test") == 0,"authority rejects friendly damage")
	Combat.set_team(e.player_id,"enemy")
	for timing in [0.08,0.18,0.30]:
		clean()
		Combat.swords.begin(e.player_id,"enemy_standard",p.player_id)
		step(0.5-timing)
		Combat.set_guard(p.player_id,true)
		step(timing+0.001)
		var expected: String = "perfect_parry" if timing < 0.1 else ("parry" if timing < 0.22 else "block")
		check(events.any(func(data: Dictionary) -> bool: return data.kind == expected),expected+" outcome emitted")
		check(p.combatant.health == 100,expected+" prevents damage")
		if timing < 0.22:
			check(Combat.swords.token_actor == -1 and e.combatant.is_stunned(),expected+" cancels token and staggers attacker")
	clean()
	Combat.swords.begin(e.player_id,"enemy_heavy",p.player_id)
	Combat.set_guard(p.player_id,true)
	step(0.86)
	check(p.combatant.health == 75,"unblockable defeats guard")
	clean()
	Combat.swords.begin(e.player_id,"enemy_standard",p.player_id)
	step(0.4)
	check(Combat.request_action(p.player_id,"ability_1").ok,"directional dodge accepted")
	step(0.11)
	check(p.combatant.health == 100,"dodge invulnerability avoids impact")
	check(not Combat.request_action(p.player_id,"ability_1").ok,"dodge recovery prevents chaining")
	clean()
	result = Combat.swords.begin(e.player_id,"enemy_aggressive",p.player_id)
	step(0.39)
	Combat.apply_damage(e.player_id,1,p.player_id,"interrupt")
	step(0.5)
	check(p.combatant.health == 90 and Combat.swords.token_actor == -1,"interrupted combination cannot deliver later strikes")
	clean()
	result = Combat.swords.begin(e.player_id,"enemy_standard",p.player_id)
	step(2.0)
	check(p.combatant.health == 100 and Combat.swords.token_actor == -1,"safety timeout invalidates before release")
	clean()
	Combat.swords.begin(e.player_id,"enemy_standard",p.player_id)
	Combat.apply_damage(e.player_id,100,p.player_id,"test")
	check(Combat.swords.token_actor == -1,"death releases token")
	clean()
	check(not Combat.request_action(p.player_id,"execute").ok,"execution rejects healthy unstaggered target")
	e.combatant.stunned_until = Combat.now()+1
	check(Combat.request_action(p.player_id,"execute").ok,"explicit execution accepts vulnerable positioned target")
	check(e.combatant.health == 100,"execution start does not kill")
	step(0.56)
	check(e.combatant.health == 0,"execution damage occurs at authored marker")

	clean()
	e.teleport(Vector3(0,0.2,1.7),0.0)
	Combat.set_guard(p.player_id,true)
	Combat.swords.begin(e.player_id,"enemy_standard",p.player_id)
	step(0.51)
	check(p.combatant.health == 90,"guard does not block attacks from behind")
	clean()
	Combat.swords.begin(e.player_id,"enemy_standard",p.player_id)
	Combat.set_guard(p.player_id,true)
	step(0.2)
	Combat.set_guard(p.player_id,false)
	step(0.31)
	check(p.combatant.health == 90,"released failed parry takes normal damage")
	clean()
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4,4,0.2)
	shape.shape = box
	wall.add_child(shape)
	arena.add_child(wall)
	wall.position = Vector3(0,1,-0.85)
	await get_tree().physics_frame
	Combat.request_action(p.player_id,"attack")
	step(0.3)
	check(e.combatant.health == 100,"wall blocks actual sword hit")
	clean()
	p.input_override = {"move":Vector2(0,1)}
	Combat.request_action(p.player_id,"ability_1")
	for i in 30:
		await get_tree().physics_frame
	check(p.global_position.z > -0.75,"directional dodge collides with wall")
	wall.queue_free()
	await get_tree().physics_frame
	clean()
	var extra_target: PlayerController = arena.spawn_actor(Vector3(0.8,0.1,-1.7))
	Combat.request_action(p.player_id,"special_attack")
	step(0.36)
	check(e.combatant.health == 0 and extra_target.combatant.health == 0,"Z sweep damages two distinct eligible targets once")
	Combat.unregister(extra_target.player_id)
	extra_target.queue_free()
	clean()
	result = Combat.request_action(p.player_id,"attack")
	var lock := p.locks.acquire("test_cinematic",ControlLock.COMBAT)
	step(0.3)
	check(e.combatant.health == 100 and not Combat.swords.attacks.has(p.player_id),"cinematic control lock cancels attack")
	p.locks.release(lock)
	clean()
	Combat.request_action(p.player_id,"attack")
	p.riding = true
	step(0.3)
	check(e.combatant.health == 100,"mounting cancels pending hit")
	p.riding = false

	clean()
	Combat.set_guard(p.player_id,true)
	var guard_at: float = Combat.swords.actors[p.player_id].guard_at
	step(0.3)
	Combat.swords.begin(e.player_id,"enemy_standard",p.player_id)
	step(0.51)
	check(Combat.swords.actors[p.player_id].guard,"held block stays raised")
	Combat.set_guard(p.player_id,true)
	check(Combat.swords.actors[p.player_id].guard_at == guard_at,"held guard never refreshes parry timestamp")
	clean()
	Combat.set_guard(p.player_id,true)
	Combat.swords.begin(e.player_id,"dual_heavy",p.player_id)
	step(0.56)
	check(p.combatant.health == 30 and not Combat.swords.actors[p.player_id].guard,"heavy strike breaks held guard")
	clean()
	Combat.swords.remove(p.player_id)
	Combat.swords.remove(e.player_id)
	var legacy: AbilityDefinition = GameState.current_form(e.player_id).ability("sword_strike")
	check(Combat._request_ability(e.player_id,legacy).ok,"legacy windup begins before campaign handoff")
	Combat.direct_enemy(e,"campaign-test")
	Combat.enemy_director.enabled = false
	check(Combat._actors[e.player_id].pending.is_empty(),"campaign handoff synchronously cancels legacy windup")
	check(Combat.swords.actors.has(p.player_id) and Combat.swords.actors[e.player_id].reactive,"campaign handoff enables player defense and enemy allocation")
	Combat.enemy_director.unregister_enemy(e.player_id)
	Combat.enemy_director.queue_free()
	Combat.enemy_director = null
	await get_tree().process_frame
	for dt in [1.0/30.0,1.0/60.0,1.0/120.0]:
		clean()
		Combat.request_action(p.player_id,"attack")
		for i in int(ceil(0.7/dt)):
			step(dt)
		check(e.combatant.health == 50,"same strike damage at %.0f Hz" % (1.0/dt))
	clean()
	arena.load_scenario(2)
	check(arena.reactive_count() == 5,"ten enemies allocate exactly five reactive")
	arena.director.enabled = true
	arena.director.turn = 5
	arena.director.selection_deadline = INF
	arena.director.schedule_at = 0
	var rotated: PlayerController = arena.enemies[0]
	rotated.teleport(p.global_position+Vector3(0,0,-1.7),PI)
	arena.director._physics_process(0.2)
	check(Combat.swords.token_actor == rotated.player_id,"rotation skips five non-reactive slots without starvation")
	Combat.cancel_attack(rotated.player_id,"test")
	arena.director.enabled = false

	var first: PlayerController = arena.enemies[0]
	var second: PlayerController = arena.enemies[1]
	Combat.swords.actors[second.player_id].encounter = "overlap"
	check(Combat.swords.begin(first.player_id,"enemy_standard").ok,"first group acquires global token")
	check(not Combat.swords.begin(second.player_id,"enemy_standard").ok,"overlapping group cannot acquire second token")
	Combat.unregister(first.player_id)
	check(Combat.swords.begin(second.player_id,"enemy_standard").ok,"removal releases token for next group")
	arena.load_scenario(4)
	check(arena.roster.soldiers.size() == 200 and arena.roster.pairs.size() == 90,"army has exact approved population and pairs")
	var victim: PlayerController = arena.enemies[0]
	Combat.apply_damage(victim.player_id,50,p.player_id,"dual_right")
	check(not arena.roster.pairs["pair.000"].active and arena.roster.pairs["pair.001"].active,"player damage interrupts only affected pair")
	Combat.apply_damage(victim.player_id,50,p.player_id,"dual_right")
	check(not arena.roster.soldiers["e.000"].alive and arena.roster.soldiers["a.000"].alive,"casualty updates roster and preserves surviving partner")
	check(not arena.roster.resolve("pair.000",0),"interrupted choreography rejects stale casualty")
	var logical_id := -1003
	var logical_position: Vector3 = Combat.logical_actors[logical_id].position
	Combat.revive(p.player_id,logical_position+Vector3(0,0.1,1.7),0.0)
	Combat.configure_sword_actor(p.player_id)
	check(Combat.request_action(p.player_id,"attack").ok,"real sword attack starts against lightweight background soldier")
	step(0.3)
	check(Combat.logical_actors[logical_id].health == 50,"validated weapon hit damages correct logical identity")
	check(not arena.roster.pairs["pair.001"].active and arena.roster.pairs["pair.002"].active,"logical hit interrupts only its choreography")

	arena.load_scenario(4)
	await get_tree().process_frame
	check(Combat.logical_actors.size() == 198,"army retry preserves replacement logical registrations")
	arena.load_scenario(0)
	check(Combat.swords.token_actor == -1 and arena.enemies.size() == 1,"retry clears token and repopulates arena")
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(Combat.swords.attacks.is_empty(),"scene unload leaves no pending attacks")
	print("[r02] %d passed, %d failed" % [passed,failed])
	get_tree().quit(1 if failed else 0)
