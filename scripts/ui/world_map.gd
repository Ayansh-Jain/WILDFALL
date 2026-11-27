class_name WorldMap
extends CanvasLayer
## The kingdom map (Tab). The ground is painted once from TerrainData (no second
## camera, no extra loading); roads, rivers and the wall are the same polylines the
## world is built from; only discovered places are named. Wheel zooms, drag pans,
## click marks a destination, right click clears it.

const EXTENT := 306.0  ## metres from the centre to the map edge
const PIXELS := 306
const MAX_ZOOM := 4.0
const ICONS := {"settlement": Color(0.93, 0.84, 0.55), "royal": Color(0.95, 0.72, 0.3), "bridge": Color(0.75, 0.6, 0.4),
	"crossing": Color(0.55, 0.75, 0.85), "viewpoint": Color(0.7, 0.9, 0.75), "pass": Color(0.8, 0.82, 0.9),
	"ruins": Color(0.72, 0.72, 0.68), "memorial": Color(0.85, 0.85, 0.95), "camp": Color(0.9, 0.6, 0.35),
	"cave": Color(0.65, 0.6, 0.7), "forest": Color(0.5, 0.75, 0.45), "defence": Color(0.9, 0.5, 0.4),
	"battlefield": Color(0.85, 0.4, 0.4)}

var exploration: ExplorationDirector
var zoom := 1.0
var centre := Vector2.ZERO  ## world [x, z] at the middle of the view
var _view: Control
var _texture: ImageTexture
var _drag := 0.0
var _mouse_before := Input.MOUSE_MODE_CAPTURED


func setup(e: ExplorationDirector) -> void:
	exploration = e
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 1.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_draw_map)
	_view.gui_input.connect(_on_gui)
	add_child(_view)


func is_open() -> bool:
	return visible


func open() -> bool:
	var p := exploration.player
	if visible or not p.controls_enabled or p.is_defeated or get_tree().paused \
			or (exploration.story and exploration.story.in_dialogue):
		return false
	if _texture == null:
		_texture = ImageTexture.create_from_image(paint(exploration.world))
	zoom = 1.0
	centre = Vector2.ZERO
	visible = true
	get_tree().paused = true
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_view.queue_redraw()
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_before


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("world_map") and not event.is_echo():
		if visible:
			close()
		elif not open():
			return
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


# --- coordinates -----------------------------------------------------------------------------

## The square on screen that shows the whole kingdom at zoom 1.
func map_rect() -> Rect2:
	var size := _view.size
	var side := minf(size.x - 60.0, size.y - 90.0)
	return Rect2((size.x - side) * 0.5, 46.0, side, side)


func scale_px() -> float:
	return map_rect().size.x / (EXTENT * 2.0) * zoom


func world_to_map(p: Vector3) -> Vector2:
	return map_rect().get_center() + (Vector2(p.x, p.z) - centre) * scale_px()


func map_to_world(at: Vector2) -> Vector3:
	var w := (at - map_rect().get_center()) / scale_px() + centre
	return Vector3(w.x, exploration.world.terrain_height(w.x, w.y), w.y)


func set_zoom(value: float, around := Vector2.INF) -> void:
	var anchor := map_to_world(around) if around != Vector2.INF else Vector3.INF
	zoom = clampf(value, 1.0, MAX_ZOOM)
	if anchor != Vector3.INF:
		centre = Vector2(anchor.x, anchor.z) - (around - map_rect().get_center()) / scale_px()
	_clamp_centre()
	_view.queue_redraw()


func _clamp_centre() -> void:
	var limit := EXTENT * (1.0 - 1.0 / zoom)
	centre = centre.clamp(Vector2(-limit, -limit), Vector2(limit, limit))


func _on_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			set_zoom(zoom * 1.25, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			set_zoom(zoom / 1.25, event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			exploration.set_waypoint(Vector3.INF)
			_view.queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag = 0.0
			elif _drag < 6.0 and map_rect().has_point(event.position):
				mark(event.position)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_drag += event.relative.length()
		centre -= event.relative / scale_px()
		_clamp_centre()
		_view.queue_redraw()


## Marks a destination at a point on screen.
func mark(at: Vector2) -> void:
	exploration.set_waypoint(map_to_world(at))
	_view.queue_redraw()


# --- painting --------------------------------------------------------------------------------

## Overview of the actual terrain: water, height, forest, relief shading.
static func paint(world: World) -> Image:
	var image := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	var td := world.terrain_data
	var step := EXTENT * 2.0 / PIXELS
	for j in PIXELS:
		var z := -EXTENT + (j + 0.5) * step
		var previous := td.height_at(-EXTENT, z)
		for i in PIXELS:
			var x := -EXTENT + (i + 0.5) * step
			var h := td.height_at(x, z)
			var colour: Color
			if h < world.water_level + 0.05:
				colour = Color(0.22, 0.36, 0.45)
			else:
				colour = Color(0.45, 0.47, 0.28).lerp(Color(0.62, 0.58, 0.5), clampf((h - 8.0) / 22.0, 0.0, 1.0))
				colour = colour.lerp(Color(0.2, 0.31, 0.19), clampf(td.sample(td.forest, x, z), 0.0, 1.0) * 0.75)
				var relief := clampf((h - previous) * 0.22, -0.18, 0.18)
				colour = colour.lightened(relief) if relief > 0.0 else colour.darkened(-relief)
			previous = h
			image.set_pixel(i, j, colour)
	return image


func _draw_map() -> void:
	var rect := map_rect()
	var s := scale_px()
	var font := ThemeDB.fallback_font
	var top_left := world_to_map(Vector3(-EXTENT, 0, -EXTENT))
	var full := Rect2(top_left, Vector2.ONE * EXTENT * 2.0 * s)
	var shown := full.intersection(rect)
	var tex := Vector2(PIXELS, PIXELS)
	_view.draw_texture_rect_region(_texture, shown,
		Rect2((shown.position - full.position) / full.size * tex, shown.size / full.size * tex))
	var layout := exploration.world.layout
	for river in layout.list("rivers"):
		_polyline(WorldLayout.points(river["points"]), Color(0.28, 0.45, 0.56), maxf(2.0, float(river["half_width"]) * 2.0 * s))
	for road in layout.list("trails"):
		_polyline(WorldLayout.points(road["points"]), Color(0.62, 0.5, 0.32, 0.75), 1.5)
	for road in layout.list("roads"):
		_polyline(WorldLayout.points(road["points"]), Color(0.8, 0.68, 0.45), 2.5)
	for bridge in layout.list("bridges"):
		_polyline(PackedVector2Array([WorldLayout.v2(bridge["a"]), WorldLayout.v2(bridge["b"])]), Color(0.45, 0.3, 0.18), 5.0)
	var wall := WorldLayout.points(layout.dict("kingdom").get("wall", {}).get("points", []))
	if wall.size() > 2:
		wall.append(wall[0])
		_polyline(wall, Color(0.2, 0.18, 0.17), 4.0)
	_view.draw_rect(rect, Color(0.65, 0.52, 0.32), false, 2.0)
	for loc in exploration.db.locations():
		if not exploration.is_discovered(String(loc["id"])):
			continue
		var p := LocationDB.xz(loc)
		var at := world_to_map(Vector3(p.x, 0, p.y))
		if not rect.has_point(at):
			continue
		_view.draw_circle(at, 6.0, Color(0, 0, 0, 0.75))
		_view.draw_circle(at, 4.0, ICONS.get(String(loc.get("category", "")), Color.WHITE))
		var major := String(loc.get("category", "")) in ["settlement", "royal", "defence", "battlefield"]
		if major or zoom >= 1.5:
			_label(font, at + Vector2(8, 4), String(loc["name"]), 13)
	var target := exploration.guidance_target()
	if target != Vector3.INF and rect.has_point(world_to_map(target)):
		var at := world_to_map(target)
		_view.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -9), at + Vector2(8, 0), at + Vector2(0, 9), at + Vector2(-8, 0)]),
			Color(0.95, 0.76, 0.3) if exploration.waypoint != Vector3.INF else Color(0.85, 0.3, 0.25))
	var player := exploration.player
	var me := world_to_map(player.global_position)
	if rect.has_point(me):
		var f := player.forward()
		var dir := Vector2(f.x, f.z).normalized()
		var side := Vector2(-dir.y, dir.x)
		_view.draw_colored_polygon(PackedVector2Array([me + dir * 12.0, me - dir * 7.0 + side * 7.0, me - dir * 7.0 - side * 7.0]), Color.WHITE)
	_label(font, Vector2(rect.position.x, 30), "THE KINGDOM          %d of %d places discovered" % [exploration.discovered.size(), exploration.db.locations().size()], 18)
	_label(font, Vector2(rect.position.x, rect.end.y + 24), "N is up    Wheel zoom    Drag pan    Click mark    Right click clear    %s / Esc close" % Settings.get_binding_text("world_map"), 14)


func _polyline(points: PackedVector2Array, colour: Color, width: float) -> void:
	var rect := map_rect()
	for i in points.size() - 1:
		var a := world_to_map(Vector3(points[i].x, 0, points[i].y))
		var b := world_to_map(Vector3(points[i + 1].x, 0, points[i + 1].y))
		var steps := maxi(1, int(a.distance_to(b) / 5.0))
		for k in steps:
			var p := a.lerp(b, float(k) / steps)
			var q := a.lerp(b, float(k + 1) / steps)
			if rect.has_point(p) and rect.has_point(q):
				_view.draw_line(p, q, colour, width)


func _label(font: Font, at: Vector2, text: String, size: int) -> void:
	_view.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	_view.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.93, 0.89, 0.76))
