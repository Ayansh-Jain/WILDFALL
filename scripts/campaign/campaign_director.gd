class_name CampaignDirector
extends Node
## The campaign's one mission manager. Owns the CampaignState (missions, roster,
## checkpoint), the King in the great hall, the evening council, the Army, the
## current Encounter, the campaign HUD and the save file, and moves each mission
## through its validated states:
##
##   AWAITING_BRIEFING -> BRIEFING_AVAILABLE (evening) -> BRIEFING (the King speaks,
##   once) -> ACTIVE (travel; the enemy waits at its area) -> ENCOUNTER_ACTIVE
##   (contact) -> OBJECTIVE_COMPLETED -> RETURN_TO_CASTLE -> COMPLETE (reported;
##   +10 recruits) ... and on the commander's death in an encounter: FAILED ->
##   Retry (ENCOUNTER_ACTIVE again from the checkpoint) or Quit (RETRY_AVAILABLE:
##   the same encounter waits at its area; survivors kept, the dead stay dead).
##
## The encounter checkpoint is taken the moment ENCOUNTER_ACTIVE begins: the roster
## (who lives, at what health). Retry restores exactly that and respawns the same
## designated enemy force from its fixed layout; no reward is ever granted for a
## failed attempt. Mission 1 begins at the seated throne after the washroom opening.

signal mission_state_changed(mission_id: int, state: int)

const CAMPAIGN_HUD := preload("res://scripts/ui/campaign_hud.gd")

var vitals: Node
var deployed := false
var strategy_confirmed := false
var deployment_positions := {}
var tactical: Control
var opening_completed := false

var config := {}
var state: CampaignState
var army: Army
## R02: the called soldiers and their scripted orders (see Escort). Nobody follows by default.
var escort: Escort
var garrison: Garrison
var encounter: Encounter
var route: RouteGraph
var king: StoryNPC
var chud: CampaignHUD 
var persist := true
var save_path := "user://campaign_save.json"
## Absolute campaign time in hours (days * 24 + hour), from the day/night clock.
var hours := 0.0
## Multiplies waits (tests use a small value).
var speed := 1.0

var main: Node
var world: World
var player: PlayerController
var hud: HUD
var story: StoryDirector
var cycle: DayNightCycle
var plan: KingdomPlan

var _last_hour := NAN
var _tick := 0.0
var _busy := false
var _encounter_mission := -1
var _hall_noted := false


func setup(p_main: Node, p_world: World, p_player: PlayerController, p_hud: HUD, p_story: StoryDirector, p_persist := true) -> void:
	main = p_main
	world = p_world
	player = p_player
	hud = p_hud
	story = p_story
	persist = p_persist and not GameState.args.has("no-campaign-save")
	config = CampaignState.load_config()
	save_path = String(config.get("save_path", save_path))
	cycle = world.get_node_or_null("DayNightCycle") as DayNightCycle
	var sites := world.get_node_or_null("Sites/Structures")
	if sites and "kingdom_plan" in sites:
		plan = sites.kingdom_plan
	state = CampaignState.new(config)
	if not (persist and not GameState.args.has("new-campaign") and _load()):
		state.new_campaign()
	if uses_persist():
		Persist.register_provider("campaign", snapshot)
	Combat.set_team(player.player_id, "kingdom")
	route = RouteGraph.new()
	route.build(world)
	Battlefield.setup(world, route, config.get("battlefield", {}))
	chud = CAMPAIGN_HUD.new()
	chud.name = "CampaignHUD"
	add_child(chud)
	chud.army_button_pressed.connect(toggle_army)
	chud.retry_pressed.connect(retry)
	chud.quit_pressed.connect(quit_encounter)
	army = Army.new()
	army.name = "Army"
	add_child(army)
	army.setup(world, player, state, route)
	army.status_changed.connect(func(_s: String) -> void: _refresh_ui())
	army.soldier_died.connect(func(_id: int) -> void: _refresh_ui())
	escort = Escort.new()
	escort.name = "Escort"
	add_child(escort)
	escort.setup(player, world.water_level)
	escort.use_routes = true
	_muster_army()
	_build_garrison()
	encounter = Encounter.new()
	encounter.name = "Encounter"
	add_child(encounter)
	encounter.init(world, player, route, plan)
	encounter.progress_changed.connect(func(_k: int, _t: int) -> void: _refresh_ui())
	encounter.phase_changed.connect(func(_p: String) -> void: _refresh_ui())
	encounter.objective_completed.connect(_on_objective_completed)
	encounter.contact.connect(_on_contact)
	Combat.player_defeated.connect(_on_defeated)
	_spawn_king()
	tactical = preload("res://scripts/ui/tactical_map.gd").new()
	chud.add_child(tactical)
	tactical.setup(self)
	vitals = preload("res://scripts/campaign/commander_vitals.gd").new()
	add_child(vitals)
	vitals.setup(self)
	# A campaign loaded mid-mission: put the waiting enemy back at its area.
	var cur := state.current_mission()
	if cur >= 0 and state.state_of(cur) in [CampaignState.M.ACTIVE, CampaignState.M.RETRY_AVAILABLE]:
		_prepare_encounter(cur)
	_refresh_ui()


## True while a mission battle is being fought.
func in_encounter() -> bool:
	for id in state.states:
		if state.state_of(id) == CampaignState.M.ENCOUNTER_ACTIVE:
			return true
	return false


# --- persistence -----------------------------------------------------------------------------

## The real game keeps its campaign in the one world save (Persist). A different
## save_path (tests, tools) writes a standalone file instead.
func uses_persist() -> bool:
	return persist and Persist.active and save_path == Persist.legacy_path


func save() -> void:
	if not persist:
		return
	if uses_persist():
		Persist.save("campaign")
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(snapshot(), "\t"))


func snapshot() -> Dictionary:
	var d := state.to_dict()
	d["hours"] = hours
	d["deployment_positions"] = {}
	for id in deployment_positions:
		var pos: Vector3 = deployment_positions[id]
		d["deployment_positions"][str(id)] = [pos.x, pos.y, pos.z]
	d["castle_opening_complete"] = opening_completed
	return d


func _load() -> bool:
	var d: Variant = null
	if uses_persist():
		d = Persist.section("campaign")
		if (d as Dictionary).is_empty():
			return false
	else:
		if not FileAccess.file_exists(save_path):
			return false
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f == null:
			return false
		d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or not state.from_dict(d):
		push_warning("Campaign: the save at %s is unreadable or from another version; starting a new campaign" % save_path)
		return false
	hours = float(d.get("hours", 0.0))
	deployment_positions.clear()
	for id in d.get("deployment_positions", {}):
		var pos: Array = d["deployment_positions"][id]
		if pos.size() == 3:
			deployment_positions[int(id)] = Vector3(pos[0],pos[1],pos[2])
	# Legacy campaign saves resume their existing missions without a new prologue.
	opening_completed = bool(d.get("castle_opening_complete", true))
	return true


## Erases progress and starts over (pause menu).
func restart_campaign() -> void:
	tactical.close_map()
	deployed = false
	strategy_confirmed = false
	deployment_positions.clear()
	encounter.reset()
	escort.clear()
	army.despawn_all()
	state.new_campaign()
	opening_completed = false
	if main.enable_opening:
		main.start_castle_opening()
	_encounter_mission = -1
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.AUTO)
	_muster_army()
	if main.get("exploration"):
		main.exploration.reset_progress()
	save()
	_refresh_ui()


## Where the current orders point, for the compass and map (Vector3.INF = nowhere).
func objective_position() -> Vector3:
	var cur := state.current_mission()
	if cur < 0:
		return Vector3.INF
	match state.state_of(cur):
		CampaignState.M.BRIEFING_AVAILABLE, CampaignState.M.RETURN_TO_CASTLE:
			return king.global_position if is_instance_valid(king) else Vector3.INF
		CampaignState.M.ACTIVE, CampaignState.M.RETRY_AVAILABLE, CampaignState.M.ENCOUNTER_ACTIVE:
			var m := state.mission(cur)
			if String(m.get("type", "")) == "spies":
				return _nearest_spy_route()
			return _mission_area_center(m)
	return Vector3.INF


# --- clock and council -----------------------------------------------------------------------

func current_hour() -> float:
	return cycle.get_hour() if cycle else 18.0


func is_council_time() -> bool:
	var c: Dictionary = config.get("council", {})
	var h := current_hour()
	return h >= float(c.get("from_hour", 17.0)) and h <= float(c.get("to_hour", 23.5))


func _track_clock() -> void:
	var h := current_hour()
	if is_nan(_last_hour):
		_last_hour = h
		if hours <= 0.0:
			hours = h
		return
	hours += fposmod(h - _last_hour, 24.0)
	_last_hour = h


static func _council_day(abs_hours: float) -> int:
	# A council "day" runs noon to noon, so an evening and its night belong together.
	return int(floor((abs_hours - 12.0) / 24.0))


func briefing_allowed() -> bool:
	return (state.current_mission() == 1 and opening_completed) or (state.current_mission() != 1 and is_council_time() and hours >= state.next_briefing_after)


## Waits in the hall until the next council (under a fade).
func wait_for_council() -> void:
	if _busy:
		return
	_busy = true
	await _fade(1.0)
	var c: Dictionary = config.get("council", {})
	var target := float(c.get("wait_to_hour", 18.0))
	var h := current_hour()
	var advance := fposmod(target - h, 24.0)
	if hours + advance < state.next_briefing_after:
		advance += 24.0
	if cycle:
		cycle.advance_to_hour(target)
	hours += advance
	_last_hour = current_hour()
	_update_states()
	await get_tree().create_timer(0.4 * speed).timeout
	await _fade(0.0)
	hud.toast("Evening. The King holds council.", 3.0)
	_busy = false
	_refresh_ui()


# --- the King -------------------------------------------------------------------------------

func _spawn_king() -> void:
	if not story.has_anchor("king_throne"):
		push_warning("Campaign: the great hall has no king_throne anchor; the King was not placed")
		return
	king = StoryNPC.new()
	king.name = "King"
	world.add_child(king)
	king.setup("king", "Speak with the King", 1.5)
	king.global_position = story.anchor_pos("king_throne")
	king.rotation.y = story.anchor_yaw("king_throne")
	king.talk.max_view_angle = 60.0
	# The talk point sits just in front of him (inside his body capsule it would be
	# hidden from the interaction ray), at chest height over the high table.
	king.talk.global_position = story.anchor_pos("king_audience") + Vector3.UP * 1.2
	# Council candles on the high table: a warm pool of light on the King.
	var candles := OmniLight3D.new()
	candles.name = "CouncilCandles"
	candles.light_color = Color(1.0, 0.7, 0.42)
	candles.light_energy = 1.3
	candles.omni_range = 5.5
	candles.position = Vector3(0.0, 1.9, -1.3)
	king.add_child(candles)
	king.talked.connect(_on_king_talked)
	story.npcs["King"] = king


func king_prompt() -> String:
	var cur := state.current_mission()
	if cur < 0:
		return "Speak with the King"
	match state.state_of(cur):
		CampaignState.M.BRIEFING_AVAILABLE:
			return "Receive the King's orders"
		CampaignState.M.AWAITING_BRIEFING:
			return "Wait for the evening council"
		CampaignState.M.RETURN_TO_CASTLE:
			return "Report to the King"
	return "Speak with the King"


func _on_king_talked(_by: Node) -> void:
	if story.in_dialogue or _busy:
		return
	if Combat.now() - player.combatant.last_combat_time < 5.0:
		hud.toast("Not now. Finish the fight first.", 2.0)
		return
	var cur := state.current_mission()
	if cur < 0:
		await story.play_dialogue([["King", "Rest, Commander. You have more than earned it."]], king, king)
		return
	match state.state_of(cur):
		CampaignState.M.BRIEFING_AVAILABLE:
			await brief(cur)
		CampaignState.M.AWAITING_BRIEFING:
			if is_council_time():
				await story.play_dialogue([["King", "We have spoken tonight, Commander. Rest. Council sits again tomorrow at dusk."]], king, king)
			else:
				await story.play_dialogue([["King", "Commander. The council sits at dusk. Wait here and we will speak then."]], king, king)
			await wait_for_council()
		CampaignState.M.RETURN_TO_CASTLE:
			await report(cur)
		CampaignState.M.ACTIVE, CampaignState.M.RETRY_AVAILABLE, CampaignState.M.ENCOUNTER_ACTIVE:
			var m := state.mission(cur)
			await story.play_dialogue([["King", "Your orders stand, Commander: %s." % String(m.get("objective", "")).to_lower()]], king, king)


## Walk the last steps to the audience mark through normal character physics.
func _royal_dialogue(lines: Array) -> void:
	var controls := player.controls_enabled
	var previous_input: Variant = player.input_override
	player.controls_enabled = false
	var mark := story.anchor_pos("king_audience")
	var elapsed := 0.0
	while CampaignUtil.flat_dist(player.global_position, mark) > 0.4 and elapsed < 4.0:
		var direction := mark - player.global_position
		player.rotation.y = atan2(-direction.x, -direction.z)
		player.input_override = {"move": Vector2(0, 0.55)}
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	player.input_override = {}
	var face := king.global_position - player.global_position
	player.rotation.y = atan2(-face.x, -face.z)
	var rig := story.commander()
	if rig:
		rig.play_story("kneel_fix")
	await get_tree().create_timer(1.3 * speed).timeout
	await story.play_dialogue(lines, king, king)
	if rig:
		rig.stop_story()
	player.input_override = previous_input
	player.controls_enabled = controls


## The King's orders for mission `id` (shown once: the state moves on afterwards).
func brief(id: int) -> bool:
	if not state.transition(id, CampaignState.M.BRIEFING):
		return false
	mission_state_changed.emit(id, CampaignState.M.BRIEFING)
	_refresh_ui()
	var m := state.mission(id)
	await _royal_dialogue(m.get("briefing", []))
	state.transition(id, CampaignState.M.ACTIVE)
	state.next_briefing_after = (_council_day(hours) + 1) * 24.0 + 12.0
	mission_state_changed.emit(id, CampaignState.M.ACTIVE)
	chud.banner(String(m.get("name", "")), String(m.get("objective", "")), 3.0)
	_prepare_encounter(id)
	if String(m.get("type", "")) == "spies":
		start_encounter(id)
	save()
	_refresh_ui()
	return true


## Reporting back: the mission completes and its recruits join (once).
func report(id: int) -> bool:
	if state.state_of(id) != CampaignState.M.RETURN_TO_CASTLE:
		return false
	var m := state.mission(id)
	await _royal_dialogue(m.get("report", [["King", "Well done, Commander."]]))
	if id == 1:
		player.controls_enabled = false
		await _fade(1.0)
		_stand_down()
		await _fade(0.0)
		player.controls_enabled = true
	var before := state.roster_size()
	if not state.transition(id, CampaignState.M.COMPLETE):
		return false
	mission_state_changed.emit(id, CampaignState.M.COMPLETE)
	var joined := state.roster_size() - before
	chud.banner("MISSION COMPLETE", String(m.get("name", "")), 3.0)
	if joined > 0:
		# New recruits muster in the castle courtyard.
		army.spawn_missing(_courtyard(), 0.0)
		hud.toast("%d recruits have joined your company (%d soldiers)." % [joined, state.alive_count()], 4.0)
	encounter.reset()
	_encounter_mission = -1
	save()
	_refresh_ui()
	return true


func _courtyard() -> Vector3:
	if story.has_anchor("castle_courtyard"):
		return story.anchor_pos("castle_courtyard")
	return CampaignUtil.v3(world, config.get("safe_point", {}).get("pos", [212, 167]))


func _safe_point() -> Vector3:
	return _courtyard()


# --- army ------------------------------------------------------------------------------------

func _muster_army() -> void:
	var muster: Dictionary = config.get("muster", {})
	var center := CampaignUtil.v3(world, muster.get("pos", [-108, -64]))
	var posts: Array = []
	for m in get_tree().get_nodes_in_group("phase3_soldier_posts"):
		posts.append((m as Node3D).global_position)
	army.spawn_missing(center, 0.0, posts)
	# Company horses are created only during the mounted transition.


## Allied guards at the castle, wall, watchtower, gate, training ground and bridges.
## They are not on the roster and never answer the army-follow order.
func _build_garrison() -> void:
	var gcfg: Dictionary = config.get("garrison", {})
	if gcfg.is_empty() or GameState.args.has("no-garrison"):
		return
	var avoid: Array[Vector3] = []
	for m in get_tree().get_nodes_in_group("phase3_soldier_posts"):
		avoid.append((m as Node3D).global_position)
	garrison = Garrison.new()
	garrison.name = "Garrison"
	add_child(garrison)
	garrison.setup(world, player, plan, gcfg, avoid)
	garrison.build()


func toggle_army() -> void:
	if _busy or story.in_dialogue or not player.controls_enabled or player.is_defeated or tactical.visible:
		return
	var cur := state.current_mission()
	if cur < 0 or state.state_of(cur) not in [CampaignState.M.ACTIVE, CampaignState.M.RETRY_AVAILABLE, CampaignState.M.RETURN_TO_CASTLE]:
		hud.toast("The King must authorize your company first.", 2.0)
		return
	if _duel_active():
		hud.toast("This fight is yours alone.", 2.0)
		return
	# Mid-battle T never abandons the field: the escort re-forms behind him, once.
	if deployed and in_encounter() and escort.active():
		escort.command("regroup")
		hud.toast("Company, form up behind me!", 2.0)
		return
	_busy = true
	player.controls_enabled = false
	army.set_paused(true)
	await _fade(1.0)
	play_transition_sound()
	var message := ""
	if deployed and escort.active():
		_stand_down()
		message = "Your escort returns to the castle."
	else:
		army.spawn_missing(player.global_position, player.rotation.y)
		army.set_follow(false)
		escort.clear()
		var result := escort.summon(army.living())
		deployed = bool(result.ok)
		if result.ok:
			message = "%d soldiers answer and hold behind you." % int(result.count)
			if in_encounter():
				for b in escort.living():
					b.weapons_free = true
		else:
			message = String(result.reason)
	army.set_paused(false)
	await _fade(0.0)
	player.controls_enabled = true
	_busy = false
	hud.toast(message, 2.5)
	save()
	_refresh_ui()


func _stand_down() -> void:
	army.sync_to_state()
	escort.clear()
	army.set_follow(false)
	army.place_at(_courtyard(), 0.0)
	deployed = false


func _duel_active() -> bool:
	return is_instance_valid(encounter) and is_instance_valid(encounter.boss_stage) and encounter.boss_stage.started and not encounter.done


## A battle has begun with the escort called: scripted orders, once. Large battles also
## bring up the rest of the living company (nobody new is created).
func _march_to_battle(m: Dictionary) -> void:
	if not deployed or _duel_active():
		return
	var type := String(m.get("type", ""))
	if type in ["battle", "final"]:
		var rest := army.living().filter(func(b) -> bool: return not escort.members.has(b))
		if m.has("ally_stage") and not rest.is_empty():
			var stage := CampaignUtil.v3(world, m["ally_stage"])
			for i in rest.size():
				var b: SoldierBrain = rest[i]
				var want := army._rank_point(stage, 0.0, i)
				var found := SpawnValidator.find(world, Vector2(want.x, want.z), want.y + 3.0, 6.0)
				if found["ok"] and not CampaignUtil.in_view(player, found["position"] + Vector3.UP, 120.0):
					b.avatar.teleport(found["position"] + Vector3.UP * 0.05, player.rotation.y)
					b.hold_pos = b.avatar.global_position
		escort.adopt(rest)
		escort.command("advance", encounter.area_center())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("strategy") and not event.is_echo():
		if can_plan():
			tactical.open_map()
		else:
			hud.toast("Assemble your army and approach the jungle camp while hidden.", 3.0)
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("army_command") and not event.is_echo() and not chud.failed_visible():
		if player.is_defeated or story.in_dialogue:
			return
		toggle_army()
		get_viewport().set_input_as_handled()


# --- encounters ------------------------------------------------------------------------------

## Places the mission's enemy force at its area in its initial (waiting) state.
func _prepare_encounter(id: int) -> void:
	var m := state.mission(id)
	if m.is_empty() or String(m.get("type", "")) == "reserved":
		return
	encounter.reset()
	encounter.configure(m)
	encounter.spawn_initial()
	_encounter_mission = id


func _on_contact() -> void:
	var cur := state.current_mission()
	if cur >= 0 and state.state_of(cur) in [CampaignState.M.ACTIVE, CampaignState.M.RETRY_AVAILABLE]:
		start_encounter(cur)


## Contact: take the checkpoint and let the fight begin. Refused unless the mission
## is ACTIVE or RETRY_AVAILABLE (no duplicate activation).
func start_encounter(id: int) -> bool:
	var s := state.state_of(id)
	if s != CampaignState.M.ACTIVE and s != CampaignState.M.RETRY_AVAILABLE:
		return false
	if _encounter_mission != id:
		_prepare_encounter(id)
	army.sync_to_state()
	state.take_checkpoint(id)
	if not state.transition(id, CampaignState.M.ENCOUNTER_ACTIVE):
		return false
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.HOLD)
	encounter.activate()
	if encounter.mission_type == "camp":
		_begin_camp_battle()
	else:
		for b in army.living():
			b.weapons_free = true
		_march_to_battle(state.mission(id))
	mission_state_changed.emit(id, CampaignState.M.ENCOUNTER_ACTIVE)
	save()
	_refresh_ui()
	return true


func _on_objective_completed() -> void:
	var id := _encounter_mission
	if id < 0 or not state.transition(id, CampaignState.M.OBJECTIVE_COMPLETED):
		return
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.AUTO)
	mission_state_changed.emit(id, CampaignState.M.OBJECTIVE_COMPLETED)
	var m := state.mission(id)
	chud.banner("OBJECTIVE COMPLETE", String(m.get("victory_text", "Return to the castle and report to the King.")), 3.5)
	army.sync_to_state()
	for b in army.living():
		b.weapons_free = false
		b.set_order(SoldierBrain.Mode.HOLD)
		b._enter(SoldierBrain.Mode.HOLD)
		b.hold_pos = b.avatar.global_position
	# Survivors form up behind him once; they do not trail him home.
	if deployed:
		escort.command("regroup")
	_refresh_ui()
	await get_tree().create_timer(3.0 * speed).timeout
	if state.transition(id, CampaignState.M.RETURN_TO_CASTLE):
		mission_state_changed.emit(id, CampaignState.M.RETURN_TO_CASTLE)
		hud.toast("Return to the castle and report to the King.", 3.5)
	save()
	_refresh_ui()


func _on_defeated(e: Dictionary) -> void:
	if e["victim"] != player.player_id or _encounter_mission < 0:
		return
	var id := _encounter_mission
	if state.state_of(id) != CampaignState.M.ENCOUNTER_ACTIVE:
		return
	state.transition(id, CampaignState.M.FAILED)
	mission_state_changed.emit(id, CampaignState.M.FAILED)
	encounter.set_paused(true)
	army.set_paused(true)
	_refresh_ui()
	await get_tree().create_timer(2.5 * speed).timeout
	if state.state_of(id) != CampaignState.M.FAILED:
		return
	var m := state.mission(id)
	chud.show_failed("%s\nThe commander has fallen. Retry the encounter from its start, or quit to the castle." % String(m.get("name", "")))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Retry: the same encounter from its checkpoint. No reward, counters reset.
func retry() -> bool:
	var id := _encounter_mission
	if _busy or id < 0 or state.state_of(id) != CampaignState.M.FAILED:
		return false
	_busy = true
	chud.hide_failed()
	_capture_mouse()
	await _fade(1.0)
	var m := state.mission(id)
	encounter.reset()
	escort.clear()
	army.despawn_all()
	state.restore_checkpoint(id)
	var spies := String(m.get("type", "")) == "spies"
	var stage := _safe_point() if spies else CampaignUtil.v3(world, m.get("ally_stage", [0, 0]))
	var cstage := _safe_point() if spies else CampaignUtil.v3(world, m.get("commander_stage", m.get("ally_stage", [0, 0])))
	var face := _mission_area_center(m) - cstage
	var yaw := atan2(-face.x, -face.z)
	Combat.revive(player.player_id, _ground(cstage), yaw)
	army.spawn_missing(stage + Basis(Vector3.UP, yaw) * Vector3(0, 0, 4.0), yaw)
	_prepare_encounter(id)
	state.transition(id, CampaignState.M.ENCOUNTER_ACTIVE)
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.HOLD)
	encounter.activate()
	for b in army.living():
		b.weapons_free = true
	if encounter.mission_type == "camp":
		_begin_camp_battle()
	else:
		for b in army.living():
			b.weapons_free = true
		if deployed:
			escort.adopt(army.living())
			_march_to_battle(m)
	mission_state_changed.emit(id, CampaignState.M.ENCOUNTER_ACTIVE)
	save()
	_refresh_ui()
	await get_tree().create_timer(0.3 * speed).timeout
	await _fade(0.0)
	_busy = false
	return true


## Quit: leave the encounter for the castle. Nothing is awarded; the survivors stay
## as they are (the fallen remain fallen); the same encounter waits at its area.
func quit_encounter() -> bool:
	var id := _encounter_mission
	if _busy or id < 0 or state.state_of(id) != CampaignState.M.FAILED:
		return false
	_busy = true
	chud.hide_failed()
	_capture_mouse()
	await _fade(1.0)
	army.sync_to_state()
	encounter.reset()
	escort.clear()
	deployed = false
	army.despawn_all()
	var safe := _safe_point()
	Combat.revive(player.player_id, _ground(safe), 0.0)
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.AUTO)
	army.spawn_missing(safe + Vector3(0, 0, 5.0), 0.0)
	state.transition(id, CampaignState.M.RETRY_AVAILABLE)
	_prepare_encounter(id)
	mission_state_changed.emit(id, CampaignState.M.RETRY_AVAILABLE)
	save()
	_refresh_ui()
	await get_tree().create_timer(0.3 * speed).timeout
	await _fade(0.0)
	hud.toast("You return to the castle. The enemy still holds %s." % String(state.mission(id).get("destination", "the field")), 4.0)
	_busy = false
	return true


func _ground(p: Vector3) -> Vector3:
	var res := SpawnValidator.find(world, Vector2(p.x, p.z), p.y + 2.0, 6.0)
	return res["position"] if res["ok"] else p


func _fade(to: float) -> void:
	var tw := chud.fade(to, 0.6 * speed)
	await tw.finished


func _capture_mouse() -> void:
	if main and main.get("auto_capture_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- per frame -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_track_clock()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	_update_states()
	_tick_camp()
	_refresh_ui()


func _update_states() -> void:
	var cur := state.current_mission()
	if cur < 0:
		return
	var s := state.state_of(cur)
	match s:
		CampaignState.M.AWAITING_BRIEFING:
			if briefing_allowed():
				state.transition(cur, CampaignState.M.BRIEFING_AVAILABLE)
				mission_state_changed.emit(cur, CampaignState.M.BRIEFING_AVAILABLE)
				_hall_noted = false
		CampaignState.M.BRIEFING_AVAILABLE:
			if cur != 1 and not is_council_time():
				state.transition(cur, CampaignState.M.AWAITING_BRIEFING)
				mission_state_changed.emit(cur, CampaignState.M.AWAITING_BRIEFING)
			elif not _hall_noted and army.leader_inside():
				_hall_noted = true
				hud.toast("The King is holding council in the great hall.", 3.0)
		CampaignState.M.ACTIVE, CampaignState.M.RETRY_AVAILABLE:
			if _busy:
				return
			if _encounter_mission != cur:
				_prepare_encounter(cur)
			var m := state.mission(cur)
			if String(m.get("type", "")) == "spies":
				if CampaignUtil.flat_dist(player.global_position, _safe_point()) > 60.0 or s == CampaignState.M.ACTIVE:
					start_encounter(cur)
			elif String(m.get("type", "")) != "camp" and not army.leader_inside() and CampaignUtil.flat_dist(player.global_position, _mission_area_center(m)) < float(m.get("trigger_radius", 40.0)):
				# Contact on the field itself (never from inside the keep next door).
				start_encounter(cur)
	if king:
		king.talk.prompt_text = king_prompt()


# --- UI --------------------------------------------------------------------------------------

func mission_info() -> Dictionary:
	if is_instance_valid(main.castle_opening) and main.castle_opening.active:
		return {"title": "MORNING AT LAKESIDE CASTLE", "state": "", "objective": story.objective}
	var cur := state.current_mission()
	if cur < 0:
		if state.campaign_complete:
			return {"title": "Campaign complete", "state": "", "objective": "The gate holds."}
		return {}
	var m := state.mission(cur)
	var s := state.state_of(cur)
	var info := {"title": "Mission %d  -  %s" % [cur, String(m.get("name", ""))], "state": state.state_name(cur)}
	var king_pos := king.global_position if king else _safe_point()
	match s:
		CampaignState.M.AWAITING_BRIEFING:
			info["objective"] = "Return to the castle in the evening for the King's council"
			info["destination"] = _bearing("The great hall", king_pos)
		CampaignState.M.BRIEFING_AVAILABLE:
			info["objective"] = "Speak with the King in the great hall"
			info["destination"] = _bearing("The great hall", king_pos)
		CampaignState.M.BRIEFING:
			info["objective"] = "Hear the King's orders"
		CampaignState.M.ACTIVE:
			info["objective"] = String(m.get("objective", ""))
			info["destination"] = _bearing(String(m.get("destination", "")), _mission_area_center(m))
			_add_progress(info, m)
		CampaignState.M.RETRY_AVAILABLE:
			info["objective"] = "%s (return to try again)" % String(m.get("objective", ""))
			info["destination"] = _bearing(String(m.get("destination", "")), _mission_area_center(m))
			_add_progress(info, m)
		CampaignState.M.ENCOUNTER_ACTIVE:
			info["objective"] = String(m.get("objective", ""))
			_add_progress(info, m)
			info["phase"] = encounter.phase_text
			if encounter.mission_type == "spies" and not encounter.retreating:
				var near := _nearest_spy_route()
				if near != Vector3.INF:
					info["destination"] = _bearing("Nearest spy route", near)
		CampaignState.M.OBJECTIVE_COMPLETED:
			info["objective"] = "Objective complete"
			_add_progress(info, m)
		CampaignState.M.RETURN_TO_CASTLE:
			info["objective"] = "Return to the castle and report to the King"
			info["destination"] = _bearing("The great hall", king_pos)
		CampaignState.M.FAILED:
			info["objective"] = "Mission failed"
			_add_progress(info, m)
	if is_instance_valid(encounter) and encounter.mission_type == "camp" and not encounter.done:
		var distance := CampaignUtil.flat_dist(player.global_position, encounter.area_center())
		info["destination"] = "Jungle camp - %d m" % int(distance)
		info["phase"] = "ENGAGED" if encounter.active else ("AT RISK - detection nearby" if distance < detection_radius() + 6 else "HIDDEN - [%s] Plan strategy" % Settings.get_binding_text("strategy"))
	if is_instance_valid(encounter) and is_instance_valid(encounter.boss_stage) and encounter.boss_stage.started and not encounter.done:
		info["objective"] = "Defeat the Black Giant alone"
		info["phase"] = encounter.phase_text
		info.erase("kills")
		info.erase("target")
	return info


func _add_progress(info: Dictionary, m: Dictionary) -> void:
	var t := encounter.target if _encounter_mission == state.current_mission() else int(m.get("kill_target", m.get("enemy_total", m.get("enemy_count", 0))))
	info["kills"] = mini(encounter.kills, t) if _encounter_mission == state.current_mission() else 0
	info["target"] = t


func _nearest_spy_route() -> Vector3:
	var best := Vector3.INF
	for b in encounter.enemies:
		if not is_instance_valid(b) or not b.is_alive() or b.patrol.is_empty():
			continue
		var mid := b.patrol[b.patrol.size() / 2]
		if best == Vector3.INF or CampaignUtil.flat_dist(mid, player.global_position) < CampaignUtil.flat_dist(best, player.global_position):
			best = mid
	return best


## Resolves the configured mission location without relying on a live Encounter.
## The encounter is reset/rebuilt during retries and can briefly be unavailable to
## UI or travel updates during that lifecycle transition.
func _mission_area_center(mission_cfg: Dictionary) -> Vector3:
	var area_id := String(mission_cfg.get("area", ""))
	if world and world.layout:
		for area in world.layout.dict("kingdom").get("missions", []):
			if String(area.get("id", "")) == area_id and area.has("center"):
				return CampaignUtil.v3(world, area["center"])
	if is_instance_valid(encounter):
		return encounter.area_center()
	return player.global_position if is_instance_valid(player) else Vector3.ZERO


func _bearing(label: String, p: Vector3) -> String:
	var d := p - player.global_position
	var dist := Vector2(d.x, d.z).length()
	if dist < 12.0:
		return label + "  (here)"
	var ang := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	var dirs := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return "%s  -  %d m %s" % [label, int(dist), dirs[int(round(ang / 45.0)) % 8]]


func _refresh_ui() -> void:
	if chud == null:
		return
	chud.set_mission(mission_info())
	chud.set_army("ARMY  %s   %d / %d   [%s]" % [army.status(), state.alive_count(), state.roster_size(),
		Settings.get_binding_text("army_command")])


func play_transition_sound(sound_name := "sword_swing") -> void:
	var audio := AudioStreamPlayer.new()
	add_child(audio)
	audio.stream = AudioLib.get_instance().get_stream(sound_name)
	audio.volume_db = -16
	audio.finished.connect(audio.queue_free)
	audio.play()


func can_plan() -> bool:
	return not _busy and deployed and not story.in_dialogue and (player.controls_enabled or tactical.visible) and not player.riding and not player.is_defeated and encounter.mission_type == "camp" and not encounter.active and not encounter.done and CampaignUtil.flat_dist(player.global_position, encounter.area_center()) < 65.0


func detection_radius() -> float:
	var radius := 0.0
	for b in encounter.enemies:
		if is_instance_valid(b) and b.is_alive():
			radius = maxf(radius, CampaignUtil.flat_dist(b.avatar.global_position, encounter.area_center()) + b.sight_range)
	return radius


func deployment_valid(p: Vector3, others: Array = []) -> bool:
	if CampaignUtil.flat_dist(p, encounter.area_center()) <= detection_radius() + 1.5:
		return false
	if CampaignUtil.flat_dist(p, encounter.area_center()) > 60.0:
		return false
	for other: Vector3 in others:
		if CampaignUtil.flat_dist(p, other) < 2.5:
			return false
	var ground := SpawnValidator.check(world, Vector2(p.x, p.z), NAN, 32.0, 0.4, 12.0)
	return bool(ground["ok"]) and CampaignUtil.flat_dist(ground["position"], p) < 1.0 and absf(ground["position"].y - world.terrain_height(p.x, p.z)) < 1.0


func deploy_strategy(placements: Dictionary) -> void:
	if not can_plan():
		return
	var accepted: Array = [player.global_position]
	for b in army.living():
		if not placements.has(b.soldier_id) or not deployment_valid(placements[b.soldier_id], accepted):
			hud.toast("Deployment changed or is obstructed. Revise the plan.", 3.0)
			return
		accepted.append(placements[b.soldier_id])
	tactical.close_map()
	_busy = true
	player.controls_enabled = false
	army.set_paused(true)
	encounter.set_paused(true)
	await _fade(1.0)
	play_transition_sound()
	army.set_follow(false)
	for b in army.living():
		var p: Vector3 = placements[b.soldier_id]
		var ground := SpawnValidator.check(world, Vector2(p.x, p.z), NAN, 32.0, 0.4, 12.0)
		b.avatar.teleport(ground["position"] + Vector3.UP * 0.05, player.rotation.y)
		b.hold_pos = b.avatar.global_position
		b.weapons_free = false
		b._enter(SoldierBrain.Mode.HOLD)
	deployment_positions = placements.duplicate()
	strategy_confirmed = true
	save()
	await _fade(0.0)
	army.set_paused(false)
	encounter.set_paused(false)
	player.controls_enabled = true
	_busy = false
	hud.toast("Positions held. Lead the approach; contact gives the attack order.", 4.0)


func _tick_camp() -> void:
	if _busy or tactical.visible or encounter.mission_type != "camp" or encounter.active or encounter.done:
		return
	for b in encounter.enemies:
		if is_instance_valid(b) and b.is_alive() and b._detect() >= 0:
			_on_contact()
			return


func _begin_camp_battle() -> void:
	hud.toast("Commander: Attack!   Enemy guard: Intruders! To arms!", 3.0)
	for b in army.living():
		b.weapons_free = true
		b.alert(-1)
	for b in encounter.enemies:
		if not is_instance_valid(b) or not b.is_alive():
			continue
		var alert_delay := 0.35
		if b.rig() and b.rig()._hold_anim == "sit_idle":
			alert_delay = maxf(0.8, b.rig().stand_up())
		b._enter(SoldierBrain.Mode.DORMANT)
		get_tree().create_timer(alert_delay + float(b.soldier_id % 3) * 0.15).timeout.connect(func() -> void:
			if is_instance_valid(b) and b.is_alive() and encounter.active:
				b.weapons_free = true
				b.alert(-1))
