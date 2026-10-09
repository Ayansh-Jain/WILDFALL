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
		for s in [-1.0, 1.0]:
			var edge: Vector3 = mid + side * s * (width * 0.5 - 0.12)
			if stone_style:
				add_box.call(edge + y * 0.4, Vector3(seg_len, 0.8, 0.35), basis, STONE * 0.9, true)
			else:
				add_box.call(edge + y * 1.0, Vector3(seg_len, 0.12, 0.12), basis, WOOD_DARK, false)
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

	# Supports: wooden piles or a central stone pier.
	if stone_style:
		var c: Vector3 = top.call(0.5)
		var bed := td.height_at(c.x, c.z)
		var h := c.y - thick - bed + 1.0
		add_box.call(Vector3(c.x, bed - 1.0 + h * 0.5, c.z), Vector3(2.6, h, width + 0.6), Basis(Vector3.UP, atan2(-(b - a).y, (b - a).x)), STONE * 0.85, true)
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
