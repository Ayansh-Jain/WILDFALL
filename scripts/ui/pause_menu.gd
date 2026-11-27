class_name PauseMenu
extends CanvasLayer
## Esc menu: resume, unstuck, settings (sensitivity, FOV, head bob, volume)
## and key rebinding. Pauses the tree while open.

var main: Node  ## Set by Main; used for "Unstuck".
## Set before adding to the tree: the menu of a visited scene (see DevVisit).
var visiting := false

var _root: Control
var _listening_action := ""
var _listening_button: Button
var _bind_buttons := {}


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	Settings.bindings_changed.connect(_refresh_bindings)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_bindings()


func close() -> void:
	_cancel_listen()
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	var accept := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
			_cancel_listen()
			get_viewport().set_input_as_handled()
			return
		accept = true
	elif event is InputEventMouseButton and event.pressed and event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		accept = true
	if accept:
		Settings.rebind(_listening_action, event)
		_listening_action = ""
		_listening_button = null
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif not is_open() and event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _cancel_listen() -> void:
	_listening_action = ""
	_listening_button = null
	_refresh_bindings()


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = Settings.get_binding_text(action)


# --- UI construction ---------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.1, 0.94)
	style.border_color = Color(0.45, 0.6, 0.55, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.82, 0.88, 0.8))
	vb.add_child(title)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(480, 330)
	vb.add_child(tabs)
	tabs.add_child(_game_tab())
	tabs.add_child(_settings_tab())
	tabs.add_child(_controls_tab())


func _game_tab() -> Control:
	var vb := VBoxContainer.new()
	vb.name = "Game"
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(_button("Resume", close))
	if visiting:
		vb.add_child(_button("Return to the kingdom", func() -> void: DevVisit.go_home(get_tree())))
		vb.add_child(_button("Quit to desktop", func() -> void: get_tree().quit()))
		return vb
	vb.add_child(_button("World map", func() -> void:
		close()
		if main and main.get("world_map"):
			main.world_map.open()))
	var saves := HBoxContainer.new()
	saves.add_theme_constant_override("separation", 10)
	for entry in [["Save game", _save_game], ["Load last save", _load_game]]:
		var b := _button(entry[0], entry[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		saves.add_child(b)
	vb.add_child(saves)
	vb.add_child(_button("Unstuck (return to nearest spawn)", func() -> void:
		close()
		if main:
			main.respawn_nearest()))
	vb.add_child(_button("Restart the campaign (erases mission progress)", func() -> void:
		close()
		if main and main.get("campaign"):
			main.campaign.restart_campaign()))
	for id in DevVisit.available():
		var visit := _button("Visit: " + DevVisit.DESTINATIONS[id][0], _visit.bind(id))
		visit.tooltip_text = "Not available during a battle."
		vb.add_child(visit)
	vb.add_child(_button("Quit to desktop", func() -> void:
		if main and main.has_method("save_on_exit"):
			close()
			main.save_on_exit()
		get_tree().quit()))
	var hint := Label.new()
	hint.text = "WASD move   Mouse look   Space jump   Shift sprint\nCtrl/C crouch   E interact   T call / dismiss army   Tab map   V follow the wind   F3 debug overlay"
	hint.add_theme_color_override("font_color", Color(0.6, 0.68, 0.65))
	vb.add_child(hint)
	return vb


func _save_game() -> void:
	close()
	if main and main.get("exploration"):
		main.hud.toast(main.exploration.save_game(), 3.0)


## Reloads the kingdom from the last save (progress since then is lost).
func _load_game() -> void:
	close()
	if not Persist.active:
		return
	DevVisit.go_home(get_tree())


## Leaving mid-battle would abandon it, so visits wait until it is over.
func _visit(id: String) -> void:
	if main == null:
		return
	var campaign: CampaignDirector = main.get("campaign")
	if campaign:
		if campaign.in_encounter():
			var hud := get_tree().get_first_node_in_group("hud")
			close()
			if hud:
				hud.toast("Finish the battle first.", 2.5)
			return
		# Wounds and losses go into the save before the world is dropped (no free healing).
		campaign.army.sync_to_state()
		campaign.save()
	DevVisit.go(get_tree(), id, main.get("player"))


func _settings_tab() -> Control:
	var grid := GridContainer.new()
	grid.name = "Settings"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	_slider_row(grid, "Mouse sensitivity", 0.02, 0.5, 0.01, Settings.mouse_sensitivity, "mouse_sensitivity")
	_slider_row(grid, "Field of view", 60.0, 100.0, 1.0, Settings.fov, "fov")
	_slider_row(grid, "Master volume (dB)", -40.0, 6.0, 1.0, Settings.master_volume_db, "master_volume_db")
	_check_row(grid, "Invert mouse Y", Settings.invert_y, "invert_y")
	_check_row(grid, "Head bob", Settings.head_bob, "head_bob")
	_slider_row(grid, "Camera distance", 0.7, 1.4, 0.05, Settings.camera_distance, "camera_distance")
	_slider_row(grid, "Camera shake", 0.0, 1.0, 0.1, Settings.camera_shake, "camera_shake")
	_check_row(grid, "Reduce motion", Settings.reduce_motion, "reduce_motion")
	return grid


func _controls_tab() -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Controls"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 260)
	outer.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	scroll.add_child(grid)
	for action in Settings.REBINDABLE:
		var l := Label.new()
		l.text = Settings.get_action_label(action)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(140, 0)
		b.pressed.connect(func() -> void:
			_refresh_bindings()
			_listening_action = action
			_listening_button = b
			b.text = "Press a key...")
		_bind_buttons[action] = b
		grid.add_child(b)
	var hint := Label.new()
	hint.text = "Click a binding, then press a key or mouse button. Esc cancels."
	hint.add_theme_color_override("font_color", Color(0.6, 0.68, 0.65))
	outer.add_child(hint)
	outer.add_child(_button("Reset to defaults", Settings.reset_bindings))
	return outer


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _slider_row(grid: GridContainer, label: String, lo: float, hi: float, step: float, value: float, key: String) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var hb := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(200, 0)
	var v := Label.new()
	v.custom_minimum_size = Vector2(48, 0)
	v.text = str(snappedf(value, step))
	s.value_changed.connect(func(x: float) -> void:
		v.text = str(snappedf(x, step))
		Settings.set_value(key, x))
	hb.add_child(s)
	hb.add_child(v)
	grid.add_child(hb)


func _check_row(grid: GridContainer, label: String, value: bool, key: String) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var c := CheckBox.new()
	c.button_pressed = value
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	grid.add_child(c)
