extends Node
## The campaign, end to end in the real game: the mission state machine and roster
## rules (pure), the King and the evening council, the Mission 2 spies (20 on separate
## patrol points, 10 kills, the retreat), reporting and army growth, the army's follow /
## hold / regroup orders, mounting, Mission 3's retry and quit, Mission 4's 50, Mission 5's
## waves, persistence, and the follow camera underground.

var t
var main: Node
var c: CampaignDirector
var player: PlayerController
var world: World
var cycle: DayNightCycle
var M := CampaignState.M


func run(runner) -> void:
	t = runner
	main = t.main
	c = main.campaign
	player = main.player
	world = t.world
	if not t.check(c != null, "the campaign director exists (one mission manager)"):
		return
	t.check(main.find_children("*", "CampaignDirector", true, false).size() == 1, "there is exactly one campaign director")
	cycle = world.get_node("DayNightCycle") as DayNightCycle
	cycle.start_automatically = false
	c.speed = 0.05
	main.story.speed = 0.02
	_pure_state()
	c.restart_campaign()
	# Mission 1 has its own full playable suite; begin the legacy council arc after it.
	for st in [M.BRIEFING_AVAILABLE,M.BRIEFING,M.ACTIVE,M.ENCOUNTER_ACTIVE,M.OBJECTIVE_COMPLETED,M.RETURN_TO_CASTLE,M.COMPLETE]:
		c.state.transition(1,st)
	c.opening_completed = true
	await _frames(10)
	await _king_and_council()
	await _spies()
	await _report_and_growth()
	await _army_orders()
	await _mounting()
	await _square_retry_quit()
	await _gatefield()
	await _final_battle()
	await _persistence()
	await _camera_underground()
	# Leave the world as the other suites expect it.
	c.restart_campaign()
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.AUTO)
	player.input_override = null
	cycle.start_automatically = true
	main.story.speed = 1.0
	player.teleport(main.player_spawns[0] + Vector3.UP * 0.1)
	await _frames(20)


# --- the model ---------------------------------------------------------------------------------

func _pure_state() -> void:
	var cfg := CampaignState.load_config()
	var s := CampaignState.new(cfg)
	s.new_campaign()
	t.check(s.missions().size() == 5, "five mission slots are registered")
	t.check(s.roster_size() == 4 and s.alive_count() == 4, "the campaign starts with 4 soldiers (plus the commander)")
	t.check(s.state_of(1) == M.AWAITING_BRIEFING, "Mission 1 awaits its gate briefing")
	t.check(s.mission(1).get("type", "") == "camp" and int(s.mission(1).get("enemy_count", 0)) == 10,
		"Mission 1 contains the ten-soldier camp")
	t.check(s.state_of(2) == M.LOCKED and s.state_of(3) == M.LOCKED and s.state_of(5) == M.LOCKED,
		"Later missions remain locked until Mission 1 is reported")
	t.check(not s.transition(2, M.ACTIVE) and not s.transition(3, M.AWAITING_BRIEFING) and not s.transition(1, M.ACTIVE),
		"invalid transitions are refused (no skipped briefing, no early unlock, no reserved start)")
	t.check(not CampaignState.can_transition(M.ENCOUNTER_ACTIVE, M.COMPLETE) and not CampaignState.can_transition(M.FAILED, M.COMPLETE),
		"an encounter cannot jump straight to complete; a failure never completes")
	# Growth: +10 per completed mission, dead stay dead, M5 adds none.
	var g := CampaignState.new(cfg)
	g.new_campaign()
	g.states[1] = M.AWAITING_BRIEFING
	g.states[2] = M.LOCKED
	g.roster[0]["alive"] = false
	var sizes := []
	for id in [1, 2, 3, 4, 5]:
		for st in [M.BRIEFING_AVAILABLE, M.BRIEFING, M.ACTIVE, M.ENCOUNTER_ACTIVE, M.OBJECTIVE_COMPLETED, M.RETURN_TO_CASTLE, M.COMPLETE]:
			if g.state_of(id) == M.LOCKED:
				g.transition(id, M.AWAITING_BRIEFING)
			g.transition(id, st)
		sizes.append(g.roster_size())
	t.check(sizes == [4, 14, 24, 34, 34], "roster grows 4 -> 4 -> 14 -> 24 -> 34 (Mission 5 is the climax)", str(sizes))
	t.check(g.alive_count() == 33 and not g.roster[0]["alive"], "recruits never refill the dead", "%d alive of %d" % [g.alive_count(), g.roster_size()])
	t.check(not g.transition(2, M.COMPLETE) and g.roster_size() == 34, "completing twice is refused and grants nothing")
	t.check(g.campaign_complete, "the campaign is complete after the fifth mission")
	# Checkpoint.
	var k := CampaignState.new(cfg)
	k.new_campaign()
	k.roster[1]["health"] = 60
	k.take_checkpoint(2)
	k.set_soldier(1, false, 0)
	k.set_soldier(2, false, 0)
	k.restore_checkpoint(2)
	t.check(k.alive_count() == 4 and int(k.soldier(2)["health"]) == 60, "restoring the checkpoint returns the exact roster (life and health)")
	t.check(not k.restore_checkpoint(3), "a checkpoint only restores its own mission")
	# Save format.
	var d := k.to_dict()
	var k2 := CampaignState.new(cfg)
	t.check(k2.from_dict(JSON.parse_string(JSON.stringify(d))) and k2.roster == k.roster and k2.states == k.states,
		"the campaign round-trips through its JSON save")
	var bad := d.duplicate(true)
	bad["version"] = 99
	t.check(not CampaignState.new(cfg).from_dict(bad), "a save from another version is refused")
	k.states[2] = M.ENCOUNTER_ACTIVE
	k.take_checkpoint(2)
	k.set_soldier(3, false, 0)
	var k3 := CampaignState.new(cfg)
	k3.from_dict(JSON.parse_string(JSON.stringify(k.to_dict())))
	t.check(k3.state_of(2) == M.RETRY_AVAILABLE and k3.alive_count() == 4,
		"a save taken mid-encounter resumes as retry available with the checkpoint roster")


# --- the King and the evening council -----------------------------------------------------------

func _king_and_council() -> void:
	var king: StoryNPC = c.king
	t.check(king != null and king.rig is KingRig, "the King is placed in the great hall")
	if king == null:
		return
	t.check(king.global_position.distance_to(main.story.anchor_pos("king_throne")) < 0.05, "the King sits on the old lord's chair on the dais")
	cycle.advance_to_hour(10.0)
	await _frames(30)
	t.check(c.state.state_of(2) == M.AWAITING_BRIEFING, "no briefing during the day")
	await _to_king()
	var it := player.get_node("Interactor") as PlayerInteractor
	t.check(it.focused == king.talk, "approaching the King gives an interaction prompt", main.hud.prompt_text())
	t.check(main.hud.prompt_text().contains("Wait for the evening council"), "by day the King's prompt offers to wait for the council")
	# Never during a fight.
	player.combatant.last_combat_time = Combat.now()
	king.talk.interact(player)
	await _frames(10)
	t.check(not main.story.in_dialogue and c.state.state_of(2) == M.AWAITING_BRIEFING, "the King does not interrupt combat")
	player.combatant.last_combat_time = -INF
	king.talk.interact(player)
	await _until(func() -> bool: return not main.story.in_dialogue and not c._busy, 900)
	t.check(c.state.state_of(2) == M.BRIEFING_AVAILABLE and c.is_council_time(), "waiting brings the evening council",
		"%.1f h" % c.current_hour())
	t.check(c.chud.objective_text().contains("Speak with the King"), "the mission panel sends the commander to the King")
	king.talk.interact(player)
	await _frames(3)
	t.check(c.state.state_of(2) == M.BRIEFING and main.story.in_dialogue and main.hud.dialogue_text() != "", "the King's briefing plays through the dialogue UI")
	await _until(func() -> bool: return not main.story.in_dialogue, 1200)
	t.check(c.state.state_of(2) == M.ENCOUNTER_ACTIVE, "after the briefing the spy hunt begins", c.state.state_name(2))
	t.check(c.chud.title_text().contains("MISSION 2") and c.chud.objective_text().contains("spies") and c.chud.progress_text() == "0 / 10",
		"the HUD shows the mission name, objective and 0 / 10", "%s | %s | %s" % [c.chud.title_text(), c.chud.objective_text(), c.chud.progress_text()])
	t.check(not await c.brief(2), "a briefing is shown once (a second one is refused)")
	king.talk.interact(player)
	await _frames(3)
	var line: String = main.hud.dialogue_text()
	await _until(func() -> bool: return not main.story.in_dialogue, 600)
	t.check(line.contains("orders stand") and c.state.state_of(2) == M.ENCOUNTER_ACTIVE, "speaking again gives a reminder, not the briefing", line)
	var before := c.encounter.enemies.size()
	t.check(not c.start_encounter(2) and c.encounter.enemies.size() == before, "the mission cannot be activated twice")


# --- Mission 2: spies ------------------------------------------------------------------------

func _spies() -> void:
	var e := c.encounter
	var spies := e.enemies.duplicate()
	t.check(spies.size() == 20, "Mission 2 fields 20 spies", "%d" % spies.size())
	var min_d := INF
	var on_ground := true
	var routes := {}
	for i in spies.size():
		var a: SoldierBrain = spies[i]
		var p := a.avatar.global_position
		if absf(p.y - world.terrain_height(p.x, p.z)) > 1.2 or world.terrain_height(p.x, p.z) < world.water_level + 0.3:
			on_ground = false
		if not a.patrol.is_empty():
			routes[a.patrol[0].snapped(Vector3.ONE)] = true
		for j in range(i + 1, spies.size()):
			min_d = minf(min_d, CampaignUtil.flat_dist(p, (spies[j] as SoldierBrain).avatar.global_position))
	t.check(min_d > 8.0, "every spy has its own patrol point (not one spawn)", "closest pair %.1f m" % min_d)
	t.check(on_ground, "every spy stands on valid dry ground")
	t.check(routes.size() >= 5, "spies patrol routes all across the kingdom", "%d routes" % routes.size())
	var modes_ok := true
	for b in spies:
		if (b as SoldierBrain).mode != SoldierBrain.Mode.PATROL:
			modes_ok = false
	t.check(modes_ok, "spies patrol their routes")
	var r0 := (spies[0] as SoldierBrain).rig()
	t.check(r0 != null and r0.faction == "enemy" and r0.variant == "spy" and r0.sword_count() == 1,
		"spies wear the enemy's black and carry one sword")
	t.check(Combat.team_of((spies[0] as SoldierBrain).avatar.player_id) == "enemy" and Combat.team_of(player.player_id) == "kingdom",
		"spies and the commander are on opposing sides")
	# A patrolling spy that is attacked fights back (patrol -> alert/combat).
	var s0: SoldierBrain = spies[19]
	Combat.apply_damage(s0.avatar.player_id, 5, player.player_id, "test")
	await _frames(20)
	t.check(s0.mode == SoldierBrain.Mode.COMBAT and s0.target_id == player.player_id, "an attacked spy turns on its attacker")
	# Nine kills: no retreat yet, no premature completion, no double counting.
	for i in 9:
		Combat.apply_damage((spies[i] as SoldierBrain).avatar.player_id, 999, player.player_id, "test")
		await _frames(2)
	e._on_defeated({"victim": (spies[0] as SoldierBrain).avatar.player_id})
	Combat.apply_damage((spies[0] as SoldierBrain).avatar.player_id, 999, player.player_id, "test")
	await _frames(5)
	t.check(e.kills == 9 and c.chud.progress_text() == "9 / 10", "kills are counted once each", "%d, HUD %s" % [e.kills, c.chud.progress_text()])
	t.check(not e.retreating and c.state.state_of(2) == M.ENCOUNTER_ACTIVE, "nine kills are not enough to end the hunt")
	# Stand beside a spy, looking at it, when the tenth falls.
	var watched: SoldierBrain = spies[12]
	var wp := watched.avatar.global_position
	player.teleport(wp + Vector3(0, 0.3, 3.0))
	var d := wp - player.global_position
	player.set_look(atan2(-d.x, -d.z), 0.0)
	await _frames(5)
	var spy_hits := [0]
	var spy_ids := {}
	for b in spies:
		spy_ids[(b as SoldierBrain).avatar.player_id] = true
	var count_hits := func(ev: Dictionary) -> void:
		if spy_ids.has(ev["source"]):
			spy_hits[0] += 1
	Combat.damage_dealt.connect(count_hits)
	Combat.apply_damage((spies[9] as SoldierBrain).avatar.player_id, 999, player.player_id, "test")
	await _frames(3)
	var retreat_all := true
	for i in range(10, 20):
		if (spies[i] as SoldierBrain).mode != SoldierBrain.Mode.RETREAT:
			retreat_all = false
	t.check(e.retreating and retreat_all, "after 10 kills the remaining 10 stop fighting and retreat")
	t.check(e.alive_count() == 10, "nobody vanishes the moment the retreat starts", "%d still there" % e.alive_count())
	var start_gap := CampaignUtil.flat_dist(watched.avatar.global_position, player.global_position)
	var premature := false
	for i in 150:
		await t.get_tree().physics_frame
		var dd := watched.avatar.global_position - player.global_position
		player.set_look(atan2(-dd.x, -dd.z), 0.0)
		if c.state.state_of(2) != M.ENCOUNTER_ACTIVE:
			premature = true
	t.check(is_instance_valid(watched) and is_instance_valid(watched.avatar) and watched.is_alive(),
		"a retreating spy in plain view is not removed in front of the player")
	t.check(is_instance_valid(watched) and CampaignUtil.flat_dist(watched.avatar.global_position, player.global_position) > start_gap + 4.0,
		"it runs for its escape route", "gap %.1f -> %.1f m" % [start_gap, CampaignUtil.flat_dist(watched.avatar.global_position, player.global_position)])
	t.check(spy_hits[0] == 0, "retreating spies do not attack")
	t.check(not premature, "the mission does not complete while spies are still retreating")
	Combat.damage_dealt.disconnect(count_hits)
	# Go back to the castle: the fleeing spies get away out of sight.
	await _to_king()
	await _until(func() -> bool: return c.state.state_of(2) == M.RETURN_TO_CASTLE, 60 * 150)
	t.check(e.escaped_count() == 10 and e.kills == 10, "the ten survivors escape once out of view", "%d escaped" % e.escaped_count())
	t.check(c.state.state_of(2) == M.RETURN_TO_CASTLE and c.chud.objective_text().contains("report"),
		"with the kills confirmed and the retreat over: return to the castle", c.state.state_name(2))
	t.check(not c.state.completed.has(2), "the mission is not complete until reported")


# --- reporting and growth --------------------------------------------------------------------

func _report_and_growth() -> void:
	t.check(c.state.roster_size() == 4, "no soldiers are granted before the report")
	await _talk_to_king()
	t.check(c.state.state_of(2) == M.COMPLETE and c.state.completed.has(2), "reporting to the King completes Mission 2")
	t.check(c.state.roster_size() == 14 and c.state.alive_count() == 14 and c.army.living().size() == 14,
		"ten recruits join: 14 soldiers (Mission 1 grants no recruits)",
		"%d roster, %d in the world" % [c.state.roster_size(), c.army.living().size()])
	await _frames(20)
	t.check(c.state.state_of(3) == M.AWAITING_BRIEFING, "the next orders wait for the next evening's council", c.state.state_name(3))
	await _talk_to_king()
	t.check(c.state.state_of(3) == M.BRIEFING_AVAILABLE, "the next evening the King has new orders")
	var all_one := true
	for b in c.army.living():
		var r := b.rig()
		if r == null or r.sword_count() != 1 or r.faction != "kingdom":
			all_one = false
	t.check(all_one, "every allied soldier wears the kingdom's maroon and carries exactly one sword")


# --- army orders -------------------------------------------------------------------------------

func _army_orders() -> void:
	var a := c.army
	var field := _ground(Vector2(-232, 112))
	player.teleport(field + Vector3.UP * 0.1, 0.0)
	a.place_at(field + Vector3(0, 0, 8), 0.0)
	a.set_follow(true)
	await _frames(30)
	await _drive(Vector2(0, 1), false, 240)
	await _settle(300)
	var near := 0
	for b in a.living():
		if b._flat(a.slot_position(b)) < 6.0:
			near += 1
	t.check(near >= int(a.living().size() * 0.8), "the army follows the commander into formation", "%d/%d at their slots" % [near, a.living().size()])
	t.check(a.status() == "Following" and c.chud.army_text().contains("Following"), "the HUD shows Following", c.chud.army_text())
	var ev := InputEventAction.new()
	ev.action = "army_command"
	ev.pressed = true
	a.set_follow(false)
	await _frames(5)
	t.check(not a.is_following() and a.status().begins_with("Holding"), "explicit hold order settles the company", a.status())
	var held := {}
	for b in a.living():
		held[b] = b.avatar.global_position
	await _drive(Vector2(0, 1), false, 200)
	var drift := 0.0
	for b in held:
		drift = maxf(drift, (b as SoldierBrain).avatar.global_position.distance_to(held[b]))
	t.check(drift < 1.5, "holding soldiers stay where they were ordered", "max drift %.2f m" % drift)
	a.set_follow(true)
	await _frames(5)
	t.check(a.is_following(), "explicit follow order resumes escort")
	# Far away: they regroup along the routes, on foot.
	player.teleport(_ground(Vector2(-150, 150)) + Vector3.UP * 0.1, 0.0)
	await _frames(70)
	t.check(a.status() == "Regrouping", "from far away the army reports Regrouping", a.status())
	var d0 := _mean_dist()
	await _settle(600)
	t.check(_mean_dist() < d0 - 30.0, "regrouping soldiers march toward the commander", "%.0f -> %.0f m" % [d0, _mean_dist()])
	player.teleport(field + Vector3.UP * 0.1, 0.0)
	a.place_at(field + Vector3(0, 0, 8), 0.0)
	await _frames(30)
	# A fallen soldier stays fallen.
	var victim: SoldierBrain = a.living()[0]
	var vid := victim.soldier_id
	Combat.apply_damage(victim.avatar.player_id, 999, -1, "test")
	await _frames(10)
	a.set_follow(false)
	a.set_follow(true)
	a.spawn_missing(field, 0.0)
	await _frames(10)
	t.check(not c.state.soldier(vid)["alive"] and c.state.alive_count() == 13 and a.living().size() == 13 and c.state.roster_size() == 14,
		"dead soldiers are not respawned when the army is called again", "%d alive of %d" % [c.state.alive_count(), c.state.roster_size()])
	# A fight near the company: they switch to combat, then fall back in.
	var foe: PlayerController = main.spawn_bot(field + Vector3(4, 0, 2), SimBot.Role.WANDERER)
	await _frames(40)
	var fighting := 0
	for b in a.living():
		if b.mode == SoldierBrain.Mode.COMBAT:
			fighting += 1
	t.check(fighting == 0, "nearby hostiles do not override the commander's hold-fire order", "%d fighting" % fighting)
	for b in a.living():
		b.weapons_free = true
		b.alert(foe.player_id)
	await _frames(40)
	fighting = 0
	for b in a.living():
		if b.mode == SoldierBrain.Mode.COMBAT:
			fighting += 1
	t.check(fighting > 0, "explicit attack orders engage the nearby hostile", str(fighting))
	Combat.apply_damage(foe.player_id, 999, -1, "test")
	await _frames(90)
	var following := 0
	for b in a.living():
		if b.mode == SoldierBrain.Mode.FOLLOW or b.mode == SoldierBrain.Mode.REGROUP:
			following += 1
	t.check(following == a.living().size(), "after the fight they return to following", "%d/%d" % [following, a.living().size()])
	main.bots.erase(foe)
	foe.queue_free()
	await _frames(5)


func _mean_dist() -> float:
	var s := 0.0
	var n := 0
	for b in c.army.living():
		s += CampaignUtil.flat_dist(b.avatar.global_position, player.global_position)
		n += 1
	return s / maxf(n, 1)


# --- mounting ------------------------------------------------------------------------------------

func _mounting() -> void:
	var a := c.army
	var field := _ground(Vector2(-232, 112))
	player.teleport(field + Vector3.UP * 0.1, 0.0)
	a.place_at(field + Vector3(0, 0, 8), 0.0)
	a.set_follow(true)
	for i in a.horses.size():
		a.horses[i].teleport(_ground(Vector2(-246 + i * 3.5, 128)) + Vector3.UP * 0.05, 0.0)
	main.spawn_horse_near(player)
	await _frames(30)
	var foot := {}
	for b in a.living():
		foot[b] = b.avatar.global_position
	var rider := player.get_node("Rider") as Rider
	rider.mount(main.horse)
	var jump := 0.0
	for i in 900:
		await t.get_tree().physics_frame
		for b in a.living():
			if b.mode != SoldierBrain.Mode.MOUNT and b.mode != SoldierBrain.Mode.MOUNTED:
				jump = maxf(jump, b.avatar.global_position.distance_to(foot[b]))
			foot[b] = b.avatar.global_position
	var mounted := 0
	var seated := true
	for b in a.living():
		if b.mode == SoldierBrain.Mode.MOUNTED:
			mounted += 1
			if b.horse == null or b.horse.rider != b.avatar:
				seated = false
	var expected := mini(a.horses.size(), a.living().size())
	var modes := []
	for b in a.living():
		modes.append(b.mode_name())
	t.check(rider.is_riding() and mounted == expected, "when the commander mounts, soldiers take the company's free horses",
		"%d mounted of %d horses; %s" % [mounted, a.horses.size(), str(modes)])
	t.check(seated, "each mounted soldier sits on his own horse")
	t.check(a.living().size() - mounted > 0 and jump < 1.0, "soldiers without a horse continue on foot (nobody is teleported onto one)",
		"%d on foot, largest per-frame move %.2f m" % [a.living().size() - mounted, jump])
	for i in 300:
		player.input_override = {"move": Vector2(0, 1), "sprint": false}
		await t.get_tree().physics_frame
	player.input_override = {"move": Vector2.ZERO}
	var keep := 0
	for b in a.living():
		if b.mode == SoldierBrain.Mode.MOUNTED and b._flat(player.global_position) < 25.0:
			keep += 1
	t.check(keep == mounted, "mounted soldiers ride with the commander", "%d/%d" % [keep, mounted])
	await _frames(240)
	rider.dismount()
	await _until(func() -> bool: return not rider.is_busy(), 400)
	await _frames(30)
	var still := 0
	for b in a.living():
		if b.mode == SoldierBrain.Mode.MOUNTED or b.mode == SoldierBrain.Mode.MOUNT:
			still += 1
	t.check(still == 0 and a.free_horses().size() == a.horses.size(), "when he dismounts, they dismount and the horses are free")
	var crig := (player.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig
	if crig:
		await _frames(5)
		t.check(crig._pivot.global_basis.y.dot(Vector3.UP) > 0.999, "after dismounting the commander stands upright (no leftover slope tilt from the saddle)")
	player.input_override = null


# --- Mission 3: retry and quit ---------------------------------------------------------------

func _square_retry_quit() -> void:
	await _talk_to_king()
	var e := c.encounter
	t.check(c.state.state_of(3) == M.ACTIVE, "Mission 3 is active after its briefing", c.state.state_name(3))
	t.check(e.enemies.size() == 20 and e.alive_count() == 20, "Mission 3 places exactly 20 enemies", "%d" % e.enemies.size())
	var layout := _positions(e)
	var dormant := true
	for b in e.enemies:
		if b.mode != SoldierBrain.Mode.DORMANT:
			dormant = false
	t.check(dormant, "they wait at Castle Square until the commander arrives")
	await _frames(40)
	t.check(c.state.state_of(3) == M.ACTIVE, "the battle does not start from inside the keep next door")
	var m3 := c.state.mission(3)
	var stage := CampaignUtil.v3(world, m3["commander_stage"])
	player.teleport(stage + Vector3.UP * 0.2, deg_to_rad(-90.0))
	c.army.place_at(CampaignUtil.v3(world, m3["ally_stage"]), deg_to_rad(-90.0))
	await _until(func() -> bool: return c.state.state_of(3) == M.ENCOUNTER_ACTIVE, 120)
	t.check(c.state.state_of(3) == M.ENCOUNTER_ACTIVE, "arriving at the square starts the encounter")
	var cp: Dictionary = c.state.checkpoint
	t.check(int(cp.get("mission", -1)) == 3 and (cp["roster"] as Array).size() == c.state.roster_size(), "the encounter checkpoint is taken as it begins")
	var alive_at_start := c.state.alive_count()
	var size_at_start := c.state.roster_size()
	# Losses, then the commander falls.
	for i in 3:
		Combat.apply_damage(e.enemies[i].avatar.player_id, 999, player.player_id, "test")
	var lost := c.army.living().slice(0, 2)
	for b in lost:
		Combat.apply_damage(b.avatar.player_id, 999, -1, "test")
	await _frames(5)
	t.check(e.kills == 3, "kills count during the encounter")
	Combat.apply_damage(player.player_id, 999, e.enemies[5].avatar.player_id, "test")
	await _frames(int(60.0 * 6.0))
	t.check(c.state.state_of(3) == M.FAILED and player.is_defeated, "the commander's death fails the mission and he stays down (no auto-respawn)",
		c.state.state_name(3))
	t.check(c.chud.failed_visible(), "the mission-failed screen offers Retry and Quit")
	var paused := true
	for b in e.enemies:
		if is_instance_valid(b) and b.is_alive() and not b.paused:
			paused = false
	t.check(paused, "the battle stops safely while the failed screen is up")
	await c.retry()
	await _frames(10)
	t.check(c.state.state_of(3) == M.ENCOUNTER_ACTIVE and not player.is_defeated and player.combatant.health == player.combatant.max_health,
		"Retry restarts the encounter with the commander on his feet")
	t.check(e.kills == 0 and e.alive_count() == 20 and _same_layout(layout, _positions(e)),
		"Retry respawns the same 20 enemies at the same initial positions, counters reset", "%d kills, %d alive" % [e.kills, e.alive_count()])
	t.check(c.state.alive_count() == alive_at_start and c.state.roster_size() == size_at_start and c.army.living().size() == alive_at_start,
		"Retry restores the allied survivors from the checkpoint", "%d alive" % c.state.alive_count())
	t.check(not c.state.completed.has(3) and c.state.roster_size() == size_at_start, "a failed attempt grants no reward")
	# Fail again, and quit this time: the losses stand.
	var dead: SoldierBrain = c.army.living()[0]
	Combat.apply_damage(dead.avatar.player_id, 999, -1, "test")
	await _frames(5)
	var survivors := c.state.alive_count()
	Combat.apply_damage(player.player_id, 999, e.enemies[2].avatar.player_id, "test")
	await _until(func() -> bool: return c.chud.failed_visible(), 600)
	await c.quit_encounter()
	await _frames(40)
	t.check(c.state.state_of(3) == M.RETRY_AVAILABLE and not c.state.completed.has(3), "Quit leaves the mission unfinished (retry available)")
	t.check(not player.is_defeated and CampaignUtil.flat_dist(player.global_position, c._safe_point()) < 10.0, "Quit returns the commander to the castle")
	t.check(c.state.alive_count() == survivors and c.state.roster_size() == size_at_start, "Quit keeps the surviving roster (the fallen stay fallen)",
		"%d alive" % c.state.alive_count())
	t.check(e.alive_count() == 20 and e.kills == 0 and _same_layout(layout, _positions(e)), "the same 20 enemies wait at their initial positions")
	await _frames(60)
	t.check(c.state.state_of(3) == M.RETRY_AVAILABLE, "quitting does not start anything new")
	player.teleport(stage + Vector3.UP * 0.2, deg_to_rad(-90.0))
	await _until(func() -> bool: return c.state.state_of(3) == M.ENCOUNTER_ACTIVE, 120)
	t.check(c.state.state_of(3) == M.ENCOUNTER_ACTIVE and e.alive_count() == 20, "returning to the square restarts the same encounter")
	# Win.
	await _kill_all(e)
	await _until(func() -> bool: return c.state.state_of(3) == M.RETURN_TO_CASTLE, 600)
	t.check(c.state.state_of(3) == M.RETURN_TO_CASTLE and e.kills == 20, "defeating all 20 completes the objective")
	var size_before := c.state.roster_size()
	await _talk_to_king()
	t.check(c.state.state_of(3) == M.COMPLETE and c.state.roster_size() == size_before + 10, "reporting adds ten more soldiers",
		"%d" % c.state.roster_size())


## The encounter's spawn layout (where each enemy was placed this attempt), sorted.
func _positions(e: Encounter) -> Array:
	var out := []
	for p in e.spawn_layout:
		out.append(Vector2(p.x, p.z))
	out.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x or (p.x == q.x and p.y < q.y))
	return out


func _same_layout(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if (a[i] as Vector2).distance_to(b[i]) > 0.6:
			return false
	return true


# --- Mission 4 ----------------------------------------------------------------------------------

func _gatefield() -> void:
	await _talk_to_king()  # waits for the council
	await _talk_to_king()  # the briefing
	var e := c.encounter
	t.check(c.state.state_of(4) == M.ACTIVE and e.enemies.size() == 50, "Mission 4 places exactly 50 enemies", "%d" % e.enemies.size())
	var pos := _positions(e)
	var crowd := 0
	for p in pos:
		var n := 0
		for q in pos:
			if (p as Vector2).distance_to(q) < 6.0:
				n += 1
		crowd = maxi(crowd, n)
	var zs: Array = pos.map(func(p: Vector2) -> float: return p.y)
	t.check(crowd <= 12 and float(zs.max()) - float(zs.min()) > 40.0, "they stand in separate groups across the field, not one cluster",
		"largest knot %d, front %.0f m wide" % [crowd, float(zs.max()) - float(zs.min())])
	var gate := CampaignUtil.v3(world, [-296, 70])
	var before_gate := true
	for p in pos:
		if (p as Vector2).x < gate.x + 10.0:
			before_gate = false
	t.check(before_gate, "the battle is fought in front of the sealed gate (inside the walls)")
	var m4 := c.state.mission(4)
	player.teleport(CampaignUtil.v3(world, m4["commander_stage"]) + Vector3.UP * 0.2, deg_to_rad(90.0))
	await _until(func() -> bool: return c.state.state_of(4) == M.ENCOUNTER_ACTIVE, 120)
	await _frames(40)
	t.check(_count_mode(e, SoldierBrain.Mode.ADVANCE) + _count_mode(e, SoldierBrain.Mode.COMBAT) == 10, "the enemy comes on in groups: the first 10 advance")
	await _frames(int(60.0 * 13.0))
	t.check(_count_mode(e, SoldierBrain.Mode.DORMANT) <= 30, "the next group follows after its interval", "%d still waiting" % _count_mode(e, SoldierBrain.Mode.DORMANT))
	await _kill_all(e)
	await _until(func() -> bool: return c.state.state_of(4) == M.RETURN_TO_CASTLE, 600)
	t.check(c.state.state_of(4) == M.RETURN_TO_CASTLE and e.kills == 50, "all 50 must fall to complete Mission 4")
	await _talk_to_king()
	t.check(c.state.state_of(4) == M.COMPLETE and c.state.roster_size() == 34, "after Mission 4 the roster stands at 34 (Mission 1 grants no recruits)", "%d" % c.state.roster_size())


func _count_mode(e: Encounter, m: int) -> int:
	var n := 0
	for b in e.enemies:
		if is_instance_valid(b) and b.is_alive() and b.mode == m:
			n += 1
	return n


# --- Mission 5 ----------------------------------------------------------------------------------

func _final_battle() -> void:
	await _talk_to_king()
	await _talk_to_king()
	var e := c.encounter
	var m5 := c.state.mission(5)
	var cap := int(m5["max_active"])
	t.check(c.state.state_of(5) == M.ACTIVE and e.designated_count() == 100, "Mission 5 is configured for 100 enemies", "%d" % e.designated_count())
	t.check(e.alive_count() == int(m5["waves"][0]["count"]), "the first wave waits on the field", "%d" % e.alive_count())
	player.teleport(CampaignUtil.v3(world, m5["commander_stage"]) + Vector3.UP * 0.2, deg_to_rad(90.0))
	await _until(func() -> bool: return c.state.state_of(5) == M.ENCOUNTER_ACTIVE, 120)
	var over_cap := 0
	var max_alive := 0
	var captain_seen_at := -1
	var waves := {}
	for step in 4000:
		if e.done:
			break
		max_alive = maxi(max_alive, e.alive_count())
		if e.alive_count() > cap:
			over_cap += 1
		if e.captain() != null and captain_seen_at < 0:
			captain_seen_at = e.spawned_count()
		if e.phase_text != "":
			waves[e.phase_text] = true
		var alive: Array = e.enemies.filter(func(b) -> bool: return is_instance_valid(b) and (b as SoldierBrain).is_alive())
		for b in alive.slice(0, 3):
			Combat.apply_damage(b.avatar.player_id, 9999, player.player_id, "test")
		Combat.heal_player(player.player_id, 100)
		await _frames(20)
	t.check(over_cap == 0, "never more than %d enemies fight at once" % cap, "peak %d" % max_alive)
	t.check(e.spawned_count() == 100 and e.kills == 100, "the whole host of 100 is fielded and must fall", "%d spawned, %d killed" % [e.spawned_count(), e.kills])
	t.check(waves.size() >= 3, "the battle comes in waves with their own objectives", str(waves.keys()))
	t.check(captain_seen_at > 65, "their captain arrives with the last wave", "after %d" % captain_seen_at)
	await _until(func() -> bool: return c.state.state_of(5) == M.RETURN_TO_CASTLE, 600)
	t.check(c.state.state_of(5) == M.RETURN_TO_CASTLE, "the gate holds: return to the King")
	var size := c.state.roster_size()
	await _talk_to_king()
	t.check(c.state.state_of(5) == M.COMPLETE and c.state.campaign_complete and c.state.roster_size() == size,
		"reporting ends the campaign (the climax adds no recruits)")
	t.check(c.state.state_of(1) == M.COMPLETE, "Mission 1 remains completed at the end")


# --- persistence --------------------------------------------------------------------------------

func _persistence() -> void:
	var path := "user://test_campaign_save.json"
	c.save_path = path
	c.persist = true
	c.save()
	c.persist = false
	var f := FileAccess.open(path, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f else null
	f = null
	t.check(d is Dictionary and int(d["version"]) == CampaignState.SAVE_VERSION and (d["completed"] as Array).size() == 5,
		"progress is saved to a small versioned file")
	var s := CampaignState.new(c.config)
	t.check(s.from_dict(d) and s.roster_size() == c.state.roster_size() and s.alive_count() == c.state.alive_count()
		and s.campaign_complete, "the saved campaign loads back with its roster and progress")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- the follow camera underground ------------------------------------------------------------

func _camera_underground() -> void:
	var cave: Dictionary = world.terrain_data.cave
	var floor_h: float = cave.get("floor", 9.0)
	var space := player.get_world_3d().direct_space_state
	for spot in [[Vector2(-32, -198), 0.0, "the cave tunnel"], [Vector2(-32, -206), 90.0, "the cave chamber"], [Vector2(-32, -206), 200.0, "the chamber, other way"]]:
		var p: Vector2 = spot[0]
		player.teleport(Vector3(p.x, floor_h + 0.2, p.y), deg_to_rad(spot[1]))
		await _settle(60)
		var cam := player.camera.global_position
		var surface := world.terrain_height(cam.x, cam.z)
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(cam, cam + Vector3.UP * 10.0, Layers.WORLD))
		var pivot := player.head.global_position
		t.check(cam.y < surface - 1.0 and not up.is_empty(), "in %s the camera stays underground with the commander (under the roof)" % spot[2],
			"camera y %.1f, terrain %.1f" % [cam.y, surface])
		t.check(cam.distance_to(pivot) > 1.0 and (player.camera.cull_mask & CharacterRig.SELF_LAYER) != 0,
			"in %s the commander is in view" % spot[2], "%.2f m from the pivot" % cam.distance_to(pivot))
	# Run and fight through the cave: the camera never pops above ground or into rock.
	player.teleport(Vector3(-32, floor_h + 0.2, -176), 0.0)
	await _settle(30)
	var above := 0
	var inside_rock := 0
	var notes: Array = []
	for i in 200:
		player.input_override = {"move": Vector2(0, 1), "sprint": i > 60}
		if i == 120:
			Combat.request_action(player.player_id, "attack")
		await t.get_tree().physics_frame
		var cam := player.camera.global_position
		var piv := player.head.global_position
		# Never on the far side of rock from him: the line from his shoulders to the lens is clear.
		var blocked := space.intersect_ray(PhysicsRayQueryParameters3D.create(piv, cam, Layers.WORLD, [player.get_rid()]))
		if not blocked.is_empty():
			above += 1
			if notes.size() < 3:
				notes.append("blocked by %s at %s (cam %s piv %s)" % [blocked["collider"].name, str(blocked["position"].snapped(Vector3.ONE * 0.1)), str(cam.snapped(Vector3.ONE * 0.1)), str(piv.snapped(Vector3.ONE * 0.1))])
		# A small sphere at the lens touching any surface = clipping (a point query would
		# call everything under the terrain trimesh "inside", including the open cave).
		var q := PhysicsShapeQueryParameters3D.new()
		var lens := SphereShape3D.new()
		lens.radius = 0.06
		q.shape = lens
		q.transform = Transform3D(Basis.IDENTITY, cam)
		q.collision_mask = Layers.WORLD
		var inside := space.intersect_shape(q, 1)
		if not inside.is_empty():
			inside_rock += 1
			if notes.size() < 6:
				notes.append("inside %s at %s" % [inside[0]["collider"].name, str(cam.snapped(Vector3.ONE * 0.1))])
	player.input_override = {"move": Vector2.ZERO}
	t.check(above == 0 and inside_rock == 0, "walking, running and fighting in the cave, the camera never goes behind or into rock",
		"%d frames behind rock, %d inside rock %s" % [above, inside_rock, str(notes)])
	# The castle crypt, below the courtyard.
	var sites := world.get_node("Sites/Structures")
	var crypt := AABB()
	for z: Dictionary in sites.interior_zones:
		if z["mood"] == "crypt":
			crypt = z["aabb"]
	if crypt.size != Vector3.ZERO:
		var cpos := crypt.get_center()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cpos.x, crypt.end.y - 0.5, cpos.z), Vector3(cpos.x, crypt.position.y, cpos.z), Layers.WORLD))
		if not hit.is_empty():
			player.teleport(hit["position"] + Vector3.UP * 0.2, 0.0)
			await _settle(60)
			var cam := player.camera.global_position
			t.check(cam.y < world.terrain_height(cam.x, cam.z) - 1.0 and crypt.grow(1.0).has_point(cam),
				"in the castle crypt the camera stays below ground with the commander", "camera y %.1f" % cam.y)
	# Open ground still keeps the camera above the terrain.
	player.teleport(_ground(Vector2(-232, 112)) + Vector3.UP * 0.1, 0.0)
	player.set_look(0.0, deg_to_rad(40.0))
	await _settle(40)
	var cam2 := player.camera.global_position
	t.check(cam2.y > world.terrain_height(cam2.x, cam2.z) + 0.3, "outdoors the camera still never dips below the ground")
	player.set_look(0.0, 0.0)
	t.check(get_viewport().get_camera_3d() == player.camera, "the player's follow camera is the only active camera")


# --- helpers ----------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


func _settle(n: int) -> void:
	player.input_override = {"move": Vector2.ZERO}
	await _frames(n)


func _drive(move: Vector2, sprint: bool, n: int) -> void:
	for i in n:
		player.input_override = {"move": move, "sprint": sprint}
		await t.get_tree().physics_frame


func _until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await t.get_tree().physics_frame


func _ground(p: Vector2) -> Vector3:
	var res := SpawnValidator.find(world, p, NAN, 8.0)
	return res["position"] if res["ok"] else Vector3(p.x, world.terrain_height(p.x, p.y), p.y)


func _to_king() -> void:
	player.input_override = {"move": Vector2.ZERO}
	player.teleport(main.story.anchor_pos("king_audience") + Vector3.UP * 0.1, main.story.anchor_yaw("king_audience"))
	await _frames(20)


## Walks up to the King and speaks, waiting out the dialogue (and any wait for council).
func _talk_to_king() -> void:
	await _to_king()
	# The King will not talk in the middle of a fight; the test's last blow was just now.
	player.combatant.last_combat_time = -INF
	c.king.talk.interact(player)
	await _frames(2)
	await _until(func() -> bool: return not main.story.in_dialogue and not c._busy, 3000)
	await _frames(5)


func _kill_all(e: Encounter) -> void:
	for i in 400:
		var alive: Array = e.enemies.filter(func(b) -> bool: return is_instance_valid(b) and (b as SoldierBrain).is_alive())
		if alive.is_empty():
			return
		for b in alive.slice(0, 5):
			Combat.apply_damage(b.avatar.player_id, 9999, player.player_id, "test")
		Combat.heal_player(player.player_id, 100)
		await _frames(6)
