extends Node
## Story sequences and the Ashford village: the decorative buildings are solid,
## unclimbable and have nothing to interact with; the missing-child and
## night-before-war sequences run end to end through the real interactables.

const BUILDINGS := ["Tavern", "Bakery", "Granary", "Smithy", "GeneralGoods", "Joinery", "CottageA", "CottageB", "CottageC", "CottageD"]


func run(t) -> void:
	var w: World = t.world
	var main: Node = t.main
	var player: PlayerController = main.player
	var story: StoryDirector = main.story
	var cave_clue: CaveStoryScroll = main.cave_story_scroll
	t.check(cave_clue != null and is_instance_valid(cave_clue), "a separate story scroll is placed in the open cave")
	if cave_clue:
		var cave := w.terrain_data.cave
		t.check(cave["rect"].has_point(Vector2(cave_clue.global_position.x, cave_clue.global_position.z)),
			"the story scroll lies within the existing cave chamber")
		var had_identity := GameState.has_monster(player.player_id)
		var cave_spot := SpawnValidator.find(w, Vector2(cave_clue.global_position.x + 2.0, cave_clue.global_position.z),
			cave_clue.global_position.y + 3.0, 8.0)
		t.check(cave_spot.ok, "the chamber floor has a player sized approach to the scroll", str(cave_spot.get("reason", "")))
		if cave_spot.ok:
			player.teleport(cave_spot.position + Vector3.UP * 0.05)
			var to_clue := cave_clue.interactable.focus_point() - player.eye_position()
			var flat_distance := Vector2(to_clue.x, to_clue.z).length()
			player.set_look(atan2(-to_clue.x, -to_clue.z), atan2(to_clue.y, flat_distance))
			await t.physics_frames(4)
			var interactor := player.get_node("Interactor") as PlayerInteractor
			t.check(interactor.focused == cave_clue.interactable, "the existing interaction system focuses the cave scroll")
			interactor.try_interact()
		t.check(cave_clue.inspected and GameState.has_monster(player.player_id) == had_identity,
			"inspecting the cave clue does not force transformation or progression")
	story.speed = 0.01
	var village := w.get_node_or_null("Sites/Structures/Ashford")
	t.check(village != null, "Ashford village is built")
	if village == null:
		return

	# --- decorative buildings ---------------------------------------------------------
	var drv := PlayerDriver.new(player)
	for bname in BUILDINGS:
		var body := village.get_node_or_null(bname) as StaticBody3D
		if not t.check(body != null and body.collision_layer & Layers.WORLD, "%s exists with world collision" % bname):
			continue
		var cs: CollisionShape3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				cs = c
		var box := cs.shape as BoxShape3D
		var interactables := body.find_children("*", "Interactable", true, false)
		t.check(interactables.is_empty(), "%s has no interaction prompt" % bname)
		var ground := w.terrain_height(cs.global_position.x, cs.global_position.z)
		var top := cs.global_position.y + box.size.y * 0.5
		t.check(top - ground > 4.5, "%s cannot be climbed (solid to %.1f m)" % [bname, top - ground])
		# Walk straight at the front door: the shell must stop the player outside.
		var front := cs.global_transform.basis * Vector3(0, 0, -1)
		var start := cs.global_position + front.normalized() * (box.size.z * 0.5 + 4.0)
		var res := SpawnValidator.find(w, Vector2(start.x, start.z), NAN, 3.0, {"max_slope_deg": 40.0, "edge_margin": 0.0})
		if not res["ok"]:
			t.check(false, "%s door approach has a valid start" % bname, res["reason"])
			continue
		player.teleport(res["position"] + Vector3.UP * 0.05)
		await drv.frames(5)
		await drv.walk([cs.global_position], {"leg_timeout": 3.5, "reach": 0.5, "sprint": true})
		var local := cs.global_transform.affine_inverse() * player.global_position
		var inside := absf(local.x) < box.size.x * 0.5 - 0.1 and absf(local.z) < box.size.z * 0.5 - 0.1
		t.check(not inside, "%s cannot be entered through its door" % bname, "player local %s" % str(local.snapped(Vector3.ONE * 0.1)))
	drv.release()

	# --- the missing child -----------------------------------------------------------
	t.check(story.npcs.has("Maren") and not story.npcs.has("Tam"), "Maren waits in Ashford; Tam is not there yet")
	t.check(not story.npcs.has("Reve"), "Princess Reve is not introduced before the night-before-war sequence")
	var maren: StoryNPC = story.npcs["Maren"]
	maren.talk.interact(player)
	await _until(t, func() -> bool: return story.has_flag("child_quest_started") and not story.in_dialogue, 10.0)
	t.check(story.has_flag("child_quest_started") and story.objective.contains("lake shore"), "talking to Maren starts the search", story.objective)
	t.check(story.npcs.has("Tam"), "Tam is waiting at the water's edge")
	for i in 3:
		var clue: Interactable = story.triggers["Clue%d" % (i + 1)]
		t.check(clue.enabled, "clue %d is active" % (i + 1))
		clue.interact(player)
	t.check(story.has_flag("clue_3") and story.objective.contains("water"), "the clues lead to the water's edge", story.objective)
	var tam: StoryNPC = story.npcs["Tam"]
	var shore_y := w.water_level
	t.check(tam.global_position.y > shore_y + 0.2, "Tam stands on dry ground", "y %.2f" % tam.global_position.y)
	tam.talk.interact(player)
	await _until(t, func() -> bool: return story.has_flag("child_returned") and not story.in_dialogue, 10.0)
	t.check(story.objective.contains("Maren"), "after finding Tam the objective is to return", story.objective)
	await _until(t, func() -> bool: return tam.visible and tam.global_position.distance_to(story.anchor_pos("child_home")) < 0.5, 8.0)
	t.check(tam.global_position.distance_to(story.anchor_pos("child_home")) < 0.5, "Tam goes home to his grandmother")
	maren.talk.interact(player)
	await _until(t, func() -> bool: return story.has_flag("child_quest_done") and not story.in_dialogue, 10.0)
	t.check(story.has_flag("child_quest_done") and story.objective == "", "returning to Maren completes the quest")
	t.check(player.controls_enabled, "controls are restored after dialogue")

	# --- night before war ------------------------------------------------------------
	var desk: Interactable = story.triggers.get("BattleMaps")
	t.check(desk != null and desk.enabled, "the battle maps can be studied in the commander's bedroom")
	desk.interact(player)
	await _until(t, func() -> bool: return story.npcs.has("Reve"), 10.0)
	t.check(story.objective.contains("roof"), "the commander is sent to the roof", story.objective)
	var reve: StoryNPC = story.npcs.get("Reve")
	var hk := w.site_height("Lakeside Castle")
	t.check(reve != null and reve.global_position.y > hk + 22.0, "Princess Reve is on the keep roof", "y %.1f" % (reve.global_position.y - hk) if reve else "")
	if reve:
		t.check(reve.rig is ReveRig, "she is the realistic Reve model, not the placeholder")
		var space := w.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(reve.global_position + Vector3.UP * 0.5, reve.global_position + Vector3.DOWN * 1.0, Layers.WORLD, [reve.get_node("Body").get_rid()])
		t.check(not space.intersect_ray(q).is_empty(), "she stands on the roof floor")
		var rig := reve.rig as ReveRig
		t.check(rig != null and rig.mood == "gaze" and rig.look_target != null and rig.look_target.name == "MoonMark",
			"she waits at the parapet, looking at the moon")
		# The commander arrives on the roof behind her: she notices him.
		var behind := reve.global_position + reve.global_transform.basis.z * 4.0 + Vector3.UP * 0.1
		player.teleport(behind)
		await _until(t, func() -> bool: return story.has_flag("reve_noticed"), 3.0)
		t.check(story.has_flag("reve_noticed") and rig.look_target == player.head, "she notices the commander arriving and looks at him")
		reve.talk.interact(player)
		await _until(t, func() -> bool: return story.has_flag("rooftop_talk_done") and not story.in_dialogue, 15.0)
		t.check(story.has_flag("rooftop_talk_done"), "the rooftop conversation plays to the end")
		t.check(not reve.talk.enabled, "the conversation does not repeat")
		t.check(rig.mood == "gaze" and rig.look_target != null and rig.look_target.name == "MoonMark",
			"afterwards she returns her gaze to the night sky")


func _until(t, cond: Callable, seconds: float) -> void:
	var limit := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < limit:
		await t.get_tree().process_frame
