extends Node
func run(t) -> void:
	var player: PlayerController = t.main.player
	var sites := t.world.get_node("Sites/Structures") as Sites
	var lift := sites.built["Lakeside Castle"].get_node("PreservedUndercroft/TraditionalUndercroftHoist") as Node3D
	var drv := PlayerDriver.new(player)
	player.teleport(sites.castle_to_world(Vector3(8, 0.7, 13)))
	await drv.frames(10)
	var route: Array = []
	for point in [[195, 139], [195, 160], [201, 172], [207, 172], [207, 169], [207, 165]]:
		route.append(Vector3(point[0], 0, point[1]))
	var result := await drv.walk(route, {"reach": 0.4, "leg_timeout": 20, "sprint": false})
	t.check(result.ok and player.global_position.y > lift.global_position.y, "new keep exit boards original prison hoist on foot", result.reason)
	drv.set_input()
	var control: Interactable = lift.get("_car_control")
	var d := control.focus_point() - player.eye_position()
	player.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	await drv.frames(5)
	var interactor := player.get_node("Interactor") as PlayerInteractor
	if not t.check(interactor.focused == control and interactor.try_interact(), "original hoist control works through interaction focus"):
		drv.release()
		return
	await drv.frames(390)
	t.check(player.global_position.y < sites.castle_origin.y - 10 and not player.is_swimming, "original hoist carries commander to dry prison floor")
	result = await drv.walk([sites.castle_origin + Vector3(-5, 0, 20), sites.castle_origin + Vector3(-10, 0, 20)], {"reach": 0.5, "leg_timeout": 15, "sprint": false})
	t.check(result.ok, "leave lift naturally inside preserved undercroft", result.reason)
	result = await drv.walk([sites.castle_origin + Vector3(-5, 0, 20), lift.global_position], {"reach": 0.35, "leg_timeout": 15, "sprint": false})
	t.check(result.ok, "board original lift again from prison", result.reason)
	d = control.focus_point() - player.eye_position()
	player.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	await drv.frames(5)
	t.check(interactor.focused == control and interactor.try_interact(), "original lift lever starts return trip")
	await drv.frames(390)
	result = await drv.walk([sites.castle_origin + Vector3(-5, 0, 22)], {"reach": 0.5, "leg_timeout": 15, "sprint": false})
	t.check(result.ok and player.global_position.y > sites.castle_origin.y - 1, "return to original surface landing on foot", result.reason)
	drv.release()
