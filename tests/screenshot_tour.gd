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
	["hands_castle", Vector3(186, 1.62, 100), 158.0, -1.0, "ground"],
	["hands_forest", Vector3(168, 1.62, 100), 150.0, -2.0, "ground"],
	["hands_trail", Vector3(-88, 1.62, -28), -110.0, -3.0, "ground"],
	["hands_attack", Vector3(186, 1.62, 100), 158.0, -1.0, "ground_attack"],
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
		["northmere_approach", Vector3(112, 1.62, -82), -135.0, 0.0, "ground"],
		["southbank_approach", Vector3(82, 1.62, 270), 0.0, 0.0, "ground"],
		["westmarch_approach", Vector3(-268, 1.62, -32), -90.0, 0.0, "ground"],
		["southwatch_approach", Vector3(-126, 1.62, 230), 32.0, 0.0, "ground"],
		["western_king_road", Vector3(-60, 1.62, -38), -45.0, 0.0, "ground"],
		["stone_bridge_to_southbank", Vector3(86, 1.62, 203), 165.0, 0.0, "ground"],
		["reed_ford_crossing", Vector3(44, 1.62, 230), 90.0, 0.0, "ground"],
		["birds_sky", Vector3(70, 1.62, 270), 0.0, 8.0, "birds"],
	# Phase 1 kingdom layout: wall, gate, town, cemetery, training ground, mission spaces.
	["kingdom_overview", Vector3(0, 430, 470), 0.0, -48.0, "abs"],
	["kingdom_town_aerial", Vector3(120, 95, 300), -35.0, -30.0, "abs"],
	["kingdom_gatefield_aerial", Vector3(-160, 75, 150), 55.0, -32.0, "abs"],
	["kingdom_great_gate", Vector3(-258, 1.62, 70), 90.0, 7.0, "ground"],
	["kingdom_gate_close", Vector3(-276, 1.62, 70), 90.0, 14.0, "ground"],
	["kingdom_gatefield_ring", Vector3(-268, 1.62, 82), -80.0, 2.0, "ground"],
	["kingdom_castle_square", Vector3(232, 1.62, 82), 180.0, 4.0, "ground"],
	["kingdom_square_north", Vector3(234, 1.62, 106), 15.0, 2.0, "ground"],
	["kingdom_wall_lane", Vector3(267, 1.62, 122), 180.0, 2.0, "ground"],
	["kingdom_south_street", Vector3(160, 1.62, 192), -62.0, 2.0, "ground"],
	["kingdom_coopers_lane", Vector3(214, 1.62, 214), 180.0, 2.0, "ground"],
	["kingdom_cross_street", Vector3(140, 1.62, 240), -95.0, 2.0, "ground"],
	["kingdom_castle_road", Vector3(92, 1.62, 183), -100.0, 3.0, "ground"],
	["kingdom_south_wall", Vector3(-5, 1.62, 262), 180.0, 6.0, "ground"],
	["kingdom_east_wall_junction", Vector3(255, 1.62, -150), -20.0, 8.0, "ground"],
	["kingdom_west_wall_junction", Vector3(-262, 1.62, -170), 20.0, 8.0, "ground"],
	["kingdom_cemetery_gate", Vector3(0, 1.62, 44), 0.0, 6.0, "ground"],
	["kingdom_memorial_stone", Vector3(1.2, 1.62, 24.2), -90.0, -6.0, "ground"],
	["kingdom_cemetery_graves", Vector3(-6, 1.62, -19), 150.0, -4.0, "ground"],
	["kingdom_cemetery_aerial", Vector3(0, 40, 52), 0.0, -40.0, ""],
	["kingdom_training_ground", Vector3(-118, 1.62, -60), 90.0, 2.0, "ground"],
	["kingdom_training_yard", Vector3(-160, 1.62, -72), 0.0, -2.0, "ground"],
	["kingdom_cave_outskirts", Vector3(-28, 1.62, -124), 0.0, 3.0, "ground"],
	# Lakeside Castle interiors: y is relative to the castle's site height.
	["castle_yard", Vector3(184, 1.8, 159), -75.0, 6.0, "site:Lakeside Castle"],
	["castle_hall", Vector3(220, 2.17, 155), 0.0, 4.0, "site:Lakeside Castle"],
	["castle_hall_rev", Vector3(220, 2.17, 131), 180.0, 2.0, "site:Lakeside Castle"],
	["castle_hearth", Vector3(216, 2.17, 141), 40.0, -4.0, "site:Lakeside Castle"],
	["castle_kitchen", Vector3(210, 2.17, 155), 40.0, -6.0, "site:Lakeside Castle"],
	["castle_armory", Vector3(231, 2.17, 141), -20.0, -6.0, "site:Lakeside Castle"],
	["castle_stairs", Vector3(231.5, 8.3, 153.4), 10.0, 22.0, "site:Lakeside Castle"],
	["castle_upper", Vector3(225, 14.32, 153), 30.0, 2.0, "site:Lakeside Castle"],
	["castle_barracks", Vector3(208.5, 14.32, 155.2), 30.0, -10.0, "site:Lakeside Castle"],
	["castle_quarters", Vector3(209, 14.32, 141.8), 40.0, -8.0, "site:Lakeside Castle"],
	["castle_quarters_bed", Vector3(205, 14.32, 133), -135.0, -12.0, "site:Lakeside Castle"],
	["castle_maproom", Vector3(232, 14.32, 141), -30.0, -8.0, "site:Lakeside Castle"],
	["castle_balcony", Vector3(209.2, 14.32, 123.6), 20.0, -4.0, "site:Lakeside Castle"],
	["castle_balcony_out", Vector3(209.2, 15.5, 112), 180.0, -2.0, "site:Lakeside Castle"],
	["castle_crypt", Vector3(188, -10.03, 145), 0.0, -4.0, "site:Lakeside Castle"],
	["castle_reliquary", Vector3(218, -10.03, 165), -90.0, -6.0, "site:Lakeside Castle"],
	["castle_stairs_upper", Vector3(233.3, 19.1, 152.4), 0.0, 20.0, "site:Lakeside Castle"],
	["castle_roof_reve", Vector3(209.0, 23.87, 132.5), 28.0, -2.0, "story_roof"],
	["castle_roof_view", Vector3(212.5, 23.87, 132.0), 52.0, 4.0, "story_roof"],
	# Ashford village (y relative to the village site) and riverbanks.
	["village_entry", Vector3(218, 1.7, 49), -98.0, 2.0, "site:Ashford"],
	["village_square", Vector3(238, 1.7, 46), -105.0, 0.0, "site:Ashford"],
	["village_tavern", Vector3(238, 1.7, 44), 18.0, 4.0, "site:Ashford"],
	["village_smithy", Vector3(242, 1.7, 47), 132.0, 0.0, "site:Ashford"],
	["village_elder", Vector3(248, 1.7, 43.6), -94.0, -6.0, "site:Ashford"],
	["village_aerial", Vector3(266, 26, 82), 27.0, -30.0, "site:Ashford"],
	["riverbank_lake", Vector3(209, 1.62, 63), 35.0, -8.0, ""],
	["riverbank_south", Vector3(79, 1.62, 156), 127.0, -6.0, ""],
	["scroll_closeup", Vector3.ZERO, 0.0, -20.0, "scroll"],
	["scroll_prompt", Vector3.ZERO, 0.0, 0.0, "prompt"],
	["pause_menu", Vector3(0, 1.62, 62), 0.0, 8.0, "menu"],
	["explorer_model", Vector3(150, 1.62, -58), 0.0, -4.0, "explorer"],
	["beast_model", Vector3(150, 1.62, -55), 0.0, 4.0, "beast"],
	["beast_roar", Vector3(150, 1.62, -55), 0.0, 4.0, "beast_roar"],
	["fp_beast_hud", Vector3(150, 1.62, -55), 0.0, 0.0, "fp_beast"],
]

var out_dir := "user://screenshots"
var only := ""
var frames := 90



var _eye_cam: Camera3D
var _eye_player: PlayerController


func _process(_delta: float) -> void:
	if _eye_cam and is_instance_valid(_eye_player):
		_eye_cam.global_transform = _eye_player.head.global_transform

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
	_audit_generated_empire(world)
	if OS.get_cmdline_user_args().has("--bird-demo"):
		var bird_ambience := world.get_node_or_null("BirdAmbience")
		if bird_ambience:
			bird_ambience._wait = 0.1
	# Profiling switches: --no-shadows, --hide=<prefix>[,<prefix>] hides vegetation multimeshes by name.
	# --hour=N fixes the time of day (e.g. 22 for night).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			var cycle := world.get_node_or_null("DayNightCycle")
			if cycle:
				cycle.set_time_override(float(arg.substr(7)), 0.0)
		if arg == "--no-shadows":
			world.moon.shadow_enabled = false
		elif arg.begins_with("--shadow-dist="):
			world.moon.directional_shadow_max_distance = float(arg.substr(14))
		elif arg.begins_with("--lod="):
			var lod := float(arg.substr(6))
			for n in world.get_node("Props/Vegetation").get_children():
				var nm := String(n.name)
				if nm.ends_with("_far"):
					n.visibility_range_begin = lod - 6.0
				elif n is GeometryInstance3D and (nm.begins_with("pine") or nm.begins_with("fir") or nm.begins_with("oak") or nm.begins_with("birch")):
					n.visibility_range_end = lod
		elif arg.begins_with("--hide="):
			for prefix in arg.substr(7).split(","):
				for n in world.get_node("Props/Vegetation").get_children():
					if String(n.name).begins_with(prefix):
						n.visible = false
	var player: PlayerController = main.player
	player.controls_enabled = false
	# This tour frames exact world points from the player's eye position. The game has
	# no first-person mode any more, so a tour-only camera rides the player's head.
	_eye_cam = Camera3D.new()
	_eye_cam.fov = player.camera.fov
	_eye_cam.far = player.camera.far
	_eye_cam.near = player.camera.near
	add_child(_eye_cam)
	_eye_cam.current = true
	_eye_player = player
	main.hud.visible = false
	main.combat_hud.visible = false
	var view_model := player.get_node("Head/Camera3D/ViewModel")
	view_model.set_process(false)
	view_model.visible = false
	if not OS.get_cmdline_user_args().has("--clean"):
		main.hud.toggle_debug()

	print("\n%-20s %8s %8s %8s %6s" % ["view", "avg ms", "p95 ms", "fps", "draws"])
	var all_ms: Array[float] = []
	for v in VIEWS:
		if only != "" and not Array(only.split(",")).any(func(o: String) -> bool: return String(v[0]).contains(o)):
			continue
		var pos: Vector3 = v[1]
		var mode: String = v[4]
		if mode == "story_roof":
			if not main.story.has_flag("night_before_war"):
				main.story.speed = 0.02
				main.story._on_battle_maps(player)
				for i in 30:
					await get_tree().process_frame
			pos.y += world.site_height("Lakeside Castle")
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
		elif mode != "abs" and mode != "story_roof":
			pos.y += world.terrain_height(pos.x, pos.z)
		if mode == "ground_attack":
			pos.y += world.terrain_height(pos.x, pos.z)
		if mode == "ground" or mode == "ground_attack":
			player.set_noclip(false)
			player.teleport(pos - Vector3.UP * player.stand_eye, deg_to_rad(v[2]))
			player.set_look(deg_to_rad(v[2]), deg_to_rad(v[3]))
			for i in 30:
				await get_tree().physics_frame
		if mode != "ground" and mode != "ground_attack":
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
		if mode == "birds" and OS.get_cmdline_user_args().has("--bird-demo"):
			var bird_ambience := world.get_node_or_null("BirdAmbience")
			if bird_ambience:
				bird_ambience._wait = 0.0
				bird_ambience._try_spawn_flock()
				bird_ambience._progress = 0.46
				bird_ambience._advance_flock(0.0)
				var bird_camera := get_viewport().get_camera_3d()
				var bird_point: Vector3 = bird_ambience._flock.global_transform * bird_ambience._multimesh.get_instance_transform(0).origin
				print("[BirdAudit] spawned=%s count=%d camera=%s forward=%s bird=%s screen=%s behind=%s" % [bird_ambience._flying, bird_ambience._bird_data.size(), str(bird_camera.global_position), str(-bird_camera.global_basis.z), str(bird_point), str(bird_camera.unproject_position(bird_point)), bird_camera.is_position_behind(bird_point)])
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
		if mode == "ground_attack":
			for i in 60:
				await get_tree().process_frame
			Combat.request_action(player.player_id, "attack")
			for i in 12:
				await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out_dir.path_join(String(v[0]) + ".png"))
			print("%-20s (pose capture)" % v[0])
			continue
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
		if mode == "birds":
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out_dir.path_join(String(v[0]) + "_flap.png"))
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


func _audit_generated_empire(world: World) -> void:
	var registry := world.get_node("Sites/Structures") as Sites
	for site_name in ["Ashford", "Westmarch Hamlet", "Southwatch Hamlet", "Northmere", "Southbank"]:
		var site: Node3D = registry.built.get(site_name)
		var houses := 0
		var house_names: PackedStringArray = []
		if site:
			for mesh: Node in site.find_children("*", "MeshInstance3D", true, false):
				var mesh_name := String(mesh.name)
				var house_mesh: bool = mesh_name.ends_with("Mesh") and (site_name == "Ashford" or mesh_name.begins_with(site_name) or mesh_name.begins_with("Hamlet"))
				if house_mesh:
					houses += 1
					house_names.append(mesh_name)
		print("[EmpireAudit] %s houses=%d %s" % [site_name, houses, str(house_names)])
	for road in world.layout.list("roads"):
		var points := WorldLayout.points(road["points"])
		var max_slope := 0.0
		var steepest := Vector2.ZERO
		var steepest_from := Vector2.ZERO
		var steepest_from_y := 0.0
		var steepest_y := 0.0
		for segment in points.size() - 1:
			var a := points[segment]
			var b := points[segment + 1]
			var length := a.distance_to(b)
			var steps := maxi(1, int(ceil(length / 3.0)))
			var previous := a
			var previous_y := _road_surface_height(world, previous)
			for sample in range(1, steps + 1):
				var p := a.lerp(b, float(sample) / steps)
				var ground := _road_surface_height(world, p)
				var run := previous.distance_to(p)
				if run > 0.01:
					var slope := rad_to_deg(atan(absf(ground - previous_y) / run))
					if slope > max_slope:
						max_slope = slope
						steepest = p
						steepest_from = previous
						steepest_from_y = previous_y
						steepest_y = ground
				previous = p
				previous_y = ground
		print("[EmpireAudit] road '%s' max_slope=%.1f deg from (%.1f, %.1f, %.1f) to (%.1f, %.1f, %.1f) width=%.1f m" % [road["name"], max_slope, steepest_from.x, steepest_from.y, steepest_from_y, steepest.x, steepest.y, steepest_y, float(road["half_width"]) * 2.0])


func _road_surface_height(world: World, point: Vector2) -> float:
	for bridge in world.layout.list("bridges"):
		var a := WorldLayout.v2(bridge["a"])
		var b := WorldLayout.v2(bridge["b"])
		var direction := b - a
		var length_squared := direction.length_squared()
		var along := (point - a).dot(direction) / length_squared
		if along < 0.0 or along > 1.0 or TerrainData.seg_dist(point, a, b) > float(bridge["width"]) * 0.5:
			continue
		var arc := 2.2 if String(bridge["style"]) == "stone" else 1.4
		return lerpf(world.terrain_height(a.x, a.y), world.terrain_height(b.x, b.y), along) + 0.04 + arc * sin(PI * along)
	return world.terrain_height(point.x, point.y)


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
