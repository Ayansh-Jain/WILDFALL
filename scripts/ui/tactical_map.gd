extends Control
## Local strategy table. Select a piece, then click a valid ground position.
var campaign: CampaignDirector
var placements := {}
var selected := -1
var assigned := {}
var terrain: Array = []
var message: Label
var confirmation: ConfirmationDialog
var old_mouse := Input.MOUSE_MODE_CAPTURED
var old_controls := true
var map_rect := Rect2()
var center := Vector3.ZERO
const EXTENT := 62.0

func setup(c: CampaignDirector) -> void:
	campaign = c
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	message = Label.new()
	message.position = Vector2(30, 20)
	message.add_theme_font_size_override("font_size", 20)
	add_child(message)
	var actions := HBoxContainer.new()
	actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	actions.position = Vector2(30, -55)
	add_child(actions)
	for entry in [["Reset formation", reset_plan], ["Place group", place_group], ["Confirm Strategy", ask_confirm], ["Close", close_map]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		actions.add_child(button)
	confirmation = ConfirmationDialog.new()
	confirmation.dialog_text = "Are you sure you want to deploy your army using this strategy?"
	confirmation.ok_button_text = "Confirm"
	confirmation.confirmed.connect(func() -> void: campaign.deploy_strategy(placements.duplicate()))
	add_child(confirmation)

func open_map() -> void:
	if visible or not campaign.can_plan():
		return
	center = campaign.encounter.area_center()
	old_controls = campaign.player.controls_enabled
	old_mouse = Input.mouse_mode
	campaign.player.controls_enabled = false
	campaign.army.set_paused(true)
	campaign.encounter.set_paused(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	terrain.clear()
	# Sample actual collision surfaces: heights, water, trees, rocks and buildings.
	var space := campaign.world.get_world_3d().direct_space_state
	for x in range(-30, 31):
		for z in range(-30, 31):
			var p := center + Vector3(x * 2, 0, z * 2)
			var h := campaign.world.terrain_height(p.x, p.z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 50, p.z), Vector3(p.x, h - 3, p.z), Layers.WORLD))
			var obstacle := not hit.is_empty() and float(hit["position"].y) > h + 1.5
			terrain.append([p, h, obstacle])
	reset_plan()

func close_map() -> void:
	if not visible:
		return
	confirmation.hide()
	visible = false
	campaign.player.controls_enabled = old_controls
	campaign.army.set_paused(false)
	campaign.encounter.set_paused(false)
	Input.mouse_mode = old_mouse

func reset_plan() -> void:
	placements.clear()
	assigned.clear()
	selected = -1
	for b in campaign.army.living():
		placements[b.soldier_id] = b.avatar.global_position
		if selected < 0:
			selected = b.soldier_id
	refresh()

func place_group() -> void:
	var used: Array = [campaign.player.global_position]
	for b in campaign.army.living():
		var found := false
		for ring in range(1, 12):
			if found:
				break
			for i in 16:
				var p := campaign.player.global_position + Vector3(cos(i * TAU / 16), 0, sin(i * TAU / 16)) * ring * 5.0
				if campaign.deployment_valid(p, used) and used.all(func(q: Vector3) -> bool: return CampaignUtil.flat_dist(p, q) > 4.5):
					placements[b.soldier_id] = p
					assigned[b.soldier_id] = true
					used.append(p)
					found = true
					break
	refresh()

func ask_confirm() -> void:
	confirmation.popup_centered(Vector2i(540, 150))

func refresh(note := "Select a numbered soldier, then click ground. Gold diamond: commander; red: visible enemy.") -> void:
	message.text = "WAR TABLE     %d available / %d assigned\n%s" % [placements.size(), assigned.size(), note]
	queue_redraw()

func project(p: Vector3) -> Vector2:
	return map_rect.get_center() + Vector2(p.x - center.x, p.z - center.z) * map_rect.size.x / (EXTENT * 2)

func unproject(p: Vector2) -> Vector3:
	var v := (p - map_rect.get_center()) * EXTENT * 2 / map_rect.size.x
	return center + Vector3(v.x, 0, v.y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and map_rect.has_point(event.position):
		for id in placements:
			if project(placements[id]).distance_to(event.position) < 14:
				selected = id
				refresh("Soldier %d selected. Click a valid deployment position." % id)
				return
		if selected < 0:
			return
		var p := unproject(event.position)
		var used: Array = [campaign.player.global_position]
		for id in placements:
			if id != selected:
				used.append(placements[id])
		if campaign.deployment_valid(p, used) and used.all(func(q: Vector3) -> bool: return CampaignUtil.flat_dist(p, q) > 4.5):
			placements[selected] = p
			assigned[selected] = true
			refresh()
		else:
			refresh("INVALID: choose clear ground outside the red warning boundary, away from other pieces.")
		accept_event()

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.055, 0.035, 1.0))
	var side := minf(size.x - 80, size.y - 170)
	map_rect = Rect2(Vector2((size.x - side) / 2, 90), Vector2(side, side))
	draw_rect(map_rect, Color(0.3, 0.32, 0.19))
	var scale := side / (EXTENT * 2)
	for sample in terrain:
		var h: float = sample[1]
		var col := Color(0.34, 0.37, 0.23).lightened(clampf((h - center.y) / 65.0, -0.2, 0.25))
		if h < campaign.world.water_level:
			col = Color(0.2, 0.35, 0.4)
		elif sample[2]:
			col = Color(0.12, 0.17, 0.10)
		draw_rect(Rect2(project(sample[0]), Vector2.ONE * 2.1 * scale), col)
	# Roads use the same authored polylines as the minimap and route network.
	for key in ["roads", "trails"]:
		for road in campaign.world.layout.list(key):
			var pts := WorldLayout.points(road["points"])
			for i in range(pts.size()-1):
				var a := project(Vector3(pts[i].x,0,pts[i].y))
				var b := project(Vector3(pts[i+1].x,0,pts[i+1].y))
				var steps := maxi(1,int(a.distance_to(b)/3))
				for step in steps:
					var q := a.lerp(b,float(step)/steps)
					if map_rect.grow(-3).has_point(q):
						draw_circle(q,2,Color(0.53,0.44,0.28))
	draw_rect(map_rect,Color(0.65,0.52,0.32),false,3)
	var rad := campaign.detection_radius() * scale
	draw_circle(project(center), rad, Color(0.7, 0.12, 0.08, 0.17))
	draw_arc(project(center), rad, 0, TAU, 96, Color(0.95, 0.38, 0.23), 2)
	draw_string(ThemeDB.fallback_font, project(center) + Vector2(-30, 0), "CAMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHEAT)
	for tent: Vector3 in campaign.encounter.tent_positions:
		draw_rect(Rect2(project(tent)-Vector2(3,3)*scale,Vector2(6,6)*scale),Color(0.04,0.04,0.04))
	for b in campaign.encounter.enemies:
		if is_instance_valid(b) and b.is_alive() and CampaignUtil.in_view(campaign.player, b.avatar.global_position + Vector3.UP, 60.0):
			draw_circle(project(b.avatar.global_position), 5, Color(0.9, 0.15, 0.08))
	for id in placements:
		var p := project(placements[id])
		draw_circle(p, 11, Color(0.7, 0.25, 0.32) if id == selected else Color(0.35, 0.06, 0.13))
		draw_arc(p, 12, 0, TAU, 24, Color.WHEAT, 1.5)
		draw_string(ThemeDB.fallback_font, p + Vector2(-4, 5), str(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHEAT)
	var cp := project(campaign.player.global_position)
	draw_colored_polygon(PackedVector2Array([cp + Vector2(0,-10),cp + Vector2(8,0),cp + Vector2(0,10),cp + Vector2(-8,0)]), Color.GOLD)
