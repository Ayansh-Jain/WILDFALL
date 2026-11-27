extends Node
## Walk the new opening with the actual controller; no teleport between route legs.
var sites: Sites

func run(t) -> void:
	sites = t.world.get_node("Sites/Structures") as Sites
	var player: PlayerController = t.main.player
	var o := sites.castle_origin
	var gate := Vector3(-296, o.y, 70)
	var front := sites.castle_transform.basis * Vector3.BACK
	var pivot := o + Vector3(8, 0, -8)
	t.check(front.dot((gate - pivot).normalized()) > 0.99999, "keep entrance axis faces outer gate exactly")
	var ward_gate := o + Vector3(-40, 0, sites.castle_gate_z)
	t.check((ward_gate - pivot).normalized().dot(front) > 0.99999, "ward entrance shares keep approach axis")
	var prison := sites.built["Lakeside Castle"].get_node("PreservedUndercroft") as Node3D
	t.check(prison.global_transform == Transform3D.IDENTITY, "undercroft hierarchy remains at original world transform")
	var lift := prison.get_node("TraditionalUndercroftHoist") as Node3D
	var lift_expected := Vector3(o.x - 5, t.world.terrain_height(o.x - 5, o.z + 15), o.z + 15)
	t.check(lift.global_position.is_equal_approx(lift_expected), "hoist retains exact original position")
	# The original crypt's authored slabs and tunnel endpoints, beneath the unchanged terrain cutout.
	for p in [Vector3(-24, -11.65, -15), Vector3(0, -11.65, -20), Vector3(-23, -11.65, 6), Vector3(-5, -11.65, 22)]:
		var hit: Dictionary = t.world.ground_ray(o.x + p.x, o.z + p.z, o.y - 8, 8)
		t.check(not hit.is_empty() and absf(hit.position.y - (o.y + p.y)) < 0.1, "preserved prison floor %s" % p)
	t.check(sites.castle_keep.find_children("ChiefSeat_*", "MeshInstance3D", false, false).size() == 6, "six symmetric individual chief seats")
	t.check(sites.castle_keep.find_children("ChiefPortrait_*", "MeshInstance3D", false, false).size() == 6, "one framed painting per chief")
	for door in sites.castle_keep.find_children("LockedChiefChamber_*", "Node3D", false, false):
		t.check(door.find_children("*", "Interactable", true, false).is_empty() and not door.find_children("*", "CollisionShape3D", true, false).is_empty(), "chief chamber stays solid with no prompts")
	t.check(sites.find_children("LostShoreCrestKey", "", true, false).is_empty(), "obsolete crest key pickup removed")
	t.main.start_castle_opening()
	var opening: Node = t.main.castle_opening
	t.main.story.speed = 0.02
	var drv := PlayerDriver.new(player)
	await drv.frames(30)
	t.check(sites.castle_from_world(player.global_position).distance_to(Vector3(-5.4, 12.7, -12)) < 0.5, "commander starts on preserved bedroom floor")
	var result := await _walk(drv, [[-3.2, -8.7]], 0.45)
	t.check(result.ok, "walk from bed to bedroom door", result.reason)
	# Mission 1 locks the corridor until the balcony title and summons have finished.
	result = await _walk(drv, [[-3.2,-19],[-3.0,-22]],0.45)
	drv.set_input()
	for i in 700:
		await drv.frames(1)
		if opening.summons_done and player.controls_enabled and not t.main.story.in_dialogue:
			break
	result = await _walk(drv,[[-3.2,-8.7]],0.45)
	# Closed door collision stops movement before interaction.
	result = await _walk(drv, [[-3.2, -5.8]], 0.4, 2.0)
	t.check(not result.ok and sites.castle_from_world(player.global_position).z < -7, "closed bedroom door blocks exit")
	var door_it := sites.bedroom_door.get_node("OpenBedroomDoor") as Interactable
	var interactor := player.get_node("Interactor") as PlayerInteractor
	_look_at(player, door_it.focus_point())
	await drv.frames(4)
	t.check(interactor.focused == door_it and interactor.try_interact(), "bedroom door opens through real interaction focus")
	await drv.frames(65)
	result = await _walk(drv, [[-3.2, -5.5], [-3.2, -1.4], [1, -1.4], [8, -1.4], [15.7, -5.7], [19.4, -5.9]], 0.6)
	t.check(result.ok and sites.castle_from_world(player.global_position).y > 12.5, "bedroom through royal corridor to stair junction", result.reason)
	# Upstairs to the existing roof and back to the same junction.
	result = await _walk(drv, [[23.4, -5.7], [23.4, 0.8], [22.8, 2.4], [19.4, 2.4], [19.4, -3], [19.4, -5.3], [16, -5.6]], 0.6)
	t.check(result.ok and sites.castle_from_world(player.global_position).y > 22.0, "existing terrace reached on foot", result.reason)
	result = await _walk(drv, [[19.4, -5.3], [19.4, 2.4], [23.4, 2.4], [23.4, -5.7], [19.4, -5.9]], 0.5)
	t.check(result.ok and absf(sites.castle_from_world(player.global_position).y - 12.7) < 0.5, "terrace stairs return to upper junction", result.reason)
	result = await _walk(drv, [[19.4, -2], [19.4, 3.5], [22.5, 3.5], [23.4, 2], [23.4, -5.8], [19.5, -5], [14, -5]], 0.6)
	t.check(result.ok and sites.castle_from_world(player.global_position).y < 1.0, "descend naturally into the royal hall", result.reason)
	drv.set_input()
	for i in 600:
		if opening.reveal_done and not opening.revealing:
			break
		await drv.frames(1)
	t.check(opening.reveal_done and not opening.revealing and player.controls_enabled and player.camera.current, "balcony reveal restores player camera and controls")
	result = await _walk(drv, [[8, -5], [8, -16], [8, -18]], 0.7)
	t.check(result.ok, "red carpet aisle is unobstructed to throne dais", result.reason)
	result = await _walk(drv, [[8, -5], [8, 3], [8, 10], [8, 13]], 0.7)
	t.check(result.ok, "hall to main entrance and courtyard on foot", result.reason)
	drv.set_input()
	await drv.frames(180)
	t.check(opening.summons_done and t.main.story.has_flag("castle_summons_delivered"), "soldier delivers summons once outside")
	if t.main.story.triggers.has("OpeningGateAudience"):
		var greeting: Interactable = t.main.story.triggers["OpeningGateAudience"]
		await _walk(drv, [[6.8, 12.8]], 0.5)
		_look_at(player, greeting.focus_point())
		await drv.frames(4)
		t.check(interactor.focused == greeting and interactor.try_interact(), "gate audience is reachable through real interaction focus")
		await drv.frames(180)
	t.check(t.main.campaign.opening_completed and not opening.active, "opening hands off to Mission 1")
	# Walk out through the aligned ward gateway and its bridge.
	var wp := o + Vector3(-34, 0, sites.castle_gate_z)
	var bridge := o + Vector3(-57, 0, sites.castle_gate_z)
	result = await drv.walk([wp, bridge], {"reach": 0.8, "leg_timeout": 20})
	t.check(result.ok, "approach from keep through ward gate remains accessible", result.reason)
	# Reach the existing road across the approach stair and paved spur.
	result = await drv.walk([o + Vector3(-70, 0, sites.castle_gate_z), o + Vector3(-74, 0, 9)], {"reach": 1.0, "leg_timeout": 25})
	t.check(result.ok and not drv.swam, "castle approach connects to the existing kingdom road", result.reason)
	result = await drv.walk([Vector3(150, 0, 134), Vector3(168, 0, 114), Vector3(190, 0, 100)], {"reach": 1.0, "leg_timeout": 25})
	t.check(result.ok and not drv.swam, "existing Castle Square Road crosses the new approach apron", result.reason)
	# Ride the real mounted horse straight through the broad keep entrance.
	var horse: Horse = t.main.horse
	var rider := player.get_node("Rider") as Rider
	var yaw := sites.castle_transform.basis.get_euler().y
	horse.teleport(sites.castle_to_world(Vector3(8, 0.2, 18)), yaw)
	player.teleport(horse.global_position + horse.global_transform.basis.x * 1.3, yaw)
	await drv.frames(20)
	t.check(rider.mount(horse), "commander mounts at castle entrance")
	await drv.frames(120)
	horse.cruise = Horse.Gait.WALK
	for i in 700:
		drv.set_input(Vector2(0, 1), false)
		await drv.frames(1)
		if sites.castle_from_world(horse.global_position).z < 3.5:
			break
	drv.set_input()
	t.check(sites.castle_from_world(horse.global_position).z < 3.5, "mounted horse crosses keep entrance and broad stair", str(sites.castle_from_world(horse.global_position)))
	rider.force_dismount()
	# Crypt is dry and its hoist controls still exist.
	player.teleport(o + Vector3(-5, -11.3, 22))
	await drv.frames(35)
	t.check(not player.is_swimming and absf(player.global_position.y - (o.y - 11.65)) < 0.2, "preserved prison is dry and walkable")
	t.check(lift.find_children("*", "Interactable", true, false).size() >= 3, "original jail lift interactions retained")
	drv.release()

func _walk(drv: PlayerDriver, points: Array, reach: float, timeout := 15.0) -> Dictionary:
	var route: Array = []
	for p in points:
		route.append(sites.castle_to_world(Vector3(p[0], 0, p[1])))
	return await drv.walk(route, {"reach": reach, "leg_timeout": timeout, "sprint": false})


func _look_at(player: PlayerController, target: Vector3) -> void:
	var d := target - player.eye_position()
	player.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
