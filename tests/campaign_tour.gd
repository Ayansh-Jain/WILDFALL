extends Node
## Visual check of the campaign and the movement / camera work, in the real game:
## the King on his chair, a briefing, the army at the training ground, following and
## mounting, spies on their routes, the square and gate-field battles, the failed
## screen, the commander's walk / run / dual-sword sprint (side views from a photo
## camera), and the follow camera inside the cave and the crypt. Saves one PNG per shot.
##   godot --path . res://tests/campaign_tour.tscn -- --out=C:/some/dir [--only=a,b]

const MAIN_SCENE := preload("res://scenes/main/main.tscn")

var out_dir := "user://campaign_tour"
var only := ""
var main: Node
var world: World
var player: PlayerController
var campaign: CampaignDirector
var photo: Camera3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	main.campaign_persist = false
	add_child(main)
	await main.ready_for_play
	world = main.world
	player = main.player
	campaign = main.campaign
	campaign.speed = 0.2
	main.story.speed = 0.15
	photo = Camera3D.new()
	photo.fov = 45.0
	add_child(photo)
	var cycle := world.get_node("DayNightCycle") as DayNightCycle
	cycle.start_automatically = false

	if _want("king") or _want("brief"):
		cycle.advance_to_hour(18.5)
		await _at_anchor("king_audience", 0.0)
		await _settle(60)
		await _shot("king_hall", "commander before the King (evening)")
		await _photo_at(campaign.king.global_position + Vector3(-2.2, 1.6, 3.2), campaign.king.global_position + Vector3(0, 1.0, 0))
		await _shot("king_close", "the King on the old lord's chair")
		photo.current = false
		if _want("brief"):
			campaign.brief(2)
			await _frames(40)
			await _shot("briefing", "the King's briefing for Mission 2")
			while main.story.in_dialogue:
				await _frames(10)
			await _frames(30)
			await _shot("brief_done", "after the briefing: objective + spies spawned")

	if _want("muster") or _want("follow") or _want("mount"):
		var posts := get_tree().get_nodes_in_group("phase3_soldier_posts")
		var p: Vector3 = (posts[0] as Node3D).global_position if posts.size() > 0 else Vector3(-160, 0, -60)
		await _place(Vector3(-108, 0, -64), 90.0)
		await _settle(60)
		await _photo_at(p + Vector3(0, 16, 22), p + Vector3(0, 0, 4))
		await _shot("muster", "the company at the training-ground posts")
		photo.current = false
		campaign.army.set_follow(true)
		await _settle(600)
		await _shot("regroup", "the company comes to the parade ground")
		await _drive(Vector2(0, 1), false, 300)
		await _settle(120)
		await _shot("follow", "following in ranks")
		await _photo_at(player.global_position + player.global_transform.basis * Vector3(6, 3, 6), player.global_position + Vector3.UP)
		await _shot("follow_side", "the company behind the commander")
		photo.current = false
		if _want("mount"):
			main.spawn_horse_near(player)
			await _frames(10)
			var rider := player.get_node("Rider") as Rider
			rider.mount(main.horse)
			await _frames(400)
			await _photo_at(player.global_position + Vector3(8, 4, 8), player.global_position)
			await _shot("mounted_army", "soldiers mounting the company's horses")
			photo.current = false
			for i in 300:
				player.input_override = {"move": Vector2(0, 1), "sprint": false}
				await get_tree().physics_frame
			await _settle(60)
			await _shot("mounted_ride", "riding with the mounted company")
			for b in campaign.army.living():
				if b.mode == SoldierBrain.Mode.MOUNTED:
					var hp := b.horse.global_position
					await _photo_at(hp + b.horse.global_transform.basis.x * -4.0 + Vector3.UP * 2.0, hp + Vector3.UP * 1.4)
					await _shot("mounted_soldier", "a soldier in the saddle")
					photo.current = false
					break
			rider.force_dismount()
			await _settle(60)

	if _want("spies"):
		if campaign.state.state_of(2) != CampaignState.M.ENCOUNTER_ACTIVE:
			_force_mission(2)
			campaign.start_encounter(2)
		await _frames(30)
		var spy: SoldierBrain = campaign.encounter.enemies[5]
		await _photo_at(spy.avatar.global_position + Vector3(4, 2.5, 4), spy.avatar.global_position + Vector3.UP)
		await _shot("spy", "a spy on its patrol route")
		photo.current = false

	if _want("square"):
		_force_mission(3)
		campaign._prepare_encounter(3)
		var c := campaign.encounter.area_center()
		await _photo_at(c + Vector3(-30, 14, 2), c)
		await _frames(30)
		await _shot("square_wait", "20 enemies holding Castle Square")
		photo.current = false
		campaign.army.set_follow(true)
		await _place(CampaignUtil.v3(world, [205, 94]), 90.0)
		await _frames(30)
		for i in 600:
			await get_tree().physics_frame
			if i % 120 == 0:
				Combat.heal_player(player.player_id, 100)
		await _photo_at(c + Vector3(-18, 9, 12), c)
		await _shot("square_fight", "the fight in the square")
		photo.current = false
		await _shot("square_hud", "HUD during the fight")

	if _want("gate"):
		_force_mission(4)
		campaign._prepare_encounter(4)
		var c := campaign.encounter.area_center()
		await _photo_at(c + Vector3(30, 26, 0), c + Vector3(-20, 0, 0))
		await _frames(30)
		await _shot("gatefield", "50 enemies before the sealed gate")
		photo.current = false

	if _want("failed"):
		_force_mission(3)
		campaign._prepare_encounter(3)
		await _place(CampaignUtil.v3(world, [205, 94]), 90.0)
		campaign.start_encounter(3)
		await _frames(20)
		Combat.apply_damage(player.player_id, 500, -1, "test")
		await _frames(int(3.2 * 60 * campaign.speed) + 30)
		await _shot("failed", "mission failed: Retry / Quit")
		campaign.retry()
		await _frames(120)
		await _shot("retried", "after Retry")

	if _want("gait"):
		await _place(Vector3(-232, 0, 105), 0.0)
		var rig := _commander()
		await _settle(30)
		for mode in [["walk", false, false], ["run", true, false], ["sprint2", true, true]]:
			if mode[2]:
				rig.toggle_swords()
				await _settle(80)
			player.teleport(player.global_position + Vector3(0, 0, 0), 0.0)
			var res := SpawnValidator.find(world, Vector2(-232, 105), NAN, 6.0)
			player.teleport(res["position"] + Vector3.UP * 0.1, 0.0)
			for i in 90:
				player.input_override = {"move": Vector2(0, 1), "sprint": mode[1]}
				await get_tree().physics_frame
			for k in 3:
				for i in 7:
					player.input_override = {"move": Vector2(0, 1), "sprint": mode[1]}
					await get_tree().physics_frame
				var f := player.global_position
				var right := player.global_transform.basis.x
				await _photo_at(f + right * 4.2 + Vector3.UP * 1.2 + player.forward() * 0.6, f + Vector3.UP * 1.0)
				await _shot("%s_side_%d" % [mode[0], k], "%s, side view (%.1f m/s)" % [mode[0], Vector2(player.velocity.x, player.velocity.z).length()])
				_pose_report(rig)
			await _photo_at(player.global_position - player.forward() * 4.0 + player.global_transform.basis.x * 2.0 + Vector3.UP * 1.6, player.global_position + Vector3.UP)
			await _shot("%s_back" % mode[0], "%s, three-quarter rear" % mode[0])
			photo.current = false
		await _settle(60)

	if _want("cave"):
		var cave: Dictionary = world.terrain_data.cave
		var floor_h: float = cave.get("floor", 9.0)
		for spot in [[Vector3(-32, 0, -176), 0.0, "cave_mouth"], [Vector3(-32, 0, -190), 0.0, "cave_tunnel"], [Vector3(-32, 0, -206), 90.0, "cave_chamber"]]:
			var p: Vector3 = spot[0]
			p.y = floor_h + 0.2
			player.teleport(p, deg_to_rad(spot[1]))
			await _settle(60)
			await _drive(Vector2(0, 1), false, 40)
			await _settle(30)
			await _shot(spot[2], "inside the cave")
		var crypt := world.get_node("Sites/Structures") as Node
		if "story_anchors" in crypt:
			pass

	get_tree().quit()


## Bone directions in the body frame (x right, y up, z forward along travel), degrees
## of torso lean, and which way each blade points.
func _pose_report(rig: CommanderRig) -> void:
	var sk := rig.skeleton
	var fwd := player.forward()
	var right := fwd.cross(Vector3.UP).normalized()
	var to_body := func(v: Vector3) -> Vector3:
		return Vector3(v.dot(right), v.y, v.dot(fwd)).snapped(Vector3.ONE * 0.01)
	# Bone attachments see the final pose (after the sprint layer); bone_world() does not.
	var dir := func(a: String, b: String) -> Vector3:
		return (rig.bone_socket(b).global_position - rig.bone_socket(a).global_position).normalized()
	var spine: Vector3 = dir.call("pelvis", "neck_01")
	var lean := rad_to_deg(acos(clampf(spine.dot(Vector3.UP), -1.0, 1.0)))
	var out := "  lean %.0f deg" % lean
	for side in ["l", "r"]:
		out += "  %s: upper %s fore %s" % [side, str(to_body.call(dir.call("upperarm_" + side, "lowerarm_" + side))), str(to_body.call(dir.call("lowerarm_" + side, "hand_" + side)))]
	for b in [rig.sword, rig.offhand_sword]:
		if b and b.visible:
			out += "  blade %s" % str(to_body.call((b.global_transform.basis * Vector3.UP).normalized()))
	print(out, "  swords in hand: ", rig.swords_in_hand())


func _want(name: String) -> bool:
	return only == "" or Array(only.split(",")).has(name)


func _commander() -> CommanderRig:
	return (player.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig


## Marks earlier missions complete and makes `id` ACTIVE (a tour shortcut, not play).
func _force_mission(id: int) -> void:
	campaign.encounter.reset()
	for m in campaign.state.missions():
		var mid := int(m["id"])
		if mid < id and campaign.state.state_of(mid) != CampaignState.M.RESERVED:
			campaign.state.states[mid] = CampaignState.M.COMPLETE
	campaign.state.states[id] = CampaignState.M.ACTIVE
	campaign._encounter_mission = -1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _settle(n: int) -> void:
	player.input_override = {"move": Vector2.ZERO}
	await _frames(n)


func _drive(move: Vector2, sprint: bool, n: int) -> void:
	for i in n:
		player.input_override = {"move": move, "sprint": sprint}
		await get_tree().physics_frame


func _place(p: Vector3, yaw_deg: float) -> void:
	var res := SpawnValidator.find(world, Vector2(p.x, p.z), NAN, 8.0)
	player.teleport((res["position"] if res["ok"] else p) + Vector3.UP * 0.1, deg_to_rad(yaw_deg))
	await _settle(45)


func _at_anchor(anchor: String, yaw: float) -> void:
	var p: Vector3 = main.story.anchor_pos(anchor)
	player.teleport(p + Vector3.UP * 0.1, yaw)
	await _settle(30)


func _photo_at(from: Vector3, look: Vector3) -> void:
	photo.global_position = from
	photo.look_at(look)
	photo.current = true
	await get_tree().process_frame


func _shot(shot_name: String, note: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot_name + ".png"))
	print("[tour] %-18s %s   | mission: %s   army: %s" % [shot_name, note, campaign.chud.title_text() + " / " + campaign.chud.objective_text() + " " + campaign.chud.progress_text(), campaign.chud.army_text()])
