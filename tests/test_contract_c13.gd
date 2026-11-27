extends Node
## Contract C-13 conformance tests for wf_marker nodes and GoldenValleyShowcase geography.

const SHOWCASE_SCENE := preload("res://scenes/world/showcase/golden_valley_showcase.tscn")
const VALID_KINDS := ["spawn_point", "escort_anchor", "camera_hint", "hazard_zone", "battle_cell", "no_spawn", "patrol_node"]


func run(t) -> void:
	var sc := SHOWCASE_SCENE.instantiate() as GoldenValleyShowcase
	sc.spawn_player = false
	sc.spawn_horse = false
	sc.auto_capture_mouse = false
	add_child(sc)
	if not sc.is_node_ready():
		await sc.showcase_ready
	await get_tree().physics_frame
	await get_tree().physics_frame

	var markers := get_tree().get_nodes_in_group("wf_marker")
	t.check(markers.size() >= 10, "C-13 showcase publishes wf_marker nodes", str(markers.size()))

	var ids := {}
	var bad_kinds := 0
	var off_ground := 0
	for m in markers:
		var mid := String(m.get_meta("marker_id", ""))
		var kind := String(m.get_meta("kind", ""))
		if mid == "" or ids.has(mid):
			ids["__dup__"] = true
		else:
			ids[mid] = true
		if not (kind in VALID_KINDS):
			bad_kinds += 1
		if m is Node3D:
			var p: Vector3 = (m as Node3D).global_position
			var gh := sc.td.height_at(p.x, p.z)
			if absf(p.y - gh) > 0.25:
				off_ground += 1

	t.check(not ids.has("__dup__"), "C-13 all marker_ids are non-empty and unique")
	t.check(bad_kinds == 0, "C-13 all marker kinds are in contract vocabulary", str(bad_kinds))
	t.check(off_ground == 0, "C-13 all markers are grounded on terrain", str(off_ground))

	# Verify terrain physics collision agrees with height_at() on showcase valley & bridge.
	var space := sc.get_world_3d().direct_space_state
	var worst := 0.0
	for pt: Vector2 in [Vector2(-146, 120), Vector2(-68, 56), Vector2(0, 25), Vector2(84, 18), Vector2(118, -42)]:
		var q := PhysicsRayQueryParameters3D.create(Vector3(pt.x, 200, pt.y), Vector3(pt.x, -50, pt.y), Layers.WORLD)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			worst = 999.0
		else:
			worst = maxf(worst, absf(float(hit["position"].y) - sc.td.height_at(pt.x, pt.y)))
	t.check(worst < 0.1, "showcase terrain collision matches height_at()", "worst=%.3f m" % worst)

	# Bridge spans river above water level with solid deck collision.
	var mid_bridge := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(34, 30, 16), Vector3(34, -10, 16), Layers.WORLD))
	t.check(not mid_bridge.is_empty() and float(mid_bridge["position"].y) > sc.WATER_LEVEL + 2.0,
		"showcase stone bridge deck has solid collision above river", str(mid_bridge.get("position", Vector3.ZERO)))

	sc.queue_free()
	await get_tree().process_frame
