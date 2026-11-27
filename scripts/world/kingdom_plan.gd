class_name KingdomPlan
extends RefCounted
## Pure-data planner for the walled kingdom (layout "kingdom"). Works from the
## layout and TerrainData only, so the map tool and tests can inspect exactly
## what KingdomBuilder will build: wall pieces and towers, the sealed gate, the
## river water gate, every house and market stall, the cemetery graves and
## fence gates, and the reserved mission spaces.
##
## House rule set (each candidate must pass every check, or it is skipped and
## the street frontage moves on): inside the wall with clearance, outside all
## landmark zones and mission fighting spaces, clear of spy spawn points and
## routes, off every road and trail, dry and away from river banks, on gentle
## ground, not overlapping another building, and with an open, walkable door
## apron.

## Archetypes reuse the Ashford/hamlet house builder (VillageBuilder) options.
const ARCHETYPES := {
	"cottage_thatch": {"w": 5.6, "d": 5.0, "o": {"roof": "thatch", "wall": Color(0.56, 0.51, 0.42, 0.5), "chimney": -1, "h1": 2.7, "thatch_tint": 0.86}},
	"cottage_stone": {"w": 5.6, "d": 5.0, "o": {"roof": "slate", "walls": "stone", "chimney": 1, "h1": 2.7}},
	"cottage_plank": {"w": 5.2, "d": 5.0, "o": {"roof": "thatch", "walls": "plank", "chimney": 1, "h1": 2.6, "thatch_tint": 0.95}},
	"house_tall": {"w": 7.0, "d": 6.0, "o": {"storeys": 2, "roof": "thatch", "wall": Color(0.51, 0.47, 0.39, 0.5), "chimney": -1}},
	"townhouse": {"w": 6.4, "d": 7.0, "o": {"storeys": 2, "jetty": 0.5, "roof": "slate", "wall": Color(0.55, 0.5, 0.41, 0.5), "chimney": 1, "gable_front": true, "lit": true}},
	"townhouse_wide": {"w": 8.6, "d": 6.6, "o": {"storeys": 2, "jetty": 0.55, "roof": "slate", "wall": Color(0.58, 0.53, 0.43, 0.5), "chimney": -1, "lit": true}},
	"longhouse": {"w": 9.0, "d": 5.6, "o": {"roof": "thatch", "wall": Color(0.57, 0.52, 0.42, 0.5), "chimney": 1, "h1": 2.8, "thatch_tint": 0.8}},
	"workshop": {"w": 6.6, "d": 5.6, "o": {"roof": "thatch", "wall": Color(0.52, 0.48, 0.4, 0.5), "chimney": 1, "h1": 2.8, "gable_front": true}},
	"smithy": {"w": 6.6, "d": 5.8, "o": {"roof": "slate", "walls": "stone", "chimney": 1, "chimney_size": 1.2, "h1": 3.0}},
	"granary": {"w": 6.0, "d": 6.0, "o": {"roof": "thatch", "walls": "plank", "staddles": true, "windows": false, "thatch_tint": 0.84}},
}
const STYLES := {
	"dense": {"townhouse": 5, "townhouse_wide": 3, "house_tall": 4, "workshop": 2, "cottage_stone": 2, "smithy": 1},
	"town": {"house_tall": 3, "townhouse": 2, "cottage_stone": 2, "cottage_thatch": 2, "workshop": 2, "longhouse": 1},
	"rural": {"cottage_thatch": 4, "cottage_plank": 3, "longhouse": 2, "cottage_stone": 2, "workshop": 1, "granary": 1},
}
const STALL_W := 3.4
const STALL_D := 2.4
const HOUSE_CLEARANCE := 1.6    ## Metres kept between neighbouring buildings.
const DOOR_APRON := 2.6         ## Open ground required in front of each door.
const WALL_PIECE := 8.0         ## Curtain wall is built in pieces of about this length.

var layout: WorldLayout
var td: TerrainData
var k: Dictionary

var wall_points := PackedVector2Array()
var wall_height := 11.0
var wall_thickness := 4.2
var wall_ref_ground := 4.0
## Each piece: {a, b, bottom, top, segment, kind} (kind "wall" or "water_gate").
var wall_pieces: Array[Dictionary] = []
## Barrier extensions beyond the wall ends, up into the mountains: [a, b].
var barrier_extensions: Array = []
var towers: Array[Vector2] = []
var tower_info: Array[Dictionary] = []
var gate := {}
var gate_center := Vector2.ZERO
var water_gates: Array[Dictionary] = []

var zones: Array[Dictionary] = []          ## Normalised landmark zones.
var fight_zones: Array[Dictionary] = []    ## Mission fighting spaces (A, B, C).
var spy_points: Array[Dictionary] = []     ## {route, pos, ok, reason}
var houses: Array[Dictionary] = []
var stalls: Array[Dictionary] = []
var graves: Array[Dictionary] = []
var fence_gates: Array[float] = []         ## Gate angles in degrees.
var fence_arcs: Array = []                 ## [from_deg, to_deg] fence runs.
var rejected: Array[String] = []
var reject_counts := {}


func compute(p_layout: WorldLayout, p_td: TerrainData) -> void:
	layout = p_layout
	td = p_td
	k = layout.dict("kingdom")
	if k.is_empty():
		return
	_collect_zones()
	_plan_wall()
	_plan_spy_points()
	_plan_cemetery()
	for district in k.get("districts", []):
		_plan_district(district)
	for row in k.get("stalls", []):
		_plan_stalls(row)


# --- zones -----------------------------------------------------------------------

func _collect_zones() -> void:
	var replaced: Array = k.get("replaces_exclusions", [])
	for ex in layout.list("residential_exclusions"):
		if ex["name"] in replaced:
			continue
		zones.append({"name": ex["name"], "center": WorldLayout.v2(ex["center"]), "radius": float(ex["radius"])})
	for ex in k.get("landmark_zones", []):
		zones.append(_zone(ex))
	for m in k.get("missions", []):
		if m.has("radius") or m.has("half"):
			var z := _zone(m)
			z["name"] = "Mission %s: %s" % [m["id"], m["name"]]
			z["capacity"] = int(m.get("capacity", 0))
			fight_zones.append(z)


static func _zone(d: Dictionary) -> Dictionary:
	if d.has("box"):
		return {"name": d.get("name", ""), "center": WorldLayout.v2(d["box"]), "half": WorldLayout.v2(d["half"])}
	if d.has("half"):
		return {"name": d.get("name", ""), "center": WorldLayout.v2(d["center"]), "half": WorldLayout.v2(d["half"])}
	return {"name": d.get("name", ""), "center": WorldLayout.v2(d["center"]), "radius": float(d["radius"])}


## Distance from p to the zone edge (negative inside).
static func zone_distance(z: Dictionary, p: Vector2) -> float:
	var c: Vector2 = z["center"]
	if z.has("half"):
		var h: Vector2 = z["half"]
		var q := (p - c).abs() - h
		var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
		return outside + minf(maxf(q.x, q.y), 0.0)
	return p.distance_to(c) - float(z["radius"])


## Area of a fighting zone in square metres.
static func zone_area(z: Dictionary) -> float:
	if z.has("half"):
		var h: Vector2 = z["half"]
		return 4.0 * h.x * h.y
	return PI * float(z["radius"]) * float(z["radius"])


# --- wall, towers, gate -------------------------------------------------------------

func _plan_wall() -> void:
	var w: Dictionary = k["wall"]
	wall_points = WorldLayout.points(w["points"])
	wall_height = float(w["height"])
	wall_thickness = float(w["thickness"])
	var g: Dictionary = k.get("gate", {})
	if not g.is_empty():
		gate_center = WorldLayout.v2(g["center"])
		gate = g.duplicate()
		gate["center_v"] = gate_center
	var gate_half := float(g.get("tower_offset", 12.0)) + float(g.get("tower_diameter", 11.0)) * 0.5 if not g.is_empty() else 0.0
	# Where the wall crosses a river, leave an arched water gate.
	var crossings: Array = []
	for river in layout.list("rivers"):
		var rp := WorldLayout.points(river["points"])
		for s in wall_points.size() - 1:
			for i in rp.size() - 1:
				var hit = Geometry2D.segment_intersects_segment(wall_points[s], wall_points[s + 1], rp[i], rp[i + 1])
				if hit != null:
					crossings.append({"segment": s, "at": hit, "half": float(river["half_width"]) + 3.5, "river": river["name"]})
	for c in crossings:
		var s: int = c["segment"]
		var dir := (wall_points[s + 1] - wall_points[s]).normalized()
		water_gates.append({"center": c["at"], "dir": dir, "span": float(c["half"]) * 2.0, "river": c["river"]})
	for s in wall_points.size() - 1:
		var a := wall_points[s]
		var b := wall_points[s + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var cuts: Array = []  # [from_t, to_t, kind]
		for wg in water_gates:
			var along: float = (wg["center"] - a).dot(dir)
			if along > 0.0 and along < length and absf((wg["center"] - a).cross(dir)) < 1.0:
				cuts.append([along - float(wg["span"]) * 0.5, along + float(wg["span"]) * 0.5, "water_gate"])
		if not g.is_empty():
			var along_g := (gate_center - a).dot(dir)
			if along_g > 0.0 and along_g < length and absf((gate_center - a).cross(dir)) < 1.0:
				cuts.append([along_g - gate_half, along_g + gate_half, "gate"])
		cuts.sort_custom(func(l: Array, r: Array) -> bool: return float(l[0]) < float(r[0]))
		var cursor := 0.0
		var spans: Array = []
		for cut in cuts:
			if float(cut[0]) > cursor:
				spans.append([cursor, float(cut[0]), "wall"])
			spans.append([maxf(float(cut[0]), cursor), float(cut[1]), cut[2]])
			cursor = float(cut[1])
		if cursor < length:
			spans.append([cursor, length, "wall"])
		for span in spans:
			var kind: String = span[2]
			if kind == "gate":
				continue
			var t0: float = span[0]
			var t1: float = span[1]
			var count := maxi(1, int(round((t1 - t0) / WALL_PIECE)))
			for i in count:
				var pa := a + dir * lerpf(t0, t1, float(i) / count)
				var pb := a + dir * lerpf(t0, t1, float(i + 1) / count)
				wall_pieces.append(_wall_piece(pa, pb, s, kind))
	# The wall walk follows the lowland grade; where the ground climbs into the
	# mountains the wall stops rising and disappears into the slope.
	var lowland: Array[float] = []
	for piece in wall_pieces:
		if td.mountain_weight(piece["a"].x, piece["a"].y) < 0.3 and piece["kind"] == "wall":
			lowland.append(piece["ground"])
	lowland.sort()
	wall_ref_ground = lowland[lowland.size() / 2] if not lowland.is_empty() else layout.base_height
	for piece in wall_pieces:
		var walk := minf(float(piece["ground"]), wall_ref_ground + 4.0)
		if piece["kind"] == "water_gate":
			walk = maxf(walk, wall_ref_ground)
		piece["top"] = walk + wall_height
	# Towers at every bend and along long runs; none on the gate or water gate.
	var spacing := float(w["tower_spacing"])
	var candidates: Array[Vector2] = []
	for s in wall_points.size():
		candidates.append(wall_points[s])
	for s in wall_points.size() - 1:
		var a := wall_points[s]
		var b := wall_points[s + 1]
		var count := int(floor(a.distance_to(b) / spacing))
		for i in range(1, count + 1):
			var t := float(i) / float(count + 1)
			candidates.append(a.lerp(b, t))
	for p in candidates:
		if not g.is_empty() and p.distance_to(gate_center) < gate_half + 14.0:
			continue
		var near_water := false
		for wg in water_gates:
			if p.distance_to(wg["center"]) < float(wg["span"]) * 0.5 + 9.0:
				near_water = true
		if near_water:
			continue
		var dup := false
		for t in towers:
			if t.distance_to(p) < spacing * 0.45:
				dup = true
		if dup:
			continue
		towers.append(p)
		tower_info.append({"pos": p, "diameter": float(w["tower_diameter"]), "height": float(w["tower_height"]),
			"mountain": td.mountain_weight(p.x, p.y)})
	# Seal the wall ends into the mountains: barriers run outward to the map edge.
	for end in [[wall_points[0], wall_points[1]], [wall_points[wall_points.size() - 1], wall_points[wall_points.size() - 2]]]:
		var tip: Vector2 = end[0]
		var outward: Vector2 = (tip - end[1]).normalized().lerp(tip.normalized(), 0.6).normalized()
		barrier_extensions.append([tip, tip + outward * (layout.half_size * 1.45 - tip.length())])


func _wall_piece(a: Vector2, b: Vector2, segment: int, kind: String) -> Dictionary:
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var lo := INF
	var sum := 0.0
	var count := 0
	for t: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var p := a.lerp(b, t)
		var centre := td.height_at(p.x, p.y)
		sum += centre
		count += 1
		for side: float in [-0.5, 0.5]:
			var q := p + nrm * side * (wall_thickness + 1.2)
			lo = minf(lo, td.height_at(q.x, q.y))
		lo = minf(lo, centre)
	var ground := sum / count
	return {"a": a, "b": b, "bottom": lo - 1.4, "top": ground + wall_height, "segment": segment, "kind": kind, "ground": ground}


# --- missions ------------------------------------------------------------------------

func _plan_spy_points() -> void:
	for m in k.get("missions", []):
		if not m.has("spawn_points"):
			continue
		var routes: Array = m.get("routes", [])
		var i := 0
		for sp in m["spawn_points"]:
			var p := WorldLayout.v2(sp)
			var reason := ""
			if not td.in_playable(p.x, p.y, 6.0):
				reason = "outside the kingdom"
			elif td.height_at(p.x, p.y) < td.water_level + 0.5:
				reason = "in water"
			elif td.normal_at(p.x, p.y).y < 0.8:
				reason = "too steep"
			for z in zones:
				if reason == "" and zone_distance(z, p) < 0.0 and not String(z["name"]).begins_with("Moonmere"):
					reason = "inside protected zone " + String(z["name"])
			spy_points.append({"pos": p, "route": mini(i / 4, routes.size() - 1), "ok": reason == "", "reason": reason})
			i += 1


# --- cemetery ---------------------------------------------------------------------------

func _plan_cemetery() -> void:
	var cem: Dictionary = k.get("cemetery", {})
	if cem.is_empty():
		return
	var c := WorldLayout.v2(cem["center"])
	var fr := float(cem["fence_radius"])
	var gate_half_deg := rad_to_deg(float(cem["gate_width"]) * 0.5 / fr)
	# Gates wherever a trail or road crosses the fence, plus the main gate.
	var angles: Array[float] = [float(cem["main_gate_deg"])]
	for key in ["trails", "roads"]:
		for route in layout.list(key):
			var pts := WorldLayout.points(route["points"])
			for i in pts.size() - 1:
				var hits := _circle_hits(pts[i], pts[i + 1], c, fr)
				for h in hits:
					var ang := rad_to_deg(atan2(h.y - c.y, h.x - c.x))
					var dup := false
					for e in angles:
						if absf(angle_difference(deg_to_rad(e), deg_to_rad(ang))) < deg_to_rad(gate_half_deg * 1.5):
							dup = true
					if not dup:
						angles.append(ang)
	angles.sort()
	fence_gates = angles
	for i in angles.size():
		var a0 := angles[i] + gate_half_deg
		var a1 := angles[(i + 1) % angles.size()] - gate_half_deg
		if i == angles.size() - 1:
			a1 += 360.0
		if a1 > a0:
			fence_arcs.append([a0, a1])
	var rows: Array = cem["rows"]
	var spacing := float(cem["grave_spacing"])
	var n := 0
	for cluster in cem["clusters"]:
		var ca := float(cluster[0])
		var nrows := int(cluster[1])
		var ncols := int(cluster[2])
		for r in nrows:
			var radius := float(rows[r])
			var step := rad_to_deg(spacing / radius)
			for col in ncols:
				var ang := ca + (float(col) - float(ncols - 1) * 0.5) * step + (step * 0.5 if r == 1 and ncols % 2 == 0 else 0.0)
				var p := c + Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang))) * radius
				var ok := true
				for g in fence_gates:
					if absf(rad_to_deg(angle_difference(deg_to_rad(g), deg_to_rad(ang)))) < gate_half_deg + 4.0:
						ok = false
				if not ok:
					rejected.append("grave at %.0f deg: on a cemetery path" % ang)
					continue
				graves.append({"pos": p, "angle": ang, "variant": n % 6, "index": n, "lean": (n * 37 % 11 - 5) * 0.6})
				n += 1


static func _circle_hits(a: Vector2, b: Vector2, c: Vector2, r: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0 or qa < 1e-6:
		return out
	disc = sqrt(disc)
	for t: float in [(-qb - disc) / (2.0 * qa), (-qb + disc) / (2.0 * qa)]:
		if t >= 0.0 and t <= 1.0:
			out.append(a + d * t)
	return out


# --- houses ------------------------------------------------------------------------------

func _plan_district(district: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(district["name"]))
	var style: Dictionary = STYLES[district.get("style", "town")]
	var setback := float(district.get("setback", 1.8))
	if district.get("kind", "street") == "ring":
		var c := WorldLayout.v2(district["center"])
		var radius := float(district["radius"])
		for arc in district.get("arcs", [[-180, 180]]):
			var ang := float(arc[0])
			while ang < float(arc[1]):
				var arch := _pick(style, rng)
				var w := float(ARCHETYPES[arch]["w"])
				var d := float(ARCHETYPES[arch]["d"])
				var r := radius + setback + d * 0.5
				var dir := Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang)))
				var centre := c + dir * r
				var placed := _try_house(district["name"], arch, centre, -dir, rng)
				var advance := (w + (rng.randf_range(1.4, 3.4) if placed else 1.6)) / r
				ang += rad_to_deg(advance)
		return
	var pts := WorldLayout.points(district["points"])
	for side_name in district.get("sides", ["left"]):
		var side := 1.0 if side_name == "left" else -1.0
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			var length := a.distance_to(b)
			var dir := (b - a) / length
			var nrm := Vector2(dir.y, -dir.x) * side  # points from the street to the lot
			var t := rng.randf_range(0.5, 2.5)
			while t < length - 2.0:
				var arch := _pick(style, rng)
				var w := float(ARCHETYPES[arch]["w"])
				var d := float(ARCHETYPES[arch]["d"])
				var centre := a + dir * (t + w * 0.5) + nrm * (setback + d * 0.5 + _street_half(district, a, b))
				var placed := _try_house(district["name"], arch, centre, -nrm, rng)
				if placed:
					t += w + (rng.randf_range(4.0, 7.0) if rng.randf() < 0.18 else rng.randf_range(1.6, 2.8))
				else:
					t += 2.0


## Half-width of the road this frontage follows (houses stand clear of it).
func _street_half(_district: Dictionary, a: Vector2, b: Vector2) -> float:
	var mid := (a + b) * 0.5
	var best := 2.0
	var best_d := INF
	for key in ["roads", "trails"]:
		for route in layout.list(key):
			var pts := WorldLayout.points(route["points"])
			for i in pts.size() - 1:
				var d := TerrainData.seg_dist(mid, pts[i], pts[i + 1])
				if d < best_d:
					best_d = d
					best = float(route["half_width"])
	return best if best_d < 4.0 else 0.5


func _pick(style: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for key in style:
		total += int(style[key])
	var roll := rng.randi_range(1, total)
	for key in style:
		roll -= int(style[key])
		if roll <= 0:
			return key
	return style.keys()[0]


## Validates and records one house. `front` is the unit direction the door faces.
func _try_house(district_name: String, arch: String, centre: Vector2, front: Vector2, rng: RandomNumberGenerator) -> bool:
	var w := float(ARCHETYPES[arch]["w"])
	var d := float(ARCHETYPES[arch]["d"])
	var yaw := atan2(-front.x, -front.y)
	var reason := house_rejection(centre, yaw, w, d, false)
	if reason != "":
		rejected.append("%s/%s at (%.0f, %.0f): %s" % [district_name, arch, centre.x, centre.y, reason])
		var key := reason.split(":")[0]
		reject_counts[key] = reject_counts.get(key, 0) + 1
		return false
	var tint := rng.randf_range(0.9, 1.06)
	houses.append({"name": "%s %d" % [district_name, houses.size()], "district": district_name, "archetype": arch,
		"center": centre, "yaw": yaw, "w": w, "d": d, "base": footprint_low(centre, yaw, w, d),
		"tint": Color(tint * rng.randf_range(0.97, 1.03), tint, tint * rng.randf_range(0.96, 1.02), 1.0)})
	return true


## Lowest terrain height under the footprint corners (the house base).
func footprint_low(centre: Vector2, yaw: float, w: float, d: float) -> float:
	var lo := INF
	for p in footprint_samples(centre, yaw, w, d):
		lo = minf(lo, td.height_at(p.x, p.y))
	return lo


static func footprint_samples(centre: Vector2, yaw: float, w: float, d: float) -> Array[Vector2]:
	var out: Array[Vector2] = [centre]
	var b := Basis(Vector3.UP, yaw)
	for sx: float in [-0.5, 0.0, 0.5]:
		for sz: float in [-0.5, 0.0, 0.5]:
			if sx == 0.0 and sz == 0.0:
				continue
			var v: Vector3 = b * Vector3(sx * w, 0.0, sz * d)
			out.append(centre + Vector2(v.x, v.z))
	return out


static func corners(centre: Vector2, yaw: float, w: float, d: float, grow := 0.0) -> PackedVector2Array:
	var b := Basis(Vector3.UP, yaw)
	var out := PackedVector2Array()
	for s: Vector2 in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var v: Vector3 = b * Vector3(s.x * (w + grow * 2.0), 0.0, s.y * (d + grow * 2.0))
		out.append(centre + Vector2(v.x, v.z))
	return out


## Returns "" when the footprint is acceptable, or the reason it is not.
func house_rejection(centre: Vector2, yaw: float, w: float, d: float, is_stall: bool) -> String:
	var radius := sqrt(w * w + d * d) * 0.5
	var samples := footprint_samples(centre, yaw, w, d)
	var clearance := float(k["wall"].get("inner_clearance", 9.0))
	for p in samples:
		if td.mountain_weight(p.x, p.y) > 0.2 or td.wall_distance(p.x, p.y) > -clearance:
			return "wall: too close to (or outside) the kingdom wall"
	if not is_stall:
		for z in zones:
			if zone_distance(z, centre) < radius:
				return "landmark: " + String(z["name"])
	for z in fight_zones:
		if zone_distance(z, centre) < radius + 1.0:
			return "mission: " + String(z["name"])
	for sp in spy_points:
		if centre.distance_to(sp["pos"]) < radius + 4.0:
			return "mission: spy spawn point"
	for m in k.get("missions", []):
		for route in m.get("routes", []):
			var rp := WorldLayout.points(route)
			for i in rp.size() - 1:
				if TerrainData.seg_dist(centre, rp[i], rp[i + 1]) < radius + 2.5:
					return "mission: spy patrol route"
	for river in layout.list("rivers"):
		var rp := WorldLayout.points(river["points"])
		var margin := float(river["half_width"]) + float(river["bank"]) + radius + 3.0
		for i in rp.size() - 1:
			if TerrainData.seg_dist(centre, rp[i], rp[i + 1]) < margin:
				return "water: river bank buffer"
	for poi in layout.list("points_of_interest"):
		if centre.distance_to(WorldLayout.v2(poi["pos"])) < 3.0 + radius:
			return "landmark: point of interest " + String(poi["name"])
	for marker in layout.list("scroll_spawns"):
		if centre.distance_to(WorldLayout.v2(marker["pos"])) < 4.5 + radius:
			return "landmark: scroll marker " + String(marker["name"])
	for spawn in layout.list("player_spawns"):
		if centre.distance_to(WorldLayout.v2(spawn)) < 6.0 + radius:
			return "landmark: player spawn"
	var low := INF
	var high := -INF
	for p in samples:
		if td.is_hole_at(p.x, p.y):
			return "terrain: hole"
		var g := td.height_at(p.x, p.y)
		if g < td.water_level + 0.8 or td.sample(td.water_influence, p.x, p.y) > 0.3:
			return "water: wet or low ground"
		if td.normal_at(p.x, p.y).y < 0.87:
			return "terrain: too steep"
		if td.sample(td.trail_dist, p.x, p.y) < 0.8:
			return "road: footprint on a road or trail"
		low = minf(low, g)
		high = maxf(high, g)
	if high - low > 1.8:
		return "terrain: %.1f m height change across footprint" % (high - low)
	var mine := corners(centre, yaw, w, d, HOUSE_CLEARANCE * 0.5)
	for other in houses + stalls:
		if centre.distance_to(other["center"]) > radius + sqrt(float(other["w"]) ** 2 + float(other["d"]) ** 2) * 0.5 + HOUSE_CLEARANCE + 0.5:
			continue
		var theirs := corners(other["center"], other["yaw"], other["w"], other["d"], HOUSE_CLEARANCE * 0.5)
		if not Geometry2D.intersect_polygons(mine, theirs).is_empty():
			return "overlap: another building"
	# The door (front, local -z) needs open, walkable ground in front of it.
	var front := Vector2(-sin(yaw), -cos(yaw))
	var apron := centre + front * (d * 0.5 + DOOR_APRON)
	if td.height_at(apron.x, apron.y) < td.water_level + 0.4 or td.normal_at(apron.x, apron.y).y < 0.85:
		return "door: blocked apron"
	for other in houses + stalls:
		if Geometry2D.is_point_in_polygon(apron, corners(other["center"], other["yaw"], other["w"], other["d"], 0.6)):
			return "door: apron blocked by a building"
	return ""


# --- market stalls ------------------------------------------------------------------------

func _plan_stalls(row: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(row["name"]))
	var pts := WorldLayout.points(row["points"])
	var side := 1.0 if row.get("side", "left") == "left" else -1.0
	for s in pts.size() - 1:
		var a := pts[s]
		var b := pts[s + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var nrm := Vector2(dir.y, -dir.x) * side
		var t := 1.0
		while t < length - STALL_W * 0.5:
			var centre := a + dir * (t + STALL_W * 0.5) + nrm * (STALL_D * 0.5)
			var yaw := atan2(-nrm.x, -nrm.y)  # back on the line, counter facing out
			var reason := house_rejection(centre, yaw, STALL_W, STALL_D, true)
			if reason == "":
				stalls.append({"name": "%s %d" % [row["name"], stalls.size()], "center": centre, "yaw": yaw, "w": STALL_W, "d": STALL_D,
					"variant": rng.randi_range(0, 2), "base": footprint_low(centre, yaw, STALL_W, STALL_D)})
				t += STALL_W + rng.randf_range(1.4, 3.2)
			else:
				rejected.append("%s stall at (%.0f, %.0f): %s" % [row["name"], centre.x, centre.y, reason])
				t += 1.5
