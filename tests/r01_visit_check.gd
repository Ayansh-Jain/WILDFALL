extends Node
## R01: the showcase visit with the real Commander and horse, then home again.
##   godot --path . res://tests/r01_visit_check.tscn -- --out=<dir>
## Lives on the root so it survives the scene changes it exercises.

var out_dir := "user://r01_visit"
var passed := 0
var failed := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		_run.call_deferred()


func check(ok: bool, label: String, detail := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", label, "  (%s)" % detail if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _scene_named(wanted: String) -> Node:
	for i in 600:
		await get_tree().process_frame
		var s := get_tree().current_scene
		if s and s.name == wanted and s.is_node_ready():
			return s
	return null


func _shot(shot: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot + ".png"))
	print("  [fps] %s %d" % [shot, Engine.get_frames_per_second()])


func _run() -> void:
	var tree := get_tree()
	tree.current_scene = null
	DevVisit.go(tree, "valley")
	var visit := await _scene_named("Visit") as DevVisit
	check(visit != null, "the visit scene loads")
	if visit == null:
		tree.quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _frames(60)
	# Keep a person at the desk from steering the check.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(not tree.paused, "nothing paused the visit")
	var player := visit.destination.get("player") as PlayerController
	var horse := visit.destination.get("horse") as Horse
	check(player != null and horse != null and visit.recall != null, "the showcase has the real Commander, horse and whistle")
	check(player.camera.current, "the follow camera is current")
	await _shot("valley_start")
	var start := player.global_position
	for i in 150:
		player.input_override = {"move": Vector2(0, 1), "sprint": true}
		await tree.physics_frame
	check(player.global_position.distance_to(start) > 8.0 and player.global_position.y > start.y - 15.0, "he runs through the valley",
		"%.1f m from %s to %s" % [player.global_position.distance_to(start), start, player.global_position])
	await _shot("valley_run")
	player.input_override = {"move": Vector2.ZERO}
	await _frames(20)
	await visit.recall.call_horse()
	for i in 900:
		await tree.physics_frame
		if horse.global_position.distance_to(player.global_position) < 6.0 and not horse.is_recalled():
			break
	check(horse.global_position.distance_to(player.global_position) < 8.0, "the whistle brings the horse",
		"%.1f m" % horse.global_position.distance_to(player.global_position))
	var rider := player.get_node("Rider") as Rider
	for i in 180:
		await tree.physics_frame
		if absf(horse.speed) < 0.1:
			break
	check(rider.mount(horse), "he mounts", "%s speed %.1f" % [rider.mount_refusal(horse), horse.speed])
	await _frames(240)
	check(rider.is_riding(), "and is in the saddle", "state %d t %.2f len %.2f defeated %s horse_dormant %s pos %s horse %s" % [rider.state, rider._t, rider._len, player.is_defeated, horse.dormant, player.global_position, horse.global_position])
	var from := horse.global_position
	for i in 360:
		player.input_override = {"move": Vector2(0, 1), "sprint": true}
		await tree.physics_frame
	check(horse.global_position.distance_to(from) > 15.0 and horse.global_position.y > -5.0, "he rides through the environment",
		"%.1f m" % horse.global_position.distance_to(from))
	await _shot("valley_ride")
	for i in 360:
		player.input_override = {"move": Vector2.ZERO}
		await tree.physics_frame
		if absf(horse.speed) < 0.1:
			break
	check(rider.dismount(), "he dismounts")
	await _frames(240)
	check(rider.state == Rider.State.NONE and not player.riding, "back on foot")
	((player.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig).toggle_swords()
	await _frames(90)
	check(((player.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig).sword_drawn, "both swords drawn")
	await _shot("valley_swords")

	visit.menu.open()
	check(tree.paused, "the visit has a pause menu")
	DevVisit.go_home(tree)
	var main := await _scene_named("Main")
	check(main != null, "return loads the kingdom")
	if main:
		if main.player == null or main.player.process_mode == Node.PROCESS_MODE_DISABLED:
			await main.ready_for_play
		await _frames(60)
		var p: PlayerController = main.player
		check(not tree.paused and p.controls_enabled or main.castle_opening != null, "control is restored at home")
		check(p.camera.current or main.castle_opening != null, "the camera is restored at home")
		check(main.horse != null and tree.get_nodes_in_group("horses").size() >= 1 and p.locks.token_count() == 0, "one personal horse, no leftover locks")
		await _shot("home")
	print("[r01_visit] %d passed, %d failed" % [passed, failed])
	tree.quit(1 if failed > 0 else 0)
