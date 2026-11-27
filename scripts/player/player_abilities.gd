class_name PlayerAbilities
extends Node
## Turns the local player's input into requests to the Combat authority.
## Bots and tests call Combat directly; nothing here decides outcomes.
##
## R02: when the Commander is a "sword actor" (Combat.configure_sword_actor, used by the
## arena and training) this is also the player-side adapter for Codex's dual-sword combat:
## guard / parry hold, one short input buffer, soft facing, contextual finisher, the
## guard pose and camera / sound feedback. It stores no combat state of its own.

const ACTIONS := ["attack", "special_attack", "heavy_attack", "ability_1", "ability_2"]
## A press refused only because of timing is retried for this long, then forgotten.
const BUFFER_SECONDS := 0.2
const ASSIST_RANGE := 3.2
## Never turn toward anything further than this from the facing (never behind him).
const ASSIST_CONE := deg_to_rad(70.0)
const ASSIST_MAX_TURN := deg_to_rad(28.0)
const ASSIST_TIME := 0.1
const TRANSIENT := ["busy or buffer full", "recovery/state", "dodge recovery", "committed", "busy"]

var _buffered := ""
var _buffer_t := 0.0
var _guard_held := false
var _guard_from_input := false
var _guard_up := false
var _guard_retry := 0.0
var _assist := 0.0

@onready var player: PlayerController = get_parent()


func _ready() -> void:
	if player.is_local and not player.is_bot:
		Combat.swords.event.connect(_on_combat_event)
	else:
		set_physics_process(false)


func _exit_tree() -> void:
	if Combat.swords.event.is_connected(_on_combat_event):
		Combat.swords.event.disconnect(_on_combat_event)


## True while the Commander fights with the dual-sword system.
func sword_mode() -> bool:
	return player.player_id >= 0 and Combat.swords.actors.has(player.player_id) and not GameState.is_revealed(player.player_id)


func _blocked() -> bool:
	return not player.is_local or not player.controls_enabled or player.is_defeated or player.locks.blocks(ControlLock.COMBAT | ControlLock.PAUSE)


func _rig() -> CommanderRig:
	var visual := player.get_node_or_null("AvatarVisual") as AvatarVisual
	return visual.human_rig as CommanderRig if visual else null


func _unhandled_input(event: InputEvent) -> void:
	if _guard_held and event.is_action_released("guard"):
		guard(false)
		return
	if _blocked():
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_echo():
		return
	if event.is_action_pressed("toggle_lamp"):
		player.portable_lamp_on = not player.portable_lamp_on
		var rig := _rig()
		if rig:
			rig.set_lamp_enabled(player.portable_lamp_on)
		get_viewport().set_input_as_handled()
		return
	if player.riding:
		return
	if event.is_action_pressed("transform"):
		trigger("transform")
		return
	if event.is_action_pressed("toggle_weapons"):
		var rig := _rig()
		if rig and not GameState.is_revealed(player.player_id) and not Combat.is_transforming(player.player_id):
			guard(false)
			rig.toggle_swords()
			(player.get_node("AvatarVisual") as AvatarVisual).play_sound("sword_swing", -16.0, 1.6)
			get_viewport().set_input_as_handled()
		return
	# Right mouse guards in sword mode; elsewhere it keeps its older meanings below.
	if sword_mode() and event.is_action_pressed("guard"):
		_guard_from_input = true
		guard(true)
		get_viewport().set_input_as_handled()
		return
	for action in ACTIONS:
		if event.is_action_pressed(action):
			# The human's right-hand attack is the alternate sword cut while the paired
			# blades are drawn. Other forms retain their existing heavy-attack binding.
			if action == "heavy_attack":
				var rig := _rig()
				if rig and rig.sword_drawn and not GameState.is_revealed(player.player_id):
					action = "attack"
			trigger(action)
			return


## Sends an action as if its key was pressed. Returns Combat's result.
func trigger(action: String) -> Dictionary:
	if action == "transform":
		if GameState.is_revealed(player.player_id):
			return Combat.request_revert(player.player_id)
		return Combat.request_transform(player.player_id)
	if not sword_mode():
		return Combat.request_action(player.player_id, action)
	if _blocked():
		return {"ok": false, "reason": "controls locked"}
	var result := _sword_request(action)
	if not result.get("ok", false) and String(result.get("reason", "")) in TRANSIENT:
		_buffered = action
		_buffer_t = BUFFER_SECONDS
	else:
		_buffered = ""
	return result


func _sword_request(action: String) -> Dictionary:
	var id := player.player_id
	if action == "ability_2":
		return Combat.request_ability(id, "ward")  # the Ward is kept alongside the swords
	if action in ["attack", "special_attack"]:
		if player.riding:
			return {"ok": false, "reason": "mounted"}
		_ready_swords()
	var result: Dictionary = {"ok": false}
	# Z: the contextual finishing strike when an opening is there, the sweep otherwise.
	if action == "special_attack":
		result = Combat.request_action(id, "execute")
	if not result.get("ok", false):
		if action == "attack" and not Combat.swords.attacks.has(id):
			_start_assist()
		result = Combat.request_action(id, action)
	if result.get("ok", false) and action == "ability_1":
		_drop_guard_pose()
	return result


## The attack needs the blades in hand now: a draw animation would be cancelled by the cut.
func _ready_swords() -> void:
	var rig := _rig()
	if rig and not rig.sword_drawn:
		rig._put_sword(true)


## Raise (true) or lower (false) the guard. A press during a recovery is retried briefly.
func guard(pressed: bool) -> bool:
	if not sword_mode():
		return false
	_guard_held = pressed
	if not pressed:
		_guard_from_input = false
		_guard_retry = 0.0
		Combat.set_guard(player.player_id, false)
		_drop_guard_pose()
		return true
	if _blocked() or player.riding:
		return false
	_guard_retry = BUFFER_SECONDS
	return _raise_guard()


func _raise_guard() -> bool:
	_ready_swords()
	if not Combat.set_guard(player.player_id, true):
		return false
	_guard_retry = 0.0
	_guard_up = true
	var rig := _rig()
	if rig:
		rig.hold("sword_block")
	return true


func _drop_guard_pose() -> void:
	if not _guard_up:
		return
	_guard_up = false
	var rig := _rig()
	if rig and rig.current_hold() == "sword_block":
		rig.release()


func _physics_process(delta: float) -> void:
	var rig := _rig()
	if not sword_mode():
		_buffered = ""
		_guard_held = false
		_drop_guard_pose()
		if rig:
			rig.face_forward = false
		return
	var id := player.player_id
	if _blocked() or player.riding:
		_buffered = ""
		if _guard_held:
			guard(false)
	elif _guard_held and _guard_from_input and not Input.is_action_pressed("guard"):
		guard(false)  # released while a menu had the input
	if _guard_retry > 0.0 and _guard_held:
		_guard_retry -= delta
		_raise_guard()
	# Combat drops the guard itself (block, guard break, death): the pose follows.
	if _guard_up and not bool(Combat.swords.actors[id].guard):
		_drop_guard_pose()
	if _buffered != "":
		_buffer_t -= delta
		if _buffer_t <= 0.0 or _sword_request(_buffered).get("ok", false):
			_buffered = ""
	if _assist != 0.0:
		var step := clampf(_assist, -ASSIST_MAX_TURN * delta / ASSIST_TIME, ASSIST_MAX_TURN * delta / ASSIST_TIME)
		player.rotate_y(step)
		_assist -= step
		if absf(_assist) < 0.002:
			_assist = 0.0
	if rig:
		rig.face_forward = _guard_up or Combat.swords.attacks.has(id)


## Soft facing: a small turn toward the opponent he evidently means to cut. Respects the
## movement direction, the facing, range, height and walls.
func assist_angle() -> float:
	var intent := player.forward()
	var move := Vector2.ZERO
	if player.input_override is Dictionary:
		move = player.input_override.get("move", Vector2.ZERO)
	elif player.controls_enabled:
		move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if move.length() > 0.2:
		intent = (Basis(Vector3.UP, player.rotation.y) * Vector3(move.x, 0.0, -move.y)).normalized()
	var space := player.get_world_3d().direct_space_state
	var chest := player.global_position + Vector3.UP
	var best := INF
	var turn := 0.0
	for other in Combat.actor_ids():
		if other == player.player_id or Combat.team_of(other) == "" or not Combat.are_hostile(player.player_id, other):
			continue
		var av := Combat.avatar(other)
		if av == null or av.is_defeated:
			continue
		var to := av.global_position - player.global_position
		if absf(to.y) > 1.5:
			continue
		to.y = 0.0
		var dist := to.length()
		if dist > ASSIST_RANGE or dist < 0.2:
			continue
		var from_facing := player.forward().signed_angle_to(to.normalized(), Vector3.UP)
		var from_intent := intent.angle_to(to.normalized())
		if absf(from_facing) > ASSIST_CONE or from_intent > ASSIST_CONE:
			continue
		if not LineOfSight.is_clear(space, chest, av.global_position + Vector3.UP, [player.get_rid(), av.get_rid()], Layers.WORLD):
			continue
		var score := from_intent + dist * 0.2
		if score < best:
			best = score
			turn = clampf(from_facing, -ASSIST_MAX_TURN, ASSIST_MAX_TURN)
	return turn


func _start_assist() -> void:
	_assist = assist_angle()


## One read-only name for what the Commander is doing, derived from the real owners
## (Combat, the controller, the rig). Nothing stores it.
func combat_state_name() -> String:
	var id := player.player_id
	if player.is_defeated:
		return "DEAD"
	if player.riding:
		return "MOUNTED"
	if not player.controls_enabled or player.locks.blocks(ControlLock.COMBAT | ControlLock.PAUSE):
		return "RESTRICTED"
	if player.combatant.is_stunned():
		return "STAGGERED"
	if sword_mode():
		var state: Dictionary = Combat.swords.actors[id]
		if Combat.swords.attacks.has(id):
			match String(Combat.swords.attacks[id].definition.id):
				"dual_execute": return "FINISHER"
				"dual_counter": return "COUNTER"
			return "ATTACKING"
		if player.locomotion_state() == PlayerController.Loco.DASH:
			return "DODGING"
		if bool(state.guard):
			return "PARRY" if Combat.now() - float(state.guard_at) <= Combat.swords.guard_window else "GUARD"
	elif Combat.is_busy(id):
		return "ATTACKING"
	var rig := _rig()
	if rig and rig.sword_drawn:
		return "READY"
	return "EXPLORE"


func _on_combat_event(data: Dictionary) -> void:
	if int(data.get("actor", -1)) != player.player_id:
		return
	var cam := player.cam
	var calm := Settings.reduce_motion
	var visual := player.get_node_or_null("AvatarVisual") as AvatarVisual
	match String(data.kind):
		"requested":
			if not calm and data.get("attack") == "dual_execute":
				cam.emphasize(1.2, 0.72, -7.0)
			elif not calm and data.get("attack") == "dual_counter":
				cam.emphasize(0.4, 0.9, -3.0)
		"hit":
			if not (data.get("targets", []) as Array).is_empty():
				var strength := 0.12
				if Combat.pending_ability(player.player_id) in ["dual_heavy", "dual_sweep", "dual_execute", "dual_counter"]:
					strength = 0.4
				cam.impact(strength)
				if visual:
					visual.play_sound("hit", -8.0)
		"parry", "perfect_parry":
			var perfect: bool = data.kind == "perfect_parry"
			cam.impact(0.45 if perfect else 0.25)
			if perfect and not calm:
				cam.emphasize(0.5, 0.86, -4.0)
			if visual:
				visual.play_sound("ward", -6.0, 1.7 if perfect else 1.35)
			_guard_up = false
			var rig := _rig()
			if rig:
				rig.release()
				rig.play("ward", 0.35)
		"block":
			cam.impact(0.15)
			if visual:
				visual.play_sound("hit", -4.0, 1.5)
		"guard_break":
			cam.impact(0.6)
			if visual:
				visual.play_sound("heavy_slam", -8.0)
