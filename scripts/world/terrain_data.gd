class_name TerrainData
extends RefCounted
## Builds the heightfield and painting masks from a WorldLayout.
##
## Pure data: no nodes are created here, so it can be generated and inspected
## in tests. Terrain.gd turns it into meshes and collision.
##
## Grid: n x n vertices from -half_size to +half_size with `cell` spacing.
## Each cell is split along the (i,j)->(i+1,j+1) diagonal; height_at() uses the
## same split so queries match the rendered and collision surface exactly.

var layout: WorldLayout
var n: int
var cell: float
var origin: float
var water_level: float

var heights := PackedFloat32Array()
var trail_dist := PackedFloat32Array()  ## Metres beyond the trail edge (<0 = on trail).
var forest := PackedFloat32Array()      ## Final tree density 0..1 after exclusions.
var wet := PackedFloat32Array()
var paving := PackedFloat32Array()
var water_influence := PackedFloat32Array()  ## 1 near rivers/lake shores.
var holes := PackedByteArray()          ## Per cell; 1 = no terrain (cave mouths).

var site_heights := {}   ## site name -> flattened ground height
var step_ms := {}        ## generation step -> milliseconds (for profiling)
var cave := {}           ## Parsed cave grid, see _parse_cave()

var _nb := FastNoiseLite.new()
var _nd := FastNoiseLite.new()
var _nr := FastNoiseLite.new()
var _ns := FastNoiseLite.new()
var _nf := FastNoiseLite.new()
var _tmp_dist := PackedFloat32Array()


func generate(p_layout: WorldLayout, seed_value: int) -> void:
	layout = p_layout
	cell = layout.cell
	origin = -layout.half_size
	water_level = layout.water_level
	n = int(round(layout.half_size * 2.0 / cell)) + 1
	_setup_noise(seed_value)
	var count := n * n
	heights.resize(count)
	trail_dist.resize(count)
	trail_dist.fill(1e6)
	forest.resize(count)
	wet.resize(count)
	wet.fill(0.0)
	paving.resize(count)
	paving.fill(0.0)
	water_influence.resize(count)
	water_influence.fill(0.0)
	holes.resize((n - 1) * (n - 1))
	holes.fill(0)

	for step in [_stamp_trails, _base_heights, _smooth_trails, _flatten_sites, _flatten_bridge_ends,
			_carve_water, _protect_trails, _parse_cave, _shape_cave, _paint_forest]:
		var t0 := Time.get_ticks_usec()
		step.call()
		step_ms[step.get_method()] = (Time.get_ticks_usec() - t0) / 1000


# --- Queries ---------------------------------------------------------------

func idx(i: int, j: int) -> int:
	return j * n + i


func vx(i: int) -> float:
	return origin + i * cell


func height_at(x: float, z: float) -> float:
	var fx := (x - origin) / cell
	var fz := (z - origin) / cell
	var i := clampi(int(floor(fx)), 0, n - 2)
	var j := clampi(int(floor(fz)), 0, n - 2)
	var u := clampf(fx - i, 0.0, 1.0)
	var v := clampf(fz - j, 0.0, 1.0)
	var h00 := heights[idx(i, j)]
	var h10 := heights[idx(i + 1, j)]
	var h01 := heights[idx(i, j + 1)]
	var h11 := heights[idx(i + 1, j + 1)]
	if u >= v:
		return h00 + (h10 - h00) * u + (h11 - h10) * v
	return h00 + (h01 - h00) * v + (h11 - h01) * u


func normal_at(x: float, z: float) -> Vector3:
	var e := cell * 0.5
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var i := clampi(int(round((x - origin) / cell)), 0, n - 1)
	var j := clampi(int(round((z - origin) / cell)), 0, n - 1)
	return arr[idx(i, j)]


func is_hole_at(x: float, z: float) -> bool:
	var i := clampi(int(floor((x - origin) / cell)), 0, n - 2)
	var j := clampi(int(floor((z - origin) / cell)), 0, n - 2)
	return holes[j * (n - 1) + i] == 1


func is_water_at(x: float, z: float) -> bool:
	return height_at(x, z) < water_level + 0.05


func in_playable(x: float, z: float, margin := 0.0) -> bool:
	return _edge_metric(x, z) < layout.playable_half - margin


func region_name(x: float, z: float) -> String:
	var best := String(layout.data.get("default_region", "Wilds"))
	var best_score := 1.0
	for r in layout.list("regions"):
		var d := Vector2(x, z).distance_to(WorldLayout.v2(r["center"])) / float(r["radius"])
		if d < best_score:
			best_score = d
			best = r["name"]
	return best


# --- Generation ------------------------------------------------------------

func _setup_noise(s: int) -> void:
	_nb.seed = s
	_nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_nb.frequency = 1.0 / 210.0
	_nb.fractal_type = FastNoiseLite.FRACTAL_FBM
	_nb.fractal_octaves = 4
	_nd.seed = s + 11
	_nd.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_nd.frequency = 1.0 / 30.0
	_nd.fractal_octaves = 3
	_nr.seed = s + 23
	_nr.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_nr.frequency = 1.0 / 48.0
	_nr.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_nr.fractal_octaves = 4
	_ns.seed = s + 37
	_ns.frequency = 1.0 / 40.0
	_nf.seed = s + 51
	_nf.frequency = 1.0 / 65.0
	_nf.fractal_octaves = 3


func _edge_metric(x: float, z: float) -> float:
	var ax := absf(x)
	var az := absf(z)
	return pow(pow(ax, 6.0) + pow(az, 6.0), 1.0 / 6.0)


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	var l2 := ab.length_squared()
	if l2 > 0.0:
		t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Calls fn(k, x, z) for every vertex within the bounding box of a..b grown by r.
func _for_vertices_near_segment(a: Vector2, b: Vector2, r: float, fn: Callable) -> void:
	var i0 := clampi(int(floor((minf(a.x, b.x) - r - origin) / cell)), 0, n - 1)
	var i1 := clampi(int(ceil((maxf(a.x, b.x) + r - origin) / cell)), 0, n - 1)
	var j0 := clampi(int(floor((minf(a.y, b.y) - r - origin) / cell)), 0, n - 1)
	var j1 := clampi(int(ceil((maxf(a.y, b.y) + r - origin) / cell)), 0, n - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			fn.call(idx(i, j), vx(i), vx(j))


func _stamp_trails() -> void:
	for t in layout.list("trails"):
		var pts := WorldLayout.points(t["points"])
		var hw := float(t["half_width"])
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			_for_vertices_near_segment(a, b, hw + 8.0, func(k: int, x: float, z: float) -> void:
				var d := seg_dist(Vector2(x, z), a, b) - hw
				if d < trail_dist[k]:
					trail_dist[k] = d)


func _base_heights() -> void:
	var base := layout.base_height
	var hills := layout.list("hills")
	var ridges := layout.list("ridges")
	var ph := layout.playable_half
	var span := layout.half_size - ph
	for j in n:
		var z := vx(j)
		for i in n:
			var x := vx(i)
			var k := idx(i, j)
			var on_trail := 1.0 - smoothstep(0.0, 6.0, trail_dist[k])
			var h := base + _nb.get_noise_2d(x, z) * 4.5
			h += _nd.get_noise_2d(x, z) * 1.3 * (1.0 - 0.85 * on_trail)
			var ridged := (_nr.get_noise_2d(x, z) + 1.0) * 0.5
			for hill in hills:
				var c := WorldLayout.v2(hill["center"])
				var r := float(hill["radius"])
				var dx := x - c.x
				var dz := z - c.y
				var d2 := dx * dx + dz * dz
				if d2 < r * r:
					var f := 1.0 - d2 / (r * r)
					f *= f
					var rocky := float(hill["rocky"]) * (1.0 - on_trail)
					h += float(hill["height"]) * f * (1.0 + rocky * (ridged - 0.5) * 0.6)
			for ridge in ridges:
				var r := float(ridge["radius"])
				var d := seg_dist(Vector2(x, z), WorldLayout.v2(ridge["a"]), WorldLayout.v2(ridge["b"]))
				if d < r:
					var f := 1.0 - (d * d) / (r * r)
					f *= f
					var rocky := float(ridge["rocky"]) * (1.0 - on_trail)
					h += float(ridge["height"]) * f * (1.0 + rocky * (ridged - 0.4) * 0.8)
			var e := _edge_metric(x, z)
			if e > ph:
				var t := clampf((e - ph) / span, 0.0, 1.0)
				h += 85.0 * pow(t, 2.2) + ridged * 26.0 * t
			heights[k] = maxf(h, 1.2)


## Blends trail vertices toward a local average so trails stay walkable even
## where they climb rocky hills.
func _smooth_trails() -> void:
	var src := heights.duplicate()
	var r := 3
	for j in range(r, n - r):
		for i in range(r, n - r):
			var k := idx(i, j)
			if trail_dist[k] > 5.0:
				continue
			var sum := 0.0
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					sum += src[idx(i + di, j + dj)]
			var avg := sum / float((2 * r + 1) * (2 * r + 1))
			heights[k] = lerpf(src[k], avg, 0.85 * (1.0 - smoothstep(0.0, 5.0, trail_dist[k])))


func _flatten_circle(center: Vector2, radius: float, blend: float, target: float, paving_amount := 0.0) -> void:
	var r_out := radius + blend
	_for_vertices_near_segment(center, center, r_out, func(k: int, x: float, z: float) -> void:
		var d := Vector2(x, z).distance_to(center)
		if d >= r_out:
			return
		var w := 1.0 - smoothstep(radius, r_out, d)
		heights[k] = lerpf(heights[k], target, w)
		if paving_amount > 0.0:
			paving[k] = maxf(paving[k], paving_amount * (1.0 - smoothstep(radius * 0.7, radius * 0.98, d))))


func _flatten_sites() -> void:
	const PAVED := {"citadel": 1.0, "castle": 1.0, "chapel": 0.9, "landmark": 0.0, "watchtower": 0.6, "hut": 0.0, "camp": 0.0, "summit": 0.0}
	for s in layout.list("sites"):
		var c := WorldLayout.v2(s["center"])
		var r := float(s["radius"])
		if r <= 0.0:
			continue
		var target := _avg_height(c, r * 0.6) + float(s.get("height_offset", 0.0))
		site_heights[s["name"]] = target
		_flatten_circle(c, r, float(s["blend"]), target, PAVED.get(s["type"], 0.0))


func _flatten_bridge_ends() -> void:
	for b in layout.list("bridges"):
		for key in ["a", "b"]:
			var p := WorldLayout.v2(b[key])
			_flatten_circle(p, 3.5, 5.0, maxf(_avg_height(p, 3.0), water_level + 1.6))


func _avg_height(c: Vector2, r: float) -> float:
	var sum := 0.0
	var cnt := 0
	for dz in [-r, 0.0, r]:
		for dx in [-r, 0.0, r]:
			sum += height_at(c.x + dx, c.y + dz)
			cnt += 1
	return sum / cnt


func _carve_water() -> void:
	var wl := water_level
	var fords := layout.list("fords")
	# Rivers
	for river in layout.list("rivers"):
		var pts := WorldLayout.points(river["points"])
		var hw := float(river["half_width"])
		var depth := float(river["depth"])
		var bank := float(river["bank"])
		_tmp_dist.resize(n * n)
		_tmp_dist.fill(1e6)
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			_for_vertices_near_segment(a, b, hw + bank, func(k: int, x: float, z: float) -> void:
				var d := seg_dist(Vector2(x, z), a, b)
				if d < _tmp_dist[k]:
					_tmp_dist[k] = d)
		for k in n * n:
			var d := _tmp_dist[k]
			if d >= hw + bank:
				continue
			var x := vx(k % n)
			var z := vx(k / n)
			var dep := depth
			for f in fords:
				var fd := Vector2(x, z).distance_to(WorldLayout.v2(f["center"]))
				var fr := float(f["radius"])
				if fd < fr * 1.6:
					dep = lerpf(float(f["depth"]), dep, smoothstep(fr * 0.6, fr * 1.6, fd))
			var target: float
			if d < hw:
				target = wl - 0.35 - (dep - 0.35) * (1.0 - (d * d) / (hw * hw))
				target = minf(target, wl - minf(dep, 0.35))
			else:
				var t := smoothstep(hw, hw + bank, d)
				target = lerpf(wl - minf(dep, 0.35), heights[k], t)
			heights[k] = minf(heights[k], target)
			water_influence[k] = maxf(water_influence[k], 1.0 - smoothstep(hw, hw + bank, d))
			wet[k] = maxf(wet[k], 1.0 - smoothstep(hw - 1.0, hw + bank * 0.5, d))

	# Lake
	var lake := layout.dict("lake")
	if not lake.is_empty():
		var c := WorldLayout.v2(lake["center"])
		var radii := WorldLayout.v2(lake["radii"])
		var depth := float(lake["depth"])
		var sw := float(lake["shore"]) / minf(radii.x, radii.y)
		var reach := maxf(radii.x, radii.y) * (1.0 + sw) * 1.15
		_for_vertices_near_segment(c, c, reach, func(k: int, x: float, z: float) -> void:
			var q := pow((x - c.x) / radii.x, 2.0) + pow((z - c.y) / radii.y, 2.0)
			var dn := sqrt(q) * (1.0 + _ns.get_noise_2d(x, z) * 0.12)
			if dn >= 1.0 + sw:
				return
			var target: float
			if dn < 1.0:
				target = wl - 0.35 - (depth - 0.35) * smoothstep(1.0, 0.55, dn)
			else:
				target = lerpf(wl - 0.35, heights[k], smoothstep(1.0, 1.0 + sw, dn))
			heights[k] = minf(heights[k], target)
			water_influence[k] = maxf(water_influence[k], 1.0 - smoothstep(1.0, 1.0 + sw, dn))
			wet[k] = maxf(wet[k], 1.0 - smoothstep(0.98, 1.0 + sw * 0.5, dn)))
		var isl: Dictionary = lake.get("island", {})
		if not isl.is_empty():
			var ic := WorldLayout.v2(isl["center"])
			var ir := float(isl["radius"])
			var ih := float(isl["height"])
			_for_vertices_near_segment(ic, ic, ir, func(k: int, x: float, z: float) -> void:
				var d := Vector2(x, z).distance_to(ic)
				var t := smoothstep(ir * 0.45, ir, d)
				var profile := lerpf(wl + ih, wl - 0.8, t) + _nd.get_noise_2d(x, z) * 0.3 * (1.0 - t)
				heights[k] = maxf(heights[k], profile)
				wet[k] = maxf(wet[k], smoothstep(ir * 0.55, ir * 0.85, d)))

	# Shallows (wading causeways)
	for sh in layout.list("shallows"):
		var a := WorldLayout.v2(sh["a"])
		var b := WorldLayout.v2(sh["b"])
		var hw := float(sh["half_width"])
		var floor_h := wl - float(sh["depth"])
		_for_vertices_near_segment(a, b, hw + 3.0, func(k: int, x: float, z: float) -> void:
			var d := seg_dist(Vector2(x, z), a, b)
			var t := smoothstep(hw, hw + 3.0, d)
			heights[k] = maxf(heights[k], lerpf(floor_h + _nd.get_noise_2d(x, z) * 0.08, heights[k], t)))


## Trails stay dry except where they deliberately cross water at a ford or causeway.
func _protect_trails() -> void:
	var crossings: Array = []
	for f in layout.list("fords"):
		crossings.append([WorldLayout.v2(f["center"]), float(f["radius"]) * 1.7])
	for sh in layout.list("shallows"):
		crossings.append([WorldLayout.v2(sh["a"]), 8.0])
		crossings.append([WorldLayout.v2(sh["b"]), 8.0])
		crossings.append([(WorldLayout.v2(sh["a"]) + WorldLayout.v2(sh["b"])) * 0.5, 30.0])
	for k in n * n:
		if trail_dist[k] > 1.0 or heights[k] > water_level + 0.5:
			continue
		var p := Vector2(vx(k % n), vx(k / n))
		var crossing := false
		for c in crossings:
			if p.distance_to(c[0]) < c[1]:
				crossing = true
				break
		if not crossing:
			heights[k] = maxf(heights[k], water_level + 0.5 - maxf(trail_dist[k], 0.0) * 0.4)


func _parse_cave() -> void:
	var cd := layout.dict("cave")
	if cd.is_empty():
		return
	var rows: Array = cd["map"]
	var cs := float(cd["cell"])
	var o := WorldLayout.v2(cd["origin"])
	var cells := {}
	var covered: Array[Rect2] = []
	var exits: Array = []  # [Rect2 apron, Vector2 outward dir]
	var nrows := rows.size()
	var ncols := String(rows[0]).length()
	for r in nrows:
		var row := String(rows[r])
		for c in ncols:
			var ch := row[c]
			if ch == ".":
				continue
			cells[Vector2i(c, r)] = ch
			var rect := Rect2(o.x + c * cs, o.y + r * cs, cs, cs)
			covered.append(rect)
			if ch != "m":
				continue
			if r == nrows - 1:
				exits.append([Rect2(rect.position.x - 2.0, rect.end.y, cs + 4.0, 10.0), Vector2(0, 1)])
			elif r == 0:
				exits.append([Rect2(rect.position.x - 2.0, rect.position.y - 10.0, cs + 4.0, 10.0), Vector2(0, -1)])
			elif c == 0:
				exits.append([Rect2(rect.position.x - 10.0, rect.position.y - 2.0, 10.0, cs + 4.0), Vector2(-1, 0)])
			elif c == ncols - 1:
				exits.append([Rect2(rect.end.x, rect.position.y - 2.0, 10.0, cs + 4.0), Vector2(1, 0)])
	cave = {
		"name": cd["name"], "origin": o, "cell": cs, "rows": nrows, "cols": ncols,
		"floor": float(cd["floor_height"]), "dome_height": float(cd["dome_height"]),
		"dome_slope": float(cd["dome_slope"]), "ceiling": cd["ceiling"],
		"cells": cells, "covered": covered, "exits": exits,
		"rect": Rect2(o.x, o.y, ncols * cs, nrows * cs),
	}


static func _rect_dist(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dz := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return sqrt(dx * dx + dz * dz)


func _shape_cave() -> void:
	if cave.is_empty():
		return
	var floor_h: float = cave["floor"]
	var grid_rect: Rect2 = cave["rect"]
	# 1. Raise a dome over every open cell so the roof is solid terrain.
	var covered: Array = cave["covered"]
	var dome_h: float = cave["dome_height"]
	var slope: float = cave["dome_slope"]
	var reach := dome_h / slope + 3.0
	var gc := grid_rect.get_center()
	_for_vertices_near_segment(gc, gc, maxf(grid_rect.size.x, grid_rect.size.y) * 0.5 + reach, func(k: int, x: float, z: float) -> void:
		var p := Vector2(x, z)
		var d := 1e6
		for rect in covered:
			d = minf(d, _rect_dist(p, rect))
		if d > reach:
			return
		var dome := floor_h + dome_h - maxf(0.0, d - 1.0) * slope
		if d < 1.0:
			dome += absf(_nd.get_noise_2d(x, z)) * 2.0
		heights[k] = maxf(heights[k], dome))
	# 2. Cut a level notch into the hillside in front of each mouth.
	for ex in cave["exits"]:
		var apron: Rect2 = ex[0]
		var dir: Vector2 = ex[1]
		var c := apron.get_center()
		_for_vertices_near_segment(c, c, maxf(apron.size.x, apron.size.y) * 0.5 + 12.0, func(k: int, x: float, z: float) -> void:
			var p := Vector2(x, z)
			if grid_rect.grow(-0.01).has_point(p):
				return
			# Only blend on the outward side of the exit edge.
			var edge := c - dir * (apron.size.y if dir.y != 0.0 else apron.size.x) * 0.5
			if (p - edge).dot(dir) < -0.01:
				return
			var w := 1.0 - smoothstep(0.0, 10.0, _rect_dist(p, apron))
			heights[k] = lerpf(heights[k], floor_h, w))
	# 3. Cut holes wherever terrain would intrude into an open cell.
	var o: Vector2 = cave["origin"]
	var cs: float = cave["cell"]
	var per := int(round(cs / cell))
	for key: Vector2i in cave["cells"]:
		var ch: String = cave["cells"][key]
		var limit := floor_h + float(cave["ceiling"][ch]) + 1.0
		var ci := int(round((o.x - origin) / cell)) + key.x * per
		var cj := int(round((o.y - origin) / cell)) + key.y * per
		for dj in per:
			for di in per:
				var i := ci + di
				var j := cj + dj
				var lo := minf(minf(heights[idx(i, j)], heights[idx(i + 1, j)]),
						minf(heights[idx(i, j + 1)], heights[idx(i + 1, j + 1)]))
				if lo < limit:
					holes[j * (n - 1) + i] = 1


func _paint_forest() -> void:
	var base := float(layout.data.get("base_forest_density", 0.2))
	forest.fill(base)
	# Zones raise density inside their radius (max-combined).
	for zone in layout.list("forest_zones"):
		var c := WorldLayout.v2(zone["center"])
		var r := float(zone["radius"])
		var dens := float(zone["density"])
		_for_vertices_near_segment(c, c, r, func(k: int, x: float, z: float) -> void:
			var dist := Vector2(x, z).distance_to(c)
			if dist < r:
				forest[k] = maxf(forest[k], dens * (1.0 - smoothstep(r * 0.55, r, dist))))
	# Clearings and sites carve density out (multiplicative).
	var cutouts: Array = []
	for cl in layout.list("clearings"):
		cutouts.append([WorldLayout.v2(cl["center"]), float(cl["radius"]), 8.0])
	for s in layout.list("sites"):
		cutouts.append([WorldLayout.v2(s["center"]), float(s["radius"]) + 4.0, 6.0])
	for cut in cutouts:
		var c: Vector2 = cut[0]
		var r: float = cut[1]
		var fade: float = cut[2]
		_for_vertices_near_segment(c, c, r + fade, func(k: int, x: float, z: float) -> void:
			var dist := Vector2(x, z).distance_to(c)
			if dist < r + fade:
				forest[k] = forest[k] * smoothstep(r, r + fade, dist))
	var wl := water_level
	for j in n:
		var z := vx(j)
		for i in n:
			var k := idx(i, j)
			var d := forest[k]
			if d <= 0.0:
				continue
			d *= clampf(0.5 + _nf.get_noise_2d(vx(i), z) * 1.1, 0.0, 1.25)
			d *= smoothstep(0.0, 4.0, trail_dist[k])
			var h := heights[k]
			d *= smoothstep(wl + 0.6, wl + 1.6, h)
			d *= 1.0 - smoothstep(42.0, 55.0, h)
			forest[k] = clampf(d, 0.0, 1.0)
	if not cave.is_empty():
		var rect: Rect2 = cave["rect"].grow(6.0)
		var cc := rect.get_center()
		_for_vertices_near_segment(cc, cc, maxf(rect.size.x, rect.size.y) * 0.5, func(k: int, x: float, z: float) -> void:
			if rect.has_point(Vector2(x, z)):
				forest[k] = forest[k] * 0.15)
