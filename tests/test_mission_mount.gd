extends Node
func run(t) -> void:
	var c: CampaignDirector = t.main.campaign
	var p: PlayerController = t.main.player
	var drv := PlayerDriver.new(p)
	c.restart_campaign()
	c.speed = 0.05
	t.main.story.speed = 0.01
	c.opening_completed = true
	c.state.transition(1,CampaignState.M.BRIEFING_AVAILABLE)
	await c.brief(1)
	var ground := SpawnValidator.find(t.world,Vector2(150,-62))
	p.teleport(ground.position,0)
	await drv.frames(10)
	await c.toggle_army()
	var horse: Horse = t.main.horse
	horse.teleport(ground.position+Vector3(1.3,0,0),0)
	var rider := p.get_node("Rider") as Rider
	await drv.frames(10)
	t.check(rider.mount(horse),"commander mounts existing horse in open field")
	await drv.frames(1200)
	var count := 0
	var horses := {}
	for b in c.army.living():
		if b.mode == SoldierBrain.Mode.MOUNTED:
			count += 1
			if b.horse:
				horses[b.horse] = true
	t.check(count==4 and horses.size()==4,"four escorts each mount a distinct real horse",str(count))
	drv.set_input(Vector2(0,1))
	await drv.frames(240)
	drv.set_input()
	var facing := 0
	for b in c.army.living():
		if b.horse and b.horse.forward().dot(horse.forward()) > 0:
			facing += 1
	t.check(facing==4,"mounted formation travels in leader's general direction",str(facing))
	rider.force_dismount()
	await drv.frames(120)
	var on_foot := true
	for b in c.army.living():
		on_foot = on_foot and b.horse==null and not b.avatar.riding
	t.check(on_foot,"all escorts return to foot formation on dismount")
	await c.toggle_army()
	drv.release()
