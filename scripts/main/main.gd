extends Node
## Match bootstrap: generates the world, validates spawns, places the scroll,
## spawns the local player and simulated opponents, and wires UI and
## developer tools.

signal ready_for_play

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HORSE_SCENE := preload("res://scenes/horse/horse.tscn")
const CAVE_STORY_SCROLL_SCENE := preload("res://scenes/interactables/cave_story_scroll.tscn")

## Tests turn this off so headless runs never grab the mouse.
@export var auto_capture_mouse := true
## Spawn simulated opponents (count from GameState.bot_count / --bots=N).
@export var spawn_bots := true
## The commander's warhorse, saddled beside him at the start.
@export var spawn_horse := true
## The campaign (King, army, missions). Tests keep it but do not read or write the save.
@export var spawn_campaign := true
@export var campaign_persist := true
## Villagers and open-world enemy groups (suites that test other systems turn it off).
@export var world_life := true
@export var enable_opening := true
var castle_opening: Node

var player_spawns: Array[Vector3] = []
var bots: Array[PlayerController] = []
var probe: SightProbe
var story: StoryDirector
var campaign: CampaignDirector
var exploration: ExplorationDirector
var world_map: WorldMap
var compass: CompassHud
var horse: Horse
var recall: HorseRecall
var healing_loot: HealingLoot
var cave_story_scroll: CaveStoryScroll
var _poi_index := -1
var _bot_serial := 0

@onready var world: World = $World
@onready var player: PlayerController = $Player
@onready var hud: HUD = $HUD
@onready var combat_hud: CombatHUD = $CombatHUD
@onready var scroll_spawner: ScrollSpawner = $World/ScrollSpawner
@onready var pause_menu = get_node_or_null("PauseMenu")
@onready var ambience = get_node_or_null("World/Ambience")
@onready var bots_root: Node3D = $Bots


func _ready() -> void:
	hud.show_loading(true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	# Let the loading screen draw before the (blocking) generation step.
	await get_tree().process_frame
	await get_tree().process_frame
	world.generate()
	player.water_level = world.water_level
	# Static bodies are queryable after the next physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_resolve_player_spawns()
	_collect_bot_waypoints()
	scroll_spawner.validate_markers(world)
	scroll_spawner.spawn(GameState.scroll_seed)
	# The original ScrollSpawner owns the single mysterious scroll in the sealed cave.
	# Campaign healing is now automatic; preserve pickup resources for older content.
	Combat.respawn_point_provider = _respawn_point

	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.scroll_seed + 7
	var spawn_index := rng.randi_range(0, player_spawns.size() - 1)
	_spawn_player_at(player_spawns[spawn_index])
	player.fell_out_of_world.connect(respawn_nearest)
	if spawn_horse:
		spawn_horse_near(player)

	hud.attach_player(player)
	hud.debug_lines = _debug_lines
	combat_hud.attach_player(player)
	if ambience:
		ambience.setup(world, player)
	story = StoryDirector.new()
	story.name = "Story"
	add_child(story)
	story.setup(world, player, hud)
	# Only a real, persisting game opens the save; everything else stays in memory.
	if spawn_campaign and campaign_persist and not GameState.args.has("no-campaign-save"):
		Persist.begin_session()
		if GameState.args.has("new-campaign"):
			for key in ["campaign", "player", "horse", "exploration", "story", "escort", "entities", "flags"]:
				Persist.erase_section(key)
	else:
		Persist.end_session()
	if spawn_campaign:
		campaign = CampaignDirector.new()
		campaign.name = "Campaign"
		add_child(campaign)
		campaign.setup(self, world, player, hud, story, campaign_persist)
	if enable_opening and (campaign == null or not campaign.opening_completed):
		start_castle_opening()
	elif enable_opening:
		# Resumed campaigns must still reach the bedroom's existing night story.
		var sites := world.get_node("Sites/Structures") as Sites
		(sites.bedroom_door.get_node("OpenBedroomDoor") as Interactable).interact(player)
	exploration = ExplorationDirector.new()
	exploration.name = "Exploration"
	add_child(exploration)
	exploration.setup(self, world, player, hud, story, campaign, world_life)
	compass = CompassHud.new()
	compass.name = "Compass"
	add_child(compass)
	compass.setup(exploration)
	world_map = WorldMap.new()
	world_map.name = "WorldMap"
	add_child(world_map)
	world_map.setup(exploration)
	if Persist.active:
		await exploration.apply_saved()
		exploration.register_save_sections()
		if Persist.status == "migrated":
			hud.toast("Your earlier campaign has been carried over.", 4.0)
		elif Persist.status == "recovered":
			hud.toast("The save was damaged; the previous one has been restored.", 5.0)
	if pause_menu:
		pause_menu.main = self
	_return_from_visit()
	if spawn_bots:
		for i in GameState.bot_count:
			var p := player_spawns[(spawn_index + 1 + i * 2) % player_spawns.size()]
			spawn_bot(p + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)), SimBot.Role.WANDERER, i % 2 == 0)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	hud.show_loading(false)
	if auto_capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_for_play.emit()


## Back from DevVisit: stand where the Commander left, if the opening is behind him.
func _return_from_visit() -> void:
	if not GameState.has_meta(DevVisit.META_RETURN):
		return
	var back: Dictionary = GameState.get_meta(DevVisit.META_RETURN)
	GameState.remove_meta(DevVisit.META_RETURN)
	if castle_opening != null:
		return
	player.teleport(back["position"] + Vector3.UP * 0.1, back["yaw"])
	if horse:
		spawn_horse_near(player)


func _place_cave_story_scroll() -> void:
	var markers := world.layout.list("scroll_spawns")
	for marker in markers:
		if String(marker.get("name", "")) != "cave_chamber":
			continue
		var point := WorldLayout.v2(marker["pos"])
		var clue := CAVE_STORY_SCROLL_SCENE.instantiate() as CaveStoryScroll
		world.add_child(clue)
		clue.global_position = Vector3(point.x + 2.0, world.terrain_data.cave.get("floor", world.terrain_height(point.x, point.y)) + 0.12, point.y)
		cave_story_scroll = clue
		return
	push_warning("Main: cave chamber marker was not found; the story scroll was not placed")


func _resolve_player_spawns() -> void:
	player_spawns.clear()
	for p in world.layout.list("player_spawns"):
		var res := SpawnValidator.find(world, WorldLayout.v2(p), NAN, 16.0)
		if res["ok"]:
			player_spawns.append(res["position"])
		else:
			push_warning("Player spawn %s rejected: %s" % [str(p), res["reason"]])
	if player_spawns.is_empty():
		push_error("No valid player spawns; using map centre")
		player_spawns.append(Vector3(0, world.terrain_height(0, 0) + 1.0, 0))


func _collect_bot_waypoints() -> void:
	var pts := PackedVector3Array()
	for t in world.layout.list("trails"):
		var poly := WorldLayout.points(t["points"])
		for i in poly.size() - 1:
			var n := maxi(1, int(poly[i].distance_to(poly[i + 1]) / 10.0))
			for k in n:
				var p := poly[i].lerp(poly[i + 1], float(k) / n)
				pts.append(Vector3(p.x, world.terrain_height(p.x, p.y), p.y))
	SimBot.waypoints = pts


## Faces the player towards the map centre so the landmark is in view.
func _spawn_player_at(pos: Vector3) -> void:
	var to_centre := Vector3(-pos.x, 0, -pos.z)
	var yaw := atan2(-to_centre.x, -to_centre.z)
	player.teleport(pos + Vector3.UP * 0.1, yaw)


func respawn_nearest() -> void:
	var best := player_spawns[0]
	for s in player_spawns:
		if s.distance_to(player.global_position) < best.distance_to(player.global_position):
			best = s
	_spawn_player_at(best)
	hud.toast("You find your bearings again.")


## Respawn point for Combat: the valid spawn farthest from where the player fell.
func _respawn_point(player_id: int, avoid: Vector3) -> Vector3:
	if exploration and player_id == player.player_id:
		var known := exploration.respawn_point(avoid)
		if known != Vector3.INF:
			return known
	var best := player_spawns[0]
	for s in player_spawns:
		if s.distance_to(avoid) > best.distance_to(avoid):
			best = s
	return best


## Simulated opponent using the same avatar scene as the player. Every bot
## carries an identical "Brain" node whatever its role, so nothing in the tree
## distinguishes a hunter from a wanderer.
func spawn_bot(pos: Vector3, role: SimBot.Role, brave := false) -> PlayerController:
	_bot_serial += 1
	var bot: PlayerController = PLAYER_SCENE.instantiate()
	bot.is_local = false
	bot.is_bot = true
	bot.display_name = "Wanderer %d" % _bot_serial
	bot.name = "Avatar%d" % _bot_serial
	bot.get_node("Head/Camera3D").current = false
	var brain := SimBot.new()
	brain.name = "Brain"
	brain.role = role
	brain.brave = brave
	bot.add_child(brain)
	bots_root.add_child(bot)
	bot.water_level = world.water_level
	var res := SpawnValidator.find(world, Vector2(pos.x, pos.z), pos.y + 3.0, 8.0)
	bot.teleport((res["position"] if res["ok"] else pos) + Vector3.UP * 0.1)
	if role == SimBot.Role.HUNTER:
		GameState.grant_monster_for_testing(bot.player_id)
	bots.append(bot)
	return bot


## Stands the horse a few paces to the player's right, facing the same way, on open
## ground (never inside a wall or the water).
func spawn_horse_near(p: PlayerController) -> Horse:
	if horse == null:
		horse = HORSE_SCENE.instantiate()
		horse.name = "Horse"
		add_child(horse)
		horse.water_level = world.water_level
		horse.enable_self_dormancy()
	var right := p.global_transform.basis.x
	right.y = 0.0
	for d in [3.2, -3.2, 4.5, -4.5, 6.0]:
		var want := p.global_position + right.normalized() * float(d)
		var res := SpawnValidator.find(world, Vector2(want.x, want.z), want.y + 2.0, 3.0)
		if res["ok"] and world.terrain_height(want.x, want.z) > world.water_level + 0.3:
			horse.teleport(res["position"] + Vector3.UP * 0.05, p.rotation.y)
			return horse
	# Keep the current safe location if no valid nearby placement exists.
	return horse


## The whistle (H): see HorseRecall.
func call_horse() -> void:
	if horse == null:
		return
	if recall == null:
		recall = HorseRecall.new()
		recall.name = "HorseRecall"
		add_child(recall)
		recall.setup(player, horse, world.water_level)
	await recall.call_horse()


## Writes the world save when the window is closed (if this is a safe moment).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_on_exit()


func save_on_exit() -> void:
	if not Persist.active or exploration == null:
		return
	if campaign:
		campaign.army.sync_to_state()
	Persist.save("exit")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		hud.toggle_debug()
	if event.is_action_pressed("call_horse") and not event.is_echo():
		call_horse()
	if not GameState.dev_mode:
		return
	if event.is_action_pressed("debug_noclip"):
		player.set_noclip(not player.noclip)
		hud.toast("Noclip %s" % ("on" if player.noclip else "off"), 1.5)
	elif event.is_action_pressed("debug_teleport"):
		_teleport_next_poi()
	elif event.is_action_pressed("debug_scroll"):
		_teleport_to_scroll()
	elif event.is_action_pressed("debug_los_probe"):
		_drop_probe()
	elif event.is_action_pressed("debug_spawn_monster"):
		spawn_bot(player.global_position - player.forward() * 18.0, SimBot.Role.HUNTER)
		hud.toast("[Dev] A test hunter is stalking you", 2.5)
	elif event.is_action_pressed("debug_grant_monster"):
		if GameState.grant_monster_for_testing(player.player_id):
			hud.toast("[Dev] You now hold the Ember Beast", 2.5)
	elif event.is_action_pressed("debug_spawn_humans"):
		for i in 3:
			var a := TAU * i / 3.0
			spawn_bot(player.global_position + Vector3(cos(a), 0, sin(a)) * 9.0, SimBot.Role.WANDERER, i == 0)
		hud.toast("[Dev] Three wanderers nearby", 2.0)


func _teleport_next_poi() -> void:
	var pois := world.layout.list("points_of_interest")
	_poi_index = (_poi_index + 1) % pois.size()
	var poi: Dictionary = pois[_poi_index]
	var poi_pos := WorldLayout.v2(poi["pos"])
	if poi["name"] == "Lakeside Castle Gate":
		poi_pos.y = (world.get_node("Sites/Structures") as Sites).castle_origin.z + (world.get_node("Sites/Structures") as Sites).castle_gate_z
	var res := SpawnValidator.find(world, poi_pos, world.resolve_y_hint(poi.get("y_hint", "")), 10.0)
	if res["ok"]:
		player.teleport(res["position"] + Vector3.UP * 0.1)
		hud.toast("[Dev] %s" % poi["name"], 2.0)


func _teleport_to_scroll() -> void:
	if GameState.scroll_is_collected:
		hud.toast("[Dev] The scroll has already been taken.", 2.0)
		return
	var target := GameState.scroll_position
	var res := SpawnValidator.find(world, Vector2(target.x + 3.0, target.z), target.y + 2.0, 6.0)
	if res["ok"]:
		var pos: Vector3 = res["position"]
		var d := target - pos
		player.teleport(pos + Vector3.UP * 0.1, atan2(-d.x, -d.z))
		hud.toast("[Dev] Teleported beside the scroll (%s)" % GameState.scroll_marker, 2.0)


func _drop_probe() -> void:
	if probe and is_instance_valid(probe):
		probe.queue_free()
		probe = null
		hud.toast("[Dev] Sight probe removed", 1.5)
		return
	probe = SightProbe.new()
	world.add_child(probe)
	probe.global_position = player.eye_position()
	probe.target = player
	hud.toast("[Dev] Sight probe placed - walk behind cover to hide", 3.0)


## Overlay lines. Identity details only appear in developer builds and only
## for the local player's own state; other players are never described.
func _debug_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	out.append("region %s" % world.region_name(player.global_position))
	out.append("world seed %d   scroll seed %d   scroll %s" % [GameState.world_seed, GameState.scroll_seed,
		"taken" if GameState.scroll_is_collected else "in the world"])
	if probe and is_instance_valid(probe):
		out.append("sight probe: %s (%d%% of body visible)" % ["SEES YOU" if probe.is_target_visible else "hidden", int(probe.fraction * 100)])
	if GameState.dev_mode:
		out.append("[dev] you: %s" % PlayerState.name_of(GameState.get_state(player.player_id)))
		out.append("[dev] F4 probe  F6 POI  F7 scroll  F8 noclip  F9 hunter  F10 monster  F11 wanderers")
	return out


func start_castle_opening() -> void:
	if castle_opening == null:
		castle_opening = preload("res://scripts/story/castle_opening.gd").new()
		castle_opening.name = "CastleOpening"
		add_child(castle_opening)
	castle_opening.begin(story, campaign)
	# Stable the existing warhorse outside; never spawn it in the bedroom.
	if is_instance_valid(horse):
		var sites := world.get_node("Sites/Structures") as Sites
		horse.global_position = sites.castle_to_world(Vector3(16, 0.6, 16))
