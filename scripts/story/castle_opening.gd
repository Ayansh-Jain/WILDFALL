extends Node
## A locked bedroom, washroom kingdom reveal, summons and first royal briefing.
## Uses StoryDirector dialogue and existing CampaignDirector mission progression.
var story: StoryDirector
var sites: Sites
var player: PlayerController
var campaign: CampaignDirector
var active := false
var revealing := false
var reveal_done := false
var summons_done := false
var camera: Camera3D
var _controls_before := true
var _camera_before: Camera3D
var _skip := false
var _generation := 0
var _input_before: Variant = null
var _interactor_mode := Node.PROCESS_MODE_INHERIT

func begin(s: StoryDirector, c: CampaignDirector = null) -> void:
	story = s
	campaign = c
	player = story.player
	sites = story.world.get_node("Sites/Structures") as Sites
	_generation += 1
	active = false
	_skip = true
	while revealing:
		await get_tree().process_frame
	if story.in_dialogue:
		await story.dialogue_finished
	for key in ["castle_corridor_entered", "royal_hall_revealed", "castle_summons_delivered", "castle_opening_complete"]:
		story.flags.erase(key)
	if story.npcs.has("CastleMessenger"):
		story.npcs["CastleMessenger"].queue_free()
		story.npcs.erase("CastleMessenger")
	if story.triggers.has("OpeningGateAudience"):
		story.triggers["OpeningGateAudience"].queue_free()
		story.triggers.erase("OpeningGateAudience")
	if campaign and is_instance_valid(campaign.king):
		campaign.king.global_position = story.anchor_pos("king_throne")
		campaign.king.rotation.y = story.anchor_yaw("king_throne")
		(campaign.king.rig as KingRig).seated = true
		campaign.king.talk.enabled = true
	active = true
	player.controls_enabled = true
	reveal_done = false
	summons_done = false
	sites.bedroom_door.rotation.y = 0
	sites.castle_keep.get_node("BedroomBalconyDoor").rotation.y = PI * 0.5
	sites.bedroom_door.set_meta("opened", false)
	var door_it := sites.bedroom_door.get_node("OpenBedroomDoor") as Interactable
	door_it.enabled = false
	door_it.monitorable = true
	player.teleport(story.anchor_pos("commander_spawn"), story.anchor_yaw("commander_spawn"))
	var cycle := story.world.get_node("DayNightCycle") as DayNightCycle
	cycle.advance_to_hour(8.0)
	if story.triggers.has("BattleMaps"):
		story.triggers["BattleMaps"].enabled = false
	story.set_objective("Step into the washroom beside the bedroom washstand")
	story._notify("Morning at Lakeside Castle", 3.5)

func _process(_delta: float) -> void:
	if not active or not is_instance_valid(player):
		return
	if revealing or story.in_dialogue:
		return
	var p := sites.castle_from_world(player.global_position)
	if not reveal_done and p.y > 12 and p.y < 16 and p.z > -15.3 and p.z < -12.2 and p.x < -6.8 and p.x > -9.5:
		_reveal()

func _unhandled_input(event: InputEvent) -> void:
	if revealing and event.is_action_pressed("interact"):
		_skip = true
		get_viewport().set_input_as_handled()

func _reveal() -> void:
	var generation := _generation
	reveal_done = true
	revealing = true
	_skip = false
	_controls_before = player.controls_enabled
	_camera_before = get_viewport().get_camera_3d()
	player.controls_enabled = false
	_interactor_mode = player.get_node("Interactor").process_mode
	player.get_node("Interactor").process_mode = Node.PROCESS_MODE_DISABLED
	player.velocity = Vector3.ZERO
	_input_before = player.input_override
	player.input_override = {}
	camera = Camera3D.new()
	camera.name = "RoyalHallRevealCamera"
	camera.fov = 65
	add_child(camera)
	camera.global_transform = _camera_before.global_transform
	camera.make_current()
	if campaign:
		campaign.chud.banner("WILDFALL", "The Commander's First War", 4.6)
	# Positions in the existing world: river, waterfall, memorial, town.
	var shots := [
		[Vector3(42, 8, 157), Vector3(58, 1, 172), 2.0],
		[Vector3(87, 27, -278), Vector3(68, 12, -307), 2.0],
		[Vector3(-20, 12, 24), Vector3(0, 1, 0), 2.0],
		[Vector3(151, 31, 153), Vector3(205, 3, 205), 2.0],
	]

	for shot in shots:
		var target := Transform3D.IDENTITY
		target.origin = shot[0]
		target = target.looking_at(shot[1], Vector3.UP)
		await _camera_leg(target, shot[2] * story.speed)
		if _skip or player.is_defeated:
			break
	if not _skip and not player.is_defeated:
		await _camera_leg(_camera_before.global_transform, 1.0 * story.speed)
	_restore_camera()
	story.set_flag("royal_hall_revealed")
	player.controls_enabled = false
	await story.play_dialogue([["Commander", "Oh, what a beautiful empire I live in. To protect this land, I would give everything I have."]])
	if generation != _generation:
		return
	await _summons()
	if generation == _generation:
		player.input_override = _input_before
		player.controls_enabled = true

func _camera_leg(target: Transform3D, seconds: float) -> void:
	var start := camera.global_transform
	var elapsed := 0.0
	while elapsed < seconds and not _skip and not player.is_defeated:
		await get_tree().process_frame
		if get_tree().paused:
			continue
		elapsed += get_process_delta_time()
		camera.global_transform = start.interpolate_with(target, smoothstep(0, 1, minf(elapsed / seconds, 1)))

func _restore_camera() -> void:
	if is_instance_valid(_camera_before):
		_camera_before.make_current()
	if is_instance_valid(camera):
		camera.queue_free()
	camera = null
	if is_instance_valid(player):
		player.controls_enabled = _controls_before
		player.get_node("Interactor").process_mode = _interactor_mode
	revealing = false

func _exit_tree() -> void:
	if revealing:
		_restore_camera()

func _summons() -> void:
	var generation := _generation
	summons_done = true # Set before awaiting, so backing into the volume cannot duplicate it.
	var messenger := story._spawn_npc("CastleMessenger", "soldier", "", sites.castle_to_world(Vector3(-6.5, 12.75, -4.5)), 0, 1.8)
	messenger.talk.enabled = false
	messenger.face(player.global_position, 0.3)
	if campaign:
		campaign.play_transition_sound("door_knock")
	await story.play_dialogue([["Soldier", "Commander, the king is summoning you to the throne in the great royal hall."]], messenger, messenger)
	if generation != _generation:
		return
	story.set_flag("castle_summons_delivered")
	(sites.bedroom_door.get_node("OpenBedroomDoor") as Interactable).enabled = true
	_finish()

func _finish() -> void:
	active = false
	story.set_flag("castle_opening_complete")
	story.set_objective("Approach the King seated in the great royal hall")
	if story.triggers.has("BattleMaps"):
		story.triggers["BattleMaps"].enabled = not story.has_flag("night_before_war")
	if campaign:
		campaign.opening_completed = true
		campaign.save()
