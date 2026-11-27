extends Node
## Visual check of Princess Reve in the real game: runs main.tscn, starts the
## night-before-war sequence and captures her on the keep roof under the game's
## own night lighting (portraits from an orbit camera, the player's view during
## the conversation, beside the commander for scale, walking), plus frame timing.
##   godot --path . res://tests/reve_tour.tscn -- --out=C:/some/dir [--only=name]

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

## name, place ("meadow" = open ground for a clear look at the model, "roof" = her
## place on the keep roof), azimuth (deg, 0 = in front of her), distance, height, extra
const SHOTS := [
	["front", "meadow", 0.0, 3.0, 0.95, ""],
	["three_quarter", "meadow", 35.0, 3.0, 0.95, ""],
	["side", "meadow", 90.0, 3.0, 0.95, ""],
	["back", "meadow", 180.0, 3.0, 1.05, ""],
	["face", "meadow", 8.0, 0.72, 1.47, ""],
	["face_left", "meadow", 45.0, 0.72, 1.47, ""],
	["face_smile", "meadow", 15.0, 0.72, 1.47, "soft_smile"],
	["face_concern", "meadow", 15.0, 0.72, 1.47, "concern"],
	["belt", "meadow", 15.0, 0.9, 1.0, ""],
	["walk_side", "meadow", 90.0, 3.4, 0.95, "walk"],
	["with_commander", "meadow", 0.0, 3.6, 1.0, "commander"],
	["roof_gaze", "roof", 200.0, 2.4, 1.45, "gaze"],
	["roof_wide", "roof", 160.0, 5.0, 1.2, "gaze"],
	["dialogue_pov", "roof", 0.0, 0.0, 0.0, "dialogue"],
]
const MEADOW := Vector2(150, -62)

var out_dir := "user://reve_tour"
var only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main := MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	add_child(main)
	await main.ready_for_play
	var player: PlayerController = main.player
	var story: StoryDirector = main.story
	story.speed = 0.01
	story.triggers["BattleMaps"].interact(player)
	while not story.npcs.has("Reve"):
		await get_tree().process_frame
	var roof_reve: StoryNPC = story.npcs["Reve"]
	var roof_home := roof_reve.global_position
	var roof_yaw := roof_reve.rotation.y
	var moon_mark := (roof_reve.rig as ReveRig).look_target
	var world: World = main.world
	var meadow := Vector3(MEADOW.x, world.terrain_height(MEADOW.x, MEADOW.y), MEADOW.y)
	var meadow_reve := StoryNPC.new()
	world.add_child(meadow_reve)
	meadow_reve.setup("reve", "", 1.63)
	meadow_reve.global_position = meadow
	meadow_reve.rotation.y = PI * 0.75   # facing the moon-lit side
	meadow_reve.talk.enabled = false
	var cam := Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	print("\n%-16s %8s" % ["shot", "avg ms"])
	for s in SHOTS:
		if only != "" and not Array(only.split(",")).any(func(o: String) -> bool: return String(s[0]).contains(o)):
			continue
		var extra: String = s[5]
		var on_roof: bool = s[1] == "roof"
		var reve: StoryNPC = roof_reve if on_roof else meadow_reve
		var rig := reve.rig as ReveRig
		var home := roof_home if on_roof else meadow
		var home_yaw := roof_yaw if on_roof else PI * 0.75
		reve.global_position = home
		reve.rotation.y = home_yaw
		# Park the player out of frame unless a shot needs him.
		var park := home + reve.global_transform.basis.z * 6.0 + Vector3.UP * 0.1
		rig.mood = "gaze" if extra == "gaze" else ""
		rig.look_target = moon_mark if extra == "gaze" else null
		rig.expression = extra if extra in ReveRig.EXPRESSIONS else ""
		player.teleport(park, home_yaw)
		player.set_third_person(false)
		if extra == "commander":
			# Side by side, both facing the camera, for scale.
			player.teleport(home + reve.global_transform.basis.x * 0.9 + Vector3.UP * 0.1, home_yaw)
			player.set_third_person(true)
		for i in 60:
			await get_tree().physics_frame
		if extra == "walk":
			var tw := reve.create_tween()
			tw.tween_property(reve, "global_position", home + reve.global_transform.basis.z * 1.8, 2.6)
			for i in 70:
				await get_tree().physics_frame
		if extra == "dialogue":
			player.teleport(home + reve.global_transform.basis.z * 2.2 + Vector3.UP * 0.1, home_yaw)
			story.speed = 1.0
			reve.talk.enabled = true
			story.flags.erase("rooftop_talk_done")
			reve.talk.interact(player)
			# Past the first exchange: she has turned to face him and is speaking.
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 9500:
				await get_tree().process_frame
			cam.current = false
			player.camera.current = true
		else:
			cam.current = true
			var yaw := reve.rotation.y + deg_to_rad(float(s[2]))
			var target := reve.global_position + Vector3.UP * float(s[4])
			var dir := -Vector3(sin(yaw), 0, cos(yaw))
			cam.global_position = target + dir * float(s[3]) + Vector3.UP * (0.03 if float(s[3]) < 1.5 else 0.2)
			cam.look_at(target)
		var samples: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in 30:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - last) / 1000.0)
			last = now
		var avg := 0.0
		for x in samples:
			avg += x
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join(String(s[0]) + ".png"))
		print("%-16s %8.2f" % [s[0], avg / samples.size()])
		if extra == "dialogue":
			story.speed = 0.01
			while story.in_dialogue:
				await get_tree().process_frame
	get_tree().quit()
