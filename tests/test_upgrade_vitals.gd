extends Node
func run(t) -> void:
	var c: CampaignDirector = t.main.campaign
	var p: PlayerController = t.main.player
	var driver := PlayerDriver.new(p)
	p.teleport(SpawnValidator.find(t.world,Vector2(-232,108)).position,0)
	await driver.frames(10)
	t.main.hud._update_interaction_prompt()
	t.check(not t.main.hud._prompt.text.contains("[G]"),"no central sit prompt")
	t.check(not t.main.combat_hud._stamina_bar.visible,"commander stamina HUD hidden")
	t.check(t.main.healing_loot == null,"no potion drop controller instantiated")
	p.combatant.set_health(100)
	Combat.apply_damage(p.player_id,20,-1,"test")
	await driver.frames(120)
	t.check(p.combatant.health==80,"no regeneration before three-second damage delay")
	await driver.frames(240)
	t.check(p.combatant.health>=85 and p.combatant.health<=87,"regeneration averages two HP per second after delay",str(p.combatant.health))
	Combat.apply_damage(p.player_id,10,-1,"test")
	var health := p.combatant.health
	await driver.frames(120)
	t.check(p.combatant.health==health,"new damage resets regeneration delay")
	driver.set_input(Vector2(0,1),true)
	await driver.frames(420)
	driver.set_input()
	t.check(p.stamina==p.max_stamina and not p.exhausted,"sustained commander sprint consumes no energy")
	var enemy := SoldierFactory.spawn(self,t.world,{"faction":"enemy","id":9999,"mission":1,"pos":p.global_position+Vector3(6,0,0)})
	enemy.paused = true
	var coins := c.state.coins
	Combat.apply_damage(enemy.avatar.player_id,999,p.player_id,"test")
	t.check(c.state.coins==coins+500,"valid commander kill awards 500 coins")
	c.vitals._defeated({"victim":enemy.avatar.player_id,"killer":p.player_id})
	t.check(c.state.coins==coins+500,"duplicate death notification cannot award twice")
	var restored := CampaignState.new(c.config)
	t.check(restored.from_dict(c.state.to_dict()) and restored.coins==c.state.coins and restored.coin_rewards.has("1:9999"),"wallet and reward ledger survive save round trip")
	enemy.avatar.queue_free()
	driver.release()
