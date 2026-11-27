extends Node
func run(t) -> void:
	var w: World = t.world
	var player: PlayerController = t.main.player
	var drv := PlayerDriver.new(player)
	for road in w.layout.list("roads"):
		if road.name != "Castle Square Road":
			continue
		var pts := WorldLayout.points(road.points)
		var route: Array = []
		for i in pts.size() - 1:
			var steps := maxi(1, int(pts[i].distance_to(pts[i + 1]) / 8.0))
			for s in steps:
				var p := pts[i].lerp(pts[i + 1], float(s) / steps)
				route.append(Vector3(p.x, 0, p.y))
		route.append(Vector3(pts[-1].x, 0, pts[-1].y))
		var start := SpawnValidator.find(w, Vector2(route[0].x, route[0].z), NAN, 8, {"max_slope_deg": 40.0, "edge_margin": 4.0})
		player.teleport(start.position + Vector3.UP * 0.05)
		await drv.frames(5)
		var result := await drv.walk(route.slice(1), {"leg_timeout": 25, "reach": 1.8})
		t.check(result.ok and not drv.swam, "Castle Square Road original densified regression", result.reason)
		if not result.ok:
			for i in player.get_slide_collision_count():
				var collision := player.get_slide_collision(i)
				var body := collision.get_collider()
				print("[approach collision] ", body.get_path(), " point=", collision.get_position(), " normal=", collision.get_normal())
		for piece in w.get_node("Sites/Structures/LakesideCastle").get_children():
			if piece is RuinPiece and piece.position.x > 125 and piece.position.x < 161:
				print("[approach geometry] ", piece.name, " kind=", piece.kind, " pos=", piece.position, " size=", piece.size, " yaw=", piece.rotation_degrees.y)
	drv.release()
