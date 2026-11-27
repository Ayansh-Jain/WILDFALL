extends Node
## Visual check of the warhorse in the real game world: portraits from every side and
## close-ups (an orbit camera), the gaits from the side, the mount sequence, riding in
## third and first person, and frame timing.
##   godot --path . res://tests/horse_tour.tscn -- --out=C:/some/dir [--only=name,name]

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const SPOT := Vector3(150, 0, -62)   ## North Meadow (open ground)

## name, kind, azimuth (deg, 0 = in front of the horse), distance, height, extra
const SHOTS := [
	["front", "portrait", 0.0, 5.0, 1.2, ""],
	["three_quarter", "portrait", 40.0, 5.2, 1.3, ""],
	["left", "portrait", 90.0, 5.5, 1.1, ""],
	["right", "portrait", -90.0, 5.5, 1.1, ""],
	["back", "portrait", 180.0, 5.0, 1.3, ""],
	["head", "portrait", 35.0, 1.5, 1.75, ""],
	["head_side", "portrait", 90.0, 1.4, 1.75, ""],
	["hooves", "portrait", 60.0, 1.6, 0.35, ""],
	["saddle", "portrait", 70.0, 2.0, 1.55, ""],
	["walk_side", "portrait", 90.0, 6.0, 1.1, "walk"],
	["trot_side", "portrait", 90.0, 6.5, 1.1, "trot"],
	["gallop_side", "portrait", 90.0, 8.0, 1.1, "gallop"],
	["mount_start", "mount", 60.0, 4.5, 1.2, "0.5"],
	["mount_mid", "mount", 60.0, 4.5, 1.3, "1.4"],
	["mount_end", "mount", 60.0, 4.5, 1.3, "3.6"],
	["ridden_left", "ridden", 90.0, 5.5, 1.4, ""],
	["ridden_front", "ridden", 25.0, 5.5, 1.5, ""],
	["ridden_tp", "ridden_view", 0.0, 0.0, 0.0, "third"],
	["ridden_fp", "ridden_view", 0.0, 0.0, 0.0, "first"],
	["ridden_trot_side", "ridden", 90.0, 7.0, 1.4, "trot"],
	["ridden_gallop_tp", "ridden_view", 0.0, 0.0, 0.0, "gallop"],
	["dismount_mid", "dismount", 60.0, 4.5, 1.3, "0.9"],
]

var out_dir := "user://horse_tour"
var only := ""
var main: Node
var player: PlayerController
var horse: Horse
var cam: Camera3D
var ground := Vector3.ZERO


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	add_child(main)
	await main.ready_for_play
	var world: World = main.world
	player = main.player
	horse = main.horse
	ground = Vector3(SPOT.x, world.terrain_height(SPOT.x, SPOT.z), SPOT.z)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	print("\n%-20s %8s" % ["shot", "avg ms"])
	for s in SHOTS:
		if only != "" and not Array(only.split(",")).any(func(o: String) -> bool: return String(s[0]).contains(o)):
			continue
		await _shot(s)
	get_tree().quit()


func _reset() -> void:
	var rider := player.get_node("Rider") as Rider
	rider.force_dismount()
	player.set_noclip(false)
	player.teleport(ground + Vector3(-3.0, 0.1, 0.0), 0.0)
	player.input_override = {"move": Vector2.ZERO}
	horse.teleport(ground + Vector3.UP * 0.05, 0.0)
	horse.drive = {}
	for i in 40:
		await get_tree().physics_frame


func _drive(gait: String) -> void:
	var sprint := gait == "gallop"
	horse.cruise = Horse.Gait.WALK if gait == "walk" else Horse.Gait.TROT
	var frames := 150 if gait == "gallop" else 90
	for i in frames:
		horse.drive = {"move": Vector2(0, 1), "sprint": sprint}
		if player.riding:
			player.input_override = {"move": Vector2(0, 1), "sprint": sprint}
		await get_tree().physics_frame


func _mount() -> void:
	var rider := player.get_node("Rider") as Rider
	player.teleport(horse.global_transform * Vector3(-1.4, 0.1, -0.3), horse.rotation.y)
	await get_tree().physics_frame
	rider.mount(horse)


func _shot(s: Array) -> void:
	var kind: String = s[1]
	var extra: String = s[5]
	await _reset()
	var rider := player.get_node("Rider") as Rider
	match kind:
		"portrait":
			if extra != "":
				await _drive(extra)
		"mount":
			await _mount()
			var until := float(extra)
			var t0 := Time.get_ticks_msec()
			while (Time.get_ticks_msec() - t0) / 1000.0 < until and rider.state != Rider.State.RIDING:
				await get_tree().process_frame
		"ridden", "ridden_view":
			await _mount()
			while rider.state != Rider.State.RIDING:
				await get_tree().process_frame
			for i in 30:
				await get_tree().physics_frame
			if extra in ["trot", "gallop"]:
				await _drive(extra)
		"dismount":
			await _mount()
			while rider.state != Rider.State.RIDING:
				await get_tree().process_frame
			for i in 20:
				await get_tree().physics_frame
			rider.dismount()
			var t0 := Time.get_ticks_msec()
			while (Time.get_ticks_msec() - t0) / 1000.0 < float(extra):
				await get_tree().process_frame
	if kind == "ridden_view":
		cam.current = false
		player.camera.current = true
		player.set_third_person(extra != "first")
		player.set_look(horse.rotation.y, deg_to_rad(-10.0 if extra != "first" else -14.0))
		for i in 40:
			await get_tree().process_frame
	else:
		cam.current = true
		player.set_third_person(true)
		var yaw := horse.rotation.y + deg_to_rad(float(s[2]))
		var target := horse.global_position + Vector3.UP * float(s[4])
		if s[0] == "head" or s[0] == "head_side":
			target = (horse.get_node("Rig") as HorseRig).bone_world("head") + Vector3.DOWN * 0.1
		elif s[0] == "saddle":
			target = (horse.get_node("Rig") as HorseRig).seat.global_position
		elif s[0] == "hooves":
			target = horse.global_transform * Vector3(0, 0.25, -0.6)
		var dir := Vector3(sin(yaw), 0, cos(yaw)) * -1.0
		cam.global_position = target + dir * float(s[3]) + Vector3.UP * 0.2
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
	print("%-20s %8.2f" % [s[0], avg / samples.size()])
	player.set_third_person(false)
	player.input_override = {"move": Vector2.ZERO}
	horse.drive = {}
