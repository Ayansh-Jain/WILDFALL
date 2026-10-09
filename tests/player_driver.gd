class_name PlayerDriver
extends RefCounted
## Drives the real PlayerController through its input_override hook, the same
## way a bot or network peer would. Used by movement and traversal tests.

var player: PlayerController
var tree: SceneTree
var log_lines: PackedStringArray = []
var swam := false
var max_depth := 0.0


func _init(p: PlayerController) -> void:
	player = p
	tree = p.get_tree()
	player.input_override = {}


func release() -> void:
	player.input_override = null


func set_input(move := Vector2.ZERO, sprint := false, crouch := false, jump := false, jump_pressed := false) -> void:
	player.input_override = {"move": move, "sprint": sprint, "crouch": crouch, "jump": jump, "jump_pressed": jump_pressed}


func frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func face(target: Vector3) -> void:
	var d := target - player.global_position
	player.set_look(atan2(-d.x, -d.z), 0.0)


## Walks through waypoints (XZ only; physics decides height).
## Returns {ok, reason, reached, time, path_length}.
func walk(points: Array, options := {}) -> Dictionary:
	var sprint: bool = options.get("sprint", true)
	var reach: float = options.get("reach", 1.6)
	var leg_timeout: float = options.get("leg_timeout", 30.0)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t_total := 0.0
	var travelled := 0.0
	var last := player.global_position
	for i in points.size():
		var target: Vector3 = points[i]
		var t_leg := 0.0
		var stuck_t := 0.0
		var check_pos := player.global_position
		var check_t := 0.0
		var sidestep := 0.0
		while true:
			var flat := Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
			if flat.length() < reach:
				break
			face(target)
			var move := Vector2(0, 1)
			if sidestep > 0.0:
				move = Vector2(1 if int(t_leg) % 2 == 0 else -1, 0.6)
				sidestep -= dt
			var jump := stuck_t > 0.8
			set_input(move, sprint, false, jump or player.is_swimming, jump)
			await tree.physics_frame
			t_leg += dt
			t_total += dt
			travelled += player.global_position.distance_to(last)
			last = player.global_position
			if player.is_swimming:
				swam = true
			max_depth = maxf(max_depth, player.water_depth)
			check_t += dt
			if check_t >= 1.0:
				var moved := player.global_position.distance_to(check_pos)
				stuck_t = stuck_t + check_t if moved < 0.6 else 0.0
				if stuck_t > 3.0 and sidestep <= 0.0:
					sidestep = 1.2
				check_pos = player.global_position
				check_t = 0.0
			if t_leg > leg_timeout:
				set_input()
				return {"ok": false, "reason": "stuck near %s heading to waypoint %d %s" % [_fmt(player.global_position), i, _fmt(target)],
					"reached": i, "time": t_total, "path_length": travelled}
	set_input()
	return {"ok": true, "reason": "", "reached": points.size(), "time": t_total, "path_length": travelled}


static func _fmt(v: Vector3) -> String:
	return "(%.0f, %.0f, %.0f)" % [v.x, v.y, v.z]
