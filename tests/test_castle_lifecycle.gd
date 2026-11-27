extends Node
func run(t) -> void:
	var main: Node = t.main
	var sites := t.world.get_node("Sites/Structures") as Sites
	main.start_castle_opening()
	var opening: Node = main.castle_opening
	var player: PlayerController = main.player
	var door := sites.bedroom_door.get_node("OpenBedroomDoor") as Interactable
	door.interact(player)
	await t.physics_frames(60)
	player.teleport(sites.castle_to_world(Vector3(-3, 12.75, -22)))
	await t.physics_frames(3)
	t.check(opening.revealing and not player.controls_enabled, "balcony entry starts one reveal")
	var before: Transform3D = opening.camera.global_transform
	get_tree().paused = true
	for i in 12:
		await get_tree().process_frame
	t.check(opening.camera.global_transform.is_equal_approx(before), "pausing the game also pauses the cinematic")
	get_tree().paused = false
	var skip := InputEventAction.new()
	skip.action = "interact"
	skip.pressed = true
	opening._unhandled_input(skip)
	await t.physics_frames(3)
	t.check(not opening.revealing and player.camera.current, "skip restores original camera before timed summons")
	main.start_castle_opening()
	await t.physics_frames(3)
	t.check(opening.active and not opening.reveal_done and not door.enabled, "restarting resets the opening without another director")
	t.check(not sites.bedroom_door.get_meta("opened") and absf(sites.castle_keep.get_node("BedroomBalconyDoor").rotation.y - PI * 0.5) < 0.01, "restart locks bedroom and keeps balcony accessible")
	var campaign: CampaignDirector = main.campaign
	var original_path := campaign.save_path
	var original_persist := campaign.persist
	campaign.save_path = "user://castle_opening_lifecycle_test.json"
	campaign.persist = true
	opening._finish()
	campaign.opening_completed = false
	t.check(campaign._load() and campaign.opening_completed, "completed opening persists across campaign save/load")
	var legacy: Dictionary = campaign.state.to_dict()
	var f := FileAccess.open(campaign.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy))
	f.close()
	campaign.opening_completed = false
	t.check(campaign._load() and campaign.opening_completed, "legacy campaign saves resume without replaying the new opening")
	DirAccess.remove_absolute(campaign.save_path)
	campaign.save_path = original_path
	campaign.persist = original_persist
