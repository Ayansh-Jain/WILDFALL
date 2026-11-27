class_name TrainingSession
extends Node
## Reusable interactive combat training (R02; later the childhood memories). A step only
## advances on a real combat outcome reported by Combat, never on a key press alone.
##
## The host scene supplies the place and the people:
##   spawn_fighter.call(slot: int) -> PlayerController   (enemy team, unarmed AI)
##   remove_fighter.call(actor)
##   reset_player.call()                                 (back to the training mark)
## Training safety (health restored, instructor cannot fall, closed guard) applies only to
## the people it spawned and ends with the session.

signal changed
signal feedback(text: String, good: bool)
signal finished(completed: bool)

const DATA := "res://data/training.json"
const INSTRUCTOR_HEALTH := 1000
const YIELD_HEALTH := 30
const ATTACK_EVERY := 2.6
const ENCOUNTER := "training"

var player: PlayerController
var director: Node
var spawn_fighter: Callable
var remove_fighter: Callable
var reset_player: Callable

var lessons: Array = []
var lesson := -1
var step := 0
var active := false
var enemies: Array = []
var goals := {"combo": false, "parry": false, "dodge": false}
## Lesson ids completed by doing them (skipped ones are not listed).
var completed: Array[String] = []

var _attack_t := 1.5
var _next_t := -1.0
var _punish_until := 0.0
var _dodged := {}  ## enemy id -> the Commander dodged during this attack
var _struck := {}  ## enemy id -> this attack reached him
var _restart_wave := false


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if parsed is Dictionary:
		lessons = parsed.get("lessons", [])


func setup(p_player: PlayerController, p_director: Node, spawn: Callable, remove: Callable, reset: Callable) -> void:
	player = p_player
	director = p_director
	spawn_fighter = spawn
	remove_fighter = remove
	reset_player = reset


func start(index := 0) -> void:
	if index < 0 or index >= lessons.size():
		_finish(true)
		return
	if not active:
		active = true
		Combat.swords.event.connect(_on_event)
		Combat.damage_dealt.connect(_on_damage)
	lesson = index
	step = 0
	_next_t = -1.0
	_attack_t = 1.8
	_restart_wave = false
	goals = {"combo": false, "parry": false, "dodge": false}
	_clear_enemies()
	_reset_player()
	if lesson_id() == "trial":
		_spawn_wave()
	else:
		var teacher: PlayerController = spawn_fighter.call(0)
		Combat.configure_sword_actor(teacher.player_id, true, ENCOUNTER)
		Combat.swords.allocate(teacher.player_id)
		teacher.combatant.set_max_health(INSTRUCTOR_HEALTH, false)
		teacher.combatant.set_health(INSTRUCTOR_HEALTH)
		enemies = [teacher]
	_apply_guard_rule()
	changed.emit()


func skip() -> void:
	if active:
		start(lesson + 1)


## Leaves training at any point without keeping any of its rules.
func stop() -> void:
	if not active:
		return
	active = false
	_next_t = -1.0
	Combat.swords.event.disconnect(_on_event)
	Combat.damage_dealt.disconnect(_on_damage)
	_clear_enemies()
	if is_instance_valid(player):
		Combat.cancel_attack(player.player_id, "training over")
		player.combatant.set_health(player.combatant.max_health)
	lesson = -1
	changed.emit()


func _exit_tree() -> void:
	if active:
		active = false
		Combat.swords.event.disconnect(_on_event)
		Combat.damage_dealt.disconnect(_on_damage)


func _finish(done: bool) -> void:
	stop()
	finished.emit(done)


# --- what the HUD shows -------------------------------------------------------------------------

func lesson_id() -> String:
	return String(lessons[lesson].id) if lesson >= 0 and lesson < lessons.size() else ""


func step_id() -> String:
	if lesson_id() == "" or step >= lessons[lesson].steps.size():
		return ""
	return String(lessons[lesson].steps[step].id)


func title() -> String:
	return String(lessons[lesson].title) if lesson_id() != "" else ""


func instruction() -> String:
	if step_id() == "":
		return "Well done." if active else ""
	var text := String(lessons[lesson].steps[step].text).format({
		"attack": Settings.get_binding_text("attack"), "guard": Settings.get_binding_text("guard"),
		"dodge": Settings.get_binding_text("ability_1"), "draw": Settings.get_binding_text("toggle_weapons"),
		"finish": Settings.get_binding_text("special_attack")})
	if lesson_id() == "trial":
		var alive := enemies.filter(func(a) -> bool: return is_instance_valid(a) and not a.is_defeated).size()
		return "%s\nStanding: %d    Combination [%s]   Parry [%s]   Dodge [%s]" % [text, alive,
			_mark("combo"), _mark("parry"), _mark("dodge")]
	return "%s\n(step %d of %d)" % [text, step + 1, lessons[lesson].steps.size()]


func _mark(key: String) -> String:
	return "done" if goals[key] else "  "


func intro() -> String:
	return String(lessons[lesson].get("intro", "")) if lesson_id() != "" else ""


# --- progression ----------------------------------------------------------------------------

func _advance() -> void:
	if step >= lessons[lesson].steps.size():
		return
	step += 1
	_attack_t = 1.4
	if step >= lessons[lesson].steps.size():
		if not completed.has(lesson_id()):
			completed.append(lesson_id())
		feedback.emit("Lesson complete", true)
		_next_t = 2.0
	else:
		feedback.emit("Good", true)
	_apply_guard_rule()
	changed.emit()


func _back(to_step: String, why: String) -> void:
	for i in lessons[lesson].steps.size():
		if lessons[lesson].steps[i].id == to_step:
			step = i
	_attack_t = 1.4
	feedback.emit(why, false)
	_apply_guard_rule()
	changed.emit()


## While he is the one attacking, the instructor's guard is closed.
func _apply_guard_rule() -> void:
	if lesson_id() == "trial":
		return
	for a in enemies:
		if is_instance_valid(a):
			a.set_meta("duel_locked", step_id() in ["parry", "perfect", "dodge"])


func _reset_player() -> void:
	var id := player.player_id
	Combat.cancel_attack(id, "training reset")
	if reset_player.is_valid():
		reset_player.call()
	Combat.configure_sword_actor(id)
	player.combatant.invulnerable_until = -INF
	player.combatant.stunned_until = -INF
	player.combatant.set_health(player.combatant.max_health)


func _spawn_wave() -> void:
	_clear_enemies()
	var patterns := ["standard", "aggressive", "heavy"]
	for i in patterns.size():
		var actor: PlayerController = spawn_fighter.call(i + 1)
		director.register_enemy(actor, ENCOUNTER, patterns[i])
		enemies.append(actor)
	director.turn = 0
	director.schedule_at = Combat.now() + 1.5
	director.enabled = true


func _clear_enemies() -> void:
	for a in enemies:
		if is_instance_valid(a):
			if director:
				director.unregister_enemy(a.player_id)
			Combat.swords.remove(a.player_id)
			remove_fighter.call(a)
	enemies.clear()
	_dodged.clear()
	_struck.clear()


func _enemy_ids() -> Array:
	return enemies.filter(func(a) -> bool: return is_instance_valid(a)).map(func(a) -> int: return a.player_id)


# --- the instructor and the clock ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not active:
		return
	if _next_t >= 0.0:
		_next_t -= delta
		if _next_t < 0.0:
			start(lesson + 1)
		return
	var sid := step_id()
	if sid == "draw":
		var visual := player.get_node_or_null("AvatarVisual") as AvatarVisual
		if visual and visual.human_rig is CommanderRig and visual.human_rig.sword_drawn:
			_advance()
	elif sid in ["opening", "counter"] and not _counter_open() and not Combat.swords.attacks.has(player.player_id):
		_back("parry" if sid == "opening" else "perfect", "The opening closed. Parry again.")
	elif sid == "punish" and Combat.now() > _punish_until and not Combat.swords.attacks.has(player.player_id):
		_back("dodge", "He has recovered. Dodge again.")
	elif sid == "trial":
		_tick_trial()
	if lesson_id() != "trial" and not enemies.is_empty():
		_tick_instructor(delta)


func _counter_open() -> bool:
	var state: Dictionary = Combat.swords.actors.get(player.player_id, {})
	return float(state.get("counter_until", 0.0)) > Combat.now()


func _tick_instructor(delta: float) -> void:
	var teacher: PlayerController = enemies[0]
	if not is_instance_valid(teacher):
		return
	var id := teacher.player_id
	if Combat.swords.attacks.has(id) or teacher.combatant.is_stunned():
		teacher.input_override = {}
		return
	var to := player.global_position - teacher.global_position
	to.y = 0.0
	teacher.set_look(atan2(-to.x, -to.z))
	var attacking := step_id() in ["parry", "perfect", "dodge"]
	# He closes the distance himself rather than asking for it.
	teacher.input_override = {"move": Vector2(0, 0.45)} if to.length() > (2.0 if attacking else 3.5) else {}
	if not attacking:
		return
	_attack_t -= delta
	if _attack_t <= 0.0 and to.length() <= 2.3:
		var key := "enemy_heavy" if lesson_id() == "falling_leaf" else "enemy_standard"
		if Combat.swords.begin(id, key, player.player_id).get("ok", false):
			_attack_t = ATTACK_EVERY


func _tick_trial() -> void:
	if _restart_wave:
		_restart_wave = false
		_reset_player()
		_spawn_wave()
		changed.emit()
		return
	var standing := enemies.filter(func(a) -> bool: return is_instance_valid(a) and not a.is_defeated)
	if not standing.is_empty():
		return
	var missing := []
	for key in goals:
		if not goals[key]:
			missing.append({"combo": "a linked combination", "parry": "a parry", "dodge": "a clean dodge"}[key])
	if missing.is_empty():
		_advance()
	else:
		feedback.emit("They fall, but show me %s. Again." % ", ".join(missing), false)
		_restart_wave = true


# --- real combat outcomes ---------------------------------------------------------------------

func _on_event(data: Dictionary) -> void:
	if _next_t >= 0.0:
		return
	var actor: int = data.get("actor", -1)
	var kind := String(data.kind)
	if actor == player.player_id:
		_on_player_event(kind, data)
	elif _enemy_ids().has(actor):
		_on_enemy_event(actor, kind)


func _on_player_event(kind: String, data: Dictionary) -> void:
	var sid := step_id()
	match kind:
		"guard":
			if sid == "guard":
				_advance()
		"parry", "perfect_parry":
			goals.parry = true
			changed.emit()
			if sid == "parry":
				_advance()
			elif sid == "perfect":
				if kind == "perfect_parry":
					_advance()
				else:
					feedback.emit("A parry. Raise the guard later still for a perfect one.", false)
		"block":
			if sid in ["parry", "perfect"]:
				feedback.emit("Blocked, not parried: raise the guard just as the blow arrives.", false)
		"guard_break":
			feedback.emit("That blow cannot be guarded. Dodge it.", false)
		"dodge":
			for id in _enemy_ids():
				if Combat.swords.attacks.has(id):
					_dodged[id] = true
		"hit":
			if (data.get("targets", []) as Array).is_empty():
				if sid in ["parry", "perfect", "dodge"]:
					feedback.emit("His guard is closed. Patience: wait for him to strike.", false)
				elif sid in ["right", "left", "combo"]:
					feedback.emit("Missed. Step closer and face him.", false)
		"completed":
			if sid in ["left", "combo"] and data.get("attack") in ["dual_right", "dual_left"]:
				_check_chain.call_deferred()


## A cut ended with no follow-up begun: say how to link them.
func _check_chain() -> void:
	if active and step_id() in ["left", "combo"] and not Combat.swords.attacks.has(player.player_id):
		feedback.emit("The chain broke. Press again just before the cut ends.", false)


func _on_enemy_event(id: int, kind: String) -> void:
	match kind:
		"telegraph":
			_dodged[id] = false
			_struck[id] = false
		"recovery":
			if not _dodged.get(id, false) or _struck.get(id, false):
				if step_id() == "dodge" and not _struck.get(id, false):
					feedback.emit("Dodge as the blade falls; do not merely wait.", false)
				return
			goals.dodge = true
			changed.emit()
			if step_id() == "dodge":
				# He over-commits: a training-only opening long enough to come back in.
				_punish_until = Combat.now() + 2.2
				var teacher: PlayerController = enemies[0]
				teacher.combatant.stunned_until = Combat.now() + 2.2
				var state: Dictionary = Combat.swords.actors[player.player_id]
				state.counter_target = id
				_advance()


func _on_damage(e: Dictionary) -> void:
	var sid := step_id()
	var ids := _enemy_ids()
	if e.source == player.player_id and ids.has(e.target):
		var ability := String(e.ability)
		if ability == "dual_left":
			goals.combo = true
			changed.emit()
		if lesson_id() != "trial":
			var teacher := Combat.avatar(e.target)
			teacher.combatant.set_health(INSTRUCTOR_HEALTH)
		if _next_t >= 0.0:
			return
		if (sid == "right" and ability == "dual_right") or (sid == "left" and ability == "dual_left") \
				or (sid == "combo" and ability == "dual_combo") or (sid in ["opening", "counter"] and ability == "dual_counter") \
				or sid == "punish":
			_advance()
	elif e.target == player.player_id and ids.has(e.source):
		_struck[e.source] = true
		var health_after: int = e.health_after
		if lesson_id() != "trial":
			player.combatant.set_health(player.combatant.max_health)
			if sid in ["parry", "perfect"]:
				feedback.emit("Struck. Face him and raise the guard as the blow arrives.", false)
			elif sid == "dodge":
				feedback.emit("Struck. That blow cannot be guarded: dodge as it falls.", false)
		elif health_after <= YIELD_HEALTH:
			player.combatant.set_health(player.combatant.max_health)
			feedback.emit("In a real fight you would have fallen. The trial begins again.", false)
			_restart_wave = true
