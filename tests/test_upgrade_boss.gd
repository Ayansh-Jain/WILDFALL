extends Node
func run(t) -> void:
	var c: CampaignDirector=t.main.campaign
	var p: PlayerController=t.main.player
	var driver:=PlayerDriver.new(p)
	c.speed=0.05
	t.main.story.speed=0.02
	c.restart_campaign()
	c.state.transition(1,CampaignState.M.BRIEFING_AVAILABLE)
	# Stage this focused combat test without replaying the long castle traversal.
	p.teleport(t.main.story.anchor_pos("king_audience"),0)
	await c.brief(1)
	var e:=c.encounter
	var stage: Node=e.boss_stage
	t.check(e.enemies.size()==10 and stage.boss.avatar.combatant.health==400,"ten ordinary enemies plus separate 400 HP giant")
	t.check(not stage.boss.avatar.visible and not stage.bar.visible,"giant and boss HUD hidden before camp clear")
	t.check(e.tent_positions.size()==4,"camp has four medieval black tents")
	var stationary:=true
	for b in e.enemies:
		stationary=stationary and b.patrol.is_empty()
	t.check(stationary,"ordinary guards have no patrol routes")
	p.teleport(e.area_center()+Vector3(-4,0,-5),PI)
	await driver.frames(15)
	c.start_encounter(1)
	for b in e.enemies.duplicate():
		Combat.apply_damage(b.avatar.player_id,1000,p.player_id,"fixture_clear_camp")
	for i in 40:
		await driver.frames(1)
		if stage.started:
			break
	t.check(not e.done and not p.controls_enabled,"ordinary camp clear starts locked celebration, not mission completion")
	for i in 1500:
		await driver.frames(1)
		if stage.duel:
			break
	t.check(stage.boss.avatar.global_position.z > e.tent_positions.back().z+3.5,"giant exits tent even when commander is already nearby")
	t.check(stage.duel and p.controls_enabled and stage.bar.visible,"emergence and challenge release player into duel")
	if DisplayServer.get_name()!="headless":
		await driver.frames(30)
		await RenderingServer.frame_post_draw
		t.get_viewport().get_texture().get_image().save_png("D:/WildFall/Screenshots/upgrade_giant_duel.png")
	t.check(CampaignUtil.flat_dist(stage.boss.avatar.global_position,p.global_position)<22,"giant physically approaches confrontation distance",str(stage.boss.avatar.global_position))
	var boss: PlayerController=stage.boss.avatar
	var ally: SoldierBrain=c.army.living()[0]
	t.check(Combat.apply_damage(boss.player_id,50,ally.avatar.player_id,"sword_strike")==0,"army cannot damage solo-duel boss")
	p.teleport(boss.global_position+Vector3(0,0,2.5),0)
	boss.rotation.y=PI
	p.combatant.set_health(100)
	var before:=p.combatant.health
	for i in 160:
		await driver.frames(1)
		if p.combatant.health<before:
			break
	t.check(p.combatant.health==70,"one valid giant melee contact deals exactly 30 HP",str(p.combatant.health))
	p.combatant.set_health(100)
	var coins:=c.state.coins
	for i in 1000:
		if boss.is_defeated or p.is_defeated:
			break
		driver.face(boss.global_position)
		var distance:=CampaignUtil.flat_dist(p.global_position,boss.global_position)
		driver.set_input(Vector2(0,1) if distance>2.1 else Vector2.ZERO)
		if distance<2.7:
			Combat.request_action(p.player_id,"attack")
		await driver.frames(1)
	driver.set_input()
	await driver.frames(40)
	t.check(boss.is_defeated and not p.is_defeated,"commander defeats giant through central sword combat")
	t.check(c.state.coins==coins+500,"boss death awards exactly 500 coins")
	t.check(e.done and c.state.state_of(1)==CampaignState.M.RETURN_TO_CASTLE,"only giant death unlocks return-to-king objective")
	t.check(not stage.bar.visible,"boss health bar hidden after death")
	driver.release()
