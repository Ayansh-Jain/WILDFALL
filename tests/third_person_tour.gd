extends Node
## Visual check of the third-person follow camera in the real game. Runs main.tscn from the
## normal spawn and drives the local player through walking, sprinting, turning, dodging,
## attacking, warding, a forest, castle interiors and backing into walls. Saves a screenshot
## per step and prints framing metrics (camera distance, height above ground, how much of
## the screen height the body fills, whether the body is visible).
##   godot --path . res://tests/third_person_tour.tscn -- --out=C:/some/dir [--only=name]

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var out_dir := "user://third_person_tour"
var only := ""
var main: Node
var world: World
var player: PlayerController


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	add_child(main)
	await main.ready_for_play
	world = main.world
	player = main.player
	print("\n%-16s %6s %6s %6s %6s %6s %5s %s" % ["shot", "pitch", "dist", "camY", "body%", "headY%", "self", "note"])

	# 1. Normal start: where main.gd spawned the player, untouched.
	await _settle(30)
	await _shot("spawn_idle", "start position, no input")
	var start := player.global_position
	var start_yaw := player.rotation.y

	await _drive(Vector2(0, 1), false, 70)
	await _shot("walk", "walking forward")
	await _drive(Vector2(0, 1), true, 80)
	await _shot("sprint", "sprinting")
	# Turning with the mouse while running: the camera swings with the body, no spin.
	for i in 40:
		player.look(Vector2(9, 0))
		player.input_override = {"move": Vector2(0, 1), "sprint": true}
		await get_tree().physics_frame
	await _shot("turn_run", "turned ~%d deg right while sprinting" % roundi(rad_to_deg(40 * 9 * deg_to_rad(Settings.mouse_sensitivity))))
	await _drive(Vector2(-1, 0), false, 40)
	await _shot("strafe_left", "strafing left")

	player.teleport(start, start_yaw)
	await _settle(30)
	await _drive(Vector2(1, 0), false, 6)
	Combat.request_action(player.player_id, "ability_1")
	await _frames(8)
	await _shot("dodge", "mid dodge (to the right)")
	await _settle(50)
	Combat.request_action(player.player_id, "attack")
	await _frames(12)
	await _shot("attack", "mid sword strike")
	await _settle(50)
	Combat.request_action(player.player_id, "ability_2")
	await _frames(12)
	await _shot("ward", "ward raised")
	await _settle(40)
	player.set_look(player.rotation.y, deg_to_rad(35))
	await _settle(20)
	await _shot("look_up", "pitch +35 (camera below pivot, above terrain)")
	player.set_look(player.rotation.y, deg_to_rad(-45))
	await _settle(20)
	await _shot("look_down", "pitch -45")

	# Trees: walk through the deep forest.
	await _place(Vector3(-200, 0, 60), 40.0, "")
	await _drive(Vector2(0, 1), false, 90)
	await _shot("forest_walk", "walking among trees")

	# Castle interiors: the hall and the kitchen (narrow), then backs to walls.
	await _place(Vector3(220, 0.05, 155), 0.0, "Lakeside Castle")
	await _shot("castle_hall", "inside the hall")
	await _place(Vector3(210, 0.05, 155), 40.0, "Lakeside Castle")
	await _shot("castle_kitchen", "narrow kitchen")
	var hide := player.third_person_hide_distance
	player.third_person_hide_distance = 0.0
	await _frames(3)
	await _shot("castle_kitchen_dbg", "kitchen with body hiding off")
	player.third_person_hide_distance = hide
	print("  kitchen player at ", player.global_position, " site ", world.site_height("Lakeside Castle"))
	await _place(Vector3(231.5, 6.7, 153.4), 10.0, "Lakeside Castle")
	await _shot("castle_stairs", "stair hall")
	await _back_to_wall("wall_backed", Vector3(220, 0.05, 150), "Lakeside Castle", 90.0)
	await _place(Vector3(184, 0.2, 159), -75.0, "Lakeside Castle")
	await _drive(Vector2(0, 1), false, 60)
	await _shot("courtyard", "castle courtyard")
	# Village street between houses.
	await _place(Vector3(238, 0.1, 46), -105.0, "Ashford")
	await _drive(Vector2(0, 1), false, 60)
	await _shot("village", "walking in Ashford")

	# There is no first-person mode: asking for it leaves the follow camera in place.
	player.set_third_person(false)
	await _settle(40)
	await _shot("fp_refused", "first person requested: still third person")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle(n: int) -> void:
	player.input_override = {"move": Vector2.ZERO}
	await _frames(n)


func _drive(move: Vector2, sprint: bool, n: int) -> void:
	for i in n:
		player.input_override = {"move": move, "sprint": sprint}
		await get_tree().physics_frame


func _place(p: Vector3, yaw_deg: float, site: String) -> void:
	var pos := p
	pos.y += world.site_height(site) if site != "" else world.terrain_height(p.x, p.z)
	player.teleport(pos + Vector3.UP * 0.1, deg_to_rad(yaw_deg))
	await _settle(45)


## Walks backwards until blocked, so the wall is right behind the camera.
func _back_to_wall(shot_name: String, p: Vector3, site: String, yaw_deg: float) -> void:
	await _place(p, yaw_deg, site)
	var last := player.global_position
	for i in 240:
		player.input_override = {"move": Vector2(0, -1)}
		await get_tree().physics_frame
		if i % 20 == 19:
			if player.global_position.distance_to(last) < 0.05:
				break
			last = player.global_position
	await _settle(25)
	await _shot(shot_name, "backed against a wall")
	# Step away: the camera should ease back out.
	await _drive(Vector2(0, 1), false, 70)
	await _settle(30)
	await _shot(shot_name + "_out", "stepped away from the wall")


func _shot(shot_name: String, note: String) -> void:
	if only != "" and not Array(only.split(",")).any(func(o: String) -> bool: return shot_name.contains(o)):
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	var cam := player.camera
	var vh := float(get_viewport().get_visible_rect().size.y)
	var feet := player.global_position
	var top := feet + Vector3.UP * player.current_height()
	var body := -1.0
	var head_y := -1.0
	if not cam.is_position_behind(feet) and not cam.is_position_behind(top):
		var a := cam.unproject_position(feet)
		var b := cam.unproject_position(top)
		body = absf(a.y - b.y) / vh * 100.0
		head_y = b.y / vh * 100.0
	var pivot := feet + Vector3.UP * (player.head.position.y - player.third_person_pivot_drop)
	var ground := world.terrain_height(cam.global_position.x, cam.global_position.z)
	var shows_self := (cam.cull_mask & CharacterRig.SELF_LAYER) != 0
	print("%-16s %6.1f %6.2f %6.2f %6.1f %6.1f %5s %s" % [shot_name, rad_to_deg(player.head.rotation.x), cam.global_position.distance_to(pivot),
		cam.global_position.y - ground, body, head_y, "yes" if shows_self else "no", note])
