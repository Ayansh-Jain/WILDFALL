extends Node
func run(t) -> void:
	var p: PlayerController = t.main.player
	var h: Horse = t.main.horse
	var c: CampaignDirector = t.main.campaign
	var driver := PlayerDriver.new(p)
	p.teleport(SpawnValidator.find(t.world,Vector2(150,-62)).position,0)
	await driver.frames(5)
	c.army.place_at(p.global_position+Vector3(0,0,7),0)
	c.army.set_follow(true)
	var soldier := c.army.living()[0]
	var slot := c.army._raw_slot(soldier)
	p.rotation.y += PI
	await driver.frames(30)
	t.check(slot.distance_to(c.army._raw_slot(soldier))<0.2,"camera yaw does not rotate stationary formation")
	h.teleport(SpawnValidator.find(t.world,Vector2(150,-90)).position,PI)
	h.come_to(p.global_position+Vector3(3.2,0,0))
	for i in 900:
		await driver.frames(1)
		if h._come_target==Vector3.INF:
			break
	t.check(h.global_position.distance_to(p.global_position)<7.0,"near horse recall reaches commander through real movement",str(h.global_position))
	var bridge: Dictionary = t.world.ground_ray(58,172,20,50)
	if t.check(not bridge.is_empty(),"existing stone bridge has a ground surface"):
		var center: Vector3 = bridge.position
		h.teleport(center+Vector3.UP*0.1,0)
		await driver.frames(10)
		t.check(h._water_depth_at(h.global_position)<=h.max_wade_depth,"horse depth query recognizes existing bridge above submerged terrain")
	var original := h.get_instance_id()
	h.teleport(p.global_position+Vector3(200,0,0),0)
	c.speed=0.05
	await t.main.call_horse()
	t.check(h.get_instance_id()==original and h.global_position.distance_to(p.global_position)<8.0,"far recall reuses one personal horse under fade")
	driver.release()

