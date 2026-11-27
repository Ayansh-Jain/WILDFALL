extends Node
## Phase 1 kingdom layout: the curtain wall and mountain quarter, the sealed
## great gate, the town (house placement rules), the memorial cemetery, the
## training ground, the four reserved mission spaces, and walks along the new
## main roads.


func run(t) -> void:
	var w: World = t.world
	var sites: Sites = w.get_node("Sites/Structures")
	var plan: KingdomPlan = sites.kingdom_plan
	if not t.check(plan != null, "the kingdom plan was built"):
		return
	var td := w.terrain_data
	_boundary(t, w, td, plan)
	_wall_continuity(t, w, plan)
	_houses(t, w, td, plan)
	_missions(t, w, td, plan)
	_cemetery(t, w, td, plan, sites)
	_training(t, w, sites)
	_vegetation(t, w, plan)
	await _gate_is_sealed(t, w, plan)
	await _escape_attempts(t, w, plan)
	await _walks(t, w)


# --- boundary --------------------------------------------------------------------------

func _boundary(t, w: World, td: TerrainData, plan: KingdomPlan) -> void:
	t.check(plan.wall_pieces.size() >= 150, "curtain wall is built in pieces along its whole length", "%d pieces" % plan.wall_pieces.size())
	var length := 0.0
	for i in plan.wall_points.size() - 1:
		length += plan.wall_points[i].distance_to(plan.wall_points[i + 1])
	# Share of the boundary held by the wall vs the northern mountains.
	var mountain_arc := 0.0
	var samples := 720
	var walled := 0
	for i in samples:
		var a := TAU * float(i) / samples
		var p := Vector2(sin(a), -cos(a)) * 300.0
		if td.mountain_weight(p.x, p.y) < 0.5:
			walled += 1
		else:
			mountain_arc += 1.0
	var share := float(walled) / samples
	t.check(share > 0.65 and share < 0.8, "the wall holds about three quarters of the boundary, the mountains the rest", "wall %.0f%% of bearings, %.0f m of wall" % [share * 100.0, length])
	t.check(plan.towers.size() >= 20, "wall towers stand along the circuit", "%d towers" % plan.towers.size())
	t.check(plan.wall_height >= 10.0 and plan.wall_thickness >= 4.0, "the wall is substantial (height and thickness)", "%.1f m high, %.1f m thick" % [plan.wall_height, plan.wall_thickness])
	t.check(td.height_at(68, -315) > 20.0 and td.height_at(0, -325) > 40.0, "the waterfall's mountain range remains in the north", "%.1f m" % td.height_at(0, -325))
	var flat_ok := true
	var detail := ""
	for p: Vector2 in [Vector2(282, 0), Vector2(0, 278), Vector2(-282, 0), Vector2(270, 230), Vector2(-260, 220)]:
		var h := td.height_at(p.x, p.y)
		if h > 14.0:
			flat_ok = false
			detail += " %s=%.1f" % [str(p), h]
	t.check(flat_ok, "no edge mountains inside the wall on the walled sides", detail)
	var outer_ok := true
	for p: Vector2 in [Vector2(330, 0), Vector2(0, 330), Vector2(-330, 40)]:
		if td.height_at(p.x, p.y) > 45.0:
			outer_ok = false
	t.check(outer_ok, "beyond the wall the land is open hills, not the old mountain rim")
	t.check(plan.water_gates.size() == 1, "the river leaves through a grated water gate", "%d" % plan.water_gates.size())
	var spawns_ok := true
	for s in w.layout.list("player_spawns"):
		var p := WorldLayout.v2(s)
		if not td.in_playable(p.x, p.y, 10.0):
			spawns_ok = false
	t.check(spawns_ok, "every player spawn is inside the kingdom")


## Horizontal rays across the wall line must always hit solid collision: low
## (walking), high (jumping/climbing) and above the wall walk (barrier).
func _wall_continuity(t, w: World, plan: KingdomPlan) -> void:
	var space := w.get_world_3d().direct_space_state
	var gaps: Array[String] = []
	var probes := 0
	for i in plan.wall_points.size() - 1:
		var a := plan.wall_points[i]
		var b := plan.wall_points[i + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var outward := Vector2(dir.y, -dir.x)
		var steps := int(length / 3.0)
		for s in steps + 1:
			var p := a + dir * (length * s / maxf(steps, 1))
			var inner := p - outward * 7.0
			var outer := p + outward * 7.0
			var g := maxf(w.terrain_height(inner.x, inner.y), w.terrain_height(p.x, p.y))
			for dy: float in [0.6, 1.6, 6.0, 18.0]:
				var y := maxf(g, w.water_level - 0.5) + dy
				var q := PhysicsRayQueryParameters3D.create(Vector3(inner.x, y, inner.y), Vector3(outer.x, y, outer.y), Layers.WORLD)
				probes += 1
				if space.intersect_ray(q).is_empty():
					gaps.append("%s@+%.1f" % [str(p.round()), dy])
			# Swimming height at the water gate.
			if w.terrain_height(p.x, p.y) < w.water_level:
				var qw := PhysicsRayQueryParameters3D.create(Vector3(inner.x, w.water_level - 0.4, inner.y), Vector3(outer.x, w.water_level - 0.4, outer.y), Layers.WORLD)
				probes += 1
				if space.intersect_ray(qw).is_empty():
					gaps.append("%s@water" % str(p.round()))
	t.check(gaps.is_empty(), "no gaps through the wall, gate or water gate (rays every 3 m at 4 heights)", "%d probes, %d gaps %s" % [probes, gaps.size(), str(gaps.slice(0, 6))])
	# Barrier beyond each wall end, into the mountains.
	var ext_gaps := 0
	for ext in plan.barrier_extensions:
		var a: Vector2 = ext[0]
		var b: Vector2 = ext[1]
		var dir := (b - a).normalized()
		var nrm := Vector2(dir.y, -dir.x)
		for s in 12:
			var p := a.lerp(b, (float(s) + 0.5) / 12.0)
			var gy := w.terrain_height(p.x, p.y) + 1.5
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x - nrm.x * 4.0, gy, p.y - nrm.y * 4.0), Vector3(p.x + nrm.x * 4.0, gy, p.y + nrm.y * 4.0), Layers.WORLD)
			if space.intersect_ray(q).is_empty():
				ext_gaps += 1
	t.check(ext_gaps == 0, "the wall ends are sealed into the mountain range", "%d gaps" % ext_gaps)


# --- houses -------------------------------------------------------------------------------

func _houses(t, w: World, td: TerrainData, plan: KingdomPlan) -> void:
	var houses := plan.houses
	t.check(houses.size() >= 70, "the town is expanded with reused house archetypes", "%d houses, %d stalls" % [houses.size(), plan.stalls.size()])
	var archetypes := {}
	for h in houses:
		archetypes[h["archetype"]] = archetypes.get(h["archetype"], 0) + 1
	t.check(archetypes.size() >= 6, "a mixture of house types is used", str(archetypes))
	var overlaps := 0
	var all := houses + plan.stalls
	for i in all.size():
		var a: Dictionary = all[i]
		var ca := KingdomPlan.corners(a["center"], a["yaw"], a["w"], a["d"])
		for j in range(i + 1, all.size()):
			var b: Dictionary = all[j]
			if a["center"].distance_to(b["center"]) > 14.0:
				continue
			if not Geometry2D.intersect_polygons(ca, KingdomPlan.corners(b["center"], b["yaw"], b["w"], b["d"])).is_empty():
				overlaps += 1
	t.check(overlaps == 0, "no two buildings intersect", "%d overlaps" % overlaps)
	var floating := 0
	var buried := 0
	var on_road := 0
	var near_wall := 0
	var in_mission := 0
	var near_cemetery := 0
	var in_zone := 0
	var cem := WorldLayout.v2(plan.k["cemetery"]["center"])
	var fence := float(plan.k["cemetery"]["fence_radius"])
	for h in houses:
		var lo := INF
		var hi := -INF
		for p in KingdomPlan.footprint_samples(h["center"], h["yaw"], h["w"], h["d"]):
			var g := td.height_at(p.x, p.y)
			lo = minf(lo, g)
			hi = maxf(hi, g)
			if td.sample(td.trail_dist, p.x, p.y) < 0.5:
				on_road += 1
			if td.wall_distance(p.x, p.y) > -8.0:
				near_wall += 1
			if p.distance_to(cem) < fence + 20.0:
				near_cemetery += 1
		if float(h["base"]) > lo + 0.01:
			floating += 1
		if hi - float(h["base"]) > 2.0:
			buried += 1
		for z in plan.fight_zones:
			if KingdomPlan.zone_distance(z, h["center"]) < 0.0:
				in_mission += 1
		for z in plan.zones:
			if KingdomPlan.zone_distance(z, h["center"]) < 0.0:
				in_zone += 1
	t.check(floating == 0 and buried == 0, "every house sits on the terrain (no floating foundations, not sunk)", "floating %d, sunk %d" % [floating, buried])
	t.check(on_road == 0, "no road or trail passes through a building", "%d footprint samples on roads" % on_road)
	t.check(near_wall == 0, "houses keep clear of the curtain wall", "%d samples within 8 m" % near_wall)
	t.check(in_mission == 0, "no house stands inside a mission fighting space", "%d" % in_mission)
	t.check(in_zone == 0, "no house stands inside a protected landmark zone", "%d" % in_zone)
	t.check(near_cemetery == 0, "at least 20 m between the cemetery fence and any house", "%d footprint samples closer" % near_cemetery)
	# Bridges and fords stay clear.
	var crossings := 0
	for h in houses:
		for b in w.layout.list("bridges"):
			for key in ["a", "b"]:
				if h["center"].distance_to(WorldLayout.v2(b[key])) < 18.0:
					crossings += 1
		for f in w.layout.list("fords"):
			if h["center"].distance_to(WorldLayout.v2(f["center"])) < 18.0:
				crossings += 1
	t.check(crossings == 0, "no house blocks a bridge or ford")
	# Doors open onto clear, walkable ground, checked with the real physics.
	var blocked := 0
	var detail := ""
	for h in houses:
		var front := Vector2(-sin(h["yaw"]), -cos(h["yaw"]))
		var apron: Vector2 = h["center"] + front * (float(h["d"]) * 0.5 + 1.6)
		var res := SpawnValidator.check(w, apron, NAN, 38.0, 0.3, 0.0)
		if not res["ok"]:
			blocked += 1
			if detail.length() < 160:
				detail += " %s:%s" % [str(apron.round()), res["reason"]]
	t.check(blocked == 0, "every door has a clear apron to stand on", "%d blocked%s" % [blocked, detail])
	# Collision exists for each house.
	var space := w.get_world_3d().direct_space_state
	var missing := 0
	for h in houses:
		var c: Vector2 = h["center"]
		var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, float(h["base"]) + 30.0, c.y), Vector3(c.x, float(h["base"]) - 1.0, c.y), Layers.WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.position.y < float(h["base"]) + 3.0:
			missing += 1
	t.check(missing == 0, "every house is solid (no entry, no roof access)", "%d without collision" % missing)


# --- missions ----------------------------------------------------------------------------------

func _missions(t, w: World, td: TerrainData, plan: KingdomPlan) -> void:
	var by_id := {}
	for m in plan.k.get("missions", []):
		by_id[m["id"]] = m
	t.check(by_id.size() == 4, "four mission spaces are reserved", str(by_id.keys()))
	var zones := {}
	for z in plan.fight_zones:
		zones[String(z["name"]).substr(8, 1)] = z
	for id in ["A", "B", "C"]:
		var z: Dictionary = zones.get(id, {})
		if z.is_empty():
			t.check(false, "mission %s has a fighting space" % id)
			continue
		var cap := int(by_id[id]["capacity"])
		var area := KingdomPlan.zone_area(z)
		t.check(area >= cap * 25.0, "mission %s (%s) has room for %d combatants" % [id, by_id[id]["name"], cap], "%.0f m2, %.0f m2 each" % [area, area / cap])
		var free := _free_fraction(w, z)
		t.check(free[0] >= 0.97, "mission %s fighting space is open, walkable ground" % id, "%.1f%% of %d points clear %s" % [free[0] * 100.0, free[1], free[2]])
	var b: Dictionary = zones.get("B", {})
	var c: Dictionary = zones.get("C", {})
	if not b.is_empty() and not c.is_empty():
		t.check(b["center"].distance_to(c["center"]) > 200.0, "the town square and the outer battlefield are separate spaces")
		# C lies directly in front of the sealed gate.
		var g := plan.gate_center
		var to_c: Vector2 = (c["center"] - g).normalized()
		var inward := Vector2(1, 0)
		for s in plan.wall_points.size() - 1:
			if TerrainData.seg_dist(g, plan.wall_points[s], plan.wall_points[s + 1]) < 1.0:
				var dir := (plan.wall_points[s + 1] - plan.wall_points[s]).normalized()
				inward = -Vector2(dir.y, -dir.x)
		t.check(rad_to_deg(absf(to_c.angle_to(inward))) < 10.0 and g.distance_to(c["center"]) < float(c["radius"]) + 30.0,
			"the 100-person battlefield lies directly in front of the great gate", "%.0f m from the gate" % g.distance_to(c["center"]))
		# Ring of houses around C.
		var ring := 0
		var sectors := {}
		for h in plan.houses:
			var d: float = h["center"].distance_to(c["center"])
			if d > float(c["radius"]) + 2.0 and d < float(c["radius"]) + 20.0:
				ring += 1
				var ang := rad_to_deg((h["center"] - c["center"]).angle())
				sectors[int(floor((ang + 180.0) / 45.0))] = true
		t.check(ring >= 18 and sectors.size() >= 6, "the battlefield is ringed by houses", "%d houses in %d of 8 sectors" % [ring, sectors.size()])
	# D: spy spawn points across the kingdom.
	var ok := 0
	var bad := ""
	for sp in plan.spy_points:
		var res := SpawnValidator.check(w, sp["pos"], NAN, 32.0, 0.4, 6.0)
		if sp["ok"] and res["ok"]:
			ok += 1
		elif bad.length() < 200:
			bad += " %s:%s%s" % [str(sp["pos"]), sp["reason"], res["reason"]]
	t.check(plan.spy_points.size() == 20 and ok == 20, "20 spy spawn points are valid (ground, dry, unblocked, outside landmarks)", "%d/%d%s" % [ok, plan.spy_points.size(), bad])
	var routes: Array = by_id.get("D", {}).get("routes", [])
	var centroids: Array[Vector2] = []
	for r in routes:
		var sum := Vector2.ZERO
		for p in r:
			sum += WorldLayout.v2(p)
		centroids.append(sum / r.size())
	var spread := INF
	for i in centroids.size():
		for j in range(i + 1, centroids.size()):
			spread = minf(spread, centroids[i].distance_to(centroids[j]))
	t.check(routes.size() >= 5 and spread > 80.0, "spy patrol routes are spread across the kingdom", "%d routes, nearest %.0f m apart" % [routes.size(), spread])


## Fraction of a 3 m grid inside the zone where a standing player fits.
func _free_fraction(w: World, z: Dictionary) -> Array:
	var c: Vector2 = z["center"]
	var ext: Vector2 = z["half"] if z.has("half") else Vector2.ONE * float(z["radius"])
	var total := 0
	var free := 0
	var worst := ""
	var x := -ext.x
	while x <= ext.x:
		var y := -ext.y
		while y <= ext.y:
			var p := c + Vector2(x, y)
			if KingdomPlan.zone_distance(z, p) <= -0.5:
				total += 1
				var res := SpawnValidator.check(w, p, NAN, 30.0, 0.4, 0.0)
				if res["ok"]:
					free += 1
				elif worst.length() < 120:
					worst += " %s:%s" % [str(p.round()), res["reason"]]
			y += 3.0
		x += 3.0
	return [float(free) / maxf(total, 1), total, worst]


# --- cemetery and training ground ---------------------------------------------------------------

func _cemetery(t, w: World, td: TerrainData, plan: KingdomPlan, sites: Sites) -> void:
	var graves := w.get_tree().get_nodes_in_group("memorial_graves")
	t.check(graves.size() >= 28 and graves.size() <= 32, "about 30 cross grave markers stand around the Elder Tree", "%d" % graves.size())
	var cem: Dictionary = plan.k["cemetery"]
	var c := WorldLayout.v2(cem["center"])
	var inside := true
	for g in plan.graves:
		var d: float = g["pos"].distance_to(c)
		if d < 21.0 or d > float(cem["fence_radius"]) - 1.5:
			inside = false
	t.check(inside, "graves lie inside the fence, clear of the tree's dais and statues")
	var variants := {}
	for g in plan.graves:
		variants[g["variant"]] = true
	t.check(variants.size() >= 5, "the crosses are distinct designs", "%d designs" % variants.size())
	t.check(plan.fence_gates.size() >= 5, "the fence opens onto every path that reaches the tree", "%d gates" % plan.fence_gates.size())
	var label: Label3D = w.find_child("MemorialInscription", true, false)
	t.check(label != null and label.text.contains("In memory of those who gave") and label.text.contains("peace"),
		"the memorial stone carries the inscription", label.text.replace("\n", " ") if label else "missing")
	if label:
		var stand := label.global_position + label.global_basis.z * 3.0
		t.check(label.pixel_size * label.font_size >= 0.12, "the inscription is legible from a few metres", "%.2f m line height" % (label.pixel_size * label.font_size))
		var space := w.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.2, label.global_position + label.global_basis.z * 0.05, Layers.WORLD)
		t.check(space.intersect_ray(q).is_empty(), "the inscription can be read from the path (nothing in front of it)")
	var memorial := 0
	for patch in sites.flower_patches:
		if String(patch[2]).begins_with("memorial:"):
			memorial += 1
	t.check(memorial >= 18, "flowers are planted in clusters around graves", "%d clusters" % memorial)
	var houses_near := 0
	for h in plan.houses:
		if h["center"].distance_to(c) < float(cem["fence_radius"]) + 20.0:
			houses_near += 1
	t.check(houses_near == 0, "no houses within 20 m of the cemetery")


func _training(t, w: World, sites: Sites) -> void:
	var posts := w.get_tree().get_nodes_in_group("phase3_soldier_posts")
	t.check(posts.size() >= 4, "soldier positions are marked at the training ground's corners for Phase 3", "%d" % posts.size())
	var ok := 0
	for p: Node3D in posts:
		if SpawnValidator.check(w, Vector2(p.global_position.x, p.global_position.z), NAN, 30.0, 0.4, 0.0)["ok"]:
			ok += 1
	t.check(ok == posts.size(), "each soldier post has room to stand", "%d/%d" % [ok, posts.size()])
	var plan: KingdomPlan = sites.kingdom_plan
	var cit := WorldLayout.v2(w.layout.find_site("Old Citadel")["center"])
	var crowd := 0
	for h in plan.houses:
		if h["center"].distance_to(cit) < 52.0:
			crowd += 1
	t.check(crowd == 0, "no houses crowd the training ground")


func _vegetation(t, w: World, plan: KingdomPlan) -> void:
	var veg := w.get_node("Props/Vegetation")
	var inside := 0
	var trees := 0
	for mmi in veg.get_children():
		if not (mmi is MultiMeshInstance3D):
			continue
		var nm := String(mmi.name)
		if not (nm.begins_with("pine") or nm.begins_with("fir") or nm.begins_with("oak") or nm.begins_with("birch") or nm.begins_with("dead_tree")) or nm.contains("far"):
			continue
		var mm: MultiMesh = mmi.multimesh
		for i in mm.instance_count:
			var o := mm.get_instance_transform(i).origin
			trees += 1
			for h in plan.houses:
				if Vector2(o.x, o.z).distance_to(h["center"]) < sqrt(float(h["w"]) ** 2 + float(h["d"]) ** 2) * 0.5:
					inside += 1
	t.check(inside == 0, "no tree grows inside a house", "%d trees checked" % trees)
	var td := w.terrain_data
	var dense := 0.0
	var n := 0
	for x in range(150, 270, 6):
		for z in range(200, 270, 6):
			dense += td.sample(td.forest, float(x), float(z))
			n += 1
	t.check(dense / n < 0.08, "the inhabited town keeps only scattered trees", "mean forest density %.3f" % (dense / n))


# --- physical checks with the player --------------------------------------------------------------

func _gate_is_sealed(t, w: World, plan: KingdomPlan) -> void:
	var g := plan.gate_center
	var space := w.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 30.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, Vector3(g.x, w.terrain_height(g.x, g.y), g.y))
	q.collision_mask = Layers.INTERACTABLE
	q.collide_with_areas = true
	q.collide_with_bodies = false
	t.check(space.intersect_shape(q, 4).is_empty(), "nothing near the great gate can be interacted with")
	var drv := PlayerDriver.new(t.main.player)
	var start := SpawnValidator.find(w, g + Vector2(26, 0), NAN, 6.0)
	drv.player.teleport(start["position"] + Vector3.UP * 0.05, deg_to_rad(90.0))
	await drv.frames(5)
	var res := await drv.walk([Vector3(g.x - 30.0, 0, g.y)], {"leg_timeout": 10.0, "reach": 1.0})
	var x := drv.player.global_position.x
	t.check(not res["ok"] and x > g.x + plan.wall_thickness * 0.5 - 0.1, "the great gate stays closed: walking (and jumping) at it does not pass", "stopped at x %.1f (wall face %.1f)" % [x, g.x + plan.wall_thickness * 0.5])
	# Interact spam at the gate changes nothing.
	for i in 5:
		Input.action_press("interact")
		await drv.frames(2)
		Input.action_release("interact")
		await drv.frames(2)
	res = await drv.walk([Vector3(g.x - 30.0, 0, g.y)], {"leg_timeout": 4.0, "reach": 1.0})
	t.check(not res["ok"] and drv.player.global_position.x > g.x, "the gate is still sealed after pressing interact beside it")
	drv.release()


func _escape_attempts(t, w: World, plan: KingdomPlan) -> void:
	var drv := PlayerDriver.new(t.main.player)
	var escaped := []
	for p: Vector2 in [Vector2(250, 262), Vector2(-276, 200), Vector2(282, -20), plan.water_gates[0]["center"] - Vector2(0, 8) if not plan.water_gates.is_empty() else Vector2(0, 280)]:
		var out := Vector2(p.x * 1.25, p.y * 1.25)
		var start := SpawnValidator.find(w, p, NAN, 10.0, {"edge_margin": 4.0})
		if not start["ok"]:
			escaped.append("%s:no start" % str(p))
			continue
		drv.player.teleport(start["position"] + Vector3.UP * 0.05)
		await drv.frames(5)
		await drv.walk([Vector3(out.x, 0, out.y)], {"leg_timeout": 8.0, "reach": 1.0})
		var pp := drv.player.global_position
		if w.terrain_data.wall_distance(pp.x, pp.z) > 0.0:
			escaped.append(str(Vector2(pp.x, pp.z).round()))
	t.check(escaped.is_empty(), "walking (and swimming) at the wall never gets outside the kingdom", str(escaped))
	drv.release()


func _walks(t, w: World) -> void:
	if t.skip_walk:
		return
	var drv := PlayerDriver.new(t.main.player)
	for road in w.layout.list("roads"):
		if not road.get("main", false):
			continue
		var pts := WorldLayout.points(road["points"])
		var route: Array = []
		for i in pts.size() - 1:
			var steps := maxi(1, int(pts[i].distance_to(pts[i + 1]) / 8.0))
			for s in steps:
				var p := pts[i].lerp(pts[i + 1], float(s) / steps)
				route.append(Vector3(p.x, 0, p.y))
		route.append(Vector3(pts[pts.size() - 1].x, 0, pts[pts.size() - 1].y))
		var start := SpawnValidator.find(w, Vector2(route[0].x, route[0].z), NAN, 8.0, {"max_slope_deg": 40.0, "edge_margin": 4.0})
		if not start["ok"]:
			t.check(false, "road: " + String(road["name"]), "no valid start: " + String(start["reason"]))
			continue
		drv.player.teleport(start["position"] + Vector3.UP * 0.05)
		drv.swam = false
		await drv.frames(5)
		var res := await drv.walk(route.slice(1), {"leg_timeout": 25.0, "reach": 1.8})
		t.check(res["ok"] and not drv.swam, "main road walkable end to end: " + String(road["name"]),
			("%.0f m in %.0f s" % [res["path_length"], res["time"]]) if res["ok"] else String(res["reason"]))
	# Landmarks reachable from the roads.
	for leg in [
		["cemetery: road -> main gate -> memorial stone -> tree dais", [[2, 42], [1, 33], [0, 26], [3, 14]]],
		["training ground: road -> east gate -> drill yard", [[-127, -60], [-134, -60], [-142, -62], [-152, -76]]],
		["cave outskirts clearing -> cave south mouth", [[-28, -140], [-30, -158], [-32, -170]]],
		["castle square -> Ashford well", [[232, 96], [240, 80], [241, 60], [246, 46]]],
		["great gate field -> King's Way east", [[-270, 70], [-232, 70], [-180, 72], [-150, 74]]],
	]:
		var pts: Array = leg[1]
		var start := SpawnValidator.find(w, Vector2(pts[0][0], pts[0][1]), NAN, 6.0, {"max_slope_deg": 40.0})
		if not start["ok"]:
			t.check(false, String(leg[0]), "no valid start")
			continue
		drv.player.teleport(start["position"] + Vector3.UP * 0.05)
		await drv.frames(5)
		var route: Array = []
		for p in pts.slice(1):
			route.append(Vector3(p[0], 0, p[1]))
		var res := await drv.walk(route, {"leg_timeout": 20.0, "reach": 1.4})
		t.check(res["ok"], String(leg[0]), "" if res["ok"] else String(res["reason"]))
	drv.release()
