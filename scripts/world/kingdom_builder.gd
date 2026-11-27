class_name KingdomBuilder
extends RefCounted
## Builds the walled kingdom from KingdomPlan: the curtain wall, towers, the
## sealed great gate, the river water gate, the new town (houses and market
## stalls), the memorial cemetery at the Elder Tree, the training-ground dressing
## in the Old Citadel, Phase 3 mission/soldier markers, street lanterns and the
## distant countryside beyond the terrain edge.
##
## Reuse: towers, gate arch, gateposts and the memorial stone are the shared
## RuinPiece scenes; roofs, merlons and banners use the castle's builders and
## materials; houses are the Ashford house builder (VillageBuilder) built once
## per archetype and drawn as shared MultiMeshes, so 80+ houses cost a few
## draw calls; fences and lanterns are the village's dry-stone wall and lantern
## posts. Everything is exterior-only and solid: no doors open, the gate never
## opens, and nothing on the wall can be climbed.

const STONE_MAT := preload("res://assets/materials/stone.tres")
const HOUSE_MAT := preload("res://assets/materials/village_props.tres")
const GLOW_WARM := preload("res://assets/materials/glow_warm.tres")
const TERRAIN_MAT := preload("res://assets/materials/terrain.tres")
const DISTANT_MOUNTAIN_MAT := preload("res://assets/materials/distant_mountain.tres")
const WALL_STONE := Color(0.36, 0.35, 0.33)
const MAROON := Color(0.36, 0.06, 0.07)
const IRON := Color(0.1, 0.105, 0.11)
const OAK_LEAF := Color(0.25, 0.17, 0.1)
## How far above the wall walk the invisible barrier reaches.
const BARRIER_ABOVE := 30.0

var sites: Sites
var world: World
var td: TerrainData
var plan: KingdomPlan
var root: Node3D
var vb: VillageBuilder
var wall_body: StaticBody3D
var _arch_cache := {}
var _shape_cache := {}
var _wall_kits := {}
var _detail: MeshKit       ## castle_props-material detail (merlons, roofs, iron)
var _banners: MeshKit
var _stone_detail: MeshKit ## stone-material detail (crosses, gate stonework)
var _wood: MeshKit         ## village-material woodwork (doors, pells, stalls' extras)
var _tower_kit: MeshKit    ## stone-material towers (skyline: never distance-culled)


func _init(p_sites: Sites, p_root: Node3D) -> void:
	sites = p_sites
	world = p_sites.world
	td = world.terrain_data
	root = p_root


func build() -> KingdomPlan:
	plan = KingdomPlan.new()
	plan.compute(world.layout, td)
	sites.kingdom_plan = plan
	vb = VillageBuilder.new(sites, root, Vector3.ZERO, td, world.water_level)
	vb.solid = StaticBody3D.new()
	vb.solid.name = "KingdomProps"
	vb.solid.collision_layer = Layers.WORLD
	vb.solid.collision_mask = 0
	root.add_child(vb.solid)
	_detail = MeshKit.new(9101, 0.04)
	_banners = MeshKit.new(9102, 0.02)
	_stone_detail = MeshKit.new(9103, 0.06)
	_wood = MeshKit.new(9104, 0.04)
	_tower_kit = MeshKit.new(9105, 0.05)
	wall_body = StaticBody3D.new()
	wall_body.name = "KingdomWall"
	wall_body.collision_layer = Layers.WORLD
	wall_body.collision_mask = 0
	root.add_child(wall_body)
	var saved_material = sites._piece_material
	sites._piece_material = null
	_build_wall()
	_build_towers()
	_build_gate()
	_build_water_gates()
	_build_houses()
	_build_stalls()
	_build_cemetery()
	_build_training_ground()
	_build_mission_markers()
	_build_lanterns()
	_build_horizon()
	_register_blockers()
	sites._piece_material = saved_material
	for key in _wall_kits:
		_emit_kit(_wall_kits[key], STONE_MAT, true, "WallStone_%s" % key, 0.0)
	_emit_kit(_tower_kit, STONE_MAT, true, "WallTowers", 0.0)
	_emit_kit(_detail, Sites.CASTLE_PROPS_MAT, true, "KingdomDetail", 0.0)
	_emit_kit(_banners, Sites.PROPS_MAT, true, "KingdomBanners", 600.0)
	_emit_kit(_stone_detail, STONE_MAT, true, "KingdomStoneDetail", 300.0)
	_emit_kit(_wood, HOUSE_MAT, true, "KingdomWoodwork", 300.0)
	vb._emit(vb.props, HOUSE_MAT, true, "KingdomVillageProps")
	vb._emit(vb.glow, GLOW_WARM, false, "KingdomGlow")
	print("[Kingdom] wall pieces %d, towers %d, houses %d, stalls %d, graves %d, plan rejections %d" % [
		plan.wall_pieces.size(), plan.towers.size(), plan.houses.size(), plan.stalls.size(), plan.graves.size(), plan.rejected.size()])
	return plan


# --- helpers ------------------------------------------------------------------------------

func _emit_kit(k: MeshKit, mat: Material, shadows: bool, node_name: String, range_end: float) -> void:
	if k.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = k.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = range_end
	root.add_child(mi)


func _box_shape(size: Vector3) -> BoxShape3D:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _shape_cache.has(key):
		var b := BoxShape3D.new()
		b.size = size
		_shape_cache[key] = b
	return _shape_cache[key]


func _add_box_collision(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = _box_shape(size.abs())
	cs.transform = xf
	body.add_child(cs)


## Yaw that turns local +x along `dir` (the convention of Sites.wall()).
static func _yaw_along(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


func _piece(kind: String, pos: Vector3, yaw_deg: float, size: Vector3, broken := 0.0, extra := {}) -> RuinPiece:
	sites._site = root
	sites._origin = Vector3.ZERO
	var p := sites.piece(kind, pos, yaw_deg, size, broken, false, extra)
	# Wall towers are skyline features: keep them visible as far as the wall.
	for c in p.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).visibility_range_end = 0.0
	return p


# --- curtain wall ---------------------------------------------------------------------------

func _wall_kit(index: int) -> MeshKit:
	var key := index / 10
	if not _wall_kits.has(key):
		_wall_kits[key] = MeshKit.new(9200 + key, 0.06)
	return _wall_kits[key]


func _build_wall() -> void:
	var t := plan.wall_thickness
	for i in plan.wall_pieces.size():
		var piece: Dictionary = plan.wall_pieces[i]
		var a: Vector2 = piece["a"]
		var b: Vector2 = piece["b"]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var outward := Vector2(dir.y, -dir.x)
		var mid := (a + b) * 0.5
		var basis := Basis(Vector3.UP, _yaw_along(dir))
		var bottom: float = piece["bottom"]
		var top: float = piece["top"]
		var ground: float = piece["ground"]
		var k := _wall_kit(i)
		var shade := 0.9 + 0.12 * fmod(float(i) * 0.618, 1.0)
		var col := WALL_STONE * shade
		var body_bottom := bottom
		if piece["kind"] == "water_gate":
			body_bottom = world.water_level + 4.2
			_water_gate_piece(piece, basis, mid, length)
		# Core, battered footing, string course and coping.
		k.add_box(Transform3D(basis, Vector3(mid.x, (body_bottom + top) * 0.5, mid.y)), Vector3(length + 0.06, top - body_bottom, t), col)
		if piece["kind"] == "wall":
			var foot_top := minf(ground + 1.3, top - 2.0)
			k.add_box(Transform3D(basis, Vector3(mid.x, (bottom + foot_top) * 0.5, mid.y)), Vector3(length + 0.08, foot_top - bottom, t + 1.3), col * 0.9)
			k.add_box(Transform3D(basis, Vector3(mid.x, foot_top + 0.1, mid.y)), Vector3(length + 0.1, 0.28, t + 0.9), col * 0.82)
		k.add_box(Transform3D(basis, Vector3(mid.x, top - 2.6, mid.y)), Vector3(length + 0.1, 0.3, t + 0.35), col * 0.85)
		k.add_box(Transform3D(basis, Vector3(mid.x, top + 0.15, mid.y)), Vector3(length + 0.12, 0.3, t + 0.5), col * 0.8)
		# Outer battlement (merlons) and an inner parapet along the wall walk.
		var count := maxi(1, int(round(length / 2.7)))
		for m in count:
			var p := a.lerp(b, (float(m) + 0.5) / count) + outward * (t * 0.5 - 0.35)
			_detail.add_box(Transform3D(basis, Vector3(p.x, top + 0.95, p.y)), Vector3(1.35, 1.3, 0.7), Sites.tagged(PropMeshes.ROCK * 0.9, Sites.SURF_RUBBLE))
		var inner := mid - outward * (t * 0.5 - 0.25)
		k.add_box(Transform3D(basis, Vector3(inner.x, top + 0.6, inner.y)), Vector3(length + 0.05, 0.9, 0.5), col * 0.95)
		# Shallow buttresses on the town side every other piece.
		if i % 2 == 0 and piece["kind"] == "wall":
			var bp := mid - outward * (t * 0.5 + 0.45)
			k.add_box(Transform3D(basis, Vector3(bp.x, (bottom + top - 2.8) * 0.5, bp.y)), Vector3(1.7, top - 2.8 - bottom, 0.9), col * 0.93)
		# Collision: the masonry plus a tall invisible barrier above the walk.
		_add_box_collision(wall_body, Transform3D(basis, Vector3(mid.x, (bottom + top + BARRIER_ABOVE) * 0.5, mid.y)),
			Vector3(length + 0.3, top + BARRIER_ABOVE - bottom, t))
	# Past each wall end the barrier continues into the mountains to the map edge.
	for ext in plan.barrier_extensions:
		var a: Vector2 = ext[0]
		var b: Vector2 = ext[1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var steps := maxi(1, int(ceil(length / 10.0)))
		for s in steps:
			var pa := a + dir * (length * s / steps)
			var pb := a + dir * (length * (s + 1) / steps)
			var lo := INF
			var hi := -INF
			for f: float in [0.0, 0.5, 1.0]:
				var q := pa.lerp(pb, f)
				var h := td.height_at(q.x, q.y)
				lo = minf(lo, h)
				hi = maxf(hi, h)
			var mid := (pa + pb) * 0.5
			_add_box_collision(wall_body, Transform3D(Basis(Vector3.UP, _yaw_along(dir)), Vector3(mid.x, (lo - 3.0 + hi + BARRIER_ABOVE + 12.0) * 0.5, mid.y)),
				Vector3(pa.distance_to(pb) + 0.5, hi + BARRIER_ABOVE + 12.0 - lo + 3.0, 3.0))


func _water_gate_piece(piece: Dictionary, basis: Basis, mid: Vector2, length: float) -> void:
	# The river passes under the wall through an iron grille; the grille is part
	# of the barrier, so the wall cannot be swum through.
	var bed := minf(float(piece["bottom"]), world.water_level - 3.0)
	var dir := Vector3(basis.x.x, 0, basis.x.z)
	var spring := world.water_level + 4.2
	var bars := int(length / 0.4)
	for i in bars + 1:
		var p := Vector3(mid.x, 0, mid.y) + dir * (-length * 0.5 + length * float(i) / bars)
		_detail.add_box(Transform3D(basis, Vector3(p.x, (bed + spring) * 0.5, p.z)), Vector3(0.09, spring - bed, 0.09), Sites.tagged(IRON, Sites.SURF_IRON))
	for y: float in [world.water_level - 0.6, world.water_level + 1.4, spring - 0.4]:
		_detail.add_box(Transform3D(basis, Vector3(mid.x, y, mid.y)), Vector3(length, 0.12, 0.14), Sites.tagged(IRON, Sites.SURF_IRON))
	_stone_detail.add_box(Transform3D(basis, Vector3(mid.x, spring + 0.25, mid.y)), Vector3(length + 0.2, 0.6, plan.wall_thickness + 0.6), WALL_STONE * 0.8)


func _build_towers() -> void:
	var w: Dictionary = plan.k["wall"]
	for i in plan.tower_info.size():
		var info: Dictionary = plan.tower_info[i]
		var p: Vector2 = info["pos"]
		var dia: float = info["diameter"]
		# Tower top: above the adjacent wall walk.
		var walk := _wall_top_near(p)
		var lo := INF
		for a in 8:
			var q := p + Vector2(cos(TAU * a / 8.0), sin(TAU * a / 8.0)) * dia * 0.5
			lo = minf(lo, td.height_at(q.x, q.y))
		lo = minf(lo, td.height_at(p.x, p.y))
		var top := walk + float(w["tower_height"]) - float(w["height"])
		_tower(p, lo - 1.0, top, dia)
		# Crenellated crown, and a slate cap on every third tower.
		var r := dia * 0.5 + 0.35
		_detail.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, top + 0.2, p.y)), r + 0.25, r + 0.25, 0.45, 14, Sites.tagged(PropMeshes.ROCK * 0.85, Sites.SURF_RUBBLE))
		if i % 3 == 0:
			sites._castle_roof(_detail, p, r + 0.5, top + 0.4, dia * 0.85, Sites.SLATE)
			if i % 2 == 0:
				sites._castle_banner(_banners, Vector3(p.x, top + dia * 0.85 + 0.2, p.y), MAROON)
		else:
			for m in 10:
				var a := TAU * float(m) / 10.0
				var q := p + Vector2(cos(a), sin(a)) * (r - 0.1)
				_detail.add_box(Transform3D(Basis(Vector3.UP, -a), Vector3(q.x, top + 1.05, q.y)), Vector3(0.7, 1.25, 1.2), Sites.tagged(PropMeshes.ROCK * 0.9, Sites.SURF_RUBBLE))
		# Arrow slits on the town side.
		var inward := -_outward_at(p)
		for y in [lo + 4.0, top - 4.0]:
			var q := p + inward * (dia * 0.5 - 0.05)
			_detail.add_box(Transform3D(Basis(Vector3.UP, _yaw_along(Vector2(-inward.y, inward.x))), Vector3(q.x, y, q.y)), Vector3(0.22, 1.4, 0.3), Color(0.03, 0.03, 0.035))
		info["top"] = top


## A round flanking tower in the wall's stone: battered plinth, tapering drum,
## string course and corbelled crown, with solid collision and the same tall
## barrier as the wall.
func _tower(p: Vector2, bottom: float, top: float, dia: float) -> void:
	var r := dia * 0.5
	var col := WALL_STONE * (0.92 + 0.08 * fmod(absf(p.x * 0.37 + p.y * 0.11), 1.0))
	var ground := td.height_at(p.x, p.y)
	_tower_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, bottom, p.y)), r * 1.16, r * 1.08, ground + 1.6 - bottom, 18, col * 0.9)
	_tower_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, ground + 1.5, p.y)), r * 1.04, r * 0.97, top - ground - 1.5, 18, col)
	_tower_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, top - 2.9, p.y)), r + 0.18, r + 0.18, 0.32, 18, col * 0.85)
	_tower_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, top - 0.7, p.y)), r * 0.97, r + 0.42, 0.75, 18, col * 0.88)
	_tower_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, top, p.y)), r + 0.42, r + 0.42, 0.25, 18, col * 0.8)
	var shape := CylinderShape3D.new()
	shape.radius = r * 1.05
	shape.height = top + BARRIER_ABOVE - bottom
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(p.x, (bottom + top + BARRIER_ABOVE) * 0.5, p.y)
	wall_body.add_child(cs)


func _wall_top_near(p: Vector2) -> float:
	var best := INF
	var top := plan.wall_ref_ground + plan.wall_height
	for piece in plan.wall_pieces:
		var d := TerrainData.seg_dist(p, piece["a"], piece["b"])
		if d < best:
			best = d
			top = piece["top"]
	return top


## Unit vector pointing out of the kingdom at the wall nearest to p.
func _outward_at(p: Vector2) -> Vector2:
	var best := INF
	var out := Vector2.RIGHT
	for s in plan.wall_points.size() - 1:
		var a := plan.wall_points[s]
		var b := plan.wall_points[s + 1]
		var d := TerrainData.seg_dist(p, a, b)
		if d < best:
			best = d
			var dir := (b - a).normalized()
			out = Vector2(dir.y, -dir.x)
	return out


# --- the great gate ------------------------------------------------------------------------

func _build_gate() -> void:
	var g := plan.gate
	if g.is_empty():
		return
	var c: Vector2 = g["center_v"]
	var inward := -_outward_at(c)
	var along := Vector2(-inward.y, inward.x)
	var yaw := _yaw_along(along)
	var basis := Basis(Vector3.UP, yaw)
	var width := float(g["width"])
	var spring := float(g["height"]) - 2.0
	var depth := float(g["depth"])
	var offset := float(g["tower_offset"])
	var tdia := float(g["tower_diameter"])
	var ground := td.height_at(c.x, c.y)
	var lo := ground
	for s: float in [-1.0, 1.0]:
		for q: float in [-1.0, 1.0]:
			var pt := c + along * s * (offset + tdia * 0.5) + inward * q * depth * 0.5
			lo = minf(lo, td.height_at(pt.x, pt.y))
	var walk := _wall_top_near(c + along * (offset + tdia + 6.0))
	var block_top := walk + 3.5
	var arch_r := width * 0.5 + 0.5
	var arch_top := ground + spring + arch_r * 0.75 + 1.0
	var root_name := root.name
	# The arch itself is the shared archway piece; the gate block is built around it.
	var arch := _piece("arch", Vector3(c.x, ground - 0.1, c.y), rad_to_deg(yaw), Vector3(width, spring, depth), 0.0)
	arch.name = "GreatGateArch"
	var col := WALL_STONE * 0.97
	for s: float in [-1.0, 1.0]:
		var side := c + along * s * (width * 0.5 + 1.0 + (offset - width * 0.5 - 1.0) * 0.5)
		var span := offset - width * 0.5 - 1.0 + 1.0
		_stone_detail.add_box(Transform3D(basis, Vector3(side.x, (lo - 1.0 + block_top) * 0.5, side.y)), Vector3(span, block_top - lo + 1.0, depth), col)
	_stone_detail.add_box(Transform3D(basis, Vector3(c.x, (arch_top + block_top) * 0.5, c.y)), Vector3(width + 2.4, block_top - arch_top, depth), col)
	# Machicolated parapet over the gate passage, facing the field.
	for m in 9:
		var q := c + along * (-offset + offset * 2.0 * float(m) / 8.0) + inward * (depth * 0.5 + 0.15)
		_detail.add_box(Transform3D(basis, Vector3(q.x, block_top + 0.85, q.y)), Vector3(1.6, 1.4, 0.8), Sites.tagged(PropMeshes.ROCK * 0.9, Sites.SURF_RUBBLE))
		_detail.add_box(Transform3D(basis, Vector3(q.x, block_top - 0.55, q.y)), Vector3(0.5, 1.0, 0.9), Sites.tagged(PropMeshes.ROCK * 0.8, Sites.SURF_RUBBLE))
	_stone_detail.add_box(Transform3D(basis, Vector3(c.x + inward.x * (depth * 0.5 + 0.4), block_top - 0.05, c.y + inward.y * (depth * 0.5 + 0.4))),
		Vector3(offset * 2.0, 0.5, 1.0), col * 0.85)
	# Closed oak leaves, iron-banded and studded, filling the arch.
	var leaf_face := c + inward * 0.4
	var plank := Sites.tagged(OAK_LEAF, Sites.SURF_PLANK)
	var iron := Sites.tagged(IRON, Sites.SURF_IRON)
	for s: float in [-1.0, 1.0]:
		var lc := leaf_face + along * s * width * 0.25
		_detail.add_box(Transform3D(basis, Vector3(lc.x, ground + spring * 0.5, lc.y)), Vector3(width * 0.5 - 0.04, spring, 0.5), plank)
		for y in 6:
			var by := ground + 0.8 + float(y) * (spring - 1.4) / 5.0
			var band := lc + inward * 0.27
			_detail.add_box(Transform3D(basis, Vector3(band.x, by, band.y)), Vector3(width * 0.5 - 0.3, 0.2, 0.06), iron)
			for st in 5:
				var sp := band + along * (-width * 0.2 + width * 0.1 * float(st)) + inward * 0.05
				_detail.add_box(Transform3D(basis, Vector3(sp.x, by + 0.35, sp.y)), Vector3(0.12, 0.12, 0.06), iron)
		var ring := lc - along * s * (width * 0.18) + inward * 0.35
		_detail.add_cylinder(Transform3D(basis * Basis(Vector3.RIGHT, PI * 0.5), Vector3(ring.x, ground + spring * 0.45, ring.y)), 0.32, 0.32, 0.06, 10, iron)
	# Tympanum boards fill the arch head above the leaves.
	for row in 5:
		var y := ground + spring + float(row) * arch_r * 0.75 / 5.0 + 0.2
		var frac := float(row + 0.5) / 5.0
		var half := arch_r * sqrt(maxf(0.0, 1.0 - frac * frac)) - 0.35
		if half > 0.3:
			_detail.add_box(Transform3D(basis, Vector3(leaf_face.x, y, leaf_face.y)), Vector3(half * 2.0, arch_r * 0.75 / 5.0 + 0.02, 0.45), plank)
	# A lowered portcullis on the town side.
	var pc := c + inward * (plan.wall_thickness * 0.5 + 0.25)
	var pbars := int(width / 0.55)
	for i in pbars + 1:
		var q := pc + along * (-width * 0.5 + width * float(i) / pbars)
		_detail.add_box(Transform3D(basis, Vector3(q.x, ground + spring * 0.5 + 0.2, q.y)), Vector3(0.14, spring + 0.4, 0.14), iron)
	for y in 7:
		_detail.add_box(Transform3D(basis, Vector3(pc.x, ground + 0.4 + float(y) * spring / 6.5, pc.y)), Vector3(width, 0.12, 0.16), iron)
	# Flanking towers with slate cones and maroon banners.
	for s: float in [-1.0, 1.0]:
		var tp := c + along * s * offset
		var ttop := ground + float(g["tower_height"])
		var tlo := INF
		for a in 8:
			var q := tp + Vector2(cos(TAU * a / 8.0), sin(TAU * a / 8.0)) * tdia * 0.5
			tlo = minf(tlo, td.height_at(q.x, q.y))
		_tower(tp, tlo - 1.0, ttop, tdia)
		sites._castle_roof(_detail, tp, tdia * 0.5 + 0.7, ttop + 0.4, tdia * 0.95, Sites.SLATE)
		sites._castle_banner(_banners, Vector3(tp.x, ttop + tdia * 0.95 + 0.2, tp.y), MAROON)
		for y: float in [ttop - 5.0, ttop - 11.0]:
			var q := tp + inward * (tdia * 0.5 - 0.05)
			_detail.add_box(Transform3D(basis, Vector3(q.x, y, q.y)), Vector3(0.3, 1.6, 0.3), Color(0.03, 0.03, 0.035))
		# Long hanging banners on the gate face, toward the field.
		var hb := c + along * s * (width * 0.5 + 2.6) + inward * (depth * 0.5 + 0.08)
		sites._castle_banner_hanging(_detail, Vector3(hb.x, block_top - 1.0, hb.y), Vector3(inward.x, 0, inward.y), 2.2, 6.5,
			Sites.tagged(MAROON, Sites.SURF_CLOTH), Sites.GOLD_TRIM)
		# Lit braziers either side of the approach.
		var bz := c + along * s * (width * 0.5 + 4.5) + inward * (depth * 0.5 + 3.0)
		_piece("brazier", Vector3(bz.x, td.height_at(bz.x, bz.y) - 0.05, bz.y), 0.0, Vector3.ONE, 0.0)
	# The gate is sealed: a solid block fills the whole gatehouse width and
	# reaches far above it. Nothing here is interactable.
	var seal := StaticBody3D.new()
	seal.name = "GreatGateSeal"
	seal.collision_layer = Layers.WORLD
	seal.collision_mask = 0
	seal.set_meta("sealed", true)
	root.add_child(seal)
	var seal_len := (offset + tdia * 0.5) * 2.0
	_add_box_collision(seal, Transform3D(basis, Vector3(c.x, (lo - 2.0 + block_top + BARRIER_ABOVE) * 0.5, c.y)),
		Vector3(seal_len, block_top + BARRIER_ABOVE - lo + 2.0, plan.wall_thickness))
	_add_box_collision(seal, Transform3D(basis, Vector3(leaf_face.x, (lo - 1.0 + arch_top) * 0.5, leaf_face.y)), Vector3(width + 1.0, arch_top - lo + 1.0, 0.8))
	sites.story_anchors["great_gate"] = {"pos": Vector3(c.x + inward.x * (depth * 0.5 + 6.0), ground, c.y + inward.y * (depth * 0.5 + 6.0)), "yaw": atan2(-inward.x, -inward.y)}
	var _unused := root_name


func _build_water_gates() -> void:
	for wg in plan.water_gates:
		var c: Vector2 = wg["center"]
		var dir: Vector2 = wg["dir"]
		var span: float = wg["span"]
		# Rounded cutwaters on both banks carry the arch.
		for s: float in [-1.0, 1.0]:
			var p := c + dir * s * (span * 0.5 + 0.6)
			var h := td.height_at(p.x, p.y)
			var base_y := minf(h, world.water_level) - 3.0
			_tower_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, base_y, p.y)), 1.9, 1.6, world.water_level + 6.5 - base_y, 14, WALL_STONE * 0.85)
			_tower_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(p.x, world.water_level + 6.5, p.y)), 1.6, 0.0, 1.4, 14, WALL_STONE * 0.75)


# --- houses and stalls -----------------------------------------------------------------------

func _archetype(arch: String) -> Dictionary:
	if _arch_cache.has(arch):
		return _arch_cache[arch]
	var def: Dictionary = KingdomPlan.ARCHETYPES[arch]
	var k := MeshKit.new(hash(arch) & 0xffff, 0.035)
	var glow := MeshKit.new(hash(arch) & 0xffff + 1)
	var saved := vb.glow
	vb.glow = glow
	var g := vb.house_geometry(k, Transform3D.IDENTITY, float(def["w"]), float(def["d"]), def["o"])
	vb.glow = saved
	var entry := {"mesh": k.to_mesh(HOUSE_MAT), "glow": glow.to_mesh(GLOW_WARM) if not glow.is_empty() else null,
		"solid_box": g["solid_box"], "chimney_boxes": g["chimney_boxes"]}
	_arch_cache[arch] = entry
	return entry


func _build_houses() -> void:
	var groups := {}
	for h in plan.houses:
		# One MultiMesh per archetype per ~160 m area keeps draw calls low while
		# still letting distant areas cull (and stay under 8 lights per mesh).
		var c0: Vector2 = h["center"]
		var key := "%d_%d|%s" % [floori(c0.x / 160.0), floori(c0.y / 160.0), h["archetype"]]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(h)
	var bodies := {}
	for key in groups:
		var list: Array = groups[key]
		var arch := _archetype(list[0]["archetype"])
		var transforms: Array[Transform3D] = []
		var tints: Array[Color] = []
		for h in list:
			var district: String = h["district"]
			if not bodies.has(district):
				var body := StaticBody3D.new()
				body.name = "Houses_" + district.replace(" ", "").replace("'", "")
				body.collision_layer = Layers.WORLD
				body.collision_mask = 0
				root.add_child(body)
				bodies[district] = body
			var c: Vector2 = h["center"]
			var xf := Transform3D(Basis(Vector3.UP, h["yaw"]), Vector3(c.x, h["base"], c.y))
			transforms.append(xf)
			tints.append(h["tint"])
			var solid: Array = arch["solid_box"]
			_add_box_collision(bodies[district], xf * Transform3D(Basis.IDENTITY, solid[0]), solid[1])
			for cb: Array in arch["chimney_boxes"]:
				_add_box_collision(bodies[district], xf * Transform3D(Basis.IDENTITY, cb[0]), cb[1])
		var node_name := String(key).replace("|", "_").replace(" ", "").replace("'", "")
		_multimesh(arch["mesh"], transforms, tints, "HouseMM_" + node_name, true, 420.0)
		if arch["glow"]:
			_multimesh(arch["glow"], transforms, [], "HouseGlowMM_" + node_name, false, 420.0)


func _multimesh(mesh: Mesh, transforms: Array[Transform3D], tints: Array, node_name: String, shadows: bool, range_end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not tints.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, tints[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = range_end
	root.add_child(mmi)
	return mmi


## A market stall at the origin: back on local +z, counter at the front (-z).
func _stall_mesh(variant: int) -> Mesh:
	var key := "stall_%d" % variant
	if _arch_cache.has(key):
		return _arch_cache[key]
	var k := MeshKit.new(9300 + variant, 0.04)
	var xf := Transform3D.IDENTITY
	var w := KingdomPlan.STALL_W
	var d := KingdomPlan.STALL_D
	var post := VillageBuilder.c(0.22, 0.15, 0.1, VillageBuilder.PLANK)
	var board := VillageBuilder.c(0.36, 0.26, 0.16, VillageBuilder.PLANK)
	var stripes: Array = [[VillageBuilder.c(0.46, 0.1, 0.08, VillageBuilder.CLOTH), VillageBuilder.c(0.62, 0.56, 0.42, VillageBuilder.CLOTH)],
		[VillageBuilder.c(0.55, 0.42, 0.14, VillageBuilder.CLOTH), VillageBuilder.c(0.6, 0.55, 0.42, VillageBuilder.CLOTH)],
		[VillageBuilder.c(0.18, 0.26, 0.3, VillageBuilder.CLOTH), VillageBuilder.c(0.58, 0.54, 0.44, VillageBuilder.CLOTH)]][variant % 3]
	for sx: float in [-0.5, 0.5]:
		vb.beam(k, xf, Vector3(sx * (w - 0.2), 0, -d * 0.5 + 0.15), Vector3(sx * (w - 0.2), 2.25, -d * 0.5 + 0.15), 0.11, post)
		vb.beam(k, xf, Vector3(sx * (w - 0.2), 0, d * 0.5 - 0.15), Vector3(sx * (w - 0.2), 2.55, d * 0.5 - 0.15), 0.11, post)
	var tilt := atan2(0.3, d)
	var n := int(w / 0.42)
	for i in n:
		var x := -w * 0.5 + (float(i) + 0.5) * w / n
		vb.box(k, xf, Vector3(x, 2.45, 0), Vector3(w / n + 0.01, 0.04, d + 0.5), stripes[i % 2], Basis(Vector3.RIGHT, -tilt))
	# Scalloped valance along the front edge.
	for i in n:
		var x := -w * 0.5 + (float(i) + 0.5) * w / n
		vb.box(k, xf, Vector3(x, 2.12, -d * 0.5 - 0.22), Vector3(w / n - 0.04, 0.26, 0.03), stripes[(i + 1) % 2])
	vb.box(k, xf, Vector3(0, 0.88, -d * 0.5 + 0.45), Vector3(w - 0.3, 0.08, 0.8), board)
	vb.box(k, xf, Vector3(0, 0.44, -d * 0.5 + 0.45), Vector3(w - 0.4, 0.84, 0.7), VillageBuilder.c(0.3, 0.21, 0.13, VillageBuilder.PLANK))
	vb.box(k, xf, Vector3(0, 1.1, d * 0.5 - 0.2), Vector3(w - 0.3, 2.0, 0.06), stripes[1])
	var goods: Array = [[Color(0.55, 0.12, 0.08), Color(0.32, 0.45, 0.16), Color(0.6, 0.44, 0.16)],
		[Color(0.72, 0.6, 0.36), Color(0.55, 0.4, 0.22), Color(0.66, 0.5, 0.3)],
		[Color(0.3, 0.32, 0.36), Color(0.45, 0.28, 0.18), Color(0.5, 0.48, 0.44)]][variant % 3]
	for i in 4:
		var p := Vector3(-w * 0.36 + float(i) * w * 0.24, 0.93, -d * 0.5 + 0.45)
		k.add_cylinder(Transform3D(Basis.IDENTITY, p), 0.2, 0.24, 0.18, 9, VillageBuilder.c(0.42, 0.32, 0.2, VillageBuilder.PLANK))
		for j in 4:
			k.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.075), p + Vector3(-0.07 + float(j % 2) * 0.14, 0.22, -0.05 + float(j / 2) * 0.1)), 1.0, goods[(i + j) % 3], false, 0.0)
	for p: Vector3 in [Vector3(-w * 0.3, 0.3, d * 0.5 - 0.6), Vector3(w * 0.28, 0.3, d * 0.5 - 0.55)]:
		vb.box(k, xf, p, Vector3(0.6, 0.6, 0.6), VillageBuilder.c(0.36, 0.27, 0.17, VillageBuilder.PLANK))
	var mesh := k.to_mesh(HOUSE_MAT)
	_arch_cache[key] = mesh
	return mesh


func _build_stalls() -> void:
	if plan.stalls.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "MarketStalls"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	root.add_child(body)
	var by_variant := {}
	for st in plan.stalls:
		var v: int = st["variant"]
		if not by_variant.has(v):
			by_variant[v] = []
		var c: Vector2 = st["center"]
		var xf := Transform3D(Basis(Vector3.UP, st["yaw"]), Vector3(c.x, st["base"], c.y))
		by_variant[v].append(xf)
		_add_box_collision(body, xf * Transform3D(Basis.IDENTITY, Vector3(0, 1.1, 0.15)), Vector3(KingdomPlan.STALL_W - 0.1, 2.2, KingdomPlan.STALL_D - 0.1))
	for v in by_variant:
		var list: Array[Transform3D] = []
		list.assign(by_variant[v])
		_multimesh(_stall_mesh(v), list, [], "MarketStallsMM_%d" % v, true, 260.0)


# --- cemetery ---------------------------------------------------------------------------------

func _build_cemetery() -> void:
	var cem: Dictionary = plan.k.get("cemetery", {})
	if cem.is_empty():
		return
	var c := WorldLayout.v2(cem["center"])
	var fr := float(cem["fence_radius"])
	var body := StaticBody3D.new()
	body.name = "CemeteryGraves"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	root.add_child(body)
	var grave_root := Node3D.new()
	grave_root.name = "MemorialCemetery"
	root.add_child(grave_root)
	var mound_kit := MeshKit.new(9401, 0.08)
	for g in plan.graves:
		var p: Vector2 = g["pos"]
		var radial := (p - c).normalized()
		var tangent := Vector2(-radial.y, radial.x)
		var gy := td.height_at(p.x, p.y)
		var yaw := _yaw_along(tangent)
		var marker := Marker3D.new()
		marker.name = "Grave_%02d" % (int(g["index"]) + 1)
		marker.position = Vector3(p.x, gy, p.y)
		marker.add_to_group("memorial_graves")
		grave_root.add_child(marker)
		_cross(int(g["variant"]), int(g["index"]), Vector3(p.x, gy, p.y), yaw, float(g["lean"]), body)
		# Low turf mound over each grave, running away from the tree.
		var m := p + radial * 1.25
		var my := td.height_at(m.x, m.y)
		mound_kit.add_blob(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(0.62, 0.16, 1.05)), Vector3(m.x, my - 0.04, m.y)), 1.0,
			Color(0.16, 0.2, 0.09) * (0.9 + 0.1 * float(int(g["index"]) % 3)), true, 0.12)
		if int(g["index"]) % 3 != 1:
			var kinds := ["memorial:0", "memorial:4", "memorial:2", "memorial:3"]
			sites.flower_patches.append([m + tangent * (0.9 if int(g["index"]) % 2 == 0 else -0.9), 0.75 + 0.15 * float(int(g["index"]) % 3), kinds[int(g["index"]) % 4]])
	_emit_kit(mound_kit, Sites.PROPS_MAT, false, "GraveMounds", 160.0)
	# Dry-stone fence with gateposts at each path.
	for arc in plan.fence_arcs:
		var a0 := deg_to_rad(float(arc[0]))
		var a1 := deg_to_rad(float(arc[1]))
		var steps := maxi(2, int(ceil((a1 - a0) * fr / 3.5)))
		var pts: Array = []
		for i in steps + 1:
			var a := lerpf(a0, a1, float(i) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * fr)
		vb._dry_stone_wall(pts)
	var gate_half := rad_to_deg(float(cem["gate_width"]) * 0.5 / fr)
	for ga in plan.fence_gates:
		for s: float in [-1.0, 1.0]:
			var a := deg_to_rad(ga + s * (gate_half + 0.6))
			var p := c + Vector2(cos(a), sin(a)) * fr
			var gy := td.height_at(p.x, p.y)
			_piece("block", Vector3(p.x, gy - 0.25, p.y), rad_to_deg(-a), Vector3(0.75, 1.85, 0.75), 0.0)
			_stone_detail.add_box(Transform3D(Basis(Vector3.UP, -a), Vector3(p.x, gy + 1.7, p.y)), Vector3(0.95, 0.22, 0.95), WALL_STONE * 1.1)
			_stone_detail.add_box(Transform3D(Basis(Vector3.UP, -a + PI * 0.25), Vector3(p.x, gy + 1.92, p.y)), Vector3(0.42, 0.28, 0.42), WALL_STONE * 1.05)
	# The memorial stone at the main gate, readable from the path.
	var pl: Dictionary = cem["plaque"]
	var pp := WorldLayout.v2(pl["pos"]) + c
	var facing := deg_to_rad(float(pl["facing_deg"]))
	var face_dir := Vector2(cos(facing), sin(facing))
	var py := td.height_at(pp.x, pp.y)
	var stone_yaw := _yaw_along(Vector2(-face_dir.y, face_dir.x))
	var stone := _piece("block", Vector3(pp.x, py - 0.25, pp.y), rad_to_deg(stone_yaw), Vector3(2.9, 2.05, 0.75), 0.0)
	stone.name = "MemorialStone"
	_piece("block", Vector3(pp.x, py - 0.3, pp.y), rad_to_deg(stone_yaw), Vector3(3.5, 0.45, 1.3), 0.0)
	var face := Vector3(pp.x + face_dir.x * 0.39, py, pp.y + face_dir.y * 0.39)
	var label_yaw := atan2(face_dir.x, face_dir.y)
	var title := Label3D.new()
	title.name = "MemorialTitle"
	title.text = String(pl["title"])
	title.font_size = 44
	title.pixel_size = 0.0052
	title.modulate = Color(0.86, 0.82, 0.7)
	title.outline_size = 5
	title.outline_modulate = Color(0.08, 0.07, 0.06)
	title.double_sided = false
	title.position = face + Vector3(0, 1.48, 0)
	title.rotation.y = label_yaw
	grave_root.add_child(title)
	var label := Label3D.new()
	label.name = "MemorialInscription"
	label.text = String(pl["text"])
	label.font_size = 30
	label.pixel_size = 0.0046
	label.line_spacing = 2.0
	label.modulate = Color(0.84, 0.8, 0.68)
	label.outline_size = 4
	label.outline_modulate = Color(0.08, 0.07, 0.06)
	label.double_sided = false
	label.position = face + Vector3(0, 0.8, 0)
	label.rotation.y = label_yaw
	grave_root.add_child(label)
	sites.flower_patches.append([pp + face_dir * 1.3, 1.6, "memorial:0"])
	sites.flower_patches.append([pp + face_dir * 1.1 + Vector2(-face_dir.y, face_dir.x) * 1.8, 0.9, "memorial:4"])
	# A few broad drifts along the inside of the fence between the grave clusters.
	var drift_kinds := ["memorial:3", "memorial:0", "memorial:2", "memorial:4"]
	var drift := 0
	for arc in plan.fence_arcs:
		var mid := deg_to_rad((float(arc[0]) + float(arc[1])) * 0.5 + 6.0)
		var q := c + Vector2(cos(mid), sin(mid)) * (fr - 1.6)
		sites.flower_patches.append([q, 1.7, drift_kinds[drift % 4]])
		drift += 1
	# Two benches facing the tree, and lanterns at the main gate.
	var main := deg_to_rad(float(cem["main_gate_deg"]))
	for s: float in [-1.0, 1.0]:
		var a := main + s * deg_to_rad(24.0)
		var bp := c + Vector2(cos(a), sin(a)) * 21.6
		vb._bench(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(bp.x, td.height_at(bp.x, bp.y), bp.y)), Vector3.ZERO, 0.0, 1.9)
		var lp := c + Vector2(cos(main + s * deg_to_rad(gate_half + 4.0)), sin(main + s * deg_to_rad(gate_half + 4.0))) * (fr + 1.6)
		vb._lantern_post(lp)
	sites.story_anchors["memorial_stone"] = {"pos": Vector3(pp.x + face_dir.x * 3.0, py, pp.y + face_dir.y * 3.0), "yaw": atan2(-face_dir.x, -face_dir.y)}


## One grave marker. Six cross designs, each grave a little different in size,
## tint and lean. Local +x runs along the row; the cross faces the tree.
func _cross(variant: int, index: int, at: Vector3, yaw: float, lean_deg: float, body: StaticBody3D) -> void:
	var h := 1.4 + 0.1 * float(index % 4) + (0.3 if variant == 4 else 0.0)
	var arm := 0.42 + 0.04 * float(index % 3)
	var t := 0.17 + 0.015 * float(index % 2)
	var tint := 0.88 + 0.06 * float(index % 4)
	var stone := Color(0.52, 0.51, 0.48) * tint
	var lean := Basis(Vector3.RIGHT, deg_to_rad(lean_deg if variant == 5 else lean_deg * 0.25))
	var base := Basis(Vector3.UP, yaw) * lean
	var xf := Transform3D(base, at + Vector3(0, -0.05, 0))
	var kit := _stone_detail
	var col := stone
	if variant == 3:
		kit = _wood
		col = VillageBuilder.c(0.3, 0.22, 0.14, VillageBuilder.PLANK)
		_stone_detail.add_box(Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0.08, 0)), Vector3(0.5, 0.22, 0.4), stone * 0.9)
	elif variant == 5:
		col = Color(0.42, 0.45, 0.38) * tint
	# Plinth (stepped for variant 4).
	if variant != 3:
		kit.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), Vector3(0.62, 0.3, 0.42), stone * 0.92)
		if variant == 4:
			kit.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.36, 0)), Vector3(0.46, 0.2, 0.32), stone * 0.95)
	var foot := 0.46 if variant == 4 else 0.26
	kit.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0, foot + h * 0.5, 0)), Vector3(t, h, t), col)
	var bar_y := foot + h * 0.7
	kit.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0, bar_y, 0)), Vector3(arm * 2.0, t * 0.95, t * 0.95), col)
	match variant:
		1:
			# Celtic ring around the crossing.
			var r := arm * 0.55
			for i in 12:
				var a := TAU * float(i) / 12.0
				kit.add_box(xf * Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a) * r, bar_y + sin(a) * r, 0)), Vector3(0.06, r * 0.56, t * 0.7), col)
		2:
			# Bottony ends.
			for e: Vector3 in [Vector3(arm, bar_y, 0), Vector3(-arm, bar_y, 0), Vector3(0, foot + h, 0)]:
				kit.add_box(xf * Transform3D(Basis.IDENTITY, e), Vector3(t * 1.5, t * 1.5, t * 1.2), col)
		3:
			# Lashing where the planks cross.
			kit.add_box(xf * Transform3D(Basis(Vector3.BACK, 0.7), Vector3(0, bar_y, 0)), Vector3(0.04, t * 1.6, t + 0.02), VillageBuilder.c(0.5, 0.42, 0.28, VillageBuilder.CLOTH))
	var shape_xf := Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 0.95, 0))
	_add_box_collision(body, shape_xf, Vector3(0.62, 1.9, 0.42))


# --- training ground ---------------------------------------------------------------------------

func _build_training_ground() -> void:
	var tg: Dictionary = plan.k.get("training_ground", {})
	if tg.is_empty():
		return
	var site := world.layout.find_site(tg["site"])
	if site.is_empty():
		return
	var c := WorldLayout.v2(site["center"])
	var markers := Node3D.new()
	markers.name = "TrainingGround"
	root.add_child(markers)
	var post := VillageBuilder.c(0.27, 0.19, 0.12, VillageBuilder.PLANK)
	var straw := VillageBuilder.c(0.62, 0.52, 0.3, VillageBuilder.THATCH)
	# Pells (striking posts) with a cross arm and a battered shield board.
	for p in tg.get("pells", []):
		var w := c + WorldLayout.v2(p)
		var y := td.height_at(w.x, w.y)
		var xf := Transform3D(Basis.IDENTITY, Vector3(w.x, y, w.y))
		vb.beam(_wood, xf, Vector3(0, -0.3, 0), Vector3(0, 1.85, 0), 0.24, post)
		vb.beam(_wood, xf, Vector3(-0.55, 1.35, 0), Vector3(0.55, 1.35, 0), 0.1, post)
		vb.box(_wood, xf, Vector3(0, 1.0, -0.15), Vector3(0.5, 0.6, 0.05), VillageBuilder.c(0.42, 0.12, 0.1, VillageBuilder.CLOTH))
		vb._collide(xf, Vector3(0, 0.9, 0), Vector3(0.35, 1.8, 0.35))
	# Straw archery butts on trestles facing into the yard.
	for p in tg.get("butts", []):
		var w := c + WorldLayout.v2(p)
		var y := td.height_at(w.x, w.y)
		var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(w.x, y, w.y))
		for sx: float in [-0.55, 0.55]:
			vb.beam(_wood, xf, Vector3(sx, 0, 0.35), Vector3(sx, 1.6, -0.05), 0.09, post)
		_wood.add_cylinder(xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.15), Vector3(0, 1.15, -0.1)), 0.62, 0.62, 0.42, 14, straw)
		for ring in 3:
			var r := 0.5 - float(ring) * 0.16
			var ring_col := VillageBuilder.c(0.55, 0.1, 0.08, VillageBuilder.CLOTH) if ring % 2 == 0 else VillageBuilder.c(0.8, 0.76, 0.62, VillageBuilder.CLOTH)
			_wood.add_cylinder(xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.15), Vector3(0, 1.15 + 0.01 * ring, -0.33 - 0.01 * ring)), r, r, 0.02, 14, ring_col)
		vb._collide(xf, Vector3(0, 0.9, 0.1), Vector3(1.4, 1.8, 0.7))
	# Weapon racks against the walls.
	for p in tg.get("racks", []):
		var w := c + Vector2(float(p[0]), float(p[1]))
		var y := td.height_at(w.x, w.y)
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[2]))), Vector3(w.x, y, w.y))
		for sx: float in [-0.9, 0.9]:
			vb.beam(_wood, xf, Vector3(sx, 0, 0), Vector3(sx, 1.7, 0), 0.1, post)
		for yy: float in [0.35, 1.25]:
			vb.beam(_wood, xf, Vector3(-0.95, yy, 0), Vector3(0.95, yy, 0), 0.08, post)
		for i in 5:
			var x := -0.7 + float(i) * 0.35
			vb.beam(_wood, xf, Vector3(x, 0.05, 0.12), Vector3(x + 0.05, 2.3, -0.05), 0.045, VillageBuilder.c(0.36, 0.27, 0.17, VillageBuilder.PLANK))
			vb.box(_wood, xf, Vector3(x + 0.05, 2.38, -0.06), Vector3(0.06, 0.2, 0.03), VillageBuilder.c(0.5, 0.52, 0.55, VillageBuilder.IRON))
		vb._collide(xf, Vector3(0, 0.9, 0), Vector3(2.0, 1.8, 0.45))
	# Phase 3: positions for maroon-armoured, helmeted soldiers at the corners.
	# No compatible soldier model exists yet, so these are markers only.
	var i := 0
	for p in tg.get("soldier_posts", []):
		var w := c + WorldLayout.v2(p)
		var m := Marker3D.new()
		m.name = "SoldierPost_%d" % (i + 1)
		m.position = Vector3(w.x, td.height_at(w.x, w.y), w.y)
		m.rotation.y = atan2(-(c.x + 1.0 - w.x), -(c.y - 15.0 - w.y))
		m.set_meta("phase", 3)
		m.set_meta("unit", "kingdom soldier, maroon armour, helmet")
		m.add_to_group("phase3_soldier_posts")
		markers.add_child(m)
		i += 1
	for area in tg.get("formation_areas", []):
		var m := Marker3D.new()
		m.name = "Formation_" + String(area["name"]).replace(" ", "")
		var w := WorldLayout.v2(area["world"]) if area.has("world") else c + WorldLayout.v2(area["center"])
		m.position = Vector3(w.x, td.height_at(w.x, w.y), w.y)
		m.set_meta("area", area)
		m.add_to_group("phase3_formation_areas")
		markers.add_child(m)


# --- missions -------------------------------------------------------------------------------------

func _build_mission_markers() -> void:
	var holder := Node3D.new()
	holder.name = "MissionAreas"
	root.add_child(holder)
	for m in plan.k.get("missions", []):
		var node := Node3D.new()
		node.name = "Mission%s_%s" % [m["id"], String(m["name"]).replace(" ", "")]
		node.set_meta("mission", m)
		node.add_to_group("phase3_mission_areas")
		holder.add_child(node)
		if m.has("center"):
			var c := WorldLayout.v2(m["center"])
			node.position = Vector3(c.x, td.height_at(c.x, c.y), c.y)
		var n := 0
		for sp in plan.spy_points:
			if not m.has("spawn_points"):
				break
			var p: Vector2 = sp["pos"]
			var mk := Marker3D.new()
			mk.name = "SpySpawn_%02d" % (n + 1)
			mk.position = Vector3(p.x, td.height_at(p.x, p.y), p.y)
			mk.set_meta("route", sp["route"])
			mk.add_to_group("phase3_spy_spawns")
			node.add_child(mk)
			n += 1


# --- lanterns ---------------------------------------------------------------------------------------

func _build_lanterns() -> void:
	var spots: Array[Vector2] = [Vector2(206, 79), Vector2(258, 110), Vector2(206, 110),
		Vector2(140, 172), Vector2(186, 210), Vector2(250, 214), Vector2(160, 248), Vector2(270, 150),
		Vector2(-270, 62), Vector2(-270, 78), Vector2(108, 186)]
	for p in spots:
		var ok := td.sample(td.trail_dist, p.x, p.y) > 0.4
		for h in plan.houses + plan.stalls:
			if p.distance_to(h["center"]) < sqrt(float(h["w"]) ** 2 + float(h["d"]) ** 2) * 0.5 + 1.0:
				ok = false
		for z in plan.fight_zones:
			if KingdomPlan.zone_distance(z, p) < 0.5:
				ok = false
		if ok:
			vb._lantern_post(p)


# --- horizon -----------------------------------------------------------------------------------------

## Countryside beyond the terrain edge: rolling wooded foothills to the south,
## east and west, and layered mountain silhouettes receding into atmospheric haze.
func _build_horizon() -> void:
	var half := world.layout.half_size
	var rings: Array[float] = [-3.0, 8.0, 24.0, 48.0, 82.0, 130.0, 200.0, 300.0, 440.0, 620.0, 860.0, 1180.0, 1550.0]
	var per_side := 64
	var count := per_side * 4
	var noise := FastNoiseLite.new()
	noise.seed = GameState.world_seed + 909
	noise.frequency = 1.0 / 280.0
	noise.fractal_octaves = 4
	var ridge := FastNoiseLite.new()
	ridge.seed = GameState.world_seed + 913
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.frequency = 1.0 / 340.0
	ridge.fractal_octaves = 4
	var detail := FastNoiseLite.new()
	detail.seed = GameState.world_seed + 910
	detail.frequency = 1.0 / 95.0
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for ri in rings.size():
		var s := half + rings[ri]
		for i in count:
			var p := _horizon_point(i, per_side, s)
			var h := _horizon_height(p, rings[ri], noise, ridge, detail, ri == 0)
			var m := td.mountain_weight(p.x, p.y)
			var woods := clampf(detail.get_noise_2d(p.y, p.x) * 0.6 + 0.35, 0.0, 0.55) * (1.0 - m * 0.7)
			verts.append(Vector3(p.x, h, p.y))
			cols.append(Color(0.0, woods, 0.0, 0.0))
	var idx := PackedInt32Array()
	for ri in rings.size() - 1:
		for i in count:
			var a := ri * count + i
			var b := ri * count + (i + 1) % count
			var c := (ri + 1) * count + (i + 1) % count
			var d := (ri + 1) * count + i
			idx.append_array([a, c, b, a, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, DISTANT_MOUNTAIN_MAT)
	var mi := MeshInstance3D.new()
	mi.name = "HorizonCountryside"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 350.0
	root.add_child(mi)
	# Woodland silhouettes on the near countryside (far-LOD tree meshes only).
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	var trees := {"pine_far": [], "oak_far": [], "fir_far": []}
	for n in 1500:
		var band := rng.randf_range(4.0, 180.0)
		var i := rng.randi_range(0, count - 1)
		var p := _horizon_point(i, per_side, half + band) + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
		if td.mountain_weight(p.x, p.y) > 0.35:
			continue
		if detail.get_noise_2d(p.y, p.x) < -0.15 and rng.randf() < 0.75:
			continue
		var h := _horizon_height(p, band, noise, ridge, detail, false) - 1.2
		var kind: String = ["pine_far", "oak_far", "fir_far", "pine_far"][rng.randi_range(0, 3)]
		var sc := rng.randf_range(0.9, 1.55)
		trees[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(p.x, h, p.y)))
	for kind in trees:
		var list: Array[Transform3D] = []
		list.assign(trees[kind])
		if not list.is_empty():
			_multimesh(PropMeshes.get_mesh(kind), list, [], "HorizonTrees_" + kind, false, 0.0)


func _horizon_point(i: int, per_side: int, s: float) -> Vector2:
	var side := i / per_side
	var f := float(i % per_side) / per_side
	match side:
		0: return Vector2(lerpf(-s, s, f), -s)
		1: return Vector2(s, lerpf(-s, s, f))
		2: return Vector2(lerpf(s, -s, f), s)
	return Vector2(-s, lerpf(s, -s, f))


## Height of the countryside beyond the terrain edge, `beyond` metres out.
func _horizon_height(p: Vector2, beyond: float, noise: FastNoiseLite, ridge: FastNoiseLite, detail: FastNoiseLite, inner: bool) -> float:
	var half := world.layout.half_size
	var edge := Vector2(clampf(p.x, -half, half), clampf(p.y, -half, half))
	var edge_h := td.height_at(edge.x, edge.y)
	if inner:
		return edge_h - 1.5
	var m := td.mountain_weight(p.x, p.y)
	var t := clampf(beyond / 1550.0, 0.0, 1.0)
	var nval := noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	var rval := clampf(ridge.get_noise_2d(p.x, p.y) * 0.5 + 0.5, 0.0, 1.0)
	var dval := detail.get_noise_2d(p.x, p.y)
	# Near foothills stay gentle; distant horizon rises into layered ridged mountain ranges.
	var hills := 14.0 + nval * 38.0 + dval * 12.0 + (45.0 + rval * 95.0) * smoothstep(0.28, 0.95, t)
	var peaks := 72.0 + rval * 135.0 + nval * 55.0 + dval * 18.0 + 95.0 * smoothstep(0.22, 0.88, t)
	var far := lerpf(hills, peaks, m)
	return lerpf(edge_h, far, smoothstep(0.0, 0.22, t))


# --- vegetation ----------------------------------------------------------------------------------------

func _register_blockers() -> void:
	for h in plan.houses + plan.stalls:
		sites.vegetation_blockers.append([h["center"], sqrt(float(h["w"]) ** 2 + float(h["d"]) ** 2) * 0.5 + 1.2])
	for info in plan.tower_info:
		sites.vegetation_blockers.append([info["pos"], float(info["diameter"]) * 0.5 + 2.5])
	if not plan.gate.is_empty():
		sites.vegetation_blockers.append([plan.gate_center, 24.0])
	for z in plan.fight_zones:
		if z.has("radius"):
			sites.vegetation_blockers.append([z["center"], float(z["radius"])])
		else:
			var h: Vector2 = z["half"]
			sites.vegetation_blockers.append([z["center"], h.length()])
	for sp in plan.spy_points:
		sites.vegetation_blockers.append([sp["pos"], 1.5])
