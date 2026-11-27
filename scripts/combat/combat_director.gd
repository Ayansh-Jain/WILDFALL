extends Node
## Scene-scoped, bounded scheduler. Combat owns the single global commitment token.
var commander: PlayerController
var members := {}
var schedule_at := 0.0
var turn := 0
var selection_deadline := 0.0
var enabled := true
var processing_usec := 0

func register_enemy(actor: PlayerController, encounter := "arena", pattern := "standard", background := false) -> void:
	Combat.configure_sword_actor(actor.player_id, true, encounter, background)
	members[actor.player_id] = {"actor": actor, "encounter": encounter, "pattern": pattern, "role": "background" if background else "holding", "slot": actor.global_position, "home": actor.global_position}
	actor.input_override = {}
	var brain = actor.get_node_or_null("Brain")
	if brain:
		brain.process_mode = Node.PROCESS_MODE_DISABLED
	Combat.swords.allocate(actor.player_id)

func unregister_enemy(id: int) -> void:
	if members.has(id):
		var actor = members[id].actor
		if is_instance_valid(actor):
			actor.input_override = {}
			var brain = actor.get_node_or_null("Brain")
			if brain:
				brain.process_mode = Node.PROCESS_MODE_INHERIT
	Combat.swords.remove(id)
	members.erase(id)

func end_encounter(key: String) -> void:
	for id in members.keys():
		if members[id].encounter == key:
			var actor = members[id].actor
			if is_instance_valid(actor):
				actor.input_override = {}
			unregister_enemy(id)

func retreat(id: int, point: Vector3) -> void:
	if members.has(id):
		Combat.cancel_attack(id, "retreat")
		Combat.swords.actors[id].reactive = false
		members[id].role = "retreating"
		members[id].slot = point

func _exit_tree() -> void:
	for id in members.keys():
		Combat.cancel_attack(id, "scene unload")
		unregister_enemy(id)

func _physics_process(_delta: float) -> void:
	if not enabled or not is_instance_valid(commander) or Combat.now() < schedule_at:
		return
	var started := Time.get_ticks_usec()
	schedule_at = Combat.now() + 0.2
	var alive_ids := []
	for id in members.keys():
		if not Combat.swords.alive(id):
			unregister_enemy(id)
			continue
		var actor = members[id].actor
		var brain = actor.get_node_or_null("Brain")
		if brain and (brain.paused or brain.mode != SoldierBrain.Mode.COMBAT or brain.target_id != commander.player_id):
			unregister_enemy(id)
			continue
		if not Combat.swords.actors.has(id):
			unregister_enemy(id)
			continue
		if not Combat.swords.actors[id].background:
			alive_ids.append(id)
	if not Combat.swords.alive(commander.player_id):
		for id in alive_ids:
			Combat.cancel_attack(id, "commander defeated")
			members[id].actor.input_override = {}
		return
	var candidates := []
	for id in alive_ids:
		if Combat.swords.allocate(id):
			candidates.append(id)
	if Combat.swords.token_actor == -1 and Combat.now() >= selection_deadline:
		turn += 1
		selection_deadline = Combat.now()+2.5
	for i in alive_ids.size():
		var id: int = alive_ids[i]
		var rec: Dictionary = members[id]
		var actor: PlayerController = rec.actor
		Combat.swords.allocate(id)
		var reactive: bool = Combat.swords.actors[id].reactive
		if rec.role != "retreating":
			var angle := float(i) * TAU / maxf(alive_ids.size(), 1.0) + 0.3
			var radius := 3.7 if reactive else 6.2
			var candidate := commander.global_position + Vector3(sin(angle), 0, cos(angle)) * radius
			var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP, candidate + Vector3.UP, Layers.WORLD)
			if actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				rec.slot = candidate
			rec.role = ["circling", "threatening", "holding", "wildcard", "holding"][i % 5] if reactive else "holding"
		if Combat.swords.attacks.has(id):
			actor.input_override = {}
			rec.role = "attacker"
			continue
		var destination: Vector3 = rec.slot
		var selected: bool = reactive and not candidates.is_empty() and id == candidates[turn % candidates.size()] and Combat.swords.token_actor == -1
		if selected:
			destination = commander.global_position
		var direction := destination - actor.global_position
		direction.y = 0
		if direction.length() > (1.9 if selected else 0.4):
			var local := actor.global_basis.inverse() * direction.normalized()
			actor.input_override = {"move": Vector2(local.x, -local.z) * 0.5}
		else:
			actor.input_override = {}
		if not actor.combatant.is_stunned():
			var facing := commander.global_position - actor.global_position
			actor.set_look(atan2(-facing.x, -facing.z))
		if selected and direction.length() < 2.3:
			var result: Dictionary = Combat.swords.begin(id, "enemy_" + rec.pattern, commander.player_id)
			if result.get("ok", false):
				turn += 1
				selection_deadline = Combat.now()+2.5
		elif rec.pattern == "defensive" and not selected:
			Combat.set_guard(id, true)
	processing_usec = Time.get_ticks_usec() - started
