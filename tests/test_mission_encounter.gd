extends Node
var measuring := false
var frame_ms: Array[float] = []
var last_usec := 0
func _process(_delta: float) -> void:
	if measuring:
		var now := Time.get_ticks_usec()
		if last_usec > 0:
			frame_ms.append((now-last_usec)/1000.0)
		last_usec = now

func run(t) -> void:
	var c: CampaignDirector = t.main.campaign
	var p: PlayerController = t.main.player
	var drv := PlayerDriver.new(p)
	c.speed = 0.05
	t.main.story.speed = 0.01
	c.restart_campaign()
	c.opening_completed = true
	if c.state.state_of(1) == CampaignState.M.AWAITING_BRIEFING:
		c.state.transition(1,CampaignState.M.BRIEFING_AVAILABLE)
	await c.brief(1)
	var stage := SpawnValidator.find(t.world,Vector2(-28,-107),NAN,8)
	p.teleport(stage.position, 0)
	await drv.frames(10)
	await c.toggle_army()
	t.check(c.deployed and c.army.living().size() == 4,"encounter setup: four deployed allies")
	await drv.frames(30)
	c.tactical.open_map()
	t.check(c.tactical.visible,"planning UI opens while hidden")
	c.tactical.place_group()
	await drv.frames(3)
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("D:/WildFall/Screenshots/mission_strategy.png")
	var placements: Dictionary = c.tactical.placements.duplicate()
	await c.deploy_strategy(placements)
	t.check(c.strategy_confirmed,"tactical ground placements accepted")
	var begin := Time.get_ticks_msec()
	measuring = true
	var worst := 0.0
	var count := 0
	var slash_captured := false
	while not c.encounter.done and not p.is_defeated and Time.get_ticks_msec()-begin < 120000:
		var target: SoldierBrain = null
		var distance := INF
		for b in c.encounter.enemies:
			if is_instance_valid(b) and b.is_alive() and p.global_position.distance_to(b.avatar.global_position) < distance:
				target = b
				distance = p.global_position.distance_to(b.avatar.global_position)
		if not target:
			break
		drv.face(target.avatar.global_position)
		drv.set_input(Vector2(0,1) if distance > 1.9 else Vector2.ZERO, distance > 5)
		if distance < 2.5:
			Combat.request_action(p.player_id,"special_attack" if Combat.cooldown_remaining(p.player_id,"sword_finisher") <= 0 else "attack")
		await drv.frames(1)
		count += 1
		var rig := (p.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig
		if not slash_captured and rig and not rig.trails.is_empty() and rig.trails[0].sample_count() > 2 and DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-capture"):
			slash_captured = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("D:/WildFall/Screenshots/mission_red_slash.png")
		if count == 180 and DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-capture"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("D:/WildFall/Screenshots/mission_combat.png")
		worst = maxf(worst,get_process_delta_time())
	measuring = false
	drv.set_input()
	await drv.frames(90)
	t.check(c.encounter.kills == 10 and not p.is_defeated,"real combat clears designated camp")
	print("[encounter performance] frames=%d elapsed_ms=%d max_frame_ms=%.2f kills=%d health=%d survivors=%d" % [count,Time.get_ticks_msec()-begin,worst*1000,c.encounter.kills,p.combatant.health,c.army.living().size()])
	if not frame_ms.is_empty():
		frame_ms.sort()
		var total := 0.0
		for ms in frame_ms:
			total += ms
		print("[render frame times] average_ms=%.2f p95_ms=%.2f max_ms=%.2f draw_calls=%d" % [total/frame_ms.size(),frame_ms[int(frame_ms.size()*0.95)],frame_ms[-1],Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	var boss_stage: Node = c.encounter.boss_stage
	for i in 1800:
		await drv.frames(1)
		if boss_stage.duel:
			break
	t.check(boss_stage.duel,"camp victory leads to giant confrontation")
	for i in 2400:
		if boss_stage.defeated or p.is_defeated:
			break
		var giant: PlayerController=boss_stage.boss.avatar
		drv.face(giant.global_position)
		var distance:=CampaignUtil.flat_dist(p.global_position,giant.global_position)
		var winding_up := Combat.pending_ability(giant.player_id)=="giant_heavy"
		drv.set_input(Vector2(0,-1) if winding_up and distance<5 else (Vector2(0,1) if distance>2.0 else Vector2.ZERO),distance>6)
		if distance<2.7 and not winding_up:
			Combat.request_action(p.player_id,"special_attack" if Combat.cooldown_remaining(p.player_id,"sword_finisher")<=0 else "attack")
		await drv.frames(1)
	drv.set_input()
	await drv.frames(100)
	t.check(boss_stage.defeated and not p.is_defeated,"commander wins giant duel through real attack windows", "commander HP=%d giant HP=%d player=%s giant=%s" % [p.combatant.health,boss_stage.boss.avatar.combatant.health,str(p.global_position),str(boss_stage.boss.avatar.global_position)])
	# R02: the company no longer follows; survivors form up once and hold.
	t.check(not c.army.is_following() and c.state.state_of(1)==CampaignState.M.RETURN_TO_CASTLE and (c.escort.active() or c.army.living().is_empty()),"survivors regroup and hold after victory")
	if c.encounter.done:
		p.teleport(t.main.story.anchor_pos("king_audience"),0)
		await c.report(1)
		t.check(c.state.state_of(1)==CampaignState.M.COMPLETE and not c.deployed,"report completes mission without losing roster")
	var commander := (p.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig
	if commander:
		commander.sheath_sword()
	await drv.frames(100)
	drv.release()
