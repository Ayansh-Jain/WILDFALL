extends Node3D
## A hand operated medieval hoist connecting the castle yard to its undercroft.
## The open timber cage carries characters while the counterweight rises.

const STONE_MAT := preload("res://assets/materials/stone.tres")
const PROPS_MAT := preload("res://assets/materials/props.tres")
const WOOD := Color(0.27, 0.19, 0.12)
const DARK_WOOD := Color(0.16, 0.12, 0.085)
const IRON := Color(0.09, 0.105, 0.11)

var depth := 12.0
var carriage: AnimatableBody3D
var _counterweight: Node3D
var _ropes: Array[MeshInstance3D] = []
var _moving := false
var _target_y := 0.0
var _top_call: Interactable
var _bottom_call: Interactable
var _car_control: Interactable
var _winch: Node3D
var _safety_grate: Node3D
var _grate_collision: CollisionShape3D


func build(p_depth: float) -> void:
	depth = maxf(p_depth, 8.0)
	_target_y = 0.0
	_build_shaft()
	_build_carriage()
	_build_boarding_sills()
	_build_hoist()
	_build_controls()
	_build_safety_grate()
	_add_lamp(Vector3(0, 2.8, 3.0), Color(1.0, 0.57, 0.27), 1.35, 10.0)
	_add_lamp(Vector3(0, -depth + 2.6, 3.1), Color(0.92, 0.54, 0.28), 1.9, 13.0)


func _build_shaft() -> void:
	var kit := MeshKit.new(6401, 0.055)
	# Rough stone cheeks keep the travel lane enclosed from the surface grate to
	# the crypt. Deep mortar bands make the shaft read as cut masonry.
	var wall_y := -depth * 0.5
	var wall_h := depth + 0.4
	for x in [-2.48, 2.48]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, wall_y, 0)), Vector3(0.62, wall_h, 5.25), Color(0.29, 0.285, 0.27))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, wall_y, -2.48)), Vector3(5.25, wall_h, 0.62), Color(0.3, 0.29, 0.27))
	# A low landing doorway at each end opens into the yard and undercroft; the
	# uninterrupted middle course keeps the rest of the shaft enclosed.
	for x in [-2.15, 2.15]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, wall_y, 2.48)), Vector3(1.0, wall_h, 0.62), Color(0.3, 0.29, 0.27))
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -depth * 0.5, 2.48)), Vector3(2.05, maxf(0.5, depth - 6.0), 0.62), Color(0.28, 0.275, 0.26))
	for y in range(0, int(depth), 2):
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -float(y) - 0.7, -2.83)), Vector3(5.1, 0.12, 0.12), Color(0.2, 0.21, 0.2))
		for x in [-2.83, 2.83]:
			kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, -float(y) - 0.7, 0)), Vector3(0.12, 0.12, 5.1), Color(0.2, 0.21, 0.2))
	# Heavy cap stones frame the mouth and protect the opening when the cage is
	# at the top landing.
	for x in [-2.7, 2.7]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.1, 0)), Vector3(1.0, 0.42, 6.2), Color(0.34, 0.33, 0.31))
	for z in [-2.7, 2.7]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, z)), Vector3(4.5, 0.42, 1.0), Color(0.34, 0.33, 0.31))
	_emit(self, kit, STONE_MAT, true)
	var body := StaticBody3D.new()
	body.name = "HoistShaftWalls"
	body.collision_layer = Layers.WORLD
	add_child(body)
	for x in [-2.48, 2.48]:
		_add_box_collision(body, Vector3(x, wall_y, 0), Vector3(0.62, wall_h, 5.25))
	_add_box_collision(body, Vector3(0, wall_y, -2.48), Vector3(5.25, wall_h, 0.62))
	for x in [-2.15, 2.15]:
		_add_box_collision(body, Vector3(x, wall_y, 2.48), Vector3(1.0, wall_h, 0.62))
	_add_box_collision(body, Vector3(0, -depth * 0.5, 2.48), Vector3(2.05, maxf(0.5, depth - 6.0), 0.62))


func _build_carriage() -> void:
	carriage = AnimatableBody3D.new()
	carriage.name = "TimberLiftCage"
	carriage.sync_to_physics = true
	carriage.position.y = 0.0
	add_child(carriage)
	var kit := MeshKit.new(6402, 0.045)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.02, 0)), Vector3(3.05, 0.48, 3.05), DARK_WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.235, 0)), Vector3(2.9, 0.055, 2.9), WOOD)
	# Recessed deck planks, rim beams, forged corner shoes and a clear boarding side.
	for i in 8:
		var z := -1.35 + float(i) * 0.38
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.28, z)), Vector3(2.82, 0.045, 0.34), Color(0.38, 0.28, 0.17))
	for x in [-1.38, 1.38]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.48, 0)), Vector3(0.2, 0.42, 2.9), DARK_WOOD)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.17, 0)), Vector3(0.2, 1.8, 0.2), WOOD)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 2.02, 0)), Vector3(0.28, 0.16, 0.28), IRON)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.48, -1.38)), Vector3(2.9, 0.42, 0.2), DARK_WOOD)
	for x in [-1.0, 1.0]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.48, 1.38)), Vector3(1.05, 0.42, 0.2), DARK_WOOD)
	# The front rail is waist high and opens in the middle like an old freight cage.
	for x in [-1.1, 1.1]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.17, 1.38)), Vector3(0.18, 1.8, 0.18), WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 1.98, 1.38)), Vector3(2.9, 0.18, 0.2), WOOD)
	for x in [-1.47, 1.47]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.0, 0)), Vector3(0.12, 0.64, 3.1), IRON)
	_emit(carriage, kit, PROPS_MAT, true)
	_add_box_collision(carriage, Vector3(0, -0.02, 0), Vector3(3.05, 0.48, 3.05))
	# Keep the in-cage control close to the player and inside the rail footprint;
	# its former corner position was awkward to target from the lift floor.
	_car_control = _make_interactable(carriage, Vector3(0.35, 1.28, 0.45), "Ride to the undercroft", 1.0)
	_car_control.interacted.connect(_on_car_control)
	_add_lever_mesh(carriage, Vector3(0.35, 1.28, 0.62), 0.82)


func _build_boarding_sills() -> void:
	# Bridge the old gap from each landing to the cage; the shaft and all
	# existing lift geometry retain their original transforms.
	var kit := MeshKit.new(6408, 0.025)
	var body := StaticBody3D.new()
	body.name = "BoardingSills"
	body.collision_layer = Layers.WORLD
	add_child(body)
	for y in [0.0, -depth]:
		var center := Vector3(0, y + 0.1, 2.65)
		var size := Vector3(2.0, 0.24, 2.2)
		kit.add_box(Transform3D(Basis.IDENTITY, center), size, WOOD)
		_add_box_collision(body, center, size)
	_emit(self, kit, PROPS_MAT, true)


func _build_hoist() -> void:
	var kit := MeshKit.new(6403, 0.025)
	# Oak portal and two capstan drums at the surface.
	for x in [-3.65, 3.65]:
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 4.45, 0)), Vector3(0.62, 8.9, 0.72), DARK_WOOD)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 8.95, 0)), Vector3(0.92, 0.35, 1.0), WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 8.55, 0)), Vector3(7.9, 0.72, 0.86), WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 8.13, 0)), Vector3(7.1, 0.18, 0.58), Color(0.41, 0.29, 0.17))
	# Great axle and broad iron-rimmed winding wheel on the right hand post.
	kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(3.65, 6.35, 0)), 0.28, 0.28, 1.5, 10, DARK_WOOD)
	kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(5.25, 6.35, 0)), 0.095, 0.095, 1.0, 8, DARK_WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, Vector3(5.72, 6.35, 0)), Vector3(0.18, 0.18, 0.18), WOOD)
	# Chain guides run to the cage and the counterweight. Their lengths follow the lift.
	for x in [-1.08, 1.08]:
		for z in [-1.08, 1.08]:
			var rope_mesh := CylinderMesh.new()
			rope_mesh.top_radius = 0.045
			rope_mesh.bottom_radius = 0.055
			rope_mesh.radial_segments = 6
			rope_mesh.height = 7.6
			var rope := MeshInstance3D.new()
			rope.mesh = rope_mesh
			rope.position = Vector3(x, 4.05, z)
			_ropes.append(rope)
			add_child(rope)
	# Counterweight slides in its own open guide below the west end of the axle.
	_counterweight = Node3D.new()
	_counterweight.name = "StoneCounterweight"
	_counterweight.position = Vector3(1.82, -depth + 1.8, -1.82)
	var weight_kit := MeshKit.new(6404, 0.04)
	weight_kit.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(0.42, 1.6, 0.42), Color(0.25, 0.25, 0.24))
	for y in [-0.66, 0.66]:
		weight_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, y, 0)), Vector3(0.54, 0.12, 0.54), IRON)
	_emit(_counterweight, weight_kit, PROPS_MAT, true)
	add_child(_counterweight)
	_winch = Node3D.new()
	_winch.position = Vector3(4.7, 6.35, 0)
	add_child(_winch)
	var wheel := MeshInstance3D.new()
	wheel.name = "WheelRotation"
	var wheel_kit := MeshKit.new(6405)
	wheel_kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), 1.22, 1.22, 0.18, 12, WOOD)
	wheel_kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.04, 0, 0)), 1.08, 1.08, 0.12, 12, IRON)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var spoke_center := Vector3(0.0, cos(angle) * 0.55, sin(angle) * 0.55)
		wheel_kit.add_box(Transform3D(Basis(Vector3.RIGHT, angle), spoke_center), Vector3(0.16, 1.15, 0.16), DARK_WOOD)
		var tooth_center := Vector3(0.0, cos(angle) * 1.25, sin(angle) * 1.25)
		wheel_kit.add_box(Transform3D(Basis(Vector3.RIGHT, angle), tooth_center), Vector3(0.22, 0.2, 0.18), IRON)
	wheel_kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), 0.24, 0.24, 0.34, 10, DARK_WOOD)
	wheel.mesh = wheel_kit.to_mesh(PROPS_MAT)
	_winch.add_child(wheel)
	# Lantern under the axle lights the well throat while keeping the world scale modest.
	_add_lamp(Vector3(0, 7.2, 0.8), Color(1.0, 0.61, 0.3), 1.25, 11.0)


func _build_controls() -> void:
	var upper_control := Vector3(3.0, 1.45, 1.0)
	var lower_control := Vector3(3.0, -depth + 1.65, 1.0)
	_top_call = _make_interactable(self, upper_control, "Call the lift", 0.7)
	_bottom_call = _make_interactable(self, lower_control, "Call the lift", 0.7)
	_top_call.interacted.connect(_on_top_call)
	_bottom_call.interacted.connect(_on_bottom_call)
	_add_lever_mesh(self, upper_control, 1.0)
	_add_lever_mesh(self, lower_control, 1.0)
	_add_label(Vector3(3.05, 2.2, 1.0), "UPPER LANDING", Color(0.73, 0.62, 0.43))
	_add_label(Vector3(3.05, -depth + 2.2, 1.0), "THE UNDERCROFT", Color(0.62, 0.72, 0.6))
	_refresh_controls()


func _make_interactable(parent: Node3D, at: Vector3, prompt: String, radius: float) -> Interactable:
	var area := Interactable.new()
	area.prompt_text = prompt
	area.focus_offset = Vector3(0, 0.08, 0)
	area.max_view_angle = 72.0
	area.position = at
	var shape := SphereShape3D.new()
	shape.radius = radius
	var collision := CollisionShape3D.new()
	collision.shape = shape
	area.add_child(collision)
	parent.add_child(area)
	return area


func _add_lever_mesh(parent: Node3D, at: Vector3, scale: float) -> void:
	var kit := MeshKit.new(6408, 0.02)
	kit.add_box(Transform3D(Basis.IDENTITY, at + Vector3(0, 0, -0.13 * scale)),
		Vector3(0.62, 0.86, 0.16) * scale, DARK_WOOD)
	kit.add_box(Transform3D(Basis.IDENTITY, at + Vector3(0, 0, -0.035 * scale)),
		Vector3(0.48, 0.68, 0.055) * scale, Color(0.34, 0.25, 0.16))
	for y in [-0.28, 0.28]:
		kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at + Vector3(0.22 * scale, y * scale, -0.005 * scale)),
			0.035 * scale, 0.035 * scale, 0.08 * scale, 8, IRON)
	kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), at + Vector3(0, 0.02 * scale, 0.08 * scale)),
		0.075 * scale, 0.075 * scale, 0.18 * scale, 8, Color(0.58, 0.43, 0.22))
	kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, -0.5), at + Vector3(0, 0.04 * scale, 0.16 * scale)),
		0.045 * scale, 0.035 * scale, 0.5 * scale, 8, IRON)
	kit.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.11 * scale),
		at + Vector3(0, 0.48 * scale, 0.39 * scale)), 1.0, Color(0.65, 0.49, 0.24), false, 0.0)
	_emit(parent, kit, PROPS_MAT, true)


func _on_top_call(_by: Node) -> void:
	if not _moving and carriage.position.y < -0.2:
		_move_to(0.0)


func _on_bottom_call(_by: Node) -> void:
	if not _moving and carriage.position.y > -depth + 0.2:
		_move_to(-depth)


func _on_car_control(_by: Node) -> void:
	if _moving:
		return
	var destination: float = 0.0 if carriage.position.y <= -depth * 0.5 else -depth
	_move_to(destination)


func _move_to(y: float) -> void:
	if _moving:
		return
	_target_y = clampf(y, -depth, 0.0)
	_moving = true
	_top_call.enabled = false
	_bottom_call.enabled = false
	_car_control.enabled = false


func _physics_process(delta: float) -> void:
	if not carriage:
		return
	if _moving:
		var previous_y: float = carriage.position.y
		carriage.position.y = move_toward(previous_y, _target_y, 2.15 * delta)
		_counterweight.position.y = -depth + 1.8 - carriage.position.y
		_winch.rotation.z += delta * 2.9
		_update_rope_lengths()
		_update_safety_grate()
		if absf(carriage.position.y - _target_y) < 0.01:
			carriage.position.y = _target_y
			_moving = false
			_refresh_controls()
			if _winch:
				_winch.rotation.z = 0.0
			_update_safety_grate()


func _update_rope_lengths() -> void:
	var top_y := 7.6
	var rope_length := maxf(0.2, top_y - carriage.position.y - 0.4)
	for rope in _ropes:
		var mesh := rope.mesh as CylinderMesh
		mesh.height = rope_length
		rope.position.y = carriage.position.y + 0.45 + rope_length * 0.5


func _refresh_controls() -> void:
	if not carriage or not _top_call or not _bottom_call or not _car_control:
		return
	var at_top := absf(carriage.position.y) <= 0.15
	var at_bottom := absf(carriage.position.y + depth) <= 0.15
	_top_call.enabled = not _moving and not at_top
	_bottom_call.enabled = not _moving and not at_bottom
	_car_control.enabled = not _moving
	_top_call.prompt_text = "Call the lift up to the upper yard"
	_bottom_call.prompt_text = "Call the lift down to the undercroft"
	_car_control.prompt_text = "Ride to the undercroft" if at_top else "Ride to the upper yard"


func _build_safety_grate() -> void:
	_safety_grate = Node3D.new()
	_safety_grate.name = "IronPitCover"
	_safety_grate.position.y = 0.48
	var kit := MeshKit.new(6407)
	for i in 7:
		var offset := -1.65 + float(i) * 0.55
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(offset, 0, 0)), Vector3(0.1, 0.12, 3.55), IRON)
		kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0, offset)), Vector3(3.55, 0.12, 0.1), IRON)
	_emit(_safety_grate, kit, PROPS_MAT, false)
	var body := StaticBody3D.new()
	body.name = "PitCoverCollision"
	body.collision_layer = Layers.WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.55, 0.18, 3.55)
	_grate_collision = CollisionShape3D.new()
	_grate_collision.shape = shape
	body.add_child(_grate_collision)
	_safety_grate.add_child(body)
	add_child(_safety_grate)
	_update_safety_grate()


func _update_safety_grate() -> void:
	if not _safety_grate or not carriage:
		return
	var closed := carriage.position.y < -1.1
	_safety_grate.visible = closed
	_grate_collision.set_deferred("disabled", not closed)


func _add_lamp(at: Vector3, tint: Color, energy: float, reach: float) -> void:
	var mount := MeshKit.new(6406, 0.025)
	_mount_torch(mount, at, tint)
	_emit(self, mount, PROPS_MAT, false)
	var light := OmniLight3D.new()
	light.position = at + Vector3(0, 0.2, 0)
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.distance_fade_enabled = true
	light.distance_fade_begin = 52.0
	light.distance_fade_length = 14.0
	add_child(light)


func _mount_torch(kit: MeshKit, at: Vector3, tint: Color) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, at + Vector3(0, -0.2, -0.22)), Vector3(0.42, 0.18, 0.38), DARK_WOOD)
	kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, -0.6, 0)), 0.1, 0.08, 0.48, 6, IRON)
	kit.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, 0.8, 0.5)), at), 0.28, tint, false, 0.0)


func _add_label(at: Vector3, text: String, tint: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 42
	label.pixel_size = 0.009
	label.modulate = tint
	label.outline_size = 8
	label.outline_modulate = Color(0.035, 0.03, 0.025)
	add_child(label)


func _add_box_collision(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	parent.add_child(collision)


func _emit(parent: Node3D, kit: MeshKit, material: Material, shadows: bool) -> void:
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(material)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


