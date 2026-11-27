extends Node
var arena: Node3D
var frames: Array[float] = []
var combat_us: Array[float] = []
var elapsed := 0.0
var duration := 14.0
var previous := 0
var scenario := 1
var output := ""
var captures := ""
var attacks := 0
var hits := 0
var parries := 0
var max_tokens := 0
var max_reactive := 0
var next_attack := 0.0
var captured := false
var query_before := []
var query_after := []
var baseline: Node

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenario = int(arg.substr(11))
		if arg.begins_with("--out="): output = arg.substr(6)
		if arg.begins_with("--capture="): captures = arg.substr(10)
	arena = preload("res://scenes/battle/battle_demo.tscn").instantiate()
	add_child(arena)
	arena.load_scenario(scenario)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	arena.player.input_override = {}
	Combat.swords.event.connect(observe)
	previous = Time.get_ticks_usec()
	# Exact pre-R02 authority, loaded only by this diagnostic probe.
	baseline = load("D:/WildFall/Backups/Codex_R02_CX_20261126_192157/combat_authority.gd").new()
	for actor in [arena.player]+arena.enemies:
		baseline.register(actor)
		baseline.set_team(actor.player_id,Combat.team_of(actor.player_id))
	var definition: AbilityDefinition = Combat.swords.definitions.dual_right
	for repeat in 3:
		var old_samples := []
		var new_samples := []
		for i in 300:
			var start := Time.get_ticks_usec()
			baseline._melee_targets(arena.player.player_id,definition)
			old_samples.append(float(Time.get_ticks_usec()-start))
			start = Time.get_ticks_usec()
			Combat._melee_targets(arena.player.player_id,definition)
			new_samples.append(float(Time.get_ticks_usec()-start))
		query_before.append(stats(old_samples))
		query_after.append(stats(new_samples))
	baseline.free()

func observe(data: Dictionary) -> void:
	if data.kind == "requested": attacks += 1
	if data.kind == "hit" and not data.targets.is_empty(): hits += 1
	if data.kind in ["parry","perfect_parry"]: parries += 1

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values: total += value
	return {"mean":total/values.size(),"median":sorted[values.size()/2],"p95":sorted[ceili(values.size()*0.95)-1],"p99":sorted[ceili(values.size()*0.99)-1],"max":sorted[-1]}

func _process(delta: float) -> void:
	elapsed += delta
	var now := Time.get_ticks_usec()
	var frame_ms := (now-previous)/1000.0
	previous = now
	if elapsed > 3:
		frames.append(frame_ms)
		combat_us.append(float(arena.director.processing_usec))
	max_tokens = maxi(max_tokens,1 if Combat.swords.token_actor != -1 else 0)
	max_reactive = maxi(max_reactive,arena.reactive_count())
	var player: PlayerController = arena.player
	if not player.combatant.is_alive():
		Combat.revive(player.player_id,Vector3(0,0.1,3),0.0)
		Combat.configure_sword_actor(player.player_id)
	# Face the live threat; ordinary action APIs drive the actual gameplay scene.
	var threat: PlayerController
	for enemy in arena.enemies:
		if is_instance_valid(enemy) and enemy.combatant.is_alive():
			if threat == null or enemy.global_position.distance_to(player.global_position)<threat.global_position.distance_to(player.global_position):
				threat = enemy
	if threat:
		var direction := threat.global_position-player.global_position
		player.set_look(atan2(-direction.x,-direction.z),-0.12)
		if Combat.swords.attacks.has(threat.player_id):
			var rec: Dictionary = Combat.swords.attacks[threat.player_id]
			var remaining: float = rec.active-Combat.now()
			if remaining > 0 and remaining < 0.085:
				Combat.set_guard(player.player_id,true)
		elif Combat.now() > next_attack:
			Combat.set_guard(player.player_id,false)
			Combat.request_action(player.player_id,"attack")
			next_attack = Combat.now()+0.5
	if elapsed > 7 and not captured and captures != "":
		captured = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(captures)
	if elapsed >= duration:
		set_process(false)
		var result := {"scenario":scenario,"frame_ms":stats(frames),"fps":1000.0/stats(frames).mean,"director_update_us":stats(combat_us),"query_before_us":query_before,"query_after_us":query_after,"attacks":attacks,"hit_events":hits,"parries":parries,"max_committed":max_tokens,"max_reactive":max_reactive,"logical":200 if scenario == 4 else arena.enemies.size(),"detailed_rigs":1+arena.enemies.size(),"memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"physics_objects":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"samples":frames}
		if output != "":
			var file := FileAccess.open(output,FileAccess.WRITE)
			file.store_string(JSON.stringify(result))
		print("R02 PLAY ",JSON.stringify(result.merged({"samples":[]},true)))
		arena.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit()
