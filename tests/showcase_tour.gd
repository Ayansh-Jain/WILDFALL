extends Node
## Visual + performance verification tour for Golden Valley Showcase AND Main World.
## Runs under Compatibility renderer, captures screenshots across lighting profiles,
## and prints avg / p95 / p99 frame times.
##   godot --rendering-method gl_compatibility --path . res://tests/showcase_tour.tscn -- --out=D:/WildFall/Screenshots/R01_AG_Showcase

const SHOWCASE_SCENE := preload("res://scenes/world/showcase/golden_valley_showcase.tscn")
const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var out_dir := "D:/WildFall/Screenshots/R01_AG_Showcase"
var mode := "both"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--mode="):
			mode = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_tree().create_timer(160.0).timeout.connect(func() -> void:
		print("[showcase_tour] TIMEOUT")
		get_tree().quit(2))

	if mode in ["both", "showcase"]:
		await _run_showcase()
	if mode in ["both", "main"]:
		await _run_main_world()
	print("[showcase_tour] complete -> ", out_dir)
	get_tree().quit(0)


func _run_showcase() -> void:
	var t0 := Time.get_ticks_msec()
	var sc := SHOWCASE_SCENE.instantiate() as GoldenValleyShowcase
	if sc == null:
		print("[showcase_tour] FAIL: could not instantiate showcase")
		get_tree().quit(1)
		return
	sc.auto_capture_mouse = false
	add_child(sc)
	if not sc.is_node_ready():
		await sc.showcase_ready
	print("SHOWCASE built in %d ms" % (Time.get_ticks_msec() - t0))
	if sc._hud_layer:
		sc._hud_layer.visible = false
	for i in 12:
		await get_tree().process_frame

	var views := sc.get_scenic_views()
	# Capture Golden Day across all 5 scenic viewpoints + measure 3 repetitions steady-state.
	sc.apply_profile("golden_day", 0.0)
	for idx in views.size():
		sc.activate_scenic_camera(idx)
		await _warmup(12)
		var stats := await _measure_reps(3, 35)
		await _save_shot("gv_day_%s" % views[idx]["name"])
		print("SHOWCASE day/%s  avg=%.2fms  p95=%.2fms  p99=%.2fms  fps=%.1f  draws=%d" % [
			views[idx]["name"], stats["avg"], stats["p95"], stats["p99"], stats["fps"], stats["draws"]])

	# Capture Atmospheric Evening, Moonlit Night, and Misty Valley from key views.
	for prof in ["atmospheric_evening", "moonlit_night", "misty_valley"]:
		sc.apply_profile(prof, 0.0)
		sc.activate_scenic_camera(0)
		await _warmup(12)
		var stats0 := await _measure_reps(3, 30)
		await _save_shot("gv_%s_overlook" % prof)
		print("SHOWCASE %s/overlook  avg=%.2fms  p95=%.2fms  p99=%.2fms  fps=%.1f" % [
			prof, stats0["avg"], stats0["p95"], stats0["p99"], stats0["fps"]])
		sc.activate_scenic_camera(1)
		await _warmup(8)
		await _save_shot("gv_%s_bridge" % prof)

	# Verify wf_marker nodes exist & are grounded.
	var markers := get_tree().get_nodes_in_group("wf_marker")
	print("SHOWCASE wf_marker count=%d" % markers.size())

	sc.queue_free()
	await get_tree().process_frame


func _run_main_world() -> void:
	var main := MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	main.enable_opening = false
	add_child(main)
	await main.ready_for_play
	main.hud.visible = false
	main.combat_hud.visible = false
	var view_model: Node = main.player.get_node_or_null("Head/Camera3D/ViewModel")
	if view_model:
		view_model.set_process(false)
		view_model.visible = false

	var world: World = main.world
	var cycle := world.get_node_or_null("DayNightCycle") as DayNightCycle
	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.far = 1600.0
	add_child(cam)
	cam.current = true

	var main_views := [
		["main_kings_way_day", Vector3(-60, world.terrain_height(-60, 82) + 2.8, 82), Vector3(12, 10, 12), 9.0],
		["main_stone_bridge_evening", Vector3(24, world.terrain_height(24, 152) + 3.0, 152), Vector3(72, 4, 180), 17.2],
		["main_waterfall_day", Vector3(62, world.terrain_height(62, -268) + 3.2, -268), Vector3(68, 8, -305), 10.5],
		["main_ashford_night", Vector3(222, world.terrain_height(222, 52) + 2.6, 52), Vector3(248, 4, 42), 21.5],
	]
	for mv in main_views:
		if cycle:
			cycle.set_time_override(float(mv[3]), 0.0)
		cam.global_position = mv[1]
		cam.look_at(mv[2], Vector3.UP)
		await _warmup(12)
		var stats := await _measure_reps(3, 30)
		await _save_shot(String(mv[0]))
		print("MAIN %s  avg=%.2fms  p95=%.2fms  p99=%.2fms  fps=%.1f  draws=%d" % [
			mv[0], stats["avg"], stats["p95"], stats["p99"], stats["fps"], stats["draws"]])

	main.queue_free()


func _warmup(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _measure_reps(reps: int, frames_per_rep: int) -> Dictionary:
	var all_times: Array[float] = []
	var draws := 0
	for r in reps:
		for i in frames_per_rep:
			var t0 := Time.get_ticks_usec()
			await get_tree().process_frame
			all_times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	all_times.sort()
	var sum := 0.0
	for t in all_times:
		sum += t
	var avg := sum / maxf(float(all_times.size()), 1.0)
	var p95: float = all_times[mini(all_times.size() - 1, int(floor(all_times.size() * 0.95)))]
	var p99: float = all_times[mini(all_times.size() - 1, int(floor(all_times.size() * 0.99)))]
	return {"avg": avg, "p95": p95, "p99": p99, "fps": 1000.0 / maxf(avg, 0.001), "draws": draws}


func _save_shot(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(label + ".png"))
