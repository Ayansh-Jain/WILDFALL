extends Node
func run(t) -> void:
	var c: CampaignDirector = t.main.campaign
	var p: PlayerController = t.main.player
	var driver := PlayerDriver.new(p)
	var rider := p.get_node("Rider") as Rider
	c.speed=0.1
	p.teleport(SpawnValidator.find(t.world,Vector2(150,-62)).position,0)
	c.army.place_at(p.global_position+Vector3(0,0,6),0)
	c.army.set_follow(true)
	t.check(c.army.horses.is_empty(),"army has no horses in foot formation")
	t.main.spawn_horse_near(p)
	t.check(rider.mount(t.main.horse),"commander begins coordinated mount")
	t.check(not p.controls_enabled,"mount transition locks commander controls")
	for i in 720:
		await driver.frames(1)
		if rider.is_riding() and not c.army.transitioning:
			break
	var mounted := 0
	for b in c.army.living():
		if b.mode==SoldierBrain.Mode.MOUNTED:
			mounted+=1
	t.check(mounted==4 and c.army.horses.size()==4,"all four commandos mount four temporary horses",str(mounted))
	t.check(p.controls_enabled,"mounted formation restores controls")
	t.check(rider.dismount(),"commander begins coordinated dismount")
	for i in 480:
		await driver.frames(1)
		if not c.army.transitioning and rider.state==Rider.State.NONE:
			break
	t.check(c.army.horses.is_empty(),"army horses removed after dismount")
	t.check(p.controls_enabled and not p.riding,"dismount restores commander controls on foot")
	t.check(is_instance_valid(t.main.horse),"personal horse remains independently available")
	t.main.spawn_horse_near(p)
	rider.mount(t.main.horse)
	for i in 720:
		await driver.frames(1)
		if rider.is_riding() and not c.army.transitioning:
			break
	rider.force_dismount()
	await driver.frames(150)
	t.check(c.army.horses.is_empty() and not c.army.transitioning,"forced dismount also cleans up army horses")
	driver.release()
