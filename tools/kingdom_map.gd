extends SceneTree
## Renders a top-down planning/validation map of the kingdom layout to PNG,
## straight from TerrainData and the layout (no renderer, no scene).
##   godot --headless --path . -s res://tools/kingdom_map.gd -- --out=C:/temp/map.png
##   [--seed=1337] [--region=x0,z0,x1,z1] [--ppm=2]   (pixels per metre)
## Colours: terrain shaded by height and slope, water blue, roads/trails tan,
## paving grey, forest density darker green. Overlays: 50 m grid (100 m darker),
## kingdom wall and gate, landmark exclusion zones (orange), mission areas
## (red = fighting space, magenta = spy patrol routes), cemetery (white),
## houses (black outlines, from KingdomPlan) and existing site circles (yellow).

var img: Image
var x0 := -340.0
var z0 := -340.0
var x1 := 340.0
var z1 := 340.0
var ppm := 2.0


func _initialize() -> void:
	var out := "user://kingdom_map.png"
	var seed_value := 1337
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		elif arg.begins_with("--ppm="):
			ppm = float(arg.substr(6))
		elif arg.begins_with("--region="):
			var p := arg.substr(9).split(",")
			x0 = float(p[0]); z0 = float(p[1]); x1 = float(p[2]); z1 = float(p[3])
	var layout := WorldLayout.load_default()
	var td := TerrainData.new()
	var t := Time.get_ticks_msec()
	td.generate(layout, seed_value)
	print("terrain %d ms  steps %s" % [Time.get_ticks_msec() - t, td.step_ms])
	var plan := KingdomPlan.new()
	t = Time.get_ticks_msec()
	plan.compute(layout, td)
	print("plan %d ms: %d houses, %d stalls, %d rejected" % [Time.get_ticks_msec() - t, plan.houses.size(), plan.stalls.size(), plan.rejected.size()])
	print("reject reasons: ", plan.reject_counts)
	if OS.get_cmdline_user_args().has("--verbose"):
		for r in plan.rejected:
			print("  rejected ", r)
	var by_district := {}
	for hs in plan.houses:
		by_district[hs["district"]] = by_district.get(hs["district"], 0) + 1
	print("houses by district: ", by_district)
	print("wall pieces %d, towers %d, water gates %d, wall ref ground %.1f" % [plan.wall_pieces.size(), plan.towers.size(), plan.water_gates.size(), plan.wall_ref_ground])
	print("cemetery gates ", plan.fence_gates, " graves ", plan.graves.size())
	for sp in plan.spy_points:
		if not sp["ok"]:
			print("  spy point ", sp["pos"], " INVALID: ", sp["reason"])
	for s in ["Lakeside Castle", "Castle Square", "Ashford", "Elder Tree", "Great Gate Field", "Old Citadel"]:
		print("site height %s: %.2f" % [s, td.site_heights.get(s, -99.0)])
	var w := int((x1 - x0) * ppm)
	var h := int((z1 - z0) * ppm)
	img = Image.create(w, h, false, Image.FORMAT_RGB8)
	for py in h:
		for px in w:
			var x := x0 + (px + 0.5) / ppm
			var z := z0 + (py + 0.5) / ppm
			img.set_pixel(px, py, _ground_color(td, x, z))
	# Grid
	for gx in range(int(ceil(x0 / 50.0)) * 50, int(x1) + 1, 50):
		_line(Vector2(gx, z0), Vector2(gx, z1), Color(0, 0, 0, 0.35 if gx % 100 == 0 else 0.15))
	for gz in range(int(ceil(z0 / 50.0)) * 50, int(z1) + 1, 50):
		_line(Vector2(x0, gz), Vector2(x1, gz), Color(0, 0, 0, 0.35 if gz % 100 == 0 else 0.15))
	_line(Vector2(0, z0), Vector2(0, z1), Color(0, 0, 0, 0.6))
	_line(Vector2(x0, 0), Vector2(x1, 0), Color(0, 0, 0, 0.6))
	for s in layout.list("sites"):
		_circle(WorldLayout.v2(s["center"]), maxf(float(s["radius"]), 3.0), Color(1, 0.9, 0.1, 0.9))
	var k := layout.dict("kingdom")
	for z in plan.zones:
		_zone(z, Color(1, 0.55, 0.0, 0.9))
	for z in plan.fight_zones:
		_zone(z, Color(0.95, 0.1, 0.1, 1.0))
		_zone(z, Color(0.95, 0.1, 0.1, 1.0), -0.6)
	for m in k.get("missions", []):
		for route in m.get("routes", []):
			var pts := WorldLayout.points(route)
			for i in pts.size() - 1:
				_line(pts[i], pts[i + 1], Color(0.9, 0.1, 0.9, 1.0))
		for p in m.get("spawn_points", []):
			_disc(WorldLayout.v2(p), 1.5, Color(0.9, 0.1, 0.9))
	if not k.is_empty():
		var cem: Dictionary = k.get("cemetery", {})
		if not cem.is_empty():
			_circle(WorldLayout.v2(cem["center"]), float(cem["fence_radius"]), Color(1, 1, 1, 1))
		for piece in plan.wall_pieces:
			_thick_line(piece["a"], piece["b"], float(k["wall"]["thickness"]), Color(0.15, 0.12, 0.1) if piece["kind"] == "wall" else Color(0.2, 0.5, 0.9))
		for ext in plan.barrier_extensions:
			_line(ext[0], ext[1], Color(0.6, 0.0, 0.6))
		for tw in plan.towers:
			_disc(tw, 3.5, Color(0.25, 0.2, 0.18))
		_disc(plan.gate_center, 6.0, Color(0.8, 0.0, 0.0))
	for hs in plan.houses:
		_rect(hs["center"], hs["yaw"], hs["w"], hs["d"], Color(0.05, 0.05, 0.05))
	for st in plan.stalls:
		_rect(st["center"], st["yaw"], st["w"], st["d"], Color(0.55, 0.1, 0.45))
	for g in plan.graves:
		_disc(g["pos"], 0.6, Color(1, 1, 1))
	img.save_png(out)
	print("wrote ", out, " (", w, "x", h, ")")
	quit()


func _zone(z: Dictionary, col: Color, grow := 0.0) -> void:
	if z.has("half"):
		var c: Vector2 = z["center"]
		var h: Vector2 = z["half"] + Vector2(grow, grow)
		var pts := [c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)]
		for i in 4:
			_line(pts[i], pts[(i + 1) % 4], col)
	else:
		_circle(z["center"], float(z["radius"]) + grow, col)


func _ground_color(td: TerrainData, x: float, z: float) -> Color:
	var hgt := td.height_at(x, z)
	if hgt < td.water_level:
		return Color(0.15, 0.3, 0.55).lerp(Color(0.05, 0.12, 0.3), clampf(-hgt / 4.0, 0.0, 1.0))
	var n := td.normal_at(x, z)
	var shade := clampf(0.55 + 0.6 * n.dot(Vector3(-0.5, 0.8, -0.35).normalized()), 0.25, 1.15)
	var base := Color(0.42, 0.55, 0.3).lerp(Color(0.62, 0.6, 0.55), clampf((hgt - 14.0) / 40.0, 0.0, 1.0))
	if n.y < 0.83:
		base = Color(0.5, 0.48, 0.45)
	if hgt > 52.0:
		base = Color(0.9, 0.92, 0.95)
	var f := td.sample(td.forest, x, z)
	base = base.lerp(Color(0.12, 0.3, 0.12), clampf(f * 0.9, 0.0, 0.8))
	if td.sample(td.trail_dist, x, z) < 0.0:
		base = Color(0.6, 0.48, 0.32)
	var pav := td.sample(td.paving, x, z)
	if pav > 0.3:
		base = base.lerp(Color(0.6, 0.6, 0.6), pav * 0.8)
	if td.is_hole_at(x, z):
		base = Color(0, 0, 0)
	return Color(base.r * shade, base.g * shade, base.b * shade)


func _px(p: Vector2) -> Vector2i:
	return Vector2i(int((p.x - x0) * ppm), int((p.y - z0) * ppm))


func _plot(q: Vector2i, c: Color) -> void:
	if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
		return
	if c.a < 1.0:
		img.set_pixelv(q, img.get_pixelv(q).lerp(Color(c.r, c.g, c.b), c.a))
	else:
		img.set_pixelv(q, c)


func _line(a: Vector2, b: Vector2, c: Color) -> void:
	var n := int(a.distance_to(b) * ppm) + 1
	for i in n + 1:
		_plot(_px(a.lerp(b, float(i) / n)), c)


func _thick_line(a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var steps := int(width * ppm) + 1
	for s in steps + 1:
		var off := nrm * (-width * 0.5 + width * float(s) / steps)
		_line(a + off, b + off, c)


func _circle(c: Vector2, r: float, col: Color) -> void:
	var n := int(TAU * r * ppm) + 8
	for i in n:
		var a := TAU * i / n
		_plot(_px(c + Vector2(cos(a), sin(a)) * r), col)


func _disc(c: Vector2, r: float, col: Color) -> void:
	var rr := int(ceil(r * ppm))
	var q := _px(c)
	for dy in range(-rr, rr + 1):
		for dx in range(-rr, rr + 1):
			if dx * dx + dy * dy <= rr * rr:
				_plot(q + Vector2i(dx, dy), col)


func _rect(c: Vector2, yaw: float, w: float, d: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var corners: Array[Vector2] = []
	for s: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var v: Vector3 = b * Vector3(s.x * w, 0, s.y * d)
		corners.append(c + Vector2(v.x, v.z))
	for i in 4:
		_line(corners[i], corners[(i + 1) % 4], col)
	# Front face (door side, local -z) highlighted.
	_line(corners[0], corners[1], Color(0.9, 0.2, 0.1))
