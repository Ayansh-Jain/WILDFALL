extends Node
func run(t) -> void:
	var c: CampaignDirector = t.main.campaign
	var p: PlayerController = t.main.player
	var sites: Sites = t.world.get_node("Sites/Structures")
	var driver := PlayerDriver.new(p)
	c.speed = 0.05
	t.main.story.speed = 0.05
	c.restart_campaign()
	t.main.start_castle_opening()
	await driver.frames(20)
	var door := sites.bedroom_door.get_node("OpenBedroomDoor") as Interactable
	t.check(not door.enabled, "bedroom remains locked before washroom reveal")
	var result := await driver.walk([sites.castle_to_world(Vector3(-7.4,12.7,-13.3))], {"reach":0.5,"sprint":false})
	t.check(result.ok, "walk into washroom using real controller", result.reason)
	driver.set_input()
	var position := p.global_position
	for i in 600:
		await driver.frames(1)
		if c.opening_completed and p.controls_enabled:
			break
	t.check(c.opening_completed and door.enabled, "washroom cinematic and summons unlock bedroom")
	t.check(p.global_position.distance_to(position)<0.5 and p.camera.current,"cinematic restores original player position and camera")
	t.check(c.king.global_position.distance_to(t.main.story.anchor_pos("king_throne"))<0.1 and (c.king.rig as KingRig).seated,"king remains seated on royal throne after summons")
	t.check(not t.main.story.triggers.has("OpeningGateAudience"),"no outer-gate mission interaction")
	# Real floor/rail checks at the relocated balcony; terrain and colliders remain enabled.
	result = await driver.walk([sites.castle_to_world(Vector3(-6,12.7,-17)), sites.castle_to_world(Vector3(-12.5,12.7,-17))],{"reach":0.6,"sprint":false})
	# The balcony starts closed until the chamber latch is opened.
	t.check(not result.ok,"new balcony doorway remains barred until latch opens")
	var balcony: Node3D = sites.castle_keep.get_node("BedroomBalconyDoor")
	balcony.rotation.y = PI
	result = await driver.walk([sites.castle_to_world(Vector3(-12.5,12.7,-17))],{"reach":0.6,"sprint":false})
	t.check(result.ok and sites.castle_from_world(p.global_position).y>12,"new west balcony has traversable opening and supporting floor",result.reason)
	t.check(t.main.story.commander().player_anim.has_animation("kneel_fix"),"existing kneel animation available")
	driver.release()
