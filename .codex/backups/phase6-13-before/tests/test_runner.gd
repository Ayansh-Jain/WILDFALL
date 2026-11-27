extends Node
## Headless test suite. Run from the Game folder:
##   godot --headless --path . res://tests/test_runner.tscn
## Optional: -- --only=<substring> to run a subset, --skip-walk to skip the
## (slower) traversal walks. Exit code 0 = all passed.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

const SUITES := ["test_terrain", "test_spawns", "test_empire_network", "test_line_of_sight", "test_player", "test_scroll", "test_settings",
	"test_identity", "test_combat", "test_defense", "test_power", "test_soak", "test_commander", "test_sitting", "test_horse", "test_reve", "test_story", "test_traversal"]

var passed := 0
var failed := 0
var only := ""
var skip_walk := false
var main: Node
var world: World


## Real-time limit: a hung await must not stall CI forever.
const WATCHDOG_SECONDS := 600

var _start_ms := 0


func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
		if arg == "--skip-walk":
			skip_walk = true
	await _run()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	main = MAIN_SCENE.instantiate()
	main.set("auto_capture_mouse", false)
	main.set("spawn_bots", false)
	add_child(main)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		if world == null:
			print("[tests] FAIL: the world never became ready (script error during generation?)")
			get_tree().quit(4))
	await main.ready_for_play
	world = main.get_node("World")
	print("[tests] world ready in %d ms" % (Time.get_ticks_msec() - t0))

	for file in SUITES:
		var path := "res://tests/%s.gd" % file
		if not ResourceLoader.exists(path):
			continue
		if only != "" and not String(file).contains(only):
			continue
		if skip_walk and file == "test_traversal":
			continue
		var s: GDScript = load(path)
		if s == null or not s.can_instantiate():
			check(false, "%s loads without script errors" % file)
			continue
		var suite: Node = s.new()
		suite.name = file
		add_child(suite)
		print("\n=== %s ===" % suite.name)
		await suite.run(self)
		suite.queue_free()

	print("\n[tests] %d passed, %d failed (%.1f s)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(1 if failed > 0 else 0)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - _start_ms > WATCHDOG_SECONDS * 1000:
		print("
[tests] WATCHDOG: aborting after %d s (a test is probably hung)" % WATCHDOG_SECONDS)
		get_tree().quit(3)


func check(condition: bool, label: String, detail := "") -> bool:
	if condition:
		passed += 1
		print("  PASS  ", label, ("  (" + detail + ")") if detail != "" else "")
	else:
		failed += 1
		print("  FAIL  ", label, ("  (" + detail + ")") if detail != "" else "")
	return condition


func physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
