extends Node
const MAIN := preload("res://scenes/main/main.tscn")
func _ready() -> void:
	var main := MAIN.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	main.campaign_persist = false
	main.enable_opening = false
	add_child(main)
	await main.ready_for_play
	var sites := main.world.get_node("Sites/Structures") as Sites
	var camera := Camera3D.new()
	camera.fov = 68
	add_child(camera)
	var cycle := main.world.get_node("DayNightCycle") as DayNightCycle
	cycle.advance_to_hour(8)
	cycle.start_automatically = false
	var out := "D:/WildFall/Screenshots/RoyalCastle_2026-11-02"
	DirAccess.make_dir_recursive_absolute(out)
	main.hud.hide()
	main.combat_hud.hide()
	main.campaign.chud.hide()
	var shots := [
		["hall", Vector3(8, 3.1, 3), Vector3(8, 4.6, -18)],
		["council", Vector3(11, 3.6, -6), Vector3(5, 3.8, -18)],
		["corridor", Vector3(-0.1, 15.2, -2), Vector3(14, 15.4, 3)],
		["bedroom", Vector3(-3.2, 15.1, -8.8), Vector3(-6.1, 14, -16)],
		["junction", Vector3(20.8, 15, -6.4), Vector3(21.4, 15, 1.5)],
		["terrace", Vector3(17, 25, -18), Vector3(-60, 8, -5)],
		["entrance", Vector3(8, 5, 30), Vector3(8, 12, 0)],
		["approach", Vector3(8, 22, 65), Vector3(8, 12, 0)],
	]
	for shot in shots:
		main.player.teleport(sites.castle_to_world(shot[1] - Vector3.UP * 1.6))
		camera.global_position = sites.castle_to_world(shot[1])
		camera.look_at(sites.castle_to_world(shot[2]))
		camera.make_current()
		for i in 60:
			await get_tree().process_frame
		var times: Array[float] = []
		for i in 90:
			var started := Time.get_ticks_usec()
			await get_tree().process_frame
			times.append((Time.get_ticks_usec() - started) / 1000.0)
		times.sort()
		print("[castle perf] ", shot[0], " median_ms=", times[45], " p95_ms=", times[85])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(shot[0] + ".png"))
		print("[castle tour] ", shot[0], " draw calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " objects=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	get_tree().quit()
