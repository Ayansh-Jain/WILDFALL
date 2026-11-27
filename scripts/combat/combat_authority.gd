extends Node

var sword_balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat_balance.json"))

const MOUNTED_SWORD_STRIKE := preload("res://data/abilities/mounted_sword_strike.tres")
## Combat authority (autoload "Combat").
##
## Owns every rule: ability validation, cooldowns, wind-ups, hit validation,
## damage, interruption, transformation, defeat and respawn. Avatars and UI
## only send requests and react to signals, so this node can later run on the
## server unchanged while clients keep the same presentation code.
##
## Time comes from an internal physics-step clock, not wall time, so results
## are deterministic in tests and independent of frame rate.

signal ability_started(actor_id: int, ability_id: String, windup: float)
signal ability_resolved(actor_id: int, ability_id: String, hit_ids: Array)
signal ability_phase(actor_id: int, ability_id: String, phase: String, duration: float)
signal ability_interrupted(actor_id: int, ability_id: String)
## Local feedback only (why a request failed).
signal ability_rejected(actor_id: int, action: String, reason: String)
## {target, source, amount, ability, position, health_after}
signal damage_dealt(event: Dictionary)
signal attack_dodged(target_id: int, source_id: int, ability_id: String)
## {defeat_id, victim, killer, victim_had_monster, killer_was_revealed, contributors}.
## Server-side event: UI must only show the public parts.
signal player_defeated(event: Dictionary)
signal player_respawned(player_id: int)
signal health_restored(player_id: int, amount: int)
## Visible to everyone: the beast form is public once revealed.
signal transform_started(actor_id: int, monster_id: String, duration: float)
signal reverted_to_human(actor_id: int)
## Private: positions revealed to the roaring player only.
signal roar_marks(actor_id: int, positions: PackedVector3Array, duration: float)
## Public, positional: a roar was heard at this position.
signal roar_heard(actor_id: int, position: Vector3, radius: float)

@export var defeat_duration := 4.0
@export var respawn_delay := 1.0
@export var respawn_invulnerability := 3.0
## Ignore hits above/below the attacker beyond this height difference.
@export var max_vertical_reach := 2.2
## Attackers within this many seconds before a defeat count as contributors.
@export var assist_window := 15.0

## (player_id, avoid_position) -> Vector3. Set by Main; falls back to staying put.
var respawn_point_provider: Callable

## Respawn modes: AUTO (the default: back after defeat_duration + respawn_delay),
## HOLD (stays down until revive(): the campaign owns the commander's death during an
## encounter) and NEVER (soldiers: the dead stay dead).
enum Respawn { AUTO, HOLD, NEVER }

var swords = preload("res://scripts/combat/sword_combat.gd").new(self)

var _clock := 0.0
var _actors := {}  ## id -> ActorData
## id -> team name. Actors on the same non-empty team never harm each other; an actor
## without a team (wanderers, hunters, tests) is hostile to everyone, as before.
var _teams := {}
var logical_actors := {}
var enemy_director: Node
var _respawn_modes := {}


class ActorData:
	var avatar: PlayerController
	var combatant: Combatant
	var cooldowns := {}           ## ability id -> ready time
	var charges := {}             ## ability id -> uses left this life
	var pending := {}             ## current wind-up / leap
	var busy_until := 0.0
	var revealed_since := -INF
	var transforming_until := -INF
	var transform_ready_at := 0.0
	var defeat_count := 0
	var defeated_at := -INF
	var respawning_at := -INF


func now() -> float:
	return _clock


func _ready() -> void:
	process_physics_priority = -10
	GameState.match_reset.connect(_on_match_reset)


# --- registration ----------------------------------------------------------------------

func register(avatar: PlayerController) -> void:
	var d := ActorData.new()
	d.avatar = avatar
	d.combatant = avatar.combatant
	d.combatant.player_id = avatar.player_id
	_actors[avatar.player_id] = d
	_apply_form(avatar.player_id)
	d.combatant.set_health(d.combatant.max_health)


func unregister(id: int) -> void:
	swords.remove(id)
	if is_instance_valid(enemy_director):
		enemy_director.members.erase(id)
	_actors.erase(id)
	_teams.erase(id)
	_respawn_modes.erase(id)


func avatar(id: int) -> PlayerController:
	var d: ActorData = _actors.get(id)
	return d.avatar if d else null


func actor_ids() -> Array:
	return _actors.keys()


# --- teams and respawn --------------------------------------------------------------------

func set_team(id: int, team: String) -> void:
	if team == "":
		_teams.erase(id)
	else:
		_teams[id] = team


func team_of(id: int) -> String:
	return _teams.get(id, "")


## Whether `a` may harm `b`: different teams, or either has no team.
func are_hostile(a: int, b: int) -> bool:
	if a == b:
		return false
	var ta: String = _teams.get(a, "")
	return ta == "" or ta != _teams.get(b, "")


func set_respawn_mode(id: int, mode: int) -> void:
	if mode == Respawn.AUTO:
		_respawn_modes.erase(id)
	else:
		_respawn_modes[id] = mode


func respawn_mode(id: int) -> int:
	return _respawn_modes.get(id, Respawn.AUTO)


## Brings a defeated (or living) actor back at once at `pos`, with full health and
## no cooldowns: the campaign's retry / quit, never ordinary play.
func revive(id: int, pos: Vector3, yaw := NAN) -> bool:
	swords.cancel(id, "revive")
	if swords.actors.has(id):
		swords.actors[id].ready = 0.0
		swords.actors[id].cooldowns.clear()
	var d: ActorData = _actors.get(id)
	if d == null:
		return false
	var state := GameState.get_state(id)
	if state == PlayerState.State.DEFEATED:
		GameState.transition(id, PlayerState.State.RESPAWNING, "revive")
		state = PlayerState.State.RESPAWNING
	d.avatar.teleport(pos + Vector3.UP * 0.1, yaw)
	if state == PlayerState.State.RESPAWNING:
		GameState.transition(id, PlayerState.State.MONSTER_HIDDEN if GameState.has_monster(id) else PlayerState.State.HUMAN, "revived")
	d.pending = {}
	d.busy_until = 0.0
	d.defeated_at = -INF
	d.respawning_at = -INF
	_apply_form(id)
	d.combatant.reset_status()
	d.combatant.set_health(d.combatant.max_health)
	d.charges.clear()
	d.cooldowns.clear()
	if d.avatar.is_defeated:
		d.avatar.on_respawned()
	player_respawned.emit(id)
	return true


# --- queries (UI, bots, tests) -----------------------------------------------------------

func cooldown_remaining(id: int, ability_id: String) -> float:
	var d: ActorData = _actors.get(id)
	if d == null:
		return 0.0
	return maxf(0.0, d.cooldowns.get(ability_id, 0.0) - _clock)


func charges_left(id: int, ability: AbilityDefinition) -> int:
	var d: ActorData = _actors.get(id)
	if d == null or ability.charges < 0:
		return -1
	return d.charges.get(ability.id, ability.charges)


func is_busy(id: int) -> bool:
	if swords.attacks.has(id):
		return true
	var d: ActorData = _actors.get(id)
	return d != null and (not d.pending.is_empty() or _clock < d.busy_until)


func pending_ability(id: int) -> String:
	if swords.attacks.has(id):
		return swords.attacks[id].definition.id
	var d: ActorData = _actors.get(id)
	if d == null or d.pending.is_empty():
		return ""
	return d.pending["ability"].id


## Which ability an input action triggers for this player right now ("" if none).
func ability_id_for_action(id: int, action: String) -> String:
	var ab := GameState.current_form(id).ability_for_action(action)
	return ab.id if ab else ""


func is_transforming(id: int) -> bool:
	var d: ActorData = _actors.get(id)
	return d != null and _clock < d.transforming_until


## Private status for the owning player's HUD only.
## phase: none | hidden_ready | hidden_cooldown | transforming | revealed_locked | revealed_free
func transform_status(id: int) -> Dictionary:
	var d: ActorData = _actors.get(id)
	var state := GameState.get_state(id)
	if d == null or not GameState.has_monster(id):
		return {"phase": "none", "time_left": 0.0}
	if state == PlayerState.State.MONSTER_REVEALED:
		if _clock < d.transforming_until:
			return {"phase": "transforming", "time_left": d.transforming_until - _clock}
		var def := GameState.monster_definition(GameState.record(id).monster_id)
		var free_at := maxf(d.revealed_since + def.min_reveal_duration, d.combatant.last_combat_time + def.combat_lockout)
		if _clock < free_at:
			return {"phase": "revealed_locked", "time_left": free_at - _clock}
		return {"phase": "revealed_free", "time_left": 0.0}
	if state == PlayerState.State.MONSTER_HIDDEN:
		if _clock < d.transform_ready_at:
			return {"phase": "hidden_cooldown", "time_left": d.transform_ready_at - _clock}
		return {"phase": "hidden_ready", "time_left": 0.0}
	return {"phase": "none", "time_left": 0.0}


# --- requests ----------------------------------------------------------------------------

func request_action(id: int, action: String) -> Dictionary:
	if swords.actors.has(id) and GameState.current_form(id).id == "human":
		return swords.request(id, action)
	var form := GameState.current_form(id)
	var ability := form.ability_for_action(action)
	if ability == null:
		return _reject(id, action, "no ability")
	return request_ability(id, ability.id)


func request_ability(id: int, ability_id: String) -> Dictionary:
	var ability := GameState.current_form(id).ability(ability_id)
	if ability == null:
		return _reject(id, ability_id, "not available in this form")
	return _request_ability(id, ability)


## One mounted sword cut uses the existing melee resolver, with its own wider side arc.
func request_mounted_attack(id: int) -> Dictionary:
	var d: ActorData = _actors.get(id)
	if d == null:
		return {"ok": false, "reason": "unknown player"}
	if not d.avatar.riding:
		return _reject(id, "mounted_sword_strike", "not mounted")
	if GameState.current_form(id).id != "human":
		return _reject(id, "mounted_sword_strike", "not available in this form")
	return _request_ability(id, MOUNTED_SWORD_STRIKE)


func _request_ability(id: int, ability: AbilityDefinition) -> Dictionary:
	var d: ActorData = _actors.get(id)
	if d == null:
		return {"ok": false, "reason": "unknown player"}
	if d.avatar.is_local and not d.avatar.controls_enabled:
		return _reject(id, ability.id, "controls locked")
	if not PlayerState.is_alive_state(GameState.get_state(id)) or not d.combatant.is_alive():
		return _reject(id, ability.id, "defeated")
	if d.combatant.is_stunned():
		return _reject(id, ability.id, "stunned")
	if _clock < d.transforming_until:
		return _reject(id, ability.id, "transforming")
	if is_busy(id):
		return _reject(id, ability.id, "busy")
	if _clock < d.cooldowns.get(ability.id, 0.0):
		return _reject(id, ability.id, "cooldown")
	if ability.charges >= 0 and d.charges.get(ability.id, ability.charges) <= 0:
		return _reject(id, ability.id, "no charges")
	if ability.stamina_cost > 0.0 and not d.avatar.spend_stamina(ability.stamina_cost):
		return _reject(id, ability.id, "stamina")

	d.cooldowns[ability.id] = _clock + ability.cooldown
	if ability.charges >= 0:
		d.charges[ability.id] = d.charges.get(ability.id, ability.charges) - 1
	match ability.kind:
		AbilityDefinition.Kind.DASH:
			d.avatar.start_dash(ability.move_distance, ability.move_duration)
			d.combatant.invulnerable_until = maxf(d.combatant.invulnerable_until, _clock + ability.invulnerable_time)
			d.busy_until = _clock + ability.recovery
			ability_started.emit(id, ability.id, 0.0)
			ability_resolved.emit(id, ability.id, [])
		AbilityDefinition.Kind.WARD:
			ability_started.emit(id, ability.id, 0.0)
			d.busy_until = _clock + ability.recovery
			_resolve_ward(id, ability)
		AbilityDefinition.Kind.FLAME:
			d.pending = {"ability": ability, "resolve_at": _clock + ability.windup, "phase": "windup", "damage_taken": 0}
			ability_started.emit(id, ability.id, ability.windup)
		_:
			d.pending = {"ability": ability, "resolve_at": _clock + ability.windup, "phase": "windup", "damage_taken": 0}
			ability_started.emit(id, ability.id, ability.windup)
	return {"ok": true, "reason": ""}


func request_transform(id: int) -> Dictionary:
	var d: ActorData = _actors.get(id)
	if d == null:
		return {"ok": false, "reason": "unknown player"}
	var rec := GameState.record(id)
	if rec == null or not rec.has_monster():
		return _reject(id, "transform", "no monster powers")
	if rec.state != PlayerState.State.MONSTER_HIDDEN:
		return _reject(id, "transform", "not hidden")
	if d.combatant.is_stunned() or is_busy(id):
		return _reject(id, "transform", "busy")
	if _clock < d.transform_ready_at:
		return _reject(id, "transform", "cooldown")
	var def := GameState.monster_definition(rec.monster_id)
	if not d.avatar.can_fit(def):
		return _reject(id, "transform", "no room")
	GameState.transition(id, PlayerState.State.MONSTER_REVEALED, "transform")
	d.revealed_since = _clock
	d.transforming_until = _clock + def.transform_time
	_apply_form(id)
	transform_started.emit(id, rec.monster_id, def.transform_time)
	return {"ok": true, "reason": ""}


func request_revert(id: int) -> Dictionary:
	var d: ActorData = _actors.get(id)
	if d == null:
		return {"ok": false, "reason": "unknown player"}
	var rec := GameState.record(id)
	if rec == null or rec.state != PlayerState.State.MONSTER_REVEALED:
		return _reject(id, "transform", "not revealed")
	var st := transform_status(id)
	if st["phase"] != "revealed_free":
		return _reject(id, "transform", "locked")
	if is_busy(id):
		return _reject(id, "transform", "busy")
	if not d.avatar.can_fit(GameState.HUMAN_FORM):
		return _reject(id, "transform", "no room")
	_revert(id, true)
	return {"ok": true, "reason": ""}


func _reject(id: int, action: String, reason: String) -> Dictionary:
	ability_rejected.emit(id, action, reason)
	return {"ok": false, "reason": reason}


# --- simulation ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	swords.tick()
	for id in _actors.keys():
		var d: ActorData = _actors.get(id)
		if d == null or not is_instance_valid(d.avatar):
			_actors.erase(id)
			continue
		_tick_pending(id, d)
		_tick_lifecycle(id, d)


func _tick_pending(id: int, d: ActorData) -> void:
	if d.pending.is_empty():
		return
	var ab: AbilityDefinition = d.pending["ability"]
	if d.pending["phase"] == "windup":
		if ab.interruptible and (d.combatant.is_stunned() or d.pending["damage_taken"] >= ab.interrupt_damage):
			d.pending = {}
			d.combatant.stunned_until = maxf(d.combatant.stunned_until, _clock + ab.stagger_on_interrupt)
			d.busy_until = _clock + ab.stagger_on_interrupt
			ability_interrupted.emit(id, ab.id)
			return
		if _clock < d.pending["resolve_at"]:
			return
		match ab.kind:
			AbilityDefinition.Kind.MELEE:
				d.pending = {}
				d.busy_until = _clock + ab.recovery
				var hits := _strike(id, ab, _melee_targets(id, ab))
				ability_resolved.emit(id, ab.id, hits)
			AbilityDefinition.Kind.ROAR:
				d.pending = {}
				d.busy_until = _clock + ab.recovery
				_resolve_roar(id, ab)
			AbilityDefinition.Kind.LEAP:
				d.avatar.start_leap(ab.move_distance, ab.leap_height)
				d.pending["phase"] = "air"
				d.pending["air_since"] = _clock
			AbilityDefinition.Kind.FLAME:
				d.pending["phase"] = "flame"
				d.pending["flame_until"] = _clock + ab.flame_duration
				d.pending["next_tick"] = _clock
				d.pending["hit_ids"] = []
				ability_phase.emit(id, ab.id, "active", ab.flame_duration)
	if not d.pending.is_empty() and d.pending["phase"] == "flame":
		if _clock >= float(d.pending["flame_until"]):
			var hits: Array = d.pending["hit_ids"]
			d.pending = {}
			d.busy_until = _clock + ab.recovery
			ability_phase.emit(id, ab.id, "recovery", ab.recovery)
			ability_resolved.emit(id, ab.id, hits)
			return
		if _clock >= float(d.pending["next_tick"]):
			for tid in _flame_targets(id, ab):
				var td: ActorData = _actors.get(tid)
				if td == null or td.combatant.is_invulnerable():
					if td != null and td.combatant.is_invulnerable():
						attack_dodged.emit(tid, id, ab.id)
					continue
				var hits: Array = d.pending["hit_ids"]
				if not hits.has(tid):
					hits.append(tid)
				apply_damage(tid, ab.damage, id, ab.id)
			d.pending["next_tick"] = _clock + maxf(ab.damage_interval, 0.1)
	elif not d.pending.is_empty() and d.pending["phase"] == "air":
		var air: float = _clock - d.pending["air_since"]
		if (air > 0.15 and d.avatar.is_on_floor()) or air > 1.6:
			d.pending = {}
			d.busy_until = _clock + ab.recovery
			var hits := _strike(id, ab, _radius_targets(id, ab.radius, false))
			ability_resolved.emit(id, ab.id, hits)


func _flame_targets(id: int, ab: AbilityDefinition) -> Array:
	# The same forward cone and world-only LOS query as melee, sampled at a
	# controlled cadence while the flame is active.
	return _melee_targets(id, ab)


func _tick_lifecycle(id: int, d: ActorData) -> void:
	var state := GameState.get_state(id)
	if state == PlayerState.State.DEFEATED and _respawn_modes.has(id):
		return  # HOLD / NEVER: someone else decides (revive) or nobody does.
	if state == PlayerState.State.DEFEATED and _clock >= d.defeated_at + defeat_duration:
		GameState.transition(id, PlayerState.State.RESPAWNING, "respawn")
		d.respawning_at = _clock
		var killer_pos := d.avatar.global_position
		var pos: Vector3 = respawn_point_provider.call(id, killer_pos) if respawn_point_provider.is_valid() else d.avatar.global_position
		d.avatar.teleport(pos + Vector3.UP * 0.1)
	elif state == PlayerState.State.RESPAWNING and _clock >= d.respawning_at + respawn_delay:
		var has := GameState.has_monster(id)
		GameState.transition(id, PlayerState.State.MONSTER_HIDDEN if has else PlayerState.State.HUMAN, "respawned")
		_apply_form(id)
		d.combatant.reset_status()
		d.combatant.set_health(d.combatant.max_health)
		d.combatant.invulnerable_until = _clock + respawn_invulnerability
		d.charges.clear()
		d.cooldowns.clear()
		if has:
			d.transform_ready_at = _clock + GameState.monster_definition(GameState.record(id).monster_id).transform_cooldown
		d.avatar.on_respawned()
		player_respawned.emit(id)


# --- hit resolution ---------------------------------------------------------------------------

func _chest(av: PlayerController) -> Vector3:
	return av.global_position + Vector3.UP * av.current_height() * 0.55


func _alive_targets(attacker_id: int) -> Array:
	var out := []
	for id in _actors:
		if id == attacker_id or not are_hostile(attacker_id, id):
			continue
		if not PlayerState.is_alive_state(GameState.get_state(id)):
			continue
		var d: ActorData = _actors[id]
		if d.combatant.is_alive():
			out.append(id)
	return out


## Targets inside the attacker's cone, in range, at similar height and with a
## clear line of sight (walls block attacks). Sorted nearest first.
func _melee_targets(id: int, ab: AbilityDefinition) -> Array:
	var a: PlayerController = _actors[id].avatar
	var origin := _chest(a)
	var fwd := -a.global_transform.basis.z
	if a.riding:
		var rider := a.get_node_or_null("Rider") as Rider
		if rider and rider.horse:
			fwd = rider.horse.forward()
	var fwd2 := Vector2(fwd.x, fwd.z).normalized()
	var space := a.get_world_3d().direct_space_state
	var found := []
	for tid in _alive_targets(id):
		var b: PlayerController = _actors[tid].avatar
		var tc := _chest(b)
		var flat := Vector2(tc.x - origin.x, tc.z - origin.z)
		var dist := flat.length() - b.capsule.radius
		if dist > ab.hit_range or absf(tc.y - origin.y) > max_vertical_reach:
			continue
		if flat.length() > 0.3 and absf(rad_to_deg(fwd2.angle_to(flat.normalized()))) > ab.arc_degrees * 0.5:
			continue
		if not LineOfSight.is_clear(space, origin, tc, [a.get_rid(), b.get_rid()], Layers.WORLD):
			continue
		found.append([dist, tid])
	found.sort_custom(func(x, y) -> bool: return x[0] < y[0])
	var out := []
	for f in found.slice(0, ab.max_targets):
		out.append(f[1])
	return out


func _radius_targets(id: int, radius: float, revealed_only: bool, need_los := true) -> Array:
	var a: PlayerController = _actors[id].avatar
	var origin := _chest(a)
	var space := a.get_world_3d().direct_space_state
	var out := []
	for tid in _alive_targets(id):
		if revealed_only and not GameState.is_revealed(tid):
			continue
		var b: PlayerController = _actors[tid].avatar
		var tc := _chest(b)
		if origin.distance_to(tc) - b.capsule.radius > radius:
			continue
		if need_los and not LineOfSight.is_clear(space, origin, tc, [a.get_rid(), b.get_rid()], Layers.WORLD):
			continue
		out.append(tid)
	return out


## Applies an ability's hit effects; dodging (invulnerable) targets are missed.
func _strike(id: int, ab: AbilityDefinition, targets: Array) -> Array:
	var hits := []
	var a: PlayerController = _actors[id].avatar
	for tid in targets:
		var td: ActorData = _actors[tid]
		if td.combatant.is_invulnerable():
			attack_dodged.emit(tid, id, ab.id)
			continue
		if swords.defend(tid, id, ab, ab.attack_class):
			continue
		hits.append(tid)
		if ab.stun_on_hit > 0.0:
			td.combatant.stunned_until = maxf(td.combatant.stunned_until, _clock + ab.stun_on_hit)
		if ab.knockback > 0.0:
			var dir := td.avatar.global_position - a.global_position
			dir.y = 0.0
			td.avatar.apply_knockback(dir.normalized() * ab.knockback * 3.0)
		var damage := ab.damage
		if ab.id in ["sword_strike", "sword_finisher", "mounted_sword_strike"]:
			var key := "commander_finisher" if ab.id == "sword_finisher" else "commander_basic"
			if a.is_bot and a.body_style.begins_with("soldier:"):
				key = "enemy_basic" if a.body_style.begins_with("soldier:enemy") else "allied_basic"
			damage = int(sword_balance.get(key, damage))
		apply_damage(tid, damage, id, ab.id)
	return hits


func _resolve_ward(id: int, ab: AbilityDefinition) -> void:
	var targets := _radius_targets(id, ab.radius, ab.affects_revealed_only)
	var hits := []
	for tid in targets:
		var td: ActorData = _actors[tid]
		td.combatant.stunned_until = maxf(td.combatant.stunned_until, _clock + ab.effect_duration)
		var dir: Vector3 = td.avatar.global_position - _actors[id].avatar.global_position
		dir.y = 0.0
		td.avatar.apply_knockback(dir.normalized() * ab.knockback * 3.0)
		hits.append(tid)
		if ab.damage > 0:
			apply_damage(tid, ab.damage, id, ab.id)
	ability_resolved.emit(id, ab.id, hits)


func _resolve_roar(id: int, ab: AbilityDefinition) -> void:
	var a: PlayerController = _actors[id].avatar
	var pressured := _radius_targets(id, ab.radius, false, false)
	for tid in pressured:
		var c: Combatant = _actors[tid].combatant
		c.slowed_until = maxf(c.slowed_until, _clock + ab.effect_duration)
		c.slow_factor = ab.slow_factor
		c.shaken_until = maxf(c.shaken_until, _clock + ab.effect_duration)
	var marks := PackedVector3Array()
	for tid in _radius_targets(id, ab.reveal_radius, false, false):
		marks.append(_actors[tid].avatar.global_position)
	roar_marks.emit(id, marks, ab.mark_duration)
	roar_heard.emit(id, a.global_position, ab.radius * 4.0)
	ability_resolved.emit(id, ab.id, pressured)


## The only way health goes down. Returns damage actually applied.
func apply_damage(target_id: int, amount: int, source_id: int, ability_id: String) -> int:
	if logical_actors.has(target_id):
		return _damage_logical(target_id, amount, source_id, ability_id)
	var td: ActorData = _actors.get(target_id)
	if td == null or amount <= 0 or not td.combatant.is_alive():
		return 0
	if not PlayerState.is_alive_state(GameState.get_state(target_id)) or td.combatant.is_invulnerable():
		return 0
	if td.avatar.get_meta("duel_locked",false):
		return 0
	if td.avatar.has_meta("duel_opponent") and source_id != int(td.avatar.get_meta("duel_opponent")):
		return 0
	var source: ActorData = _actors.get(source_id)
	if source and source.avatar.has_meta("duel_opponent") and target_id != int(source.avatar.get_meta("duel_opponent")):
		return 0
	if source_id >= 0 and not are_hostile(source_id, target_id):
		return 0
	if swords.attacks.has(target_id) and swords.attacks[target_id].definition.interruptible:
		swords.cancel(target_id, "damage interruption")
	var c := td.combatant
	c.set_health(c.health - amount)
	c.last_combat_time = _clock
	if source_id >= 0 and source_id != target_id:
		c.recent_attackers[source_id] = _clock
		var sd: ActorData = _actors.get(source_id)
		if sd:
			sd.combatant.last_combat_time = _clock
	if not td.pending.is_empty():
		td.pending["damage_taken"] = int(td.pending["damage_taken"]) + amount
	damage_dealt.emit({"target": target_id, "source": source_id, "amount": amount, "ability": ability_id,
		"position": _chest(td.avatar), "health_after": c.health})
	if c.health <= 0:
		_defeat(target_id, source_id)
	return amount


func heal_player(target_id: int, amount: int) -> int:
	var d: ActorData = _actors.get(target_id)
	if d == null or amount <= 0 or not d.combatant.is_alive():
		return 0
	if not PlayerState.is_alive_state(GameState.get_state(target_id)):
		return 0
	var before := d.combatant.health
	d.combatant.set_health(mini(d.combatant.max_health, before + amount))
	var restored := d.combatant.health - before
	if restored > 0:
		health_restored.emit(target_id, restored)
	return restored


func _defeat(victim_id: int, killer_id: int) -> void:
	swords.cancel(victim_id, "death")
	var d: ActorData = _actors[victim_id]
	d.defeat_count += 1
	d.pending = {}
	var contributors := []
	for aid in d.combatant.recent_attackers:
		if _clock - d.combatant.recent_attackers[aid] <= assist_window:
			contributors.append(aid)
	var event := {
		"defeat_id": "%d:%d" % [victim_id, d.defeat_count],
		"victim": victim_id,
		"killer": killer_id,
		"victim_had_monster": GameState.has_monster(victim_id),
		"victim_was_revealed": GameState.is_revealed(victim_id),
		"killer_was_revealed": GameState.is_revealed(killer_id),
		"contributors": contributors,
	}
	if GameState.is_revealed(victim_id):
		_revert(victim_id, false)
	GameState.transition(victim_id, PlayerState.State.DEFEATED, "defeated")
	d.defeated_at = _clock
	d.avatar.on_defeated()
	player_defeated.emit(event)


func _revert(id: int, start_cooldown: bool) -> void:
	var d: ActorData = _actors[id]
	if GameState.get_state(id) == PlayerState.State.MONSTER_REVEALED:
		GameState.transition(id, PlayerState.State.MONSTER_HIDDEN, "revert")
	d.transforming_until = -INF
	if start_cooldown:
		d.transform_ready_at = _clock + GameState.monster_definition(GameState.record(id).monster_id).transform_cooldown
	_apply_form(id)
	reverted_to_human.emit(id)


func _apply_form(id: int) -> void:
	var d: ActorData = _actors.get(id)
	if d == null:
		return
	var form := GameState.current_form(id)
	d.combatant.set_max_health(form.max_health, true)
	d.avatar.apply_form(form)


func _on_match_reset() -> void:
	swords.reset()
	if is_instance_valid(enemy_director):
		enemy_director.queue_free()
		enemy_director = null
	for id in _actors:
		var d: ActorData = _actors[id]
		d.pending = {}
		d.transforming_until = -INF
		d.transform_ready_at = 0.0
		d.cooldowns.clear()
		d.charges.clear()
		d.defeated_at = -INF
		d.combatant.reset_status()
		_apply_form(id)
		d.combatant.set_health(d.combatant.max_health)
		if d.avatar.is_defeated:
			d.avatar.on_respawned()
		reverted_to_human.emit(id)


## Additive R02 integration API. Arena enables actors explicitly; legacy forms remain intact.
func configure_sword_actor(id: int, enemy := false, encounter := "arena", background := false) -> void:
	cancel_attack(id, "runtime handoff")
	swords.configure(id, enemy, encounter, background)

func set_guard(id: int, pressed: bool) -> bool:
	return swords.set_guard(id, pressed)

func cancel_attack(id: int, reason := "external") -> void:
	swords.cancel(id, reason)
	var d: ActorData = _actors.get(id)
	if d != null and not d.pending.is_empty():
		var ab: AbilityDefinition = d.pending.ability
		d.pending = {}
		ability_interrupted.emit(id, ab.id)

func combat_state(id: int) -> Dictionary:
	if not swords.actors.has(id):
		return {}
	var state: Dictionary = swords.actors[id].duplicate(true)
	state["attack"] = swords.attacks.get(id, {}).duplicate(true)
	return state


## Lightweight battle identities: no CharacterBody or skeleton required.
func register_logical(id: int, record: Dictionary, team: String) -> void:
	logical_actors[id] = record
	set_team(id, team)

func unregister_logical(id: int) -> void:
	logical_actors.erase(id)
	_teams.erase(id)

func _damage_logical(id: int, amount: int, source: int, ability: String) -> int:
	var rec: Dictionary = logical_actors[id]
	if amount <= 0 or rec.health <= 0 or not are_hostile(source, id) or not swords.alive(source):
		return 0
	rec.health = maxi(0, int(rec.health) - amount)
	damage_dealt.emit({"target": id, "source": source, "amount": amount, "ability": ability, "position": rec.position + Vector3.UP, "health_after": rec.health})
	return amount

func sword_targets(id: int, ab: AbilityDefinition) -> Array:
	var targets := _melee_targets(id, ab)
	var actor := avatar(id)
	var origin := _chest(actor)
	var forward := Vector2(actor.forward().x, actor.forward().z).normalized()
	for tid in logical_actors:
		var rec: Dictionary = logical_actors[tid]
		if rec.health <= 0 or not are_hostile(id, tid):
			continue
		var chest: Vector3 = rec.position + Vector3.UP
		var flat := Vector2(chest.x-origin.x,chest.z-origin.z)
		if flat.length()-0.3 > ab.hit_range or absf(chest.y-origin.y)>max_vertical_reach:
			continue
		if flat.length()>0.3 and absf(rad_to_deg(forward.angle_to(flat.normalized())))>ab.arc_degrees*0.5:
			continue
		if LineOfSight.is_clear(actor.get_world_3d().direct_space_state,origin,chest,[actor.get_rid()],Layers.WORLD):
			targets.append(tid)
	targets.sort_custom(func(a, b) -> bool: return sword_target_position(a).distance_squared_to(origin)<sword_target_position(b).distance_squared_to(origin))
	return targets.slice(0,ab.max_targets)

func sword_target_position(id: int) -> Vector3:
	return logical_actors[id].position if logical_actors.has(id) else avatar(id).global_position


## Existing campaign brains hand Commander-facing engagement to one bounded scheduler.
func direct_enemy(actor: PlayerController, encounter_id: String, pattern := "standard") -> void:
	if not is_instance_valid(enemy_director):
		enemy_director = preload("res://scripts/combat/combat_director.gd").new()
		add_child(enemy_director)
	enemy_director.commander = avatar(GameState.local_player_id)
	if enemy_director.commander != null and not swords.actors.has(GameState.local_player_id):
		configure_sword_actor(GameState.local_player_id)
	if not enemy_director.members.has(actor.player_id):
		enemy_director.register_enemy(actor, encounter_id, pattern)
