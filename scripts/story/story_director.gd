class_name StoryDirector
extends Node
## Local story sequences: talk to characters, read dialogue, follow objectives.
## World builders publish named staging points (Sites.story_anchors); this node
## spawns characters and triggers there. It never touches Combat, PowerScore or
## the secret identity, so it can stay client-side when multiplayer arrives.
##
## Sequences:
## - "missing_child": Maren, an old woman in Ashford, asks the commander to find
##   her grandson Tam. Three clues lead from the village to the lake shore.
## - "night_before_war": the commander studies the battle maps in his bedroom,
##   cannot sleep, climbs to the keep roof and finds Princess Reve watching the
##   moon. She notices him arrive, they talk quietly about the battle, and she
##   returns her gaze to the sky. (She is not introduced before this sequence.)

signal objective_changed(text: String)
signal flag_set(flag: String)
signal dialogue_finished

## Multiplies dialogue line durations (tests use a small value).
var speed := 1.0
var flags := {}
var objective := ""
var in_dialogue := false
var npcs := {}  ## name -> StoryNPC
var triggers := {}  ## name -> Interactable

var world: World
var player: PlayerController
var hud: HUD
var _anchors := {}
var _skip := false
var voice: AudioStreamPlayer
var voice_map: Dictionary = {}


func setup(w: World, p: PlayerController, h: HUD) -> void:
	world = w
	player = p
	hud = h
	voice=AudioStreamPlayer.new()
	voice.name="DialogueVoice"
	add_child(voice)
	voice.volume_db=-8
	voice_map=JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue_voices.json"))
	var sites := world.get_node_or_null("Sites/Structures")
	if sites and "story_anchors" in sites:
		_anchors = sites.story_anchors
	_setup_bedroom()
	_setup_village()


func has_anchor(anchor: String) -> bool:
	return _anchors.has(anchor)


func anchor_pos(anchor: String) -> Vector3:
	var a: Variant = _anchors.get(anchor, Vector3.ZERO)
	return a["pos"] if a is Dictionary else a


func anchor_yaw(anchor: String) -> float:
	var a: Variant = _anchors.get(anchor, 0.0)
	return float(a.get("yaw", 0.0)) if a is Dictionary else 0.0


func set_flag(flag: String) -> void:
	flags[flag] = true
	flag_set.emit(flag)


func has_flag(flag: String) -> bool:
	return flags.get(flag, false)


func set_objective(text: String) -> void:
	objective = text
	if hud:
		hud.set_objective(text)
	objective_changed.emit(text)


# --- dialogue ----------------------------------------------------------------------

## Plays [speaker, line] pairs; the interact key skips to the next line. Movement
## is paused and the view turns towards `face` (a Node3D) while it plays.
func play_dialogue(lines: Array, face: Node3D = null, npc: StoryNPC = null) -> void:
	while in_dialogue:
		await dialogue_finished
	in_dialogue = true
	var had_controls := player.controls_enabled
	player.controls_enabled = false
	var cmd := commander()
	if cmd and face:
		# Look at the speaker's face, not their feet (same height the camera uses).
		var eyes := face.get_node_or_null("LookAt") as Node3D
		if eyes == null:
			eyes = Node3D.new()
			eyes.name = "LookAt"
			face.add_child(eyes)
			eyes.position.y = 1.45
		cmd.look_target = eyes
	for line in lines:
		var speaker: String = line[0]
		var text: String = line[1]
		if hud:
			hud.show_dialogue(speaker, text)
		var duration := (1.4 + text.length() * 0.052) * speed
		voice.stop()
		var path:=String(voice_map.get(speaker+"|"+text,""))
		if not path.is_empty() and ResourceLoader.exists(path):
			var stream:=load(path) as AudioStream
			if stream:
				voice.stream=stream
				voice.play()
				duration=stream.get_length()+0.15
		var npc_line := npc != null and speaker != "" and speaker != "Commander"
		if npc_line:
			npc.say_gesture(duration)
		if npc and npc.rig is ReveRig:
			# Her expression for her own lines; she listens while he speaks.
			var r := npc.rig as ReveRig
			if npc_line:
				r.expression = String(line[2]) if line.size() > 2 else ""
			elif speaker == "Commander" and r.mood == "":
				r.mood = "listen"
			if npc_line and r.mood == "listen":
				r.mood = ""
		if cmd:
			# Optional third element: the commander's expression for the line.
			if line.size() > 2 and not npc_line:
				cmd.expression = String(line[2])
			elif speaker == "Commander":
				cmd.expression = ""
			cmd.talking = speaker == "Commander"
			if speaker == "Commander" and cmd.current_hold() == "":
				cmd.play_story("idle_talk")
		_skip = false
		var t := 0.0
		while t < duration and not _skip:
			await get_tree().process_frame
			t += get_process_delta_time()
			if face and is_instance_valid(face):
				_turn_view_towards(face.global_position + Vector3.UP * 1.45)
	voice.stop()
	if hud:
		hud.hide_dialogue()
	if npc and npc.rig is ReveRig and npc.rig.mood == "listen":
		npc.rig.mood = ""
	if cmd:
		cmd.talking = false
		cmd.expression = ""
		cmd.look_target = null
		if cmd.current_hold() == "idle_talk":
			cmd.stop_story()
	player.controls_enabled = had_controls
	in_dialogue = false
	dialogue_finished.emit()


## The player's realistic commander body, or null (bots, tests with the explorer body).
func commander() -> CommanderRig:
	if player == null:
		return null
	var visual := player.get_node_or_null("AvatarVisual") as AvatarVisual
	return visual.human_rig as CommanderRig if visual else null


func _turn_view_towards(target: Vector3) -> void:
	var eye := player.eye_position()
	var d := target - eye
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	var cur_yaw := player.rotation.y
	var cur_pitch: float = player.head.rotation.x
	var k := minf(1.0, get_process_delta_time() * 3.0)
	player.set_look(cur_yaw + wrapf(yaw - cur_yaw, -PI, PI) * k, lerpf(cur_pitch, clampf(pitch, -0.6, 0.6), k))


func _unhandled_input(event: InputEvent) -> void:
	if in_dialogue and event.is_action_pressed("interact") and not event.is_echo():
		_skip = true
		get_viewport().set_input_as_handled()


func _notify(text: String, seconds := 4.0) -> void:
	if hud:
		hud.toast(text, seconds)


func _spawn_npc(npc_name: String, style: String, prompt: String, pos: Vector3, yaw: float, height: float) -> StoryNPC:
	var npc := StoryNPC.new()
	npc.name = npc_name
	world.add_child(npc)
	npc.setup(style, prompt, height)
	npc.global_position = pos
	npc.rotation.y = yaw
	npcs[npc_name] = npc
	return npc


func _make_trigger(trigger_name: String, prompt: String, pos: Vector3, radius := 0.6) -> Interactable:
	var it := Interactable.new()
	it.name = trigger_name
	it.prompt_text = prompt
	it.max_view_angle = 55.0
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var cs := CollisionShape3D.new()
	cs.shape = sphere
	it.add_child(cs)
	world.add_child(it)
	it.global_position = pos
	triggers[trigger_name] = it
	return it


# --- night before war ------------------------------------------------------------

func _setup_bedroom() -> void:
	if not has_anchor("commander_desk"):
		return
	var desk := _make_trigger("BattleMaps", "Study the battle maps", anchor_pos("commander_desk"), 0.7)
	desk.interacted.connect(_on_battle_maps)


func _on_battle_maps(_by: Node) -> void:
	if in_dialogue or has_flag("night_before_war"):
		return
	triggers["BattleMaps"].enabled = false
	set_flag("night_before_war")
	var cmd := commander()
	if cmd:
		cmd.play_story("study_map")
	await play_dialogue([
		["Commander", "Their fires were counted at the ford at dusk. More than yesterday.", "worried"],
		["Commander", "By first light they will be at the bridge.", "determined"],
		["", "Sleep will not come. The roof, then, and some air.", "tired"],
	])
	if cmd:
		cmd.stop_story()
	set_objective("Climb to the roof of the keep")
	if has_anchor("roof_reve"):
		var reve := _spawn_npc("Reve", "reve", "Speak with Princess Reve", anchor_pos("roof_reve"), anchor_yaw("roof_reve"), 1.63)
		reve.rig.mood = "gaze"
		_reve_rig().look_target = _moon_mark(reve)
		reve.talked.connect(_on_reve_talked)


func _reve_rig() -> ReveRig:
	var reve: StoryNPC = npcs.get("Reve")
	return reve.rig as ReveRig if reve else null


## A point far out along the moon's direction, for her head and eyes to follow.
func _moon_mark(npc: Node3D) -> Node3D:
	var mark := world.get_node_or_null("MoonMark") as Node3D
	if mark == null:
		mark = Node3D.new()
		mark.name = "MoonMark"
		world.add_child(mark)
	var dir := Vector3(-0.4, 0.6, -0.7)
	var moon := world.get_node_or_null("Moon") as Node3D
	if moon:
		dir = moon.global_transform.basis.z
	mark.global_position = npc.global_position + Vector3.UP * 1.5 + dir.normalized() * 400.0
	return mark


## She notices the commander arriving on the roof: the head turns first, then the
## body a little toward him. Polled while she waits.
func _process(_delta: float) -> void:
	if not npcs.has("Reve") or has_flag("reve_noticed") or in_dialogue or player == null:
		return
	var reve: StoryNPC = npcs["Reve"]
	var d := player.global_position - reve.global_position
	if absf(d.y) < 2.0 and Vector2(d.x, d.z).length() < 8.0:
		set_flag("reve_noticed")
		var rig := _reve_rig()
		if rig:
			rig.look_target = player.head
			rig.expression = "listening"
		var to_player := atan2(-d.x, -d.z)
		var home := anchor_yaw("roof_reve")
		reve.face_yaw(home + wrapf(to_player - home, -PI, PI) * 0.3, 1.4)


func _on_reve_talked(_by: Node) -> void:
	var reve: StoryNPC = npcs["Reve"]
	if in_dialogue or has_flag("rooftop_talk_done"):
		return
	reve.talk.enabled = false
	set_flag("reve_noticed")
	set_objective("")
	var rig := _reve_rig()
	var cmd := commander()
	if cmd:
		cmd.play_story("moon_gaze")
	# Still facing the sky; her eyes go back to the moon as she speaks.
	if rig:
		rig.look_target = _moon_mark(reve)
	await play_dialogue([
		["Reve", "You could not sleep either.", "wistful"],
		["Commander", "The maps do not change, however long I look at them.", "tired"],
	], reve, reve)
	if cmd:
		cmd.stop_story()
	reve.rig.mood = ""
	reve.face(player.global_position, 1.4)
	if rig:
		rig.look_target = player.head
	await play_dialogue([
		["Reve", "The scouts say their fires stretch past the ford. More than we counted.", "concern"],
		["Commander", "More than we counted. Not more than we can hold, if the bridge stands.", "determined"],
		["Reve", "And if it does not?", "concern"],
		["Commander", "Then we fall back to the walls, and make them pay for every step.", "angry"],
		["Reve", "My father came up here before every battle. He said the moon looks the same whether you win or lose.", "wistful"],
		["Commander", "Did he believe that?"],
		["Reve", "No. He said it so that I would.", "sad"],
		["Commander", "Tomorrow, stay behind the inner gate. Whatever you hear.", "determined"],
		["Reve", "Only if you promise to come back through it.", "resolve"],
		["Commander", "...I will come back.", "worried"],
		["Reve", "Then I will be there when you do.", "soft_smile"],
		["Reve", "Go and rest, Commander. One of us should.", "soft_smile"],
	], reve, reve)
	set_flag("rooftop_talk_done")
	reve.face_yaw(anchor_yaw("roof_reve"), 1.8)
	reve.rig.mood = "gaze"
	if rig:
		rig.expression = "wistful"
		rig.look_target = _moon_mark(reve)
	_notify("Dawn will come too soon.", 4.5)


# --- the missing child -------------------------------------------------------------

func _setup_village() -> void:
	if not has_anchor("elder"):
		return
	var elder := _spawn_npc("Maren", "elder", "Speak with the old woman", anchor_pos("elder"), anchor_yaw("elder"), 1.5)
	elder.rig.mood = "worried"
	elder.talked.connect(_on_elder_talked)
	for i in 3:
		var key := "clue_%d" % (i + 1)
		if not has_anchor(key):
			continue
		var clue := _make_trigger("Clue%d" % (i + 1), ["Look at the basket", "Look at the flowers", "Look at the small shoe"][i], anchor_pos(key), 0.55)
		clue.enabled = false
		clue.interacted.connect(_on_clue.bind(i + 1))


func _on_elder_talked(_by: Node) -> void:
	var elder: StoryNPC = npcs["Maren"]
	if in_dialogue:
		return
	if not has_flag("child_quest_started"):
		elder.talk.enabled = false
		await play_dialogue([
			["Old woman", "Commander? Forgive me, my lord. I would not stop you if I had anyone else."],
			["Commander", "What has happened?", "worried"],
			["Maren", "My grandson, Tam. He went down to the lake for flowers this morning, for his mother's grave."],
			["Maren", "He always comes back before the bells. He has not come back."],
			["Commander", "Which way did he go?"],
			["Maren", "West, past the well and down the shore path. He takes his little basket."],
			["Commander", "I will find him. Stay here, in case he comes home another way.", "determined"],
		], elder, elder)
		set_flag("child_quest_started")
		set_objective("Search the lake shore west of Ashford for Tam")
		elder.talk.prompt_text = "Speak with Maren"
		elder.talk.enabled = true
		for t in ["Clue1", "Clue2", "Clue3"]:
			if triggers.has(t):
				triggers[t].enabled = true
		_spawn_child()
	elif has_flag("child_returned") and not has_flag("child_quest_done"):
		elder.talk.enabled = false
		elder.rig.mood = ""
		var child: StoryNPC = npcs.get("Tam")
		await play_dialogue([
			["Maren", "He came running up the lane, soaked to the knees and grinning like a fool."],
			["Maren", "Thank you, my lord. I know what tomorrow holds for you. You still came."],
			["Commander", "Keep him close to home for a few days.", "smirk"],
		], elder, elder)
		set_flag("child_quest_done")
		set_objective("")
		elder.talk.prompt_text = "Maren"
		elder.talk.enabled = false
		if child:
			child.talk.enabled = false
	else:
		await play_dialogue([["Maren", "Please, the shore path. He would not go far."]], elder, elder)


func _on_clue(_by: Node, index: int) -> void:
	if in_dialogue or has_flag("clue_%d" % index):
		return
	set_flag("clue_%d" % index)
	triggers["Clue%d" % index].enabled = false
	match index:
		1:
			_notify("A child's basket, tipped over. Half the flowers are still in it.")
			set_objective("Follow the shore path towards the lake")
		2:
			_notify("Fresh marsh flowers, dropped in a line towards the water.")
			set_objective("Search the reeds along the lake shore")
		3:
			_notify("A small shoe, stuck in the mud. Someone is close.")
			set_objective("Find Tam at the water's edge")


func _spawn_child() -> void:
	if not has_anchor("child") or npcs.has("Tam"):
		return
	var child := _spawn_npc("Tam", "child", "Talk to the boy", anchor_pos("child"), anchor_yaw("child"), 1.15)
	child.rig.mood = "worried"
	child.talked.connect(_on_child_talked)


func _on_child_talked(_by: Node) -> void:
	var child: StoryNPC = npcs["Tam"]
	if in_dialogue or has_flag("child_returned"):
		return
	child.talk.enabled = false
	child.face(player.global_position, 0.5)
	await play_dialogue([
		["Boy", "I wasn't lost. I was getting the white ones. They only grow right by the water."],
		["Commander", "Your grandmother thinks the lake has taken you.", "smirk"],
		["Tam", "My foot went in the mud and the shoe stayed there. I didn't want to go back with one shoe."],
		["Commander", "I found your shoe. Go home, Tam. Straight up the path, and let her see you."],
		["Tam", "Yes, Commander."],
	], child, child)
	set_flag("child_returned")
	set_objective("Return to Maren in Ashford")
	child.rig.mood = ""
	if has_anchor("child_home"):
		var home := anchor_pos("child_home")
		var dir := Vector3(home.x - child.global_position.x, 0, home.z - child.global_position.z).normalized()
		var away := child.global_position + dir * 4.5
		away.y = world.terrain_height(away.x, away.z)
		child.face(home, 0.3)
		var tween := child.create_tween()
		tween.tween_interval(0.3)
		tween.tween_property(child, "global_position", away, 2.2)
		tween.tween_callback(func() -> void:
			child.visible = false
			child.global_position = home
			child.rotation.y = anchor_yaw("child_home"))
		tween.tween_interval(1.5)
		tween.tween_callback(func() -> void: child.visible = true)
