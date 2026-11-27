extends RefCounted
## Dressing for the existing keep, authored in its original local coordinates.
## MeshKit batches share the castle materials; candles do not create extra lights.

func build(s: Sites, wood: MeshKit, art: MeshKit, stone: MeshKit, glow: MeshKit) -> void:
	_council(s, wood, art, glow)
	_corridor(s, wood, art, stone, glow)
	_entrance(s, wood, stone)
	# Retain the washstand and define its small washroom with oak privacy screens.
	for z in [-15.25,-11.95]:
		var screen:=MeshInstance3D.new()
		var kit:=MeshKit.new(746)
		kit.add_box(Transform3D.IDENTITY,Vector3(2.3,2.2,0.12),s.DARK_OAK)
		screen.mesh=kit.to_mesh(s.CASTLE_PROPS_MAT)
		s.castle_keep.add_child(screen)
		screen.position=s.castle_origin+Vector3(-7.9,13.8,z)
		_solid(screen,Vector3.ZERO,Vector3(2.3,2.2,0.12))
	s.story_anchors["commander_spawn"] = {"pos": s.castle_origin + Vector3(-5.4, 12.85, -12.0), "yaw": PI}
	s.story_anchors["hall_reveal"] = s.castle_origin + Vector3(14.2, 0.55, -4.9)
	s.story_anchors["castle_exit"] = s.castle_origin + Vector3(8, 0.55, 13)

func _council(s: Sites, wood: MeshKit, art: MeshKit, glow: MeshKit) -> void:
	# Paired seats along the sides face the central aisle. Each has its own panel.
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var x := 8.0 + side * 6.0
			var z := -10.5 - i * 4.0
			var yaw := PI * 0.5 * side
			var at := Vector3(x, 0.55, z)
			var seat := MeshKit.new(520 + i)
			s._castle_chair(seat, Vector3.ZERO, yaw)
			# A taller council chair, with arms and red upholstery.
			var b := Basis(Vector3.UP, yaw)
			seat.add_box(Transform3D(b, b * Vector3(0, 0.52, 0)), Vector3(0.6, 0.09, 0.58), s.CRIMSON)
			for arm in [-0.36, 0.36]:
				seat.add_box(Transform3D(b, b * Vector3(arm, 0.76, 0)), Vector3(0.09, 0.09, 0.72), s.DARK_OAK)
			var node := MeshInstance3D.new()
			node.name = "ChiefSeat_%s_%d" % ["West" if side < 0 else "East", i]
			node.mesh = seat.to_mesh(s.CASTLE_PROPS_MAT)
			node.position = s.castle_origin + at
			node.scale = Vector3(1.45, 1.45, 1.45)
			s.castle_keep.add_child(node)
			_solid(node, Vector3(0, 0.5, 0), Vector3(0.8, 1, 0.85))
			var portrait := MeshKit.new(600 + i)
			s._castle_painting(portrait, Vector3.ZERO, 2.15, 2.65,
				[Color(0.18, 0.10, 0.08), Color(0.09, 0.16, 0.17), Color(0.18, 0.17, 0.09)][i], 2, -side * PI * 0.5)
			var panel := MeshInstance3D.new()
			panel.name = "ChiefPortrait_%s_%d" % ["West" if side < 0 else "East", i]
			panel.mesh = portrait.to_mesh(s.CASTLE_PROPS_MAT)
			panel.position = s.castle_origin + Vector3(8 + side * 8.35, 4.1, z)
			s.castle_keep.add_child(panel)
			# Heraldic bars distinguish the six placeholder oil panels.
			if i == 0:
				s._castle_banner_hanging(wood, Vector3(x, 8.7, -21.8), Vector3(0, 0, 1), 1.0, 3.0)
	# Central crown above the original throne; restrained iron and gilt ornament.
	for i in 5:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(7.5 + i * 0.25, 3.6 + (0.18 if i % 2 == 0 else 0), -21.95)), Vector3(0.13, 0.42, 0.16), s.GOLD_TRIM)
	# A wide open iron hoop chandelier around the retained central lamp.
	var center := Vector3(8, 8.5, -11)
	for i in 16:
		var a := TAU * i / 16.0
		var b := TAU * (i + 1) / 16.0
		var p := center + Vector3(cos(a), 0, sin(a)) * 2.5
		var q := center + Vector3(cos(b), 0, sin(b)) * 2.5
		wood.add_cylinder(Transform3D(Landmark.basis_y(q - p), p), 0.075, 0.075, p.distance_to(q), 6, s.FORGED)
		s._castle_candle(wood, glow, p + Vector3.UP * 0.08)
		if i % 4 == 0:
			var top := Vector3(8, 11.7, -11)
			wood.add_cylinder(Transform3D(Landmark.basis_y(top - p), p), 0.035, 0.035, p.distance_to(top), 5, s.FORGED)

func _corridor(s: Sites, wood: MeshKit, art: MeshKit, stone: MeshKit, glow: MeshKit) -> void:
	# Close the old upper facade opening: the terrace has its existing stair route.
	s.piece("wall", Vector3(8, 12.7, 7), 0, Vector3(8, 8.7, 1.8), 0, false, {"stone_material": s.CASTLE_ASHLAR})
	for i in 4:
		var x := 2.0 + i * 4.0
		var at := Vector3(x, 12.7, 5.95)
		var panel := Node3D.new()
		panel.name = "LockedChiefChamber_%d" % i
		panel.position = s.castle_origin + at
		s.castle_keep.add_child(panel)
		var k := MeshKit.new(710 + i)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 0)), Vector3(2.0, 3.6, 0.22), s.DARK_OAK)
		for y in [0.6, 2.8]:
			k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, y, -0.15)), Vector3(1.9, 0.13, 0.08), s.FORGED)
		for dx in [-1.16, 1.16]:
			k.add_box(Transform3D(Basis.IDENTITY, Vector3(dx, 1.95, 0)), Vector3(0.3, 3.9, 0.5), s.DRESSED)
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 3.95, 0)), Vector3(2.6, 0.32, 0.5), s.DRESSED)
		var mesh := MeshInstance3D.new()
		mesh.mesh = k.to_mesh(s.CASTLE_PROPS_MAT)
		panel.add_child(mesh)
		_solid(panel, Vector3(0, 1.8, 0), Vector3(2.2, 3.6, 0.3))
		s._castle_banner_hanging(wood, at + Vector3(1.55, 4.9, -0.15), Vector3(0, 0, -1), 0.65, 1.8,
			[Color(0.3, 0.12, 0.12), Color(0.17, 0.24, 0.25), Color(0.34, 0.29, 0.14), Color(0.18, 0.24, 0.15)][i])
		s._castle_sconce(wood, glow, at + Vector3(-1.55, 2.8, -0.3), Vector3(0, 0, -1))
	# The former key-locked map room is a private chamber, with no interaction.
	s.piece("block", Vector3(17, 12.7, -14.6), 0, Vector3(0.45, 6.0, 4), 0, false, {"color": s.DARK_OAK, "stone_material": s.CASTLE_PROPS_MAT})
	# The bedroom's actual swinging door; interaction itself is the opening condition.
	var door := Node3D.new()
	door.name = "CommanderBedroomDoor"
	door.position = s.castle_origin + Vector3(-4.1, 12.7, -7)
	s.castle_keep.add_child(door)
	s.bedroom_door = door
	var k := MeshKit.new(744)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.9, 1.8, 0)), Vector3(1.8, 3.6, 0.2), s.DARK_OAK)
	for y in [0.65, 2.8]:
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0.9, y, -0.13)), Vector3(1.65, 0.12, 0.08), s.FORGED)
	var mesh := MeshInstance3D.new()
	mesh.mesh = k.to_mesh(s.CASTLE_PROPS_MAT)
	door.add_child(mesh)
	_solid(door, Vector3(0.9, 1.8, 0), Vector3(1.8, 3.6, 0.23))
	var it := Interactable.new()
	it.name = "OpenBedroomDoor"
	it.prompt_text = "Open the chamber door"
	it.position = Vector3(1.3, 1.5, -0.35)
	it.max_view_angle = 80
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.65
	cs.shape = shape
	it.add_child(cs)
	door.add_child(it)
	it.interacted.connect(func(_by: Node) -> void:
		it.enabled = false
		it.set_deferred("monitorable", false)
		door.set_meta("opened", true)
		door.create_tween().tween_property(door, "rotation:y", -PI * 0.5, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT))
	# A visible barred balcony door prevents bypassing the bedroom's opening condition.
	# It opens with the chamber latch, keeping the original balcony accessible afterwards.
	var balcony := Node3D.new()
	balcony.name = "BedroomBalconyDoor"
	balcony.position = s.castle_origin + Vector3(-10, 12.7, -16.05)
	balcony.rotation.y = PI * 0.5
	s.castle_keep.add_child(balcony)
	var balcony_kit := MeshKit.new(745)
	for x in [0.04, 1.86]:
		balcony_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.8, 0)), Vector3(0.12, 3.6, 0.15), s.DARK_OAK)
	for y in [0.08, 1.2, 3.52]:
		balcony_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.95, y, 0)), Vector3(1.9, 0.14, 0.15), s.DARK_OAK)
	for i in 8:
		balcony_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0.2 + i * 0.21, 1.8, 0)), Vector3(0.045, 3.5, 0.07), s.FORGED)
	var balcony_mesh := MeshInstance3D.new()
	balcony_mesh.mesh = balcony_kit.to_mesh(s.CASTLE_PROPS_MAT)
	balcony.add_child(balcony_mesh)
	_solid(balcony, Vector3(0.95, 1.8, 0), Vector3(1.9, 3.6, 0.2))
	it.interacted.connect(func(_by: Node) -> void:
		balcony.create_tween().tween_property(balcony, "rotation:y", PI, 0.85))
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(7.5, 12.76, -1.4)), Vector3(16, 0.04, 2.0), s.CRIMSON)
	# Warm, shadow-free fill shared by the entire junction.
	s._castle_light("RoyalLandingDaylight", Vector3(9, 17.2, -1), Color(1, 0.88, 0.69), 1.2, 13, false)

func _entrance(s: Sites, wood: MeshKit, stone: MeshKit) -> void:
	s._castle_door(wood, Vector3(8, 0.55, 7), Vector3(0, 0, 1), 8, 6.8, 8.5, true, 1.0)
	s._castle_shield(wood, Vector3(8, 9.6, 8.4), Vector3(0, 0, 1), false)
	# Broad shallow stair joins the raised floor to the courtyard.
	s.piece("stairs", Vector3(8, 0, 10.5), 180, Vector3(8, 0.55, 3.5), 0, false, {"stone_material": s.CASTLE_ASHLAR})
	# Hand-laid quoin courses add shallow irregularity without noisy wall displacement.
	for x in [-10.0, 26.0]:
		for row in 18:
			var y := 0.35 + row * 1.15
			stone.add_box(Transform3D(Basis.IDENTITY, Vector3(x, y, 7.95)), Vector3(1.5 + (row % 2) * 0.25, 1.06, 0.22 + (row % 3) * 0.025), s.shade(s.DRESSED, 0.88 + (row % 4) * 0.035))

func _solid(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	body.add_child(cs)
	parent.add_child(body)
