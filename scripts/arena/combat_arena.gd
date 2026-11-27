class_name CombatArena
extends Node3D
## The one shared Round 2 playable arena: Antigravity's Golden Valley (environment and
## wf_marker anchors), Codex's CombatDirector and dual-sword Combat API, and the player
## layer: training, practice stations, the called escort and a scripted army display.
## Nothing here writes the campaign save; the army roster is only read.

const SHOWCASE := "res://scenes/world/showcase/golden_valley_showcase.tscn"
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DIRECTOR := preload("res://scripts/combat/combat_director.gd")
const HUD_SCRIPT := preload("res://scripts/arena/arena_hud.gd")
const ENCOUNTER := "arena"
const ELITE_HEALTH := 260

## Station -> [anchor marker, banner].
const STATIONS := {
	"spawn": ["gv_patrol_1", "Practice Valley"],
	"training": ["gv_escort_right", "Training Ground"],
	"duel": ["gv_patrol_2", "Single Opponent"],
	"group": ["gv_clearing_center", "Surrounded"],
	"elite": ["gv_patrol_3", "Captain of the Black Guard"],
	"army": ["gv_enemy_spawn_e", "The Line of Battle"],
}
const KEYS := {KEY_1: "training", KEY_2: "duel", KEY_3: "group", KEY_4: "elite", KEY_5: "army", KEY_0: "spawn"}

## Tells DevVisit that this scene shows its own controls.
var custom_hint := true
var showcase: Node3D
var player: PlayerController
var horse: Horse
var director: Node
var training: TrainingSession
var escort: Escort
var hud: CanvasLayer
var roster: CampaignState
var water_level := 0.0
var station := "spawn"
var enemies: Array = []
var markers := {}
var ready_done := false

var _soldiers := {}  ## roster id -> SoldierBrain
var _pawns: Array = []
var _demo_step := -1
var _demo_t := 0.0
var _swing_t := 0.0
var _won := false
var _sheathe_t := -1.0


func _ready() -> void:
	showcase = (load(SHOWCASE) as PackedScene).instantiate()
	add_child(showcase)
	# The showcase's own number keys and panel give way to the arena's.
	showcase.set_process_unhandled_input(false)
	var panel := showcase.get_node_or_null("ShowcaseHUD") as CanvasLayer
	if panel:
		panel.visible = false
	player = showcase.get("player")
	horse = showcase.get("horse")
	water_level = player.water_level
	for m in get_tree().get_nodes_in_group("wf_marker"):
		if showcase.is_ancestor_of(m):
			markers[String(m.get_meta("marker_id"))] = (m as Node3D).global_position

	director = DIRECTOR.new()
	director.name = "CombatDirector"
	director.commander = player
	add_child(director)
	escort = Escort.new()
	escort.name = "Escort"
	add_child(escort)
	escort.setup(player, water_level)
	hud = HUD_SCRIPT.new()
	hud.name = "ArenaHUD"
	add_child(hud)
	hud.setup(self)
	training = TrainingSession.new()
	training.name = "Training"
	add_child(training)
	training.setup(player, director, _training_fighter, _remove_actor, _stand_at.bind("training"))
	training.changed.connect(_on_training_changed)
	training.feedback.connect(_on_training_feedback)
	training.finished.connect(_on_training_finished)
	_load_roster()

	Combat.set_team(player.player_id, "kingdom")
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.HOLD)
	Combat.configure_sword_actor(player.player_id)
	Combat.player_defeated.connect(_on_defeated)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_stand_at("spawn")
	hud.banner("Practice Valley\n[1] begins combat training", 5.0)
	ready_done = true


func _exit_tree() -> void:
	if training:
		training.stop()
	if is_instance_valid(player) and player.player_id >= 0:
		Combat.cancel_attack(player.player_id, "leaving the arena")
		Combat.swords.remove(player.player_id)
		Combat.set_respawn_mode(player.player_id, Combat.Respawn.AUTO)
		player.cam.abort_cinematic()


func training_ids() -> Array:
	return training._enemy_ids() if training.active else []


# --- stations ---------------------------------------------------------------------------------

## Where a station is, and the direction the player faces there.
func station_frame(id: String) -> Dictionary:
	var at: Vector3 = markers.get(STATIONS[id][0], player.global_position)
	var ahead: Vector3 = markers.get("gv_clearing_center", at) - markers.get("gv_patrol_1", at)
	ahead.y = 0.0
	ahead = ahead.normalized() if ahead.length() > 0.1 else Vector3.FORWARD
	return {"at": at, "ahead": ahead, "yaw": atan2(-ahead.x, -ahead.z)}


## A standable point near `want`, searching outward.
func ground_near(want: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	for r in [0.0, 1.2, 2.4, 3.6, 5.0]:
		for k in 8:
			var p: Vector3 = want + Vector3(sin(k * TAU / 8.0), 0.0, cos(k * TAU / 8.0)) * float(r)
			p.y = showcase.td.height_at(p.x, p.z)
			var spot := SafeSpot.standing(space, p, Vector3.INF, water_level, [player.get_rid()])
			if spot != Vector3.INF:
				return spot
			if r == 0.0:
				break
	want.y = showcase.td.height_at(want.x, want.z)
	return want


func _stand_at(id: String) -> void:
	var f := station_frame(id)
	var back: float = 0.0 if id == "spawn" else (6.0 if id == "army" else 1.8)
	if player.riding:
		(player.get_node("Rider") as Rider).force_dismount()
	player.teleport(ground_near(f.at - f.ahead * back) + Vector3.UP * 0.05, f.yaw)


func start_station(id: String) -> void:
	if not STATIONS.has(id):
		return
	clear_station()
	station = id
	if player.is_defeated:
		Combat.revive(player.player_id, player.global_position, player.rotation.y)
	Combat.configure_sword_actor(player.player_id)
	player.combatant.set_health(player.combatant.max_health)
	_stand_at(id)
	hud.banner(String(STATIONS[id][1]), 2.5)
	match id:
		"training":
			training.start(0)
		"duel":
			_spawn_group(id, ["standard"])
		"group":
			_spawn_group(id, ["standard", "aggressive", "heavy", "defensive", "standard"])
		"elite":
			_spawn_group(id, ["elite"])
			if not Settings.reduce_motion:
				player.cam.emphasize(2.2, 0.76, -6.0)
		"army":
			_start_army_demo()


func clear_station() -> void:
	if training.active:
		training.stop()
	Combat.cancel_attack(player.player_id, "station change")
	for actor in enemies:
		if is_instance_valid(actor):
			director.unregister_enemy(actor.player_id)
			_remove_actor(actor)
	enemies.clear()
	for pawn in _pawns:
		if is_instance_valid(pawn):
			pawn.queue_free()
	_pawns.clear()
	_demo_step = -1
	_won = false
	_sheathe_t = -1.0
	hud.lesson_text("")


func _spawn_group(id: String, patterns: Array) -> void:
	var f := station_frame(id)
	for i in patterns.size():
		var angle: float = f.yaw + (i - (patterns.size() - 1) * 0.5) * 0.75
		var reach := 4.5 if patterns.size() > 1 else 4.0
		var pos := ground_near(f.at - f.ahead * 1.8 + Basis(Vector3.UP, angle) * Vector3(0, 0, -reach))
		var elite: bool = patterns[i] == "elite"
		var actor := spawn_enemy(pos, "soldier:enemy:captain" if elite else "soldier:enemy")
		if elite:
			actor.combatant.set_max_health(ELITE_HEALTH, false)
			actor.combatant.set_health(ELITE_HEALTH)
			actor.set_meta("duel_opponent", player.player_id)  # a duel: allies stay out of it
		director.register_enemy(actor, ENCOUNTER, patterns[i])
		enemies.append(actor)
	director.turn = 0
	director.schedule_at = Combat.now() + 1.8


## One enemy fighter body, facing the player. The caller decides who drives it.
func spawn_enemy(pos: Vector3, style := "soldier:enemy") -> PlayerController:
	var actor := _body(pos, style, "Black Guard", true)
	Combat.set_team(actor.player_id, "enemy")
	Combat.set_respawn_mode(actor.player_id, Combat.Respawn.NEVER)
	# Fighters arrive with the blade out. Needed: SoldierRig is a CommanderRig, and Combat
	# cancels an attack made with a sheathed blade (REQ-20261126-claude-r02).
	var visual := actor.get_node_or_null("AvatarVisual") as AvatarVisual
	var rig := visual.human_rig as SoldierRig if visual else null
	if rig:
		rig.combat_ready = true
		rig._put_sword(true)
	return actor


func _body(pos: Vector3, style: String, who: String, register: bool, brain: SoldierBrain = null) -> PlayerController:
	var actor: PlayerController = PLAYER_SCENE.instantiate()
	actor.is_local = false
	actor.is_bot = true
	actor.auto_register = register
	actor.display_name = who
	actor.body_style = style
	actor.get_node("Head/Camera3D").current = false
	if brain:
		actor.add_child(brain)
	add_child(actor)
	actor.water_level = water_level
	var to := player.global_position - pos
	actor.teleport(pos + Vector3.UP * 0.05, atan2(-to.x, -to.z))
	actor.input_override = {}
	return actor


func _training_fighter(slot: int) -> PlayerController:
	var f := station_frame("training")
	var offsets := [Vector3(0, 0, -2.2), Vector3(-3.2, 0, -3.5), Vector3(0, 0, -5.0), Vector3(3.2, 0, -3.5)]
	var base: Vector3 = f.at - f.ahead * 1.8
	return spawn_enemy(ground_near(base + Basis(Vector3.UP, f.yaw) * offsets[slot]))


func _remove_actor(actor: PlayerController) -> void:
	if is_instance_valid(actor):
		actor.queue_free()


# --- the escort (T) ---------------------------------------------------------------------------

## The campaign's roster, read only: training and the arena never change the save.
func _load_roster() -> void:
	var config := CampaignState.load_config()
	roster = CampaignState.new(config)
	# The world save first (read only), then the older campaign file.
	var world_save: Dictionary = Persist.peek_section("campaign")
	if not world_save.is_empty() and roster.from_dict(world_save):
		return
	var path := String(config.get("save_path", "user://campaign_save.json"))
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and roster.from_dict(data):
			return
	roster.new_campaign()


func toggle_escort() -> void:
	if player.is_defeated or not player.controls_enabled:
		return
	if _demo_step >= 0:
		_demo_step = -1
		_clear_pawns()
	if escort.active():
		_dismiss_escort()
		hud.flash("Your escort stands down")
		return
	# Bodies for at most four of the living, healthiest first; never anyone new.
	var living := roster.roster.filter(func(r: Dictionary) -> bool: return r.alive)
	living.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.id) < int(b.id) if int(a.health) == int(b.health) else int(a.health) > int(b.health))
	var called := []
	for rec: Dictionary in living.slice(0, Escort.SIZE):
		called.append(_soldier(rec))
	var result := escort.summon(called)
	if not result.ok:
		_dismiss_escort()
		for b in called:
			_retire(b)
		hud.flash(String(result.reason), false)
		return
	for b in called:
		if not escort.members.has(b):
			_retire(b)
	_sound("commander_whistle", -12.0)
	hud.flash("%d soldiers hold behind you" % int(result.count))


func _soldier(rec: Dictionary) -> SoldierBrain:
	var id := int(rec.id)
	if _soldiers.has(id) and is_instance_valid(_soldiers[id]):
		return _soldiers[id]
	var brain := SoldierBrain.new()
	brain.name = "Brain"
	brain.team = "kingdom"
	brain.soldier_id = id
	brain.weapons_free = false
	# Created behind him; the escort places it before it is ever seen.
	var body := _body(player.global_position - player.forward() * 8.0, "soldier:kingdom", String(rec.name), true, brain)
	Combat.set_team(body.player_id, "kingdom")
	Combat.set_respawn_mode(body.player_id, Combat.Respawn.NEVER)
	body.combatant.set_health(clampi(int(rec.health), 1, body.combatant.max_health))
	brain.weapons_free = false
	brain.died.connect(func(b: SoldierBrain) -> void: roster.set_soldier(b.soldier_id, false, 0))
	_soldiers[id] = brain
	return brain


func _retire(b: SoldierBrain) -> void:
	if not is_instance_valid(b):
		return
	if b.is_alive():
		roster.set_soldier(b.soldier_id, true, b.avatar.combatant.health)
	_soldiers.erase(b.soldier_id)
	b.avatar.queue_free()


func _dismiss_escort() -> void:
	escort.clear()
	for b in _soldiers.values():
		_retire(b)
	_soldiers.clear()


func escort_brains() -> Array:
	return escort.living()


# --- the scripted army display (no attack token, no damage) -------------------------------------

func _start_army_demo() -> void:
	if not escort.active():
		toggle_escort()
	var f := station_frame("army")
	var right: Vector3 = Basis(Vector3.UP, f.yaw) * Vector3.RIGHT
	for i in Escort.SIZE:
		var pos := ground_near(f.at + f.ahead * 3.2 + right * (i - 1.5) * 1.8)
		var pawn := _body(pos, "soldier:enemy", "Black Guard", false)
		pawn.set_look(f.yaw + PI)
		_pawns.append(pawn)
	_demo_step = 0
	_demo_t = 0.5


func _tick_army_demo(delta: float) -> void:
	_demo_t -= delta
	var f := station_frame("army")
	if _demo_step == 2:
		_swing_t -= delta
		if _swing_t <= 0.0:
			_swing_t = 0.55
			var line: Array = escort.living().map(func(b) -> PlayerController: return b.avatar) + _pawns
			if not line.is_empty():
				var actor: PlayerController = line[randi() % line.size()]
				var visual := actor.get_node_or_null("AvatarVisual") as AvatarVisual
				if visual:
					visual.human_rig.play("attack", 0.6)
					visual.play_sound("sword_swing", -14.0)
	if _demo_t > 0.0:
		return
	match _demo_step:
		0:
			if escort.command("advance", ground_near(f.at + f.ahead * 1.4)):
				hud.flash("Soldiers: advance in formation")
			_demo_t = 6.0
		1:
			hud.flash("Soldiers: engage")
			_demo_t = 8.0
		2:
			escort.command("retreat", ground_near(f.at - f.ahead * 3.0))
			hud.flash("Soldiers: fall back")
			_demo_t = 5.0
		3:
			escort.command("regroup")
			hud.flash("Soldiers: regroup and hold")
			_clear_pawns()
			_demo_step = -1
			return
	_demo_step += 1


func _clear_pawns() -> void:
	for pawn in _pawns:
		if is_instance_valid(pawn):
			pawn.queue_free()
	_pawns.clear()


# --- input and the clock ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not ready_done or event.is_echo():
		return
	if event.is_action_pressed("army_command"):
		toggle_escort()
	elif event.is_action_pressed("training_skip") and training.active:
		training.skip()
	elif event.is_action_pressed("training_leave") and training.active:
		training.stop()
		clear_station()
		hud.flash("You leave the training. [1] returns to it.")
	elif event.is_action_pressed("training_retry"):
		retry()
	elif event is InputEventKey and event.pressed and KEYS.has((event as InputEventKey).physical_keycode):
		if KEYS[event.physical_keycode] == "spawn":
			clear_station()
			station = "spawn"
			if player.is_defeated:
				Combat.revive(player.player_id, player.global_position, player.rotation.y)
		else:
			start_station(KEYS[event.physical_keycode])
	else:
		return
	get_viewport().set_input_as_handled()


func retry() -> void:
	if training.active:
		training.start(training.lesson)
	elif station != "spawn":
		start_station(station)
	elif player.is_defeated:
		Combat.revive(player.player_id, player.global_position, player.rotation.y)


func _physics_process(delta: float) -> void:
	if not ready_done:
		return
	if _demo_step >= 0:
		_tick_army_demo(delta)
	if not _won and not enemies.is_empty() and enemies.all(func(a) -> bool: return not is_instance_valid(a) or a.is_defeated):
		_won = true
		_sheathe_t = 3.0
		hud.banner("The field is yours\n[%s] fight again" % Settings.get_binding_text("training_retry"), 4.0)
		if not Settings.reduce_motion:
			player.cam.emphasize(2.0, 1.25, 2.0)
		_sound("power_up", -14.0)
	if _sheathe_t > 0.0:
		_sheathe_t -= delta
		if _sheathe_t <= 0.0:
			var visual := player.get_node_or_null("AvatarVisual") as AvatarVisual
			if visual and visual.human_rig is CommanderRig and not Combat.is_busy(player.player_id):
				(visual.human_rig as CommanderRig).sheath_sword()


# --- events -------------------------------------------------------------------------------------

func _on_defeated(event: Dictionary) -> void:
	if event.victim != player.player_id:
		return
	for actor in enemies:
		if is_instance_valid(actor):
			Combat.cancel_attack(actor.player_id, "commander defeated")
	hud.banner("You have fallen\n[%s] try again    [0] clear the field" % Settings.get_binding_text("training_retry"), 3600.0)


func _on_training_changed() -> void:
	if training.active:
		hud.lesson_text("%s\n%s\n[%s] retry   [%s] skip   [%s] leave" % [training.title(), training.instruction(),
			Settings.get_binding_text("training_retry"), Settings.get_binding_text("training_skip"), Settings.get_binding_text("training_leave")])
	else:
		hud.lesson_text("")


func _on_training_feedback(text: String, good: bool) -> void:
	hud.flash(text, good)
	if good:
		_sound("power_up", -18.0)


func _on_training_finished(done: bool) -> void:
	if done:
		station = "spawn"
		hud.banner("Training complete\n[2]-[4] test yourself", 5.0)


func _sound(sound_name: String, volume: float) -> void:
	var stream := AudioLib.get_instance().get_stream(sound_name)
	if stream == null or not is_inside_tree():
		return
	var audio := AudioStreamPlayer.new()
	add_child(audio)
	audio.stream = stream
	audio.volume_db = volume
	audio.finished.connect(audio.queue_free)
	audio.play()
