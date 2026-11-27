extends Node
## R01 visual check: the follow camera in the castle, a village, open country and on
## horseback, with mode and frame time per shot.
##   godot --path . res://tests/r01_tour.tscn -- --out=<dir>

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var out_dir := "user://r01_tour"
var main: Node
var world: World
var player: PlayerController


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	main.enable_opening = false
	main.campaign_persist = false
	add_child(main)
	await main.ready_for_play
	world = main.world
	player = main.player
	var sites := world.get_node("Sites/Structures") as Sites
	await _run_walk("spawn", Vector2(0, 1), false, 60)
	await _run_walk("sprint", Vector2(0, 1), true, 80)
	for anchor in ["hall_reveal", "king_audience", "commander_spawn", "commander_desk", "castle_courtyard"]:
		var a: Variant = sites.story_anchors.get(anchor)
		if a == null:
			continue
		var at: Vector3 = a["pos"] if a is Dictionary else a
		player.teleport(at + Vector3.UP * 0.1, float(a.get("yaw", 0.0)) if a is Dictionary else 0.0)
		await _run_walk("castle_" + anchor, Vector2.ZERO, false, 60)
	# Gate Field: open ground for the horse.
	var p := Vector3(-232, world.terrain_height(-232, 108) + 0.2, 108)
	player.teleport(p, 0.0)
	await _frames(40)
	main.spawn_horse_near(player)
	await _frames(20)
	await _run_walk("field_horse", Vector2.ZERO, false, 30)
	var rider := player.get_node("Rider") as Rider
	rider.mount(main.horse)
	await _frames(150)
	await _run_walk("mounted_idle", Vector2.ZERO, false, 30)
	await _run_walk("mounted_trot", Vector2(0, 1), false, 150)
	await _run_walk("mounted_gallop", Vector2(0, 1), true, 200)
	await _run_walk("mounted_stop", Vector2.ZERO, false, 200)
	rider.dismount()
	await _frames(150)
	await _run_walk("dismounted", Vector2.ZERO, false, 30)
	(player.get_node("AvatarVisual") as AvatarVisual).human_rig.toggle_swords()
	await _frames(80)
	player.combatant.last_combat_time = Combat.now()
	await _run_walk("swords_combat_frame", Vector2.ZERO, false, 50)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run_walk(shot: String, move: Vector2, sprint: bool, n: int) -> void:
	for i in n:
		player.input_override = {"move": move, "sprint": sprint}
		await get_tree().physics_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot + ".png"))
	print("[r01] %-26s mode=%-8s dist=%.2f fov=%.1f fps=%d pos=%s" % [shot, player.cam.mode_name(),
		player.camera.global_position.distance_to(player.head.global_position), player.camera.fov, Engine.get_frames_per_second(), str(player.global_position.snapped(Vector3.ONE * 0.1))])
