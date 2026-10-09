class_name Sites
extends Node3D
## Builds the hand-designed structures listed under "sites" in the layout, using
## the reusable RuinPiece scenes. Coordinates inside each builder are local to
## the site centre (x east, z south); "ground" pieces sit on the terrain, the
## rest are placed relative to the site's flattened height.

const PIECES := {
	"wall": preload("res://scenes/world/props/ruin_wall.tscn"),
	"pillar": preload("res://scenes/world/props/pillar.tscn"),
	"arch": preload("res://scenes/world/props/archway.tscn"),
	"stairs": preload("res://scenes/world/props/stairs.tscn"),
	"platform": preload("res://scenes/world/props/platform.tscn"),
	"brazier": preload("res://scenes/world/props/brazier.tscn"),
	"menhir": preload("res://scenes/world/props/menhir.tscn"),
	"statue": preload("res://scenes/world/props/statue.tscn"),
	"rubble": preload("res://scenes/world/props/rubble.tscn"),
	"fallen": preload("res://scenes/world/props/fallen_pillar.tscn"),
	"block": preload("res://scenes/world/props/stone_block.tscn"),
}
const WOOD := Color(0.3, 0.22, 0.15)
const WATERFALL_SHADER := preload("res://assets/materials/waterfall.gdshader")

var world: World
var td: TerrainData
var built := {}  ## site name -> Node3D

var _site: Node3D
var _origin := Vector3.ZERO
var _seed := 1


func build(w: World) -> void:
	world = w
	td = w.terrain_data
	for s in w.layout.list("sites"):
		var c := WorldLayout.v2(s["center"])
		var h: float = td.site_heights.get(s["name"], td.height_at(c.x, c.y))
		_site = Node3D.new()
		_site.name = String(s["name"]).replace(" ", "").replace("'", "")
		add_child(_site)
		_origin = Vector3(c.x, h, c.y)
		_seed = hash(s["name"]) & 0xffff
		match s["type"]:
			"citadel": _citadel()
			"watchtower": _watchtower()
			"chapel": _chapel()
			"castle": _castle()
			"shrine": _shrine()
			"hut": _hut()
			"camp": _camp()
			"summit": _summit()
			"landmark": Landmark.build(_site, _origin, w)
		built[s["name"]] = _site
	for b in w.layout.list("bridges"):
		built[b["name"]] = Bridge.build(self, w, b)
	_waterfall()
	_river_sink()


# --- placement helpers -----------------------------------------------------------

## Places a piece. `pos` is local to the site; with ground=true, y is an offset
## from the lowest terrain under the footprint and tall pieces are extended so
## they never float on slopes. Otherwise y is relative to the site height.
func piece(kind: String, pos: Vector3, yaw_deg: float, size: Vector3, broken := 0.0, ground := true, extra := {}) -> RuinPiece:
	var p: RuinPiece = PIECES[kind].instantiate()
	_seed += 1
	p.seed_value = _seed
	p.broken = broken
	for k in extra:
		p.set(k, extra[k])
	var yaw := deg_to_rad(yaw_deg)
	var world_xz := Vector2(_origin.x + pos.x, _origin.z + pos.z)
	var y := _origin.y + pos.y
	if ground:
		var basis := Basis(Vector3.UP, yaw)
		var hx := size.x * 0.5
		var hz := size.z * 0.5
		if kind == "stairs":
			hz = size.z
		var lo := INF
		var hi := -INF
		for corner in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3.ZERO]:
			var cw: Vector3 = basis * corner
			var gh := td.height_at(world_xz.x + cw.x, world_xz.y + cw.z)
			lo = minf(lo, gh)
			hi = maxf(hi, gh)
		y = lo - 0.15 + pos.y
		if kind in ["wall", "platform", "pillar", "menhir", "block"]:
			size.y += (hi - lo) + 0.15
	p.size = size
	p.position = Vector3(world_xz.x, y, world_xz.y)
	p.rotation.y = yaw
	_site.add_child(p)
	return p


func wall(a: Vector2, b: Vector2, height: float, thick: float, broken := 0.35) -> RuinPiece:
	var d := b - a
	var mid := (a + b) * 0.5
	return piece("wall", Vector3(mid.x, 0, mid.y), rad_to_deg(atan2(-d.y, d.x)), Vector3(d.length(), height, thick), broken)


## Stairs from the ground up to an absolute height, ascending in direction `dir`.
## Returns the piece; the stairs' top edge lands at `top`.
func stairs_to(top: Vector3, dir: Vector2, width: float, top_y: float, slope := 0.45, broken := 0.0) -> RuinPiece:
	var yaw := atan2(dir.x, dir.y)
	var run := 6.0
	var base := Vector2.ZERO
	var ground := 0.0
	for i in 5:
		base = Vector2(top.x, top.z) - dir * run
		ground = td.height_at(_origin.x + base.x, _origin.z + base.y)
		run = maxf(4.0, (top_y - ground) / slope)
	# Base and size must come from the same run, or the ramp overshoots the top edge.
	base = Vector2(top.x, top.z) - dir * run
	ground = td.height_at(_origin.x + base.x, _origin.z + base.y)
	var p: RuinPiece = PIECES["stairs"].instantiate()
	_seed += 1
	p.seed_value = _seed
	p.broken = broken
	p.size = Vector3(width, top_y - ground + 0.15, run)
	p.position = Vector3(_origin.x + base.x, ground - 0.15, _origin.z + base.y)
	p.rotation.y = yaw
	_site.add_child(p)
	return p


# --- sites -----------------------------------------------------------------------------

func _citadel() -> void:
	var H := 5.0
	var T := 1.6
	# Outer walls with gates, a postern, a breach and a collapsed corner.
	wall(Vector2(-14, -24), Vector2(11, -24), H, T, 0.35)
	wall(Vector2(14, -24), Vector2(24, -24), H, T, 0.3)
	wall(Vector2(-24, -24), Vector2(-14, -24), 2.0, T, 0.9)
	wall(Vector2(24, -24), Vector2(24, -3.5), H, T, 0.3)
	wall(Vector2(24, 3.5), Vector2(24, 24), H, T, 0.3)
	piece("arch", Vector3(24, 0, 0), -90, Vector3(5, 4.2, 1.8))
	wall(Vector2(-4, 24), Vector2(24, 24), H, T, 0.45)
	wall(Vector2(-24, -16), Vector2(-24, 4), H, T, 0.35)
	wall(Vector2(-24, 10), Vector2(-24, 24), H, T, 0.3)
	piece("arch", Vector3(-24, 0, 7), -90, Vector3(4, 3.8, 1.8), 0.7)
	piece("rubble", Vector3(-21, 0, -21), 0, Vector3(3, 1.2, 3))
	piece("rubble", Vector3(-7, 0, 24), 0, Vector3(2.5, 1.0, 2.5))
	for c in [Vector3(24, 0, -24), Vector3(24, 0, 24), Vector3(-24, 0, 24)]:
		piece("pillar", c, 0, Vector3(6.4, 7.5, 6.4), 0.5)
	# South-west rampart: flat-topped and walkable via inner stairs.
	piece("wall", Vector3(-17, 0, 24), 0, Vector3(14, 4, 3), 0.0)
	piece("stairs", Vector3(-10, 0, 21.4), -90, Vector3(2.2, 4.0, 8.0), 0.0, false)
	for i in 6:
		piece("block", Vector3(-23 + i * 2.2, 4.0, 25.2), 0, Vector3(1.2, 0.8, 0.6), 0.0, false)

	# Keep: raised platform with stairs and a rubble ramp.
	piece("platform", Vector3(2, 0, -4), 0, Vector3(14, 3.2, 14))
	piece("stairs", Vector3(2, 0, 9.4), 180, Vector3(3, 3.2, 6.4), 0.0, false)
	piece("stairs", Vector3(-13, 0, -4), 90, Vector3(2.6, 3.2, 8), 0.6, false)
	var keep_y := 3.2
	for i in 6:
		var a := TAU * i / 6.0
		var b := 0.0 if i % 2 == 0 else 0.7
		piece("pillar", Vector3(2 + cos(a) * 4.5, keep_y, -4 + sin(a) * 4.5), 0, Vector3(0.8, 4.0, 0.8), b, false)
	piece("block", Vector3(2, keep_y, -5.6), 0, Vector3(1.8, 1.0, 1.0), 0.5, false)
	piece("fallen", Vector3(6, keep_y, -9), 25, Vector3(3.5, 0.8, 0.8), 0.0, false)
	piece("wall", Vector3(2, keep_y, -10.6), 0, Vector3(12, 1.4, 0.8), 0.5, false)
	piece("wall", Vector3(8.6, keep_y, -4), 90, Vector3(12, 1.4, 0.8), 0.5, false)
	piece("brazier", Vector3(-3, keep_y, -9.5), 0, Vector3.ONE, 0.0, false)

	# Inner walls: rooms and narrow passages.
	wall(Vector2(-24, -10), Vector2(-15, -10), 3.5, 1.2, 0.3)
	wall(Vector2(-13.4, -10), Vector2(-8, -10), 3.5, 1.2, 0.3)
	wall(Vector2(-12, -23.2), Vector2(-12, -10.6), 3.5, 1.2, 0.4)
	wall(Vector2(10, -18), Vector2(21.6, -18), 3.5, 1.2, 0.3)

	# Collapsed hall in the south-east.
	wall(Vector2(9, 8), Vector2(13, 8), 4, 1.0, 0.5)
	wall(Vector2(15, 8), Vector2(19, 8), 4, 1.0, 0.5)
	wall(Vector2(19, 8), Vector2(19, 18), 4, 1.0, 0.4)
	wall(Vector2(9, 18), Vector2(19, 18), 4, 1.0, 0.6)
	var slab := piece("block", Vector3(16.6, 0.2, 13), 0, Vector3(4.5, 0.35, 5), 0.0)
	slab.rotation = Vector3(0, 0, deg_to_rad(32))

	# Courtyard: colonnade, fountain, statue.
	var breaks := [0.0, 0.8, 0.0, 0.6, 0.0]
	for i in 5:
		piece("pillar", Vector3(-21 + i * 3.5, 0, 1), 0, Vector3(0.9, 4.5, 0.9), breaks[i])
	piece("fallen", Vector3(-15, 0, 5), 20, Vector3(4.5, 0.9, 0.9))
	for i in 8:
		var a := TAU * i / 8.0
		piece("block", Vector3(-14 + cos(a) * 2.6, 0, 14 + sin(a) * 2.6), rad_to_deg(-a) + 90, Vector3(1.9, 0.7, 0.5))
	piece("pillar", Vector3(-14, 0, 14), 0, Vector3(0.7, 2.2, 0.7), 0.5)
	piece("statue", Vector3(-19, 0, 18), -90, Vector3(1.3, 2.2, 1.3))
	piece("rubble", Vector3(-6, 0, 16), 0, Vector3(1.8, 0.8, 1.8))
	piece("brazier", Vector3(27, 0, -5), 0, Vector3.ONE)
	piece("brazier", Vector3(27, 0, 5), 0, Vector3.ONE)
	piece("brazier", Vector3(-1.5, 0, 20), 0, Vector3.ONE)


func _watchtower() -> void:
	var tower := piece("platform", Vector3.ZERO, 0, Vector3(8, 6, 8))
	var top := tower.position.y + tower.size.y
	var top_rel := top - _origin.y
	stairs_to(Vector3(0, 0, 4.0), Vector2(0, -1), 3.0, top, 0.5)
	for i in 5:
		var t := -3.2 + i * 1.6
		piece("block", Vector3(t, top_rel, -3.7), 0, Vector3(0.9, 0.9, 0.6), 0.0, false)
		piece("block", Vector3(3.7, top_rel, t), 90, Vector3(0.9, 0.9, 0.6), 0.0, false)
		piece("block", Vector3(-3.7, top_rel, t), 90, Vector3(0.9, 0.9, 0.6), 0.0, false)
		if absf(t) > 1.8:
			piece("block", Vector3(t, top_rel, 3.7), 0, Vector3(0.9, 0.9, 0.6), 0.0, false)
	# Remnants stay on the west side so the view east to the Elder Tree is open.
	for c in [Vector3(-3.4, 0, -3.4), Vector3(-3.4, 0, 3.4)]:
		piece("pillar", c + Vector3(0, top_rel, 0), 0, Vector3(1.0, 3.5, 1.0), 0.6, false)
	piece("brazier", Vector3(-2.4, top_rel, 0.0), 0, Vector3.ONE, 0.0, false)


func _chapel() -> void:
	wall(Vector2(-5, -9), Vector2(-5, 1), 4.5, 1.0, 0.5)
	wall(Vector2(-5, 3), Vector2(-5, 9), 4.5, 1.0, 0.5)
	wall(Vector2(5, -9), Vector2(5, 9), 4.5, 1.0, 0.75)
	wall(Vector2(-5, -9), Vector2(5, -9), 5.0, 1.0, 0.3)
	wall(Vector2(-5, 9), Vector2(-2.5, 9), 4.5, 1.0, 0.4)
	wall(Vector2(2.5, 9), Vector2(5, 9), 4.5, 1.0, 0.4)
	piece("arch", Vector3(0, 0, 9), 0, Vector3(3, 3.6, 1.2))
	var b := [0.0, 0.7, 0.0, 0.0, 0.6, 0.8]
	var i := 0
	for x in [-2.6, 2.6]:
		for z in [-5.0, -1.0, 3.0]:
			piece("pillar", Vector3(x, 0, z), 0, Vector3(0.7, 4.0, 0.7), b[i])
			i += 1
	piece("block", Vector3(0, 0, -7.8), 0, Vector3(2.2, 1.0, 1.0), 0.5)
	var slab := piece("block", Vector3(3.4, 0.3, 4.5), 0, Vector3(4.0, 0.35, 3.0))
	slab.rotation = Vector3(0, 0, deg_to_rad(28))
	piece("rubble", Vector3(-3.5, 0, 6), 0, Vector3(1.2, 0.6, 1.2))
	piece("brazier", Vector3(2, 0, 11.5), 0, Vector3.ONE)


func _castle() -> void:
	var R := 17.0
	var verts: Array[Vector2] = []
	for k in 8:
		var a := deg_to_rad(22.5 + 45.0 * k)
		verts.append(Vector2(cos(a), sin(a)) * R)
	for k in 8:
		if k == 3:
			continue  # west side: gatehouse
		var broken := 0.95 if k == 7 else 0.35
		var height := 2.2 if k == 7 else 6.0
		wall(verts[k], verts[(k + 1) % 8], height, 1.8, broken)
	var gx := verts[3].x
	piece("arch", Vector3(gx, 0, 0), -90, Vector3(4, 5, 2.2))
	wall(Vector2(gx, 3), Vector2(gx, verts[3].y), 6, 1.8, 0.2)
	wall(Vector2(gx, -3), Vector2(gx, verts[4].y), 6, 1.8, 0.2)
	for k in [3, 4]:
		piece("pillar", Vector3(verts[k].x, 0, verts[k].y), 0, Vector3(5.2, 10, 5.2), 0.3)
	for k in [0, 1, 6]:
		piece("pillar", Vector3(verts[k].x, 0, verts[k].y), 0, Vector3(3.4, 7.5, 3.4), 0.6)
	piece("pillar", Vector3(5, 0, -4), 0, Vector3(7, 18, 7), 0.25)
	piece("rubble", Vector3(-4, 0, -8), 0, Vector3(2.2, 1.0, 2.2))
	piece("rubble", Vector3(R, 0, 0), 0, Vector3(3.0, 1.2, 3.0))
	piece("fallen", Vector3(-3, 0, 10), -15, Vector3(5, 1.0, 1.0))
	piece("brazier", Vector3(gx - 3.5, 0, -4), 0, Vector3.ONE)
	piece("brazier", Vector3(gx - 3.5, 0, 4), 0, Vector3.ONE)


func _shrine() -> void:
	var breaks := [0.0, 0.0, 0.7, 0.0, 0.8, 0.0]
	var base := td.height_at(_origin.x, _origin.z)
	_origin.y = base
	for i in 6:
		var a := TAU * i / 6.0
		piece("pillar", Vector3(cos(a) * 5.0, 0, sin(a) * 5.0), 0, Vector3(0.8, 3.6, 0.8), breaks[i])
	for pair in [[0, 1], [5, 0]]:
		var a0 := TAU * float(pair[0]) / 6.0
		var a1 := TAU * float(pair[1]) / 6.0
		var p0 := Vector2(cos(a0), sin(a0)) * 5.0
		var p1 := Vector2(cos(a1), sin(a1)) * 5.0
		var mid := (p0 + p1) * 0.5
		var d := p1 - p0
		piece("block", Vector3(mid.x, 3.9, mid.y), rad_to_deg(atan2(-d.y, d.x)), Vector3(5.6, 0.5, 0.8), 0.0, false)
	piece("block", Vector3(0, 0, -1.2), 0, Vector3(1.4, 0.9, 0.9), 0.4)
	piece("menhir", Vector3(0, 0, -3.4), 0, Vector3(1.0, 2.8, 0.6))
	piece("brazier", Vector3(2.6, 0, 1.6), 0, Vector3.ONE)


func _hut() -> void:
	wall(Vector2(-2.5, -2.5), Vector2(2.5, -2.5), 2.6, 0.5, 0.5)
	wall(Vector2(2.5, -2.5), Vector2(2.5, 2.5), 2.6, 0.5, 0.5)
	wall(Vector2(-2.5, 2.5), Vector2(2.5, 2.5), 2.6, 0.5, 0.6)
	wall(Vector2(-2.5, -2.5), Vector2(-2.5, -1.0), 2.6, 0.5, 0.3)
	wall(Vector2(-2.5, 1.0), Vector2(-2.5, 2.5), 2.6, 0.5, 0.3)
	var slab := piece("block", Vector3(0, 0.2, -3.8), 0, Vector3(4.2, 0.25, 2.4), 0.0, true, {"color": WOOD})
	slab.rotation = Vector3(deg_to_rad(-30), 0, 0)
	piece("brazier", Vector3(-4, 0, 2.6), 0, Vector3.ONE)


func _camp() -> void:
	piece("brazier", Vector3.ZERO, 0, Vector3.ONE)
	piece("fallen", Vector3(-2.4, 0, 0.3), 80, Vector3(2.4, 0.5, 0.5), 0.0, true, {"color": WOOD})
	piece("fallen", Vector3(1.0, 0, 2.4), 10, Vector3(2.4, 0.5, 0.5), 0.0, true, {"color": WOOD})
	for x in [-4.6, -1.6]:
		piece("pillar", Vector3(x, 0, -3.2), 0, Vector3(0.25, 2.0, 0.25), 0.0, true, {"color": WOOD})
	var slab := piece("block", Vector3(-3.1, 1.0, -2.4), 0, Vector3(3.4, 0.12, 2.4), 0.0, true, {"color": WOOD})
	slab.rotation = Vector3(deg_to_rad(28), 0, 0)


func _summit() -> void:
	piece("menhir", Vector3(-3, 0, -3), 20, Vector3(1.2, 4.0, 0.8))
	piece("rubble", Vector3(2.8, 0, -3.2), 0, Vector3(1.2, 1.4, 1.2))


# --- water features ----------------------------------------------------------------------

func _waterfall() -> void:
	var wf := world.layout.dict("waterfall")
	if wf.is_empty():
		return
	var top := WorldLayout.v2(wf["top"])
	var bottom := WorldLayout.v2(wf["bottom"])
	var steps := 10
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var width := 11.0
	for i in steps + 1:
		var t := float(i) / steps
		var p := top.lerp(bottom, t)
		var y := maxf(td.height_at(p.x, p.y) + 0.6, world.water_level + 0.05)
		verts.append(Vector3(p.x - width * 0.5, y, p.y))
		verts.append(Vector3(p.x + width * 0.5, y, p.y))
		uvs.append(Vector2(0, t))
		uvs.append(Vector2(1, t))
		if i < steps:
			var b := i * 2
			idx.append_array([b, b + 1, b + 3, b, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = WATERFALL_SHADER
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Waterfall"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var foam := CPUParticles3D.new()
	foam.name = "WaterfallFoam"
	foam.position = Vector3(bottom.x, world.water_level + 0.2, bottom.y + 1.0)
	foam.amount = 60
	foam.lifetime = 1.6
	foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	foam.emission_box_extents = Vector3(width * 0.45, 0.2, 1.0)
	foam.direction = Vector3(0, 1, 0.4)
	foam.spread = 35.0
	foam.initial_velocity_min = 1.0
	foam.initial_velocity_max = 2.5
	foam.gravity = Vector3(0, -3, 0)
	var fm := SphereMesh.new()
	fm.radius = 0.18
	fm.height = 0.36
	fm.radial_segments = 6
	fm.rings = 3
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.7, 0.82, 0.85, 0.55)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.material = fmat
	foam.mesh = fm
	add_child(foam)


func _river_sink() -> void:
	var rs := world.layout.dict("river_sink")
	if rs.is_empty():
		return
	var c := WorldLayout.v2(rs["center"])
	_site = Node3D.new()
	_site.name = "RiverSink"
	add_child(_site)
	_origin = Vector3(c.x, world.water_level, c.y)
	# A rock arch swallows the river; the boulder wall behind it is solid.
	var kit := MeshKit.new(77, 0.08)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	_site.add_child(body)
	var rocks := [[Vector3(-9, 2, 2), 6.0], [Vector3(9, 2, 2), 6.0], [Vector3(0, 9, 3), 7.5],
		[Vector3(-4, 1.5, 5), 4.5], [Vector3(4, 1.5, 5), 4.5], [Vector3(0, -1, 6), 5.0]]
	for r in rocks:
		var p: Vector3 = _origin + r[0]
		kit.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1.1, 0.9, 1.0)), p), r[1], PropMeshes.ROCK * 0.75, true, 0.25)
		var s := SphereShape3D.new()
		s.radius = r[1] * 0.85
		var cs := CollisionShape3D.new()
		cs.shape = s
		cs.position = p
		body.add_child(cs)
	var dark := MeshKit.new(78)
	dark.add_box(Transform3D(Basis.IDENTITY, _origin + Vector3(0, 1.0, 3.0)), Vector3(10, 4, 0.5), Color(0.01, 0.01, 0.015))
	kit.append(dark)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(PropMeshes.STONE_MAT)
	_site.add_child(mi)
