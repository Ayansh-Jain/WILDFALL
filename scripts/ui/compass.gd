class_name CompassHud
extends CanvasLayer
## A thin heading strip: north, the marked destination or mission, and discovered
## places nearby. Nothing floats over the landscape. Also the "follow the wind"
## guide (V): a short gust that blows toward where the Commander is headed.

const WIDTH := 440.0
const SPAN := PI * 0.75  ## half-angle shown
const PLACE_RANGE := 160.0
const GUST_SECONDS := 3.5
## The ambient wind DayNightCycle sets; restored after a gust.
const CALM := [Vector2(0.85, 0.52), 1.0, 1.35, 0.42]

var exploration: ExplorationDirector
var _strip: Control
var _gust: CPUParticles3D
var _gust_left := 0.0
var _redraw := 0.0


func setup(e: ExplorationDirector) -> void:
	exploration = e
	layer = 8
	_strip = Control.new()
	_strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_strip.offset_left = -WIDTH * 0.5
	_strip.offset_right = WIDTH * 0.5
	_strip.offset_top = 8
	_strip.offset_bottom = 56
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.draw.connect(_draw_strip)
	add_child(_strip)


## Compass bearing of a world direction: 0 = north (-z), +PI/2 = east (+x).
static func bearing(direction: Vector3) -> float:
	return atan2(direction.x, -direction.z)


func heading() -> float:
	var camera := get_viewport().get_camera_3d()
	return bearing(-camera.global_basis.z) if camera else bearing(exploration.player.forward())


func _process(delta: float) -> void:
	if exploration == null:
		return
	var p := exploration.player
	_strip.visible = p.controls_enabled and not p.is_defeated and not (exploration.story and exploration.story.in_dialogue)
	_redraw -= delta
	if _redraw <= 0.0 and _strip.visible:
		_redraw = 0.05
		_strip.queue_redraw()
	if _gust_left > 0.0:
		_gust_left -= delta
		if is_instance_valid(_gust):
			_gust.global_position = p.global_position + Vector3.UP * 1.6
		if _gust_left <= 0.0:
			_calm()


func _x(angle: float, from: float) -> float:
	var rel := wrapf(angle - from, -PI, PI)
	return NAN if absf(rel) > SPAN else WIDTH * 0.5 + rel / SPAN * WIDTH * 0.5


func _draw_strip() -> void:
	var from := heading()
	var font := ThemeDB.fallback_font
	var here := exploration.player.global_position
	_strip.draw_line(Vector2(0, 20), Vector2(WIDTH, 20), Color(0.9, 0.86, 0.72, 0.35), 1.0)
	for pair in [["N", 0.0], ["E", PI * 0.5], ["S", PI], ["W", -PI * 0.5]]:
		var x := _x(pair[1], from)
		if not is_nan(x):
			_text(font, Vector2(x - 6, 17), pair[0], 15, Color(1.0, 0.92, 0.7) if pair[0] == "N" else Color(0.85, 0.85, 0.8, 0.8))
	var centred := ""
	for id in exploration.discovered:
		var p := exploration.db.travel_point(id)
		var d := Vector3(p.x - here.x, 0, p.y - here.z)
		if d.length() > PLACE_RANGE or d.length() < 12.0:
			continue
		var x := _x(bearing(d), from)
		if is_nan(x):
			continue
		_strip.draw_circle(Vector2(x, 20), 2.5, Color(0.75, 0.85, 0.8, 0.9))
		if absf(x - WIDTH * 0.5) < 22.0:
			centred = "%s  %d m" % [exploration.db.location(id)["name"], int(d.length())]
	var target := exploration.guidance_target()
	if target != Vector3.INF:
		var d := Vector3(target.x - here.x, 0, target.z - here.z)
		var rel := wrapf(bearing(d) - from, -PI, PI)
		var x := WIDTH * 0.5 + clampf(rel / SPAN, -1.0, 1.0) * WIDTH * 0.5
		var colour := Color(0.95, 0.76, 0.3) if exploration.waypoint != Vector3.INF else Color(0.85, 0.35, 0.3)
		_strip.draw_colored_polygon(PackedVector2Array([Vector2(x, 13), Vector2(x + 6, 20), Vector2(x, 27), Vector2(x - 6, 20)]), colour)
		if centred == "" and absf(x - WIDTH * 0.5) < 30.0:
			centred = "%d m" % int(d.length())
	if centred != "":
		var w := font.get_string_size(centred, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_text(font, Vector2((WIDTH - w) * 0.5, 42), centred, 14, Color(0.92, 0.9, 0.82))


func _text(font: Font, at: Vector2, text: String, size: int, colour: Color) -> void:
	_strip.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.75))
	_strip.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("guide_wind") and not event.is_echo():
		get_viewport().set_input_as_handled()
		guide()


## Blows a gust toward the destination. False if there is none.
func guide() -> bool:
	var p := exploration.player
	var target := exploration.guidance_target()
	if target == Vector3.INF:
		exploration.hud.toast("Mark a destination on the map (%s) and the wind will find it." % Settings.get_binding_text("world_map"), 3.0)
		return false
	if not p.controls_enabled:
		return false
	var d := Vector3(target.x - p.global_position.x, 0, target.z - p.global_position.z).normalized()
	if _gust == null:
		_gust = CPUParticles3D.new()
		# Thin streaks laid along their own motion.
		var streak := BoxMesh.new()
		streak.size = Vector3(0.008, 0.45, 0.008)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.95, 0.78, 0.4)
		streak.material = m
		_gust.mesh = streak
		_gust.particle_flag_align_y = true
		_gust.amount = 45
		_gust.lifetime = 1.6
		_gust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_gust.emission_box_extents = Vector3(5.0, 1.4, 5.0)
		_gust.gravity = Vector3.ZERO
		_gust.spread = 6.0
		_gust.initial_velocity_min = 6.0
		_gust.initial_velocity_max = 10.0
		_gust.local_coords = false
		exploration.world.add_child(_gust)
	_gust.global_position = p.global_position + Vector3.UP * 1.6
	_gust.direction = d
	_gust.emitting = true
	_gust_left = GUST_SECONDS
	Atmosphere.push_wind_to_materials(Vector2(d.x, d.z), 1.8, 2.2, 0.5)
	return true


func gusting() -> bool:
	return _gust_left > 0.0


func _calm() -> void:
	_gust_left = 0.0
	if is_instance_valid(_gust):
		_gust.emitting = false
	Atmosphere.push_wind_to_materials(CALM[0], CALM[1], CALM[2], CALM[3])


func _exit_tree() -> void:
	if _gust_left > 0.0:
		_calm()
	if is_instance_valid(_gust):
		_gust.queue_free()
