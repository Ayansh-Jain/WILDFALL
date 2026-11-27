extends Node
## Focused movement checks for the new settlement lanes and connected bridge roads.


func run(t) -> void:
	var driver := PlayerDriver.new(t.main.player)
	var routes := [
		{
			"name": "Westmarch cart road to North Bridge west deck",
			"points": [[-236, -32], [-224, -17], [-208, 0], [-190, 13], [-171, 22], [-151, 26], [-132, 21], [-113, 9], [-94, -5], [-76, -21], [-60, -38], [-44, -52], [-20, -56], [10, -58], [42, -58], [64, -110], [82, -150]],
		},
		{
			"name": "North Bridge deck to east roadhead",
			"points": [[78, -150], [82, -150], [100, -150], [118, -150], [124, -150]],
		},
		{
			"name": "Stone Bridge cart road to Southbank",
			"points": [[38, 158], [42, 162], [44, 164], [58, 172], [72, 180], [80, 188], [94, 202], [108, 220], [110, 234], [104, 246], [94, 252], [80, 253], [80, 225]],
		},
		{
			"name": "Northmere house lanes",
			"points": [[144, -78], [141, -80], [139, -83], [141, -85], [145, -84], [147, -81], [144, -78], [149, -77], [150, -74], [147, -72], [144, -78], [139, -75], [137, -72], [140, -70], [144, -78]],
		},
		{
			"name": "Southbank house lanes",
			"points": [[80, 225], [76, 222], [73, 220], [71, 223], [73, 227], [77, 229], [80, 225], [84, 222], [88, 220], [90, 223], [87, 227], [83, 229], [80, 225]],
		},
	]
	for route: Dictionary in routes:
		await _walk_route(t, driver, String(route["name"]), route["points"])
	driver.release()


func _walk_route(t, driver: PlayerDriver, label: String, coordinates: Array) -> void:
	var world: World = t.world
	var first: Array = coordinates[0]
	var start := SpawnValidator.find(world, Vector2(float(first[0]), float(first[1])), NAN, 8.0, {"max_slope_deg": 40.0})
	if not start.get("ok", false):
		t.check(false, label, "no valid start: " + String(start.get("reason", "unknown")))
		return
	driver.player.teleport(start["position"] + Vector3.UP * 0.05)
	driver.swam = false
	await driver.frames(5)
	var points: Array[Vector3] = []
	for coordinate: Array in coordinates.slice(1):
		points.append(Vector3(float(coordinate[0]), 0.0, float(coordinate[1])))
	var result := await driver.walk(points, {"leg_timeout": 25.0, "reach": 1.8, "sprint": true})
	var ok: bool = result.get("ok", false) and not driver.swam
	var detail := "%.0f m in %.0f s" % [float(result.get("path_length", 0.0)), float(result.get("time", 0.0))]
	if driver.swam:
		detail += "; unexpectedly entered swimming"
	elif not result.get("ok", false):
		detail = String(result.get("reason", "route failed"))
	t.check(ok, label, detail)
