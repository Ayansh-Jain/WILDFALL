extends Node
## Visual + performance check. Runs the real game (windowed), visits a list of
## viewpoints, saves a screenshot at each and measures frame time.
##   godot --path . res://tests/screenshot_tour.tscn -- --out=C:/some/dir [--only=name] [--frames=120]
## Writes <out>/<name>.png and prints a timing table. VSync is disabled so the
## numbers reflect GPU/CPU cost rather than the monitor refresh rate. Pass
## --vsync to measure frame pacing as players see it (expect ~16.7 ms at 60 Hz).

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

## name, camera position (y is metres above ground unless abs=true), yaw, pitch
const VIEWS := [
	["spawn_view", Vector3(-245, 1.62, -150), 0.0, 0.0, "spawn"],
	["grove_tree", Vector3(0, 1.62, 62), 0.0, 8.0, ""],
	["grove_close", Vector3(14, 1.62, 26), 25.0, 12.0, ""],
	["citadel_gate", Vector3(-120, 1.62, -56), 85.0, 2.0, ""],
	["citadel_courtyard", Vector3(-170, 1.62, -44), 30.0, 0.0, ""],
	["citadel_keep_top", Vector3(-160, 4.9, -60), 120.0, -5.0, ""],
	["deep_forest", Vector3(-200, 1.62, 60), 40.0, 0.0, ""],
	["forest_trail", Vector3(-88, 1.62, -28), -110.0, 0.0, ""],
	["lake_west_shore", Vector3(56, 1.62, 30), -80.0, -2.0, ""],
	["north_bridge", Vector3(70, 1.62, -150), -90.0, 0.0, ""],
	["old_ford", Vector3(70, 1.62, -214), -90.0, -6.0, ""],
	["stone_bridge", Vector3(36, 1.62, 156), -60.0, 0.0, ""],
	["cave_mouth", Vector3(-32, 1.62, -166), 0.0, 4.0, ""],
	["cave_inside", Vector3(-32, 10.62, -200), 0.0, 0.0, "abs"],
	["watchtower_view", Vector3(-200, 1.62, 214), 0.0, 6.0, ""],
	["watchtower_top", Vector3(-200, 7.8, 190), 60.0, -6.0, "site:Watchtower"],
	["crag_summit", Vector3(213, 1.62, -90), -120.0, -6.0, ""],
	["lake_castle", Vector3(180, 1.62, 154), -90.0, 4.0, ""],
	["landmark_from_watchtower", Vector3(-200, 7.8, 190), -46.5, 2.0, "site:Watchtower"],
	["landmark_from_crag", Vector3(215, 1.7, -90), 112.7, 1.0, ""],
	["aerial_overview", Vector3(-60, 140, 260), 0.0, -32.0, "abs"],
	["scroll_closeup", Vector3.ZERO, 0.0, -20.0, "scroll"],
	["scroll_prompt", Vector3.ZERO, 0.0, 0.0, "prompt"],
	["pause_menu", Vector3(0, 1.62, 62), 0.0, 8.0, "menu"],
	["explorer_model", Vector3(248, 1.62, 44), 0.0, -4.0, "explorer"],
	["beast_model", Vector3(248, 1.62, 47), 0.0, 4.0, "beast"],
	["beast_roar", Vector3(248, 1.62, 47), 0.0, 4.0, "beast_roar"],
	["fp_beast_hud", Vector3(248, 1.62, 47), 0.0, 0.0, "fp_beast"],
]

var out_dir := "user://screenshots"
var only := ""
var frames := 90


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
		elif arg.begins_with("--frames="):
			frames = int(arg.substr(9))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if not OS.get_cmdline_user_args().has("--vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var main := MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = OS.get_cmdline_user_args().has("--with-bots")
	add_child(main)
	await main.ready_for_play
	var world: World = main.world
	var player: PlayerController = main.player
	player.controls_enabled = false
	main.hud.toggle_debug()

	print("\n%-20s %8s %8s %8s %6s" % ["view", "avg ms", "p95 ms", "fps", "draws"])
	var all_ms: Array[float] = []
	for v in VIEWS:
		if only != "" and not Array(only.split(",")).any(func(o: String) -> bool: return String(v[0]).contains(o)):
			continue
		var pos: Vector3 = v[1]
		var mode: String = v[4]
		if mode == "spawn":
			pos = player.global_position + Vector3.UP * 1.62
		elif mode == "scroll":
			var sp := GameState.scroll_position
			pos = sp + Vector3(0, 2.2, 3.2)
		elif mode == "prompt":
			var sp2 := GameState.scroll_position
			var stand := SpawnValidator.find(world, Vector2(sp2.x, sp2.z + 1.9), sp2.y + 2.0, 2.0)
			pos = stand["position"] + Vector3.UP * player.stand_eye
		elif mode == "menu" or mode.begins_with("explorer") or mode.begins_with("beast") or mode == "fp_beast":
			pos.y += world.terrain_height(pos.x, pos.z)
		elif mode.begins_with("site:"):
			pos.y += world.site_height(mode.substr(5))
		elif mode != "abs":
			pos.y += world.terrain_height(pos.x, pos.z)
		player.set_noclip(true)
		player.global_position = pos - Vector3.UP * player.stand_eye
		player.head.position.y = player.stand_eye
		if mode == "spawn":
			pass
		elif mode == "prompt":
			var target := GameState.scroll_position + Vector3.UP * 0.75
			var d := target - pos
			player.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
		else:
			player.set_look(deg_to_rad(v[2]), deg_to_rad(v[3]))
		if mode == "menu":
			main.hud.toggle_debug()
			main.pause_menu.open()
		if mode in ["explorer", "beast", "beast_roar"]:
			await _stage_model(main, pos, mode)
		if mode == "fp_beast":
			main.hud.toggle_debug()
			player.set_noclip(false)
			player.teleport(pos - Vector3.UP * player.stand_eye, 0.0)
			GameState.grant_monster_for_testing(player.player_id)
			Combat.request_transform(player.player_id)
			for i in 70:
				await get_tree().physics_frame
			Combat.request_action(player.player_id, "heavy_attack")
			for i in 30:
				await get_tree().physics_frame
		# Warm up (shader compiles, streaming), then measure.
		for i in 20:
			await get_tree().process_frame
		var samples: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in frames:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - last) / 1000.0)
			last = now
		if OS.get_cmdline_user_args().has("--histogram"):
			var spikes := samples.filter(func(s: float) -> bool: return s > 12.0)
			var idxs := []
			for si in samples.size():
				if samples[si] > 12.0:
					idxs.append(si)
			print("   spikes >12ms: %d of %d at frames %s" % [spikes.size(), samples.size(), str(idxs.slice(0, 30))])
		samples.sort()
		var avg := 0.0
		for s in samples:
			avg += s
		avg /= samples.size()
		all_ms.append(avg)
		var p95 := samples[int(samples.size() * 0.95)]
		var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join(String(v[0]) + ".png"))
		print("%-20s %8.2f %8.2f %8.1f %6d" % [v[0], avg, p95, 1000.0 / avg, draws])
		if mode == "fp_beast":
			main.hud.toggle_debug()
			player.set_noclip(true)
		for b in main.bots:
			if is_instance_valid(b):
				b.queue_free()
		main.bots.clear()
		if mode == "menu":
			main.pause_menu.close()
			main.hud.toggle_debug()
	var total := 0.0
	for a in all_ms:
		total += a
	if not all_ms.is_empty():
		print("overall average %.2f ms (%.1f fps) at %s" % [total / all_ms.size(), 1000.0 / (total / all_ms.size()), str(get_viewport().get_visible_rect().size)])
	get_tree().quit()


## Places a still model 4 m in front of the camera for a portrait shot.
func _stage_model(main: Node, cam_pos: Vector3, mode: String) -> void:
	var bot: PlayerController = main.spawn_bot(cam_pos + Vector3(0, 0, -4.5), SimBot.Role.WANDERER if mode == "explorer" else SimBot.Role.HUNTER)
	bot.get_node("Brain").process_mode = Node.PROCESS_MODE_DISABLED
	bot.input_override = {}
	await get_tree().physics_frame
	bot.set_look(PI * 0.15 + PI, 0.0)
	if mode != "explorer":
		Combat.request_transform(bot.player_id)
		for i in 80:
			await get_tree().physics_frame
		if mode == "beast_roar":
			Combat.request_action(bot.player_id, "ability_2")
			for i in 30:
				await get_tree().physics_frame
