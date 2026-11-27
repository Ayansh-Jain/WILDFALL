extends Node3D
## Interactive A-E scenarios, isolated from campaign persistence.
const PLAYER = preload("res://scenes/player/player.tscn")
const DIRECTOR = preload("res://scripts/combat/combat_director.gd")
const LEDGER = preload("res://scripts/battle/p11_ledger.gd")
var player: PlayerController
var director: Node
var enemies: Array = []
var roster = LEDGER.new()
var roster_actors := {}
var crowd: Node3D
var label: Label
var scenario := 0
var last_event := ""
var automated := false
var pair_cue_at := 0.0
var pair_turn := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--r02-automated":
			automated = true
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.12, 0.17, 0.22)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.8, 0.85, 1)
	settings.ambient_light_energy = 0.7
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 1.8
	add_child(sun)
	box(Vector3(0,-0.5,0), Vector3(70,1,90), Color(0.24,0.30,0.23))
	box(Vector3(-8,1.5,-3), Vector3(1,3,14), Color(0.35,0.33,0.3))
	box(Vector3(8,1.5,-3), Vector3(1,3,14), Color(0.35,0.33,0.3))
	player = PLAYER.instantiate()
	player.is_local = true
	player.display_name = "Commander"
	add_child(player)
	player.teleport(Vector3(0,0.1,3))
	Combat.set_team(player.player_id, "kingdom")
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.HOLD)
	director = DIRECTOR.new()
	director.commander = player
	add_child(director)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(20,20)
	canvas.add_child(label)
	Combat.swords.event.connect(feedback)
	Combat.damage_dealt.connect(on_damage)
	load_scenario(0)
	if not automated:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = size
	mesh.mesh = geometry
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
	body.position = pos

func spawn_actor(pos: Vector3, enemy := true) -> PlayerController:
	var actor: PlayerController = PLAYER.instantiate()
	actor.is_local = false
	actor.is_bot = true
	actor.body_style = "soldier:enemy" if enemy else "soldier:kingdom"
	add_child(actor)
	actor.teleport(pos, PI if enemy else 0.0)
	actor.input_override = {}
	Combat.set_team(actor.player_id, "enemy" if enemy else "kingdom")
	Combat.set_respawn_mode(actor.player_id, Combat.Respawn.NEVER)
	enemies.append(actor)
	return actor

func load_scenario(index: int) -> void:
	for id in director.members.keys():
		director.unregister_enemy(id)
	for actor in enemies:
		if is_instance_valid(actor):
			Combat.unregister(actor.player_id)
			actor.queue_free()
	enemies.clear()
	roster_actors.clear()
	if is_instance_valid(crowd):
		remove_child(crowd) # Unregister old logical identities before reusing roster ids.
		crowd.queue_free()
	scenario = index
	Combat.revive(player.player_id, Vector3(0,0.1,3), 0.0)
	Combat.configure_sword_actor(player.player_id)
	director.turn = 0
	director.schedule_at = Combat.now() + 1.0
	var counts := [1,5,10,1,2]
	for i in counts[index]:
		var angle: float = float(i) * TAU / counts[index]
		var pos := Vector3(sin(angle)*4, 0.1, -1-cos(angle)*3)
		var actor := spawn_actor(pos, not (index == 4 and i == 1))
		var pattern: String = "elite" if index == 3 else ["standard","aggressive","heavy","defensive","standard"][i % 5]
		director.register_enemy(actor, "arena", pattern, index == 4)
		if index == 4:
			roster_actors[actor.player_id] = "e.000" if i == 0 else "a.000"
			actor.teleport(Vector3(-1 if i == 0 else 1,0.1,-1), PI if i == 0 else 0)
	if index == 4:
		roster.setup()
		build_crowd()
	last_event = "Ready"

func build_crowd() -> void:
	crowd = preload("res://scripts/battle/battle_presentation.gd").new()
	add_child(crowd)
	crowd.setup(roster, player)

func on_damage(data: Dictionary) -> void:
	if scenario != 4 or not roster_actors.has(data.target):
		return
	var id: String = roster_actors[data.target]
	roster.interrupt(id)
	if data.health_after <= 0:
		roster.fall(id, "player")
	last_event = "Pair 000 interrupted; partner survives; roster updated"

func feedback(data: Dictionary) -> void:
	last_event = str(data.kind)
	if data.kind == "telegraph":
		last_event = str(data.get("class", "normal")) + " attack ? " + str(data.get("attack", ""))
	if data.kind in ["parry","perfect_parry","block","guard_break"]:
		var actor = Combat.avatar(data.actor)
		if is_instance_valid(actor):
			var visual = actor.get_node_or_null("AvatarVisual")
			if visual:
				visual.human_rig.play("ward" if data.kind != "guard_break" else "stagger", 0.35)
				visual.play_sound("ward", -5.0)
		if data.actor == player.player_id:
			player.cam.impact(0.25)

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	label.text = "R02 COMBAT | %s | HP %d\n1 Duel  2 Five enemies  3 Ten enemies  4 Elite  5 Army pair\nLMB attack (late press links combo) | RMB guard/parry | Q dodge\nZ sweep | F execute vulnerable target | T reserves | R retry | Esc mouse\n%s | token %d | reactive %d" % [["A","B","C","D","E"][scenario], player.combatant.health,last_event,Combat.swords.token_actor,reactive_count()]

func reactive_count() -> int:
	var count := 0
	for state in Combat.swords.actors.values():
		if state.reactive:
			count += 1
	return count

func _input(event: InputEvent) -> void:
	if automated or not is_instance_valid(player):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Combat.set_guard(player.player_id, event.pressed)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			load_scenario(event.keycode-KEY_1)
		elif event.keycode == KEY_T and scenario == 4:
			crowd.summon_reserves(player.global_position, player.rotation.y)
		elif event.keycode == KEY_R:
			load_scenario(scenario)
		elif event.keycode == KEY_F:
			Combat.request_action(player.player_id, "execute")
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		else:
			return
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_instance_valid(player):
		Combat.swords.remove(player.player_id)


func _physics_process(_delta: float) -> void:
	if scenario != 4 or not roster.pairs.has("pair.000") or not roster.pairs["pair.000"].active or Combat.now() < pair_cue_at:
		return
	pair_cue_at = Combat.now()+1.2
	pair_turn += 1
	for i in mini(enemies.size(),2):
		var actor = enemies[i]
		if is_instance_valid(actor) and actor.combatant.is_alive():
			var visual = actor.get_node_or_null("AvatarVisual")
			if visual:
				visual.human_rig.play("attack" if i == pair_turn%2 else "ward",0.8)
