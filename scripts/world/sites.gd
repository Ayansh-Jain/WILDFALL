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
const IRON := Color(0.105, 0.12, 0.13)
const BONE := Color(0.74, 0.69, 0.55)
const SLATE := Color(0.105, 0.13, 0.16)
const PROPS_MAT := preload("res://assets/materials/props.tres")
const GLOW_WARM := preload("res://assets/materials/glow_warm.tres")
const WATERFALL_SHADER := preload("res://assets/materials/waterfall.gdshader")
const CASTLE_LIFT_SCRIPT: Script = preload("res://scripts/world/castle_lift.gd")
const VILLAGE_BUILDER_SCRIPT: Script = preload("res://scripts/world/village_builder.gd")
const KINGDOM_BUILDER_SCRIPT: Script = preload("res://scripts/world/kingdom_builder.gd")
const CASTLE_ASHLAR := preload("res://assets/materials/castle_ashlar.tres")
const CASTLE_PROPS_MAT := preload("res://assets/materials/castle_props.tres")
## Surface tags read by castle_props.gdshader from the vertex colour alpha.
## Alpha above 0.65 is plain colour, so `color * k` darkening stays plain; use
## shade() to darken a tagged colour.
const SURF_WOOD := 0.1
const SURF_PLANK := 0.2
const SURF_CLOTH := 0.3
const SURF_IRON := 0.4
const SURF_STONE := 0.5
const SURF_RUBBLE := 0.6
const OAK := Color(0.46, 0.33, 0.22, SURF_WOOD)
const DARK_OAK := Color(0.34, 0.235, 0.155, SURF_WOOD)
const PLANKS := Color(0.40, 0.29, 0.20, SURF_PLANK)
const FORGED := Color(0.13, 0.135, 0.14, SURF_IRON)
const CRIMSON := Color(0.54, 0.205, 0.23, SURF_CLOTH)
const LINEN := Color(0.55, 0.5, 0.42, SURF_CLOTH)
const DRESSED := Color(0.72, 0.64, 0.51, SURF_STONE)
const GOLD_TRIM := Color(0.6, 0.45, 0.16, SURF_CLOTH)

## Interior volumes (world AABB + mood name) that Ambience uses to darken the
## ambient light and drop the ground mist indoors.
var interior_zones: Array[Dictionary] = []
## Story staging points (world space) for the Story director: name -> Vector3.
var story_anchors := {}
## Flower drifts requested by builders for Vegetation: [Vector2 centre, radius, kind].
var flower_patches: Array = []
## Footprints Vegetation must keep clear (kingdom houses, towers, mission spaces): [Vector2, radius].
var vegetation_blockers: Array = []
## The walled kingdom's plan (houses, wall, gate, missions), or null without a "kingdom" layout.
var kingdom_plan: KingdomPlan
var _piece_material: Material
var _flicker: Array[Dictionary] = []
var window_glow := MeshKit.new(4401)
var window_glass := MeshKit.new(4402)
var _window_glow_count := 0
var _flicker_t := 0.0

var world: World
var td: TerrainData
var built := {}  ## site name -> Node3D

var _site: Node3D
var _origin := Vector3.ZERO
var _seed := 1
var castle_transform := Transform3D.IDENTITY
var castle_origin := Vector3.ZERO
var castle_keep: Node3D
var castle_gate_z := 9.0
var bedroom_door: Node3D

func castle_to_world(local: Vector3) -> Vector3:
	return castle_transform * (castle_origin + local)

func castle_from_world(point: Vector3) -> Vector3:
	return castle_transform.affine_inverse() * point - castle_origin


## Routes geometry into one MeshKit per keep room. Compatibility lights at most
## 8 lights per mesh, so a single castle-wide mesh would ignore most lamps;
## per-room meshes also cull independently.
class ZoneKits extends MeshKit:
	var kits := {}
	var _kit_seed := 0
	var _kit_jitter := 0.0

	func _init(seed_value: int = 0, jitter: float = 0.0) -> void:
		super(seed_value, jitter)
		_kit_seed = seed_value
		_kit_jitter = jitter

	func add_tri(a: Vector3, b: Vector3, c: Vector3, color: Color, sa := 0.0, sb := 0.0, sc := 0.0) -> void:
		var key := Sites.castle_zone((a + b + c) / 3.0)
		if not kits.has(key):
			kits[key] = MeshKit.new(_kit_seed + kits.size() * 17, _kit_jitter)
		(kits[key] as MeshKit).add_tri(a, b, c, color, sa, sb, sc)

	func append(other: MeshKit) -> void:
		for i in range(0, other.verts.size(), 3):
			var key := Sites.castle_zone((other.verts[i] + other.verts[i + 1] + other.verts[i + 2]) / 3.0)
			if not kits.has(key):
				kits[key] = MeshKit.new(_kit_seed + kits.size() * 17, 0.0)
			var k: MeshKit = kits[key]
			k.verts.append_array([other.verts[i], other.verts[i + 1], other.verts[i + 2]])
			k.normals.append_array([other.normals[i], other.normals[i + 1], other.normals[i + 2]])
			k.colors.append_array([other.colors[i], other.colors[i + 1], other.colors[i + 2]])
			k.uvs.append_array([other.uvs[i], other.uvs[i + 1], other.uvs[i + 2]])

	func is_empty() -> bool:
		return kits.is_empty()


static func shade(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)


static func tagged(c: Color, surf: float) -> Color:
	return Color(c.r, c.g, c.b, surf)


## Room key for castle-local positions: crypt wings, outside the keep, or
## level + column + row inside it.
static func castle_zone(p: Vector3) -> String:
	if p.y < -2.0:
		return "crypt_w" if p.x < -12.0 else ("crypt_e" if p.x > 5.0 else "crypt_m")
	if p.x < -10.5 or p.x > 26.5 or p.z < -23.5 or p.z > 7.5:
		return "outer_w" if p.x < 8.0 else "outer_e"
	var level := "g" if p.y < 12.3 else ("u" if p.y < 22.0 else "r")
	var column := "w" if p.x < -1.0 else ("e" if p.x > 17.0 else "m")
	var row := "n" if p.z < -7.0 else "s"
	return level + column + row


func _process(delta: float) -> void:
	if _flicker.is_empty():
		return
	_flicker_t += delta
	for f in _flicker:
		var light: OmniLight3D = f["light"]
		var ph: float = f["phase"]
		light.light_energy = float(f["base"]) * (1.0 + 0.09 * sin(_flicker_t * 8.3 + ph) + 0.06 * sin(_flicker_t * 19.0 + ph * 2.7))


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
			"village": VILLAGE_BUILDER_SCRIPT.new(self, _site, _origin, td, w.water_level).build()
			"hamlet": VILLAGE_BUILDER_SCRIPT.new(self, _site, _origin, td, w.water_level).build_hamlet(String(s["name"]))
			"landmark": Landmark.build(_site, _origin, w)
		built[s["name"]] = _site
	for b in w.layout.list("bridges"):
		built[b["name"]] = Bridge.build(self, w, b)
	_waterfall()
	_river_sink()
	_bake_water_shore_map()
	_publish_battlefield_markers()
	if not w.layout.dict("kingdom").is_empty():
		_site = Node3D.new()
		_site.name = "Kingdom"
		add_child(_site)
		_origin = Vector3.ZERO
		_seed = 9001
		KINGDOM_BUILDER_SCRIPT.new(self, _site).build()
		built["Kingdom"] = _site


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
	if _piece_material and not extra.has("stone_material"):
		p.stone_material = _piece_material
		if _piece_material == CASTLE_ASHLAR:
			p.color = Color(0.847, 0.804, 0.725)
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
	# Lakeside Castle: a complete outer ward, defended gate, tall inner keep and
	# a preserved underground bone jail. All dimensions remain in the same metre-scale,
	# hand-built stone language as the rest of the world.
	var hw := 40.0
	var hd := 32.0
	castle_origin = _origin
	var pivot := _origin + Vector3(8, 0, -8)
	var outer_gate := WorldLayout.v2(world.layout.dict("kingdom").get("gate", {}).get("center", [-296, 70]))
	var forward := Vector3(outer_gate.x - pivot.x, 0, outer_gate.y - pivot.z).normalized()
	var turn := Basis(Vector3.UP, atan2(forward.x, forward.z))
	castle_transform = Transform3D(turn, pivot - turn * pivot)
	castle_gate_z = -8.0 + (-40.0 - 8.0) * forward.z / forward.x
	var gate_z := castle_gate_z
	var wall_h := 12.0
	var wall_t := 2.4
	var stonework := ZoneKits.new(_seed + 811, 0.045)
	var roofs := MeshKit.new(_seed + 812, 0.04)
	var banners := MeshKit.new(_seed + 813, 0.025)
	var darkness := MeshKit.new(_seed + 814)
	var woodwork := ZoneKits.new(_seed + 815, 0.035)
	var paintings := ZoneKits.new(_seed + 816, 0.025)
	var lantern_glow := MeshKit.new(_seed + 817)
	_piece_material = CASTLE_ASHLAR

	# Outer curtain wall and broad crenellations.
	_castle_wall_between(Vector2(-hw, -hd), Vector2(hw, -hd), wall_h, wall_t)
	_castle_wall_between(Vector2(hw, -hd), Vector2(hw, hd), wall_h, wall_t)
	_castle_wall_between(Vector2(hw, hd), Vector2(-hw, hd), wall_h, wall_t)
	_castle_wall_between(Vector2(-hw, -hd), Vector2(-hw, gate_z - 6.0), wall_h, wall_t)
	_castle_wall_between(Vector2(-hw, gate_z + 6.0), Vector2(-hw, hd), wall_h, wall_t)
	for edge in [[Vector2(-hw, -hd), Vector2(hw, -hd)], [Vector2(hw, -hd), Vector2(hw, hd)],
			[Vector2(hw, hd), Vector2(-hw, hd)], [Vector2(-hw, -hd), Vector2(-hw, gate_z - 6.0)],
			[Vector2(-hw, gate_z + 6.0), Vector2(-hw, hd)]]:
		_castle_merlons(stonework, edge[0], edge[1], wall_h, wall_t, 3.1)

	# The west gate projects from the curtain wall, with a tall open arch and raised portcullis.
	piece("arch", Vector3(-hw, 0, gate_z), -90, Vector3(10, 8.5, 3.8), 0.0)
	piece("arch", Vector3(-hw + 4.3, 0, gate_z), -90, Vector3(8, 7.5, 3.2), 0.0)
	for z in [gate_z - 10.0, gate_z + 10.0]:
		piece("pillar", Vector3(-hw + 0.2, 0, z), 0, Vector3(6.4, 29.0, 6.4), 0.04)
		_castle_roof(roofs, Vector2(-hw + 0.2, z), 3.8, 29.0, 8.0, SLATE)
		_castle_banner(banners, Vector3(-hw - 4.7, 21.0, z), Color(0.39, 0.055, 0.045))
	for offset in [-3.45, -2.3, -1.15, 0.0, 1.15, 2.3, 3.45]:
		stonework.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(-hw + 0.6, 8.8, gate_z + offset)), 0.105, 0.105, 5.0, 6, IRON)
	stonework.add_cylinder(Transform3D(Landmark.basis_y(Vector3(0, 0, 7.0)), Vector3(-hw + 0.6, 11.2, gate_z - 3.5)), 0.12, 0.12, 7.0, 6, IRON)
	stonework.add_cylinder(Transform3D(Landmark.basis_y(Vector3(0, 0, 7.0)), Vector3(-hw + 0.6, 8.4, gate_z - 3.5)), 0.12, 0.12, 7.0, 6, IRON)

	# Round corner bastions and a smaller eastern watch turret give the skyline depth.
	for c in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]:
		var h := 24.0 if c.x > 0.0 else 22.0
		piece("pillar", Vector3(c.x, 0, c.y), 0, Vector3(9.2, h, 9.2), 0.05)
		_castle_roof(roofs, c, 5.5, h, 7.0, SLATE)
	for z in [-21.0, 21.0]:
		piece("pillar", Vector3(hw, 0, z), 0, Vector3(7.2, 17.0, 7.2), 0.08)
		_castle_roof(roofs, Vector2(hw, z), 4.4, 17.0, 5.5, SLATE)

	# Masonry bridge, parapets and torch stands lead from the old trail to the gate.
	var approach_bridge := piece("platform", Vector3(-51.5, 0, gate_z), 0, Vector3(23.0, 0.9, 11.0), 0.0)
	_castle_wall_between(Vector2(-54.0, gate_z - 6.0), Vector2(-40.0, gate_z - 6.0), 2.2, 0.8)
	_castle_wall_between(Vector2(-54.0, gate_z + 6.0), Vector2(-40.0, gate_z + 6.0), 2.2, 0.8)
	# Climb from the lower approach onto the bridge, then descend into the courtyard.
	var approach_stair := stairs_to(Vector3(-63.0, 0, gate_z), Vector2(1, 0), 22.0, approach_bridge.position.y + approach_bridge.size.y, 0.6)
	_castle_approach_paving(approach_stair.position - _origin)
	# Castle Square Road crosses the bridge apron here. Keep its existing ground
	# route on the broad flared stair, with a north descent and no crossing parapet.
	var deck_y := approach_bridge.position.y + approach_bridge.size.y
	stairs_to(Vector3(-57, 0, gate_z - 5.5), Vector2(0, 1), 10.0, deck_y, 0.35)
	piece("stairs", Vector3(-34.0, 0, gate_z), -90, Vector3(8.0, 0.9, 6.0), 0.0, false)
	piece("brazier", Vector3(-57.0, 0, gate_z - 7.0), 0, Vector3.ONE)
	piece("brazier", Vector3(-57.0, 0, gate_z + 7.0), 0, Vector3.ONE)
	piece("brazier", Vector3(-34.0, 0, gate_z - 9.0), 0, Vector3.ONE)
	piece("brazier", Vector3(-34.0, 0, gate_z + 9.0), 0, Vector3.ONE)

	# Emit the existing ward independently; only the keep rotates.
	var ward := _site
	_emit(ward, stonework, CASTLE_PROPS_MAT, true)
	_emit(ward, roofs, CASTLE_PROPS_MAT, true)
	_emit(ward, banners, PROPS_MAT, true)
	stonework = ZoneKits.new(_seed + 811, 0.025)
	roofs = MeshKit.new(_seed + 812, 0.025)
	banners = MeshKit.new(_seed + 813, 0.025)
	castle_keep = Node3D.new()
	castle_keep.name = "RoyalKeep"
	ward.add_child(castle_keep)
	_site = castle_keep
	# Central keep: great hall at ground level, a walkable first floor and a
	# rooftop tower. The south entrance lines up with the broad approach stair.
	var kx := 8.0
	var kz := -8.0
	var west := kx - 18.0
	var east := kx + 18.0
	var north := kz - 15.0
	var south := kz + 15.0
	# The keep is dressed masonry with flagstone floors; the curtain walls stay rubble.
	_piece_material = CASTLE_ASHLAR
	piece("platform", Vector3(kx, 0, kz), 0, Vector3(36.0, 0.55, 30.0), 0.0)
	_castle_wall_openings(Vector2(west, north), Vector2(east, north), 12.0, 2.0, 0.0,
		[{"t": 0.22, "width": 1.25, "sill": 3.25, "height": 2.2}, {"t": 0.50, "width": 1.25, "sill": 3.25, "height": 2.2}, {"t": 0.78, "width": 1.25, "sill": 3.25, "height": 2.2}], true)
	_castle_wall_openings(Vector2(west, north), Vector2(west, south), 12.0, 2.0, 0.0,
		[{"t": 0.22, "width": 1.25, "sill": 3.25, "height": 2.2}, {"t": 0.68, "width": 1.25, "sill": 3.25, "height": 2.2}], true)
	_castle_wall_openings(Vector2(east, north), Vector2(east, south), 12.0, 2.0, 0.0,
		[{"t": 0.22, "width": 1.25, "sill": 3.25, "height": 2.2}, {"t": 0.68, "width": 1.25, "sill": 3.25, "height": 2.2}], true)
	_castle_wall_openings(Vector2(west, south), Vector2(east, south), 12.0, 2.0, 0.0,
		[{"t": 0.5, "width": 8.0, "sill": 0.0, "height": 8.5}], true)
	piece("arch", Vector3(kx, 0, south), 0, Vector3(8.0, 8.5, 2.6), 0.0)
	# Keep corner turrets rise above the hall roofline.
	for c in [Vector2(west, north), Vector2(east, north), Vector2(west, south), Vector2(east, south)]:
		piece("pillar", Vector3(c.x, 0, c.y), 0, Vector3(7.0, 26.5, 7.0), 0.03)
		_castle_roof(roofs, c, 4.3, 26.5, 6.5, SLATE)

	# Interior hall colonnade and a long feasting table.
	for x in [kx - 12.0, kx - 4.0, kx + 4.0, kx + 12.0]:
		for z in [kz - 6.0, kz + 3.0]:
			if x > kx + 8.0 and z > kz:
				continue  # This bay is the stair hall's walkway.
			piece("pillar", Vector3(x, 0.5, z), 0, Vector3(1.35, 10.0, 1.35), 0.0, false)
	# Preserve the throne dais; the council aisle must remain free of feast tables.
	piece("block", Vector3(kx, 0.55, kz - 13.0), 0, Vector3(7.0, 0.34, 3.6), 0.0, false, {"visible": false})
	piece("brazier", Vector3(kx - 13.0, 0.5, kz - 11.0), 0, Vector3.ONE, 0.0, false)
	piece("brazier", Vector3(kx + 13.0, 0.5, kz - 11.0), 0, Vector3.ONE, 0.0, false)

	# First storey and parapeted roof are solid walkable slabs; stairs join each level.
	# The first floor is four slabs around the stairwell in the south-east stair hall
	# (x 17.5..21.2, z -5.5..1.5); together they cover the original 34 x 28 m slab.
	piece("platform", Vector3(4.25, 12.0, kz), 0, Vector3(26.5, 0.7, 28.0), 0.0, false)
	piece("platform", Vector3(21.25, 12.0, -13.75), 0, Vector3(7.5, 0.7, 16.5), 0.0, false)
	piece("platform", Vector3(23.1, 12.0, 0.25), 0, Vector3(3.8, 0.7, 11.5), 0.0, false)
	piece("platform", Vector3(19.35, 12.0, 3.75), 0, Vector3(3.7, 0.7, 4.5), 0.0, false)
	# The commander's lakeward window is a door onto the balcony.
	_castle_wall_openings(Vector2(west, north), Vector2(east, north), 9.0, 1.8, 12.7,
		[{"t": 0.2, "width": 2.2, "sill": 2.0, "height": 3.4}, {"t": 0.5, "width": 2.2, "sill": 2.0, "height": 3.4}, {"t": 0.8, "width": 2.2, "sill": 2.0, "height": 3.4}], false)
	_castle_wall_openings(Vector2(west, north), Vector2(west, south), 9.0, 1.8, 12.7,
		[{"t": 0.2, "width": 2.0, "sill": 0.0, "height": 3.7}, {"t": 0.55, "width": 2.2, "sill": 2.0, "height": 3.4}, {"t": 0.82, "width": 2.2, "sill": 2.0, "height": 3.4}], false)
	_castle_wall_openings(Vector2(east, north), Vector2(east, south), 9.0, 1.8, 12.7,
		[{"t": 0.2, "width": 2.2, "sill": 2.0, "height": 3.4}, {"t": 0.55, "width": 2.2, "sill": 2.0, "height": 3.4}, {"t": 0.82, "width": 2.2, "sill": 2.0, "height": 3.4}], false)
	_castle_wall_openings(Vector2(west, south), Vector2(east, south), 9.0, 1.8, 12.7,
		[{"t": 0.5, "width": 8.0, "sill": 0.0, "height": 6.8}], false)
	piece("arch", Vector3(kx, 12.7, south), 0, Vector3(8.0, 6.8, 2.4), 0.0, false)
	_castle_wall_between(Vector2(west, north), Vector2(east, north), 1.8, 1.5, false, 21.7)
	_castle_wall_between(Vector2(west, north), Vector2(west, south), 1.8, 1.5, false, 21.7)
	_castle_wall_between(Vector2(east, north), Vector2(east, south), 1.8, 1.5, false, 21.7)
	_castle_wall_between(Vector2(west, south), Vector2(east, south), 1.8, 1.5, false, 21.7)
	# Roof walk. The former 50-degree oak stair over the south hall could not be
	# climbed; the roof is now reached from the stair hall, so its opening is closed
	# and the stairwell opening sits above the stair hall (x 17.5..21.2, z -4.4..-0.6).
	piece("platform", Vector3(-2.25, 21.7, kz), 0, Vector3(15.5, 0.55, 30.0), 0.0, false)
	piece("platform", Vector3(kx, 21.7, kz), 0, Vector3(5.0, 0.55, 30.0), 0.0, false)
	piece("platform", Vector3(14.0, 21.7, kz), 0, Vector3(7.0, 0.55, 30.0), 0.0, false)
	piece("platform", Vector3(19.35, 21.7, -13.7), 0, Vector3(3.7, 0.55, 18.6), 0.0, false)
	piece("platform", Vector3(19.35, 21.7, 3.2), 0, Vector3(3.7, 0.55, 7.6), 0.0, false)
	piece("platform", Vector3(23.6, 21.7, kz), 0, Vector3(4.8, 0.55, 30.0), 0.0, false)
	for edge in [[Vector2(west, north), Vector2(east, north)], [Vector2(east, north), Vector2(east, south)],
			[Vector2(east, south), Vector2(west, south)], [Vector2(west, south), Vector2(west, north)]]:
		_castle_merlons(stonework, edge[0], edge[1], 23.5, 1.5, 2.6)

	# Square roof tower with an open south doorway and a steep slate cap.
	var tw := 6.5
	var tz := -8.0
	_castle_wall_between(Vector2(kx - tw, tz - tw), Vector2(kx + tw, tz - tw), 13.0, 1.8, false, 22.25)
	_castle_wall_between(Vector2(kx - tw, tz - tw), Vector2(kx - tw, tz + tw), 13.0, 1.8, false, 22.25)
	_castle_wall_between(Vector2(kx + tw, tz - tw), Vector2(kx + tw, tz + tw), 13.0, 1.8, false, 22.25)
	_castle_wall_between(Vector2(kx - tw, tz + tw), Vector2(kx - 3.2, tz + tw), 13.0, 1.8, false, 22.25)
	_castle_wall_between(Vector2(kx + 3.2, tz + tw), Vector2(kx + tw, tz + tw), 13.0, 1.8, false, 22.25)
	piece("arch", Vector3(kx, 22.25, tz + tw), 0, Vector3(6.4, 6.0, 2.0), 0.0, false)
	_castle_merlons(stonework, Vector2(kx - tw, tz - tw), Vector2(kx + tw, tz - tw), 35.25, 1.8, 2.5)
	_castle_merlons(stonework, Vector2(kx + tw, tz - tw), Vector2(kx + tw, tz + tw), 35.25, 1.8, 2.5)
	_castle_merlons(stonework, Vector2(kx + tw, tz + tw), Vector2(kx - tw, tz + tw), 35.25, 1.8, 2.5)
	_castle_merlons(stonework, Vector2(kx - tw, tz + tw), Vector2(kx - tw, tz - tw), 35.25, 1.8, 2.5)
	_castle_roof(roofs, Vector2(kx, tz), 8.2, 35.25, 9.0, SLATE)
	_castle_banner(banners, Vector3(kx, 39.0, tz - 8.0), Color(0.37, 0.05, 0.04))

	# Glazed gothic windows puncture the upper storey; deep stone reveals and
	# timber tracery make them read as openings from both inside and out.
	_castle_window_details(stonework, darkness, Vector2(west, north), Vector2(east, north),
		[0.2, 0.5, 0.8], 2.2, 14.7, 3.4, 1.8)
	_castle_window_details(stonework, darkness, Vector2(west, north), Vector2(west, south),
		[0.55, 0.82], 2.2, 14.7, 3.4, 1.8)
	_castle_window_details(stonework, darkness, Vector2(east, north), Vector2(east, south),
		[0.2, 0.55, 0.82], 2.2, 14.7, 3.4, 1.8)
	_castle_window_details(stonework, darkness, Vector2(west, south), Vector2(east, south),
		[0.2, 0.8], 2.2, 14.7, 3.4, 1.8)
	for x in [kx - 5.0, kx + 5.0]:
		_castle_banner(banners, Vector3(x, 17.7, south + 1.18), Color(0.39, 0.06, 0.045))
	# Narrow ground-floor embrasures have deep stone sills; their matching upper
	# lights are visible across the lake after dusk.
	_castle_window_details(stonework, darkness, Vector2(west, north), Vector2(east, north),
		[0.22, 0.5, 0.78], 1.25, 3.25, 2.2, 2.0)
	_castle_window_details(stonework, darkness, Vector2(west, north), Vector2(west, south),
		[0.22, 0.68], 1.25, 3.25, 2.2, 2.0)
	_castle_window_details(stonework, darkness, Vector2(east, north), Vector2(east, south),
		[0.22, 0.68], 1.25, 3.25, 2.2, 2.0)

	# Practical room divisions: a smoky kitchen and library flank the great hall;
	# private chambers and a map room occupy the upper floor.
	_castle_wall_openings(Vector2(-1.0, north), Vector2(-1.0, south), 11.4, 1.0, 0.0,
		[{"t": 0.72, "width": 3.6, "sill": 0.0, "height": 7.0}], false)
	# New: a door into the south-east stair hall, and one from the kitchen into the library.
	_castle_wall_openings(Vector2(17.0, north), Vector2(17.0, south), 11.4, 1.0, 0.0,
		[{"t": 0.28, "width": 4.0, "sill": 0.0, "height": 7.0}, {"t": 0.6, "width": 2.2, "sill": 0.0, "height": 3.8}], false)
	_castle_wall_openings(Vector2(-1.0, north), Vector2(-1.0, south), 8.7, 1.0, 12.7,
		[{"t": 0.72, "width": 3.6, "sill": 0.0, "height": 6.0}], false)
	# New: the stair hall opens to the upper landing; the barracks open to the commander's quarters.
	_castle_wall_openings(Vector2(17.0, north), Vector2(17.0, south), 8.7, 1.0, 12.7,
		[{"t": 0.28, "width": 4.0, "sill": 0.0, "height": 6.0}, {"t": 0.5767, "width": 3.8, "sill": 0.0, "height": 3.6}], false)
	_castle_wall_openings(Vector2(west, -7.0), Vector2(kx - 4.0, -7.0), 8.7, 1.0, 12.7,
		[{"t": 0.4857, "width": 1.8, "sill": 0.0, "height": 3.6}], false)
	_castle_wall_openings(Vector2(kx + 4.0, -7.0), Vector2(east, -7.0), 8.7, 1.0, 12.7, [], false)
	piece("arch", Vector3(kx, 12.7, -7.0), 0, Vector3(5.0, 6.0, 1.4), 0.0, false)
	_castle_stair_tower(stonework)
	_castle_balcony(stonework)
	_piece_material = null
	interior_zones.append({"mood": "keep", "inverse": castle_transform.affine_inverse(), "aabb": AABB(_origin + Vector3(-10.0, 0.3, -23.0), Vector3(36.0, 21.6, 30.0))})
	interior_zones.append({"mood": "crypt", "aabb": AABB(_origin + Vector3(-37.0, -13.0, -26.0), Vector3(56.0, 9.0, 53.0))})
	_castle_rooms(woodwork, paintings)
	_castle_dressing(woodwork, paintings, stonework, lantern_glow)
	_castle_lamps(woodwork, lantern_glow, false)
	preload("res://scripts/world/royal_castle.gd").new().build(self, woodwork, paintings, stonework, lantern_glow)

	_emit(_site, stonework, CASTLE_PROPS_MAT, true)
	_emit(_site, roofs, CASTLE_PROPS_MAT, true)
	_emit(_site, banners, PROPS_MAT, true)
	_emit(_site, darkness, PROPS_MAT, false)
	_emit(_site, woodwork, CASTLE_PROPS_MAT, true)
	_emit(_site, paintings, CASTLE_PROPS_MAT, false)
	_emit(_site, lantern_glow, GLOW_WARM, false)
	_emit(_site, window_glow, GLOW_WARM, false)
	_emit(_site, window_glass, preload("res://assets/materials/castle_glass.tres"), false)
	castle_keep.transform = castle_transform
	for key in ["roof_reve", "king_throne", "king_audience", "castle_courtyard", "commander_desk", "commander_spawn", "hall_reveal", "castle_exit"]:
		if not story_anchors.has(key):
			continue
		var anchor: Variant = story_anchors[key]
		if anchor is Dictionary:
			anchor["pos"] = castle_transform * anchor["pos"]
			anchor["yaw"] = float(anchor.get("yaw", 0.0)) + turn.get_euler().y
		else:
			story_anchors[key] = castle_transform * anchor
	# Prison, tunnel, lift and their lights retain their original world transforms.
	_site = ward
	_piece_material = null
	var prison := Node3D.new()
	prison.name = "PreservedUndercroft"
	ward.add_child(prison)
	_site = prison
	stonework = ZoneKits.new(_seed + 811, 0.045)
	darkness = MeshKit.new(_seed + 814)
	paintings = ZoneKits.new(_seed + 816, 0.025)
	woodwork = ZoneKits.new(_seed + 815, 0.035)
	lantern_glow = MeshKit.new(_seed + 817)
	_castle_crypt(stonework, darkness, paintings)
	_castle_lift()
	_castle_lamps(woodwork, lantern_glow, true)
	_emit(_site, stonework, CASTLE_PROPS_MAT, true)
	_emit(_site, darkness, PROPS_MAT, false)
	_emit(_site, paintings, CASTLE_PROPS_MAT, false)
	_emit(_site, woodwork, CASTLE_PROPS_MAT, true)
	_emit(_site, lantern_glow, GLOW_WARM, false)
	_site = ward
	# Courtyard well and scattered fallen masonry; the active jail is below ground.
	for i in 8:
		var a := TAU * i / 8.0
		piece("block", Vector3(-23.0 + cos(a) * 2.2, 0, 13.0 + sin(a) * 2.2), rad_to_deg(-a), Vector3(1.9, 1.15, 0.8), 0.12)
	piece("pillar", Vector3(-23, 0, 13), 0, Vector3(1.1, 1.2, 1.1), 0.0)
	piece("fallen", Vector3(24.0, 0, 20.0), 18, Vector3(6.0, 1.0, 1.0), 0.0)



func _castle_wall_between(a: Vector2, b: Vector2, height: float, thick: float,
		ground := true, base_y := 0.0, broken := 0.06) -> RuinPiece:
	var d := b - a
	var mid := (a + b) * 0.5
	var yaw := rad_to_deg(atan2(-d.y, d.x))
	return piece("wall", Vector3(mid.x, base_y, mid.y), yaw, Vector3(d.length(), height, thick), broken, ground)


## Builds a wall around door and window apertures. Each aperture is {t, width,
## sill, height}, with t measured along the wall from a to b.
func _castle_wall_openings(a: Vector2, b: Vector2, height: float, thick: float,
		base_y: float, openings: Array = [], ground := false) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var sorted: Array = openings.duplicate()
	sorted.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left["t"]) < float(right["t"]))
	var cursor := 0.0
	for opening: Dictionary in sorted:
		var center := clampf(float(opening["t"]), 0.0, 1.0) * length
		var half := float(opening["width"]) * 0.5
		var start := maxf(cursor, center - half)
		var finish := minf(length, center + half)
		if start > cursor + 0.05:
			_castle_wall_span(a, b, cursor, start, 0.0, height, thick, base_y, ground)
		if finish <= start:
			continue
		var sill := clampf(float(opening["sill"]), 0.0, height)
		var aperture_top := clampf(sill + float(opening["height"]), sill, height)
		_castle_wall_span(a, b, start, finish, 0.0, sill, thick, base_y, ground)
		_castle_wall_span(a, b, start, finish, aperture_top, height - aperture_top, thick, base_y, ground)
		cursor = finish
	if cursor < length - 0.05:
		_castle_wall_span(a, b, cursor, length, 0.0, height, thick, base_y, ground)


func _castle_wall_span(a: Vector2, b: Vector2, from: float, to: float, bottom: float,
		part_height: float, thick: float, base_y: float, ground: bool) -> void:
	if to - from < 0.05 or part_height < 0.12:
		return
	var dir := (b - a).normalized()
	var p0 := a + dir * from
	var p1 := a + dir * to
	var mid := (p0 + p1) * 0.5
	var yaw := rad_to_deg(atan2(-(p1.y - p0.y), p1.x - p0.x))
	piece("wall", Vector3(mid.x, base_y + bottom, mid.y), yaw,
		Vector3(p0.distance_to(p1), part_height, thick), 0.0, ground)


func _castle_window_details(kit: MeshKit, panes: MeshKit, a: Vector2, b: Vector2,
		fractions: Array, width: float, sill: float, window_height: float, thick: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.1:
		return
	var axis := d / length
	var normal := Vector2(-axis.y, axis.x)
	var yaw := atan2(-axis.y, axis.x)
	var basis := Basis(Vector3.UP, yaw)
	for fraction in fractions:
		var center := a.lerp(b, float(fraction))
		var pos := Vector3(center.x, sill + window_height * 0.5, center.y)
		var reveal := thick * 0.5 + 0.08
		for side in [-1.0, 1.0]:
			var p: Vector3 = pos + Vector3(normal.x, 0, normal.y) * reveal * side
			kit.add_box(Transform3D(basis, p + Vector3(0, -window_height * 0.5, 0)), Vector3(width + 0.4, 0.22, 0.42), DRESSED)
			for x in [-1.0, 1.0]:
				kit.add_box(Transform3D(basis, p + basis * Vector3(x * width * 0.5, 0, 0)), Vector3(0.2, window_height + 0.2, 0.42), shade(DRESSED, 0.92))
		# A leaded, smoked pane catches a little amber light from inside at night.
		var inset := pos - Vector3(normal.x, 0, normal.y) * 0.1
		window_glass.add_box(Transform3D(basis, inset), Vector3(width - 0.2, window_height - 0.22, 0.055), Color.WHITE)
		_window_glow_count += 1
		if _window_glow_count % 3 != 0:
			var away := center - Vector2(8.0, -8.0)
			var out := Vector3(normal.x, 0, normal.y) * (1.0 if normal.dot(away) > 0.0 else -1.0)
			var gc := pos + out * 0.16
			var right := basis * Vector3(width * 0.5 - 0.12, 0, 0)
			var up := Vector3(0, window_height * 0.5 - 0.13, 0)
			# A single outward-facing quad: culled from inside the room.
			var q := [gc - right - up, gc + right - up, gc + right + up, gc - right + up]
			if right.cross(up).dot(out) < 0.0:
				q = [q[1], q[0], q[3], q[2]]
			window_glow.add_quad(q[0], q[1], q[2], q[3], Color(0.2, 0.11, 0.05))
			# Leaded bars in front of the glow so it reads as a lit window, not a slab.
			for bx in [-0.34, 0.0, 0.34]:
				kit.add_box(Transform3D(basis, gc + out * 0.03 + basis * Vector3(bx * width, 0, 0)), Vector3(0.06, window_height - 0.24, 0.04), Color(0.06, 0.05, 0.04))
			kit.add_box(Transform3D(basis, gc + out * 0.03), Vector3(width - 0.2, 0.06, 0.04), Color(0.06, 0.05, 0.04))
		for x in [-0.5, 0.5]:
			panes.add_box(Transform3D(basis, inset + basis * Vector3(x * width * 0.68, 0, 0)), Vector3(0.075, window_height - 0.3, 0.08), Color(0.16, 0.13, 0.1))
		panes.add_box(Transform3D(basis, inset + Vector3(0, 0, 0.045)), Vector3(width - 0.22, 0.075, 0.08), Color(0.16, 0.13, 0.1))


func _castle_rooms(wood: MeshKit, art: MeshKit) -> void:
	# Great hall: a central runner, high table, benches, dais and the old lord's chair.
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(8.0, 0.57, -7.5)), Vector3(4.2, 0.03, 26.0), CRIMSON)
	for side in [-1.0, 1.0]:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(8.0 + side * 1.95, 0.585, -7.5)), Vector3(0.22, 0.03, 26.0), tagged(Color(0.55, 0.42, 0.18), SURF_CLOTH))
	# Dais, high table and the lord's chair.
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(8.0, 0.72, -21.0)), Vector3(7.0, 0.34, 3.6), PLANKS)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(8.0, 1.4, -21.6)), Vector3(1.0, 0.12, 0.9), DARK_OAK)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(8.0, 2.35, -22.0)), Vector3(1.1, 2.0, 0.14), DARK_OAK)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(8.0, 2.5, -21.9)), Vector3(0.8, 1.2, 0.06), CRIMSON)
	for x in [7.45, 8.55]:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.1, -21.2)), Vector3(0.1, 1.1, 0.1), DARK_OAK)
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 1.75, -21.6)), Vector3(0.12, 0.08, 0.85), DARK_OAK)
	# Side rooms: shelves in the west library, a working kitchen, and an orderly armory.
	_castle_bookshelf(wood, Vector3(-7.2, 0.5, -16.5), 5.7, 5.8, 1.0)
	_castle_bookshelf(wood, Vector3(-7.2, 0.5, -9.8), 5.7, 5.8, 1.0)
	_castle_table(wood, Vector3(-5.2, 0.55, -0.2), 4.0, 1.8, 0.9, 0.0)
	wood.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(-8.35, 0.75, 1.6)), 0.42, 0.34, 0.5, 10, FORGED)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(21.5, 0.85, -18.7)), Vector3(6.4, 0.5, 1.2), OAK)
	for i in 6:
		var z := -22.0 + float(i) * 2.0
		wood.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(23.6, 1.7, z)), 0.055, 0.055, 3.4, 6, FORGED)
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(21.8, 1.4, z)), Vector3(2.1, 0.11, 0.18), OAK)
		wood.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.6, 0.7, 0.35)), Vector3(21.7, 1.82, z)), 0.95,
			[tagged(Color(0.42, 0.42, 0.4), SURF_IRON), tagged(Color(0.36, 0.2, 0.12), SURF_CLOTH), tagged(Color(0.2, 0.21, 0.22), SURF_IRON)][i % 3], false, 0.0)
	# War room table with maps.
	_castle_table(wood, Vector3(9.0, 12.7, -14.6), 9.0, 3.2, 0.9, 0.0)
	for x in [5.5, 8.0, 10.5, 13.0]:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 13.61, -14.6)), Vector3(1.6, 0.015, 1.1), tagged(Color(0.62, 0.55, 0.4), SURF_CLOTH))
	for x in [6.0, 9.0, 12.0]:
		for side in [-1.0, 1.0]:
			_castle_chair(wood, Vector3(x, 12.7, -14.6 + side * 2.2), 0.0 if side > 0.0 else PI)
	# Archive furniture remains behind the private chamber door.
	_castle_table(wood, Vector3(21.8, 12.7, -14.5), 6.5, 4.8, 0.9, 0.0)
	for x in [19.0, 24.6]:
		_castle_bookshelf(wood, Vector3(x, 12.72, -20.3), 4.5, 5.8, 0.9)
	# Heraldic wall panels: a lake, a hunt, and a founder whose crown was removed.
	_castle_painting(art, Vector3(1.6, 5.25, 5.95), 3.2, 2.6, Color(0.07, 0.13, 0.2), 1, PI)
	_castle_painting(art, Vector3(-6.5, 5.0, -22.0), 2.7, 2.3, Color(0.23, 0.1, 0.07), 2)
	_castle_painting(art, Vector3(0.0, 17.3, -6.42), 3.2, 2.6, Color(0.16, 0.15, 0.1), 3)
	_castle_plaque("THE LAKE REMEMBERS", Vector3(1.6, 3.65, 5.72), Color(0.77, 0.64, 0.42), PI)
	_castle_plaque("ARVEN, LAST LORD OF THE SHORE", Vector3(0.0, 19.1, -6.34), Color(0.72, 0.62, 0.43))


## Plank top on two trestles with a stretcher; `at` is on the floor under the
## table centre and yaw 0 runs the long side along x.
func _castle_table(kit: MeshKit, at: Vector3, length: float, width: float, height: float, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.add_box(Transform3D(b, at + b * Vector3(0, height - 0.06, 0)), Vector3(length, 0.12, width), OAK)
	for x in [-length * 0.38, length * 0.38]:
		kit.add_box(Transform3D(b, at + b * Vector3(x, (height - 0.12) * 0.5, 0)), Vector3(0.16, height - 0.12, 0.16), DARK_OAK)
		kit.add_box(Transform3D(b, at + b * Vector3(x, 0.06, 0)), Vector3(0.22, 0.12, width * 0.8), DARK_OAK)
		kit.add_box(Transform3D(b, at + b * Vector3(x, height - 0.2, 0)), Vector3(0.18, 0.12, width * 0.85), DARK_OAK)
	kit.add_box(Transform3D(b, at + b * Vector3(0, height * 0.35, 0)), Vector3(length * 0.76, 0.1, 0.12), DARK_OAK)


func _castle_bench(kit: MeshKit, at: Vector3, length: float, width: float, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.add_box(Transform3D(b, at + b * Vector3(0, 0.44, 0)), Vector3(length, 0.08, width), OAK)
	for x in [-length * 0.4, length * 0.4]:
		kit.add_box(Transform3D(b, at + b * Vector3(x, 0.2, 0)), Vector3(0.1, 0.4, width * 0.85), DARK_OAK)


func _castle_chair(kit: MeshKit, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.add_box(Transform3D(b, at + b * Vector3(0, 0.46, 0)), Vector3(0.5, 0.06, 0.5), OAK)
	for x in [-0.21, 0.21]:
		for z in [-0.21, 0.21]:
			kit.add_box(Transform3D(b, at + b * Vector3(x, 0.23, z)), Vector3(0.06, 0.46, 0.06), DARK_OAK)
	kit.add_box(Transform3D(b, at + b * Vector3(0, 0.85, 0.22)), Vector3(0.5, 0.7, 0.06), DARK_OAK)


func _castle_chest(kit: MeshKit, at: Vector3, yaw: float, length: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.add_box(Transform3D(b, at + b * Vector3(0, 0.28, 0)), Vector3(length, 0.56, 0.55), PLANKS)
	kit.add_box(Transform3D(b, at + b * Vector3(0, 0.6, 0)), Vector3(length + 0.04, 0.1, 0.6), DARK_OAK)
	for x in [-length * 0.35, length * 0.35]:
		kit.add_box(Transform3D(b, at + b * Vector3(x, 0.33, 0)), Vector3(0.06, 0.6, 0.62), FORGED)
	kit.add_box(Transform3D(b, at + b * Vector3(0, 0.45, 0.29)), Vector3(0.12, 0.14, 0.03), tagged(Color(0.5, 0.4, 0.2), SURF_IRON))


func _castle_bookshelf(kit: MeshKit, center: Vector3, width: float, height: float, depth: float) -> void:
	kit.add_box(Transform3D(Basis.IDENTITY, center + Vector3(0, height * 0.5, -depth * 0.05)), Vector3(width, height, depth * 0.9), DARK_OAK)
	for level in range(1, 5):
		var y := height * float(level) / 5.0
		kit.add_box(Transform3D(Basis.IDENTITY, center + Vector3(0, y, depth * 0.12)), Vector3(width - 0.18, 0.1, depth * 1.1), OAK)
		for i in range(int(width / 0.42)):
			var x := -width * 0.47 + float(i) * 0.42
			var h := 0.48 + float((i * 7 + level * 3) % 5) * 0.09
			var color: Color = [Color(0.34, 0.08, 0.055), Color(0.11, 0.19, 0.2), Color(0.43, 0.31, 0.16), Color(0.22, 0.25, 0.16)][(i + level) % 4]
			kit.add_box(Transform3D(Basis.IDENTITY, center + Vector3(x, y + 0.06 + h * 0.5, depth * 0.14)), Vector3(0.27, h, 0.38), tagged(color, SURF_CLOTH))


func _castle_bed(kit: MeshKit, center: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	kit.add_box(Transform3D(b, center + b * Vector3(0, 0.3, 0)), Vector3(1.3, 0.22, 2.2), OAK)
	for x in [-0.6, 0.6]:
		for z in [-1.05, 1.05]:
			kit.add_box(Transform3D(b, center + b * Vector3(x, 0.2, z)), Vector3(0.1, 0.4, 0.1), DARK_OAK)
	kit.add_box(Transform3D(b, center + b * Vector3(0, 0.55, -1.08)), Vector3(1.3, 0.7, 0.08), DARK_OAK)
	kit.add_box(Transform3D(b, center + b * Vector3(0, 0.49, 0.05)), Vector3(1.18, 0.16, 2.05), LINEN)
	kit.add_box(Transform3D(b, center + b * Vector3(0, 0.59, -0.78)), Vector3(0.8, 0.12, 0.38), tagged(Color(0.66, 0.62, 0.54), SURF_CLOTH))
	kit.add_box(Transform3D(b, center + b * Vector3(0, 0.585, 0.35)), Vector3(1.24, 0.06, 1.35), tagged(Color(0.24, 0.2, 0.15), SURF_CLOTH))


func _castle_painting(kit: MeshKit, center: Vector3, width: float, height: float, back: Color, motif: int, yaw := 0.0) -> void:
	var r := Basis(Vector3.UP, yaw)
	kit.add_box(Transform3D(r, center), Vector3(width + 0.34, height + 0.34, 0.22), tagged(Color(0.26, 0.17, 0.1), SURF_WOOD))
	kit.add_box(Transform3D(r, center + r * Vector3(0, 0, 0.13)), Vector3(width, height, 0.06), tagged(Color(0.58, 0.45, 0.22), SURF_IRON))
	kit.add_box(Transform3D(r, center + r * Vector3(0, 0, 0.18)), Vector3(width - 0.24, height - 0.24, 0.045), back)
	var inner := Vector3(width - 0.3, height - 0.3, 0.02)
	var field := center + r * Vector3(0, 0, 0.215)
	if motif == 1:
		# Mountains, moonlit water, and the shoreline castle on dark canvas.
		kit.add_box(Transform3D(r, field + r * Vector3(0, -height * 0.3, 0)), Vector3(inner.x, height * 0.34, inner.z), Color(0.06, 0.15, 0.2))
		kit.add_tri(field + r * Vector3(-width * 0.46, -height * 0.03, 0), field + r * Vector3(-width * 0.08, height * 0.36, 0), field + r * Vector3(width * 0.13, -height * 0.02, 0), Color(0.3, 0.36, 0.35))
		kit.add_tri(field + r * Vector3(-width * 0.05, -height * 0.02, 0), field + r * Vector3(width * 0.23, height * 0.27, 0), field + r * Vector3(width * 0.49, -height * 0.03, 0), Color(0.22, 0.29, 0.31))
		kit.add_box(Transform3D(r, field + r * Vector3(0.0, -height * 0.39, -0.02)), Vector3(width * 0.45, height * 0.12, 0.025), Color(0.47, 0.35, 0.18))
	elif motif == 2:
		kit.add_blob(Transform3D(r * Basis.IDENTITY.scaled(Vector3(0.65, 0.85, 0.3)), field + r * Vector3(0, 0.18, 0)), 0.58, Color(0.65, 0.54, 0.38), false, 0.0)
		kit.add_box(Transform3D(r, field + r * Vector3(0, -0.55, -0.02)), Vector3(width * 0.4, 0.65, 0.03), Color(0.24, 0.07, 0.055))
		kit.add_box(Transform3D(r, field + r * Vector3(0, 0.48, 0.02)), Vector3(0.46, 0.11, 0.04), Color(0.67, 0.51, 0.19))
	else:
		kit.add_box(Transform3D(r, field + r * Vector3(0, -0.35, 0)), Vector3(width * 0.36, height * 0.43, 0.04), Color(0.28, 0.08, 0.06))
		kit.add_blob(Transform3D(r * Basis.IDENTITY.scaled(Vector3(0.52, 0.65, 0.28)), field + r * Vector3(0, 0.42, 0.04)), 0.5, Color(0.62, 0.51, 0.4), false, 0.0)
		# The conspicuously empty space above the portrait hints at a cut-away crown.
		kit.add_box(Transform3D(r, field + r * Vector3(0, 0.95, 0.05)), Vector3(0.95, 0.08, 0.05), Color(0.11, 0.1, 0.09))


func _castle_plaque(message: String, at: Vector3, tint: Color, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = message
	label.position = Vector3(_origin.x + at.x, _origin.y + at.y, _origin.z + at.z)
	label.rotation.y = yaw
	label.double_sided = false
	label.font_size = 38
	label.pixel_size = 0.008
	label.modulate = tint
	label.outline_size = 6
	label.outline_modulate = Color(0.025, 0.02, 0.018)
	_site.add_child(label)


func _castle_lamps(kit: MeshKit, glow: MeshKit, fixed: bool) -> void:
	var warm := Color(1.0, 0.56, 0.27)
	var witch := Color(0.76, 0.83, 0.58)
	# Each entry: position and mount. "post" keeps the yard lanterns, a Vector3
	# is the wall normal of a torch sconce, a float is the ceiling for a chain.
	var lamps := [
		[Vector3(-57.0, 2.0, -1.0), "post"], [Vector3(-57.0, 2.0, 19.0), "post"],
		[Vector3(-34.0, 2.0, -2.0), "post"], [Vector3(-34.0, 2.0, 20.0), "post"],
		[Vector3(-0.5, 3.6, -20.0), Vector3(1, 0, 0)], [Vector3(16.5, 3.6, -20.0), Vector3(-1, 0, 0)],
		[Vector3(-0.5, 3.6, 2.0), Vector3(1, 0, 0)], [Vector3(16.5, 3.6, 2.0), Vector3(-1, 0, 0)],
		[Vector3(-9.1, 15.2, -13.8), Vector3(1, 0, 0)], [Vector3(8.0, 16.0, -17.0), 21.2],
		[Vector3(23.0, 16.0, -18.0), 21.7], [Vector3(25.1, 14.4, -6.0), Vector3(-1, 0, 0)],
		[Vector3(-24.0, 3.0, -10.0), "post"], [Vector3(-34.0, 3.0, -10.0), "post"],
		[Vector3(-14.0, -7.0, 7.0), -4.35], [Vector3(-14.0, -7.0, 22.0), -4.35], [Vector3(4.0, -7.0, 8.0), -4.35],
		[Vector3(4.0, -7.0, 22.0), -4.35], [Vector3(-24.5, -7.0, 2.0), -6.4], [Vector3(17.4, -7.0, 15.0), -4.35],
	]
	for i in lamps.size():
		var at: Vector3 = lamps[i][0]
		var mount: Variant = lamps[i][1]
		var crypt := i >= lamps.size() - 6
		if i < 4:
			at.z += castle_gate_z - 9.0
		if fixed != (crypt or mount is String):
			continue
		var tint := witch if crypt else warm
		var light_pos := at
		if mount is Vector3:
			light_pos = _castle_sconce(kit, glow, at, mount)
		elif mount is float:
			_castle_hanging_lantern(kit, glow, at, mount, tint)
		else:
			kit.add_box(Transform3D(Basis.IDENTITY, at + Vector3(0, -0.3, -0.22)), Vector3(0.46, 0.16, 0.32), Color(0.23, 0.16, 0.1))
			kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, -0.72, 0)), 0.085, 0.07, 0.5, 6, Color(0.12, 0.12, 0.11))
			glow.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.55, 0.85, 0.55)), at), 0.22, tint, false, 0.0)
		var outdoor := mount is String
		var energy := 1.15 if crypt else (0.95 if outdoor else 1.7)
		var reach := 12.0 if crypt else (10.0 if outdoor else 11.0)
		_castle_light("CastleLamp_%02d" % i, light_pos, tint, energy, reach, not crypt)
	if fixed:
		return
	# Rooms that had no light of their own.
	var sconces := [
		["HallSconce_W", Vector3(-0.5, 3.6, -10.0), Vector3(1, 0, 0)],
		["HallSconce_E", Vector3(16.5, 3.6, -10.0), Vector3(-1, 0, 0)],
		["ArmorySconce", Vector3(17.5, 3.6, -20.5), Vector3(1, 0, 0)],
		["BarracksSconce", Vector3(-1.5, 15.2, -4.6), Vector3(-1, 0, 0)],
		["StairSconce_Low", Vector3(17.5, 3.6, 1.0), Vector3(1, 0, 0)],
		["StairSconce_Landing", Vector3(24.9, 8.2, 3.6), Vector3(-1, 0, 0)],
	]
	for s in sconces:
		var flame := _castle_sconce(kit, glow, s[1], s[2])
		_castle_light(s[0], flame, warm, 1.7, 11.0, true)
	_castle_light("LibraryCandle", Vector3(-3.4, 1.75, -13.5), Color(1.0, 0.62, 0.32), 0.8, 6.0, true)
	_castle_light("QuartersCandle", Vector3(-8.75, 13.75, -16.2), Color(1.0, 0.62, 0.32), 0.55, 4.5, true)
	for center in [Vector3(8.0, 9.45, -11.0), Vector3(8.0, 19.35, -14.0)]:
		kit.add_cylinder(Transform3D(Basis.IDENTITY, center + Vector3(0, 1.2, 0)), 0.03, 0.03, (12.0 if center.y < 12.0 else 21.7) - center.y - 1.2, 4, FORGED)
		kit.add_cylinder(Transform3D(Basis.IDENTITY, center + Vector3(0, 0.95, 0)), 0.45, 0.32, 0.16, 8, FORGED)
		kit.add_cylinder(Transform3D(Basis.IDENTITY, center + Vector3(0, 0.1, 0)), 0.9, 0.9, 0.06, 12, FORGED, 0.0, 0.0, false)
		for i in 6:
			var angle := TAU * float(i) / 6.0
			var candle: Vector3 = center + Vector3(cos(angle) * 0.8, 0.15, sin(angle) * 0.8)
			kit.add_box(Transform3D(Basis.IDENTITY, center + Vector3(cos(angle) * 0.4, 0.6, sin(angle) * 0.4)), Vector3(0.03, 0.9, 0.03), FORGED)
			kit.add_cylinder(Transform3D(Basis.IDENTITY, candle), 0.06, 0.05, 0.4, 6, Color(0.82, 0.76, 0.6))
			glow.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.42, 0.72, 0.42)), candle + Vector3(0, 0.5, 0)), 0.15, Color(1.0, 0.62, 0.32), false, 0.0)
		_castle_light("Chandelier", center + Vector3(0, 0.65, 0), Color(1.0, 0.58, 0.3), 1.45, 13.0, true)
	# A warm gate wash and a cool crown beacon give the keep a strong night
	# silhouette while the interior lamps keep windows and halls readable.
	_castle_hero_light("HallEntryWash", Vector3(8.0, 7.0, 3.5), Color(1.0, 0.62, 0.34), 1.5, 16.0, false)
	_castle_hero_light("LakewardWindows", Vector3(8.0, 17.4, -21.5), Color(1.0, 0.56, 0.31), 1.0, 13.0, false)
	_castle_hero_light("KeepCrownBeacon", Vector3(8.0, 36.0, -8.0), Color(0.48, 0.65, 0.92), 1.1, 22.0, false)


func _castle_hero_light(light_name: String, local_pos: Vector3, tint: Color,
		energy: float, reach: float, cast_shadows: bool) -> void:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = _origin + local_pos
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.45
	light.light_specular = 0.18
	light.shadow_enabled = cast_shadows
	light.distance_fade_enabled = true
	light.distance_fade_begin = 65.0
	light.distance_fade_length = 24.0
	_site.add_child(light)


## South-east stair hall: two flights and a half landing join the great hall to
## the first floor, entered through new doors in the x = 17 wall on both levels.
func _castle_stair_tower(stone: MeshKit) -> void:
	piece("stairs", Vector3(23.4, 0.55, -5.0), 0, Vector3(3.2, 6.05, 7.6), 0.0, false)
	piece("platform", Vector3(21.3, 5.9, 3.5), 0, Vector3(7.4, 0.7, 1.8), 0.0, false)
	piece("stairs", Vector3(19.4, 6.6, 2.6), 180, Vector3(3.6, 6.1, 8.1), 0.0, false)
	# Spine wall between the flights, and parapets around the stairwell above.
	_castle_wall_between(Vector2(21.5, -4.0), Vector2(21.5, 2.6), 11.45, 0.5, false, 0.55, 0.0)
	_castle_wall_between(Vector2(21.4, -5.5), Vector2(21.4, 1.5), 1.05, 0.35, false, 12.7, 0.0)
	_castle_wall_between(Vector2(17.5, 1.65), Vector2(21.2, 1.65), 1.05, 0.35, false, 12.7, 0.0)
	# Dressed nosing along the open edge of the landing.
	stone.add_box(Transform3D(Basis.IDENTITY, Vector3(21.3, 6.62, 2.62)), Vector3(7.4, 0.08, 0.12), DRESSED)
	# First floor to roof: two more flights (about 38 degrees) and a half landing.
	piece("stairs", Vector3(23.4, 12.7, -4.6), 0, Vector3(3.2, 4.78, 6.0), 0.0, false)
	piece("platform", Vector3(21.3, 16.78, 2.4), 0, Vector3(7.4, 0.7, 2.0), 0.0, false)
	piece("stairs", Vector3(19.4, 17.48, 1.4), 180, Vector3(3.6, 4.78, 6.0), 0.0, false)
	_castle_wall_between(Vector2(21.5, -4.6), Vector2(21.5, 1.4), 9.0, 0.5, false, 12.7, 0.0)
	_castle_wall_between(Vector2(17.6, 3.55), Vector2(25.0, 3.55), 1.05, 0.3, false, 17.48, 0.0)
	stone.add_box(Transform3D(Basis.IDENTITY, Vector3(21.3, 17.5, 1.42)), Vector3(7.4, 0.08, 0.12), DRESSED)
	# Parapets around the stairwell opening on the roof.
	_castle_wall_between(Vector2(17.32, -4.4), Vector2(17.32, -0.6), 1.05, 0.35, false, 22.25, 0.0)
	_castle_wall_between(Vector2(21.38, -4.4), Vector2(21.38, -0.6), 1.05, 0.35, false, 22.25, 0.0)
	_castle_wall_between(Vector2(17.5, -0.42), Vector2(21.2, -0.42), 1.05, 0.35, false, 22.25, 0.0)


## Commander's balcony outside the lakeward door of the north-west chamber.
func _castle_balcony(stone: MeshKit) -> void:
	piece("platform", Vector3(-12.65, 12.0, -17), 0, Vector3(3.5, 0.7, 4.6), 0.0, false)
	for z in [-19.12, -14.88]:
		_castle_wall_between(Vector2(-11, z), Vector2(-14.22, z), 1.05, 0.35, false, 12.7, 0.0)
	_castle_wall_between(Vector2(-14.22, -19.12), Vector2(-14.22, -14.88), 1.05, 0.35, false, 12.7, 0.0)
	for z in [-18.75, -17.0, -15.25]:
		stone.add_box(Transform3D(Basis.IDENTITY, Vector3(-12.4, 11.75, z)), Vector3(2.9, 0.5, 0.5), DRESSED)
		stone.add_box(Transform3D(Basis.IDENTITY, Vector3(-11.8, 11.25, z)), Vector3(1.7, 0.5, 0.45), DRESSED)
		stone.add_box(Transform3D(Basis.IDENTITY, Vector3(-11.4, 10.8, z)), Vector3(0.9, 0.4, 0.4), DRESSED)
	for x in [-11.0, -9.0]:
		for z in [-18.1, -15.9]:
			stone.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 14.55, z)), Vector3(0.3, 3.7, 0.24), DRESSED)
		stone.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 16.5, -17)), Vector3(0.32, 0.3, 2.5), DRESSED)


func _castle_dressing(wood: MeshKit, art: MeshKit, stone: MeshKit, glow: MeshKit) -> void:
	_castle_ceilings(wood, stone)
	_castle_hearth(wood, stone, glow, Vector3(-0.5, 0.55, -15.0), Vector3(1, 0, 0), 3.4, 11.45, "GreatHallHearth", 2.4, 14.0)
	_castle_hearth(wood, stone, glow, Vector3(-9.0, 0.55, 1.6), Vector3(1, 0, 0), 2.6, 11.45, "KitchenHearth", 1.7, 10.0)
	_castle_hearth(wood, stone, glow, Vector3(-5.4, 12.7, -22.1), Vector3(0, 0, 1), 1.6, 18.6, "QuartersHearth", 1.3, 9.0)
	# Doors: timber tympana fill the tall stone openings above head height, and
	# iron-strapped leaves stand open against the wall.
	_castle_door(wood, Vector3(-1.0, 0.55, -1.4), Vector3(-1, 0, 0), 3.6, 3.85, 7.0, true)
	_castle_door(wood, Vector3(17.0, 0.55, -14.6), Vector3(1, 0, 0), 4.0, 3.85, 7.0, true)
	_castle_door(wood, Vector3(-1.0, 12.7, -1.4), Vector3(-1, 0, 0), 3.6, 3.5, 6.0, true)
	_castle_door(wood, Vector3(17.0, 0.55, -5.0), Vector3(1, 0, 0), 2.2, 3.25, 3.25, false, 0.5, true, -1.0)
	_castle_door(wood, Vector3(-3.0, 0.55, -7.0), Vector3(0, 0, -1), 1.8, 3.05, 3.05, false)
	_castle_door(wood, Vector3(-10, 12.7, -17), Vector3(-1, 0, 0), 1.9, 3.6, 3.6, true, 0.9, false)
	# Great hall heraldry: banners on the end walls, shields on the arcade wall.
	for x in [4.0, 12.0]:
		_castle_banner_hanging(wood, Vector3(x, 10.2, -21.95), Vector3(0, 0, 1), 1.7, 5.6)
		_castle_banner_hanging(wood, Vector3(x, 20.6, -22.05), Vector3(0, 0, 1), 1.5, 4.6)
	_castle_banner_hanging(wood, Vector3(14.6, 9.6, 5.95), Vector3(0, 0, -1), 1.6, 5.0)
	for x in [1.8, 14.2]:
		_castle_shield(wood, Vector3(x, 4.6, -6.45), Vector3(0, 0, 1), x < 8.0)
		_castle_shield(wood, Vector3(x, 4.6, -7.55), Vector3(0, 0, -1), x > 8.0)
	_castle_weapon_rack(wood, Vector3(15.2, 0.55, 5.55), PI)
	_castle_weapon_rack(wood, Vector3(0.8, 0.55, 5.55), PI)
	_castle_chest(wood, Vector3(15.6, 0.55, 3.2), PI * 0.5, 1.2)
	_castle_chest(wood, Vector3(0.3, 0.55, 3.2), -PI * 0.5, 1.2)
	# Armory wall of shields and a dummy.
	for i in 4:
		_castle_shield(wood, Vector3(18.8 + float(i) * 1.6, 3.4, -21.95), Vector3(0, 0, 1), i % 2 == 0)
	# Kitchen: barrels, sacks and a pot shelf.
	for p in [Vector3(-8.2, 0.55, -5.6), Vector3(-7.0, 0.55, -5.8), Vector3(-8.3, 0.55, -4.4)]:
		_castle_barrel(wood, p)
	for p in [Vector3(-2.4, 0.55, 5.2), Vector3(-3.1, 0.55, 5.4)]:
		wood.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.38, 0.5, 0.32)), p + Vector3(0, 0.45, 0)), 1.0, tagged(Color(0.5, 0.42, 0.3), SURF_CLOTH), true, 0.12)
	for y in [1.6, 2.4]:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-1.75, y, 3.6)), Vector3(0.4, 0.06, 2.6), OAK)
		for i in 4:
			wood.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(-1.78, y + 0.03, 2.6 + float(i) * 0.65)), 0.13, 0.1, 0.26, 8, Color(0.42, 0.26, 0.16) if i % 2 == 0 else tagged(Color(0.3, 0.3, 0.29), SURF_IRON))
	# Library reading desk.
	_castle_table(wood, Vector3(-3.6, 0.55, -14.0), 1.8, 0.9, 0.85, PI * 0.5)
	_castle_chair(wood, Vector3(-4.6, 0.55, -14.0), -PI * 0.5)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-3.6, 1.42, -14.2)), Vector3(0.45, 0.04, 0.6), tagged(Color(0.72, 0.66, 0.52), SURF_CLOTH))
	_castle_candle(wood, glow, Vector3(-3.4, 1.4, -13.5))
	# Barracks: plank floor, weapon rack, table.
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-5.3, 12.725, -0.3)), Vector3(7.6, 0.05, 12.4), PLANKS)
	_castle_weapon_rack(wood, Vector3(-2.0, 12.7, 3.9), -PI * 0.5)
	_castle_quarters(wood, art, glow)
	# Roof: Princess Reve's place at the north-west parapet, facing the moon over the
	# lake, with a brazier for warm fill and a torch by the stairwell.
	story_anchors["roof_reve"] = {"pos": _origin + Vector3(-5.85, 22.25, -21.25), "yaw": PI * 0.2}
	# The King holds council from the old lord's chair on the great hall's dais
	# (its seat is 0.57 m above the dais), facing down the hall; the commander
	# stands before the high table.
	story_anchors["king_throne"] = {"pos": _origin + Vector3(8.0, 0.89, -21.68), "yaw": PI}
	story_anchors["king_audience"] = {"pos": _origin + Vector3(8.0, 0.89, -19.45), "yaw": 0.0}
	story_anchors["castle_courtyard"] = {"pos": _origin + Vector3(8.0, 0.55, 12.0), "yaw": 0.0}
	piece("brazier", Vector3(-7.6, 22.25, -18.8), 0, Vector3.ONE, 0.0, false)
	for x in [2.6, 13.4]:
		var door_flame := _castle_sconce(wood, glow, Vector3(x, 3.4, 8.0), Vector3(0, 0, 1))
		_castle_light("KeepDoorTorch", door_flame, Color(1.0, 0.56, 0.27), 1.6, 12.0, true)
	for x in [-1.0, 17.0]:
		piece("brazier", Vector3(x, 0.0, 12.5), 0, Vector3.ONE)
	var exit_flame := _castle_sconce(wood, glow, Vector3(15.4, 23.9, -3.0), Vector3(1, 0, 0))
	_castle_light("RoofSconce", exit_flame, Color(1.0, 0.56, 0.27), 1.3, 9.0, true)


## Timber beams under the first floor and roof, with stone corbels; the
## chambers on the first floor get a lower boarded ceiling.
func _castle_ceilings(wood: MeshKit, stone: MeshKit) -> void:
	for i in 11:
		var z := -21.0 + float(i) * 2.6
		if absf(z + 7.0) < 0.8:
			continue
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(8.0, 11.72, z)), Vector3(17.0, 0.55, 0.42), DARK_OAK)
		for x in [-0.25, 16.25]:
			stone.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 11.15, z)), Vector3(0.5, 0.6, 0.5), DRESSED)
		if z < -7.0:
			for x in [-5.25, 21.25]:
				wood.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 11.75, z)), Vector3(7.6, 0.45, 0.36), DARK_OAK)
		else:
			wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-5.25, 11.75, z)), Vector3(7.6, 0.45, 0.36), DARK_OAK)
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(8.0, 21.45, z)), Vector3(17.0, 0.5, 0.4), DARK_OAK)
	for x in [4.0, 12.0]:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 11.2, -8.0)), Vector3(0.55, 0.5, 28.0), DARK_OAK)
	# Boarded ceilings at 18.6 m over the commander's chamber and the barracks.
	for zc in [[-14.8, 14.6], [-0.3, 12.4]]:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-5.3, 18.66, float(zc[0]))), Vector3(7.6, 0.12, float(zc[1])), PLANKS)
		var count := int(float(zc[1]) / 2.2)
		for i in count:
			var z: float = float(zc[0]) - float(zc[1]) * 0.5 + 1.1 + float(i) * 2.2
			wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-5.3, 18.42, z)), Vector3(7.6, 0.36, 0.3), DARK_OAK)


## Stone fireplace against a wall. `at` is the wall face at floor level and
## `normal` points into the room.
func _castle_hearth(wood: MeshKit, stone: MeshKit, glow: MeshKit, at: Vector3, normal: Vector3,
		width: float, ceiling: float, light_name: String, energy: float, reach: float) -> void:
	var b := Basis(Vector3.UP, atan2(normal.x, normal.z))
	var p := func(local: Vector3) -> Vector3: return at + b * local
	var soot := Color(0.05, 0.045, 0.04)
	for side in [-1.0, 1.0]:
		stone.add_box(Transform3D(b, p.call(Vector3(side * (width * 0.5 + 0.25), 1.0, 0.45))), Vector3(0.5, 2.0, 0.9), DRESSED)
	stone.add_box(Transform3D(b, p.call(Vector3(0, 2.25, 0.5))), Vector3(width + 1.1, 0.5, 1.0), DRESSED)
	stone.add_box(Transform3D(b, p.call(Vector3(0, 2.55, 0.55))), Vector3(width + 1.4, 0.1, 1.1), shade(DRESSED, 0.85))
	var hood_h := ceiling - at.y - 2.6
	stone.add_box(Transform3D(b, p.call(Vector3(0, 2.6 + hood_h * 0.5, 0.35))), Vector3(width * 0.75, hood_h, 0.7), DRESSED)
	stone.add_box(Transform3D(b, p.call(Vector3(0, 1.0, 0.03))), Vector3(width, 2.0, 0.06), soot)
	stone.add_box(Transform3D(b, p.call(Vector3(0, 0.03, 0.75))), Vector3(width + 1.0, 0.06, 1.5), shade(DRESSED, 0.7))
	for side in [-1.0, 1.0]:
		wood.add_box(Transform3D(b, p.call(Vector3(side * width * 0.28, 0.3, 0.45))), Vector3(0.08, 0.5, 0.6), FORGED)
	for i in 3:
		var log_basis := b * Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, 0.2 * float(i - 1))
		wood.add_cylinder(Transform3D(log_basis, p.call(Vector3(-width * 0.32, 0.2 + float(i % 2) * 0.16, 0.35 + float(i) * 0.12))), 0.11, 0.1, width * 0.64, 7, shade(DARK_OAK, 0.6))
	glow.add_blob(Transform3D(b.scaled(Vector3(width * 0.32, 0.12, 0.35)), p.call(Vector3(0, 0.18, 0.45))), 1.0, Color(1.0, 0.36, 0.12), false, 0.0)
	for i in 5:
		var fx := (float(i) - 2.0) * width * 0.11
		glow.add_cylinder(Transform3D(b, p.call(Vector3(fx, 0.25, 0.45 + 0.05 * float(i % 2)))), 0.13, 0.0, 0.5 + 0.18 * float((i * 3) % 4), 4, Color(1.0, 0.62, 0.28))
	var light := _castle_light(light_name, at + b * Vector3(0, 1.1, 1.1), Color(1.0, 0.5, 0.22), energy, reach, true)
	light.omni_attenuation = 1.25


## Door in a wall opening. `at` is the opening centre on the wall axis at floor
## level, `normal` the side the leaves open towards; with a tympanum the stone
## opening above `leaf_h` is closed by boards up to `opening_h`.
func _castle_door(wood: MeshKit, at: Vector3, normal: Vector3, width: float, leaf_h: float,
		opening_h: float, double_leaf: bool, half_thick := 0.5, frame := true, leaf_side := 1.0) -> void:
	var b := Basis(Vector3.UP, atan2(normal.x, normal.z))
	var along := b * Vector3.RIGHT
	if frame:
		wood.add_box(Transform3D(b, at + Vector3(0, leaf_h + 0.12, 0)), Vector3(width + 0.3, 0.24, half_thick * 2.0 + 0.15), DARK_OAK)
		for side in [-1.0, 1.0]:
			wood.add_box(Transform3D(b, at + along * side * (width * 0.5 - 0.06) + Vector3(0, leaf_h * 0.5, 0)), Vector3(0.12, leaf_h, half_thick * 2.0 + 0.1), DARK_OAK)
	if opening_h > leaf_h + 0.4:
		var th := opening_h - leaf_h - 0.24
		wood.add_box(Transform3D(b, at + Vector3(0, leaf_h + 0.24 + th * 0.5 - 0.55, 0)), Vector3(width, th, 0.16), PLANKS)
		for i in int(width / 0.9):
			var x := -width * 0.5 + 0.45 + float(i) * 0.9
			wood.add_box(Transform3D(b, at + along * x + Vector3(0, leaf_h + 0.24 + th * 0.5 - 0.55, 0)), Vector3(0.1, th, 0.2), DARK_OAK)
	var leaves: Array[float] = [-1.0, 1.0]
	if not double_leaf:
		leaves = [leaf_side]
	var leaf_w := width * 0.5 if double_leaf else width
	for side in leaves:
		var hinge: Vector3 = at + along * side * width * 0.5 + normal * (half_thick + 0.08)
		var centre: Vector3 = hinge + along * side * (leaf_w * 0.5) + normal * 0.07
		var lb := b
		wood.add_box(Transform3D(lb, centre + Vector3(0, leaf_h * 0.5 - 0.02, 0)), Vector3(leaf_w - 0.04, leaf_h - 0.06, 0.1), PLANKS)
		for y in [0.45, leaf_h * 0.5, leaf_h - 0.45]:
			wood.add_box(Transform3D(lb, centre + Vector3(0, y, 0) + normal * 0.06), Vector3(leaf_w - 0.1, 0.08, 0.025), FORGED)
		wood.add_cylinder(Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), centre - along * side * leaf_w * 0.3 + Vector3(0, leaf_h * 0.45, 0) + normal * 0.09), 0.09, 0.09, 0.02, 10, FORGED, 0.0, 0.0, false)


func _castle_banner_hanging(kit: MeshKit, top: Vector3, normal: Vector3, width: float, length: float,
		cloth := CRIMSON, trim := GOLD_TRIM) -> void:
	var b := Basis(Vector3.UP, atan2(normal.x, normal.z))
	var along := b * Vector3.RIGHT
	var off := normal * 0.07
	kit.add_cylinder(Transform3D(b * Basis(Vector3.FORWARD, PI * 0.5), top + off - along * (width * 0.5 + 0.15) + Vector3(0, 0.05, 0)), 0.04, 0.04, width + 0.3, 6, FORGED)
	kit.add_box(Transform3D(b, top + off + Vector3(0, -length * 0.5, 0)), Vector3(width, length, 0.04), cloth)
	for side in [-1.0, 1.0]:
		kit.add_box(Transform3D(b, top + off + along * side * (width * 0.5 - 0.06) + Vector3(0, -length * 0.5, 0) + normal * 0.01), Vector3(0.08, length, 0.04), trim)
	# A pale tower: the house of the shore lords.
	var badge := top + off + normal * 0.02 + Vector3(0, -length * 0.42, 0)
	var pale := tagged(Color(0.7, 0.66, 0.55), SURF_CLOTH)
	kit.add_box(Transform3D(b, badge), Vector3(width * 0.32, width * 0.5, 0.03), pale)
	for x in [-1.0, 0.0, 1.0]:
		kit.add_box(Transform3D(b, badge + along * x * width * 0.11 + Vector3(0, width * 0.29, 0)), Vector3(width * 0.08, width * 0.1, 0.03), pale)
	for side in [-1.0, 1.0]:
		kit.add_tri(top + off + along * side * width * 0.5 + Vector3(0, -length, 0) + normal * 0.021,
			top + off + along * side * width * 0.05 + Vector3(0, -length, 0) + normal * 0.021,
			top + off + along * side * width * 0.28 + Vector3(0, -length - width * 0.4, 0) + normal * 0.021, cloth)
		kit.add_tri(top + off + along * side * width * 0.05 + Vector3(0, -length, 0) + normal * 0.021,
			top + off + along * side * width * 0.5 + Vector3(0, -length, 0) + normal * 0.021,
			top + off + along * side * width * 0.28 + Vector3(0, -length - width * 0.4, 0) + normal * 0.021, cloth)


func _castle_shield(kit: MeshKit, at: Vector3, normal: Vector3, with_spears: bool) -> void:
	var b := Basis(Vector3.UP, atan2(normal.x, normal.z))
	var face := b * Basis(Vector3.RIGHT, PI * 0.5)
	if with_spears:
		for s in [-1.0, 1.0]:
			kit.add_cylinder(Transform3D(b * Basis(Vector3.BACK, s * 0.6), at + normal * 0.06 + Vector3(0, -1.3, 0) + b * Vector3(s * 0.95, 0, 0)), 0.035, 0.03, 2.8, 6, DARK_OAK)
			kit.add_cylinder(Transform3D(b * Basis(Vector3.BACK, s * 0.6), at + normal * 0.06 + b * Vector3(-s * 0.68, 1.3, 0) - Vector3(0, 0.1, 0)), 0.05, 0.0, 0.35, 4, FORGED)
	kit.add_cylinder(Transform3D(face, at + normal * 0.08), 0.6, 0.6, 0.06, 14, OAK)
	kit.add_cylinder(Transform3D(face, at + normal * 0.09), 0.62, 0.62, 0.03, 14, FORGED, 0.0, 0.0, false)
	kit.add_cylinder(Transform3D(face, at + normal * 0.115), 0.5, 0.5, 0.02, 14, CRIMSON if with_spears else tagged(Color(0.12, 0.18, 0.26), SURF_CLOTH))
	kit.add_blob(Transform3D(face.scaled(Vector3(0.14, 0.08, 0.14)), at + normal * 0.16), 1.0, FORGED, false, 0.0)


func _castle_weapon_rack(kit: MeshKit, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	for x in [-0.8, 0.8]:
		kit.add_box(Transform3D(b, at + b * Vector3(x, 0.9, 0)), Vector3(0.1, 1.8, 0.35), DARK_OAK)
	for y in [0.25, 1.15]:
		kit.add_box(Transform3D(b, at + b * Vector3(0, y, 0)), Vector3(1.7, 0.08, 0.4), OAK)
	for i in 5:
		var x := -0.6 + float(i) * 0.3
		kit.add_cylinder(Transform3D(b * Basis(Vector3.RIGHT, -0.12), at + b * Vector3(x, 0.2, 0.05)), 0.025, 0.025, 2.1, 5, DARK_OAK)
		kit.add_cylinder(Transform3D(b * Basis(Vector3.RIGHT, -0.12), at + b * Vector3(x, 2.28, -0.2)), 0.045, 0.0, 0.3, 4, FORGED)


func _castle_barrel(kit: MeshKit, at: Vector3) -> void:
	kit.add_cylinder(Transform3D(Basis.IDENTITY, at), 0.36, 0.42, 0.5, 10, OAK)
	kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.5, 0)), 0.42, 0.36, 0.5, 10, OAK)
	for y in [0.12, 0.5, 0.88]:
		kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, y - 0.03, 0)), 0.4 + (0.03 if absf(y - 0.5) < 0.1 else 0.0), 0.4 + (0.03 if absf(y - 0.5) < 0.1 else 0.0), 0.06, 10, FORGED, 0.0, 0.0, false)


func _castle_candle(kit: MeshKit, glow: MeshKit, at: Vector3) -> void:
	kit.add_cylinder(Transform3D(Basis.IDENTITY, at), 0.08, 0.06, 0.03, 8, tagged(Color(0.5, 0.4, 0.22), SURF_IRON))
	kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.03, 0)), 0.035, 0.035, 0.2, 6, Color(0.82, 0.76, 0.6))
	glow.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.03, 0.06, 0.03)), at + Vector3(0, 0.28, 0)), 1.0, Color(1.0, 0.7, 0.35), false, 0.0)


## The commander's bedroom (first floor, north-west): a soldier's room, not a
## royal one. Plain oak bed against the partition, campaign desk under the west
## window, wardrobe, armour stand, washstand, weapon rack, hearth and a worn rug;
## the west door opens onto the balcony.
func _castle_quarters(wood: MeshKit, art: MeshKit, glow: MeshKit) -> void:
	var f := 12.7
	var wool := tagged(Color(0.3, 0.28, 0.25), SURF_CLOTH)
	var wool_dark := tagged(Color(0.19, 0.18, 0.17), SURF_CLOTH)
	var steel := tagged(Color(0.44, 0.45, 0.46), SURF_IRON)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-5.3, f + 0.025, -14.8)), Vector3(7.6, 0.05, 14.6), PLANKS)
	# Worn wool rug.
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-4.4, f + 0.055, -12.5)), Vector3(3.0, 0.02, 3.8), tagged(Color(0.27, 0.2, 0.15), SURF_CLOTH))
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-4.4, f + 0.06, -12.5)), Vector3(2.6, 0.02, 3.4), tagged(Color(0.33, 0.26, 0.19), SURF_CLOTH))
	# Sturdy oak bed, head against the east partition: wool blankets and a fur.
	var bx := -2.75
	var bz := -12.5
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(bx, f + 0.36, bz)), Vector3(2.2, 0.22, 1.5), OAK)
	for x in [bx - 1.05, bx + 1.05]:
		for dz in [-0.7, 0.7]:
			wood.add_box(Transform3D(Basis.IDENTITY, Vector3(x, f + 0.3, bz + dz)), Vector3(0.12, 0.6, 0.12), DARK_OAK)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-1.64, f + 0.75, bz)), Vector3(0.1, 0.9, 1.55), DARK_OAK)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(bx - 1.1, f + 0.5, bz)), Vector3(0.08, 0.35, 1.5), DARK_OAK)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(bx, f + 0.56, bz)), Vector3(2.05, 0.18, 1.38), LINEN)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(bx - 0.25, f + 0.67, bz)), Vector3(1.5, 0.06, 1.44), wool)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(bx + 0.78, f + 0.7, bz)), Vector3(0.36, 0.12, 0.9), tagged(Color(0.64, 0.6, 0.53), SURF_CLOTH))
	wood.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.42, 0.06, 0.62)), Vector3(bx - 0.75, f + 0.72, bz + 0.05)), 1.0, tagged(Color(0.3, 0.22, 0.15), SURF_CLOTH), true, 0.15)
	_castle_chest(wood, Vector3(bx - 1.65, f, bz), PI * 0.5, 1.2)
	# Boots by the bed.
	for dz in [-0.12, 0.12]:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-4.1, f + 0.17, bz + 1.15 + dz)), Vector3(0.24, 0.34, 0.1), tagged(Color(0.22, 0.14, 0.09), SURF_CLOTH))
	# Bedside table with a candle.
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-2.0, f + 0.32, -10.95)), Vector3(0.5, 0.64, 0.45), OAK)
	_castle_candle(wood, glow, Vector3(-2.0, f + 0.64, -10.95))
	# Campaign desk under the north window: a marked map, letters, inkwell, dagger.
	_castle_table(wood, Vector3(-2.8, f, -21.5), 1.9, 0.95, 0.8, 0.0)
	_castle_chair(wood, Vector3(-2.8, f, -20.55), 0.0)
	wood.add_box(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-2.7, f + 0.808, -21.5)), Vector3(0.72, 0.012, 1.1), tagged(Color(0.66, 0.58, 0.42), SURF_CLOTH))
	for m in [Vector3(-2.45, 0, -21.35), Vector3(-2.8, 0, -21.6), Vector3(-3.05, 0, -21.45)]:
		wood.add_cylinder(Transform3D(Basis.IDENTITY, m + Vector3(0, f + 0.815, 0)), 0.025, 0.02, 0.05, 6, Color(0.42, 0.08, 0.06))
	wood.add_box(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-3.45, f + 0.82, -21.7)), Vector3(0.26, 0.02, 0.34), tagged(Color(0.72, 0.66, 0.54), SURF_CLOTH))
	wood.add_cylinder(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-2.05, f + 0.8, -21.78)), 0.04, 0.035, 0.07, 8, Color(0.06, 0.06, 0.07))
	wood.add_box(Transform3D(Basis(Vector3.UP, 0.4 - PI * 0.5), Vector3(-3.2, f + 0.815, -21.3)), Vector3(0.04, 0.02, 0.32), steel)
	_castle_candle(wood, glow, Vector3(-3.75, f + 0.8, -21.75))
	# Wardrobe on the west wall, washstand beside it.
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-8.65, f + 1.15, -11.0)), Vector3(0.7, 2.3, 1.7), PLANKS)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-8.62, f + 2.36, -11.0)), Vector3(0.82, 0.12, 1.85), DARK_OAK)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-8.29, f + 1.2, -11.0)), Vector3(0.02, 2.0, 0.04), DARK_OAK)
	for dz in [-0.12, 0.12]:
		wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-8.27, f + 1.25, -11.0 + dz)), Vector3(0.04, 0.16, 0.04), FORGED)
	wood.add_box(Transform3D(Basis.IDENTITY, Vector3(-8.7, f + 0.42, -13.4)), Vector3(0.5, 0.84, 0.6), OAK)
	wood.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(-8.7, f + 0.84, -13.4)), 0.2, 0.15, 0.1, 10, tagged(Color(0.48, 0.42, 0.34), SURF_IRON))
	wood.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(-8.78, f + 0.84, -13.25)), 0.06, 0.08, 0.24, 8, Color(0.52, 0.4, 0.28))
	# Armour stand: breastplate, pauldrons, helm, a plain wool cloak and a sheathed sword.
	var a := Vector3(-7.4, f, -8.7)
	wood.add_box(Transform3D(Basis.IDENTITY, a + Vector3(0, 0.03, 0)), Vector3(0.6, 0.06, 0.6), DARK_OAK)
	wood.add_box(Transform3D(Basis.IDENTITY, a + Vector3(0, 0.85, 0)), Vector3(0.07, 1.65, 0.07), DARK_OAK)
	wood.add_box(Transform3D(Basis.IDENTITY, a + Vector3(0, 1.45, 0)), Vector3(0.62, 0.06, 0.06), DARK_OAK)
	wood.add_cylinder(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.62)), a + Vector3(0, 0.95, 0)), 0.17, 0.22, 0.5, 10, steel)
	wood.add_cylinder(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.62)), a + Vector3(0, 0.85, 0)), 0.18, 0.17, 0.1, 10, tagged(Color(0.22, 0.15, 0.1), SURF_CLOTH))
	for s in [-1.0, 1.0]:
		wood.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.13, 0.08, 0.12)), a + Vector3(s * 0.26, 1.44, 0)), 1.0, steel, true, 0.0)
	wood.add_cylinder(Transform3D(Basis.IDENTITY, a + Vector3(0, 1.52, 0)), 0.12, 0.12, 0.16, 10, steel)
	wood.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.12, 0.09, 0.12)), a + Vector3(0, 1.68, 0)), 1.0, steel, true, 0.0)
	wood.add_box(Transform3D(Basis.IDENTITY, a + Vector3(0, 1.55, 0.02)), Vector3(0.2, 0.025, 0.25), Color(0.04, 0.04, 0.04))
	wood.add_box(Transform3D(Basis(Vector3.RIGHT, 0.05), a + Vector3(0, 0.88, 0.17)), Vector3(0.6, 1.1, 0.04), wool_dark)
	wood.add_box(Transform3D(Basis(Vector3.BACK, 0.18), a + Vector3(0.42, 0.55, 0.05)), Vector3(0.06, 1.0, 0.05), tagged(Color(0.2, 0.13, 0.08), SURF_CLOTH))
	wood.add_box(Transform3D(Basis(Vector3.BACK, 0.18), a + Vector3(0.33, 1.08, 0.05)), Vector3(0.2, 0.03, 0.04), steel)
	_castle_shield(wood, Vector3(-9.04, f + 1.9, -14.6), Vector3(1, 0, 0), false)
	_castle_weapon_rack(wood, Vector3(-8.85, f, -8.7), PI * 0.5)
	# The commander's company pennant above the bed: slate blue, a pale tower.
	_castle_banner_hanging(wood, Vector3(-1.52, f + 4.8, bz), Vector3(-1, 0, 0), 1.0, 1.9,
		tagged(Color(0.12, 0.16, 0.22), SURF_CLOTH), tagged(Color(0.42, 0.42, 0.4), SURF_CLOTH))
	# Moonlight spilling through the west window.
	var moon := _castle_light("QuartersMoonSpill", Vector3(-8.2, f + 3.0, -17.0), Color(0.55, 0.65, 0.9), 0.35, 5.5, false)
	moon.light_specular = 0.1
	story_anchors["commander_desk"] = _origin + Vector3(-2.8, f + 0.95, -21.5)


## Iron sconce with a burning torch. `at` is the wall face at mount height and
## `normal` points into the room.
func _castle_sconce(kit: MeshKit, glow: MeshKit, at: Vector3, normal: Vector3) -> Vector3:
	var b := Basis(Vector3.UP, atan2(normal.x, normal.z))
	kit.add_box(Transform3D(b, at + normal * 0.03), Vector3(0.2, 0.42, 0.06), FORGED)
	kit.add_box(Transform3D(b * Basis(Vector3.RIGHT, -0.7), at + normal * 0.2 + Vector3(0, 0.02, 0)), Vector3(0.05, 0.05, 0.42), FORGED)
	kit.add_cylinder(Transform3D(b, at + normal * 0.36 + Vector3(0, 0.08, 0)), 0.05, 0.08, 0.14, 6, FORGED)
	kit.add_cylinder(Transform3D(b * Basis(Vector3.RIGHT, 0.15), at + normal * 0.33 - Vector3(0, 0.2, 0)), 0.035, 0.045, 0.5, 6, DARK_OAK)
	var flame := at + normal * 0.4 + Vector3(0, 0.36, 0)
	glow.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.09, 0.13, 0.09)), flame), 1.0, Color(1.0, 0.55, 0.22), false, 0.0)
	glow.add_cylinder(Transform3D(Basis.IDENTITY, flame), 0.07, 0.0, 0.3, 4, Color(1.0, 0.72, 0.36))
	return flame + normal * 0.12 + Vector3(0, 0.1, 0)


## Iron cage lantern on a chain up to `ceiling`.
func _castle_hanging_lantern(kit: MeshKit, glow: MeshKit, at: Vector3, ceiling: float, tint: Color) -> void:
	if ceiling > at.y + 0.4:
		kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.32, 0)), 0.02, 0.02, ceiling - at.y - 0.32, 4, FORGED)
	kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, 0.18, 0)), 0.2, 0.05, 0.16, 6, FORGED)
	kit.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3(0, -0.3, 0)), 0.17, 0.17, 0.05, 6, FORGED)
	for i in 4:
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		kit.add_box(Transform3D(Basis.IDENTITY, at + Vector3(cos(ang) * 0.15, -0.06, sin(ang) * 0.15)), Vector3(0.025, 0.48, 0.025), FORGED)
	glow.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.55, 0.85, 0.55)), at - Vector3(0, 0.05, 0)), 0.2, tint, false, 0.0)


func _castle_light(light_name: String, local_pos: Vector3, tint: Color, energy: float, reach: float, flicker: bool) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = _origin + local_pos
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.35
	light.light_specular = 0.35
	light.distance_fade_enabled = true
	light.distance_fade_begin = 48.0
	light.distance_fade_length = 14.0
	light.add_to_group("day_night_lights")
	_site.add_child(light)
	if flicker:
		_flicker.append({"light": light, "base": energy, "phase": float(_flicker.size()) * 1.7})
	return light


func _castle_crypt(stone: MeshKit, dark: MeshKit, art: MeshKit) -> void:
	var floor_y := -12.15
	var floor_top := floor_y + 0.5
	# Lower hoist chamber; the corridor dog-legs toward the ossuary beneath the
	# courtyard, keeping the secret route easy to follow once at the bottom.
	# Leave a full shaft opening through the hoist-room floor. A single slab here
	# used to overlap the carriage at the lower landing and trap it in the floor.
	piece("platform", Vector3(-11.15, floor_y, 15.0), 0, Vector3(7.7, 0.5, 22.0), 0.0, false)
	piece("platform", Vector3(1.15, floor_y, 15.0), 0, Vector3(7.7, 0.5, 22.0), 0.0, false)
	piece("platform", Vector3(-5.0, floor_y, 8.35), 0, Vector3(4.6, 0.5, 8.7), 0.0, false)
	piece("platform", Vector3(-5.0, floor_y, 21.65), 0, Vector3(4.6, 0.5, 8.7), 0.0, false)
	piece("platform", Vector3(-19.0, floor_y, 15.0), 0, Vector3(9.0, 0.5, 4.5), 0.0, false)
	piece("platform", Vector3(-23.0, floor_y, 3.5), 0, Vector3(4.6, 0.5, 20.5), 0.0, false)
	piece("platform", Vector3(-19.0, -6.8, 15.0), 0, Vector3(9.0, 0.4, 4.7), 0.0, false)
	piece("platform", Vector3(-23.0, -6.8, 3.5), 0, Vector3(4.8, 0.4, 20.5), 0.0, false)
	_castle_wall_between(Vector2(-15.0, 4.0), Vector2(5.0, 4.0), 8.0, 1.2, false, floor_top)
	_castle_wall_between(Vector2(5.0, 4.0), Vector2(5.0, 11.0), 8.0, 1.2, false, floor_top)
	_castle_wall_openings(Vector2(5.0, 11.0), Vector2(5.0, 19.0), 8.0, 1.2, floor_top,
		[{"t": 0.5, "width": 4.0, "sill": 0.0, "height": 5.6}], false)
	_castle_wall_between(Vector2(5.0, 19.0), Vector2(5.0, 26.0), 8.0, 1.2, false, floor_top)
	_castle_wall_between(Vector2(5.0, 26.0), Vector2(-15.0, 26.0), 8.0, 1.2, false, floor_top)
	_castle_wall_between(Vector2(-15.0, 26.0), Vector2(-15.0, 18.0), 8.0, 1.2, false, floor_top)
	_castle_wall_between(Vector2(-15.0, 12.0), Vector2(-15.0, 4.0), 8.0, 1.2, false, floor_top)
	piece("arch", Vector3(5.0, floor_top, 15.0), 90, Vector3(4.0, 5.6, 1.4), 0.0, false)
	# Tunnel sides and roof lead north to the old bone jail.
	_castle_wall_between(Vector2(-14.5, 12.6), Vector2(-23.0, 12.6), 4.8, 0.9, false, floor_top)
	_castle_wall_between(Vector2(-14.5, 17.4), Vector2(-23.0, 17.4), 4.8, 0.9, false, floor_top)
	_castle_wall_between(Vector2(-25.2, 13.0), Vector2(-25.2, -6.0), 4.8, 0.9, false, floor_top)
	_castle_wall_between(Vector2(-20.8, 13.0), Vector2(-20.8, -6.0), 4.8, 0.9, false, floor_top)
	# Deep prison room, cells and three more sets of remains.
	piece("platform", Vector3(-24.0, floor_y, -15.5), 0, Vector3(24.0, 0.5, 19.0), 0.0, false)
	_castle_wall_between(Vector2(-36.0, -25.0), Vector2(-12.0, -25.0), 7.5, 1.3, false, floor_top)
	_castle_wall_between(Vector2(-36.0, -25.0), Vector2(-36.0, -6.0), 7.5, 1.3, false, floor_top)
	_castle_wall_openings(Vector2(-12.0, -25.0), Vector2(-12.0, -6.0), 7.5, 1.3, floor_top,
		[{"t": 0.5, "width": 4.2, "sill": 0.0, "height": 5.6}], false)
	_castle_wall_openings(Vector2(-36.0, -6.0), Vector2(-12.0, -6.0), 7.5, 1.3, floor_top,
		[{"t": 13.0 / 24.0, "width": 4.0, "sill": 0.0, "height": 5.4}], false)
	piece("arch", Vector3(-24.0, floor_top, -6.0), 0, Vector3(4.0, 5.4, 1.6), 0.0, false)
	_castle_wall_between(Vector2(-28.0, -25.0), Vector2(-28.0, -6.3), 6.7, 0.9, false, floor_top)
	_castle_wall_openings(Vector2(-20.0, -25.0), Vector2(-20.0, -6.3), 6.7, 0.9, floor_top,
		[{"t": 0.5, "width": 3.8, "sill": 0.0, "height": 5.5}], false)
	piece("arch", Vector3(-20.0, floor_top, -15.65), 90, Vector3(3.8, 5.5, 1.2), 0.0, false)
	var bones := MeshKit.new(_seed + 931, 0.035)
	var sockets := MeshKit.new(_seed + 932)
	for x in [-32.0, -24.0, -16.0]:
		var broken_gate := is_equal_approx(float(x), -24.0)
		var gate_z := -7.15
		for j in 11:
			if broken_gate and j == 5:
				continue
			var bx: float = x - 3.5 + float(j) * 0.7
			stone.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(bx, floor_top, gate_z)), 0.07, 0.06, 5.6, 6, IRON)
		if broken_gate:
			for rail_y in [floor_top + 2.9, floor_top + 0.9]:
				for rail_start in [x - 3.5, x + 0.65]:
					stone.add_cylinder(Transform3D(Landmark.basis_y(Vector3(2.85, 0, 0)),
						Vector3(rail_start, rail_y, gate_z)), 0.09, 0.09, 2.85, 6, IRON)
		else:
			stone.add_cylinder(Transform3D(Landmark.basis_y(Vector3(7.0, 0, 0)), Vector3(x - 3.5, floor_top + 2.9, gate_z)), 0.09, 0.09, 7.0, 6, IRON)
			stone.add_cylinder(Transform3D(Landmark.basis_y(Vector3(7.0, 0, 0)), Vector3(x - 3.5, floor_top + 0.9, gate_z)), 0.09, 0.09, 7.0, 6, IRON)
		var cell_body := StaticBody3D.new()
		cell_body.position = _origin
		cell_body.collision_layer = Layers.WORLD
		cell_body.collision_mask = 0
		if broken_gate:
			for side in [-1.0, 1.0]:
				var broken_shape := BoxShape3D.new()
				broken_shape.size = Vector3(2.85, 5.8, 0.32)
				var broken_collision := CollisionShape3D.new()
				broken_collision.shape = broken_shape
				broken_collision.position = Vector3(x + side * 2.075, floor_top + 3.0, gate_z)
				cell_body.add_child(broken_collision)
		else:
			var full_shape := BoxShape3D.new()
			full_shape.size = Vector3(7.1, 5.8, 0.32)
			var full_collision := CollisionShape3D.new()
			full_collision.shape = full_shape
			full_collision.position = Vector3(x, floor_top + 3.0, gate_z)
			cell_body.add_child(full_collision)
		_site.add_child(cell_body)
		_add_skeleton(bones, sockets, Vector3(x, floor_top + 0.09, -19.7), deg_to_rad(float(x + 24.0) * 1.4))
	# The east annexe extends the prison into a second block. Its short passage
	# links the old cells to four deeper, locked bone cells.
	piece("platform", Vector3(0.0, floor_y, -15.5), 0, Vector3(24.0, 0.5, 19.0), 0.0, false)
	_castle_wall_between(Vector2(-12.0, -25.0), Vector2(12.0, -25.0), 7.5, 1.3, false, floor_top)
	_castle_wall_between(Vector2(12.0, -25.0), Vector2(12.0, -6.0), 7.5, 1.3, false, floor_top)
	_castle_wall_between(Vector2(12.0, -6.0), Vector2(-12.0, -6.0), 7.5, 1.3, false, floor_top)
	piece("arch", Vector3(-12.0, floor_top, -15.5), 90, Vector3(4.2, 5.6, 1.6), 0.0, false)
	for x in [-6.0, 0.0, 6.0]:
		_castle_wall_between(Vector2(x, -25.0), Vector2(x, -18.3), 7.3, 0.9, false, floor_top)
	for x in [-9.0, -3.0, 3.0, 9.0]:
		# Heavy portcullis bars close each deeper cell; individual lock plates make
		# the four cells read as secure rooms rather than one decorative cage.
		for bar in 9:
			var bar_x: float = x - 2.6 + float(bar) * 0.65
			stone.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(bar_x, floor_top, -18.0)),
				0.075, 0.065, 7.0, 6, IRON)
		for rail_y in [0.85, 3.0, 5.25]:
			stone.add_cylinder(Transform3D(Landmark.basis_y(Vector3(5.5, 0, 0)),
				Vector3(x - 2.75, floor_top + rail_y, -18.0)), 0.08, 0.08, 5.5, 6, IRON)
		stone.add_box(Transform3D(Basis.IDENTITY, Vector3(x + 2.25, floor_top + 2.5, -18.17)),
			Vector3(0.28, 0.42, 0.14), Color(0.16, 0.15, 0.13))
		stone.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.055, 0.055, 0.035)),
			Vector3(x + 2.25, floor_top + 2.45, -18.26)), 1.0, Color(0.66, 0.46, 0.2), false, 0.0)
		art.add_box(Transform3D(Basis.IDENTITY, Vector3(x, floor_top + 0.11, -23.5)),
			Vector3(3.9, 0.14, 1.35), Color(0.18, 0.13, 0.085))
		art.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.32, 0.07, 0.5)),
			Vector3(x, floor_top + 0.23, -23.45)), 1.0, Color(0.41, 0.32, 0.17), true, 0.1)
		var annex_cell_body := StaticBody3D.new()
		annex_cell_body.position = _origin
		annex_cell_body.collision_layer = Layers.WORLD
		annex_cell_body.collision_mask = 0
		var annex_cell_shape := BoxShape3D.new()
		annex_cell_shape.size = Vector3(5.7, 7.1, 0.32)
		var annex_cell_collision := CollisionShape3D.new()
		annex_cell_collision.shape = annex_cell_shape
		annex_cell_collision.position = Vector3(x, floor_top + 3.55, -18.0)
		annex_cell_body.add_child(annex_cell_collision)
		_site.add_child(annex_cell_body)
		_add_skeleton(bones, sockets, Vector3(x, floor_top + 0.08, -21.1), deg_to_rad(float(x) * 1.1))
	var west_wisp := OmniLight3D.new()
	west_wisp.name = "OldCellsWisp"
	west_wisp.position = _origin + Vector3(-24.0, -7.6, -12.0)
	west_wisp.light_color = Color(0.32, 0.83, 0.65)
	west_wisp.light_energy = 0.9
	west_wisp.omni_range = 11.0
	west_wisp.omni_attenuation = 1.4
	_site.add_child(west_wisp)
	# Green witchlight marks the newer prison block and guides the route back out.
	for x in [-10.5, -1.5, 7.5]:
		var prison_light := OmniLight3D.new()
		prison_light.name = "AnnexPrisonWisp"
		prison_light.position = _origin + Vector3(x, -7.2, -19.5)
		prison_light.light_color = Color(0.32, 0.83, 0.65)
		prison_light.light_energy = 0.9
		prison_light.omni_range = 8.5
		prison_light.omni_attenuation = 1.55
		_site.add_child(prison_light)
	_castle_plaque("CELL XII: OPENED FROM THE INSIDE", Vector3(-23.0, -8.75, -5.35), Color(0.74, 0.68, 0.53))
	# A blind reliquary branches from the hoist room. Its mural commemorates
	# the Shore Guard; the sealed doorway retains its original interaction.
	piece("platform", Vector3(11.5, floor_y, 15.0), 0, Vector3(13.0, 0.5, 16.0), 0.0, false)
	_castle_wall_between(Vector2(5.0, 7.0), Vector2(18.0, 7.0), 7.5, 1.2, false, floor_top)
	_castle_wall_between(Vector2(18.0, 7.0), Vector2(18.0, 12.0), 7.5, 1.2, false, floor_top)
	_castle_wall_openings(Vector2(18.0, 12.0), Vector2(18.0, 18.0), 7.5, 1.2, floor_top,
		[{"t": 0.5, "width": 3.2, "sill": 0.0, "height": 5.4}], false)
	_castle_wall_between(Vector2(18.0, 18.0), Vector2(18.0, 23.0), 7.5, 1.2, false, floor_top)
	_castle_wall_between(Vector2(18.0, 23.0), Vector2(5.0, 23.0), 7.5, 1.2, false, floor_top)
	piece("arch", Vector3(18.0, floor_top, 15.0), 90, Vector3(3.2, 5.4, 1.5), 0.0, false)
	var sealed_door := Interactable.new()
	sealed_door.name = "CryptSealedDoor"
	sealed_door.prompt_text = "Sealed: chains move behind the stone"
	sealed_door.position = _origin + Vector3(17.2, floor_top + 2.8, 15.0)
	sealed_door.max_view_angle = 75.0
	var sealed_shape := SphereShape3D.new()
	sealed_shape.radius = 0.8
	var sealed_collision := CollisionShape3D.new()
	sealed_collision.shape = sealed_shape
	sealed_door.add_child(sealed_collision)
	sealed_door.interacted.connect(_on_crypt_sealed_door_interacted)
	_site.add_child(sealed_door)
	# Sealed black doorway beyond the reliquary, with a readable iron lock plate.
	var gate := MeshKit.new(_seed + 933)
	for x in [-1.3, -0.65, 0.0, 0.65, 1.3]:
		gate.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(18.7 + x, floor_top, 15.0)), 0.075, 0.075, 5.1, 6, IRON)
	gate.add_box(Transform3D(Basis.IDENTITY, Vector3(18.7, floor_top + 2.6, 15.0)), Vector3(3.0, 0.16, 0.18), IRON)
	stone.append(gate)
	# Blocked door marks the dead end; touching it is allowed, passage is not.
	_castle_wall_between(Vector2(18.6, 12.0), Vector2(18.6, 18.0), 5.4, 0.9, false, floor_top)
	piece("block", Vector3(18.65, floor_top, 15.0), 0, Vector3(0.35, 5.2, 3.0), 0.0, false, {"color": Color(0.19, 0.18, 0.17)})
	# Ceiling slabs are low enough to frame the lamps and vaulted supports.
	for c in [Vector3(-24.0, -4.35, -15.5), Vector3(11.5, -4.35, 15.0)]:
		var size := Vector3(20.0, 0.4, 22.0) if c.x < -10.0 else (Vector3(24.0, 0.4, 19.0) if c.x < 0.0 else Vector3(13.0, 0.4, 16.0))
		piece("platform", c, 0, size, 0.0, false)
	piece("platform", Vector3(0.0, -4.35, -15.5), 0, Vector3(24.0, 0.4, 19.0), 0.0, false)
	# Continue the same open throat through the hoist-room ceiling so the cage
	# never collides with a solid slab on its return journey.
	piece("platform", Vector3(-11.15, -4.35, 15.0), 0, Vector3(7.7, 0.4, 22.0), 0.0, false)
	piece("platform", Vector3(1.15, -4.35, 15.0), 0, Vector3(7.7, 0.4, 22.0), 0.0, false)
	piece("platform", Vector3(-5.0, -4.35, 8.35), 0, Vector3(4.6, 0.4, 8.7), 0.0, false)
	piece("platform", Vector3(-5.0, -4.35, 21.65), 0, Vector3(4.6, 0.4, 8.7), 0.0, false)
	# Ribbed stone vaults and an inscription room-side of the lift mouth.
	for x in [-12.0, 2.0]:
		stone.add_box(Transform3D(Basis.IDENTITY, Vector3(x, -4.65, 15.0)), Vector3(0.3, 0.35, 19.0), Color(0.25, 0.24, 0.23))
	for x in [-9.0, -3.0, 3.0, 9.0]:
		stone.add_box(Transform3D(Basis.IDENTITY, Vector3(x, -4.65, -15.5)), Vector3(0.28, 0.32, 17.0), Color(0.25, 0.24, 0.23))
	for i in 7:
		var x := 8.0 + float(i % 4) * 1.8
		var z := 9.0 + float(i / 4) * 5.0
		art.add_box(Transform3D(Basis.IDENTITY, Vector3(x, floor_top + 1.5, z)), Vector3(0.14, 0.14, 0.14), Color(0.55, 0.72, 0.42))
	dark.add_box(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(18.25, floor_top + 2.7, 15.0)), Vector3(2.8, 4.4, 0.08), Color(0.035, 0.04, 0.04))
	_castle_plaque("IN MEMORY OF THE SHORE GUARD", Vector3(11.5, -9.0, 22.25), Color(0.74, 0.78, 0.58))
	_emit(_site, bones, PROPS_MAT, false)
	_emit(_site, sockets, PROPS_MAT, false)


func _castle_lift() -> void:
	for site_data in world.layout.list("sites"):
		if site_data.get("type", "") != "castle" or not site_data.has("lift"):
			continue
		var local: Vector2 = WorldLayout.v2(site_data["lift"])
		var lift: Node3D = CASTLE_LIFT_SCRIPT.new() as Node3D
		lift.name = "TraditionalUndercroftHoist"
		lift.position = Vector3(_origin.x + local.x, td.height_at(_origin.x + local.x, _origin.z + local.y), _origin.z + local.y)
		_site.add_child(lift)
		lift.call("build", float(site_data.get("crypt_depth", 12.0)))
		return


func _on_crypt_sealed_door_interacted(by: Node) -> void:
	_notify_castle(by, "A cold chain slides somewhere beyond the sealed stone.")


func _notify_castle(by: Node, message: String) -> void:
	if not is_instance_valid(by):
		return
	var hud := by.get_tree().root.find_child("HUD", true, false) as HUD
	if hud:
		hud.toast(message, 4.5)


func _emit(parent: Node3D, kit: MeshKit, mat: Material, shadows: bool) -> void:
	if kit is ZoneKits:
		for key in (kit as ZoneKits).kits:
			_emit(parent, (kit as ZoneKits).kits[key], mat, shadows)
		return
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(mat)
	mi.position = _origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _castle_merlons(kit: MeshKit, a: Vector2, b: Vector2, top_y: float, depth: float, spacing: float) -> void:
	var d := b - a
	var count := maxi(1, int(floor(d.length() / spacing)))
	var yaw := rad_to_deg(atan2(-d.y, d.x))
	for i in count + 1:
		var p := a.lerp(b, float(i) / count)
		kit.add_box(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(p.x, top_y + 0.62, p.y)), Vector3(1.35, 1.25, depth + 0.3), tagged(PropMeshes.ROCK * 0.9, SURF_RUBBLE))


func _castle_roof(kit: MeshKit, center: Vector2, radius: float, base_y: float, height: float, color: Color) -> void:
	var slate := tagged(color * 1.25, SURF_RUBBLE)
	kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(center.x, base_y, center.y)), radius, 0.0, height, 12, slate, 0.0, 0.0, false)
	kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(center.x, base_y - 0.25, center.y)), radius * 0.92, radius, 0.3, 12, tagged(color * 0.9, SURF_RUBBLE))
	kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(center.x, base_y + height - 0.2, center.y)), 0.18, 0.0, 1.4, 5, Color(0.52, 0.39, 0.22), 0.0, 0.0, false)


func _castle_banner(kit: MeshKit, pole_base: Vector3, cloth: Color) -> void:
	kit.add_cylinder(Transform3D(Basis.IDENTITY, pole_base), 0.09, 0.06, 6.4, 5, Color(0.28, 0.2, 0.12), 0.0, 0.0, false)
	kit.add_box(Transform3D(Basis.IDENTITY, pole_base + Vector3(0.0, 4.0, 0.72)), Vector3(0.12, 4.6, 2.25), cloth)
	# Forked cloth tails and a pale heraldic bar stay readable against the night sky.
	for z in [-0.42, 0.42]:
		kit.add_box(Transform3D(Basis.IDENTITY, pole_base + Vector3(0.075, 1.45, 0.72 + z)), Vector3(0.11, 0.72, 0.68), cloth * 0.78)
	kit.add_box(Transform3D(Basis.IDENTITY, pole_base + Vector3(0.08, 4.0, 0.72)), Vector3(0.08, 0.38, 1.45), Color(0.78, 0.68, 0.48))


func _castle_ossuary(stonework: MeshKit, darkness: MeshKit) -> void:
	# Three barred cells make the skeletons visible from the courtyard without
	# letting the crypt read as an ordinary empty room.
	var left := -36.0
	var right := -12.0
	var back := -25.0
	var front := -6.0
	var floor_top := 0.4
	var bedding := MeshKit.new(_seed + 934, 0.035)
	piece("platform", Vector3((left + right) * 0.5, 0, (back + front) * 0.5), 0, Vector3(right - left, 0.55, front - back), 0.0)
	_castle_wall_between(Vector2(left, back), Vector2(right, back), 5.4, 1.4)
	_castle_wall_between(Vector2(left, back), Vector2(left, front), 5.4, 1.4)
	_castle_wall_between(Vector2(right, back), Vector2(right, front), 5.4, 1.4)
	for x in [-28.0, -20.0]:
		_castle_wall_between(Vector2(x, back), Vector2(x, front - 0.2), 4.9, 1.0)
	var bone_mesh := MeshKit.new(_seed + 901, 0.035)
	var socket_mesh := MeshKit.new(_seed + 902)
	var cell_centers: Array[float] = [-32.0, -24.0, -16.0]
	for cell_x in cell_centers:
		var broken_gate := is_equal_approx(cell_x, -24.0)
		var gate_z := front - 0.75
		# Iron grille with stout jambs and a crossbar on each cell front.
		for j in 11:
			if broken_gate and j == 5:
				continue
			var x: float = cell_x - 3.5 + float(j) * 0.7
			stonework.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(x, floor_top, gate_z)), 0.085, 0.065, 4.5, 6, IRON)
		if broken_gate:
			for rail_y in [1.15, 3.15]:
				for rail_start in [cell_x - 3.5, cell_x + 0.65]:
					stonework.add_cylinder(Transform3D(Landmark.basis_y(Vector3(2.85, 0, 0)),
						Vector3(rail_start, rail_y, gate_z)), 0.09, 0.09, 2.85, 6, IRON)
		else:
			stonework.add_cylinder(Transform3D(Landmark.basis_y(Vector3(7.0, 0, 0)), Vector3(cell_x - 3.5, 3.15, gate_z)), 0.09, 0.09, 7.0, 6, IRON)
			stonework.add_cylinder(Transform3D(Landmark.basis_y(Vector3(7.0, 0, 0)), Vector3(cell_x - 3.5, 1.15, gate_z)), 0.09, 0.09, 7.0, 6, IRON)
		# Low stone shelf behind the remains.
		piece("block", Vector3(cell_x, floor_top, -23.2), 0, Vector3(5.6, 0.55, 2.0), 0.0, false, {"color": Color(0.22, 0.22, 0.21)})
		bedding.add_box(Transform3D(Basis.IDENTITY, Vector3(cell_x, floor_top + 0.64, -23.15)),
			Vector3(3.8, 0.16, 1.45), Color(0.19, 0.14, 0.095))
		bedding.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.38, 0.09, 0.62)),
			Vector3(cell_x, floor_top + 0.78, -23.05)), 1.0, Color(0.43, 0.34, 0.19), true, 0.08)
		_add_skeleton(bone_mesh, socket_mesh, Vector3(cell_x, 0.46, -16.7), deg_to_rad(cell_x * 0.55))
		var barrier := StaticBody3D.new()
		barrier.position = _origin
		barrier.collision_layer = Layers.WORLD
		barrier.collision_mask = 0
		if broken_gate:
			for side in [-1.0, 1.0]:
				var broken_shape := BoxShape3D.new()
				broken_shape.size = Vector3(2.85, 4.7, 0.32)
				var broken_collision := CollisionShape3D.new()
				broken_collision.shape = broken_shape
				broken_collision.position = Vector3(cell_x + side * 2.075, 2.65, gate_z)
				barrier.add_child(broken_collision)
		else:
			var full_shape := BoxShape3D.new()
			full_shape.size = Vector3(7.1, 4.7, 0.32)
			var full_collision := CollisionShape3D.new()
			full_collision.shape = full_shape
			full_collision.position = Vector3(cell_x, 2.65, gate_z)
			barrier.add_child(full_collision)
		_site.add_child(barrier)
	# Open roof, short battlements and a pale green lantern give the bone cells a
	# deliberate dungeon silhouette and keep their contents visible at night.
	var light := OmniLight3D.new()
	light.name = "OssuaryWisp"
	light.position = _origin + Vector3(-24.0, 3.5, -10.0)
	light.light_color = Color(0.22, 0.76, 0.58)
	light.light_energy = 1.4
	light.omni_range = 19.0
	light.omni_attenuation = 1.5
	_site.add_child(light)
	var label := Label3D.new()
	label.name = "OssuarySign"
	label.text = "THE BONE JAIL"
	label.position = _origin + Vector3(-24.0, 6.2, front + 0.25)
	label.font_size = 48
	label.pixel_size = 0.012
	label.modulate = Color(0.72, 0.67, 0.53)
	_site.add_child(label)
	_emit(_site, bone_mesh, PROPS_MAT, false)
	_emit(_site, socket_mesh, PROPS_MAT, false)
	_emit(_site, bedding, PROPS_MAT, false)


func _add_skeleton(bones: MeshKit, sockets: MeshKit, root: Vector3, yaw := 0.0) -> void:
	# Human-scale remains with separate cranial, jaw, spine, rib, pelvic and limb
	# bones. The face points upward; yaw varies the scattered poses per cell.
	var pose := Basis(Vector3.UP, yaw)
	var skull := _skeleton_point(root, pose, Vector3(0, 0.25, 0.73))
	bones.add_blob(Transform3D(pose.scaled(Vector3(0.135, 0.15, 0.17)), skull), 1.0, BONE, true, 0.025)
	var jaw := _skeleton_point(root, pose, Vector3(0, 0.115, 0.79))
	bones.add_blob(Transform3D(pose.scaled(Vector3(0.092, 0.052, 0.105)), jaw), 1.0, BONE, true, 0.015)
	for side in [-1.0, 1.0]:
		var socket_at := _skeleton_point(root, pose, Vector3(side * 0.052, 0.27, 0.875))
		sockets.add_blob(Transform3D(pose.scaled(Vector3(0.034, 0.043, 0.024)), socket_at),
			1.0, Color(0.018, 0.019, 0.018), false)
		var cheek := _skeleton_point(root, pose, Vector3(side * 0.083, 0.185, 0.85))
		bones.add_blob(Transform3D(pose.scaled(Vector3(0.052, 0.045, 0.045)), cheek), 1.0, BONE, true, 0.01)
	var nasal_cavity := _skeleton_point(root, pose, Vector3(0, 0.205, 0.901))
	sockets.add_blob(Transform3D(pose.scaled(Vector3(0.022, 0.034, 0.016)), nasal_cavity),
		1.0, Color(0.02, 0.021, 0.019), false)
	for tooth in 6:
		var tooth_x := -0.05 + float(tooth) * 0.02
		var tooth_at := _skeleton_point(root, pose, Vector3(tooth_x, 0.128, 0.887))
		bones.add_box(Transform3D(pose, tooth_at), Vector3(0.014, 0.028, 0.018), Color(0.84, 0.8, 0.68))
	# Cervical vertebrae continue down the spine into the sacrum.
	var previous_vertebra := _skeleton_point(root, pose, Vector3(0, 0.15, 0.57))
	for i in 9:
		var vertebra_at := _skeleton_point(root, pose, Vector3(0, 0.145, 0.49 - float(i) * 0.095))
		bones.add_blob(Transform3D(pose.scaled(Vector3(0.042, 0.045, 0.038)), vertebra_at), 1.0, BONE, false)
		_bone(bones, previous_vertebra, vertebra_at, 0.027)
		previous_vertebra = vertebra_at
	# Clavicles and a full six-pair rib cage, built as curved front and side arcs.
	var sternum_top := _skeleton_point(root, pose, Vector3(0, 0.235, 0.49))
	var sternum_bottom := _skeleton_point(root, pose, Vector3(0, 0.205, -0.045))
	_bone(bones, sternum_top, sternum_bottom, 0.036)
	for side in [-1.0, 1.0]:
		_bone(bones, sternum_top, _skeleton_point(root, pose, Vector3(side * 0.24, 0.21, 0.43)), 0.038)
	for rib in 6:
		var z := 0.37 - float(rib) * 0.083
		var spine_at := _skeleton_point(root, pose, Vector3(0, 0.145, z))
		for side in [-1.0, 1.0]:
			var rib_peak := _skeleton_point(root, pose, Vector3(side * 0.17, 0.24, z - 0.025))
			var rib_side := _skeleton_point(root, pose, Vector3(side * 0.285, 0.205, z - 0.065))
			var rib_front := _skeleton_point(root, pose, Vector3(side * 0.3, 0.12, z - 0.1))
			_bone(bones, spine_at, rib_peak, 0.033)
			_bone(bones, rib_peak, rib_side, 0.03)
			_bone(bones, rib_side, rib_front, 0.028)
	# Ilium wings and sacrum create a recognisable pelvic bowl.
	var sacrum := _skeleton_point(root, pose, Vector3(0, 0.11, -0.2))
	bones.add_blob(Transform3D(pose.scaled(Vector3(0.105, 0.065, 0.12)), sacrum), 1.0, BONE, false)
	for side in [-1.0, 1.0]:
		var iliac_peak := _skeleton_point(root, pose, Vector3(side * 0.2, 0.17, -0.28))
		var hip := _skeleton_point(root, pose, Vector3(side * 0.18, 0.09, -0.34))
		_bone(bones, sacrum, iliac_peak, 0.045)
		_bone(bones, iliac_peak, hip, 0.05)
		bones.add_blob(Transform3D(pose.scaled(Vector3.ONE * 0.055), hip), 1.0, BONE, false)
		# Shoulder, humerus, paired forearm bones, wrist and separated fingers.
		var shoulder := _skeleton_point(root, pose, Vector3(side * 0.25, 0.17, 0.41))
		var elbow := _skeleton_point(root, pose, Vector3(side * 0.42, 0.085, 0.16))
		var wrist := _skeleton_point(root, pose, Vector3(side * 0.55, 0.055, -0.005))
		var palm := _skeleton_point(root, pose, Vector3(side * 0.58, 0.05, -0.085))
		_bone(bones, shoulder, elbow, 0.047)
		_bone(bones, elbow, wrist, 0.032)
		_bone(bones, elbow + pose * Vector3(0, -0.035, 0.035), wrist + pose * Vector3(0, -0.035, 0.025), 0.024)
		bones.add_blob(Transform3D(pose.scaled(Vector3(0.07, 0.035, 0.085)), palm), 1.0, BONE, false)
		bones.add_blob(Transform3D(pose.scaled(Vector3.ONE * 0.045), elbow), 1.0, BONE, false)
		for finger in 4:
			var spread := (float(finger) - 1.5) * 0.034
			var knuckle := palm + pose * Vector3(spread, 0, -0.045)
			var fingertip := knuckle + pose * Vector3(spread * 0.28, -0.005, -0.105)
			_bone(bones, knuckle, fingertip, 0.013)
		var thumb_base := palm + pose * Vector3(side * 0.055, 0, 0.005)
		_bone(bones, thumb_base, thumb_base + pose * Vector3(side * 0.085, 0, -0.07), 0.016)
		# Femur, kneecap, paired lower-leg bones, ankle and small foot bones.
		var knee := _skeleton_point(root, pose, Vector3(side * 0.17, 0.055, -0.62))
		var ankle := _skeleton_point(root, pose, Vector3(side * 0.16, 0.035, -0.93))
		var hip_head := hip + pose * Vector3(side * 0.03, 0, -0.04)
		_bone(bones, hip_head, knee, 0.055)
		bones.add_blob(Transform3D(pose.scaled(Vector3.ONE * 0.045), knee), 1.0, BONE, false)
		_bone(bones, knee, ankle, 0.032)
		_bone(bones, knee + pose * Vector3(side * 0.045, 0, 0), ankle + pose * Vector3(side * 0.045, 0, 0), 0.024)
		bones.add_blob(Transform3D(pose.scaled(Vector3.ONE * 0.035), ankle), 1.0, BONE, false)
		var heel := ankle + pose * Vector3(0, 0, -0.1)
		var toes := heel + pose * Vector3(0, 0.005, -0.12)
		bones.add_blob(Transform3D(pose.scaled(Vector3(0.07, 0.04, 0.12)), toes), 1.0, BONE, false)
		for toe in 3:
			var toe_start := heel + pose * Vector3((float(toe) - 1.0) * 0.035, 0.015, -0.13)
			_bone(bones, toe_start, toe_start + pose * Vector3((float(toe) - 1.0) * 0.018, 0, -0.07), 0.013)


func _skeleton_point(root: Vector3, pose: Basis, local: Vector3) -> Vector3:
	return root + pose * local


func _bone(kit: MeshKit, a: Vector3, b: Vector3, radius: float) -> void:
	var axis := b - a
	if axis.length_squared() < 0.0001:
		return
	kit.add_cylinder(Transform3D(Landmark.basis_y(axis), a), radius, radius * 0.78, axis.length(), 6, BONE, 0.0, 0.0, false)


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
	foam.position = Vector3(bottom.x, world.water_level + 0.35, bottom.y + 1.2)
	foam.amount = 36
	foam.lifetime = 2.2
	foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	foam.emission_box_extents = Vector3(width * 0.48, 0.35, 1.4)
	foam.direction = Vector3(0, 1, 0.45)
	foam.spread = 45.0
	foam.initial_velocity_min = 0.8
	foam.initial_velocity_max = 2.2
	foam.gravity = Vector3(0, -1.2, 0)
	var fm := QuadMesh.new()
	fm.size = Vector2(2.6, 2.6)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_texture = _soft_mist_texture()
	fmat.albedo_color = Color(0.84, 0.92, 0.94, 0.34)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fm.material = fmat
	foam.mesh = fm
	add_child(foam)
	# Framing mossy cliff rocks flanking the waterfall plunge pool.
	var wf_rocks := MeshKit.new(8821, 0.08)
	for side_x: float in [-1.0, 1.0]:
		var rx := bottom.x + side_x * (width * 0.62)
		var rz := bottom.y - 2.0
		var ry := td.height_at(rx, rz)
		wf_rocks.add_blob(Transform3D(Basis(Vector3.UP, side_x * 0.7).scaled(Vector3(3.4, 4.2, 3.0)), Vector3(rx, ry + 0.8, rz)), 1.0, PropMeshes.ROCK * 0.85, true, 0.3)
		wf_rocks.add_blob(Transform3D(Basis(Vector3.UP, -side_x * 0.4).scaled(Vector3(2.2, 1.6, 2.0)), Vector3(rx - side_x * 1.4, world.water_level + 0.2, rz + 3.2)), 1.0, PropMeshes.ROCK.lerp(PropMeshes.MOSS, 0.4), true, 0.28)
	var wfr := MeshInstance3D.new()
	wfr.name = "WaterfallRocks"
	wfr.mesh = wf_rocks.to_mesh(PropMeshes.ROCK_MAT)
	add_child(wfr)


static func _soft_mist_texture() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var dx := (float(x) - half) / half
			var dy := (float(y) - half) / half
			var r2 := dx * dx + dy * dy
			var a := pow(clampf(1.0 - r2, 0.0, 1.0), 2.2)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


## Bakes a lightweight 256x256 shoreline-depth + river-flow map for water.gdshader
## (R = depth 0..1, GB = flow dir, A = rapids/waterfall foam boost).
func _bake_water_shore_map() -> void:
	var half := world.layout.half_size
	var wl := world.water_level
	var sz := 256
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rivers := world.layout.list("rivers")
	var wf := world.layout.dict("waterfall")
	var wf_bot := WorldLayout.v2(wf["bottom"]) if not wf.is_empty() else Vector2(1e6, 1e6)
	var river_segs: Array = []
	for rv in rivers:
		var pts := WorldLayout.points(rv["points"])
		var hw := float(rv["half_width"]) + float(rv["bank"])
		for i in pts.size() - 1:
			var dir := (pts[i + 1] - pts[i]).normalized()
			river_segs.append([pts[i], pts[i + 1], dir, hw])
	for py in sz:
		var z := lerpf(-half, half, (float(py) + 0.5) / float(sz))
		for px in sz:
			var x := lerpf(-half, half, (float(px) + 0.5) / float(sz))
			var h := td.height_at(x, z)
			var depth := clampf((wl - h) / 3.2, 0.0, 1.0)
			var flow := Vector2.ZERO
			var rapids := 0.0
			var p2 := Vector2(x, z)
			for seg in river_segs:
				var d := TerrainData.seg_dist(p2, seg[0], seg[1])
				if d < seg[3]:
					var w := 1.0 - smoothstep(seg[3] * 0.4, seg[3], d)
					flow += (seg[2] as Vector2) * w
					rapids = maxf(rapids, 0.35 * w)
			if p2.distance_to(wf_bot) < 22.0:
				rapids = maxf(rapids, 1.0 - smoothstep(4.0, 22.0, p2.distance_to(wf_bot)))
			if flow.length_squared() > 0.001:
				flow = flow.normalized() * 0.75
			img.set_pixel(px, py, Color(depth, flow.x * 0.5 + 0.5, flow.y * 0.5 + 0.5, clampf(rapids, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	var water_mat := preload("res://assets/materials/water.tres") as ShaderMaterial
	if water_mat:
		water_mat.set_shader_parameter("shore_map", tex)
		water_mat.set_shader_parameter("map_half_size", half)
		water_mat.set_shader_parameter("use_shore_map", 1.0)


## Publishes Integration Contract C-13 wf_marker nodes for Codex/Claude consumers.
func _publish_battlefield_markers() -> void:
	var holder := Node3D.new()
	holder.name = "WorldMarkers"
	add_child(holder)
	var defs := [
		{"id": "great_gate_field_center", "kind": "battle_cell", "pos": Vector2(-232.0, 70.0), "radius": 44.0},
		{"id": "great_gate_spawn_west", "kind": "spawn_point", "pos": Vector2(-262.0, 70.0), "radius": 8.0},
		{"id": "great_gate_escort", "kind": "escort_anchor", "pos": Vector2(-202.0, 70.0), "radius": 6.0},
		{"id": "north_meadow_clearing", "kind": "battle_cell", "pos": Vector2(150.0, -62.0), "radius": 36.0},
		{"id": "southbank_bridge_clearing", "kind": "battle_cell", "pos": Vector2(76.0, 198.0), "radius": 24.0},
		{"id": "castle_square_clearing", "kind": "battle_cell", "pos": Vector2(232.0, 94.0), "radius": 18.0},
		{"id": "elder_tree_camera", "kind": "camera_hint", "pos": Vector2(0.0, 42.0), "radius": 5.0},
	]
	for d in defs:
		var m := Marker3D.new()
		m.name = "WF_" + String(d["id"])
		var p: Vector2 = d["pos"]
		m.position = Vector3(p.x, td.height_at(p.x, p.y), p.y)
		m.set_meta("marker_id", d["id"])
		m.set_meta("kind", d["kind"])
		m.set_meta("radius", float(d["radius"]))
		m.add_to_group("wf_marker")
		holder.add_child(m)


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


func _castle_approach_paving(stair_base: Vector3) -> void:
	var path := MeshKit.new(9012)
	var a := Vector2(-74, 9)
	var b := Vector2(stair_base.x - 1.0, stair_base.z)
	var side := Vector2(-(b - a).y, (b - a).x).normalized() * 3.4
	var steps := maxi(1, int(a.distance_to(b)))
	for i in steps:
		var p := a.lerp(b, float(i) / steps)
		var q := a.lerp(b, float(i + 1) / steps)
		var points: Array[Vector3] = []
		for xz in [p - side, p + side, q + side, q - side]:
			points.append(Vector3(xz.x, td.height_at(_origin.x + xz.x, _origin.z + xz.y) - _origin.y + 0.045, xz.y))
		path.add_quad(points[0], points[1], points[2], points[3], DRESSED)
	_emit(_site, path, CASTLE_PROPS_MAT, false)
