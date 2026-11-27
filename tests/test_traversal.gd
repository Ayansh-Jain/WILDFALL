extends Node
## Walks the real player controller through every trail and the key
## structures (bridges, fords, stairs, cave, viewpoints). A route fails if the
## walker gets stuck for longer than the leg timeout.


func run(t) -> void:
	var w: World = t.world
	var player: PlayerController = t.main.player
	var drv := PlayerDriver.new(player)
	var cave: Cave = w.get_node("Sites/Cave")
	var c := WorldLayout.v2(w.layout.find_site("Old Citadel")["center"])
	var hc := w.site_height("Old Citadel")
	var total_m := 0.0
	var t0 := Time.get_ticks_msec()

	# 1. Every trail in the layout, end to end.
	for trail in w.layout.list("trails"):
		var pts := _densify(WorldLayout.points(trail["points"]), 6.0)
		if pts.size() < 2:
			continue
		var res := await _route(t, w, drv, "trail: " + trail["name"], pts)
		total_m += res.get("path_length", 0.0)

	# 2. Crossings, structures and viewpoints, with extra checks.
	var r := await _route(t, w, drv, "cross North Bridge", _v([[74, -150], [84, -150], [100, -150], [116, -150], [124, -150]]))
	t.check(r["ok"] and not drv.swam, "North Bridge is crossed without entering the water")
	r = await _route(t, w, drv, "cross Stone Bridge", _v([[38, 158], [45, 165], [58, 172], [71, 180], [78, 184]]))
	t.check(r["ok"] and not drv.swam, "Stone Bridge is crossed without entering the water")
	r = await _route(t, w, drv, "wade Old Ford", _v([[62, -213], [86, -214], [110, -217]]))
	t.check(r["ok"] and not drv.swam and drv.max_depth > 0.2, "Old Ford is crossed by wading", "max depth %.2f" % drv.max_depth)
	r = await _route(t, w, drv, "wade Reed Ford", _v([[0, 228], [23, 228], [46, 230]]))
	t.check(r["ok"] and not drv.swam and drv.max_depth > 0.2, "Reed Ford is crossed by wading", "max depth %.2f" % drv.max_depth)
	r = await _route(t, w, drv, "island causeway", _v([[137, 108], [139, 100], [144, 75], [148, 50], [150, 38]]))
	t.check(r["ok"] and not drv.swam and player.global_position.y > w.water_level + 1.0, "island shrine is reachable on foot via the causeway")
	r = await _route(t, w, drv, "swim across the lake", _v([[56, 40], [100, 40], [130, 20]]), {"allow_water": true})
	t.check(r["ok"] and drv.swam, "the lake can be swum across")

	var keep := _local(c, [[30, 0], [20, 0], [11, 5], [2, 12], [2, 5], [2, 0]])
	r = await _route(t, w, drv, "citadel gate to keep top", keep)
	t.check(r["ok"] and player.global_position.y > hc + 2.8, "keep top (elevated) is reachable by stairs", "y %.1f, ground %.1f" % [player.global_position.y, hc])
	r = await _route(t, w, drv, "citadel rampart", _local(c, [[-5, 17], [-8.5, 21.4], [-17.4, 21.4], [-16, 24]]), {"start_y": hc + 2.0, "reach": 0.5})
	t.check(r["ok"] and player.global_position.y > hc + 3.5, "rampart wall-walk is reachable by stairs", "y %.1f" % player.global_position.y)
	r = await _route(t, w, drv, "citadel west gate and passage", _local(c, [[-34, 7], [-20, 7], [-14, -4], [-14.2, -12], [-18, -18]]))
	t.check(r["ok"], "west gate and the narrow inner passage are passable")

	var wt := w.site_height("Watchtower")
	r = await _route(t, w, drv, "watchtower stairs", _v([[-200, 224], [-200, 205], [-200, 191]]))
	t.check(r["ok"] and player.global_position.y > wt + 5.0, "watchtower top (viewpoint) is reachable", "y %.1f, site %.1f" % [player.global_position.y, wt])

	var cave_pts: Array = [Vector3(-32, 0, -170)]
	for k in [[7, 15], [7, 13], [7, 11], [7, 9], [7, 7], [7, 6], [10, 6], [10, 4], [10, 3], [10, 2], [9, 2], [9, 1], [6, 1], [6, 2], [5, 2], [5, 3], [4, 3], [4, 4], [2, 4], [0, 4]]:
		cave_pts.append(cave.cell_center_world(Vector2i(k[0], k[1])))
	cave_pts.append(Vector3(-72, 0, -226))
	var entered := [false]
	var on_enter := func() -> void: entered[0] = true
	cave.player_entered.connect(on_enter)
	r = await _route(t, w, drv, "cave: south mouth -> chamber -> west mouth", cave_pts)
	cave.player_entered.disconnect(on_enter)
	t.check(r["ok"] and entered[0], "the cave network is traversable end to end and triggers the cave zone")

	r = await _route(t, w, drv, "Elder Tree dais", _v([[0, 44], [0, 26], [3, 14], [4, 7]]))
	t.check(r["ok"] and player.global_position.y > w.site_height("Elder Tree") + 0.8, "the landmark dais is walkable up to the roots")
	r = await _route(t, w, drv, "Sentinel summit", _v([[196, -104], [210, -93], [215, -90]]))
	t.check(r["ok"] and player.global_position.y > w.terrain_height(215, -90) - 0.5, "Sentinel Crag summit is reachable", "y %.1f" % player.global_position.y)
	r = await _route(t, w, drv, "chapel interior", _v([[-95, 150], [-95, 140], [-95, 124]]))
	r = await _route(t, w, drv, "lakeside castle courtyard", _v([[182, 152], [194, 150], [204, 150], [212, 154]]))
	var cc := WorldLayout.v2(w.layout.find_site("Lakeside Castle")["center"])
	var hk := w.site_height("Lakeside Castle")
	var sites := w.get_node("Sites/Structures") as Sites
	(sites.bedroom_door.get_node("OpenBedroomDoor") as Interactable).interact(player)
	r = await _route(t, w, drv, "castle keep: great hall -> stair hall -> commander's balcony", _keep_local(sites, [
		[8, 3], [14, -5], [19.5, -5.5], [23.4, -5.8], [23.4, 2.0], [22.5, 3.5], [19.4, 3.5], [19.4, -2.0],
		[19.4, -5.9], [15.5, -5.7], [3, -4.0], [0.5, -1.4], [-3.0, -1.4], [-3.0, -5.5], [-3.2, -8.5],
		[-5.5, -12.0], [-3.0, -20.5], [-2.8, -25.5]]), {"start_y": hk + 2.0, "reach": 0.9})
	t.check(r["ok"] and player.global_position.y > hk + 12.4 and sites.castle_from_world(player.global_position).z < -24.0,
		"the keep's first floor and the commander's balcony are reachable on foot",
		"at %s" % str(player.global_position - Vector3(cc.x, hk, cc.y)))
	r = await _route(t, w, drv, "castle keep: first floor -> stair hall -> roof, where Princess Reve waits", _keep_local(sites, [
		[19.0, -6.0], [23.4, -5.7], [23.4, 0.8], [22.8, 2.4], [19.4, 2.4], [19.4, -3.0], [19.4, -5.3],
		[16.0, -5.6], [17.5, -11.0], [18.0, -18.5], [10.0, -18.8], [0.0, -19.0], [-4.6, -20.3]]), {"start_y": hk + 14.0, "reach": 0.9})
	t.check(r["ok"] and player.global_position.y > hk + 22.0, "the keep roof is reachable on foot (no steep stair)",
		"at %s" % str(player.global_position - Vector3(cc.x, hk, cc.y)))
	player.teleport(Vector3(cc.x - 5.0, hk - 11.4, cc.y + 9.0))
	await drv.frames(40)
	t.check(not player.is_swimming and not player.is_camera_underwater() and absf(player.global_position.y - (hk - 11.65)) < 0.5,
		"the crypt below the lake's water line is dry ground", "y %.2f swimming %s" % [player.global_position.y - hk, player.is_swimming])
	r = await _route(t, w, drv, "ferryman's hut", _v([[100, -224], [107, -224], [112, -224]]))

	# 3. Off-trail crossings of the deep forest (hide-and-seek routes).
	# The west woods now open onto the Great Gate Field; leave its ring of houses by the King's Way gap.
	r = await _route(t, w, drv, "off-trail: west deep forest", _v([[-250, 0], [-220, 50], [-196, 71], [-168, 76], [-150, 120]]))
	r = await _route(t, w, drv, "off-trail: south-west woods", _v([[-170, 230], [-120, 190], [-60, 140]]))
	r = await _route(t, w, drv, "off-trail: north-east woods", _v([[140, -180], [180, -150], [220, -160]]))

	print("    walked %.0f m of trails in %.1f s real time" % [total_m, (Time.get_ticks_msec() - t0) / 1000.0])
	drv.release()


func _route(t, w: World, drv: PlayerDriver, label: String, pts: Array, options := {}) -> Dictionary:
	var first: Vector3 = pts[0]
	var from_y: float = options.get("start_y", NAN)
	var start := SpawnValidator.find(w, Vector2(first.x, first.z), from_y, 8.0, {"max_slope_deg": 40.0})
	if not start["ok"]:
		t.check(false, label, "no valid start: " + start["reason"])
		return {"ok": false}
	drv.player.teleport(start["position"] + Vector3.UP * 0.05)
	drv.swam = false
	drv.max_depth = 0.0
	await drv.frames(5)
	var res: Dictionary = await drv.walk(pts.slice(1), {"leg_timeout": 25.0, "reach": options.get("reach", 1.6)})
	var detail: String = "%.0f m in %.0f s" % [res["path_length"], res["time"]] if res["ok"] else res["reason"]
	if res["ok"] and drv.swam and not options.get("allow_water", false) and label.begins_with("trail"):
		t.check(false, label, "had to swim")
		res["ok"] = false
		return res
	t.check(res["ok"], label, detail)
	return res


func _v(arr: Array) -> Array:
	var out := []
	for p in arr:
		out.append(Vector3(p[0], 0, p[1]))
	return out


func _local(c: Vector2, arr: Array) -> Array:
	var out := []
	for p in arr:
		out.append(Vector3(c.x + p[0], 0, c.y + p[1]))
	return out


func _densify(pts: PackedVector2Array, step: float) -> Array:
	var out := []
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in n:
			var p := a.lerp(b, float(k) / n)
			out.append(Vector3(p.x, 0, p.y))
	var last := pts[pts.size() - 1]
	out.append(Vector3(last.x, 0, last.y))
	return out


func _keep_local(sites: Sites, points: Array) -> Array:
	var out := []
	for p in points:
		out.append(sites.castle_to_world(Vector3(p[0], 0, p[1])))
	return out
