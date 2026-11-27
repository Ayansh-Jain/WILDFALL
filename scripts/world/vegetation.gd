class_name Vegetation
extends Node3D
## Scatters trees, rocks, logs, bushes and ground clutter from the terrain's
## forest mask, using a seeded jittered grid. Rendering uses one
## MultiMeshInstance3D per prop type per 68 m chunk (frustum + distance culled).
## Collision: trunks/rocks/logs block movement (layer "world"); bushes only
## block sight (layer "foliage_sight") so they hide players without trapping them.

## prop -> [visibility range (m), casts shadow, far-LOD range]. Props with a far
## range get a detailed near mesh up to the first value and a lighter "_far"
## mesh beyond it.
const RENDER := {
	"pine": [72.0, true, 330.0], "fir": [72.0, true, 330.0], "oak": [72.0, true, 310.0], "birch": [68.0, true, 290.0],
	"dead_tree": [300.0, true],
	"rock0": [260.0, true], "rock1": [260.0, true], "rock2": [260.0, true], "rock3": [260.0, true],
	"log": [150.0, true], "bush0": [80.0, true, 170.0], "bush1": [80.0, true, 170.0], "bush2": [80.0, true, 170.0],
	"fern": [54.0, false], "grass": [50.0, false], "grass_tall": [64.0, false], "pebble": [40.0, false], "reeds": [95.0, false], "mushrooms": [75.0, false],
	"flower0": [46.0, false], "flower1": [46.0, false], "flower2": [42.0, false], "flower3": [58.0, false], "flower4": [46.0, false],
	"rush": [60.0, false], "mosspatch": [40.0, false], "branch": [60.0, false],
}
## Ground clutter uses small chunks so it fades in smoothly around the player.
const SMALL_CHUNK := ["grass", "grass_tall", "fern", "pebble", "mushrooms", "flower0", "flower1", "flower2", "flower3", "flower4", "rush", "mosspatch", "branch"]
const SMALL_CHUNK_SIZE := 20.0

var counts := {}
var step_ms := {}  ## pass -> milliseconds (for profiling)

var _world: World
var _td: TerrainData
var _rng := RandomNumberGenerator.new()
var _chunk_size := 68.0
var _instances := {}      ## "prop|cx|cz" -> [[Transform3D, Color], ...]
var _solid := {}          ## chunk key -> StaticBatch
var _sight := {}          ## chunk key -> StaticBatch
var _occupied := {}       ## Vector2i (3 m cell) -> [[Vector2, radius], ...]
var _exclusions: Array = []  ## [[Vector2, radius], ...]
var _excl_grid := {}         ## Vector2i (EXCL_CELL m) -> exclusions overlapping that cell
var _shape_cache := {}
const EXCL_CELL := 24.0


func build(world: World) -> void:
	_world = world
	_td = world.terrain_data
	_chunk_size = _td.cell * world.layout.chunk_cells
	_rng.seed = GameState.world_seed * 7919 + 17
	for step in [_collect_exclusions, _scatter_trees, _scatter_logs, _scatter_rocks, _scatter_bushes, _scatter_clutter, _scatter_riverbank, _scatter_flower_patches, _emit_multimeshes]:
		var t0 := Time.get_ticks_usec()
		step.call()
		step_ms[step.get_method()] = (Time.get_ticks_usec() - t0) / 1000
	var space := get_world_3d().space
	for b in _solid.values():
		b.commit(space)
	for b in _sight.values():
		b.commit(space)


func _exit_tree() -> void:
	for b in _solid.values():
		b.release()
	for b in _sight.values():
		b.release()


## Keeps props out of sites, bridge ends, spawns, scroll markers and cave mouths.
func _collect_exclusions() -> void:
	var L := _world.layout
	for s in L.list("sites"):
		var r := float(s["radius"])
		if s["type"] == "shrine":
			r = 12.0
		_exclusions.append([WorldLayout.v2(s["center"]), r + 4.0])
	for ex in L.list("vegetation_exclusions"):
		_exclusions.append([WorldLayout.v2(ex["center"]), float(ex["radius"])])
	for b in L.list("bridges"):
		_exclusions.append([WorldLayout.v2(b["a"]), 7.0])
		_exclusions.append([WorldLayout.v2(b["b"]), 7.0])
	for p in L.list("player_spawns"):
		_exclusions.append([WorldLayout.v2(p), 6.0])
	for m in L.list("scroll_spawns"):
		_exclusions.append([WorldLayout.v2(m["pos"]), 4.5])
	for poi in L.list("points_of_interest"):
		_exclusions.append([WorldLayout.v2(poi["pos"]), 3.0])
	if not _td.cave.is_empty():
		for ex in _td.cave["exits"]:
			var r: Rect2 = ex[0]
			_exclusions.append([r.get_center(), 12.0])
	var sites := _world.get_node_or_null("Sites/Structures")
	if sites and "vegetation_blockers" in sites:
		_exclusions.append_array(sites.vegetation_blockers)
	# Bucket by grid cell so each query only tests nearby circles.
	for e in _exclusions:
		var c: Vector2 = e[0]
		var reach: float = float(e[1]) + 3.0
		for gz in range(floori((c.y - reach) / EXCL_CELL), floori((c.y + reach) / EXCL_CELL) + 1):
			for gx in range(floori((c.x - reach) / EXCL_CELL), floori((c.x + reach) / EXCL_CELL) + 1):
				var key := Vector2i(gx, gz)
				if not _excl_grid.has(key):
					_excl_grid[key] = []
				_excl_grid[key].append(e)


func _excluded(p: Vector2, r: float) -> bool:
	for e in _excl_grid.get(Vector2i(floori(p.x / EXCL_CELL), floori(p.y / EXCL_CELL)), []):
		if p.distance_to(e[0]) < e[1] + r:
			return true
	if not _td.cave.is_empty() and _td.cave["rect"].grow(3.0 + r).has_point(p):
		return true
	# Keep the curtain wall's footing clear on both sides.
	if not _td.wall_dist.is_empty():
		var wd := _td.wall_distance(p.x, p.y)
		if wd > -7.0 - r and wd < 5.0 + r and _td.mountain_weight(p.x, p.y) < 0.5:
			return true
	return _td.is_hole_at(p.x, p.y)


## Ground cover only matters where players can stand: inside the kingdom.
func _inside(x: float, z: float) -> bool:
	return _td.wall_dist.is_empty() or _td.wall_distance(x, z) < -1.0 or _td.mountain_weight(x, z) >= 0.5


func _free_at(p: Vector2, r: float) -> bool:
	var c := Vector2i(floor(p.x / 3.0), floor(p.y / 3.0))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for o in _occupied.get(c + Vector2i(dx, dz), []):
				if p.distance_to(o[0]) < r + o[1]:
					return false
	return true


func _occupy(p: Vector2, r: float) -> void:
	var c := Vector2i(floor(p.x / 3.0), floor(p.y / 3.0))
	if not _occupied.has(c):
		_occupied[c] = []
	_occupied[c].append([p, r])


func _chunk_key(p: Vector2, size := -1.0) -> String:
	var s := _chunk_size if size <= 0.0 else size
	return "%d|%d" % [floor(p.x / s), floor(p.y / s)]


func _add_instance(prop: String, xform: Transform3D, tint: Color) -> void:
	var size := SMALL_CHUNK_SIZE if prop in SMALL_CHUNK else -1.0
	var key := prop + "|" + _chunk_key(Vector2(xform.origin.x, xform.origin.z), size)
	if not _instances.has(key):
		_instances[key] = []
	_instances[key].append([xform, tint])
	counts[prop] = counts.get(prop, 0) + 1


func _batch(table: Dictionary, p: Vector2, layer: int) -> StaticBatch:
	var key := _chunk_key(p)
	if not table.has(key):
		table[key] = StaticBatch.new(layer, self)
	return table[key]


func _tint(spread := 0.15) -> Color:
	var b := _rng.randf_range(1.0 - spread, 1.0 + spread)
	return Color(b * _rng.randf_range(0.95, 1.05), b, b * _rng.randf_range(0.95, 1.05), 1.0)


func _ground(x: float, z: float, sink := 0.12) -> Vector3:
	return Vector3(x, _td.height_at(x, z) - sink, z)


func _jittered_cells(cell: float, half: float, fn: Callable) -> void:
	var count := int(ceil(half * 2.0 / cell))
	for j in count:
		for i in count:
			var x := -half + (i + _rng.randf_range(0.15, 0.85)) * cell
			var z := -half + (j + _rng.randf_range(0.15, 0.85)) * cell
			fn.call(x, z)


func _cylinder(radius: float, height: float) -> CylinderShape3D:
	var key := "cyl_%.2f_%.2f" % [radius, height]
	if not _shape_cache.has(key):
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		_shape_cache[key] = s
	return _shape_cache[key]


func _sphere(radius: float) -> SphereShape3D:
	var key := "sph_%.2f" % radius
	if not _shape_cache.has(key):
		var s := SphereShape3D.new()
		s.radius = radius
		_shape_cache[key] = s
	return _shape_cache[key]


# --- scatter passes ----------------------------------------------------------

func _scatter_trees() -> void:
	var half := _world.layout.half_size - 6.0
	var wl := _world.water_level
	_jittered_cells(4.8, half, func(x: float, z: float) -> void:
		var p := Vector2(x, z)
		var f := _td.sample(_td.forest, x, z)
		if _rng.randf() > f:
			return
		var h := _td.height_at(x, z)
		if h < wl + 0.9 or _td.normal_at(x, z).y < 0.86:
			return
		if _td.sample(_td.trail_dist, x, z) < 1.6 or _excluded(p, 1.5):
			return
		var near_water := _td.sample(_td.water_influence, x, z) > 0.02 or h < 2.6
		var deep := f > 0.6
		var roll := _rng.randf()
		var prop := "pine"
		if near_water:
			prop = "birch" if roll < 0.4 else ("oak" if roll < 0.75 else ("pine" if roll < 0.95 else "dead_tree"))
		elif deep:
			prop = "fir" if roll < 0.45 else ("pine" if roll < 0.8 else ("oak" if roll < 0.9 else "dead_tree"))
		else:
			prop = "pine" if roll < 0.45 else ("oak" if roll < 0.75 else ("birch" if roll < 0.87 else ("dead_tree" if roll < 0.95 else "fir")))
		var s := _rng.randf_range(0.8, 1.25)
		if deep and _rng.randf() < 0.12:
			s = _rng.randf_range(1.4, 1.8)
		var trunk_r: float = PropMeshes.TRUNK_RADIUS[prop] * s
		if not _free_at(p, trunk_r + 1.0):
			return
		_occupy(p, trunk_r + 1.0)
		var tilt := Basis(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized(), _rng.randf_range(0.0, 0.05))
		var basis := tilt * Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		var origin := _ground(x, z, 0.2)
		_add_instance(prop, Transform3D(basis, origin), _tint())
		var trunk_h := 7.0 * s
		_batch(_solid, p, Layers.WORLD).add(_cylinder(snappedf(trunk_r, 0.02), snappedf(trunk_h, 0.5)),
				Transform3D(Basis.IDENTITY, origin + Vector3.UP * trunk_h * 0.5)))


func _scatter_logs() -> void:
	var half := _world.layout.playable_half
	_jittered_cells(16.0, half, func(x: float, z: float) -> void:
		var f := _td.sample(_td.forest, x, z)
		if _rng.randf() > f * 0.55:
			return
		if _td.normal_at(x, z).y < 0.94 or _td.height_at(x, z) < _world.water_level + 1.0:
			return
		var s := _rng.randf_range(0.8, 1.15)
		var yaw := _rng.randf() * TAU
		var dir := Vector2(cos(yaw), -sin(yaw))
		var length := 6.0 * s
		var mid := Vector2(x, z) + dir * length * 0.5
		for t: float in [0.0, 0.5, 1.0]:
			var q := Vector2(x, z) + dir * length * t
			if _td.sample(_td.trail_dist, q.x, q.y) < 2.0 or _excluded(q, 1.0) or not _free_at(q, 0.9):
				return
		for t: float in [0.0, 0.5, 1.0]:
			_occupy(Vector2(x, z) + dir * length * t, 0.8)
		# Rest the log on the higher end so it never floats.
		var y := maxf(_td.height_at(x, z), _td.height_at(x + dir.x * length, z + dir.y * length)) - 0.12
		var xform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, y, z))
		_add_instance("log", xform, _tint(0.1))
		var shape := _cylinder(snappedf(0.34 * s, 0.02), snappedf(length, 0.1))
		var col_xform := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5),
				Vector3(mid.x, y + 0.35 * s, mid.y))
		_batch(_solid, mid, Layers.WORLD).add(shape, col_xform)
	)


func _scatter_rocks() -> void:
	var half := _world.layout.half_size - 10.0
	_jittered_cells(9.0, half, func(x: float, z: float) -> void:
		var p := Vector2(x, z)
		var nrm := _td.normal_at(x, z)
		var f := _td.sample(_td.forest, x, z)
		var steep := 1.0 - smoothstep(0.75, 0.92, nrm.y)
		var chance := 0.05 + 0.35 * steep + 0.08 * f
		if not _td.in_playable(x, z, -20.0):
			chance *= 0.5
		if _rng.randf() > chance:
			return
		if _td.height_at(x, z) < _world.water_level - 0.6:
			return
		var s := lerpf(0.5, 2.4, pow(_rng.randf(), 2.2))
		if _td.sample(_td.trail_dist, x, z) < s * 1.3 + 0.5 or _excluded(p, s):
			return
		if not _free_at(p, s * 1.05):
			return
		_occupy(p, s * 1.05)
		var prop := "rock%d" % _rng.randi_range(0, 3)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		var origin := _ground(x, z, 0.25 * s)
		_add_instance(prop, Transform3D(basis, origin), _tint(0.12))
		# Supporting smaller stones nestled around large landmark boulders.
		if s >= 1.25:
			var sup_count := 2 if s >= 1.7 else 1
			for sc in sup_count:
				var a := _rng.randf() * TAU
				var dist := s * _rng.randf_range(0.75, 1.15)
				var sx := x + cos(a) * dist
				var sz := z + sin(a) * dist
				if _td.sample(_td.trail_dist, sx, sz) >= 0.8 and not _excluded(Vector2(sx, sz), 0.35):
					var ss := s * _rng.randf_range(0.24, 0.42)
					var sb := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * ss)
					_add_instance("rock%d" % _rng.randi_range(0, 3), Transform3D(sb, _ground(sx, sz, 0.22 * ss)), _tint(0.14))
		if s >= 0.6:
			var key := "%s_%.1f" % [prop, s]
			if not _shape_cache.has(key):
				var hull := ConvexPolygonShape3D.new()
				hull.points = PropMeshes.rock_hull(prop, snappedf(s, 0.1))
				_shape_cache[key] = hull
			_batch(_solid, p, Layers.WORLD).add(_shape_cache[key], Transform3D(Basis(Vector3.UP, basis.get_euler().y), origin)))


func _scatter_bushes() -> void:
	var half := maxf(_world.layout.playable_half + 10.0, _clutter_half())
	_jittered_cells(4.2, half, func(x: float, z: float) -> void:
		var u := _rng.randf()
		if u > 0.62:
			return
		if not _inside(x, z):
			return
		var f := _td.sample(_td.forest, x, z)
		var edge := 0.1 if f > 0.08 and f < 0.45 else 0.0
		if u > clampf(0.02 + f * 0.31 + edge, 0.0, 0.48):
			return
		if _td.height_at(x, z) < _world.water_level + 0.5 or _td.normal_at(x, z).y < 0.8:
			return
		var p := Vector2(x, z)
		if _td.sample(_td.trail_dist, x, z) < 0.8 or _excluded(p, 0.6):
			return
		var s := _rng.randf_range(0.7, 1.45)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
		var origin := _ground(x, z, 0.1)
		_add_instance("bush%d" % _rng.randi_range(0, 2), Transform3D(basis, origin), _tint(0.18))
		if s >= 0.85:
			_batch(_sight, p, Layers.FOLIAGE_SIGHT).add(_sphere(snappedf(0.8 * s, 0.05)), Transform3D(Basis.IDENTITY, origin + Vector3.UP * 0.6 * s)))


## Half-extent that covers the whole walled kingdom.
func _clutter_half() -> float:
	var half := _world.layout.playable_half + 8.0
	for p in _td.wall_points:
		half = maxf(half, maxf(absf(p.x), absf(p.y)))
	return minf(half, _world.layout.half_size - 2.0)


func _scatter_clutter() -> void:
	var half := _clutter_half()
	var wl := _world.water_level
	# Ferns under the canopy
	_jittered_cells(2.8, half, func(x: float, z: float) -> void:
		var u := _rng.randf()
		if u > 0.6:
			return
		if not _inside(x, z):
			return
		var f := _td.sample(_td.forest, x, z)
		if u > f * 0.6:
			return
		if _td.sample(_td.trail_dist, x, z) < 0.3 or _td.is_hole_at(x, z):
			return
		var s := _rng.randf_range(0.7, 1.35)
		_add_instance("fern", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), _ground(x, z, 0.05)), _tint(0.2)))
	# Pebbles and small stones on the forest floor and along trails
	_jittered_cells(3.4, half, func(x: float, z: float) -> void:
		var f := _td.sample(_td.forest, x, z)
		if _rng.randf() > 0.12 + f * 0.4:
			return
		if _td.height_at(x, z) < wl + 0.3 or _td.is_hole_at(x, z):
			return
		var s := _rng.randf_range(0.07, 0.22)
		var b := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.4, 0.4))
		_add_instance("pebble", Transform3D(b.scaled(Vector3.ONE * s), _ground(x, z, 0.04 * s)), _tint(0.15)))
	# Grass fields in open ground: sweeping golden-sage drifts with height variation.
	var drift_noise := FastNoiseLite.new()
	drift_noise.seed = GameState.world_seed + 713
	drift_noise.frequency = 0.022
	var gold_noise := FastNoiseLite.new()
	gold_noise.seed = GameState.world_seed + 719
	gold_noise.frequency = 0.015
	_jittered_cells(1.65, half, func(x: float, z: float) -> void:
		var drift := smoothstep(-0.25, 0.45, drift_noise.get_noise_2d(x, z))
		var f := _td.sample(_td.forest, x, z)
		var chance := (1.0 - f * 0.9) * lerpf(0.14, 0.72, drift)
		if _rng.randf() > chance:
			return
		if not _inside(x, z):
			return
		var h := _td.height_at(x, z)
		if h < wl + 0.35 or h > 46.0 or _td.sample(_td.trail_dist, x, z) < 0.35 or _td.sample(_td.paving, x, z) > 0.28:
			return
		if _td.normal_at(x, z).y < 0.80 or _td.is_hole_at(x, z):
			return
		var gold_w := smoothstep(-0.15, 0.45, gold_noise.get_noise_2d(x, z))
		var is_tall := drift > 0.45 and _rng.randf() < (0.36 * drift)
		var s := _rng.randf_range(0.85, 1.45) if is_tall else _rng.randf_range(0.75, 1.35)
		var base_col := Color(0.84, 0.96, 0.74).lerp(Color(1.16, 0.98, 0.58), gold_w) * _rng.randf_range(0.88, 1.12)
		_add_instance("grass_tall" if is_tall else "grass", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), _ground(x, z, 0.04)), base_col))
	# Reeds along the waterline
	_jittered_cells(2.2, half, func(x: float, z: float) -> void:
		if _td.sample(_td.water_influence, x, z) <= 0.0:
			return
		var h := _td.height_at(x, z)
		if h < wl - 0.5 or h > wl + 0.5 or _rng.randf() > 0.55:
			return
		if _td.sample(_td.trail_dist, x, z) < 0.5 or _excluded(Vector2(x, z), 0.0):
			return
		var s := _rng.randf_range(0.8, 1.3)
		_add_instance("reeds", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), _ground(x, z, 0.05)), _tint(0.15)))
	# Glowing mushrooms deep in the forest
	_jittered_cells(7.0, half, func(x: float, z: float) -> void:
		var u := _rng.randf()
		if u > 0.14:
			return
		var f := _td.sample(_td.forest, x, z)
		if f < 0.5 or u > f * 0.14:
			return
		if _td.sample(_td.trail_dist, x, z) < 0.6:
			return
		_add_instance("mushrooms", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), _ground(x, z, 0.02)), Color(1, 1, 1)))


## Riverbank and lake-shore planting: rushes at the waterline, flowers in drifts
## (one species dominates each patch), moss, pebbles and the odd fallen branch.
## Lushness follows a low-frequency noise so some banks are bare and others full.
func _scatter_riverbank() -> void:
	var half := _world.layout.playable_half + 8.0
	var wl := _world.water_level
	var lush := FastNoiseLite.new()
	lush.seed = GameState.world_seed + 401
	lush.frequency = 0.03
	var kind := FastNoiseLite.new()
	kind.seed = GameState.world_seed + 402
	kind.frequency = 0.07
	_jittered_cells(1.0, half, func(x: float, z: float) -> void:
		var wi := _td.sample(_td.water_influence, x, z)
		if wi <= 0.04:
			return
		var above := _td.height_at(x, z) - wl
		if above < 0.1 or above > 3.4:
			return
		if _td.normal_at(x, z).y < 0.84 or _td.is_hole_at(x, z):
			return
		if _td.sample(_td.trail_dist, x, z) < 0.7 or _excluded(Vector2(x, z), 0.3):
			return
		var l := smoothstep(0.32, 0.62, lush.get_noise_2d(x, z) * 0.5 + 0.5)
		if _rng.randf() > l * (0.35 + 0.65 * wi):
			if above < 0.6 and _rng.randf() < 0.08:
				_add_instance("pebble", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.08, 0.2)), _ground(x, z, 0.02)), _tint(0.15))
			return
		# FastNoiseLite rarely leaves -0.5..0.5, so spread it over 0..1 for the species bands.
		var k := clampf(kind.get_noise_2d(x, z) * 0.9 + 0.5, 0.0, 1.0)
		var prop := "grass"
		if above < 0.65 and _rng.randf() < 0.45:
			prop = "rush"
		elif above < 1.3 and k > 0.66:
			prop = "flower3"
		elif k < 0.3:
			prop = "flower1"
		elif k < 0.46:
			prop = "flower0"
		elif k < 0.6:
			prop = "flower2" if _rng.randf() < 0.85 else "flower4"
		elif _rng.randf() < 0.45:
			prop = "flower0" if _rng.randf() < 0.7 else "flower4"
		var s := _rng.randf_range(0.75, 1.3)
		_add_instance(prop, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), _ground(x, z, 0.03)), _tint(0.12))
		var r := _rng.randf()
		if r < 0.05 and above < 1.0:
			_add_instance("mosspatch", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.7, 1.3)), _ground(x + 0.4, z + 0.3, 0.02)), _tint(0.15))
		elif r < 0.065:
			_add_instance("branch", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), _ground(x - 0.5, z, 0.03)), _tint(0.1)))


## Flower drifts requested by site builders (village gardens, story spots).
func _scatter_flower_patches() -> void:
	var sites := _world.get_node_or_null("Sites/Structures")
	if not sites or not "flower_patches" in sites:
		return
	for patch in sites.flower_patches:
		var c: Vector2 = patch[0]
		var radius: float = patch[1]
		var kind: String = patch[2]
		var n := int(radius * radius * (2.2 if kind == "white" else (14.0 if kind.begins_with("memorial:") else 1.2)))
		for i in n:
			var a := _rng.randf() * TAU
			var d := radius * sqrt(_rng.randf()) * _rng.randf_range(0.6, 1.0)
			var p := c + Vector2(cos(a), sin(a)) * d
			if _td.height_at(p.x, p.y) < _world.water_level + 0.08 or _td.sample(_td.trail_dist, p.x, p.y) < 0.5:
				continue
			var prop := "flower0"
			if kind == "garden":
				prop = ["flower2", "flower4", "flower1", "flower0", "flower2"][_rng.randi_range(0, 4)]
			elif kind.begins_with("memorial:"):
				# Restrained memorial palette: white, muted red, pale yellow and purple,
				# one leading each cluster with a few of the others mixed in.
				var lead := "flower" + kind.substr(9)
				prop = lead if _rng.randf() < 0.72 else ["flower0", "flower4", "flower2", "flower3"][_rng.randi_range(0, 3)]
			elif _rng.randf() < 0.2:
				prop = "rush"
			var s := _rng.randf_range(0.8, 1.25)
			_add_instance(prop, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), _ground(p.x, p.y, 0.03)), _tint(0.1))


func _emit_multimeshes() -> void:
	for key in _instances:
		var parts: PackedStringArray = key.split("|")
		var prop := parts[0]
		var list: Array = _instances[key]
		var r: Array = RENDER.get(prop, [200.0, true])
		if r.size() > 2:
			_emit(key, prop, list, 0.0, r[0], r[1])
			_emit(key + "|far", prop + "_far", list, r[0] - 6.0, r[2], false)
		else:
			_emit(key, prop, list, 0.0, r[0], r[1])


func _emit(key: String, mesh_name: String, list: Array, begin: float, end: float, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PropMeshes.get_mesh(mesh_name)
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i][0])
		mm.set_instance_color(i, list[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = key.replace("|", "_")
	mmi.multimesh = mm
	mmi.visibility_range_begin = begin
	mmi.visibility_range_begin_margin = 6.0 if begin > 0.0 else 0.0
	mmi.visibility_range_end = end
	mmi.visibility_range_end_margin = 6.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
