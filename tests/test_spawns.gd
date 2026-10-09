extends Node
## Player spawn markers and scroll spawn markers.


func run(t) -> void:
	var w: World = t.world
	var main = t.main
	var spawns: Array[Vector3] = main.player_spawns
	var defined: int = w.layout.list("player_spawns").size()
	t.check(spawns.size() == defined, "all %d player spawn markers resolve to valid ground" % defined, "%d valid" % spawns.size())
	t.check(spawns.size() >= 10, "at least 10 player spawns for 8-10 players")

	var landmark := WorldLayout.v2(w.layout.find_site("Elder Tree")["center"])
	var min_landmark := INF
	var min_pair := INF
	var min_water := INF
	var min_edge_ok := true
	for i in spawns.size():
		var s := spawns[i]
		min_landmark = minf(min_landmark, Vector2(s.x, s.z).distance_to(landmark))
		min_water = minf(min_water, s.y - w.water_level)
		if not w.terrain_data.in_playable(s.x, s.z, 10.0):
			min_edge_ok = false
		for j in range(i + 1, spawns.size()):
			min_pair = minf(min_pair, s.distance_to(spawns[j]))
	t.check(min_landmark > 150.0, "spawns are far from the central landmark", "closest %.0f m" % min_landmark)
	t.check(min_water > 0.8, "spawns are on dry land", "lowest %.1f m above water" % min_water)
	t.check(min_pair > 60.0, "spawns are spread around the map", "closest pair %.0f m" % min_pair)
	t.check(min_edge_ok, "spawns are inside the playable area")
	var hazard_free := true
	for s in spawns:
		# No deep water within 12 m (would be an immediate hazard).
		for a in 8:
			var p := Vector2(s.x, s.z) + Vector2.from_angle(TAU * a / 8.0) * 12.0
			if w.terrain_data.height_at(p.x, p.y) < w.water_level - 1.0:
				hazard_free = false
	t.check(hazard_free, "no deep water right next to any spawn")

	# Scroll markers
	var sp: ScrollSpawner = main.scroll_spawner
	var markers := w.layout.list("scroll_spawns")
	t.check(sp.rejected.is_empty(), "every designated scroll marker validates", str(sp.rejected))
	t.check(sp.candidates.size() == markers.size(), "%d scroll candidates" % markers.size(), str(sp.candidates.size()))
	var space := w.get_world_3d().direct_space_state
	var all_clear := true
	var all_dry := true
	for cand in sp.candidates:
		var pos: Vector3 = cand["position"]
		if pos.y < w.water_level + 0.5:
			all_dry = false
		var q := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.35
		q.shape = sphere
		q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.75)
		q.collision_mask = Layers.WORLD
		if not space.intersect_shape(q, 1).is_empty():
			all_clear = false
			print("    marker inside geometry: ", cand["name"])
	t.check(all_dry, "no scroll marker is underwater or at the waterline")
	t.check(all_clear, "no scroll marker is inside geometry")

	# Cave marker really is inside the cave (under the roof), not on the dome.
	for cand in sp.candidates:
		if cand["name"] == "cave_chamber":
			var floor_h: float = w.terrain_data.cave["floor"]
			t.check(absf(cand["position"].y - floor_h) < 0.6, "cave scroll marker sits on the cave floor", "%.2f vs %.2f" % [cand["position"].y, floor_h])

	# Determinism and variety.
	var a := _pick(sp, 12345)
	var b := _pick(sp, 12345)
	t.check(a == b, "same scroll seed gives the same marker", a)
	var seen := {}
	for s in 40:
		seen[_pick(sp, s * 977 + 3)] = true
	t.check(seen.size() >= 6, "different seeds use many different markers", "%d distinct" % seen.size())
	t.check(get_tree().get_nodes_in_group("scroll").size() == 1, "exactly one scroll exists in the match")


func _pick(sp: ScrollSpawner, seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return sp.candidates[rng.randi_range(0, sp.candidates.size() - 1)]["name"]
