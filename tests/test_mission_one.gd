extends Node
var t
var c: CampaignDirector
var p: PlayerController
var drv: PlayerDriver
var sites: Sites

func run(runner) -> void:
	t = runner
	c = t.main.campaign
	p = t.main.player
	sites = t.world.get_node("Sites/Structures")
	drv = PlayerDriver.new(p)
	c.speed = 0.1
	t.main.story.speed = 0.02
	c.restart_campaign()
	t.main.start_castle_opening()
	await drv.frames(20)
	var door := sites.bedroom_door.get_node("OpenBedroomDoor") as Interactable
	t.check(not door.enabled, "bedroom locked before washroom sequence")
	var result := await walk_local([Vector3(-7.4,12.7,-13.3)])
	t.check(result.ok, "walk to washroom using real controller", result.reason)
	drv.set_input()
	var start := p.global_position
	for i in 700:
		await drv.frames(1)
		if t.main.castle_opening.summons_done and not t.main.story.in_dialogue and p.controls_enabled:
			break
	t.check(t.main.castle_opening.reveal_done and door.enabled, "title reveal and summons unlock the bedroom")
	t.check(p.global_position.distance_to(start) < 1.0 and p.camera.current, "cinematic returns to same washroom and camera")
	result = await walk_local([Vector3(-3.2,12.7,-8.7)])
	look(door.focus_point())
	await drv.frames(5)
	t.check((p.get_node("Interactor") as PlayerInteractor).try_interact(), "player opens bedroom door after summons")
	await drv.frames(60)
	result = await walk_local([Vector3(-3.2,0,-5.5),Vector3(-3.2,0,-1.4),Vector3(8,0,-1.4),Vector3(15.7,0,-5.7),Vector3(19.4,0,-5.9),Vector3(19.4,0,3.5),Vector3(23.4,0,3.5),Vector3(23.4,0,-5.8),Vector3(19.5,0,-5),Vector3(14,0,-5),Vector3(8,0,-5),Vector3(8,0,-12),Vector3(8,0,-18.8)])
	t.check(result.ok and sites.castle_from_world(p.global_position).y < 1, "walk bedroom to throne hall without teleport", result.reason)
	var greeting: Interactable = c.king.talk
	await drv.walk([greeting.global_position], {"reach":1.6})
	look(greeting.focus_point())
	await drv.frames(5)
	t.check((p.get_node("Interactor") as PlayerInteractor).try_interact(), "royal briefing through actual throne interaction")
	await drv.frames(150)
	t.check(c.state.state_of(1) == CampaignState.M.ACTIVE and c.encounter.enemies.size() == 10, "mission one active with ten designated enemies")
	await c.toggle_army()
	t.check(c.deployed and c.army.living().size() == 4, "four soldiers assembled under fade")
	result = await walk_local([Vector3(8,0,-12),Vector3(8,0,-5),Vector3(8,0,10),Vector3(8,0,16)])
	t.check(result.ok,"walk from throne hall through castle exit",result.reason)
	var horse: Horse = t.main.horse
	var rider := p.get_node("Rider") as Rider
	await drv.walk([horse.global_position + horse.global_basis.x * 1.2], {"reach":0.8})
	t.check(rider.mount(horse), "commander mounts his existing horse")
	await drv.frames(600)
	var mounted := 0
	for b in c.army.living():
		if b.mode == SoldierBrain.Mode.MOUNTED:
			mounted += 1
	t.check(mounted > 0, "assigned soldiers mount real available horses", str(mounted))
	rider.dismount()
	await drv.frames(250)
	for b in c.army.living():
		t.check(not b.weapons_free and b.avatar.global_position.distance_to(p.global_position) < 20, "escort assembled locally and holds fire")
	var o := sites.castle_origin
	result = await drv.walk([o + Vector3(-34,0,sites.castle_gate_z),o + Vector3(-57,0,sites.castle_gate_z),o + Vector3(-70,0,sites.castle_gate_z),o + Vector3(-74,0,9)], {"reach":1.0,"leg_timeout":25})
	t.check(result.ok, "leave castle along existing approach", result.reason)
	var stage := CampaignUtil.v3(t.world, [-28,-107])
	var route := c.route.route(p.global_position, stage)
	var points: Array = []
	for point in route:
		points.append(point)
	points.append(stage)
	result = await drv.walk(points, {"reach":2.0,"leg_timeout":35})
	t.check(result.ok, "travel to jungle camp via existing route network", result.reason)
	await drv.frames(120)
	t.check(c.can_plan(), "hidden approach enables strategy")
	c.tactical.open_map()
	c.tactical.place_group()
	t.check(not c.deployment_valid(c.encounter.area_center()), "reject deployment within detection boundary")
	var placements: Dictionary = c.tactical.placements.duplicate()
	c.tactical.ask_confirm()
	c.tactical.confirmation.hide()
	t.check(c.tactical.placements == placements, "cancel retains tactical placements")
	await c.deploy_strategy(placements)
	t.check(c.strategy_confirmed and not c.tactical.visible, "confirmed plan deploys through fade")
	var start_ms := Time.get_ticks_msec()
	var worst_frame := 0.0
	var frames := 0
	while not c.encounter.done and not p.is_defeated and Time.get_ticks_msec() - start_ms < 180000:
		var nearest: SoldierBrain = null
		var best := INF
		for b in c.encounter.enemies:
			if is_instance_valid(b) and b.is_alive():
				var d := p.global_position.distance_to(b.avatar.global_position)
				if d < best:
					best = d
					nearest = b
		if nearest == null:
			break
		drv.face(nearest.avatar.global_position)
		drv.set_input(Vector2(0,1) if best > 1.9 else Vector2.ZERO, best > 5)
		if best < 2.5:
			Combat.request_action(p.player_id, "special_attack" if Combat.cooldown_remaining(p.player_id,"sword_finisher") <= 0 else "attack")
		await drv.frames(1)
		worst_frame = maxf(worst_frame, get_process_delta_time())
		frames += 1
	drv.set_input()
	await drv.frames(100)
	print("[mission performance] frames=%d elapsed_ms=%d max_frame_ms=%.2f kills=%d" % [frames,Time.get_ticks_msec()-start_ms,worst_frame*1000,c.encounter.kills])
	t.check(not p.is_defeated and c.encounter.kills == 10, "commander and four allies defeat all ten using real attack windows")
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
	t.check(c.state.state_of(1) == CampaignState.M.RETURN_TO_CASTLE and not c.army.is_following(), "victory regroups survivors and enables report")
	if c.state.state_of(1) == CampaignState.M.RETURN_TO_CASTLE:
		var return_points: Array = []
		var outside := o + Vector3(-74,0,9)
		for point in c.route.route(p.global_position, outside):
			return_points.append(point)
		return_points.append(outside)
		result = await drv.walk(return_points,{"reach":2.0,"leg_timeout":35})
		t.check(result.ok,"return from camp on existing roads",result.reason)
		result = await drv.walk([o+Vector3(-70,0,sites.castle_gate_z),o+Vector3(-57,0,sites.castle_gate_z),o+Vector3(-34,0,sites.castle_gate_z),sites.castle_to_world(Vector3(8,0,16)),sites.castle_to_world(Vector3(8,0,10)),sites.castle_to_world(Vector3(8,0,-5)),sites.castle_to_world(Vector3(8,0,-12)),t.main.story.anchor_pos("king_audience")],{"reach":0.8,"leg_timeout":25})
		t.check(result.ok,"survivors accompany commander back to castle",result.reason)
		look(c.king.talk.focus_point())
		await drv.frames(5)
		t.check((p.get_node("Interactor") as PlayerInteractor).try_interact(),"report to king through actual interaction")
		await drv.frames(150)
		t.check(c.state.state_of(1) == CampaignState.M.COMPLETE and not c.deployed, "report dismisses army and preserves roster")
	drv.release()

func walk_local(points: Array) -> Dictionary:
	var world_points: Array = []
	for point in points:
		world_points.append(sites.castle_to_world(point))
	return await drv.walk(world_points,{"reach":0.5,"leg_timeout":20})

func look(target: Vector3) -> void:
	var d := target - p.eye_position()
	p.set_look(atan2(-d.x,-d.z), atan2(d.y,Vector2(d.x,d.z).length()))
