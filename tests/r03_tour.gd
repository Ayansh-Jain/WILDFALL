extends Node
## R03 visual check (windowed):
##   godot --path . res://tests/r03_tour.tscn -- --out=<dir>
## Never opens the save.

var out := "user://r03_tour"
var main: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	main = (load("res://scenes/main/main.tscn") as PackedScene).instantiate()
	main.set("auto_capture_mouse", false)
	main.set("campaign_persist", false)
	main.set("enable_opening", false)
	main.set("spawn_bots", false)
	add_child(main)
	await main.ready_for_play
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(main.world.get_node("DayNightCycle") as DayNightCycle).set_time_override(10.0, 0.0)
	var ex: ExplorationDirector = main.exploration
	await _view("sign_castle", Vector2(136, 146), Vector2(136, 140))
	await _view("ashford", Vector2(240, 55), Vector2(244, 42))
	await _view("rest_hunters", Vector2(55, -32), Vector2(55, -39))
	await _view("patrol", Vector2(-143, 28), Vector2(-132, 22))
	await _view("great_gate", Vector2(-262, 70), Vector2(-296, 70))
	for id in ["lakeside_castle", "stone_bridge", "southbank", "northmere", "north_bridge", "elder_tree", "war_plains", "eldoria"]:
		ex.discover(id, true)
	ex.set_waypoint(ex.place(Vector2(58, 172)))
	main.compass.guide()
	await _wait(0.8)
	await _shot("wind_compass")
	main.world_map.open()
	await _wait(0.4)
	await _shot("map")
	main.world_map.set_zoom(2.5, main.world_map.world_to_map(Vector3(200, 0, 100)))
	await _wait(0.3)
	await _shot("map_zoom")
	main.world_map.close()
	get_tree().quit()


func _view(shot: String, from: Vector2, look_at: Vector2) -> void:
	var p: PlayerController = main.player
	var d := look_at - from
	p.teleport(main.exploration.place(from) + Vector3.UP * 0.1, atan2(-d.x, -d.y))
	await _wait(2.0)
	await _shot(shot)
	print("[r03-tour] ", shot, " fps ", Engine.get_frames_per_second(), " location ", main.exploration.current_location)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(shot: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(shot + ".png"))
