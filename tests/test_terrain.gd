extends Node
## Terrain generation, collision agreement, water carving and cave holes.


func run(t) -> void:
	var w: World = t.world
	var td := w.terrain_data
	t.check(td.n == 341, "terrain grid is 341x341 vertices (680 m at 2 m)", str(td.n))
	t.check(w.timings.get("terrain_data", 99999) < 8000, "terrain data generates in under 8 s", "%d ms" % w.timings.get("terrain_data", -1))

	# Physics surface must match the height function used for placement.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	var misses := 0
	for i in 300:
		var x := rng.randf_range(-280, 280)
		var z := rng.randf_range(-280, 280)
		if td.is_hole_at(x, z) or td.cave.get("rect", Rect2()).grow(4).has_point(Vector2(x, z)):
			continue
		var hit := _terrain_only_ray(w, x, z)
		if hit.is_empty():
			misses += 1
			continue
		worst = maxf(worst, absf(hit.position.y - td.height_at(x, z)))
	t.check(misses == 0, "downward rays always hit terrain collision", "%d misses" % misses)
	t.check(worst < 0.05, "collision height matches height_at() within 5 cm", "worst %.3f m" % worst)

	# Water: lake centre and river centre are under water, deep enough to read as water.
	var lake: Dictionary = w.layout.dict("lake")
	var lc := WorldLayout.v2(lake["center"])
	t.check(td.height_at(lc.x - 30, lc.y) < w.water_level - 2.0, "lake bed is well below water level", "%.2f" % td.height_at(lc.x - 30, lc.y))
	t.check(td.height_at(100, -150) < w.water_level - 1.5, "north river is swimmable-deep at the bridge", "%.2f" % td.height_at(100, -150))
	for f in w.layout.list("fords"):
		var c := WorldLayout.v2(f["center"])
		var h := td.height_at(c.x, c.y)
		t.check(h < w.water_level and h > w.water_level - 0.8, "%s is shallow wadeable water" % f["name"], "%.2f" % h)
	var isl: Dictionary = lake["island"]
	var ic := WorldLayout.v2(isl["center"])
	t.check(td.height_at(ic.x, ic.y) > w.water_level + 1.5, "lake island rises above the water")

	# No dry land below water level outside the water features (would be an odd puddle).
	var low_dry := 0
	for j in range(0, td.n, 3):
		for i in range(0, td.n, 3):
			var k := td.idx(i, j)
			if td.heights[k] < w.water_level and td.water_influence[k] <= 0.0:
				low_dry += 1
	t.check(low_dry == 0, "no below-water terrain outside rivers/lake", "%d samples" % low_dry)

	# Cave mouths are open (holes) and the covered tunnel has a terrain roof.
	var holes := 0
	for b in td.holes:
		holes += b
	t.check(holes > 0, "cave mouths cut holes into the terrain", "%d cells" % holes)
	var cave := td.cave
	var floor_h: float = cave["floor"]
	var o: Vector2 = cave["origin"]
	var cs: float = cave["cell"]
	var chamber := o + Vector2(7.5, 8.5) * cs
	t.check(td.height_at(chamber.x, chamber.y) > floor_h + 7.0, "terrain roof sits above the cave chamber", "%.1f vs floor %.1f" % [td.height_at(chamber.x, chamber.y), floor_h])

	# Edge mountains form a natural barrier: steep, high ground near the map edge.
	var edge_h := td.height_at(0, -325)
	t.check(edge_h > 40.0, "north map edge is mountainous", "%.1f m" % edge_h)


func _terrain_only_ray(w: World, x: float, z: float) -> Dictionary:
	var space := w.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -100, z), Layers.WORLD)
	var hit := space.intersect_ray(q)
	# Skip props: walk down through non-terrain bodies.
	var guard := 0
	while not hit.is_empty() and not (hit.collider is StaticBody3D and String(hit.collider.name).begins_with("Collision_")) and guard < 8:
		q.from = hit.position + Vector3.DOWN * 0.01
		q.exclude = q.exclude + [hit.rid]
		hit = space.intersect_ray(q)
		guard += 1
	return hit
