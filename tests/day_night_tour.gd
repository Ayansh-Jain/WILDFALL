extends Node
## Runs the real world at dusk, night, and dawn and saves reference captures.
##   godot --path . res://tests/day_night_tour.tscn -- --out=D:/some/path

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var out_dir := "user://day_night_tour"
var failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	if out_dir.begins_with("user://"):
		out_dir = ProjectSettings.globalize_path(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main := MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	add_child(main)
	await main.ready_for_play
	var world: World = main.world
	var cycle := world.get_node("DayNightCycle") as DayNightCycle
	var env_count := 0
	for node in world.get_children():
		if node is WorldEnvironment:
			env_count += 1
	_check(env_count == 1, "one WorldEnvironment remains active")
	var checkpoints := {"pre_dawn": 4.3, "dawn": 5.5, "morning": 7.0, "midday": 12.0,
		"afternoon": 15.5, "golden_hour": 17.2, "sunset": 18.4, "dusk": 19.5, "night": 22.0}
	for expected_phase in checkpoints:
		var sample: Dictionary = cycle._sample(float(checkpoints[expected_phase]))
		_check(sample["phase"] == expected_phase, "phase table includes %s" % expected_phase)
	var initial := cycle.get_hour()
	await get_tree().create_timer(1.0).timeout
	_check(not is_equal_approx(initial, cycle.get_hour()), "world clock advances without a sleep or scene change")
	_check(AudioLib.get_instance().get_stream("horse_hoof_1") != null, "horse hoof sample loads")
	_check(AudioLib.get_instance().get_stream("horse_hoof_water") != null, "wet hoof sample loads")
	_check(AudioLib.get_instance().get_stream("birds_loop") != null, "daytime ambience sample loads")
	var horse: Horse = main.horse
	horse.cruise = Horse.Gait.WALK
	horse.drive = {"move": Vector2(0, 1), "sprint": false}
	await get_tree().create_timer(1.2).timeout
	_check(horse.rig.current_state() == "walk", "horse movement selects its walk gait")
	_check(horse.rig._hooves.stream != null, "animation-timed hoofbeat plays while walking")
	horse.drive = null
	var night_lamps := get_tree().get_nodes_in_group("day_night_lights")
	_check(not night_lamps.is_empty(), "castle and village fixtures join the night-light cycle")

	cycle.set_time_override(19.5)
	await get_tree().create_timer(2.2).timeout
	_check(cycle.phase_name == "dusk", "story override blends into dusk", "phase=%s hour=%.2f" % [cycle.phase_name, cycle.get_hour()])
	await _capture(main, "dusk")
	cycle.set_time_override(21.0)
	await get_tree().create_timer(0.5).timeout
	_check(cycle.night_strength > 0.95, "night lighting reaches full night strength")
	var lit_lamps := 0
	for node in night_lamps:
		if is_instance_valid(node) and node is OmniLight3D and node.visible and node.light_energy > 0.0:
			lit_lamps += 1
	_check(lit_lamps > 0, "local fixtures turn on at night", "%d lights" % lit_lamps)
	await _capture(main, "night")
	cycle.set_time_override(5.5)
	await get_tree().create_timer(2.2).timeout
	_check(cycle.phase_name == "dawn", "override blends into dawn", "phase=%s hour=%.2f" % [cycle.phase_name, cycle.get_hour()])
	_check(world.environment.ambient_light_energy > 0.65, "dawn keeps terrain readable")
	await _capture(main, "dawn")
	cycle.clear_time_override()
	_check(not cycle.override_active, "normal clock resumes after story override")
	print("[day_night_tour] %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _capture(main: Node, label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := main.get_viewport().get_texture().get_image()
	var path := out_dir.path_join(label + ".png")
	var err := image.save_png(path)
	_check(err == OK, "%s frame captured" % label, path)


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  ", label, (" (" + detail + ")") if detail != "" else "")
	else:
		failures += 1
		print("  FAIL  ", label, (" (" + detail + ")") if detail != "" else "")
