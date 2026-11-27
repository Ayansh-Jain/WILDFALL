class_name RouteGraph
extends RefCounted
## Walkable long-distance routes for soldiers (the project has no navmesh): every
## trail, road and town street from the layout is sampled every few metres, the
## samples are chained along each line and joined where lines meet, and A* runs
## over the result. Soldiers walk the returned points with local steering; the
## last stretch to the goal (and short trips) is direct.

const STEP := 7.0
const JOIN := 6.5

var points := PackedVector3Array()
var _astar := AStar3D.new()
var _grid := {}  ## Vector2i cell -> Array[int] of point ids
const CELL := 24.0


func build(world: World) -> void:
	points.clear()
	_astar.clear()
	_grid.clear()
	var lines: Array = []
	for key in ["trails", "roads"]:
		for t in world.layout.list(key):
			lines.append(WorldLayout.points(t["points"]))
	for d in world.layout.dict("kingdom").get("districts", []):
		if d.has("points"):
			lines.append(WorldLayout.points(d["points"]))
	for poly in lines:
		var prev := -1
		for i in poly.size() - 1:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[i + 1]
			var n := maxi(1, int(ceil(a.distance_to(b) / STEP)))
			for k in n + (1 if i == poly.size() - 2 else 0):
				var p := a.lerp(b, float(k) / n)
				var id := _add(world, p)
				if prev >= 0 and prev != id:
					_astar.connect_points(prev, id)
				prev = id
	# Join samples of different lines that touch (junctions, crossings).
	for id in points.size():
		for other in _near(Vector2(points[id].x, points[id].z), JOIN):
			if other != id and not _astar.are_points_connected(id, other):
				_astar.connect_points(id, other)


func _add(world: World, p: Vector2) -> int:
	# Reuse a sample that already sits here (shared vertices of joined lines).
	for other in _near(p, 1.5):
		return other
	var id := points.size()
	var v := Vector3(p.x, world.terrain_height(p.x, p.y), p.y)
	points.append(v)
	_astar.add_point(id, v)
	var c := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	if not _grid.has(c):
		_grid[c] = []
	(_grid[c] as Array).append(id)
	return id


func _near(p: Vector2, r: float) -> Array[int]:
	var out: Array[int] = []
	var c0 := Vector2i(floori((p.x - r) / CELL), floori((p.y - r) / CELL))
	var c1 := Vector2i(floori((p.x + r) / CELL), floori((p.y + r) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for id in _grid.get(Vector2i(cx, cz), []):
				var q := points[id]
				if Vector2(q.x, q.z).distance_to(p) <= r:
					out.append(id)
	return out


func nearest(p: Vector3, max_r := 60.0) -> int:
	var best := -1
	var best_d := INF
	var r := 12.0
	while r <= max_r and best < 0:
		for id in _near(Vector2(p.x, p.z), r):
			var d := Vector2(points[id].x - p.x, points[id].z - p.z).length()
			if d < best_d:
				best_d = d
				best = id
		r *= 2.0
	return best


## Waypoints from `from` to `to` along the route network, ending at `to`. Short or
## off-network trips return just [to].
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if Vector2(from.x - to.x, from.z - to.z).length() < 35.0 or points.is_empty():
		out.append(to)
		return out
	var a := nearest(from)
	var b := nearest(to)
	if a < 0 or b < 0:
		out.append(to)
		return out
	var path := _astar.get_point_path(a, b)
	# Drop leading points behind us and trailing points past the goal.
	var start := 0
	while start + 1 < path.size() and _flat(path[start + 1], from) < _flat(path[start], from) and _flat(path[start], from) < 20.0:
		start += 1
	for i in range(start, path.size()):
		if _flat(path[i], to) < 6.0:
			break
		out.append(path[i])
	out.append(to)
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
