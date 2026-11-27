extends Node
## Frame timing of the large campaign battles in a real window (run after the suite,
## with nothing else busy; the laptop throttles, so compare runs, not single numbers):
##   godot --path . res://tests/campaign_perf.tscn -- [--vsync] [--allies=N] [--only=m4|m5|square]
## For each battle: the army (N allies) stands with the commander at the ally stage,
## the encounter starts, and frames are timed for 20 s of fighting (the commander is
## kept alive). Prints avg / p95 / worst frame time, draw calls and actor counts.

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var main: Node
var c: CampaignDirector
var player: PlayerController
var only := ""
var allies := 34


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
		elif arg.begins_with("--allies="):
			allies = int(arg.substr(9))
	if not OS.get_cmdline_user_args().has("--vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	main.campaign_persist = false
	add_child(main)
	await main.ready_for_play
	c = main.campaign
	player = main.player
	(main.world.get_node("DayNightCycle") as DayNightCycle).advance_to_hour(19.0)
	# Recruit up to the requested company size.
	if c.state.roster_size() < allies:
		c.state.recruit(allies - c.state.roster_size())
	print("\n%-8s %6s %6s %6s %6s %6s %8s" % ["battle", "avg", "p95", "worst", "fps", "draws", "actors"])
	for id in [3, 4, 5]:
		var key := {3: "square", 4: "m4", 5: "m5"}[id] as String
		if only != "" and only != key:
			continue
		await _battle(id, key)
	get_tree().quit()


func _battle(id: int, key: String) -> void:
	c.encounter.reset()
	c.army.despawn_all()
	for m in c.state.missions():
		var mid := int(m["id"])
		if c.state.state_of(mid) != CampaignState.M.RESERVED:
			c.state.states[mid] = CampaignState.M.COMPLETE if mid < id else CampaignState.M.LOCKED
	c.state.states[id] = CampaignState.M.ACTIVE
	for s in c.state.roster:
		s["alive"] = true
		s["health"] = 100
	var m := c.state.mission(id)
	var stage := CampaignUtil.v3(main.world, m["commander_stage"])
	c._prepare_encounter(id)
	var face := c.encounter.area_center() - stage
	var yaw := atan2(-face.x, -face.z)
	player.teleport(stage + Vector3.UP * 0.2, yaw)
	c.army.spawn_missing(CampaignUtil.v3(main.world, m["ally_stage"]), yaw)
	c.army.set_follow(true)
	player.set_look(yaw, deg_to_rad(-12.0))
	for i in 30:
		await get_tree().process_frame
	c.start_encounter(id)
	if OS.get_cmdline_user_args().has("--profile"):
		await _profile()
	var times: Array[float] = []
	var draws := 0.0
	var prims := 0.0
	var bias := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lodbias="):
			bias = float(arg.substr(10))
	if bias > 0.0:
		for b in SoldierBrain.all:
			for gi in b.avatar.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).lod_bias = bias
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < 20_000_000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		Combat.heal_player(player.player_id, 100)
		player.input_override = {"move": Vector2.ZERO}
	times.sort()
	var avg := 0.0
	for x in times:
		avg += x
	avg /= maxf(times.size(), 1)
	var actors := Combat.actor_ids().size()
	print("%-8s %6.1f %6.1f %6.1f %6.0f %6.0f %8d   (enemies alive %d, allies %d, kills %d, %.2f M primitives)" % [key, avg, times[int(times.size() * 0.95)], times[-1],
		1000.0 / avg, draws / times.size(), actors, c.encounter.alive_count(), c.army.living().size(), c.encounter.kills, prims / times.size() / 1e6])
	Combat.set_respawn_mode(player.player_id, Combat.Respawn.AUTO)


## Per-tick cost with parts switched off in turn (run with --fixed-fps 60 --headless).
func _profile() -> void:
	var avatars: Array = []
	for b in SoldierBrain.all:
		avatars.append(b.avatar)
	for variant in ["all", "no_rigs", "hidden", "nothing", "all_again"]:
		for av in avatars:
			if not is_instance_valid(av):
				continue
			var brain := av.get_node_or_null("Brain") as SoldierBrain
			var vis := av.get_node_or_null("AvatarVisual") as AvatarVisual
			if brain:
				brain.process_mode = Node.PROCESS_MODE_DISABLED if variant in ["no_ai", "no_ai_no_rigs"] else Node.PROCESS_MODE_INHERIT
			if vis:
				vis.process_mode = Node.PROCESS_MODE_DISABLED if variant in ["no_rigs", "no_ai_no_rigs", "nothing"] else Node.PROCESS_MODE_INHERIT
			if brain and variant == "nothing":
				brain.process_mode = Node.PROCESS_MODE_DISABLED
			av.set_physics_process(not variant in ["no_bodies", "nothing"])
			if vis:
				vis.visible = variant != "hidden"
		for i in 30:
			await get_tree().physics_frame
		var t0 := Time.get_ticks_usec()
		var tp := 0.0
		var tph := 0.0
		for i in 240:
			await get_tree().process_frame
			Combat.heal_player(player.player_id, 100)
			tp += Performance.get_monitor(Performance.TIME_PROCESS)
			tph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		print("[profile] %-18s %.2f ms per frame   (idle/process %.2f ms, physics incl. scripts %.2f ms)" % [variant, (Time.get_ticks_usec() - t0) / 1000.0 / 240.0,
			tp / 240.0 * 1000.0, tph / 240.0 * 1000.0])
