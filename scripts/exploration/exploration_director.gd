class_name ExplorationDirector
extends Node
## The gameplay layer of the open world: discovery, nearby content (interactions,
## villagers, encounters), resting, the waypoint, safe relocation, and what the world
## save holds about the Commander.
##
## Nothing here runs per object: a 4 Hz tick compares distances and creates or frees
## content. Streaming (Codex) can read focus() for the travel direction, gate content
## with `content_allowed`, and gate relocation through `relocator.provider`.

signal location_discovered(id: String)
signal location_entered(id: String)
signal location_exited(id: String)
signal content_activated(key: String)
signal content_deactivated(key: String)
signal waypoint_changed(position: Vector3)

const TICK := 0.25
## [activate within, deactivate beyond] metres.
const POI_RANGE := [45.0, 62.0]
const LIFE_RANGE := [60.0, 85.0]
const ENCOUNTER_RANGE := [75.0, 115.0]
const LOOK_AHEAD_SECONDS := 2.0
const REST_ENEMY_DISTANCE := 35.0

var main: Node
var world: World
var player: PlayerController
var hud: HUD
var story: StoryDirector
var campaign: CampaignDirector
var db: LocationDB
var relocator: SafeRelocator
## Optional (Vector3) -> bool: false while a streaming system has that ground unloaded.
var content_allowed: Callable
## Villagers and encounters (tests of other systems switch this off).
var world_life := true

var discovered := {}  ## location id -> true
var used := {}  ## interaction id -> true
var current_location := ""
var waypoint := Vector3.INF
var encounters := {}  ## id -> WorldEncounter
var pois := {}  ## id -> WorldPoi (active only)
var villagers := {}  ## id -> StoryNPC (active only)

var _tick := 0.0
var _banner: Label
var _detail: Label
var _banner_tween: Tween
var _chime: AudioStreamPlayer
var _save_wanted := ""


func setup(p_main: Node, p_world: World, p_player: PlayerController, p_hud: HUD,
		p_story: StoryDirector, p_campaign: CampaignDirector, p_life := true) -> void:
	main = p_main
	world = p_world
	player = p_player
	hud = p_hud
	story = p_story
	campaign = p_campaign
	world_life = p_life
	db = LocationDB.load_default()
	relocator = SafeRelocator.new()
	relocator.name = "Relocator"
	add_child(relocator)
	relocator.setup(world, player, safe_points)
	for cfg in db.encounters():
		var encounter := WorldEncounter.new().setup(cfg, world, player)
		add_child(encounter)
		encounter.cleared.connect(_on_cleared)
		encounters[encounter.id] = encounter
	_build_banner()
	Persist.load_failed.connect(_on_load_failed)
	Persist.save_failed.connect(_on_save_failed)


func _exit_tree() -> void:
	if Persist.load_failed.is_connected(_on_load_failed):
		Persist.load_failed.disconnect(_on_load_failed)
		Persist.save_failed.disconnect(_on_save_failed)
	for key in ["player", "horse", "exploration", "story", "escort"]:
		Persist.unregister_provider(key)


# --- queries ---------------------------------------------------------------------------------

## The travel interface for streaming and preloading.
func focus() -> Dictionary:
	var mounted := player.riding
	var velocity := player.velocity
	var horse: Horse = main.horse
	if mounted and horse:
		velocity = horse.velocity
	return {"position": player.global_position, "velocity": velocity, "mounted": mounted}


func is_discovered(id: String) -> bool:
	return discovered.has(id)


## Enemies are fighting the Commander (world or campaign).
func in_combat() -> bool:
	if campaign and campaign.in_encounter():
		return true
	for encounter: WorldEncounter in encounters.values():
		if encounter.fighting:
			return true
	return false


## Known good places to be put down: discovered safe places, then the start points.
func safe_points() -> Array:
	var out: Array = []
	for loc in db.locations():
		var id := String(loc["id"])
		if bool(loc.get("safe", false)) and discovered.has(id):
			out.append(db.travel_point(id))
	for p in world.layout.list("player_spawns"):
		out.append(WorldLayout.v2(p))
	return out


## Where a fallen Commander wakes: the nearest discovered safe place that is not on top
## of the fight, else Vector3.INF (Main then uses its own spawn points).
func respawn_point(avoid: Vector3) -> Vector3:
	var best := Vector3.INF
	for id in discovered:
		if not db.is_safe(id):
			continue
		var p := db.travel_point(id)
		var res := SpawnValidator.find(world, p, world.terrain_height(p.x, p.y) + 3.0, 8.0, {"edge_margin": 1.0})
		if not res["ok"]:
			continue
		var at: Vector3 = res["position"]
		if at.distance_to(avoid) > 30.0 and at.distance_to(avoid) < best.distance_to(avoid):
			best = at
	return best


func set_waypoint(p: Vector3) -> void:
	waypoint = p
	waypoint_changed.emit(p)


## What the compass and wind point at: the player's mark, else the mission.
func guidance_target() -> Vector3:
	if waypoint != Vector3.INF:
		return waypoint
	return campaign.objective_position() if campaign else Vector3.INF


# --- tick ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	refresh()


## One pass of discovery, content and encounter logic.
func refresh() -> void:
	if world == null or not world.is_generated:
		return
	_update_location()
	_update_content()
	for encounter: WorldEncounter in encounters.values():
		encounter.tick()
	if waypoint != Vector3.INF and _flat(player.global_position, waypoint) < 8.0:
		set_waypoint(Vector3.INF)
	if _save_wanted != "" and can_save() == "":
		var reason := _save_wanted
		_save_wanted = ""
		Persist.save(reason)


## No discovery pop-ups over cinematics, dialogue or a fall.
func _presentable() -> bool:
	return player.controls_enabled and not player.is_defeated and not (story and story.in_dialogue)


func _update_location() -> void:
	var here := db.location_at(player.global_position)
	if here != current_location:
		if current_location != "":
			location_exited.emit(current_location)
		current_location = here
		if here != "":
			location_entered.emit(here)
			if discovered.has(here) and _presentable():
				_show_banner(String(db.location(here)["name"]), "", 1.6)
		_update_audio(here)
	if here != "" and not discovered.has(here) and _presentable():
		discover(here)


func discover(id: String, quiet := false) -> bool:
	var loc := db.location(id)
	if loc.is_empty() or discovered.has(id):
		return false
	discovered[id] = true
	location_discovered.emit(id)
	if not quiet:
		_show_banner(String(loc["name"]), "Discovered - " + String(loc.get("description", "")), 4.0)
		if _chime and _chime.stream:
			_chime.play()
		request_save("discovery")
	return true


func _update_audio(here: String) -> void:
	var ambience = main.ambience
	if ambience and "region_offsets" in ambience:
		ambience.region_offsets = db.location(here).get("audio", _category_audio(here))


func _category_audio(id: String) -> Dictionary:
	match String(db.location(id).get("category", "")):
		"forest", "camp":
			return {"birds": 4.0, "wind": -3.0, "leaves": 3.0}
		"pass", "viewpoint", "defence":
			return {"wind": 5.0, "birds": -4.0}
		"battlefield":
			return {"wind": 4.0, "birds": -12.0, "leaves": -6.0}
		"settlement", "royal":
			return {"wind": -4.0}
		"cave", "ruins":
			return {"birds": -8.0}
	return {}


func _allowed(p: Vector3) -> bool:
	return not content_allowed.is_valid() or bool(content_allowed.call(p))


## True when content at `at` should now exist, given whether it already does.
func _wanted(at: Vector3, ranges: Array, exists: bool) -> bool:
	var f := focus()
	var ahead: Vector3 = f["position"] + (f["velocity"] as Vector3) * LOOK_AHEAD_SECONDS
	var d := minf(_flat(f["position"], at), _flat(ahead, at))
	return d < float(ranges[1 if exists else 0]) and _allowed(at)


func _update_content() -> void:
	for cfg in db.interactions():
		var id := String(cfg["id"])
		var p := LocationDB.xz(cfg)
		var at := Vector3(p.x, world.terrain_height(p.x, p.y), p.y)
		var exists := pois.has(id)
		var want := _wanted(at, POI_RANGE, exists)
		if want and not exists:
			_add_poi(cfg)
		elif exists and not want:
			(pois[id] as WorldPoi).queue_free()
			pois.erase(id)
			content_deactivated.emit("poi:" + id)
	if not world_life:
		return
	for settlement in db.settlements():
		for cfg in settlement.get("villagers", []):
			var id := String(cfg["id"])
			var p := LocationDB.xz(cfg)
			var at := Vector3(p.x, world.terrain_height(p.x, p.y), p.y)
			var exists := villagers.has(id)
			var want := _wanted(at, LIFE_RANGE, exists)
			if want and not exists:
				_add_villager(cfg)
			elif exists and not want:
				(villagers[id] as StoryNPC).queue_free()
				villagers.erase(id)
				content_deactivated.emit("villager:" + id)
	var busy_campaign: bool = campaign != null and (campaign.in_encounter() or main.castle_opening != null and main.castle_opening.active)
	for encounter: WorldEncounter in encounters.values():
		var exists := encounter.is_active()
		var want := not busy_campaign and _wanted(encounter.center(), ENCOUNTER_RANGE, exists)
		if want and not exists and not WorldEncounter.is_cleared(encounter.id):
			encounter.activate()
			content_activated.emit("enc:" + encounter.id)
		elif exists and not want:
			encounter.deactivate()
			content_deactivated.emit("enc:" + encounter.id)


## Solid ground for a prop or a person near a data position.
func place(xz: Vector2) -> Vector3:
	var y := world.terrain_height(xz.x, xz.y)
	var res := SpawnValidator.find(world, xz, y + 3.0, 8.0, {"edge_margin": 1.0, "min_above_water": 0.15})
	return res["position"] if res["ok"] else Vector3(xz.x, y, xz.y)


func _add_poi(cfg: Dictionary) -> void:
	var poi := WorldPoi.new().setup(cfg)
	add_child(poi)
	poi.global_position = place(LocationDB.xz(cfg))
	poi.rotation.y = float(cfg.get("yaw", 0.0))
	poi.used.connect(use_poi)
	pois[poi.id] = poi
	content_activated.emit("poi:" + poi.id)


func use_poi(poi: WorldPoi) -> void:
	if story == null or story.in_dialogue:
		return
	if poi.kind == "rest":
		rest(String(poi.cfg.get("title", "")))
		return
	used[poi.id] = true
	for id in poi.cfg.get("reveals", []):
		discover(String(id), true)
	var title := String(poi.cfg.get("title", ""))
	var lines: Array = []
	for line in poi.cfg.get("lines", []):
		lines.append([title, String(line)])
	if not lines.is_empty():
		await story.play_dialogue(lines)
	if poi_is_view(poi.cfg):
		hud.toast("Places seen from here are marked on your map.", 3.0)
	request_save("interaction")


static func poi_is_view(cfg: Dictionary) -> bool:
	return String(cfg.get("kind", "")) == "view" and not (cfg.get("reveals", []) as Array).is_empty()


## Heals and saves. Refused while enemies are close.
func rest(where: String) -> bool:
	var refused := in_combat()
	for id in Combat.actor_ids():
		var other := Combat.avatar(id)
		if other and other != player and not other.is_defeated and Combat.team_of(id) == Factions.ENEMY \
				and other.global_position.distance_to(player.global_position) < REST_ENEMY_DISTANCE:
			refused = true
	if refused:
		hud.toast("Not with enemies near.", 2.0)
		return false
	Combat.heal_player(player.player_id, player.combatant.max_health)
	var stored := Persist.save("rest")
	hud.toast("You rest%s.%s" % ["" if where == "" else " at " + where, " Progress saved." if stored else ""], 3.0)
	return true


func _add_villager(cfg: Dictionary) -> void:
	var npc := StoryNPC.new()
	npc.name = "Villager_" + String(cfg["id"])
	add_child(npc)
	var style := String(cfg.get("style", "elder"))
	npc.setup(style, "Talk to " + String(cfg["name"]), 1.2 if style == "child" else 1.6)
	npc.global_position = place(LocationDB.xz(cfg))
	npc.rotation.y = float(hash(cfg["id"]) % 628) / 100.0
	npc.talked.connect(_on_villager.bind(npc, cfg))
	villagers[String(cfg["id"])] = npc
	if cfg.has("to"):
		# An authored stroll: no navigation, no decisions.
		var from := npc.global_position
		var to := place(LocationDB.xz(cfg, "to"))
		var seconds := maxf(2.0, from.distance_to(to) / 0.9)
		var walk := npc.create_tween().set_loops()
		walk.tween_callback(npc.face.bind(to))
		walk.tween_property(npc, "global_position", to, seconds)
		walk.tween_interval(3.0)
		walk.tween_callback(npc.face.bind(from))
		walk.tween_property(npc, "global_position", from, seconds)
		walk.tween_interval(4.0)
	content_activated.emit("villager:" + String(cfg["id"]))


func _on_villager(_by: Node, npc: StoryNPC, cfg: Dictionary) -> void:
	if story.in_dialogue:
		return
	var lines: Array = cfg.get("lines", [])
	if lines.is_empty():
		return
	var key := "talk:" + String(cfg["id"])
	var i := int(Persist.entity(key).get("count", 0))
	Persist.set_entity(key, {"count": i + 1})
	npc.face(player.global_position)
	await story.play_dialogue([[String(cfg["name"]), String(lines[i % lines.size()])]], npc, npc)


func _on_cleared(id: String) -> void:
	hud.toast("The road is safe again.", 3.0)
	request_save("encounter:" + id)


# --- saving ----------------------------------------------------------------------------------

## Why a save is refused right now ("" = fine).
func can_save() -> String:
	if main.castle_opening != null and main.castle_opening.active:
		return "The morning has not yet begun."
	if in_combat():
		return "You cannot save during a fight."
	if player.is_defeated or not player.controls_enabled or (story and story.in_dialogue) or relocator.busy:
		return "You cannot save right now."
	if player.noclip or player.is_swimming or (not player.is_on_floor() and not player.riding):
		return "Find solid ground first."
	return ""


## Saves at the next safe moment.
func request_save(reason: String) -> void:
	_save_wanted = reason


## Manual save. Returns a message for the player.
func save_game() -> String:
	if not Persist.active:
		return "Saving is switched off in this session."
	var why := can_save()
	if why != "":
		return why
	if campaign:
		campaign.army.sync_to_state()
		campaign.save()
	return "Game saved." if Persist.save("manual") else "The save could not be written."


## Registers what the world adds to the save. Call after apply_saved().
func register_save_sections() -> void:
	Persist.register_provider("player", snapshot_player)
	Persist.register_provider("horse", snapshot_horse)
	Persist.register_provider("exploration", snapshot_exploration)
	Persist.register_provider("story", snapshot_story)
	Persist.register_provider("escort", snapshot_escort)


## Position is only taken at safe moments; otherwise the last safe one is kept.
func snapshot_player() -> Dictionary:
	if can_save() != "":
		return {}
	var p := player.global_position
	return {"position": [p.x, p.y, p.z], "yaw": player.rotation.y, "health": player.combatant.health,
		"mounted": player.riding, "location": current_location, "world_seed": GameState.world_seed}


func snapshot_horse() -> Dictionary:
	var horse: Horse = main.horse
	if horse == null or not is_instance_valid(horse):
		return {}
	var p := horse.global_position
	return {"position": [p.x, p.y, p.z], "yaw": horse.rotation.y}


func snapshot_exploration() -> Dictionary:
	var d := {"discovered": discovered.keys(), "used": used.keys()}
	d["waypoint"] = [] if waypoint == Vector3.INF else [waypoint.x, waypoint.y, waypoint.z]
	return d


## Only finished story sequences: a half-done one restarts cleanly.
func snapshot_story() -> Dictionary:
	if story == null:
		return {}
	return {"child_quest_done": story.has_flag("child_quest_done"), "rooftop_talk_done": story.has_flag("rooftop_talk_done")}


func snapshot_escort() -> Dictionary:
	if campaign == null:
		return {}
	var members: Array = []
	if campaign.deployed:
		for b in campaign.escort.living():
			var p: Vector3 = b.avatar.global_position
			members.append({"id": b.soldier_id, "position": [p.x, p.y, p.z], "yaw": b.avatar.rotation.y})
	return {"deployed": not members.is_empty(), "members": members}


## Restores the world from the open save. Awaitable. The world stays quiet meanwhile, so
## nothing is discovered or activated around the temporary start position.
func apply_saved() -> void:
	set_physics_process(false)
	await _apply_saved()
	set_physics_process(true)


func _apply_saved() -> void:
	var seen := Persist.section("exploration")
	discovered.clear()
	for id in seen.get("discovered", []):
		# A place that no longer exists is simply forgotten; everything else stays.
		if not db.location(String(id)).is_empty():
			discovered[String(id)] = true
	used.clear()
	for id in seen.get("used", []):
		used[String(id)] = true
	var mark: Array = seen.get("waypoint", [])
	waypoint = _v3(mark) if mark.size() == 3 else Vector3.INF
	_restore_story(Persist.section("story"))
	var saved := Persist.section("player")
	var fresh_opening: bool = main.castle_opening != null and main.castle_opening.active
	if saved.is_empty() or fresh_opening:
		return
	var res: Dictionary = await relocator.relocate(_v3(saved.get("position", [])), float(saved.get("yaw", 0.0)))
	if bool(res["fallback"]):
		hud.toast("The land has changed. You find yourself on familiar ground.", 4.0)
	var health := int(saved.get("health", 0))
	if health > 0:
		player.combatant.set_health(mini(health, player.combatant.max_health))
	_restore_horse(Persist.section("horse"), bool(saved.get("mounted", false)) or bool(res["fallback"]))
	_restore_escort(Persist.section("escort"))
	current_location = db.location_at(player.global_position)


func _restore_horse(saved: Dictionary, beside: bool) -> void:
	var horse: Horse = main.horse
	if horse == null:
		return
	var at := _v3(saved.get("position", []))
	if not beside and at.is_finite() and world.terrain_data.in_playable(at.x, at.z, 0.5):
		var yaw := float(saved.get("yaw", 0.0))
		var ground := SafeSpot.horse_stand(player.get_world_3d().direct_space_state, at, yaw, world.water_level,
			[player.get_rid(), horse.get_rid()])
		if ground != Vector3.INF and absf(ground.y - at.y) < 2.0:
			horse.teleport(ground + Vector3.UP * 0.05, yaw)
			return
	main.spawn_horse_near(player)


func _restore_story(saved: Dictionary) -> void:
	if story == null:
		return
	if bool(saved.get("child_quest_done", false)):
		for flag in ["child_quest_started", "child_returned", "child_quest_done"]:
			story.set_flag(flag)
	if bool(saved.get("rooftop_talk_done", false)):
		for flag in ["night_before_war", "reve_noticed", "rooftop_talk_done"]:
			story.set_flag(flag)
		if story.triggers.has("BattleMaps"):
			story.triggers["BattleMaps"].enabled = false


## The same soldiers (by roster id), only if they are still alive.
func _restore_escort(saved: Dictionary) -> void:
	if campaign == null or not bool(saved.get("deployed", false)):
		return
	var by_id := {}
	for b in campaign.army.living():
		by_id[b.soldier_id] = b
	campaign.escort.clear()
	for m in saved.get("members", []):
		var b: SoldierBrain = by_id.get(int(m.get("id", -1)))
		if b == null:
			continue
		var spot := relocator.resolve(_v3(m.get("position", [])))
		if spot == Vector3.INF:
			spot = relocator.resolve(player.global_position)
		if spot == Vector3.INF:
			continue
		campaign.escort.adopt([b])
		campaign.escort._place(b, spot, float(m.get("yaw", 0.0)))
	campaign.deployed = campaign.escort.active()


## "Restart the campaign": the world forgets too.
func reset_progress() -> void:
	discovered.clear()
	used.clear()
	set_waypoint(Vector3.INF)
	current_location = ""
	for encounter: WorldEncounter in encounters.values():
		encounter.deactivate()
	for key in ["player", "horse", "exploration", "story", "escort", "entities", "flags"]:
		Persist.erase_section(key)


# --- presentation ----------------------------------------------------------------------------

func _build_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	_banner = _banner_label(layer, 118, 30, Color(0.93, 0.86, 0.68))
	_detail = _banner_label(layer, 160, 17, Color(0.86, 0.85, 0.8))
	_chime = AudioStreamPlayer.new()
	_chime.stream = AudioLib.get_instance().get_stream("scroll_pickup")
	_chime.volume_db = -20.0
	add_child(_chime)


func _banner_label(layer: CanvasLayer, top: float, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.offset_top = top
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate.a = 0.0
	layer.add_child(label)
	return label


func banner_text() -> String:
	return _banner.text


func _show_banner(title: String, detail: String, seconds: float) -> void:
	_banner.text = title
	_detail.text = detail
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween().set_parallel()
	for label: Label in [_banner, _detail]:
		_banner_tween.tween_property(label, "modulate:a", 1.0, 0.6)
		_banner_tween.tween_property(label, "modulate:a", 0.0, 1.2).set_delay(0.6 + seconds)


func _on_load_failed(reason: String, kept: String) -> void:
	hud.toast("%s%s" % [reason.capitalize(), "" if kept == "" else " A copy has been kept."], 6.0)


func _on_save_failed(reason: String) -> void:
	hud.toast("Not saved: %s." % reason, 5.0)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _v3(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.INF
