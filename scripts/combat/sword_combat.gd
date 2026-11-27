extends RefCounted
## Owned by Combat. One simulation clock, monotonically increasing attack identities.
signal event(data: Dictionary)
var authority: Node
var actors := {}
var attacks := {}
var definitions := {}
var serial := 0
var token_actor := -1
var token_instance := -1
var protected_actor := -1
var guard_window := 0.22
var perfect_window := 0.10
var guard_arc := 110.0

func _init(owner: Node) -> void:
	authority = owner
	for key in ["dual_right", "dual_left", "dual_combo", "dual_heavy", "dual_sweep", "dual_counter", "dual_execute", "enemy_standard", "enemy_aggressive", "enemy_heavy", "enemy_defensive", "enemy_elite"]:
		definitions[key] = load("res://data/attacks/%s.tres" % key)

func configure(id: int, enemy := false, encounter := "arena", background := false) -> void:
	cancel(id, "configure")
	actors[id] = {"enemy": enemy, "encounter": encounter, "background": background, "reactive": false, "guard": false, "guard_at": -INF, "guard_ready": 0.0, "buffer": "", "buffer_until": 0.0, "counter_until": 0.0, "counter_target": -1, "ready": 0.0, "dodge_from": INF, "dodge_until": -INF, "cooldowns": {}}

func allocate(id: int) -> bool:
	if not actors.has(id) or actors[id].background:
		return false
	if actors[id].reactive:
		return true
	var count := 0
	for other in actors:
		if actors[other].encounter == actors[id].encounter and actors[other].reactive:
			count += 1
	if count >= 5:
		return false
	actors[id].reactive = true
	return true

func remove(id: int) -> void:
	cancel(id, "removed")
	actors.erase(id)

func reset() -> void:
	for id in attacks.keys():
		cancel(id, "reset")
	actors.clear()
	token_actor = -1
	token_instance = -1
	protected_actor = -1

func alive(id: int) -> bool:
	var av = authority.avatar(id)
	return is_instance_valid(av) and av.combatant.is_alive() and not av.is_defeated

func emit_event(id: int, kind: String, extra := {}) -> void:
	var data := {"actor": id, "kind": kind, "time": authority.now()}
	data.merge(extra)
	event.emit(data)

func set_guard(id: int, pressed: bool) -> bool:
	if not actors.has(id) or not alive(id):
		return false
	var state: Dictionary = actors[id]
	if not pressed:
		state.guard = false
		return true
	var av = authority.avatar(id)
	if av.riding or not av.controls_enabled or av.locks.blocks(ControlLock.COMBAT | ControlLock.PAUSE) or av.combatant.is_stunned() or authority.now() < state.guard_ready or attacks.has(id):
		return false
	if not state.guard:
		state.guard_at = authority.now()
		state.guard = true
		emit_event(id, "guard")
	return true

func request(id: int, action: String) -> Dictionary:
	if not actors.has(id) or not alive(id):
		return {"ok": false, "reason": "unavailable"}
	var state: Dictionary = actors[id]
	var av = authority.avatar(id)
	if av.riding or av.combatant.is_stunned() or not av.controls_enabled or av.locks.blocks(ControlLock.COMBAT | ControlLock.PAUSE):
		return {"ok": false, "reason": "control/state"}
	if action == "ability_1":
		if authority.now() < state.ready or authority.now() < float(state.cooldowns.get("dodge", 0.0)):
			return {"ok": false, "reason": "dodge recovery"}
		if attacks.has(id) and not attacks[id].definition.dodge_cancel:
			return {"ok": false, "reason": "committed"}
		cancel(id, "dodge")
		state.guard = false
		state.ready = authority.now() + 0.46
		state.cooldowns.dodge = authority.now() + 0.7
		av.start_dash(3.0, 0.30)
		state.dodge_from = authority.now() + 0.04
		state.dodge_until = authority.now() + 0.29
		authority.ability_started.emit(id, "dodge", 0.0)
		emit_event(id, "dodge")
		return {"ok": true}
	if attacks.has(id):
		var current: Dictionary = attacks[id]
		var ab: AbilityDefinition = current.definition
		var remaining: float = current.end - authority.now()
		if action == "attack" and ab.combo_next != "" and remaining <= ab.buffer_window and state.buffer == "":
			state.buffer = ab.combo_next
			state.buffer_until = authority.now() + ab.buffer_window + 0.10
			return {"ok": true, "buffered": true}
		return {"ok": false, "reason": "busy or buffer full"}
	var key := action
	if action == "attack":
		key = "enemy_standard" if state.enemy else ("dual_counter" if state.counter_until > authority.now() and alive(state.counter_target) else "dual_right")
	elif action == "special_attack":
		key = "dual_sweep"
	elif action == "execute":
		key = "dual_execute"
	return begin(id, key)

func begin(id: int, key: String, target := -1) -> Dictionary:
	if not actors.has(id) or not alive(id) or not definitions.has(key) or attacks.has(id):
		return {"ok": false, "reason": "invalid attack"}
	var state: Dictionary = actors[id]
	var av = authority.avatar(id)
	var ab: AbilityDefinition = definitions[key]
	if av.combatant.is_stunned() or av.riding or not av.controls_enabled or av.locks.blocks(ControlLock.COMBAT | ControlLock.PAUSE) or authority.now() < state.ready or authority.now() < float(state.cooldowns.get(key, 0.0)):
		return {"ok": false, "reason": "recovery/state"}
	if state.enemy and (not state.reactive or state.background or token_actor != -1 or protected_actor != -1):
		return {"ok": false, "reason": "attack token"}
	if key == "dual_execute":
		var candidates: Array = authority._melee_targets(id, ab)
		target = -1
		for candidate in candidates:
			var opponent = authority.avatar(candidate)
			if opponent.combatant.is_stunned() or opponent.combatant.health <= 35:
				target = candidate
				break
		if target == -1 or token_actor != -1:
			return {"ok": false, "reason": "no safe execution target"}
		protected_actor = id
	serial += 1
	var start: float = authority.now()
	var times: Array = []
	if ab.hit_times.is_empty():
		times.append(0.0)
	else:
		for value in ab.hit_times:
			times.append(float(value))
	attacks[id] = {"instance": serial, "definition": ab, "start": start, "active": start + ab.windup, "end": start + ab.windup + ab.active_duration + ab.recovery, "phase": "requested", "hit_index": 0, "times": times, "target": target, "hits": {}, "drawn": false, "lock": -1, "heavy_cue": false}
	if key == "dual_execute":
		attacks[id].lock = av.locks.acquire("combat_execution", ControlLock.MOVE | ControlLock.MOUNT)
	if state.enemy:
		token_actor = id
		token_instance = serial
	state.guard = false
	state.buffer = ""
	state.cooldowns[key] = start + ab.cooldown
	emit_event(id, "requested", {"instance": serial, "attack": key})
	phase(id, "startup")
	# Existing public rig API; no animation-tree mutation from gameplay.
	var visual = av.get_node_or_null("AvatarVisual")
	if visual:
		var rig = visual.human_rig
		if rig is CommanderRig:
			if not rig.sword_drawn:
				rig._put_sword(true)
			attacks[id].drawn = rig.sword_drawn
			rig.play(ab.animation_id, ab.windup + ab.active_duration + ab.recovery)
			visual.play_sound(ab.audio_event, -6.0)
	if ab.move_distance > 0.0:
		av.request_attack_motion(ab.move_distance, ab.move_duration)
	emit_event(id, "telegraph", {"attack": key, "class": ab.attack_class, "duration": ab.windup, "sword": ab.sword})
	return {"ok": true, "instance": serial}

func phase(id: int, value: String) -> void:
	if not attacks.has(id):
		return
	attacks[id].phase = value
	emit_event(id, value, {"instance": attacks[id].instance, "attack": attacks[id].definition.id})

func cancel(id: int, reason: String) -> void:
	if actors.has(id):
		actors[id].buffer = ""
		actors[id].guard = false
	if attacks.has(id):
		var rec: Dictionary = attacks[id]
		if rec.lock >= 0 and is_instance_valid(authority.avatar(id)):
			authority.avatar(id).locks.release(rec.lock)
		attacks.erase(id) # Invalidate before signals or token release permit another request.
		if token_actor == id and token_instance == rec.instance:
			token_actor = -1
			token_instance = -1
		if protected_actor == id:
			protected_actor = -1
		authority.ability_interrupted.emit(id, rec.definition.id)
		emit_event(id, "canceled", {"instance": rec.instance, "reason": reason})

func tick() -> void:
	for id in actors:
		var state: Dictionary = actors[id]
		if authority.now() >= state.dodge_from and authority.now() < state.dodge_until and alive(id):
			var actor = authority.avatar(id)
			if not actor.riding and actor.controls_enabled and not actor.combatant.is_stunned():
				actor.combatant.invulnerable_until = maxf(actor.combatant.invulnerable_until,state.dodge_until)
	for id in attacks.keys():
		if not attacks.has(id):
			continue
		if not alive(id):
			cancel(id, "death")
			continue
		var av = authority.avatar(id)
		var rec: Dictionary = attacks[id]
		var ab: AbilityDefinition = rec.definition
		if ab.id == "dual_execute" and not alive(rec.target) and rec.hit_index == 0:
			cancel(id, "execution target removed")
			continue
		var visual = av.get_node_or_null("AvatarVisual")
		if visual != null and visual.human_rig is CommanderRig and visual.human_rig.sword_drawn:
			rec.drawn = true
		var sheathed: bool = rec.drawn and visual != null and visual.human_rig is CommanderRig and not visual.human_rig.sword_drawn
		if av.riding or av.combatant.is_stunned() or not av.controls_enabled or av.locks.blocks(ControlLock.COMBAT | ControlLock.PAUSE) or sheathed:
			cancel(id, "state interruption")
			continue
		var time: float = authority.now()
		if time > rec.end + 0.5:
			cancel(id, "safety timeout")
			continue
		if time >= rec.active and rec.phase == "startup":
			phase(id, "committed")
			phase(id, "active")
		if ab.id == "enemy_elite" and not rec.heavy_cue and time >= rec.active + 0.8:
			rec.heavy_cue = true
			if visual != null:
				visual.human_rig.play("sword_heavy", 1.55)
			emit_event(id, "telegraph", {"attack": "elite heavy follow-up", "class": "unblockable", "duration": 0.65})
		# Process crossed hit markers, including frames spanning an entire short window.
		while attacks.has(id) and rec.hit_index < rec.times.size() and time >= rec.active + rec.times[rec.hit_index]:
			var index: int = rec.hit_index
			rec.hit_index += 1
			resolve_hit(id, rec.instance, index)
		if not attacks.has(id):
			continue
		if time >= rec.active + ab.active_duration and rec.phase == "active":
			phase(id, "recovery")
			if actors[id].enemy:
				open_counter(GameState.local_player_id, id, ab.recovery, "recovery")
		if time >= rec.end:
			var next: String = actors[id].buffer
			var buffered: bool = actors[id].buffer_until >= time
			phase(id, "completed")
			if rec.lock >= 0:
				av.locks.release(rec.lock)
			attacks.erase(id)
			if token_actor == id:
				token_actor = -1
				token_instance = -1
			if protected_actor == id:
				protected_actor = -1
			actors[id].buffer = ""
			if buffered and next != "":
				begin(id, next)

func resolve_hit(id: int, instance: int, index: int) -> bool:
	if not attacks.has(id) or not alive(id):
		return false
	var rec: Dictionary = attacks[id]
	var ab: AbilityDefinition = rec.definition
	if rec.instance != instance or rec.phase != "active" or index < 0 or index >= rec.times.size() or rec.hits.has(index):
		return false
	var scheduled: float = rec.active + rec.times[index]
	if authority.now() < scheduled or authority.now() > rec.end:
		return false
	if actors[id].enemy and (token_actor != id or token_instance != instance):
		return false
	rec.hits[index] = true
	var targets: Array = authority.sword_targets(id, ab)
	var landed := []
	for tid in targets:
		if not attacks.has(id):
			break
		if rec.target >= 0 and tid != rec.target:
			continue
		if authority.logical_actors.has(tid):
			if authority.apply_damage(tid, ab.damage, id, ab.id) > 0:
				landed.append(tid)
			continue
		var target = authority.avatar(tid)
		if not is_instance_valid(target):
			continue
		if target.combatant.is_invulnerable():
			authority.attack_dodged.emit(tid, id, ab.id)
			open_counter(tid, id, 0.65, "dodge")
			continue
		var classification: String = "unblockable" if ab.id == "enemy_elite" and index == 2 else ab.attack_class
		if defend(tid, id, ab, classification):
			continue
		var amount: int = authority.apply_damage(tid, ab.damage, id, ab.id)
		if amount > 0:
			landed.append(tid)
			if ab.stun_on_hit > 0 and alive(tid):
				target.combatant.stunned_until = authority.now() + ab.stun_on_hit
				cancel(tid, "stagger")
	authority.ability_resolved.emit(id, ab.id, landed)
	emit_event(id, "hit", {"instance": instance, "strike": index, "targets": landed})
	return true

func defend(target: int, source: int, ab: AbilityDefinition, classification: String) -> bool:
	if not actors.has(target) or not actors[target].guard or classification == "unblockable":
		return false
	var av = authority.avatar(target)
	var attacker = authority.avatar(source)
	var offset: Vector3 = attacker.global_position - av.global_position
	offset.y = 0
	var forward: Vector3 = av.forward()
	forward.y = 0
	if rad_to_deg(forward.angle_to(offset)) > guard_arc * 0.5:
		return false
	var held: float = authority.now() - actors[target].guard_at
	if held <= guard_window and classification != "heavy":
		var perfect := held <= perfect_window
		cancel(source, "perfect_parry" if perfect else "parry")
		attacker.combatant.stunned_until = authority.now() + (0.9 if perfect else 0.55)
		open_counter(target, source, 0.9 if perfect else 0.55, "perfect_parry" if perfect else "parry")
		emit_event(target, "perfect_parry" if perfect else "parry", {"source": source})
		return true
	if ab.guard_break or classification == "heavy":
		actors[target].guard = false
		actors[target].guard_ready = authority.now() + 0.55
		av.combatant.stunned_until = authority.now() + 0.4
		cancel(target, "guard_break")
		open_counter(source, target, 0.55, "guard_break")
		emit_event(target, "guard_break", {"source": source})
		return false
	# Holding remains an ordinary guard; its original timestamp never refreshes.
	emit_event(target, "block", {"source": source})
	return true

func open_counter(id: int, target: int, duration: float, cause: String) -> void:
	if not actors.has(id):
		return
	actors[id].counter_target = target
	actors[id].counter_until = authority.now() + duration
	emit_event(id, "counter", {"target": target, "duration": duration, "cause": cause})
