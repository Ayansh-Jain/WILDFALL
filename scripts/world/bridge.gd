class_name Bridge
extends RefCounted
## Builds an arched bridge between two bank points from the layout. Deck ends
## sit flush with the ground; railings/parapets have collision so players do
## not slip off, but the deck is low enough that falling in is harmless.

const STONE_MAT := preload("res://assets/materials/stone.tres")
const PROPS_MAT := preload("res://assets/materials/props.tres")
const WOOD := Color(0.32, 0.23, 0.15)
const WOOD_DARK := Color(0.2, 0.14, 0.09)
const STONE := Color(0.4, 0.39, 0.36)


static func build(parent: Node3D, world: World, def: Dictionary) -> StaticBody3D:
	var td := world.terrain_data
	var a := WorldLayout.v2(def["a"])
	var b := WorldLayout.v2(def["b"])
	var width: float = def["width"]
	var stone_style: bool = def["style"] == "stone"
	var ga := td.height_at(a.x, a.y)
	var gb := td.height_at(b.x, b.y)
	var length := a.distance_to(b)
	var arc := 2.2 if stone_style else 1.4
	var thick := 0.8 if stone_style else 0.3
	var segs := maxi(6, int(length / 2.0))

	var body := StaticBody3D.new()
	body.name = String(def["name"]).replace(" ", "")
	body.collision_layer = Layers.WORLD
	parent.add_child(body)
	var kit := MeshKit.new(hash(def["name"]), 0.07)

	var top := func(t: float) -> Vector3:
		var p := a.lerp(b, t)
		return Vector3(p.x, lerpf(ga, gb, t) + 0.04 + arc * sin(PI * t), p.y)

	var add_box := func(center: Vector3, size: Vector3, basis: Basis, col: Color, collide: bool) -> void:
		kit.add_box(Transform3D(basis, center), size, col)
		if collide:
			var bs := BoxShape3D.new()
			bs.size = size
			var cs := CollisionShape3D.new()
			cs.shape = bs
			cs.transform = Transform3D(basis, center)
			body.add_child(cs)

	for i in segs:
		var p0: Vector3 = top.call(float(i) / segs)
		var p1: Vector3 = top.call(float(i + 1) / segs)
		var x := (p1 - p0).normalized()
		var side := Vector3(-x.z, 0, x.x).normalized()
		var y := side.cross(x).normalized()
		var basis := Basis(x, y, side)
		var seg_len := p0.distance_to(p1) + 0.1
		var mid := (p0 + p1) * 0.5
		add_box.call(mid - y * thick * 0.5, Vector3(seg_len, thick, width), basis, (STONE if stone_style else WOOD) * (0.92 + 0.12 * (i % 2)), true)
		if stone_style:
			# Underside arch ribs and stone kerb courses for stronger bridge silhouette.
			kit.add_box(Transform3D(basis, mid - y * (thick + 0.18)), Vector3(seg_len * 0.88, 0.38, width * 0.86), STONE * 0.78)
		for s in [-1.0, 1.0]:
			var edge: Vector3 = mid + side * s * (width * 0.5 - 0.12)
			if stone_style:
				add_box.call(edge + y * 0.4, Vector3(seg_len, 0.8, 0.35), basis, STONE * 0.9, true)
				# Chamfered coping cap & buttress pilaster every 3rd segment.
				kit.add_box(Transform3D(basis, edge + y * 0.84), Vector3(seg_len + 0.04, 0.14, 0.46), STONE * 1.04)
				if i % 3 == 0:
					kit.add_box(Transform3D(basis, edge + side * s * 0.24 + y * 0.2), Vector3(0.45, 1.25, 0.25), STONE * 0.82)
			else:
				add_box.call(edge + y * 1.0, Vector3(seg_len, 0.12, 0.12), basis, WOOD_DARK, false)
				add_box.call(edge + y * 0.56, Vector3(seg_len, 0.08, 0.08), basis, WOOD * 0.9, false)
				kit.add_box(Transform3D(Basis.IDENTITY, p0 + side * s * (width * 0.5 - 0.12) + Vector3(0, 0.5, 0)), Vector3(0.16, 1.1, 0.16), WOOD_DARK)
				# The rail itself is thin; give it a full-height collider so it reads as solid.
				var rs := BoxShape3D.new()
				rs.size = Vector3(seg_len, 1.1, 0.14)
				var rcs := CollisionShape3D.new()
				rcs.shape = rs
				rcs.transform = Transform3D(basis, edge + y * 0.55)
				body.add_child(rcs)
		if not stone_style:
			for k in 3:
				var plank_c: Vector3 = mid + x * (seg_len * (k - 1) / 3.0) + y * 0.005
				kit.add_box(Transform3D(basis, plank_c), Vector3(0.05, 0.02, width * 0.98), WOOD_DARK)

	# Supports: wooden piles with diagonal bracing or a central cutwater stone pier.
	if stone_style:
		var c: Vector3 = top.call(0.5)
		var bed := td.height_at(c.x, c.z)
		var h := c.y - thick - bed + 1.0
		var yaw_b := atan2(-(b - a).y, (b - a).x)
		add_box.call(Vector3(c.x, bed - 1.0 + h * 0.5, c.z), Vector3(2.6, h, width + 0.6), Basis(Vector3.UP, yaw_b), STONE * 0.85, true)
		kit.add_box(Transform3D(Basis(Vector3.UP, yaw_b + PI * 0.25), Vector3(c.x, bed - 1.0 + h * 0.45, c.z)), Vector3(width * 0.82, h * 0.9, width * 0.82), STONE * 0.78)
		# End bollards at both bridge approaches.
		var dir2 := (b - a).normalized()
		var side2 := Vector2(-dir2.y, dir2.x)
		for end_pt: Vector2 in [a, b]:
			for s: float in [-1.0, 1.0]:
				var bp := end_pt + side2 * s * (width * 0.5 + 0.1)
				var gy := td.height_at(bp.x, bp.y)
				kit.add_box(Transform3D(Basis(Vector3.UP, yaw_b), Vector3(bp.x, gy + 0.55, bp.y)), Vector3(0.55, 1.35, 0.55), STONE * 0.95)
				kit.add_box(Transform3D(Basis(Vector3.UP, yaw_b), Vector3(bp.x, gy + 1.28, bp.y)), Vector3(0.68, 0.18, 0.68), STONE * 1.08)
	else:
		for t in [0.3, 0.5, 0.7]:
			var c: Vector3 = top.call(t)
			var x := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
			var side := Vector3(-x.z, 0, x.x)
			for s in [-1.0, 1.0]:
				var p: Vector3 = c + side * s * (width * 0.5 - 0.2)
				var bed := td.height_at(p.x, p.z) - 0.5
				kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, bed, p.z)), 0.18, 0.16, c.y - bed - thick, 6, WOOD_DARK)

	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(STONE_MAT if stone_style else PROPS_MAT)
	body.add_child(mi)
	return body
