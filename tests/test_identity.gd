extends Node
## Scroll -> hidden identity -> transformation and back (scenarios 1-5).


func run(t) -> void:
	var k := CombatKit.new(t)
	var me := k.local
	var id := me.player_id
	GameState.reset_match(GameState.scroll_seed)
	t.main.scroll_spawner.spawn(GameState.scroll_seed)
	await k.frames(3)

	# Signals: public vs private.
	var taken_args := []
	var granted := []
	var on_taken := func() -> void: taken_args.append("taken")
	var on_granted := func(pid: int, mid: String) -> void: granted.append([pid, mid])
	GameState.scroll_taken.connect(on_taken)
	GameState.identity_granted.connect(on_granted)

	# 1. Collect once.
	var scroll: Scroll = get_tree().get_nodes_in_group("scroll")[0]
	var other := k.dummy(Vector3(6, 0, 0))
	t.check(scroll.collect(me), "local player collects the scroll")
	t.check(GameState.has_monster(id) and GameState.record(id).monster_id == "ember_beast", "collector receives the Ember Beast identity")
	t.check(GameState.get_state(id) == PlayerState.State.MONSTER_HIDDEN, "collector starts MONSTER_HIDDEN (no forced transformation)")
	t.check(is_instance_valid(me.get_node("AvatarVisual")) and me.get_node("AvatarVisual").form_rig == null, "no monster model appears on collection")
	t.check(is_equal_approx(me.capsule.height, 1.8) and me.combatant.max_health == 100, "body and health stay human-sized while hidden")
	# 2. Cannot be collected twice (by anyone).
	t.check(not scroll.collect(me) and not GameState.collect_scroll(id), "the scroll cannot be collected a second time")
	t.check(not GameState.collect_scroll(other.player_id), "another player cannot collect it either")
	await k.frames(170)
	t.check(get_tree().get_nodes_in_group("scroll").is_empty(), "the scroll is removed from the world")
	t.check(taken_args.size() == 1, "one public 'scroll taken' event, carrying no collector")
	t.check(granted.size() == 1 and granted[0][0] == id, "identity is delivered privately, to the collector only")
	GameState.scroll_taken.disconnect(on_taken)
	GameState.identity_granted.disconnect(on_granted)

	# 4. Hidden identity is not exposed.
	var pub := GameState.public_view(id)
	t.check(not pub.has("monster_id") and not pub.has("state") and pub["visible_form"] == "human", "public view of a hidden monster shows only a human", str(pub))
	t.check(GameState.private_view(id)["monster_id"] == "ember_beast", "private view (for the owner) includes the identity")
	var sa := CombatKit.tree_signature(me.get_node("AvatarVisual"))
	var sb := CombatKit.tree_signature(other.get_node("AvatarVisual"))
	t.check(sa == sb, "hidden monster's visible node tree is identical to a human's", CombatKit.first_diff(sa, sb))
	var hunter := k.dummy(Vector3(-6, 0, 0), SimBot.Role.HUNTER)
	var ha := CombatKit.tree_signature(hunter)
	var hb := CombatKit.tree_signature(other)
	t.check(ha == hb, "hunter and wanderer bots have identical scene trees", CombatKit.first_diff(ha, hb))
	t.check(not String(hunter.name).to_lower().contains("monster") and hunter.display_name.begins_with("Wanderer"), "monster bot's name gives nothing away")
	var hud: CombatHUD = t.main.combat_hud
	t.check(hud._who(hunter.player_id) == hunter.display_name, "a hidden monster appears to others by its name only")
	var old_dev := GameState.dev_mode
	GameState.dev_mode = false
	var overlay: String = t.main.hud._debug_text()
	GameState.dev_mode = old_dev
	t.check(not overlay.to_lower().contains("monster") and not overlay.contains("Ember") and not overlay.contains("collected by"),
		"debug overlay outside developer builds reveals no identity")
	t.check(hud.status_text().contains("hidden"), "the owner's private HUD status says hidden")

	# Transform rules.
	var r: Dictionary = Combat.request_transform(other.player_id)
	t.check(not r["ok"] and r["reason"] == "no monster powers", "a player without powers cannot transform")
	var roof := k.wall(Vector3(30, 2.05, 0), Vector3(3, 0.3, 3))
	var me_start := me.global_position
	k.place(me, Vector3(30, 0, 0))
	await k.frames(5)
	r = Combat.request_transform(id)
	t.check(not r["ok"] and r["reason"] == "no room", "transformation is refused under a low ceiling", r["reason"])
	roof.queue_free()
	k.place(me, Vector3(0, 0, 0))
	await k.frames(5)

	# 5. Transformation keeps camera control.
	me.set_look(0.0, 0.0)
	r = Combat.request_transform(id)
	t.check(r["ok"] and GameState.is_revealed(id), "transform input reveals the monster")
	await k.frames(10)
	var yaw0 := me.rotation.y
	me.look(Vector2(100, 0))
	t.check(absf(rad_to_deg(yaw0 - me.rotation.y) - 100.0 * Settings.mouse_sensitivity) < 0.05, "mouse look works during the transformation")
	t.check(not Combat.request_action(id, "attack")["ok"], "no attacks while the transformation plays")
	await k.seconds(1.2)
	var vis: AvatarVisual = me.get_node("AvatarVisual")
	t.check(vis.form_rig != null and vis.form_rig.name == "RevealedForm", "a generic 'RevealedForm' model is attached when revealed")
	t.check(is_equal_approx(me.capsule.height, 2.5) and me.combatant.max_health == 250, "revealed body is beast-sized with beast health")
	t.check(absf(me.head.position.y - 2.3) < 0.15 and absf(me.head.rotation.z) < 0.001, "camera sits at the beast's eye height, level", "%.2f" % me.head.position.y)
	me.look(Vector2(0, -10000))
	t.check(absf(rad_to_deg(me.head.rotation.x) - me.max_pitch) < 0.01, "pitch is still clamped in beast form")
	me.set_look(me.rotation.y, 0.0)
	t.check(Combat.ability_id_for_action(id, "attack") == "claw", "attack input maps to Claw while revealed")
	t.check(GameState.public_view(id)["visible_form"] == "ember_beast", "once revealed, the beast form is public (it is visible)")

	# Commitment: cannot hide again instantly, cooldown before re-transforming.
	r = Combat.request_revert(id)
	t.check(not r["ok"] and r["reason"] == "locked", "cannot return to human before the minimum reveal time")
	var def := GameState.monster_definition("ember_beast")
	await k.seconds(def.min_reveal_duration)
	r = Combat.request_revert(id)
	t.check(r["ok"] and GameState.get_state(id) == PlayerState.State.MONSTER_HIDDEN, "returns to human appearance after the reveal period")
	# 3. Powers retained.
	t.check(GameState.has_monster(id), "monster powers are kept after returning to human")
	await k.frames(2)
	t.check(vis.form_rig == null and not vis.has_node("RevealedForm"), "beast model is removed on return")
	t.check(is_equal_approx(me.capsule.height, 1.8) and me.combatant.max_health == 100, "human body and health restored")
	t.check(Combat.ability_id_for_action(id, "attack") == "sword_strike", "human abilities are back")
	r = Combat.request_transform(id)
	t.check(not r["ok"] and r["reason"] == "cooldown", "transform has a cooldown after returning")
	await k.seconds(def.transform_cooldown + 0.2)
	r = Combat.request_transform(id)
	t.check(r["ok"], "transform is available again after the cooldown")
	await k.seconds(1.0)

	# Revert is blocked right after combat.
	var target := k.dummy(Vector3(0, 0, -2))
	k.place(me, Vector3.ZERO, 0.0)
	await k.seconds(def.min_reveal_duration)
	Combat.request_action(id, "attack")
	await k.seconds(0.4)
	r = Combat.request_revert(id)
	t.check(not r["ok"], "cannot slip back into human form mid-fight (combat lockout)")
	t.check(target.combatant.health < 100, "the claw that triggered the lockout landed")
	me.global_position = me_start
	await k.cleanup()
