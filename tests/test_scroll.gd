extends Node
## Scroll placement, interaction prompt, collection through the real input
## path, one-time collection, removal, and match reset.


func run(t) -> void:
	var w: World = t.world
	var main = t.main
	var player: PlayerController = main.player
	var hud: HUD = main.hud
	var interactor: PlayerInteractor = player.get_node("Interactor")
	var drv := PlayerDriver.new(player)
	drv.set_input()

	var scrolls := get_tree().get_nodes_in_group("scroll")
	t.check(scrolls.size() == 1, "one scroll in the world")
	var scroll: Scroll = scrolls[0]
	t.check(GameState.scroll_marker != "" and scroll.global_position.distance_to(GameState.scroll_position) < 0.01,
		"GameState records the scroll marker", GameState.scroll_marker)
	t.check(not GameState.scroll_is_collected, "scroll starts uncollected")
	t.check(scroll.get_node("Light").visible and scroll.get_node("Sparkles").emitting, "scroll has its glow and sparkle effect")
	t.check(scroll.get_node("Hum").playing, "scroll emits its magical hum")
	var lib := AudioLib.get_instance()
	var loops_ok := true
	for sound in Synth.SOUNDS:
		var s: AudioStreamWAV = lib.get_stream(sound)
		if s == null:
			loops_ok = false
		elif Synth.SOUNDS[sound][1] and (s.loop_mode != AudioStreamWAV.LOOP_FORWARD or s.loop_end <= 0):
			loops_ok = false
	# Some sounds are deliberately synthesized at runtime (see AudioLib), so only
	# require a stream for each name and looping for the ambience beds.
	t.check(loops_ok, "every sound has a stream and ambience beds loop")

	# Far away: no prompt.
	var sp := scroll.global_position
	var far := SpawnValidator.find(w, Vector2(sp.x + 9.0, sp.z), sp.y + 2.0, 4.0)
	player.teleport(far["position"])
	_look_at(player, sp + Vector3.UP * 0.75)
	await drv.frames(5)
	t.check(interactor.focused == null and hud.prompt_text() == "", "no prompt from 9 m away")

	# Close and facing it: prompt appears with the bound key.
	var near := SpawnValidator.find(w, Vector2(sp.x + 1.8, sp.z), sp.y + 2.0, 2.0)
	t.check(near["ok"], "found a standing spot next to the scroll")
	player.teleport(near["position"])
	_look_at(player, sp + Vector3.UP * 0.75)
	await drv.frames(5)
	t.check(interactor.focused == scroll.interactable, "scroll becomes the interaction focus when approached")
	var expected := "[%s]" % Settings.get_binding_text("interact")
	t.check(hud.prompt_text().begins_with(expected) and hud.prompt_text().contains("scroll"),
		"interaction prompt shows the bound key", hud.prompt_text())

	# Looking away hides the prompt.
	player.set_look(player.rotation.y + PI, 0.0)
	await drv.frames(3)
	t.check(interactor.focused == null, "prompt disappears when looking away")
	_look_at(player, sp + Vector3.UP * 0.75)
	await drv.frames(3)

	# Collect through the real input path (an "interact" action event).
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await drv.frames(3)
	var release := InputEventAction.new()
	release.action = "interact"
	release.pressed = false
	Input.parse_input_event(release)
	t.check(GameState.scroll_is_collected, "pressing interact collects the scroll")
	t.check(GameState.scroll_holder() == player.player_id, "the collector holds the monster identity (server-side record)")
	t.check(GameState.get_state(player.player_id) == PlayerState.State.MONSTER_HIDDEN, "collector is MONSTER_HIDDEN, not forced into a transformation")
	t.check(not scroll.interactable.enabled, "scroll can no longer be interacted with")
	t.check(not interactor.try_interact(), "a second interaction does nothing")
	t.check(not GameState.collect_scroll(player.player_id), "GameState refuses a second collection")
	await drv.frames(10)
	t.check(interactor.focused == null and hud.prompt_text() == "", "prompt clears after collection")
	await drv.frames(170)
	t.check(not is_instance_valid(scroll) and get_tree().get_nodes_in_group("scroll").is_empty(), "collected scroll is removed from the world")

	# Reset for a new match: exactly one fresh scroll.
	GameState.reset_match(777)
	var marker: String = main.scroll_spawner.spawn(GameState.scroll_seed)
	await drv.frames(2)
	t.check(get_tree().get_nodes_in_group("scroll").size() == 1 and not GameState.scroll_is_collected, "match reset spawns one new scroll", marker)
	var again: String = main.scroll_spawner.spawn(GameState.scroll_seed)
	await drv.frames(2)
	t.check(again == marker and get_tree().get_nodes_in_group("scroll").size() == 1, "respawning never duplicates the scroll")
	drv.release()


func _look_at(player: PlayerController, target: Vector3) -> void:
	var eye := player.global_position + Vector3.UP * player.stand_eye
	var d := target - eye
	var flat := Vector2(d.x, d.z).length()
	player.set_look(atan2(-d.x, -d.z), atan2(d.y, flat))
