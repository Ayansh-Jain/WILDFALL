extends Node
## Visual check of the commander in the real game world. Runs main.tscn, places the
## local player and captures portraits (a separate orbit camera) and gameplay shots
## (the player's own third-person camera), plus frame timing.
##   godot --path . res://tests/commander_tour.tscn -- --out=C:/some/dir [--only=name]

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const SPOT := Vector3(150, 0, -62)   ## North Meadow (open ground)

## name, mode, azimuth (deg, 0 = in front of him), distance, height, extra
const SHOTS := [
	["front", "portrait", 0.0, 3.4, 1.0, ""],
	["three_quarter", "portrait", 35.0, 3.4, 1.0, ""],
	["left", "portrait", 90.0, 3.4, 1.0, ""],
	["right", "portrait", -90.0, 3.4, 1.0, ""],
	["back", "portrait", 180.0, 3.4, 1.1, ""],
	["face", "portrait", 10.0, 0.75, 1.72, ""],
	["face_left", "portrait", 50.0, 0.7, 1.72, ""],
	["face_determined", "portrait", 20.0, 0.75, 1.72, "determined"],
	["sword_drawn", "portrait", 30.0, 3.2, 1.0, "draw"],
	["dual_swords", "portrait", 30.0, 3.2, 1.0, "dual"],
	["tp_idle", "gameplay", 0.0, 0.0, 0.0, ""],
	["tp_dual", "gameplay", 0.0, 0.0, 0.0, "dual"],
		["tp_dual_sprint", "gameplay", 0.0, 0.0, 0.0, "dual_sprint"],
		["dual_sprint_side", "portrait", 90.0, 3.4, 1.0, "dual_sprint"],
		["tp_sit", "gameplay", 0.0, 0.0, 0.0, "sit"],
	["tp_walk", "gameplay", 0.0, 0.0, 0.0, "walk"],
	["tp_sprint", "gameplay", 0.0, 0.0, 0.0, "sprint"],
	["tp_attack", "gameplay", 0.0, 0.0, 0.0, "attack"],
	["walk_side", "portrait", 90.0, 4.0, 1.0, "walk"],
]

var out_dir := "user://commander_tour"
var only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
		elif arg == "--v3-body":
			CommanderRig.use_replacement_body = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main := MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	add_child(main)
	await main.ready_for_play
	var world: World = main.world
	var player: PlayerController = main.player
	var visual: AvatarVisual = player.get_node("AvatarVisual")
	var rig := visual.human_rig as CommanderRig
	if rig == null:
		push_error("local player has no CommanderRig")
		get_tree().quit(1)
		return
	var ground := Vector3(SPOT.x, world.terrain_height(SPOT.x, SPOT.z), SPOT.z)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	print("\n%-18s %8s" % ["shot", "avg ms"])
	for s in SHOTS:
		if only != "" and not Array(only.split(",")).any(func(o: String) -> bool: return String(s[0]).contains(o)):
			continue
		var mode: String = s[1]
		var extra: String = s[5]
		player.set_noclip(false)
		player.teleport(ground + Vector3.UP * 0.1, 0.0)
		if rig.sword_drawn:
			rig.dual_wield = false
			rig.sheath_sword()
		player.input_override = {"move": Vector2.ZERO}
		rig.expression = extra if extra in CommanderRig.EXPRESSIONS else ""
		for i in 40:
			await get_tree().physics_frame
		if extra == "draw":
			rig.draw_sword()  # queues behind any landing from the teleport
			for i in 170:
				await get_tree().physics_frame
		elif extra == "dual" or extra == "dual_sprint":
			rig.toggle_dual_wield()
			for i in 170:
				await get_tree().physics_frame
		if extra == "walk" or extra == "sprint" or extra == "dual_sprint":
			player.input_override = {"move": Vector2(0, 1), "sprint": extra == "sprint"}
			if extra == "dual_sprint":
				player.input_override["sprint"] = true
			for i in 75:
				await get_tree().physics_frame
		if extra == "sit":
			var seated := false
			for radius in range(0, 3):
				for dz in range(-2, 3):
					for dx in range(-2, 3):
						if maxi(abs(dx), abs(dz)) != radius:
							continue
						var p := Vector2(SPOT.x, SPOT.z) + Vector2(dx, dz) * 2.0
						if not world.terrain_data.in_playable(p.x, p.y, -1.0):
							continue
						if world.terrain_data.normal_at(p.x, p.y).y < 0.97 or world.terrain_height(p.x, p.y) < world.water_level + 1.0:
							continue
						player.teleport(Vector3(p.x, world.terrain_height(p.x, p.y) + 0.1, p.y))
						for i in 8:
							await get_tree().physics_frame
						if player.can_sit_anywhere():
							seated = player.sit_at()
							break
					if seated:
						break
				if seated:
					break
			print("[tour] seated on unmarked ground=", seated)
			if seated:
				for i in 110:
					await get_tree().physics_frame
		if mode == "portrait":
			player.set_third_person(true)
			cam.current = true
			var yaw := player.rotation.y + deg_to_rad(float(s[2]))
			var target := player.global_position + Vector3.UP * float(s[4])
			# The body faces -Z (its forward); azimuth 0 puts the camera in front of him.
			var dir := Vector3(sin(yaw), 0, cos(yaw)) * -1.0
			# Keep the external portrait camera current after switching the player view.
			cam.global_position = target + dir * float(s[3]) + Vector3.UP * (0.05 if float(s[3]) < 1.5 else 0.25)
			cam.look_at(target)
		else:
			cam.current = false
			player.camera.current = true
			player.set_third_person(true)
			player.set_look(0.0, deg_to_rad(-8.0))
			for i in 40:
				await get_tree().process_frame
		if extra == "attack":
			Combat.request_action(player.player_id, "attack")
			for i in 14:
				await get_tree().physics_frame
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
		print("%-18s %8.2f" % [s[0], avg / samples.size()])
		player.set_third_person(false)
	get_tree().quit()
