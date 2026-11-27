extends Node
## R03 open-world integration, played through the real game. Writes save files, so it
## refuses to run unless the user data folder is redirected:
##   APPDATA=<repo>/.test_user_data/r03 godot --headless --fixed-fps 60 --path . res://tests/r03_world.tscn
## Options: -- --skip-journey

const MAIN := preload("res://scenes/main/main.tscn")
const SAVE := "user://wildfall_save.json"
const V1 := "user://campaign_save.json"

var passed := 0
var failed := 0
var main: Node
var world: World
var player: PlayerController
var ex: ExplorationDirector


func check(ok: bool, label: String, detail := "") -> bool:
	if ok:
		passed += 1
	else:
		failed += 1
	print("%s %s%s" % ["PASS" if ok else "FAIL", label, "" if detail == "" else "  (%s)" % detail])
	return ok


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_user_data_dir().contains(".test_user_data"):
		print("FAIL refusing to run against the real user folder: ", OS.get_user_data_dir())
		get_tree().quit(2)
		return
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("FAIL watchdog")
		get_tree().quit(3))
	_wipe()
	_persist_checks()
	_wipe()
	var v1_text := _write_v1_fixture()
	await _boot()
	check(Persist.status == "migrated", "an old campaign save is migrated", Persist.status)
	check(main.campaign.state.alive_count() == 3 and main.campaign.state.coins == 55, "migrated roster and coins survive",
		"%d alive, %d coins" % [main.campaign.state.alive_count(), main.campaign.state.coins])
	check(FileAccess.get_file_as_string(V1) == v1_text, "the old save file is not modified")
	await _data_checks()
	await _discovery()
	await _lifecycle()
	await _interaction()
	await _encounter()
	await _horse_and_map()
	await _save_and_reload(v1_text)
	await _recovery()
	await _relocation()
	if not OS.get_cmdline_user_args().has("--skip-journey"):
		await _journey()
	print("[r03-world] %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)


func _wipe() -> void:
	Persist.end_session()
	var dir := DirAccess.open("user://")
	for f in dir.get_files():
		if f.begins_with("wildfall_save") or f.begins_with("campaign_save"):
			dir.remove(f)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _write_v1_fixture() -> String:
	var state := CampaignState.new(CampaignState.load_config())
	state.new_campaign()
	while state.roster_size() < 4:
		state.roster.append({"id": state.roster.size() + 1, "name": "Test %d" % state.roster.size(), "alive": true, "health": 100})
	state.next_soldier_id = state.roster_size() + 1
	state.roster[0].alive = false
	state.roster[0].health = 0
	state.coins = 55
	var d := state.to_dict()
	d["hours"] = 3.0
	d["deployment_positions"] = {}
	d["castle_opening_complete"] = true
	var text := JSON.stringify(d, "\t")
	_write(V1, text)
	return text


# --- the save authority on its own -------------------------------------------------------------

func _persist_checks() -> void:
	var p := "user://wildfall_save_unit.json"
	var legacy := "user://campaign_save_none.json"
	check(Persist.begin_session(p, legacy) == "new", "no file means a new session")
	Persist.set_section("player", {"position": [1, 2, 3]})
	Persist.set_entity("enc:x", {"dead": [0]})
	Persist.set_flag("met", true)
	check(Persist.save("one") and Persist.save("two") and Persist.save("three"), "saving succeeds")
	check(FileAccess.file_exists(p + ".bak1") and FileAccess.file_exists(p + ".bak2") and not FileAccess.file_exists(p + ".tmp"),
		"two backups rotate and no temporary file is left")
	check(Persist.begin_session(p, legacy) == "loaded" and Persist.get_flag("met") == true
		and Persist.entity("enc:x").has("dead"), "sections, flags and entities round trip")
	_write(p, "{\"version\": 2, \"sections\": {")
	check(Persist.begin_session(p, legacy) == "recovered" and Persist.get_flag("met") == true, "a truncated save recovers from backup")
	var kept := Array(DirAccess.open("user://").get_files()).filter(func(f: String) -> bool: return f.begins_with("wildfall_save_unit.json.corrupt"))
	check(kept.size() >= 1, "the damaged file is kept aside")
	check(Persist.save("after recovery") and Persist.begin_session(p, legacy) == "loaded", "saving over a recovered file works")
	var newer := JSON.stringify({"version": 99, "sections": {}})
	_write(p, newer)
	check(Persist.begin_session(p, legacy) == "newer" and not Persist.save("x") and FileAccess.get_file_as_string(p) == newer,
		"a newer save is refused and left untouched")
	_write(legacy, "not json")
	check(Persist.begin_session("user://wildfall_save_none.json", legacy) == "new", "an unreadable old save starts fresh")
	Persist.end_session()
	check(not Persist.save("inactive"), "an inactive session never writes")


# --- the game -----------------------------------------------------------------------------------

func _boot() -> void:
	GameState.reset_match()
	main = MAIN.instantiate()
	main.set("auto_capture_mouse", false)
	main.set("spawn_bots", false)
	add_child(main)
	await main.ready_for_play
	world = main.world
	player = main.player
	ex = main.exploration
	main.story.speed = 0.02
	player.input_override = {}
	await frames(40)


func _shutdown() -> void:
	main.queue_free()
	await frames(10)


func _stand(xz: Vector2, wait := 40) -> void:
	if player.riding:
		(player.get_node("Rider") as Rider).force_dismount()
	player.teleport(ex.place(xz) + Vector3.UP * 0.15)
	await frames(wait)


func _data_checks() -> void:
	var bad: Array = []
	for loc in ex.db.locations():
		var p := ex.db.travel_point(String(loc["id"]))
		var res := SpawnValidator.find(world, p, world.terrain_height(p.x, p.y) + 3.0, 12.0, {"edge_margin": 1.0})
		if not res["ok"]:
			bad.append("%s: %s" % [loc["id"], res["reason"]])
	check(bad.is_empty(), "every place has a standable travel point", str(bad))
	bad.clear()
	var entries: Array = ex.db.interactions().duplicate()
	for s in ex.db.settlements():
		entries.append_array(s["villagers"])
	for entry in entries:
		var p := LocationDB.xz(entry)
		var at := ex.place(p)
		if Vector2(at.x - p.x, at.z - p.y).length() > 8.1 or at.y < world.water_level:
			bad.append("%s -> %s" % [entry["id"], at])
	check(bad.is_empty(), "every interaction and villager has ground nearby", str(bad))
	var ids := {}
	for entry in ex.db.locations() + ex.db.interactions() + ex.db.encounters():
		ids[entry["id"]] = true
	check(ids.size() == ex.db.locations().size() + ex.db.interactions().size() + ex.db.encounters().size(), "ids are unique")


func _discovery() -> void:
	var found: Array = []
	var count := func(id: String) -> void: found.append(id)
	ex.location_discovered.connect(count)
	await _stand(ex.db.travel_point("stone_bridge"))
	await _stand(LocationDB.xz(ex.db.location("stone_bridge")))
	check(ex.is_discovered("stone_bridge") and found.count("stone_bridge") == 1, "walking up to a landmark discovers it", str(found))
	await _stand(Vector2(0, -90))
	await _stand(LocationDB.xz(ex.db.location("stone_bridge")))
	check(found.count("stone_bridge") == 1, "returning does not announce it again")
	ex.location_discovered.disconnect(count)


func _count_named(prefix: String) -> int:
	return ex.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(prefix) and not n.is_queued_for_deletion()).size()


func _lifecycle() -> void:
	await _stand(Vector2(240, 44))
	check(ex.villagers.has("ashford_miller") and ex.pois.has("rest_ashford"), "Ashford's people and bench are there when he is")
	var near_count := ex.get_child_count()
	var bess: StoryNPC = ex.villagers.get("ashford_miller")
	if bess:
		bess.talk.interact(player)
		await frames(60)
	check(int(Persist.entity("talk:ashford_miller").get("count", 0)) == 1 and player.controls_enabled, "a villager can be spoken to and control returns")
	await _stand(Vector2(-200, 205))
	check(not ex.villagers.has("ashford_miller") and not ex.pois.has("rest_ashford"), "they are freed when he is far away")
	check(ex.pois.has("view_watch"), "the watchtower viewpoint activates instead")
	await _stand(Vector2(240, 44))
	check(_count_named("Villager_ashford_miller") == 1 and ex.get_child_count() == near_count, "returning makes no duplicates",
		"%d then %d" % [near_count, ex.get_child_count()])


func _interaction() -> void:
	await _stand(Vector2(210, -96))
	var poi: WorldPoi = ex.pois.get("view_crag")
	if not check(poi != null, "the crag viewpoint exists up there"):
		return
	# The real prompt and the E key path, not just the handler.
	var interactor := player.get_node("Interactor") as PlayerInteractor
	for side: Vector3 in [Vector3(0, 0, 1.6), Vector3(1.6, 0, 0), Vector3(0, 0, -1.6), Vector3(-1.6, 0, 0)]:
		player.teleport(poi.global_position + side + Vector3.UP * 0.2, atan2(side.x, side.z))
		await frames(30)
		if interactor.focused == poi.trigger:
			break
	check(interactor.focused == poi.trigger, "facing it shows its prompt", str(interactor.focused))
	check(interactor.try_interact(), "and interacting works")
	await frames(60)
	check(ex.used.has("view_crag") and ex.is_discovered("northmere") and ex.is_discovered("ashford"),
		"taking in the view marks places on the map")
	await _stand(Vector2(55, -37))
	player.combatant.set_health(40)
	check(ex.rest("Hunter's Camp") and player.combatant.health == player.combatant.max_health, "resting heals and saves")
	check(Persist.peek_section("exploration", SAVE).get("used", []).has("view_crag"), "and the save holds the interaction")


func _encounter() -> void:
	var enc: WorldEncounter = ex.encounters["patrol_forest_road"]
	var c := enc.center()
	check(not enc.is_active(), "a distant patrol does not exist")
	await _stand(Vector2(c.x - 40, c.z), 90)
	check(enc.is_active() and enc.living().size() == 2 and not enc.fighting, "it appears, waiting, as he approaches")
	check(enc.living()[0].avatar.global_position.distance_to(c) < 10.0, "the patrol stands where authored")
	await _stand(Vector2(c.x - 7, c.z), 90)
	check(enc.fighting and ex.in_combat(), "coming close starts the fight")
	check(ex.can_save() != "" and ex.save_game().contains("fight"), "no saving mid-fight")
	var committed := {}
	var struck := false
	var health := player.combatant.health
	for i in 600:
		Combat.heal_player(player.player_id, 100)
		await get_tree().physics_frame
		if Combat.swords.token_actor >= 0:
			committed[Combat.swords.token_actor] = true
			struck = true
		if struck and i > 200:
			break
	var director = Combat.enemy_director
	check(director != null and director.members.size() >= 1, "campaign combat direction takes the patrol")
	check(struck, "the patrol attacks through the single attack token", "%d attackers over time, health %d" % [committed.size(), health])
	var first: SoldierBrain = enc.living()[0]
	var hp := first.avatar.combatant.health
	var toward := first.avatar.global_position - player.global_position
	player.teleport(first.avatar.global_position - toward.normalized() * 1.6, atan2(-toward.x, -toward.z))
	var accepted := false
	for i in 400:
		Combat.heal_player(player.player_id, 100)
		var d := first.avatar.global_position - player.global_position
		if d.length() > 2.2:
			player.teleport(first.avatar.global_position - d.normalized() * 1.5, atan2(-d.x, -d.z))
		else:
			player.set_look(atan2(-d.x, -d.z))
		if i % 20 == 0:
			var r: Dictionary = _abilities().trigger("attack")
			accepted = accepted or bool(r.get("ok", false))
		await get_tree().physics_frame
		if first.avatar.combatant.health < hp:
			break
	check(accepted and first.avatar.combatant.health < hp, "the Commander's swords hurt open-world enemies",
		"%d -> %d" % [hp, first.avatar.combatant.health])
	Combat.apply_damage(first.avatar.player_id, 9999, player.player_id, "test")
	await frames(20)
	check(Persist.entity("enc:patrol_forest_road").get("dead", []).size() == 1, "a death is recorded under the encounter id")
	await _stand(Vector2(240, 44), 90)
	check(not enc.is_active() and not ex.in_combat(), "leaving far behind releases the actors")
	await _stand(Vector2(c.x - 40, c.z), 90)
	check(enc.living().size() == 1, "the fallen enemy stays fallen", "%d living" % enc.living().size())
	await _stand(Vector2(c.x - 7, c.z), 60)
	var done: Array = []
	enc.cleared.connect(func(id: String) -> void: done.append(id))
	for b in enc.living():
		Combat.apply_damage(b.avatar.player_id, 9999, player.player_id, "test")
	await frames(40)
	check(done == ["patrol_forest_road"] and WorldEncounter.is_cleared("patrol_forest_road"), "clearing is recorded once")
	await _stand(Vector2(240, 44), 90)
	await _stand(Vector2(c.x - 40, c.z), 90)
	check(not enc.is_active(), "a cleared encounter never returns")
	# A fall wakes him at a known safe place, not in the middle of the fight.
	var wake: Vector3 = main._respawn_point(player.player_id, c)
	check(wake.distance_to(c) > 30.0 and ex.respawn_point(c) == wake, "he wakes at a discovered safe place", str(wake))
	Combat.apply_damage(player.player_id, 9999, -1, "test")
	await frames(900)
	check(not player.is_defeated and player.controls_enabled, "death and respawn return control", str(player.global_position))


func _abilities() -> PlayerAbilities:
	for c in player.get_children():
		if c is PlayerAbilities:
			return c
	return null


func _horse_and_map() -> void:
	var horse: Horse = main.horse
	horse.teleport(ex.place(Vector2(240, 46)), 0.0)
	await _stand(Vector2(-228, 72), 60)
	check(horse.global_position.distance_to(player.global_position) > 100.0, "the horse is far behind")
	await main.call_horse()
	await frames(30)
	check(horse.global_position.distance_to(player.global_position) < 8.0, "H brings the same horse across the kingdom",
		"%.1f m" % horse.global_position.distance_to(player.global_position))
	check(main.find_children("*", "Horse", false, false).size() == 1, "there is still exactly one horse")
	var map: WorldMap = main.world_map
	check(map.open() and get_tree().paused, "the map opens and pauses the game")
	await get_tree().process_frame
	var p := Vector3(58, world.terrain_height(58, 172), 172)
	var back := map.map_to_world(map.world_to_map(p))
	check(back.distance_to(p) < 0.5, "map coordinates are world coordinates")
	map.set_zoom(2.5, map.world_to_map(p))
	check(map.map_to_world(map.world_to_map(p)).distance_to(p) < 0.5 and map.world_to_map(Vector3(0, 0, -100)).y < map.world_to_map(Vector3.ZERO).y,
		"zoomed, they still match and north is up")
	map.mark(map.world_to_map(p))
	check(ex.waypoint.distance_to(p) < 0.5 and ex.guidance_target() == ex.waypoint, "a click marks a destination")
	map.close()
	check(not get_tree().paused and not map.is_open(), "closing resumes the game")
	check(is_equal_approx(CompassHud.bearing(Vector3(0, 0, -1)), 0.0) and is_equal_approx(CompassHud.bearing(Vector3(1, 0, 0)), PI * 0.5),
		"compass bearings: north and east")
	check(main.compass.guide() and main.compass.gusting(), "the wind blows toward the mark")


func _save_and_reload(v1_text: String) -> void:
	var campaign: CampaignDirector = main.campaign
	await _stand(Vector2(-266, 72), 90)
	check(ex.is_discovered("great_gate") and ex.is_discovered("war_plains"), "the Great Gate approach is reached and recorded")
	var result: Dictionary = campaign.escort.summon(campaign.army.living())
	campaign.deployed = bool(result.ok)
	var escort_ids: Array = campaign.escort.living().map(func(b) -> int: return b.soldier_id)
	check(result.ok, "an escort is with him", str(escort_ids))
	var wounded: SoldierBrain = campaign.escort.living()[0]
	var wounded_id := wounded.soldier_id
	Combat.apply_damage(wounded.avatar.player_id, 9999, -1, "test")
	await frames(20)
	escort_ids.erase(wounded_id)
	player.combatant.set_health(77)
	await main.call_horse()
	await frames(60)
	var at := player.global_position
	var horse_at: Vector3 = main.horse.global_position
	var found := ex.discovered.size()
	var alive := campaign.state.alive_count()
	check(ex.save_game() == "Game saved.", "manual save works")
	await _shutdown()
	await _boot()
	check(Persist.status == "loaded", "the world save is loaded next time", Persist.status)
	check(player.global_position.distance_to(at) < 1.5, "he returns where he saved", "%.2f m" % player.global_position.distance_to(at))
	check(player.is_on_floor() and player.controls_enabled, "standing on solid ground with control")
	check(player.combatant.health >= 77 and player.combatant.health < 100, "health is restored", str(player.combatant.health))
	check(ex.discovered.size() == found, "discoveries survive", "%d / %d" % [ex.discovered.size(), found])
	check(WorldEncounter.is_cleared("patrol_forest_road"), "the cleared encounter stays cleared")
	check(main.horse.global_position.distance_to(horse_at) < 2.5, "the horse is where he left it")
	check(main.campaign.state.alive_count() == alive, "casualties persist", "%d / %d" % [main.campaign.state.alive_count(), alive])
	var now: Array = main.campaign.escort.living().map(func(b) -> int: return b.soldier_id)
	now.sort()
	escort_ids.sort()
	check(now == escort_ids and not now.has(wounded_id), "the same living soldiers are his escort", "%s / %s" % [now, escort_ids])
	check(main.campaign.state.coins == 55, "campaign progress survives")
	check(FileAccess.get_file_as_string(V1) == v1_text, "the old save is still untouched")


func _recovery() -> void:
	main.save_on_exit()
	var at := player.global_position
	await _shutdown()
	_write(SAVE, "garbage")
	await _boot()
	check(Persist.status == "recovered", "a damaged save falls back to a backup", Persist.status)
	check(player.global_position.distance_to(at) < 3.0 and WorldEncounter.is_cleared("patrol_forest_road"), "with progress intact")
	await _shutdown()
	# A saved position that no longer exists: safe place instead, everything else kept.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SAVE + ".bak1"))
	data["sections"]["player"]["position"] = [5000, 12, -5000]
	data["sections"]["exploration"]["discovered"].append("a_place_that_was_removed")
	_write(SAVE, JSON.stringify(data))
	await _boot()
	check(world.terrain_data.in_playable(player.global_position.x, player.global_position.z, 0.5) and player.is_on_floor(),
		"an impossible saved position becomes a safe one", str(player.global_position))
	check(ex.is_discovered("great_gate") and not ex.is_discovered("a_place_that_was_removed") and main.campaign.state.coins == 55,
		"without losing other progress")


class SlowStreamer:
	var prepared := 0
	var answer := false
	func prepare(_p: Vector3) -> void:
		prepared += 1
	func is_ready(_p: Vector3) -> bool:
		return answer


func _relocation() -> void:
	var streamer := SlowStreamer.new()
	ex.relocator.provider = streamer
	var res: Dictionary = await ex.relocator.relocate(Vector3(246, world.terrain_height(246, 42), 42))
	check(streamer.prepared == 1 and res.ok and res.fallback, "terrain that never loads ends in a safe fallback")
	check(player.locks.token_count() == 0, "control is always returned")
	streamer.answer = true
	var want := ex.place(Vector2(246, 42))
	res = await ex.relocator.relocate(want)
	check(res.ok and not res.fallback and (res.position as Vector3).distance_to(want) < 1.0, "ready terrain is used")
	ex.relocator.provider = null
	var blocked := {"on": true}
	ex.content_allowed = func(_p: Vector3) -> bool: return not blocked.on
	await frames(40)
	check(ex.pois.is_empty() and ex.villagers.is_empty(), "streaming can withhold content")
	ex.content_allowed = Callable()
	await frames(40)
	check(not ex.pois.is_empty(), "and release it again")


# --- the round 3 journey ------------------------------------------------------------------------

## Rides (or walks) the road network to `goal` with real physics.
func _travel(goal: Vector2, mounted: bool) -> Dictionary:
	var to := ex.place(goal)
	var path: PackedVector3Array = main.campaign.route.route(player.global_position, to)
	var horse: Horse = main.horse
	var stuck := 0.0
	var check_at := player.global_position
	var falls := 0
	var elapsed := 0.0
	var i := 0
	var reverse := 0.0
	while i < path.size():
		var body: Node3D = horse if mounted else player
		var target := path[i]
		var d := Vector3(target.x - body.global_position.x, 0, target.z - body.global_position.z)
		if d.length() < (3.5 if mounted else 1.8):
			i += 1
			continue
		if mounted:
			var ang := horse.forward().signed_angle_to(d.normalized(), Vector3.UP)
			var steer := clampf(-ang * 2.0, -1.0, 1.0)
			var forward := 1.0 if absf(ang) < 1.0 else 0.35
			if reverse > 0.0:
				reverse -= 1.0 / 60.0
				steer = 1.0
				forward = -1.0
			player.input_override = {"move": Vector2(steer, forward), "sprint": false}
		else:
			player.set_look(atan2(-d.x, -d.z))
			player.input_override = {"move": Vector2(1.0 if reverse > 0.0 else 0.0, 1), "sprint": true, "jump": reverse > 0.0, "jump_pressed": reverse > 0.9}
			reverse = maxf(0.0, reverse - 1.0 / 60.0)
		Combat.heal_player(player.player_id, 100)
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		stuck += 1.0 / 60.0
		if player.global_position.y < world.terrain_height(player.global_position.x, player.global_position.z) - 3.0:
			falls += 1
		if stuck > 3.0:
			if player.global_position.distance_to(check_at) < 2.0:
				reverse = 1.0
			stuck = 0.0
			check_at = player.global_position
		if OS.get_cmdline_user_args().has("--trace") and int(elapsed * 60.0) % 600 == 0:
			print("  trace ", body.global_position.snapped(Vector3.ONE * 0.1), " wp ", i, "/", path.size(), " ", target.snapped(Vector3.ONE))
		if elapsed > 150.0:
			break
	player.input_override = {}
	await frames(60)
	var left := Vector2(player.global_position.x - to.x, player.global_position.z - to.z).length()
	return {"ok": left < 9.0 and falls == 0, "detail": "%.0f s, %.1f m short, %d frames under ground, at %s" % [elapsed, left, falls, player.global_position.snapped(Vector3.ONE)]}


func _journey() -> void:
	_wipe()
	await _shutdown()
	await _boot()
	main.campaign.opening_completed = true
	if main.castle_opening:
		main.castle_opening.queue_free()
		main.castle_opening = null
	player.controls_enabled = true
	# On foot from the courtyard, out through the gate and down the approach stair.
	var sites := world.get_node("Sites/Structures") as Sites
	var o := sites.castle_origin
	var g := sites.castle_gate_z
	player.teleport(main.story.anchor_pos("castle_courtyard") + Vector3.UP * 0.2)
	await frames(20)
	var driver := PlayerDriver.new(player)
	var out: Dictionary = await driver.walk([o + Vector3(-34, 0, g), o + Vector3(-57, 0, g), o + Vector3(-74, 0, g)], {"reach": 1.0})
	player.input_override = {}
	check(out.ok, "journey: leave the castle on foot", out.reason)
	var horse: Horse = main.horse
	await main.call_horse()
	for i in 900:
		if horse.global_position.distance_to(player.global_position) < 6.0 and not horse.is_recalled():
			break
		await get_tree().physics_frame
	check(horse.global_position.distance_to(player.global_position) < 8.0, "journey: the horse answers outside the castle",
		"%.1f m" % horse.global_position.distance_to(player.global_position))
	horse.stop_recall()
	var rider := player.get_node("Rider") as Rider
	horse.speed = 0.0
	rider.mount(horse)
	await frames(300)
	check(rider.state == Rider.State.RIDING, "journey: mounted")
	var legs := [["Golden Valley", Vector2(104, 206)], ["Southbank", Vector2(80, 232)], ["Stone Bridge", Vector2(44, 164)],
		["back over the bridge", Vector2(96, 182)], ["Castle Square", Vector2(231, 100)], ["Ashford", Vector2(240, 46)],
		["Northmere", Vector2(144, -78)], ["North Bridge", Vector2(76, -150)], ["forest road patrol", Vector2(-132, 21)],
		["the Great Gate", Vector2(-266, 70)]]
	for leg in legs:
		if rider.state != Rider.State.RIDING:
			rider.force_dismount()
			horse.teleport(player.global_position + player.global_basis.x * 2.0, player.rotation.y)
			await frames(20)
			rider.mount(horse)
			await frames(300)
		var r := await _travel(leg[1], true)
		if not check(r.ok, "journey: ride to " + String(leg[0]), r.detail):
			# Carry on from the intended place so later legs are still measured.
			rider.force_dismount()
			await _stand(leg[1], 30)
			horse.teleport(ex.place(leg[1] + Vector2(3, 0)), player.rotation.y)
			await frames(20)
			rider.mount(horse)
			await frames(300)
	rider.force_dismount()
	await frames(30)
	check(main.find_children("*", "Horse", false, false).size() == 1, "journey: still one horse")
	var walk := await _travel(Vector2(-232, 70), false)
	check(walk.ok, "journey: walk the War Plains", walk.detail)
	check(ex.discovered.size() >= 8, "journey: places discovered along the way", str(ex.discovered.keys()))
	check(ex.save_game() == "Game saved.", "journey: save at the gate", ex.can_save())
	var at := player.global_position
	await _shutdown()
	await _boot()
	check(player.global_position.distance_to(at) < 1.5, "journey: reload at the same place")
	var walk_back := await _travel(Vector2(-190, 13), false)
	check(walk_back.ok, "journey: set off home along the road", walk_back.detail)
