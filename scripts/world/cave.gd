class_name Cave
extends Node3D
## Builds the cave interior from the ASCII map in the layout: floor, walls and
## ceilings as box geometry with matching collision, plus crystals, a few warm
## and cold lights, and a trail of glowing mushrooms leading back to each mouth.
## The terrain generator has already raised a dome over it and cut the mouths.

signal player_entered
signal player_exited

const STONE_MAT := preload("res://assets/materials/stone.tres")
const GLOW_MAGIC := preload("res://assets/materials/glow_magic.tres")
const CAVE_ROCK := Color(0.24, 0.24, 0.26)
const CAVE_FLOOR := Color(0.2, 0.19, 0.18)

var world: World
var info: Dictionary
var path_cells: Array[Vector2i] = []
var players_inside := 0

var _kit: MeshKit
var _glow: MeshKit
var _body: StaticBody3D
var _rng := RandomNumberGenerator.new()


func build(w: World) -> void:
	world = w
	info = w.terrain_data.cave
	if info.is_empty():
		return
	_rng.seed = 5150
	_kit = MeshKit.new(5151, 0.1)
	_glow = MeshKit.new(5152)
	_body = StaticBody3D.new()
	_body.name = "CaveCollision"
	_body.collision_layer = Layers.WORLD
	add_child(_body)
	var cells: Dictionary = info["cells"]
	var cs: float = info["cell"]
	var floor_h: float = info["floor"]
	var ceil: Dictionary = info["ceiling"]
	for key: Vector2i in cells:
		var ch: String = cells[key]
		var c := _center(key)
		var ch_h: float = ceil[ch]
		_solid(Vector3(c.x, floor_h - 0.5, c.y), Vector3(cs + 0.04, 1.0, cs + 0.04), CAVE_FLOOR)
		_solid(Vector3(c.x, floor_h + ch_h + 0.5, c.y), Vector3(cs + 0.04, 1.0, cs + 0.04), CAVE_ROCK * 0.8)
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := key + dir
			if cells.has(n):
				var nh: float = ceil[cells[n]]
				if nh < ch_h:
					# Lip where a tall chamber meets a lower tunnel.
					var e := c + Vector2(dir) * cs * 0.5
					var size := Vector3(0.6 if dir.x != 0 else cs, ch_h - nh + 1.0, cs if dir.x != 0 else 0.6)
					_solid(Vector3(e.x, floor_h + nh + size.y * 0.5, e.y), size, CAVE_ROCK)
				continue
			if ch == "m" and _outside_grid(n):
				_mouth_facade(c, dir, floor_h, ch_h)
				continue  # this is the open mouth
			var t := 1.2
			var e2 := c + Vector2(dir) * (cs * 0.5 + t * 0.5)
			var wall_h := ch_h + 2.0
			var wsize := Vector3(t, wall_h, cs + 2.0 * t) if dir.x != 0 else Vector3(cs + 2.0 * t, wall_h, t)
			_solid(Vector3(e2.x, floor_h - 1.0 + wall_h * 0.5, e2.y), wsize, CAVE_ROCK * _rng.randf_range(0.85, 1.1))
			_wall_detail(c, dir, floor_h, ch_h)
	_decorate()
	_find_paths()
	_place_path_lights()
	_zone()
	var mi := MeshInstance3D.new()
	mi.name = "CaveMesh"
	mi.mesh = _kit.to_mesh(STONE_MAT)
	add_child(mi)
	var gi := MeshInstance3D.new()
	gi.name = "CaveGlow"
	gi.mesh = _glow.to_mesh(GLOW_MAGIC)
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(gi)


func floor_height() -> float:
	return info.get("floor", 0.0)


func cell_center_world(key: Vector2i) -> Vector3:
	var c := _center(key)
	return Vector3(c.x, floor_height(), c.y)


func _center(key: Vector2i) -> Vector2:
	var o: Vector2 = info["origin"]
	var cs: float = info["cell"]
	return o + (Vector2(key) + Vector2(0.5, 0.5)) * cs


func _outside_grid(k: Vector2i) -> bool:
	return k.x < 0 or k.y < 0 or k.x >= info["cols"] or k.y >= info["rows"]


func _solid(center: Vector3, size: Vector3, col: Color) -> void:
	_kit.add_box(Transform3D(Basis.IDENTITY, center), size, col)
	var b := BoxShape3D.new()
	b.size = size
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.position = center
	_body.add_child(cs)


## Rock face above a mouth: fills the gap between the tunnel roof and the
## hillside where the terrain was cut away, and frames the opening.
func _mouth_facade(c: Vector2, dir: Vector2i, floor_h: float, ch_h: float) -> void:
	var cs: float = info["cell"]
	var top: float = floor_h + float(info["dome_height"]) + 1.0
	var bottom := floor_h + ch_h + 0.5
	var e := c + Vector2(dir) * (cs * 0.5 - 1.1)
	var size := Vector3(2.2, top - bottom, cs + 2.4) if dir.x != 0 else Vector3(cs + 2.4, top - bottom, 2.2)
	_solid(Vector3(e.x, bottom + size.y * 0.5, e.y), size, CAVE_ROCK * 1.15)
	var side := Vector2(-dir.y, dir.x)
	# Boulders break up the facade so it reads as a cliff face, not a slab.
	var out := Vector2(dir)
	for row in 4:
		for col in 3:
			var p := e + out * 1.3 + side * (col - 1) * 2.4 + side * _rng.randf_range(-0.4, 0.4)
			var y := bottom + 1.4 + row * 2.6 + _rng.randf_range(-0.4, 0.4)
			if y > top + 0.5:
				continue
			_kit.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 0.85, 1.0)), Vector3(p.x, y, p.y)), _rng.randf_range(1.5, 2.1), CAVE_ROCK * _rng.randf_range(1.05, 1.3), true, 0.3)
	for s: float in [-1.0, 1.0]:
		for k in 3:
			var p := c + out * (cs * 0.5 + 0.4) + side * s * (cs * 0.5 + 0.7)
			_kit.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.9, 1.3, 0.9)), Vector3(p.x, floor_h + 0.8 + k * 2.2, p.y)), _rng.randf_range(1.0, 1.4), CAVE_ROCK * 1.2, true, 0.3)
	# A brazier beside each mouth makes the entrance readable from the trail.
	var brazier: RuinPiece = Sites.PIECES["brazier"].instantiate()
	var bp := c + out * (cs * 0.5 + 2.2) + side * (cs * 0.5 + 0.8)
	brazier.position = Vector3(bp.x, floor_h - 0.05, bp.y)
	add_child(brazier)

## Visual-only rock lumps pressed against walls so tunnels feel carved, not built.
func _wall_detail(c: Vector2, dir: Vector2i, floor_h: float, ch_h: float) -> void:
	var cs: float = info["cell"]
	for i in 2:
		var along := Vector2(-dir.y, dir.x) * _rng.randf_range(-cs * 0.35, cs * 0.35)
		var p := c + Vector2(dir) * (cs * 0.5 + 0.1) + along
		var y := floor_h + _rng.randf_range(0.3, ch_h - 0.5)
		_kit.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.4, 1.0)), Vector3(p.x, y, p.y)), _rng.randf_range(0.45, 0.8), CAVE_ROCK * 1.1, false, 0.3)


func _decorate() -> void:
	var cells: Dictionary = info["cells"]
	var floor_h: float = info["floor"]
	var ceil: Dictionary = info["ceiling"]
	var cs: float = info["cell"]
	for key: Vector2i in cells:
		var ch: String = cells[key]
		if ch == "m":
			continue
		var c := _center(key)
		var h: float = ceil[ch]
		# Stalactites hang from every cell; stalagmites only hug the edges of tall chambers.
		for i in 2:
			var p := c + Vector2(_rng.randf_range(-1.4, 1.4), _rng.randf_range(-1.4, 1.4))
			var len := _rng.randf_range(0.4, 1.3)
			_kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(p.x, floor_h + h, p.y)), 0.22, 0.0, len, 5, CAVE_ROCK)
		if ch == "C" and _rng.randf() < 0.45:
			var edge := c + Vector2(_rng.randf_range(-1.6, 1.6), _rng.randf_range(-1.6, 1.6))
			if _is_wall_adjacent(key):
				_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(edge.x, floor_h, edge.y)), 0.35, 0.0, _rng.randf_range(0.8, 1.8), 5, CAVE_ROCK * 1.1)
	# Crystal clusters and lights.
	var lights := [
		[Vector2i(7, 8), Color(0.4, 1.0, 0.9), 2.2, 16.0],
		[Vector2i(7, 1), Color(0.75, 0.5, 1.0), 1.8, 12.0],
		[Vector2i(3, 4), Color(1.0, 0.65, 0.35), 1.6, 10.0],
		[Vector2i(7, 13), Color(0.4, 1.0, 0.9), 1.0, 8.0],
	]
	for l in lights:
		var key: Vector2i = l[0]
		if not cells.has(key):
			continue
		var c := _center(key)
		for i in 5:
			var p := c + Vector2(_rng.randf_range(-1.5, 1.5), _rng.randf_range(-1.5, 1.5))
			var tilt := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.1, 0.5))
			var col: Color = l[1]
			_glow.add_cylinder(Transform3D(tilt, Vector3(p.x, floor_h, p.y)), 0.16, 0.0, _rng.randf_range(0.6, 1.4), 4, col)
		var light := OmniLight3D.new()
		light.position = Vector3(c.x, floor_h + 2.4, c.y)
		light.light_color = l[1]
		light.light_energy = l[2]
		light.omni_range = l[3]
		light.omni_attenuation = 1.3
		add_child(light)
	# A glimmer of cave water in the chamber.
	var pool := _center(Vector2i(8, 9))
	_glow.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(pool.x, floor_h + 0.01, pool.y)), 1.6, 1.4, 0.02, 9, Color(0.05, 0.14, 0.17))


func _is_wall_adjacent(key: Vector2i) -> bool:
	var cells: Dictionary = info["cells"]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not cells.has(key + d):
			return true
	return false


## Breadth-first paths from the chamber to every mouth; used for the glowing trail.
func _find_paths() -> void:
	var cells: Dictionary = info["cells"]
	var start := Vector2i(7, 8)
	var prev := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var k: Vector2i = queue.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + d
			if cells.has(n) and not prev.has(n):
				prev[n] = k
				queue.append(n)
	for key: Vector2i in cells:
		if cells[key] != "m":
			continue
		var cur := key
		while cur != start and prev.has(cur):
			if not path_cells.has(cur):
				path_cells.append(cur)
			cur = prev[cur]


func _place_path_lights() -> void:
	var floor_h: float = info["floor"]
	var i := 0
	for key in path_cells:
		i += 1
		if i % 2 == 0:
			continue
		var c := _center(key) + Vector2(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-1.2, 1.2))
		for m in 3:
			var p := c + Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3))
			var hgt := _rng.randf_range(0.12, 0.25)
			_glow.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, floor_h, p.y)), 0.03, 0.02, hgt, 4, Color(0.5, 0.7, 0.7))
			_glow.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, floor_h + hgt, p.y)), 0.1, 0.0, 0.06, 6, Color(0.6, 1.0, 0.9))


## Trigger volume covering the roofed cells; dims ambient light while inside.
func _zone() -> void:
	var area := Area3D.new()
	area.name = "CaveZone"
	area.collision_layer = 0
	area.collision_mask = Layers.PLAYER
	area.monitorable = false
	var cells: Dictionary = info["cells"]
	var cs: float = info["cell"]
	var floor_h: float = info["floor"]
	for key: Vector2i in cells:
		if cells[key] == "m":
			continue
		var c := _center(key)
		var b := BoxShape3D.new()
		b.size = Vector3(cs, 4.0, cs)
		var shape := CollisionShape3D.new()
		shape.shape = b
		shape.position = Vector3(c.x, floor_h + 2.0, c.y)
		area.add_child(shape)
	area.body_entered.connect(func(body: Node) -> void:
		if body is PlayerController:
			players_inside += 1
			if players_inside == 1:
				player_entered.emit())
	area.body_exited.connect(func(body: Node) -> void:
		if body is PlayerController:
			players_inside = maxi(players_inside - 1, 0)
			if players_inside == 0:
				player_exited.emit())
	add_child(area)
