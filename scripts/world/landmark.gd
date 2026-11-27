class_name Landmark
extends RefCounted
## The Elder Tree: a giant twisted tree on a stepped dais at the centre of the
## map, ringed by rune stones and kneeling statues. Its hanging lantern-orbs use
## a fog-free glow material so the silhouette reads from distant viewpoints.

const STONE_MAT := preload("res://assets/materials/stone.tres")
const PROPS_MAT := preload("res://assets/materials/props.tres")
const BEACON := preload("res://assets/materials/glow_beacon.tres")
const BEACON_TEAL := preload("res://assets/materials/glow_beacon_teal.tres")
const RUNES := preload("res://assets/materials/glow_magic.tres")
const CANOPY_CARDS := preload("res://assets/materials/leaves.tres")

const BARK := Color(0.34, 0.26, 0.21)
const CANOPY := Color(0.13, 0.27, 0.23)
const DAIS := Color(0.38, 0.37, 0.35)


static func basis_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	return Basis(x, y, x.cross(y))


static func build(parent: Node3D, o: Vector3, world: World) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var stone := MeshKit.new(4241, 0.06)
	var bark := MeshKit.new(4242, 0.08)
	var leaf_cards := FoliageMeshes.CardKit.new()
	var warm := MeshKit.new(4244)
	var teal := MeshKit.new(4245)
	var runes := MeshKit.new(4246)
	var body := StaticBody3D.new()
	body.name = "ElderTreeCollision"
	body.collision_layer = Layers.WORLD
	parent.add_child(body)
	var add_shape := func(shape: Shape3D, xform: Transform3D) -> void:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = xform
		body.add_child(cs)

	# Dais: three octagonal tiers, with a gentle frustum for collision.
	for tier in 3:
		var r := 14.0 - tier * 2.5
		var h := 0.4 * (tier + 1)
		stone.add_cylinder(Transform3D(Basis(Vector3.UP, PI / 8.0), o + Vector3(0, -0.8, 0)), r, r, h + 0.8, 8, DAIS * (0.9 + tier * 0.06))
	var pts := PackedVector3Array()
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		pts.append(Vector3(cos(a) * 14.3, -0.8, sin(a) * 14.3))
		pts.append(Vector3(cos(a) * 9.0, 1.2, sin(a) * 9.0))
	var dais := ConvexPolygonShape3D.new()
	dais.points = pts
	add_shape.call(dais, Transform3D(Basis.IDENTITY, o))

	# Trunk: stacked, twisting, tapering segments.
	var pos := o + Vector3(0, 0.8, 0)
	var r := 4.4
	var drift := Vector3.ZERO
	var trunk_points: Array = []
	for i in 7:
		var h := 4.6
		var nr := r * 0.85
		var tilt := Basis(Vector3(cos(i * 1.7), 0, sin(i * 1.7)), 0.05)
		bark.add_cylinder(Transform3D(tilt * Basis(Vector3.UP, i * 0.45), pos), r, nr, h + 0.4, 11, BARK * rng.randf_range(0.9, 1.1))
		trunk_points.append([pos, r])
		drift = Vector3(sin(i * 1.3) * 0.45, 0, cos(i * 1.1) * 0.45)
		pos += tilt * Vector3(0, h, 0) + drift
		r = nr
	var trunk_top := pos
	var cyl := CylinderShape3D.new()
	cyl.radius = 3.9
	cyl.height = 28.0
	add_shape.call(cyl, Transform3D(Basis.IDENTITY, o + Vector3(0, 14.5, 0)))

	# Glowing veins spiralling up the bark.
	for i in 30:
		var t := float(i) / 30.0
		var seg: Array = trunk_points[mini(int(t * 7.0), 6)]
		var a := t * TAU * 2.3 + rng.randf_range(-0.2, 0.2)
		var sr: float = seg[1] * 0.92 + 0.05
		var p: Vector3 = seg[0] + Vector3(cos(a) * sr, fmod(t * 7.0, 1.0) * 4.6, sin(a) * sr)
		runes.add_box(Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, rng.randf_range(-0.5, 0.5)), p), Vector3(0.12, rng.randf_range(1.2, 2.6), 0.12), Color(1, 1, 1))

	# Roots spread over the dais; low enough to step or hop over.
	for i in 8:
		var a := TAU * i / 8.0 + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var p0 := o + dir * 2.5 + Vector3(0, 1.4, 0)
		var p1 := o + dir * rng.randf_range(10.0, 12.5) + Vector3(0, -0.2, 0)
		var axis := p1 - p0
		bark.add_cylinder(Transform3D(basis_y(axis), p0), 1.3, 0.25, axis.length(), 7, BARK * 0.9)
		var cap := CapsuleShape3D.new()
		cap.radius = 0.55
		cap.height = axis.length() * 0.8
		add_shape.call(cap, Transform3D(basis_y(axis), p0 + axis * 0.45 + Vector3(0, -0.35, 0)))

	# Branches, leaf canopy and hanging orbs.
	var orb_sites: Array[Vector3] = []
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.3, 0.3)
		var start := trunk_top - Vector3(0, rng.randf_range(2.0, 9.0), 0)
		var dir := Vector3(cos(a), rng.randf_range(0.35, 0.7), sin(a)).normalized()
		var length := rng.randf_range(11.0, 16.0)
		bark.add_cylinder(Transform3D(basis_y(dir), start), 1.4, 0.35, length, 7, BARK)
		var end := start + dir * length
		var sub_dir := (dir + Vector3(rng.randf_range(-0.6, 0.6), 0.3, rng.randf_range(-0.6, 0.6))).normalized()
		var sub_start := start + dir * length * 0.55
		bark.add_cylinder(Transform3D(basis_y(sub_dir), sub_start), 0.6, 0.15, length * 0.6, 5, BARK)
		for c in [end, sub_start + sub_dir * length * 0.6]:
			orb_sites.append(c)

	# Build the crown from overlapping textured leaf cards like the forest trees.
	# Small, irregular clusters break up the giant faceted blobs while keeping a
	# dense rounded silhouette around the Elder Tree's broad limbs.
	var canopy_center := trunk_top + Vector3(0, 4.0, 0)
	for i in 1500:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.85, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var radius := pow(rng.randf(), 0.52)
		var center := canopy_center + Vector3(dir.x * 23.0, dir.y * 11.5, dir.z * 22.0) * radius
		var facing := (dir + Vector3(rng.randf_range(-0.65, 0.65), rng.randf_range(-0.45, 0.65), rng.randf_range(-0.65, 0.65))).normalized()
		var size := rng.randf_range(2.8, 4.8)
		var shade := rng.randf_range(0.78, 1.2) * (1.08 if dir.y > 0.25 else 0.92)
		var leaf_color := Color(CANOPY.r * shade, CANOPY.g * shade, CANOPY.b * shade)
		FoliageMeshes._cluster(leaf_cards, center, facing, size, canopy_center, rng, 0.65 + radius * 0.35, leaf_color)
		if i % 3 == 0:
			var second_center := center + Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.8, 0.8), rng.randf_range(-1.2, 1.2))
			FoliageMeshes._cluster(leaf_cards, second_center, Vector3(-facing.z, facing.y, facing.x), size * rng.randf_range(0.65, 0.9), canopy_center, rng, 0.7 + radius * 0.3, leaf_color * 1.04)
	for i in orb_sites.size() * 2:
		var site: Vector3 = orb_sites[i % orb_sites.size()]
		var hang := rng.randf_range(3.0, 8.0)
		var p := site + Vector3(rng.randf_range(-4, 4), -hang, rng.randf_range(-4, 4))
		bark.add_cylinder(Transform3D(Basis.IDENTITY, p), 0.03, 0.03, hang - 1.0, 3, Color(0.15, 0.2, 0.12))
		var target := warm if i % 3 != 0 else teal
		target.add_blob(Transform3D(Basis.IDENTITY, p), rng.randf_range(0.35, 0.6), Color(1, 1, 1), false)

	_emit(parent, stone, STONE_MAT, true)
	_emit(parent, bark, PROPS_MAT, true)
	var canopy_mat: ShaderMaterial = CANOPY_CARDS.duplicate()
	canopy_mat.set_shader_parameter("tint", Color(0.78, 0.88, 0.78))
	canopy_mat.set_shader_parameter("wind_strength", 0.07)
	canopy_mat.set_shader_parameter("wind_speed", 0.4)
	canopy_mat.set_shader_parameter("translucency", 0.18)
	var canopy_instance := MeshInstance3D.new()
	canopy_instance.mesh = FoliageMeshes._mesh(null, null, leaf_cards, canopy_mat)
	canopy_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(canopy_instance)
	_emit(parent, warm, BEACON, false)
	_emit(parent, teal, BEACON_TEAL, false)
	_emit(parent, runes, RUNES, false)

	_ring_pieces(parent, o, world, rng)
	_lights(parent, o, trunk_top)


static func _emit(parent: Node3D, kit: MeshKit, mat: Material, shadows: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _ring_pieces(parent: Node3D, o: Vector3, world: World, rng: RandomNumberGenerator) -> void:
	var td := world.terrain_data
	var menhir: PackedScene = Sites.PIECES["menhir"]
	var block: PackedScene = Sites.PIECES["block"]
	var statue: PackedScene = Sites.PIECES["statue"]
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector3(o.x + cos(a) * 20.0, 0, o.z + sin(a) * 20.0)
		p.y = td.height_at(p.x, p.z) - 0.3
		var fallen := i == 2 or i == 5
		var piece: RuinPiece = (block if fallen else menhir).instantiate()
		piece.seed_value = 900 + i
		if fallen:
			piece.size = Vector3(3.6, 1.0, 1.2)
			piece.broken = 0.5
			piece.rotation.y = a + 0.4
		else:
			piece.size = Vector3(1.3, rng.randf_range(3.6, 4.8), 0.8)
			# Runes face the tree.
			piece.rotation.y = -a - PI * 0.5
		piece.position = p
		parent.add_child(piece)
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var p := Vector3(o.x + cos(a) * 16.5, 0, o.z + sin(a) * 16.5)
		p.y = td.height_at(p.x, p.z) - 0.1
		var st: RuinPiece = statue.instantiate()
		st.seed_value = 950 + i
		st.size = Vector3(1.3, 2.4, 1.3)
		st.position = p
		st.rotation.y = -a + PI * 0.5
		parent.add_child(st)
	# A sword driven into a stone at the roots.
	var sword_stone: RuinPiece = block.instantiate()
	sword_stone.size = Vector3(1.4, 0.8, 1.0)
	sword_stone.position = o + Vector3(0, 1.15, 7.0)
	parent.add_child(sword_stone)
	var kit := MeshKit.new(4300)
	kit.add_box(Transform3D(Basis(Vector3.FORWARD, 0.08), o + Vector3(0, 2.6, 7.0)), Vector3(0.12, 1.8, 0.04), Color(0.55, 0.57, 0.6))
	kit.add_box(Transform3D(Basis.IDENTITY, o + Vector3(0.05, 3.3, 7.0)), Vector3(0.6, 0.08, 0.1), Color(0.5, 0.4, 0.2))
	_emit(parent, kit, PROPS_MAT, true)


static func _lights(parent: Node3D, o: Vector3, top: Vector3) -> void:
	var base := OmniLight3D.new()
	base.position = o + Vector3(0, 4.0, 8.0)
	base.light_color = Color(1.0, 0.7, 0.42)
	base.light_energy = 1.4
	base.omni_range = 16.0
	base.omni_attenuation = 1.2
	parent.add_child(base)
	var canopy := OmniLight3D.new()
	canopy.position = top - Vector3(0, 6.0, 0)
	canopy.light_color = Color(0.45, 1.0, 0.9)
	canopy.light_energy = 1.6
	canopy.omni_range = 34.0
	canopy.omni_attenuation = 1.1
	parent.add_child(canopy)
	var flies := CPUParticles3D.new()
	flies.name = "Fireflies"
	flies.position = o + Vector3(0, 3.0, 0)
	flies.amount = 70
	flies.lifetime = 6.0
	flies.preprocess = 6.0
	flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flies.emission_box_extents = Vector3(30, 3, 30)
	flies.direction = Vector3(0, 1, 0)
	flies.spread = 180.0
	flies.gravity = Vector3.ZERO
	flies.initial_velocity_min = 0.1
	flies.initial_velocity_max = 0.4
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	m.radial_segments = 4
	m.rings = 2
	m.material = preload("res://assets/materials/glow_warm.tres")
	flies.mesh = m
	parent.add_child(flies)
