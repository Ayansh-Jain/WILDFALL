extends Node
## Key rebinding, persistence and comfort settings. Restores the user's
## settings file afterwards.


func run(t) -> void:
	var backup := ""
	var had_file := FileAccess.file_exists(Settings.SAVE_PATH)
	if had_file:
		backup = FileAccess.get_file_as_string(Settings.SAVE_PATH)

	for action in Settings.DEFAULT_BINDINGS:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			t.check(false, "default binding for %s" % action)
	t.check(Settings.get_binding_text("interact") == "E", "interact defaults to E", Settings.get_binding_text("interact"))
	t.check(Settings.get_binding_text("move_forward") == "W", "move forward defaults to W")
	t.check(Settings.get_binding_text("special_attack") == "Z" and Settings.get_binding_text("ability_2") == "R",
		"the finisher has a dedicated key and keeps R for Ward")
	t.check(Settings.get_binding_text("toggle_lamp") == "L", "the portable lamp has a dedicated L binding")

	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	Settings.rebind("interact", key)
	var evs := InputMap.action_get_events("interact")
	t.check(evs.size() == 1 and evs[0] is InputEventKey and evs[0].physical_keycode == KEY_F, "rebinding interact to F updates the InputMap")
	t.check(Settings.get_binding_text("interact") == "F", "binding label follows the rebind")

	var press := InputEventKey.new()
	press.physical_keycode = KEY_F
	press.pressed = true
	t.check(press.is_action_pressed("interact"), "pressing F now triggers interact")
	var old := InputEventKey.new()
	old.physical_keycode = KEY_E
	old.pressed = true
	t.check(not old.is_action_pressed("interact"), "E no longer triggers interact")

	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	Settings.rebind("crouch", mb)
	t.check(Settings.get_binding_text("crouch") == "Mouse R", "actions can be bound to mouse buttons")

	# Persistence: a fresh Settings instance reads the saved file.
	var fresh: Node = load("res://scripts/managers/settings.gd").new()
	fresh._load()
	t.check(fresh.get_specs("interact") == ["key:F"], "rebinding is saved to disk", str(fresh.get_specs("interact")))
	fresh.free()

	Settings.reset_bindings()
	t.check(Settings.get_binding_text("interact") == "E" and Settings.get_binding_text("crouch") == "Ctrl", "reset restores default bindings")

	# The in-game Controls menu rebinds through a real button press and key event.
	var menu: PauseMenu = t.main.pause_menu
	menu.open()
	t.check(menu.is_open() and get_tree().paused, "Esc menu opens and pauses the game")
	var btn: Button = menu._bind_buttons["jump"]
	btn.pressed.emit()
	t.check(btn.text == "Press a key...", "clicking a binding waits for a key")
	var j := InputEventKey.new()
	j.physical_keycode = KEY_J
	j.pressed = true
	Input.parse_input_event(j)
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(Settings.get_binding_text("jump") == "J" and btn.text == "J", "pressing J in the Controls menu rebinds jump", btn.text)
	Settings.reset_bindings()
	t.check(btn.text == "Space", "menu shows defaults after reset", btn.text)
	menu.close()
	t.check(not menu.is_open() and not get_tree().paused, "closing the menu resumes the game")

	# Sensitivity and head bob settings are applied live.
	var player: PlayerController = t.main.player
	var old_sens := Settings.mouse_sensitivity
	Settings.set_value("mouse_sensitivity", 0.2)
	player.set_look(0.0)
	player.look(Vector2(50, 0))
	t.check(absf(rad_to_deg(-player.rotation.y) - 10.0) < 0.01, "mouse sensitivity setting applies immediately")
	Settings.set_value("mouse_sensitivity", old_sens)

	var drv := PlayerDriver.new(player)
	var meadow := SpawnValidator.find(t.world, Vector2(150, -62), NAN, 10.0, {"max_slope_deg": 8.0})
	var bob_on := await _bob_range(drv, player, meadow["position"], true)
	var bob_off := await _bob_range(drv, player, meadow["position"], false)
	t.check(bob_on > 0.02 and bob_on < 0.12, "head bob is subtle when enabled", "%.3f m" % bob_on)
	t.check(bob_off < 0.01, "head bob can be disabled", "%.3f m" % bob_off)
	Settings.set_value("head_bob", true)
	drv.release()

	if had_file:
		var f := FileAccess.open(Settings.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.SAVE_PATH))


func _bob_range(drv: PlayerDriver, player: PlayerController, pos: Vector3, enabled: bool) -> float:
	Settings.set_value("head_bob", enabled)
	player.teleport(pos, 0.0)
	await drv.frames(20)
	drv.set_input(Vector2(0, 1))
	await drv.frames(30)
	var lo := INF
	var hi := -INF
	for i in 60:
		await drv.frames(1)
		var rel := player.head.position.y
		lo = minf(lo, rel)
		hi = maxf(hi, rel)
	drv.set_input()
	return hi - lo
