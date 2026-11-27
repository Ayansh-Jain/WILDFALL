extends Node
func run(t) -> void:
	if DisplayServer.get_name()=="headless":
		return
	var p: PlayerController=t.main.player
	var story: StoryDirector=t.main.story
	var c: CampaignDirector=t.main.campaign
	var sites: Sites=t.world.get_node("Sites/Structures")
	var driver:=PlayerDriver.new(p)
	p.teleport(story.anchor_pos("king_audience")+Vector3(0,0,0.6),0)
	c.speed=1
	story.speed=1
	var camera:=Camera3D.new()
	add_child(camera)
	camera.global_position=sites.castle_to_world(Vector3(12,3.5,-16))
	camera.look_at(c.king.global_position+Vector3.UP)
	camera.make_current()
	c._royal_dialogue([["King","Commander, I entrust you with my four best commandos. Lead them well."]])
	await driver.frames(140)
	await RenderingServer.frame_post_draw
	t.get_viewport().get_texture().get_image().save_png("D:/WildFall/Screenshots/upgrade_royal_audience.png")
	while story.in_dialogue or not p.controls_enabled:
		await driver.frames(1)
	t.check((c.king.rig as KingRig).seated,"rendered audience keeps king seated")
	camera.queue_free()
	p.camera.make_current()
	driver.release()
