extends Node
## Frame cost of the horse in the real scenes: forest, castle, village. At each place
## the frame time is measured on foot with the horse hidden, then riding (third and
## first person), twice and interleaved (the laptop throttles; distrust single runs).
##   godot --path . res://tests/horse_perf.tscn [-- --out=dir]

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const PLACES := {"forest": Vector2(-205, 60), "castle": Vector2(150, 150), "village": Vector2(238, 48)}
const LOOK := {"forest": Vector2(-150, 120), "castle": Vector2(212, 150), "village": Vector2(250, 40)}

var out_dir := ""
var main: Node
var player: PlayerController
var horse: Horse
var results := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	add_child(main)
	await main.ready_for_play
	player = main.player
	horse = main.horse
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
	for rnd in 2:
		for place in PLACES:
			if only != "" and place != only:
				continue
			for mode in ["no_horse", "riding_tp", "riding_fp"]:
				var ms := await _measure(place, mode)
				var key := "%s/%s" % [place, mode]
				results[key] = results.get(key, []) + [ms]
	print("\n%-22s %10s %10s" % ["place/mode", "run 1 ms", "run 2 ms"])
	for k in results:
		print("%-22s %10.2f %10.2f" % [k, results[k][0], results[k][1]])
	get_tree().quit()


func _measure(place: String, mode: String) -> float:
	var rider := player.get_node("Rider") as Rider
	rider.force_dismount()
	var xz: Vector2 = PLACES[place]
	var w: World = main.world
	# On the ground (not on a wall walk): search from just above the terrain.
	var res := SpawnValidator.find(w, xz, w.terrain_height(xz.x, xz.y) + 1.0, 12.0)
	var pos: Vector3 = res["position"]
	var look: Vector2 = LOOK[place]
	var yaw := atan2(-(look.x - pos.x), -(look.y - pos.z))
	horse.visible = mode != "no_horse"
	horse.process_mode = Node.PROCESS_MODE_INHERIT if mode != "no_horse" else Node.PROCESS_MODE_DISABLED
	horse.teleport(pos + Vector3.UP * 0.05, yaw)
	player.teleport(horse.global_transform * Vector3(-1.2, 0.1, -0.3) if mode != "no_horse" else pos + Vector3.UP * 0.1, yaw)
	player.camera.current = true
	player.set_third_person(mode != "riding_fp")
	player.set_look(yaw, deg_to_rad(-6.0))
	for i in 20:
		await get_tree().physics_frame
	if mode != "no_horse":
		rider.mount(horse)
		while rider.state != Rider.State.RIDING:
			await get_tree().process_frame
		player.input_override = {"move": Vector2(0, 0.6)}
		horse.cruise = Horse.Gait.WALK
	for i in 60:
		await get_tree().process_frame
	var total := 0.0
	var n := 180
	var last := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		total += (now - last) / 1000.0
		last = now
	if out_dir != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [place, mode]))
	player.input_override = {"move": Vector2.ZERO}
	return total / n
