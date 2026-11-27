extends Node
## CPU cost per call of the follow-camera update and the horse's physics step, on open
## ground. Uses only names that existed before R01, so it also runs on older copies.
##   godot --headless --fixed-fps 60 --path . res://tests/r01_perf.tscn

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const CALLS := 3000


func _ready() -> void:
	var main := MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	main.enable_opening = false
	main.campaign_persist = false
	add_child(main)
	await main.ready_for_play
	var player: PlayerController = main.player
	var world: World = main.world
	player.teleport(Vector3(-232, world.terrain_height(-232, 108) + 0.2, 108), 0.0)
	for i in 90:
		await get_tree().physics_frame
	var horse: Horse = main.spawn_horse_near(player)
	for i in 60:
		await get_tree().physics_frame
	player.set_physics_process(false)
	horse.set_physics_process(false)
	for rep in 3:
		await get_tree().physics_frame
		var t0 := Time.get_ticks_usec()
		for i in CALLS:
			player._update_camera(1.0 / 60.0)
		var cam := float(Time.get_ticks_usec() - t0) / CALLS
		horse.drive = {}
		t0 = Time.get_ticks_usec()
		for i in CALLS:
			horse._physics_process(1.0 / 60.0)
		var idle := float(Time.get_ticks_usec() - t0) / CALLS
		print("[r01_perf] run %d: camera %.1f us/tick   horse idle %.1f us/tick" % [rep + 1, cam, idle])
	get_tree().quit()
