class_name VillageBuilder
extends RefCounted
## Ashford: a compact village on the East Meadow, east of Moonmere. Every house,
## shop and workshop is an exterior-only shell: closed doors, shuttered or opaque
## windows, no interiors, no interaction, and one solid collision box per
## building (taller than the roof ridge, so nothing can be climbed or entered).
## Coordinates are local to the site centre (x east, z south).

const MAT := preload("res://assets/materials/village_props.tres")
const GLOW_WARM := preload("res://assets/materials/glow_warm.tres")
## Surface tags for village_props.tres (castle_props shader slots, rebound).
const THATCH := 0.1
const PLANK := 0.2
const CLOTH := 0.3
const IRON := 0.4
const PLASTER := 0.5
const STONE := 0.6

var sites: Sites
var root: Node3D
var origin: Vector3
var td: TerrainData
var water_level := 0.0
var props := MeshKit.new(7101, 0.05)
var glow := MeshKit.new(7102)
var solid: StaticBody3D
var residential_footprints: Array[Dictionary] = []


func _init(p_sites: Sites, p_root: Node3D, p_origin: Vector3, p_td: TerrainData, p_water_level: float) -> void:
	sites = p_sites
	root = p_root
	origin = p_origin
	td = p_td
	water_level = p_water_level


static func c(r: float, g: float, b: float, surf := 1.0) -> Color:
	return Color(r, g, b, surf)


func build() -> void:
	solid = StaticBody3D.new()
	solid.name = "VillageProps"
	solid.collision_layer = Layers.WORLD
	solid.collision_mask = 0
	root.add_child(solid)

	var tavern := _building("Tavern", Vector2(-13, -13), PI, 11.0, 8.0, {"storeys": 2, "jetty": 0.55, "roof": "slate",
		"wall": c(0.55, 0.50, 0.41, PLASTER), "chimney": 1, "lit": true, "door_bay": 2})
	_tavern_yard(tavern)
	var bakery := _building("Bakery", Vector2(1.5, -14), PI, 6.5, 6.0, {"roof": "thatch", "wall": c(0.58, 0.52, 0.39, PLASTER),
		"chimney": -1, "lit": true, "h1": 3.1, "gable_front": true})
	_bakery_yard(bakery)
	var granary := _building("Granary", Vector2(14.5, -13.5), PI, 6.0, 7.0, {"roof": "thatch", "walls": "plank",
		"staddles": true, "thatch_tint": 0.82, "windows": false})
	_granary_yard(granary)
	var smithy := _building("Smithy", Vector2(-13, 13), 0.0, 7.0, 6.0, {"roof": "slate", "walls": "stone", "chimney": 1,
		"chimney_size": 1.3, "h1": 3.2})
	_smithy_yard(smithy)
	var shop := _building("GeneralGoods", Vector2(2, 13.5), 0.0, 7.0, 6.0, {"storeys": 2, "roof": "thatch",
		"wall": c(0.51, 0.47, 0.39, PLASTER), "chimney": -1})
	_shop_yard(shop)
	var joiner := _building("Joinery", Vector2(15.5, 12.5), 0.0, 7.0, 6.5, {"roof": "thatch", "walls": "plank",
		"thatch_tint": 1.08, "gable_front": true})
	_joinery_yard(joiner)
	var cot_a := _building("CottageA", Vector2(23, -5), PI * 0.5, 5.5, 5.0, {"roof": "thatch", "wall": c(0.56, 0.53, 0.47, PLASTER),
		"chimney": 1, "thatch_tint": 0.75, "h1": 2.6})
	_cottage_garden(cot_a, Vector2(5.6, 0.0), Vector2(3.4, 5.0))
	var cot_b := _building("CottageB", Vector2(23.5, 9.5), 0.0, 5.0, 5.5, {"roof": "slate", "wall": c(0.48, 0.45, 0.39, PLASTER),
		"chimney": -1, "h1": 2.7, "gable_front": true})
	_laundry(cot_b)
	var cot_c := _building("CottageC", Vector2(-25, -12), PI, 5.0, 5.0, {"roof": "thatch", "wall": c(0.59, 0.55, 0.45, PLASTER),
		"chimney": -1, "thatch_tint": 0.9, "h1": 2.6})
	_cottage_garden(cot_c, Vector2(0.0, 4.7), Vector2(4.4, 3.0))
	var cot_d := _building("CottageD", Vector2(-23, 14), 0.0, 5.5, 5.0, {"roof": "thatch", "walls": "stone", "chimney": 1,
		"thatch_tint": 0.7, "h1": 2.5})
	_firewood(cot_d["xf"], Vector3(-3.3, 0, 0.6), PI * 0.5, 1.8)

	_well(Vector2(9.0, -5.0))
	for p: Vector2 in [Vector2(-22, 7.5), Vector2(-6, -3.2), Vector2(10.5, 4.6), Vector2(19.0, -3.6)]:
		_lantern_post(p)
	_dry_stone_wall([Vector2(-30, -20), Vector2(-20, -22.5), Vector2(-8, -23)])
	_dry_stone_wall([Vector2(29.5, -16), Vector2(29, -8.5)])
	_dry_stone_wall([Vector2(29, 6), Vector2(29.5, 18), Vector2(25, 23)])
	_dry_stone_wall([Vector2(-31, 20), Vector2(-27, 25), Vector2(-16, 26)])
	_story_layout()

	_emit(props, MAT, true, "VillageDetail")
	_emit(glow, GLOW_WARM, false, "VillageGlow")


## Rural settlements reuse Ashford's exterior house builder, material set and
## collision rules. Their open central spaces connect to the existing routes.
func build_hamlet(settlement_name := "") -> void:
	solid = StaticBody3D.new()
	solid.name = "HamletProps"
	solid.collision_layer = Layers.WORLD
	solid.collision_mask = 0
	root.add_child(solid)
	match settlement_name:
		"Northmere": _build_northmere()
		"Southbank": _build_southbank()
		_: _build_woodland_hamlet(settlement_name)
	_emit(props, MAT, true, "HamletDetail")
	_emit(glow, GLOW_WARM, false, "HamletGlow")


func _build_woodland_hamlet(settlement_name: String) -> void:
	_building("HamletCottageNorthwest", Vector2(-9.0, -8.5), PI * 0.42, 5.8, 5.2, {
		"roof": "thatch", "wall": c(0.56, 0.51, 0.42, PLASTER), "chimney": -1, "h1": 2.7, "thatch_tint": 0.86, "respect_exclusions": true})
	_building("HamletCottageNortheast", Vector2(7.5, -10.5), PI * 1.57, 5.6, 5.0, {
		"roof": "slate", "walls": "stone", "chimney": 1, "h1": 2.7, "respect_exclusions": true})
	_building("HamletCottageSouthwest", Vector2(-10.5, 8.0), PI * 0.6, 5.2, 5.0, {
		"roof": "thatch", "walls": "plank", "chimney": -1, "h1": 2.6, "thatch_tint": 0.95, "respect_exclusions": true})
	_building("HamletWorkshopSoutheast", Vector2(9.0, 8.5), PI * 1.38, 6.5, 5.5, {
		"roof": "thatch", "wall": c(0.52, 0.48, 0.4, PLASTER), "chimney": 1, "h1": 2.8, "gable_front": true, "respect_exclusions": true})
	var west_house := Vector2(-16.0, -1.0)
	var east_house := Vector2(16.0, -0.5)
	var west_yaw := -PI * 0.5
	var east_yaw := PI * 0.5
	if settlement_name == "Westmarch Hamlet":
		# The old east-facing lot falls inside the Citadel's protected approach.
		# Place this outlying cottage on the northern edge of the clearing instead.
		east_house = Vector2(-4.0, -20.0)
	elif settlement_name == "Southwatch Hamlet":
		west_house = Vector2(-17.0, 3.0)
		east_house = Vector2(17.0, -2.0)
		west_yaw = -PI / 3.0
	_building("HamletCottageWest", west_house, west_yaw, 5.0, 5.2, {
		"roof": "slate", "wall": c(0.50, 0.47, 0.40, PLASTER), "chimney": -1, "h1": 2.6, "respect_exclusions": true})
	_building("HamletCottageEast", east_house, east_yaw, 5.4, 5.0, {
		"roof": "thatch", "walls": "plank", "chimney": 1, "h1": 2.6, "thatch_tint": 0.9, "respect_exclusions": true})
	_well(Vector2(-2.0, 10.0) if settlement_name == "Southwatch Hamlet" else Vector2(0.0, 12.0))
	_lantern_post(Vector2(-3.0, -13.0))
	_lantern_post(Vector2(3.0, -13.0))
	_lantern_post(Vector2(-3.0, 13.0))
	_lantern_post(Vector2(3.0, 13.0))
	_dry_stone_wall([Vector2(-20.0, -13.0), Vector2(-18.0, -8.0)])
	_dry_stone_wall([Vector2(20.0, 4.0), Vector2(18.0, 10.0)])


func _build_northmere() -> void:
	# A market-road hamlet arranged around an open hardstanding. Its houses
	# face the shared square; the king's road runs through the empty centre.
	_building("NorthmereTannerCottage", Vector2(-18.0, -6.0), -PI * 0.75, 5.8, 5.2, {
		"roof": "thatch", "wall": c(0.55, 0.50, 0.41, PLASTER), "chimney": -1, "h1": 2.7, "thatch_tint": 0.88, "respect_exclusions": true})
	_building("NorthmereNorthCottage", Vector2(-6.0, -19.0), PI, 5.2, 5.0, {
		"roof": "slate", "walls": "stone", "chimney": 1, "h1": 2.7, "respect_exclusions": true})
	_building("NorthmereGranary", Vector2(9.0, -17.0), PI * 0.65, 6.2, 6.0, {
		"roof": "thatch", "walls": "plank", "staddles": true, "windows": false, "thatch_tint": 0.84, "respect_exclusions": true})
	_building("NorthmereSmithy", Vector2(12.0, -1.0), PI * 0.5, 6.5, 5.8, {
		"roof": "slate", "walls": "stone", "chimney": 1, "chimney_size": 1.2, "h1": 3.0, "respect_exclusions": true})
	_building("NorthmereSouthCottage", Vector2(-1.0, 18.0), 0.0, 5.2, 5.0, {
		"roof": "thatch", "wall": c(0.58, 0.52, 0.42, PLASTER), "chimney": -1, "h1": 2.6, "thatch_tint": 0.92, "respect_exclusions": true})
	_building("NorthmereWestCottage", Vector2(-16.0, 13.0), -PI * 0.25, 5.4, 5.1, {
		"roof": "thatch", "walls": "plank", "chimney": 1, "h1": 2.7, "respect_exclusions": true})
	_well(Vector2(-4.0, 1.0))
	_lantern_post(Vector2(-3.5, -4.0))
	_lantern_post(Vector2(4.5, 2.0))
	_dry_stone_wall([Vector2(-24.0, -14.0), Vector2(-21.0, -10.0)])
	_dry_stone_wall([Vector2(18.0, 17.0), Vector2(22.0, 14.0)])


func _build_southbank() -> void:
	# A farm village on the dry eastern side of the river country, well outside
	# the castle approach and with its south lane joining the Reed Ford road.
	var farmhouse := _building("SouthbankFarmhouse", Vector2(-15.0, -12.0), -PI * 0.75, 6.0, 5.6, {
		"roof": "thatch", "wall": c(0.57, 0.51, 0.41, PLASTER), "chimney": -1, "h1": 2.8, "thatch_tint": 0.86, "respect_exclusions": true})
	if farmhouse.has("xf"):
		_cottage_garden(farmhouse, Vector2(0.0, 4.5), Vector2(3.8, 3.0))
	_building("SouthbankBarn", Vector2(-2.0, -20.0), PI, 7.0, 7.0, {
		"roof": "thatch", "walls": "plank", "staddles": true, "windows": false, "thatch_tint": 0.78, "respect_exclusions": true})
	_building("SouthbankEastCottage", Vector2(13.0, -14.0), PI * 0.65, 5.2, 5.0, {
		"roof": "slate", "walls": "stone", "chimney": 1, "h1": 2.7, "respect_exclusions": true})
	_building("SouthbankRoadsideCottage", Vector2(18.0, 0.0), PI * 0.5, 5.0, 5.2, {
		"roof": "thatch", "wall": c(0.52, 0.49, 0.41, PLASTER), "chimney": -1, "h1": 2.6, "respect_exclusions": true})
	_building("SouthbankOrchardHouse", Vector2(14.0, 15.0), PI * 0.25, 5.6, 5.0, {
		"roof": "thatch", "walls": "plank", "chimney": 1, "h1": 2.6, "thatch_tint": 0.94, "respect_exclusions": true})
	_building("SouthbankSouthCottage", Vector2(-7.0, 18.0), 0.0, 5.2, 5.0, {
		"roof": "slate", "wall": c(0.55, 0.51, 0.43, PLASTER), "chimney": -1, "h1": 2.7, "respect_exclusions": true})
	_building("SouthbankWestCottage", Vector2(-16.0, 12.0), -PI * 0.25, 5.4, 5.0, {
		"roof": "thatch", "wall": c(0.59, 0.54, 0.44, PLASTER), "chimney": 1, "h1": 2.6, "respect_exclusions": true})
	_building("SouthbankWestStorehouse", Vector2(-27.0, 14.0), -PI * 0.5, 5.8, 6.0, {
		"roof": "thatch", "walls": "plank", "staddles": true, "windows": false, "respect_exclusions": true})
	_well(Vector2(-5.0, -2.0))
	_lantern_post(Vector2(-4.0, -8.0))
	_lantern_post(Vector2(5.0, -7.0))
	_dry_stone_wall([Vector2(-25.0, 9.0), Vector2(-22.0, 15.0), Vector2(-17.0, 18.0)])
	_dry_stone_wall([Vector2(18.0, -22.0), Vector2(22.0, -18.0)])


# --- helpers -------------------------------------------------------------------------------

func _w(local: Vector3) -> Vector3:
	return origin + local


func _ground(x: float, z: float) -> float:
	return td.height_at(origin.x + x, origin.z + z) - origin.y


func box(k: MeshKit, xf: Transform3D, center: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	k.add_box(xf * Transform3D(basis, center), size, col)


## Square beam from a to b (building-local), `t` thick.
func beam(k: MeshKit, xf: Transform3D, a: Vector3, b: Vector3, t: float, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var x := d / l
	var ref := Vector3.UP if absf(x.y) < 0.9 else Vector3.FORWARD
	var z := x.cross(ref).normalized()
	var y := z.cross(x)
	k.add_box(xf * Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(l, t, t), col)


func _collide(xf: Transform3D, center: Vector3, size: Vector3, body: StaticBody3D = null) -> void:
	var shape := BoxShape3D.new()
	shape.size = size.abs()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var b := body if body else solid
	cs.transform = (b.global_transform.affine_inverse() if b.is_inside_tree() else Transform3D.IDENTITY) * xf * Transform3D(Basis.IDENTITY, center)
	b.add_child(cs)


func _emit(k: MeshKit, mat: Material, shadows: bool, node_name: String, parent: Node3D = null) -> void:
	if k.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = k.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 420.0
	(parent if parent else root).add_child(mi)


func _light(light_name: String, local: Vector3, energy: float, reach: float, flicker := true) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = _w(local)
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.4
	light.light_specular = 0.3
	light.distance_fade_enabled = true
	light.distance_fade_begin = 60.0
	light.distance_fade_length = 16.0
	light.add_to_group("day_night_lights")
	root.add_child(light)
	if flicker:
		sites._flicker.append({"light": light, "base": energy, "phase": float(sites._flicker.size()) * 1.3})
	return light


# --- buildings ------------------------------------------------------------------------------

## Builds one exterior-only building. Building-local frame: x across the
## front (width w), z through the depth d, front face at z = -d/2 facing -z.
func _building(bname: String, at: Vector2, yaw: float, w: float, d: float, o: Dictionary) -> Dictionary:
	var build_at := at
	if o.get("respect_exclusions", false):
		var rejection := _residential_candidate_rejection(build_at, yaw, w, d)
		if not rejection.is_empty():
			if root.name in ["WestmarchHamlet", "SouthwatchHamlet", "Northmere", "Southbank"]:
				build_at = _find_residential_fallback(at, yaw, w, d, bname)
				rejection = _residential_candidate_rejection(build_at, yaw, w, d) if build_at != at else rejection
			if not rejection.is_empty():
				print("[VillageBuilder] skipped %s/%s at %s: %s" % [root.name, bname, str(build_at), rejection])
				return {}
		if root.name in ["WestmarchHamlet", "SouthwatchHamlet", "Northmere", "Southbank"]:
			residential_footprints.append({"center": build_at, "radius": sqrt(w * w + d * d) * 0.5})
	var basis := Basis(Vector3.UP, yaw)
	var lo := INF
	for cx: float in [-0.5, 0.5]:
		for cz: float in [-0.5, 0.5]:
			var corner: Vector3 = basis * Vector3(cx * w, 0, cz * d)
			lo = minf(lo, _ground(build_at.x + corner.x, build_at.y + corner.z))
	var xf := Transform3D(basis, _w(Vector3(build_at.x, lo, build_at.y)))
	var k := MeshKit.new(hash(bname) & 0xffff, 0.035)
	var g := house_geometry(k, xf, w, d, o)
	for box_def: Array in g["chimney_boxes"]:
		_collide(xf, box_def[0], box_def[1])
	# One solid box per building, taller than the ridge: no entry, no roof access.
	var body := StaticBody3D.new()
	body.name = bname
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	root.add_child(body)
	var solid_box: Array = g["solid_box"]
	_collide(xf, solid_box[0], solid_box[1], body)
	_emit(k, MAT, true, bname + "Mesh", body)
	return {"xf": xf, "w": w, "d": d, "base": g["base"], "top1": g["top1"], "ridge": g["ridge"], "door_x": g["door_x"]}


## The exterior shell of one building, drawn into `k` (lit window panes go to
## `glow`). Collision is returned rather than created, so the same geometry can
## be built once at the origin and reused as a shared mesh: "solid_box" is the
## [centre, size] of the no-entry box (taller than the ridge), "chimney_boxes"
## any chimney stacks.
func house_geometry(k: MeshKit, xf: Transform3D, w: float, d: float, o: Dictionary) -> Dictionary:
	var chimney_boxes: Array = []
	var storeys: int = o.get("storeys", 1)
	var h1: float = o.get("h1", 2.9)
	var h2: float = o.get("h2", 2.5)
	var walls: String = o.get("walls", "plaster")
	var staddles: bool = o.get("staddles", false)
	var base := 0.95 if staddles else 0.45
	var jetty: float = o.get("jetty", 0.0) if storeys == 2 else 0.0
	var frame := c(0.19, 0.13, 0.09, PLANK)
	var plaster: Color = o.get("wall", c(0.55, 0.50, 0.42, PLASTER))
	var stone := c(0.4, 0.39, 0.36, STONE)
	var wall1 := plaster
	if walls == "stone":
		wall1 = stone
	elif walls == "plank":
		wall1 = c(0.32, 0.23, 0.15, PLANK)

	if staddles:
		for sx: float in [-0.42, 0.0, 0.42]:
			for sz: float in [-0.4, 0.4]:
				var p := Vector3(sx * w, 0, sz * d)
				k.add_cylinder(xf * Transform3D(Basis.IDENTITY, p + Vector3(0, -0.4, 0)), 0.2, 0.13, 1.05, 7, stone)
				k.add_cylinder(xf * Transform3D(Basis.IDENTITY, p + Vector3(0, 0.62, 0)), 0.38, 0.32, 0.16, 8, stone)
		box(k, xf, Vector3(0, base - 0.12, 0), Vector3(w + 0.1, 0.24, d + 0.1), frame)
	else:
		box(k, xf, Vector3(0, (base - 0.9) * 0.5 + 0.0, 0), Vector3(w + 0.26, base + 0.9, d + 0.26), stone)
	var top1 := base + h1
	box(k, xf, Vector3(0, base + h1 * 0.5, 0), Vector3(w, h1, d), wall1)
	if walls == "plaster":
		_frame_storey(k, xf, base, top1, w, d, 0.0, frame)
	elif walls == "stone":
		_quoins(k, xf, base, top1, w, d, stone)
	else:
		_plank_battens(k, xf, base, top1, w, d, frame)
	var wall_top := top1
	var depth_top := d
	var zshift := 0.0
	if storeys == 2:
		box(k, xf, Vector3(0, top1 + 0.12, -jetty * 0.5), Vector3(w + 0.12, 0.24, d + jetty + 0.12), frame)
		if jetty > 0.0:
			var n := int(w / 0.6)
			for i in n + 1:
				var x := -w * 0.5 + w * float(i) / n
				box(k, xf, Vector3(x, top1 + 0.02, -d * 0.5 - jetty + 0.08), Vector3(0.14, 0.16, jetty + 0.1), frame)
		var y2 := top1 + 0.24
		box(k, xf, Vector3(0, y2 + h2 * 0.5, -jetty * 0.5), Vector3(w, h2, d + jetty), plaster)
		_frame_storey(k, xf, y2, y2 + h2, w, d + jetty, -jetty * 0.5, frame)
		wall_top = y2 + h2
		depth_top = d + jetty
		zshift = -jetty * 0.5
	var ridge := _roof(k, xf, w, depth_top, zshift, wall_top, o, plaster if walls != "plank" else wall1, frame)
	# Door: closed, set in the front face of the ground storey.
	var bays := maxi(2, int(round(w / 1.45)))
	var door_bay: int = o.get("door_bay", bays / 2)
	var bay_w := w / bays
	var door_x := -w * 0.5 + bay_w * (float(door_bay) + 0.5)
	_door(k, xf, Vector3(door_x, base, -d * 0.5), minf(1.1, bay_w - 0.2), 2.05, base)
	# Windows between the posts: closed shutters, or opaque glazing (lit or dark).
	if o.get("windows", true):
		var lit: bool = o.get("lit", false)
		for i in bays:
			if i == door_bay:
				continue
			var x := -w * 0.5 + bay_w * (float(i) + 0.5)
			_window(k, xf, Vector3(x, base + 0.95, -d * 0.5), Vector3(0, 0, -1), lit and i % 2 == 0, (i + bays) % 3 == 0)
		if storeys == 2:
			for i in bays:
				var x := -w * 0.5 + bay_w * (float(i) + 0.5)
				_window(k, xf, Vector3(x, top1 + 0.24 + 0.75, -d * 0.5 - jetty), Vector3(0, 0, -1), lit and i % 2 == 1, i % 2 == 0)
		for sd: float in [-1.0, 1.0]:
			_window(k, xf, Vector3(sd * w * 0.5, base + 0.95, 0.0), Vector3(sd, 0, 0), false, true)
		_window(k, xf, Vector3(w * 0.2, base + 0.95, d * 0.5), Vector3(0, 0, 1), false, true)
	# Chimney stack against a gable wall.
	var chim: int = o.get("chimney", 0)
	var csize: float = o.get("chimney_size", 0.9)
	if chim != 0:
		var cx := float(chim) * (w * 0.5 + csize * 0.5 - 0.05)
		var ctop := ridge + 0.9
		box(k, xf, Vector3(cx, (ctop - 0.6) * 0.5, 0.0), Vector3(csize, ctop + 0.6, csize), stone)
		box(k, xf, Vector3(cx, ctop - 0.1, 0.0), Vector3(csize + 0.18, 0.18, csize + 0.18), c(0.33, 0.32, 0.3, STONE))
		box(k, xf, Vector3(cx, ctop + 0.01, 0.0), Vector3(csize - 0.3, 0.02, csize - 0.3), c(0.03, 0.03, 0.03))
		chimney_boxes.append([Vector3(cx, (ctop - 0.6) * 0.5, 0.0), Vector3(csize, ctop + 0.6, csize)])
	var hbox := ridge + 1.6
	return {"base": base, "top1": top1, "ridge": ridge, "door_x": door_x, "chimney_boxes": chimney_boxes,
		"solid_box": [Vector3(0, hbox * 0.5 - 0.8, zshift), Vector3(w + 0.3, hbox, depth_top + 0.3)]}


func _find_residential_fallback(at: Vector2, yaw: float, w: float, d: float, bname: String) -> Vector2:
	# Search a compact, deterministic spiral around an obstructed house position.
	# This keeps the intended cluster while retaining the same road, slope,
	# water, landmark, and house-to-house spacing rules.
	var phase := float(absi(hash(bname)) % 24) * TAU / 24.0
	for radius_index in 10:
		var radius := 2.0 + float(radius_index) * 2.0
		for step in 24:
			var candidate: Vector2 = at + Vector2.RIGHT.rotated(phase + TAU * float(step) / 24.0) * radius
			if _residential_candidate_rejection(candidate, yaw, w, d).is_empty():
				return candidate
	return at


## Reject a new home if its footprint overlaps a protected landmark, a route,
## a water margin, or ground too steep for this exterior-only house builder.
func _residential_candidate_rejection(at: Vector2, yaw: float, w: float, d: float) -> String:
	if not sites.world or not sites.world.layout:
		return ""
	var center := Vector2(origin.x + at.x, origin.z + at.y)
	var footprint_radius := sqrt(w * w + d * d) * 0.5 + 1.0
	var layout := sites.world.layout
	for river in layout.list("rivers"):
		var river_points := WorldLayout.points(river["points"])
		var river_margin := float(river["half_width"]) + float(river["bank"]) + footprint_radius + 4.0
		for i in river_points.size() - 1:
			if TerrainData.seg_dist(center, river_points[i], river_points[i + 1]) < river_margin:
				return "river/bank buffer: " + String(river["name"])
	for exclusion in layout.list("residential_exclusions"):
		var protected_center := WorldLayout.v2(exclusion["center"])
		if center.distance_to(protected_center) < float(exclusion["radius"]) + footprint_radius:
			return "protected exclusion: " + String(exclusion["name"])
	for poi in layout.list("points_of_interest"):
		if center.distance_to(WorldLayout.v2(poi["pos"])) < 3.0 + footprint_radius:
			return "quest landmark: " + String(poi["name"])
	for marker in layout.list("scroll_spawns"):
		if center.distance_to(WorldLayout.v2(marker["pos"])) < 4.5 + footprint_radius:
			return "scroll spawn: " + String(marker["name"])
	for spawn in layout.list("player_spawns"):
		if center.distance_to(WorldLayout.v2(spawn)) < 6.0 + footprint_radius:
			return "player spawn"
	var rotation := Basis(Vector3.UP, yaw)
	var samples: Array[Vector2] = [at]
	for sx: float in [-0.5, 0.5]:
		var edge: Vector3 = rotation * Vector3(sx * w, 0.0, 0.0)
		samples.append(at + Vector2(edge.x, edge.z))
	for sz: float in [-0.5, 0.5]:
		var edge: Vector3 = rotation * Vector3(0.0, 0.0, sz * d)
		samples.append(at + Vector2(edge.x, edge.z))
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var corner: Vector3 = rotation * Vector3(sx * w, 0.0, sz * d)
			samples.append(at + Vector2(corner.x, corner.z))
	var low := INF
	var high := -INF
	for local in samples:
		var x := origin.x + local.x
		var z := origin.z + local.y
		if td.is_hole_at(x, z):
			return "terrain hole"
		var ground := td.height_at(x, z)
		if ground < water_level + 0.8 or td.sample(td.water_influence, x, z) > 0.35:
			return "wet or low terrain"
		if td.normal_at(x, z).y < 0.86:
			return "terrain grade exceeds house limit"
		if td.sample(td.trail_dist, x, z) < 1.0:
			return "road or trail footprint"
		low = minf(low, ground)
		high = maxf(high, ground)
	if high - low > 2.2:
		return "terrain height varies %.1f m across footprint" % (high - low)
	for placed in residential_footprints:
		var clearance := float(placed["radius"]) + footprint_radius + 1.5
		if at.distance_to(placed["center"]) < clearance:
			return "overlaps another house's walking space"
	return ""


func _frame_storey(k: MeshKit, xf: Transform3D, y0: float, y1: float, w: float, d: float, zs: float, col: Color) -> void:
	var faces := [
		[Vector3(-w * 0.5, 0, zs - d * 0.5), Vector3(1, 0, 0), w, Vector3(0, 0, -1)],
		[Vector3(w * 0.5, 0, zs + d * 0.5), Vector3(-1, 0, 0), w, Vector3(0, 0, 1)],
		[Vector3(-w * 0.5, 0, zs + d * 0.5), Vector3(0, 0, -1), d, Vector3(-1, 0, 0)],
		[Vector3(w * 0.5, 0, zs - d * 0.5), Vector3(0, 0, 1), d, Vector3(1, 0, 0)],
	]
	for f in faces:
		var start: Vector3 = f[0]
		var along: Vector3 = f[1]
		var length: float = f[2]
		var nrm: Vector3 = f[3]
		var out := nrm * 0.04
		var bays := maxi(2, int(round(length / 1.45)))
		var mid := y0 + (y1 - y0) * 0.42
		for i in bays + 1:
			var p := start + along * length * float(i) / bays + out
			beam(k, xf, p + Vector3(0, y0, 0), p + Vector3(0, y1, 0), 0.16, col)
		for y: float in [y0 + 0.08, mid, y1 - 0.08]:
			beam(k, xf, start + out + Vector3(0, y, 0), start + along * length + out + Vector3(0, y, 0), 0.15, col)
		var bw := length / bays
		beam(k, xf, start + out + Vector3(0, y0 + 0.1, 0), start + along * bw + out + Vector3(0, mid, 0), 0.12, col)
		var end := start + along * length
		beam(k, xf, end + out + Vector3(0, y0 + 0.1, 0), end - along * bw + out + Vector3(0, mid, 0), 0.12, col)


func _quoins(k: MeshKit, xf: Transform3D, y0: float, y1: float, w: float, d: float, col: Color) -> void:
	var dark := c(col.r * 0.86, col.g * 0.86, col.b * 0.86, col.a)
	var n := int((y1 - y0) / 0.42)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			for i in n:
				var long := i % 2 == 0
				var sx := 0.62 if long else 0.34
				var sz := 0.34 if long else 0.62
				box(k, xf, Vector3(cx * (w * 0.5 - sx * 0.5 + 0.04), y0 + 0.21 + float(i) * 0.42, cz * (d * 0.5 - sz * 0.5 + 0.04)), Vector3(sx, 0.38, sz), dark)


func _plank_battens(k: MeshKit, xf: Transform3D, y0: float, y1: float, w: float, d: float, col: Color) -> void:
	for x in range(1, int(w / 0.9)):
		for sz: float in [-1.0, 1.0]:
			var px := -w * 0.5 + float(x) * 0.9
			box(k, xf, Vector3(px, (y0 + y1) * 0.5, sz * (d * 0.5 + 0.03)), Vector3(0.08, y1 - y0, 0.05), col)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			box(k, xf, Vector3(cx * w * 0.5, (y0 + y1) * 0.5, cz * d * 0.5), Vector3(0.2, y1 - y0, 0.2), col)
	for y: float in [y0 + 0.1, y1 - 0.1]:
		box(k, xf, Vector3(0, y, -d * 0.5 - 0.04), Vector3(w, 0.16, 0.08), col)


## Gable roof. The ridge runs along x, or along z with "gable_front" (so the
## gable faces the lane). Returns the ridge height.
func _roof(k: MeshKit, xf: Transform3D, w: float, d: float, zs: float, top: float, o: Dictionary, gable_col: Color, frame: Color) -> float:
	var thatch: bool = o.get("roof", "thatch") == "thatch"
	var gf: bool = o.get("gable_front", false)
	var rx := xf * Transform3D(Basis(Vector3.UP, PI * 0.5) if gf else Basis.IDENTITY, Vector3(0, 0, zs))
	var span_w := d if gf else w
	var span_d := w if gf else d
	var pitch := deg_to_rad(52.0 if thatch else 41.0)
	var t := 0.42 if thatch else 0.14
	var ov := 0.62 if thatch else 0.38
	var gov := 0.32 if thatch else 0.3
	var tint: float = o.get("thatch_tint", 1.0)
	var col := c(0.38 * tint, 0.32 * tint, 0.21 * tint, THATCH) if thatch else c(0.17, 0.18, 0.2, STONE)
	var rise := span_d * 0.5 * tan(pitch)
	var hs := span_d * 0.5 + ov
	for s: float in [-1.0, 1.0]:
		var center := Vector3(0, top + rise - hs * tan(pitch) * 0.5 + t * 0.5 / cos(pitch), s * hs * 0.5)
		k.add_box(rx * Transform3D(Basis(Vector3.RIGHT, s * pitch), center), Vector3(span_w + gov * 2.0, t, hs / cos(pitch)), col)
	for sx: float in [-1.0, 1.0]:
		var x := sx * span_w * 0.5
		var a := rx * Vector3(x, top, -span_d * 0.5)
		var b := rx * Vector3(x, top, span_d * 0.5)
		var apex := rx * Vector3(x, top + rise, 0)
		k.add_tri(a, b, apex, gable_col)
		k.add_tri(a, apex, b, gable_col)
		beam(k, rx, Vector3(x + sx * 0.04, top, 0), Vector3(x + sx * 0.04, top + rise - 0.1, 0), 0.14, frame)
		beam(k, rx, Vector3(x + sx * 0.04, top + 0.05, -span_d * 0.5), Vector3(x + sx * 0.04, top + 0.05, span_d * 0.5), 0.14, frame)
	if thatch:
		k.add_cylinder(rx * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-span_w * 0.5 - gov, top + rise + t * 0.55, 0)), t * 0.75, t * 0.75, span_w + gov * 2.0, 7, c(col.r * 0.9, col.g * 0.9, col.b * 0.9, THATCH))
	else:
		box(k, rx, Vector3(0, top + rise + 0.1, 0), Vector3(span_w + gov * 2.0, 0.16, 0.3), c(0.16, 0.16, 0.17, STONE))
	return top + rise + t


func _door(k: MeshKit, xf: Transform3D, at: Vector3, width: float, height: float, base: float) -> void:
	var frame := c(0.17, 0.12, 0.08, PLANK)
	var leaf := c(0.3, 0.21, 0.13, PLANK)
	var iron := c(0.12, 0.12, 0.12, IRON)
	var o := Vector3(0, 0, -0.06)
	beam(k, xf, at + o + Vector3(-width * 0.5 - 0.08, 0, 0), at + o + Vector3(-width * 0.5 - 0.08, height + 0.1, 0), 0.16, frame)
	beam(k, xf, at + o + Vector3(width * 0.5 + 0.08, 0, 0), at + o + Vector3(width * 0.5 + 0.08, height + 0.1, 0), 0.16, frame)
	beam(k, xf, at + o + Vector3(-width * 0.5 - 0.2, height + 0.12, 0), at + o + Vector3(width * 0.5 + 0.2, height + 0.12, 0), 0.2, frame)
	box(k, xf, at + Vector3(0, height * 0.5, -0.05), Vector3(width, height, 0.08), leaf)
	for y: float in [0.35, height * 0.5, height - 0.35]:
		box(k, xf, at + Vector3(0, y, -0.1), Vector3(width - 0.08, 0.07, 0.02), iron)
	k.add_cylinder(xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), at + Vector3(width * 0.3, height * 0.48, -0.1)), 0.06, 0.06, 0.02, 8, iron, 0.0, 0.0, false)
	if base > 0.2 and base < 0.9:
		box(k, xf, at + Vector3(0, (base - 0.6) * 0.5 - base, -0.4), Vector3(width + 0.5, base + 0.6, 0.7), c(0.36, 0.35, 0.33, STONE))


## Closed window: shutters, or opaque glazing (dark, or lit by firelight inside).
func _window(k: MeshKit, xf: Transform3D, at: Vector3, nrm: Vector3, lit: bool, shuttered: bool) -> void:
	var b := Basis(Vector3.UP, atan2(nrm.x, nrm.z))
	var frame := c(0.16, 0.11, 0.08, PLANK)
	var wv := 0.72
	var hv := 0.86
	var p := at + nrm * 0.05
	box(k, xf, p + Vector3(0, -0.06, 0) + nrm * 0.03, Vector3(wv + 0.3, 0.1, 0.16), frame, b)
	box(k, xf, p + Vector3(0, hv + 0.06, 0), Vector3(wv + 0.24, 0.1, 0.1), frame, b)
	for sx: float in [-1.0, 1.0]:
		box(k, xf, p + b * Vector3(sx * (wv * 0.5 + 0.06), hv * 0.5, 0), Vector3(0.1, hv + 0.1, 0.1), frame, b)
	if shuttered and not lit:
		for sx: float in [-1.0, 1.0]:
			box(k, xf, p + b * Vector3(sx * wv * 0.25, hv * 0.5, 0.02), Vector3(wv * 0.5 - 0.02, hv, 0.05), c(0.27, 0.19, 0.12, PLANK), b)
			box(k, xf, p + b * Vector3(sx * wv * 0.25, hv * 0.5, 0.05), Vector3(wv * 0.5 - 0.06, 0.06, 0.02), frame, b)
	else:
		var pane := glow if lit else k
		var pane_col := Color(0.62, 0.36, 0.16) if lit else c(0.05, 0.06, 0.07)
		var pk := xf * Transform3D(b, p + b * Vector3(0, hv * 0.5, -0.01))
		pane.add_box(pk, Vector3(wv, hv, 0.03), pane_col)
		box(k, xf, p + b * Vector3(0, hv * 0.5, 0.02), Vector3(0.05, hv, 0.03), frame, b)
		box(k, xf, p + b * Vector3(0, hv * 0.5, 0.02), Vector3(wv, 0.05, 0.03), frame, b)


func _sign(xf: Transform3D, at: Vector3, text: String) -> void:
	var frame := c(0.16, 0.11, 0.08, PLANK)
	beam(props, xf, at, at + Vector3(0, 0, -1.0), 0.07, c(0.12, 0.12, 0.12, IRON))
	beam(props, xf, at + Vector3(0, -0.25, 0), at + Vector3(0, 0, -0.6), 0.04, c(0.12, 0.12, 0.12, IRON))
	box(props, xf, at + Vector3(0, -0.42, -0.6), Vector3(0.06, 0.62, 0.9), c(0.36, 0.26, 0.16, PLANK))
	box(props, xf, at + Vector3(0, -0.42, -0.6), Vector3(0.08, 0.68, 0.96), frame)
	for sx: float in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = text
		label.font_size = 30
		label.pixel_size = 0.0055
		label.modulate = Color(0.86, 0.76, 0.52)
		label.outline_size = 4
		label.outline_modulate = Color(0.06, 0.04, 0.03)
		label.double_sided = false
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.width = 150.0
		root.add_child(label)
		label.global_transform = xf * Transform3D(Basis(Vector3.UP, sx * PI * 0.5), at + Vector3(sx * 0.05, -0.42, -0.6))


# --- yards and details ----------------------------------------------------------------------

func _tavern_yard(b: Dictionary) -> void:
	var xf: Transform3D = b["xf"]
	var front: float = -float(b["d"]) * 0.5
	_sign(xf, Vector3(float(b["door_x"]) + 1.1, 2.9, front - 0.1), "THE DROWNED LANTERN")
	for x: float in [-3.6, 2.2]:
		_bench(xf, Vector3(x, 0, front - 2.0), 0.0, 2.2)
		_bench(xf, Vector3(x, 0, front - 3.6), 0.0, 2.2)
		_table(xf, Vector3(x, 0, front - 2.8), 2.0, 0.8)
	for p: Vector3 in [Vector3(4.6, 0, front - 0.55), Vector3(5.2, 0, front - 0.6), Vector3(4.9, 0.98, front - 0.6)]:
		_barrel(xf, p)
	var lamp_at: Vector3 = xf * Vector3(float(b["door_x"]) - 1.0, 2.35, front - 0.32)
	_wall_lantern(xf, Vector3(float(b["door_x"]) - 1.0, 2.35, front - 0.1))
	_light("TavernLantern", lamp_at - origin, 1.3, 9.0)


func _bakery_yard(b: Dictionary) -> void:
	var xf: Transform3D = b["xf"]
	var w: float = b["w"]
	var front: float = -float(b["d"]) * 0.5
	# Domed bread oven against the east wall (building-local -x faces east here).
	var stone := c(0.42, 0.38, 0.33, STONE)
	box(props, xf, Vector3(-w * 0.5 - 1.0, 0.45, 0.4), Vector3(1.9, 0.9, 2.0), stone)
	props.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.95, 0.75, 1.0)), Vector3(-w * 0.5 - 1.0, 0.9, 0.4)), 1.0, stone, true, 0.05)
	box(props, xf, Vector3(-w * 0.5 - 1.0, 1.0, -0.62), Vector3(0.55, 0.5, 0.06), c(0.05, 0.04, 0.03))
	_collide(xf, Vector3(-w * 0.5 - 1.0, 0.85, 0.4), Vector3(1.9, 1.7, 2.0))
	_sign(xf, Vector3(float(b["door_x"]) + 1.0, 2.7, front - 0.1), "BAKER")
	_table(xf, Vector3(-1.6, 0, front - 1.0), 1.6, 0.7)
	for i in 3:
		var p := Vector3(-2.15 + float(i) * 0.55, 0.85, front - 1.0)
		props.add_cylinder(xf * Transform3D(Basis.IDENTITY, p), 0.2, 0.24, 0.16, 9, c(0.45, 0.34, 0.2, PLANK))
		for j in 3:
			props.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.1, 0.07, 0.15)), p + Vector3(-0.08 + float(j) * 0.08, 0.2, 0.0)), 1.0, Color(0.62, 0.42, 0.2), false, 0.0)
	for p: Vector3 in [Vector3(1.9, 0, front - 0.5), Vector3(2.4, 0, front - 0.6), Vector3(2.15, 0.45, front - 0.55)]:
		props.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.3, 0.38, 0.26)), p + Vector3(0, 0.34, 0)), 1.0, c(0.66, 0.6, 0.48, CLOTH), true, 0.1)
	_firewood(xf, Vector3(-w * 0.5 - 0.6, 0, 2.2), 0.0, 1.6)


func _granary_yard(b: Dictionary) -> void:
	var xf: Transform3D = b["xf"]
	var front: float = -float(b["d"]) * 0.5
	var dx: float = b["door_x"]
	for i in 4:
		box(props, xf, Vector3(dx, 0.12 + float(i) * 0.24, front - 1.05 + float(i) * 0.25), Vector3(1.2, 0.08, 0.3), c(0.3, 0.21, 0.13, PLANK))
	for sx: float in [-1.0, 1.0]:
		beam(props, xf, Vector3(dx + sx * 0.62, 0, front - 1.2), Vector3(dx + sx * 0.62, 0.95, front - 0.05), 0.1, c(0.22, 0.15, 0.1, PLANK))
	for p: Vector3 in [Vector3(2.6, 0, front - 1.3), Vector3(2.6, 0, front - 2.4), Vector3(2.6, 0.55, front - 1.85)]:
		box(props, xf, p + Vector3(0, 0.28, 0), Vector3(1.0, 0.55, 1.0), c(0.6, 0.52, 0.32, THATCH))
	_collide(xf, Vector3(2.6, 0.55, front - 1.85), Vector3(1.1, 1.1, 2.2))
	_cart(xf, Vector3(-3.6, 0, front - 2.6), 0.3)


func _smithy_yard(b: Dictionary) -> void:
	var xf: Transform3D = b["xf"]
	var w: float = b["w"]
	var front: float = -float(b["d"]) * 0.5
	var post := c(0.2, 0.14, 0.09, PLANK)
	var lx := w * 0.5
	# Open lean-to over the forge on the east side.
	for z: float in [front + 0.3, -front - 0.3]:
		beam(props, xf, Vector3(lx + 3.0, 0, z), Vector3(lx + 3.0, 2.5, z), 0.18, post)
		_collide(xf, Vector3(lx + 3.0, 1.25, z), Vector3(0.2, 2.5, 0.2))
	beam(props, xf, Vector3(lx + 3.0, 2.5, front + 0.1), Vector3(lx + 3.0, 2.5, -front - 0.1), 0.18, post)
	var slope := atan2(0.7, 3.2)
	box(props, xf, Vector3(lx + 1.6, 2.92, 0), Vector3(3.6, 0.12, -front * 2.0 + 0.6), c(0.18, 0.19, 0.2, STONE), Basis(Vector3.BACK, slope))
	# Forge hearth with coals, bellows, anvil, quench tub, tools and coal.
	var stone := c(0.36, 0.34, 0.31, STONE)
	box(props, xf, Vector3(lx + 0.9, 0.5, -0.4), Vector3(1.6, 1.0, 1.5), stone)
	_collide(xf, Vector3(lx + 0.9, 0.5, -0.4), Vector3(1.6, 1.0, 1.5))
	glow.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, 0.1, 0.45)), Vector3(lx + 0.9, 1.02, -0.4)), 1.0, Color(1.0, 0.35, 0.1), false, 0.0)
	box(props, xf, Vector3(lx + 0.9, 1.9, -0.4), Vector3(1.2, 0.9, 1.1), stone)
	box(props, xf, Vector3(lx + 1.75, 0.7, -0.4), Vector3(0.5, 0.25, 0.8), c(0.28, 0.18, 0.11, CLOTH), Basis(Vector3.BACK, 0.25))
	var anvil_at := Vector3(lx + 1.8, 0, 1.0)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, anvil_at), 0.3, 0.27, 0.55, 8, c(0.3, 0.22, 0.14, PLANK))
	var iron := c(0.15, 0.15, 0.16, IRON)
	box(props, xf, anvil_at + Vector3(0, 0.66, 0), Vector3(0.28, 0.22, 0.2), iron)
	box(props, xf, anvil_at + Vector3(0, 0.82, 0), Vector3(0.56, 0.12, 0.24), iron)
	props.add_cylinder(xf * Transform3D(Basis(Vector3.FORWARD, PI * 0.5), anvil_at + Vector3(0.28, 0.82, 0)), 0.08, 0.0, 0.25, 6, iron)
	_collide(xf, anvil_at + Vector3(0, 0.45, 0), Vector3(0.6, 0.9, 0.6))
	_barrel(xf, Vector3(lx + 2.4, 0, -1.6))
	box(props, xf, Vector3(lx + 2.4, 0.98, -1.6), Vector3(0.62, 0.02, 0.62), c(0.04, 0.05, 0.06))
	for i in 4:
		box(props, xf, Vector3(lx + 0.05, 1.5 + float(i % 2) * 0.1, 1.4 + float(i) * 0.3), Vector3(0.05, 0.6, 0.05), iron)
	props.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.7, 0.3, 0.6)), Vector3(lx + 2.6, 0.05, 1.9)), 1.0, c(0.05, 0.05, 0.05), true, 0.2)
	_firewood(xf, Vector3(-lx - 0.6, 0, 0.0), PI * 0.5, 2.2)
	_light("ForgeGlow", (xf * Vector3(lx + 1.1, 1.4, -0.2)) - origin, 1.6, 8.0)
	_sign(xf, Vector3(lx - 0.6, 2.8, front - 0.1), "SMITH")


func _shop_yard(b: Dictionary) -> void:
	var xf: Transform3D = b["xf"]
	var front: float = -float(b["d"]) * 0.5
	var post := c(0.2, 0.14, 0.09, PLANK)
	# Striped awning on posts over a goods stall.
	for x: float in [-3.2, -0.6]:
		beam(props, xf, Vector3(x, 0, front - 1.9), Vector3(x, 2.25, front - 1.9), 0.12, post)
		_collide(xf, Vector3(x, 1.1, front - 1.9), Vector3(0.15, 2.2, 0.15))
	var tilt := atan2(0.45, 1.9)
	for i in 6:
		var x := -3.35 + float(i) * 0.5 + 0.25
		var col := c(0.48, 0.12, 0.08, CLOTH) if i % 2 == 0 else c(0.62, 0.56, 0.42, CLOTH)
		box(props, xf, Vector3(x, 2.5, front - 0.95), Vector3(0.5, 0.03, 2.05), col, Basis(Vector3.RIGHT, -tilt))
	_table(xf, Vector3(-1.9, 0, front - 1.1), 2.4, 0.9)
	_collide(xf, Vector3(-1.9, 0.45, front - 1.1), Vector3(2.4, 0.9, 0.9))
	for i in 4:
		var p := Vector3(-2.9 + float(i) * 0.65, 0.93, front - 1.1)
		props.add_cylinder(xf * Transform3D(Basis.IDENTITY, p), 0.22, 0.26, 0.2, 9, c(0.42, 0.32, 0.2, PLANK))
		var fruit: Color = [Color(0.55, 0.12, 0.08), Color(0.32, 0.45, 0.16), Color(0.6, 0.44, 0.16), Color(0.45, 0.3, 0.42)][i]
		for j in 4:
			props.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.075), p + Vector3(-0.08 + float(j % 2) * 0.16, 0.24, -0.06 + float(j / 2) * 0.12)), 1.0, fruit, false, 0.0)
	for p: Vector3 in [Vector3(1.8, 0, front - 0.6), Vector3(2.6, 0, front - 0.7), Vector3(2.2, 0.62, front - 0.65)]:
		box(props, xf, p + Vector3(0, 0.3, 0), Vector3(0.62, 0.6, 0.62), c(0.36, 0.27, 0.17, PLANK))
	_collide(xf, Vector3(2.2, 0.6, front - 0.65), Vector3(1.5, 1.2, 0.75))
	_barrel(xf, Vector3(3.2, 0, front - 1.4))
	_sign(xf, Vector3(1.0, 2.9, front - 0.1), "GOODS AND PROVISIONS")
	_cart(xf, Vector3(5.6, 0, front - 2.5), -0.5)


func _joinery_yard(b: Dictionary) -> void:
	var xf: Transform3D = b["xf"]
	var w: float = b["w"]
	var front: float = -float(b["d"]) * 0.5
	var wood := c(0.42, 0.31, 0.19, PLANK)
	for i in 5:
		for j in 2:
			box(props, xf, Vector3(w * 0.5 + 0.9 + float(j) * 0.35, 0.14 + float(i) * 0.12, 0.3), Vector3(0.3, 0.1, 4.6), wood)
	_collide(xf, Vector3(w * 0.5 + 1.08, 0.35, 0.3), Vector3(0.8, 0.7, 4.6))
	# Sawhorse with a log, workbench and shavings.
	var sh := Vector3(-1.8, 0, front - 2.0)
	for sx: float in [-0.6, 0.6]:
		for sz: float in [-1.0, 1.0]:
			beam(props, xf, sh + Vector3(sx, 0, sz * 0.25), sh + Vector3(sx, 0.75, 0), 0.07, wood)
	beam(props, xf, sh + Vector3(-0.8, 0.75, 0), sh + Vector3(0.8, 0.75, 0), 0.1, wood)
	props.add_cylinder(xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), sh + Vector3(1.3, 0.97, 0)), 0.2, 0.2, 2.6, 8, c(0.38, 0.27, 0.17, PLANK))
	_collide(xf, sh + Vector3(0, 0.45, 0), Vector3(1.8, 0.9, 0.6))
	_table(xf, Vector3(1.6, 0, front - 1.0), 2.0, 0.8)
	_collide(xf, Vector3(1.6, 0.45, front - 1.0), Vector3(2.0, 0.9, 0.8))
	for i in 6:
		box(props, xf, sh + Vector3(-0.8 + float(i) * 0.3, 0.015, 0.4 + float(i % 3) * 0.2), Vector3(0.25, 0.02, 0.18), c(0.68, 0.55, 0.36), Basis(Vector3.UP, float(i)))
	beam(props, xf, Vector3(-w * 0.5 + 0.6, 0, front - 0.6), Vector3(-w * 0.5 + 0.6, 3.0, front - 0.06), 0.07, wood)
	beam(props, xf, Vector3(-w * 0.5 + 1.1, 0, front - 0.6), Vector3(-w * 0.5 + 1.1, 3.0, front - 0.06), 0.07, wood)
	for i in 7:
		var y := 0.3 + float(i) * 0.4
		var z := front - 0.6 + (y / 3.0) * 0.54
		beam(props, xf, Vector3(-w * 0.5 + 0.6, y, z), Vector3(-w * 0.5 + 1.1, y, z), 0.05, wood)
	_sign(xf, Vector3(w * 0.25, 2.7, front - 0.1), "JOINER")


func _cottage_garden(b: Dictionary, offset: Vector2, size: Vector2) -> void:
	var xf: Transform3D = b["xf"]
	var w: float = b["w"]
	var d: float = b["d"]
	var gc := Vector3(offset.x, 0, offset.y)
	var post := c(0.24, 0.17, 0.11, PLANK)
	var corners := [gc + Vector3(-size.x, 0, -size.y) * 0.5, gc + Vector3(size.x, 0, -size.y) * 0.5,
		gc + Vector3(size.x, 0, size.y) * 0.5, gc + Vector3(-size.x, 0, size.y) * 0.5]
	for i in 4:
		var a: Vector3 = corners[i]
		var e: Vector3 = corners[(i + 1) % 4]
		var n := maxi(1, int(a.distance_to(e) / 1.4))
		for j in n + 1:
			var p := a.lerp(e, float(j) / n)
			beam(props, xf, p + Vector3(0, -0.1, 0), p + Vector3(0, 1.0, 0), 0.08, post)
		if i == 3:
			continue
		for y: float in [0.4, 0.82]:
			beam(props, xf, a + Vector3(0, y, 0), e + Vector3(0, y, 0), 0.05, post)
		var mid := (a + e) * 0.5
		var along := e - a
		_collide(xf, mid + Vector3(0, 0.5, 0), Vector3(maxf(absf(along.x), 0.1), 1.0, maxf(absf(along.z), 0.1)))
	var soil := c(0.16, 0.11, 0.07)
	for r in 3:
		var z := gc.z - size.y * 0.3 + float(r) * size.y * 0.3
		box(props, xf, Vector3(gc.x, 0.03, z), Vector3(size.x * 0.8, 0.08, 0.5), soil)
		for i in int(size.x * 0.8 / 0.5):
			var x := gc.x - size.x * 0.4 + 0.25 + float(i) * 0.5
			props.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.17, 0.12, 0.17)), Vector3(x, 0.14, z)), 1.0,
				Color(0.2, 0.36, 0.14) if r != 1 else Color(0.32, 0.4, 0.18), false, 0.15)
	sites.flower_patches.append([Vector2((xf * gc).x, (xf * gc).z), maxf(size.x, size.y) * 0.75, "garden"])
	_barrel(xf, Vector3(w * 0.5 + 0.45, 0, -d * 0.5 + 0.6))
	_bench(xf, Vector3(-w * 0.5 + 0.9, 0, -d * 0.5 - 0.55), 0.0, 1.4)


func _laundry(b: Dictionary) -> void:
	var xf: Transform3D = b["xf"]
	var w: float = b["w"]
	var post := c(0.24, 0.17, 0.11, PLANK)
	var a := Vector3(w * 0.5 + 1.2, 0, -1.5)
	var e := Vector3(w * 0.5 + 1.2, 0, 2.7)
	for p: Vector3 in [a, e]:
		beam(props, xf, p, p + Vector3(0, 2.1, 0), 0.09, post)
		_collide(xf, p + Vector3(0, 1.0, 0), Vector3(0.12, 2.0, 0.12))
	beam(props, xf, a + Vector3(0, 2.0, 0), e + Vector3(0, 2.0, 0), 0.02, c(0.5, 0.45, 0.36))
	var cloths := [c(0.62, 0.58, 0.5, CLOTH), c(0.32, 0.38, 0.44, CLOTH), c(0.5, 0.2, 0.14, CLOTH), c(0.66, 0.64, 0.58, CLOTH)]
	for i in 4:
		var z := a.z + 0.6 + float(i) * 0.9
		box(props, xf, Vector3(a.x, 1.62 - float(i % 2) * 0.12, z), Vector3(0.02, 0.72 + float(i % 2) * 0.2, 0.64), cloths[i])
	_firewood(xf, Vector3(0.0, 0, float(b["d"]) * 0.5 + 0.6), 0.0, 2.0)


func _bench(xf: Transform3D, at: Vector3, yaw: float, length: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var col := c(0.36, 0.26, 0.16, PLANK)
	box(props, xf, at + b * Vector3(0, 0.45, 0), Vector3(length, 0.07, 0.36), col, b)
	for sx: float in [-0.4, 0.4]:
		box(props, xf, at + b * Vector3(sx * length, 0.22, 0), Vector3(0.08, 0.44, 0.32), col, b)
	_collide(xf, at + b * Vector3(0, 0.25, 0), b * Vector3(length, 0.5, 0.4))


func _table(xf: Transform3D, at: Vector3, length: float, depth: float) -> void:
	var col := c(0.34, 0.24, 0.15, PLANK)
	box(props, xf, at + Vector3(0, 0.8, 0), Vector3(length, 0.07, depth), col)
	for sx: float in [-0.42, 0.42]:
		box(props, xf, at + Vector3(sx * length, 0.4, 0), Vector3(0.08, 0.8, depth * 0.8), col)


func _barrel(xf: Transform3D, at: Vector3) -> void:
	var wood := c(0.36, 0.25, 0.15, PLANK)
	var iron := c(0.13, 0.13, 0.13, IRON)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, at), 0.32, 0.37, 0.48, 10, wood)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, at + Vector3(0, 0.48, 0)), 0.37, 0.32, 0.48, 10, wood)
	for y: float in [0.1, 0.48, 0.86]:
		props.add_cylinder(xf * Transform3D(Basis.IDENTITY, at + Vector3(0, y - 0.03, 0)), 0.36 if absf(y - 0.48) > 0.1 else 0.39, 0.36 if absf(y - 0.48) > 0.1 else 0.39, 0.06, 10, iron, 0.0, 0.0, false)
	if at.y < 0.1:
		_collide(xf, at + Vector3(0, 0.48, 0), Vector3(0.7, 0.96, 0.7))


func _firewood(xf: Transform3D, at: Vector3, yaw: float, length: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var log_col := c(0.32, 0.23, 0.15, PLANK)
	for row in 4:
		var n := 6 - row
		for i in n:
			var x := (float(i) - float(n - 1) * 0.5) * 0.2
			var p: Vector3 = at + b * Vector3(x, 0.09 + float(row) * 0.17, 0)
			props.add_cylinder(xf * Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), p + b * Vector3(0, 0, -length * 0.5)), 0.09, 0.09, length, 7, log_col, 0.0, 0.0, true, Color(0.62, 0.48, 0.32))
	_collide(xf, at + Vector3(0, 0.35, 0), b * Vector3(1.3, 0.7, length))


func _cart(xf: Transform3D, at: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood := c(0.34, 0.24, 0.15, PLANK)
	box(props, xf, at + b * Vector3(0, 0.75, 0), Vector3(1.3, 0.08, 2.1), wood, b)
	for sx: float in [-1.0, 1.0]:
		box(props, xf, at + b * Vector3(sx * 0.65, 0.98, 0), Vector3(0.06, 0.4, 2.1), wood, b)
		props.add_cylinder(xf * Transform3D(b * Basis(Vector3.BACK, PI * 0.5), at + b * Vector3(sx * 0.75 - sx * 0.05, 0.5, 0.2)), 0.5, 0.5, 0.08, 12, wood)
		beam(props, xf, at + b * Vector3(sx * 0.45, 0.72, -1.0), at + b * Vector3(sx * 0.3, 0.3, -2.6), 0.07, wood)
	box(props, xf, at + b * Vector3(0, 1.0, 0.4), Vector3(0.9, 0.4, 0.9), c(0.6, 0.52, 0.32, THATCH), b)
	_collide(xf, at + Vector3(0, 0.6, 0), b * Vector3(1.4, 1.2, 2.2))


func _wall_lantern(xf: Transform3D, at: Vector3) -> void:
	var iron := c(0.12, 0.12, 0.12, IRON)
	beam(props, xf, at, at + Vector3(0, 0, -0.35), 0.04, iron)
	var lp := at + Vector3(0, -0.22, -0.32)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, lp + Vector3(0, 0.16, 0)), 0.14, 0.03, 0.12, 6, iron)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, lp - Vector3(0, 0.18, 0)), 0.11, 0.11, 0.03, 6, iron)
	glow.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.08, 0.12, 0.08)), lp), 1.0, Color(1.0, 0.62, 0.3), false, 0.0)


func _lantern_post(at: Vector2) -> void:
	var y := _ground(at.x, at.y)
	var xf := Transform3D(Basis.IDENTITY, _w(Vector3(at.x, y, at.y)))
	var wood := c(0.22, 0.15, 0.1, PLANK)
	beam(props, xf, Vector3(0, -0.3, 0), Vector3(0, 2.7, 0), 0.14, wood)
	beam(props, xf, Vector3(0, 2.55, 0), Vector3(0.7, 2.55, 0), 0.08, wood)
	beam(props, xf, Vector3(0, 2.1, 0), Vector3(0.45, 2.55, 0), 0.06, wood)
	var iron := c(0.12, 0.12, 0.12, IRON)
	var lp := Vector3(0.62, 2.2, 0)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, lp + Vector3(0, 0.16, 0)), 0.16, 0.03, 0.14, 6, iron)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, lp - Vector3(0, 0.2, 0)), 0.12, 0.12, 0.03, 6, iron)
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		box(props, xf, lp + Vector3(cos(a) * 0.11, 0, sin(a) * 0.11), Vector3(0.02, 0.36, 0.02), iron)
	glow.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.09, 0.13, 0.09)), lp), 1.0, Color(1.0, 0.62, 0.3), false, 0.0)
	_collide(xf, Vector3(0, 1.3, 0), Vector3(0.2, 2.6, 0.2))
	_light("Lantern_%d_%d" % [int(at.x), int(at.y)], Vector3(at.x + 0.62, y + 2.15, at.y), 1.15, 10.0)


func _well(at: Vector2) -> void:
	var y := _ground(at.x, at.y)
	var xf := Transform3D(Basis.IDENTITY, _w(Vector3(at.x, y, at.y)))
	var stone := c(0.4, 0.38, 0.35, STONE)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.3, 0)), 1.0, 0.95, 1.15, 14, stone)
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.84, 0)), 1.02, 1.02, 0.08, 14, c(0.34, 0.33, 0.31, STONE))
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.86, 0)), 0.72, 0.72, 0.01, 14, c(0.02, 0.02, 0.02))
	var wood := c(0.24, 0.17, 0.11, PLANK)
	for sx: float in [-1.0, 1.0]:
		beam(props, xf, Vector3(sx * 0.95, 0.5, 0), Vector3(sx * 0.95, 2.4, 0), 0.13, wood)
	beam(props, xf, Vector3(-1.1, 2.0, 0), Vector3(1.1, 2.0, 0), 0.1, wood)
	for s: float in [-1.0, 1.0]:
		box(props, xf, Vector3(0, 2.62, s * 0.42), Vector3(2.4, 0.06, 1.0), c(0.52, 0.45, 0.31, THATCH), Basis(Vector3.RIGHT, s * 0.75))
	beam(props, xf, Vector3(0.2, 2.0, 0), Vector3(0.2, 1.25, 0), 0.015, c(0.5, 0.44, 0.34))
	props.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(0.2, 1.0, 0)), 0.14, 0.17, 0.26, 8, wood)
	var shape := CylinderShape3D.new()
	shape.radius = 1.05
	shape.height = 1.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = solid.global_transform.affine_inverse() * xf * Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
	solid.add_child(cs)


func _dry_stone_wall(points: Array) -> void:
	var stone := c(0.38, 0.37, 0.34, STONE)
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var e: Vector2 = points[i + 1]
		var n := maxi(1, int(a.distance_to(e) / 1.6))
		for j in n:
			var p := a.lerp(e, (float(j) + 0.5) / n)
			var y := _ground(p.x, p.y)
			var dir := (e - a).normalized()
			var yaw := atan2(-dir.y, dir.x)
			var xf := Transform3D(Basis(Vector3.UP, yaw), _w(Vector3(p.x, y, p.y)))
			var seg := a.distance_to(e) / n
			var h := 0.85 + 0.12 * sin(float(j) * 2.3 + float(i))
			box(props, xf, Vector3(0, h * 0.5 - 0.25, 0), Vector3(seg + 0.06, h + 0.5, 0.62), stone)
			box(props, xf, Vector3(0, h + 0.06, 0), Vector3(seg + 0.1, 0.14, 0.7), c(0.33, 0.33, 0.3, STONE))
			_collide(xf, Vector3(0, h * 0.5, 0), Vector3(seg, h + 0.1, 0.62))


# --- story staging --------------------------------------------------------------------------

## Maren waits by the well; a trail of clues leads west to the lake shore where
## Tam is picking flowers at the water's edge.
func _story_layout() -> void:
	sites.story_anchors["elder"] = {"pos": _w(Vector3(7.2, _ground(7.2, 2.0), 2.0)), "yaw": PI * 0.5}
	sites.story_anchors["child_home"] = {"pos": _w(Vector3(6.6, _ground(6.6, 3.6), 3.6)), "yaw": PI * 0.35}
	# Walk west from the shore trail until the ground meets the water line.
	var start := Vector2(origin.x - 32.0, origin.z + 15.0)
	var shore := start
	for i in 80:
		var p := start + Vector2(-0.5 * i, 0.12 * i)
		if td.height_at(p.x, p.y) < water_level + 0.35:
			break
		shore = p
	var toward_village := (Vector2(origin.x - 26.0, origin.z + 6.0) - shore).normalized()
	var child := shore + toward_village * 0.6
	var shoe := shore + toward_village * 3.8
	var posy := shore + toward_village * 8.5
	var basket := Vector2(origin.x - 26.5, origin.z + 7.5)
	sites.story_anchors["child"] = {"pos": Vector3(child.x, td.height_at(child.x, child.y), child.y), "yaw": atan2(toward_village.x, toward_village.y)}
	var clue_pts := [basket, posy, shoe]
	for i in 3:
		var p: Vector2 = clue_pts[i]
		var gy := td.height_at(p.x, p.y)
		sites.story_anchors["clue_%d" % (i + 1)] = Vector3(p.x, gy + 0.25, p.y)
		var xf := Transform3D(Basis(Vector3.UP, float(i) * 1.3), Vector3(p.x, gy, p.y))
		match i:
			0:
				props.add_cylinder(xf * Transform3D(Basis(Vector3.BACK, 1.3), Vector3(0, 0.16, 0)), 0.17, 0.2, 0.22, 9, c(0.45, 0.33, 0.18, PLANK))
				for j in 5:
					props.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.05, 0.03, 0.05)), Vector3(0.25 + float(j) * 0.09, 0.04, -0.05 + float(j % 2) * 0.1)), 1.0, Color(0.92, 0.9, 0.82), false, 0.0)
			1:
				for j in 7:
					props.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.05, 0.03, 0.05)), Vector3(float(j) * 0.16 - 0.5, 0.04, float(j % 3) * 0.08)), 1.0, Color(0.92, 0.9, 0.82), false, 0.0)
					beam(props, xf, Vector3(float(j) * 0.16 - 0.5, 0.02, float(j % 3) * 0.08), Vector3(float(j) * 0.16 - 0.38, 0.02, float(j % 3) * 0.08 + 0.05), 0.012, Color(0.2, 0.34, 0.14))
			2:
				box(props, xf, Vector3(0, 0.05, 0), Vector3(0.11, 0.1, 0.22), c(0.3, 0.19, 0.11, CLOTH), Basis(Vector3.RIGHT, 0.4))
	sites.flower_patches.append([child, 4.5, "white"])
