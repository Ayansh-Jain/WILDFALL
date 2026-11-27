extends Node
## R02 player integration, played through the real arena, Combat and physics.
##   godot --headless --fixed-fps 60 --path . res://tests/r02_player.tscn
var passed := 0
var failed := 0
var arena: CombatArena
var p: PlayerController
var abilities: PlayerAbilities
var feedbacks: Array = []


func check(ok: bool, label: String, detail := "") -> void:
	if ok:
		passed += 1
		print("PASS ", label, "" if detail == "" else "  (%s)" % detail)
	else:
		failed += 1
		print("FAIL ", label, "" if detail == "" else "  (%s)" % detail)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("FAIL watchdog")
		get_tree().quit(3))
	arena = (load("res://scenes/arena/combat_arena.tscn") as PackedScene).instantiate()
	add_child(arena)
	while not arena.ready_done:
		await get_tree().physics_frame
	p = arena.player
	abilities = p.get_node("PlayerAbilities") if p.has_node("PlayerAbilities") else null
	if abilities == null:
		for c in p.get_children():
			if c is PlayerAbilities:
				abilities = c
	arena.training.feedback.connect(func(text: String, good: bool) -> void: feedbacks.append([text, good]))
	await frames(30)
	await _setup_checks()
	await _combat_checks()
	await _training()
	await _stations()
	await _escort()
	await _formation()
	await _leave()
	print("[r02-player] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)


func _setup_checks() -> void:
	check(abilities != null and abilities.sword_mode(), "the Commander enters the arena with the dual-sword system")
	check(arena.markers.size() >= 8, "showcase wf_markers found", str(arena.markers.size()))
	check(p.is_on_floor(), "safe player spawn stands on ground")
	for id in CombatArena.STATIONS:
		arena._stand_at(id)
		await frames(20)
		check(p.is_on_floor() and p.global_position.distance_to(arena.station_frame(id).at) < 12.0,
			"station '%s' is standable" % id, str(p.global_position.snapped(Vector3.ONE * 0.1)))
	check(InputMap.has_action("guard") and Settings.get_specs("guard") == ["mouse:2"], "guard is a rebindable action on the right mouse button")


func _dummy(distance := 1.7, angle := 0.0) -> PlayerController:
	var dir := p.forward().rotated(Vector3.UP, angle)
	var actor := arena.spawn_enemy(arena.ground_near(p.global_position + dir * distance))
	Combat.configure_sword_actor(actor.player_id, true, "test")
	Combat.swords.allocate(actor.player_id)
	return actor


func _free(actor: PlayerController) -> void:
	Combat.swords.remove(actor.player_id)
	actor.queue_free()
	await frames(3)


func _combat_checks() -> void:
	arena._stand_at("duel")
	Combat.configure_sword_actor(p.player_id)
	await frames(20)
	var rig := (p.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig
	rig._put_sword(false)
	check(abilities.combat_state_name() == "EXPLORE", "sheathed state reads EXPLORE", abilities.combat_state_name())
	var e := _dummy()
	await frames(10)
	var result := abilities.trigger("attack")
	check(result.get("ok", false), "attack from sheathed is accepted")
	await frames(3)
	check(Combat.swords.attacks.has(p.player_id) and rig.sword_drawn, "the draw does not cancel the cut")
	check(abilities.combat_state_name() == "ATTACKING", "state reads ATTACKING", abilities.combat_state_name())
	await frames(60)
	check(e.combatant.health == 50, "the cut lands once", str(e.combatant.health))
	# An early press is held and still links the combination (one press, one follow-up).
	e.combatant.set_health(100)
	abilities.trigger("attack")
	await frames(14)
	abilities.trigger("attack")
	await frames(14)
	check(Combat.pending_ability(p.player_id) != "", "attack running")
	await frames(120)
	check(not Combat.is_busy(p.player_id), "no attack keeps firing after presses stop")
	check(abilities.guard(true) and abilities.combat_state_name() in ["PARRY", "GUARD"], "guard raises", abilities.combat_state_name())
	check(rig.current_hold() == "sword_block", "guard pose shown")
	abilities.guard(false)
	check(rig.current_hold() == "" and not Combat.swords.actors[p.player_id].guard, "guard lowers cleanly")
	# Menu / control lock: nothing is accepted and nothing stays buffered.
	var token := p.locks.acquire("test", ControlLock.COMBAT)
	check(not abilities.trigger("attack").get("ok", false), "no attack while restricted")
	p.locks.release(token)
	await frames(20)
	check(not Combat.is_busy(p.player_id), "a refused press does not attack later")
	await _free(e)
	# Soft facing.
	var side := _dummy(2.0, deg_to_rad(22))
	await frames(10)
	var turn := rad_to_deg(abilities.assist_angle())
	check(turn > 12.0 and turn <= 28.1, "soft facing turns toward the intended opponent", "%.1f deg" % turn)
	await _free(side)
	var behind := _dummy(2.0, PI)
	await frames(10)
	check(abilities.assist_angle() == 0.0, "never turns toward an opponent behind")
	await _free(behind)


## Drives one training lesson the way a player would, reading only what he can see.
func _play_lesson(max_frames: int) -> void:
	var t := arena.training
	var start_lesson := t.lesson
	var wait := 0
	var guard_down_at := -1.0
	for i in max_frames:
		await get_tree().physics_frame
		if not t.active or t.lesson != start_lesson:
			break
		if t.enemies.is_empty():
			continue
		wait = maxi(0, wait - 1)
		var target: PlayerController = null
		var best := INF
		for a in t.enemies:
			if is_instance_valid(a) and not a.is_defeated and a.global_position.distance_to(p.global_position) < best:
				best = a.global_position.distance_to(p.global_position)
				target = a
		if target == null:
			continue
		var to := target.global_position - p.global_position
		var step := t.step_id()
		# The threat: any running enemy attack and when it lands.
		var threat := {}
		for a in t.enemies:
			if is_instance_valid(a) and Combat.swords.attacks.has(a.player_id):
				threat = Combat.swords.attacks[a.player_id].duplicate()
				threat["from"] = a
		if guard_down_at > 0.0 and Combat.now() > guard_down_at:
			abilities.guard(false)
			guard_down_at = -1.0
		if not Combat.swords.attacks.has(p.player_id) and p.locomotion_state() != PlayerController.Loco.DASH:
			var face: PlayerController = threat.get("from", target)
			var look := face.global_position - p.global_position
			p.set_look(atan2(-look.x, -look.z))
		var close := to.length() <= 1.9
		p.input_override = {} if close or step in ["dodge", "parry", "perfect", "guard", "draw"] else {"move": Vector2(0, 0.8)}
		var lead := 0.06 if step == "perfect" else 0.15
		match step:
			"draw":
				if wait == 0:
					(p.get_node("AvatarVisual") as AvatarVisual).human_rig.toggle_swords()
					wait = 120
			"right":
				if close and wait == 0:
					abilities.trigger("attack")
					wait = 50
			"left", "combo":
				if close and wait == 0:
					abilities.trigger("attack")
					wait = 17 if Combat.swords.attacks.has(p.player_id) else 22
			"guard":
				abilities.guard(true)
				guard_down_at = Combat.now() + 0.1
			"parry", "perfect", "trial":
				var want_dodge: bool = step == "trial" and t.goals.parry and not t.goals.dodge
				if not threat.is_empty() and threat.definition.attack_class == "normal" and not want_dodge:
					var remain: float = threat.active - Combat.now()
					if remain <= lead and remain > 0.0 and not bool(Combat.swords.actors[p.player_id].guard):
						abilities.guard(true)
						guard_down_at = threat.active + 0.12
				elif not threat.is_empty() and step == "trial":
					var remain: float = threat.active - Combat.now()
					if remain <= 0.12 and remain > 0.0:
						p.input_override = {"move": Vector2(1, 0)}
						abilities.trigger("ability_1")
				elif step == "trial" and close and wait == 0 and not bool(Combat.swords.actors[p.player_id].guard):
					abilities.trigger("attack")
					wait = 17
			"dodge":
				if not threat.is_empty():
					var remain: float = threat.active - Combat.now()
					if remain <= 0.12 and remain > 0.0:
						p.input_override = {"move": Vector2(1, 0)}
						abilities.trigger("ability_1")
			"opening", "counter", "punish":
				if guard_down_at > 0.0:
					abilities.guard(false)
					guard_down_at = -1.0
				if close and wait == 0:
					abilities.trigger("attack")
					wait = 12
	abilities.guard(false)
	p.input_override = null


func _training() -> void:
	arena.start_station("training")
	await frames(40)
	var t := arena.training
	check(t.active and t.lesson_id() == "twin_blades" and t.enemies.size() == 1, "training starts with an instructor")
	# Pressing without the outcome does not pass a step.
	t.start(1)
	await frames(10)
	abilities.guard(true)
	await frames(5)
	abilities.guard(false)
	await frames(10)
	check(t.step_id() == "parry", "pressing guard teaches the stance but does not pass the parry", t.step_id())
	t.enemies[0].global_position.x += 0.0
	abilities.guard(true)
	await frames(20)
	abilities.guard(false)
	check(t.step_id() == "parry", "a parry press with no incoming blow does not count")
	# Standing still and being struck: feedback, same step, health restored.
	feedbacks.clear()
	await frames(300)
	check(t.step_id() == "parry" and p.combatant.health == p.combatant.max_health and not p.is_defeated and not feedbacks.is_empty(),
		"failure gives feedback, restores health and stays on the step", str(feedbacks.size()))
	t.start(0)
	var names := ["twin_blades", "warrior_guard", "balance", "falling_leaf", "trial"]
	for i in names.size():
		feedbacks.clear()
		await _play_lesson(5400 if i == 4 else 2700)
		var last: String = "" if feedbacks.is_empty() else String(feedbacks.back()[0])
		check(t.completed.has(names[i]), "lesson '%s' is completable by real outcomes" % names[i],
			"step %s goals %s last: %s" % [t.step_id(), t.goals, last])
		if not t.completed.has(names[i]):
			t.start(i + 1)
		await frames(10)
	await frames(150)
	check(not t.active, "training ends after the trial")
	check(p.combatant.health == p.combatant.max_health and not p.is_defeated, "Commander leaves training whole")
	check(arena.director.members.is_empty() and Combat.swords.token_actor == -1, "no training enemy or token remains")
	# Skip and leave.
	arena.start_station("training")
	await frames(10)
	t.skip()
	check(t.lesson_id() == "warrior_guard" and not t.completed.is_empty(), "a lesson can be skipped")
	t.stop()
	await frames(5)
	check(not t.active and not Combat.damage_dealt.is_connected(t._on_damage), "leaving removes every training rule")
	arena.clear_station()


func _stations() -> void:
	arena.start_station("group")
	await frames(10)
	check(arena.enemies.size() == 5 and arena.director.members.size() == 5, "group station has five opponents")
	var most := 0
	for i in 600:
		await get_tree().physics_frame
		var committed := 0
		for a in arena.enemies:
			if is_instance_valid(a) and Combat.swords.attacks.has(a.player_id):
				committed += 1
		most = maxi(most, committed)
		p.combatant.set_health(p.combatant.max_health)
	check(most == 1, "exactly one regular enemy commits at a time", "max %d" % most)
	Combat.apply_damage(p.player_id, 999, -1, "test")
	await frames(20)
	check(p.is_defeated and abilities.combat_state_name() == "DEAD", "player death in a station")
	check(not abilities.trigger("attack").get("ok", false) and not abilities.guard(true), "no actions while dead")
	abilities.guard(false)
	arena.retry()
	await frames(20)
	check(not p.is_defeated and p.combatant.health == p.combatant.max_health and arena.enemies.size() == 5, "retry restores the station")
	arena.start_station("elite")
	await frames(10)
	var elite: PlayerController = arena.enemies[0]
	check(elite.combatant.health == CombatArena.ELITE_HEALTH and elite.get_meta("duel_opponent") == p.player_id, "elite duel is protected from allies")
	for a in arena.enemies:
		Combat.apply_damage(a.player_id, 9999, p.player_id, "test")
	await frames(20)
	check(arena._won, "victory is recognised")
	arena.clear_station()
	await frames(10)
	check(arena.director.members.is_empty() and Combat.swords.token_actor == -1, "clearing releases everything")


func _escort() -> void:
	arena._stand_at("spawn")
	await frames(20)
	var saved := FileAccess.get_file_as_string("user://campaign_save.json") if FileAccess.file_exists("user://campaign_save.json") else ""
	arena.toggle_escort()
	await frames(30)
	var brains := arena.escort_brains()
	check(brains.size() == 4, "T summons four living roster soldiers", str(brains.size()))
	var ids := brains.map(func(b) -> int: return b.soldier_id)
	var before: Array = brains.map(func(b) -> Vector3: return b.avatar.global_position)
	var clear := true
	for i in before.size():
		clear = clear and before[i].distance_to(p.global_position) > 1.0
		for j in i:
			clear = clear and before[i].distance_to(before[j]) > 1.0
	check(clear, "formation does not overlap the Commander or itself")
	check(p.forward().dot((before[0] - p.global_position).normalized()) < 0.0, "formation stands behind him")
	p.input_override = {"move": Vector2(0, 1)}
	await frames(180)
	p.input_override = null
	var drift := 0.0
	for i in brains.size():
		drift = maxf(drift, brains[i].avatar.global_position.distance_to(before[i]))
	check(drift < 1.2, "escort holds; it does not follow", "%.2f m" % drift)
	Combat.apply_damage(brains[0].avatar.player_id, 999, -1, "test")
	await frames(10)
	var dead: int = brains[0].soldier_id
	arena.toggle_escort()
	await frames(10)
	check(not arena.escort.active() and arena.escort_brains().is_empty(), "T dismisses")
	arena.toggle_escort()
	await frames(10)
	var again := arena.escort_brains().map(func(b) -> int: return b.soldier_id)
	check(not again.has(dead), "the fallen are not resurrected by dismissing and summoning")
	var living: int = arena.roster.alive_count()
	check(living == arena.roster.roster_size() - 1 and again.size() == mini(4, living), "population is not increased", "%d living, %d called" % [living, again.size()])
	for i in 6:
		arena.toggle_escort()
	await frames(10)
	var bodies := 0
	for c in arena.get_children():
		if c is PlayerController and c.body_style == "soldier:kingdom" and not c.is_queued_for_deletion():
			bodies += 1
	check(bodies <= 4, "repeated T never duplicates soldiers", str(bodies))
	arena.toggle_escort() if not arena.escort.active() else null
	var man = arena.escort_brains()[0]
	arena.escort.sleep(man)
	check(arena.escort.sleeping_count() == 1 and not man.avatar.visible, "a distant soldier can be put to sleep")
	await frames(60)
	check(arena.escort.sleeping_count() == 0 and man.avatar.visible, "and wakes when the Commander is near")
	arena.start_station("army")
	var seen := {}
	arena.escort.command_issued.connect(func(c: String) -> void: seen[c] = true)
	var token_used := false
	for i in 1700:
		await get_tree().physics_frame
		token_used = token_used or Combat.swords.token_actor != -1
	check(seen.has("advance") and seen.has("retreat") and seen.has("regroup") and arena._demo_step == -1, "army display runs advance, engage, retreat, regroup", str(seen.keys()))
	check(not token_used, "army display never takes the Commander attack token")
	check((FileAccess.get_file_as_string("user://campaign_save.json") if FileAccess.file_exists("user://campaign_save.json") else "") == saved, "the arena never writes the campaign save")
	arena.clear_station()


func _wall(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at
	return body


func _formation() -> void:
	var o := Vector3(0, 200, 0)
	var parts := [_wall(o + Vector3(0, -0.5, 0), Vector3(60, 1, 60))]
	await frames(3)
	var space := p.get_world_3d().direct_space_state
	var open := Escort.plan_formation(space, o, 0.0, 4)
	check(open.size() == 4 and absf(open[0].x - open[1].x) > 1.0 and absf(open[0].z - open[2].z) > 1.0, "open ground gives two by two")
	parts.append(_wall(o + Vector3(-1.4, 1.5, 6), Vector3(0.4, 3, 20)))
	parts.append(_wall(o + Vector3(1.4, 1.5, 6), Vector3(0.4, 3, 20)))
	await frames(3)
	var narrow := Escort.plan_formation(space, o, 0.0, 4)
	check(narrow.size() >= 1 and narrow.all(func(v: Vector3) -> bool: return absf(v.x) < 0.9), "a narrow way gives a file inside the walls", str(narrow.size()))
	parts.append(_wall(o + Vector3(0, 1.5, 0.8), Vector3(4, 3, 0.4)))
	await frames(3)
	check(Escort.plan_formation(space, o, 0.0, 4).is_empty(), "no room behind: the summon is refused")
	for part in parts:
		part.queue_free()


func _leave() -> void:
	var id := p.player_id
	arena.queue_free()
	await frames(5)
	check(not Combat.swords.actors.has(id) and Combat.swords.attacks.is_empty() and Combat.swords.token_actor == -1, "leaving the arena leaves no combat state")
	check(Combat.respawn_mode(id) == Combat.Respawn.AUTO, "respawn mode restored")
