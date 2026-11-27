extends Node
## P06 reproducible movement route: a fixed script of inputs run in an isolated flat lab
## (high above the world), once with the pre-P06 ground model (smooth_locomotion = false)
## and once with the P06 model, repeated and interleaved. Prints a metrics table and, with
## --out=<dir>, a per-tick speed CSV for each mode.
##   godot --headless --fixed-fps 60 --path . res://tests/movement_route.tscn -- --out=<dir>
## Interactive feel check: run the game and toggle `smooth_locomotion` on the Player node.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const LAB_Y := 420.0
const REPS := 3

var out_dir := ""
var main: Node
var player: PlayerController
var rows := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	main = MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	add_child(main)
	await main.ready_for_play
	player = main.player
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, LAB_Y - 0.5, 0)

	for rep in REPS:
		for smooth in [false, true]:
			var key := "smooth" if smooth else "legacy"
			var m := await _run_route(smooth)
			rows[key] = rows.get(key, []) + [m]
	_report()
	get_tree().quit()


var _phys_sum := 0.0
var _phys_n := 0


func _tick(n: int, trace: PackedFloat32Array) -> void:
	for i in n:
		await get_tree().physics_frame
		trace.append(player.ground_speed())
		_phys_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_phys_n += 1


func _run_route(smooth: bool) -> Dictionary:
	player.smooth_locomotion = smooth
	player.controls_enabled = true
	player.teleport(Vector3(0, LAB_Y + 0.05, 0), 0.0)
	player.input_override = {}
	await get_tree().create_timer(0.4).timeout
	var trace := PackedFloat32Array()
	var segs := {}
	_phys_sum = 0.0
	_phys_n = 0
	# 1 run start, 2 run stop, 3 sprint start, 4 sprint stop, 5 reversals, 6 stop.
	player.input_override = {"move": Vector2(0, 1)}
	await _tick(60, trace)
	segs["run_start"] = trace.slice(0, 60)
	var p := player.global_position
	player.input_override = {}
	var stop_trace := PackedFloat32Array()
	await _tick(40, stop_trace)
	segs["run_stop"] = stop_trace
	var stop_dist := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
	player.teleport(Vector3(0, LAB_Y + 0.05, 0), 0.0)
	await get_tree().create_timer(0.3).timeout
	var sprint_trace := PackedFloat32Array()
	player.input_override = {"move": Vector2(0, 1), "sprint": true}
	await _tick(90, sprint_trace)
	segs["sprint_start"] = sprint_trace
	p = player.global_position
	player.input_override = {}
	var sstop := PackedFloat32Array()
	await _tick(50, sstop)
	var sprint_stop_dist := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
	segs["sprint_stop"] = sstop
	player.teleport(Vector3(0, LAB_Y + 0.05, 0), 0.0)
	await get_tree().create_timer(0.3).timeout
	var rev := PackedFloat32Array()
	for i in 90:
		var dir := 1.0 if (i / 12) % 2 == 0 else -1.0
		player.input_override = {"move": Vector2(dir, 0.0)}
		await get_tree().physics_frame
		rev.append(player.ground_speed())
	segs["reversals"] = rev
	player.input_override = {}
	var phys := _phys_sum / maxf(float(_phys_n), 1.0)
	var m := {
		"run_t90": _first(segs["run_start"], player.walk_speed * 0.9, true),
		"run_stop_t": _first(segs["run_stop"], 0.2, false),
		"run_stop_m": stop_dist,
		"sprint_t95": _first(segs["sprint_start"], player.sprint_speed * 0.95, true),
		"sprint_stop_t": _first(segs["sprint_stop"], 0.2, false),
		"sprint_stop_m": sprint_stop_dist,
		"rev_min": _min_after(rev, 14),
		"rev_max": _max(rev),
		"phys_ms": phys * 1000.0,
		"trace": trace + sprint_trace + rev,
	}
	return m


func _first(a: PackedFloat32Array, v: float, rising: bool) -> int:
	for i in a.size():
		if (rising and a[i] >= v) or (not rising and a[i] <= v):
			return i + 1
	return -1


func _min_after(a: PackedFloat32Array, from: int) -> float:
	var m := 99.0
	for i in range(from, a.size()):
		m = minf(m, a[i])
	return m


func _max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m


func _report() -> void:
	var keys := ["run_t90", "run_stop_t", "run_stop_m", "sprint_t95", "sprint_stop_t", "sprint_stop_m", "rev_min", "rev_max", "phys_ms"]
	print("\n[route] median of %d interleaved runs (ticks are 1/60 s)" % REPS)
	print("%-16s %10s %10s" % ["metric", "legacy", "P06"])
	for k in keys:
		print("%-16s %10.2f %10.2f" % [k, _median(rows["legacy"], k), _median(rows["smooth"], k)])
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		for mode in rows:
			var f := FileAccess.open(out_dir.path_join("route_%s.csv" % mode), FileAccess.WRITE)
			f.store_line("tick,speed")
			var tr: PackedFloat32Array = rows[mode][0]["trace"]
			for i in tr.size():
				f.store_line("%d,%.3f" % [i, tr[i]])
			f.close()
		print("[route] CSV written to %s" % out_dir)


func _median(list: Array, key: String) -> float:
	var vals: Array = []
	for m in list:
		vals.append(float(m[key]))
	vals.sort()
	return vals[vals.size() / 2]
