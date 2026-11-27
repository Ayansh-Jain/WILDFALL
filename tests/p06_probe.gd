extends Node
## P06 fast probe (no world boot): sweeps start phases for a staircase climb, in both
## ground models, so step-up robustness can be measured in seconds.
##   godot --headless --fixed-fps 60 --path . res://tests/p06_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const Y0 := 100.0


func _ready() -> void:
	_floor(Vector3(-30, 0, -40), Vector3(60, 1, 80), Y0)
	for i in 10:
		var h := 0.18 * (i + 1)
		_floor(Vector3(-2, 0, -2.0 - 0.3 * i), Vector3(4, h, 0.3), Y0 + h)
	_floor(Vector3(-2, 0, -15), Vector3(4, 1.8, 10), Y0 + 1.8)
	# Trace the known failing phase.
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.auto_register = false
	add_child(p)
	await get_tree().physics_frame
	p.teleport(Vector3(0.0, Y0 + 0.05, 2.0 + 3 * 0.0285), 0.0)
	await get_tree().physics_frame
	p.input_override = {"move": Vector2(0, 1)}
	for i in 110:
		await get_tree().physics_frame
		if i >= 62 and i < 70:
			var s := ""
			for k in p.get_slide_collision_count():
				var c := p.get_slide_collision(k)
				s += " n%d=(%.2f,%.2f,%.2f)@y%.3f" % [k, c.get_normal().x, c.get_normal().y, c.get_normal().z, c.get_position().y - Y0]
			print("[probe] i=%d z=%.3f y=%.3f v=%.2f floor=%s wall=%s wedged=%d lifted=%s %s" % [i, p.global_position.z, p.global_position.y - Y0, p.ground_speed(), p.is_on_floor(), p.is_on_wall(), p._wedged, p._lifted, s])
	p.queue_free()
	await get_tree().physics_frame
	for smooth in [true, false]:
		var fails := 0
		var line := ""
		for k in 21:
			var z0 := 2.0 + k * 0.0285  # phase sweep across a 0.3 m stride
			var g := await _climb(smooth, z0, 0.0)
			line += " %.2f" % g
			if g < 1.7:
				fails += 1
		print("[probe] smooth=%s z-phase sweep gains:%s  -> %d/21 failed" % [smooth, line, fails])
		fails = 0
		line = ""
		for k in 11:
			var g := await _climb(smooth, 2.0, -1.4 + k * 0.28)  # lateral offsets incl. riser edges
			line += " %.2f" % g
			if g < 1.7:
				fails += 1
		print("[probe] smooth=%s x-offset sweep gains:%s  -> %d/11 failed" % [smooth, line, fails])
	get_tree().quit()


func _climb(smooth: bool, z0: float, x0: float) -> float:
	var p := PLAYER_SCENE.instantiate() as PlayerController
	p.auto_register = false
	p.smooth_locomotion = smooth
	add_child(p)
	await get_tree().physics_frame
	p.teleport(Vector3(x0, Y0 + 0.05, z0), 0.0)
	await get_tree().physics_frame
	p.input_override = {"move": Vector2(0, 1)}
	for i in 150:
		await get_tree().physics_frame
	var gain := p.global_position.y - Y0
	p.queue_free()
	await get_tree().physics_frame
	return gain


func _floor(corner: Vector3, size: Vector3, top: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := BoxShape3D.new()
	var thick := maxf(size.y, 0.5)
	shape.size = Vector3(size.x, thick, size.z)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(corner.x + size.x * 0.5, top - thick * 0.5, corner.z + size.z * 0.5)
