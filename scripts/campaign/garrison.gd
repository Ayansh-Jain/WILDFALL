class_name Garrison
extends Node
## Allied guards at the kingdom's key positions (castle entrance, castle corners,
## watchtower, the curtain wall's towers, the Great Gate, the training-ground corners,
## castle and bridge approaches). Data: the `garrison` block of campaign.json.
##
## Guards are ordinary kingdom soldiers (SoldierFactory -> SoldierRig + SoldierBrain)
## but are NOT on the commander's roster: the Army never sees them, so the follow
## order does not move them. They start in HOLD (stand and watch) or PATROL (a short
## beat), defend themselves and each other against the enemy team, and walk back to
## their post afterwards. A dead guard stays dead (no respawn) and its body is removed
## once it is out of sight.
##
## Every post is validated before a guard is spawned: solid dry ground, a walkable
## slope, room for a standing soldier (so never inside a wall), no more than
## `max_above` over the terrain (so never on a roof), open sky above (never under an
## arch), off every road, outside the mission fighting spaces and the cemetery, and
## `min_spacing` from every other guard. If the listed spot fails, nearby spots are tried.
##
## Level of detail: a guard far from the commander (beyond `sleep_radius`) with no
## enemy near it is put to sleep (its process mode disabled: no AI, animation or
## physics cost) and wakes inside `wake_radius`.

signal guard_died(brain: SoldierBrain)

var world: World
var player: PlayerController
var plan: KingdomPlan
var cfg := {}
var guards: Array[SoldierBrain] = []
## Every post considered: {group, name, want, pos, ok, reason, brain}
var posts: Array[Dictionary] = []

var _roads: Array = []        ## [PackedVector2Array points, float half_width]
var _zones: Array[Dictionary] = []
var _avoid: Array[Vector3] = []
var _accepted: Array[Vector3] = []
var _tick := 0.0
var _serial := 0
var _corpses: Array = []      ## [avatar, died_at]
var _clock := 0.0
var _asleep := {}             ## SoldierBrain -> true


func setup(p_world: World, p_player: PlayerController, p_plan: KingdomPlan, p_cfg: Dictionary, avoid_points: Array[Vector3] = []) -> void:
	world = p_world
	player = p_player
	plan = p_plan
	cfg = p_cfg
	_avoid = avoid_points
	_collect_roads()
	_collect_zones()


func build() -> int:
	clear()
	for g in cfg.get("groups", []):
		var group: Dictionary = g
		var entries: Array = []
		if String(group.get("generate", "")) == "wall_towers":
			entries = _wall_entries(group)
		else:
			entries = group.get("posts", []).duplicate()
		for e in entries:
			_place(group, e)
	return guards.size()


func clear() -> void:
	for b in guards:
		if is_instance_valid(b) and is_instance_valid(b.avatar):
			b.avatar.queue_free()
	for c in _corpses:
		if is_instance_valid(c[0]):
			c[0].queue_free()
	guards.clear()
	_corpses.clear()
	_asleep.clear()
	posts.clear()
	_accepted.clear()


func living() -> Array[SoldierBrain]:
	var out: Array[SoldierBrain] = []
	for b in guards:
		if is_instance_valid(b) and b.is_alive():
			out.append(b)
	return out


# --- placement -------------------------------------------------------------------------------

func _place(group: Dictionary, e: Dictionary) -> void:
	var entry := e.duplicate(true)
	if String(group.get("name", "")) == "Castle entrance":
		var sites := world.get_node("Sites/Structures") as Sites
		var shift := sites.castle_gate_z - 9.0
		entry["pos"][1] += shift
		if entry.has("face"):
			entry["face"][1] += shift
	e = entry
	var want := WorldLayout.v2(e["pos"])
	var rec := {"group": String(group.get("name", "")), "want": want, "ok": false, "reason": "", "brain": null, "pos": Vector3.ZERO}
	var hint := world.resolve_y_hint(String(e.get("y_hint", "")))
	var max_above := float(e.get("max_above", group.get("max_above", 1.5)))
	var found := _resolve(want, hint, max_above)
	rec["ok"] = found["ok"]
	rec["reason"] = found["reason"]
	posts.append(rec)
	if not found["ok"]:
		push_warning("Garrison: no valid spot for a guard at %s (%s): %s" % [want, rec["group"], found["reason"]])
		return
	var pos: Vector3 = found["pos"]
	rec["pos"] = pos
	_accepted.append(pos)
	_serial += 1
	var yaw := 0.0
	if e.has("face"):
		var f := WorldLayout.v2(e["face"])
		yaw = atan2(-(f.x - pos.x), -(f.y - pos.z))
	var patrol := PackedVector3Array()
	var length := 0.0
	if length > 0.0 and e.has("beat"):
		var dir := WorldLayout.v2(e["beat"]).normalized()
		var far := _resolve(Vector2(pos.x, pos.z) + dir * length, hint, max_above, false)
		if far["ok"]:
			patrol = PackedVector3Array([pos, far["pos"]])
	var mode := SoldierBrain.Mode.PATROL if patrol.size() == 2 else SoldierBrain.Mode.HOLD
	var brain := SoldierFactory.spawn(self, world, {"faction": "kingdom", "name": "Guard %d" % _serial,
		"node_name": "Guard_%d" % _serial, "id": 1000 + _serial, "pos": pos, "yaw": yaw, "exact": true,
		"mode": mode, "max_health": int(cfg.get("max_health", 120)), "aggression": float(cfg.get("aggression", 0.55)),
		"sight_range": float(cfg.get("sight_range", 26.0)), "role": "guard", "hold_yaw": yaw})
	if patrol.size() == 2:
		brain.patrol = patrol
	brain.weapons_free = false
	brain.died.connect(_on_guard_died)
	rec["brain"] = brain
	guards.append(brain)


## Finds a valid standing spot at or near `want` (world x, z). {ok, pos, reason}
func _resolve(want: Vector2, y_hint: float, max_above: float, keep_apart := true) -> Dictionary:
	var reason := "no candidate"
	var cands: Array[Vector2] = [want]
	for r: float in [2.0, 3.5, 5.0]:
		for s in 8:
			cands.append(want + Vector2.from_angle(TAU * float(s) / 8.0 + r) * r)
	for c in cands:
		var res := _check(c, y_hint, max_above, keep_apart)
		if res["ok"]:
			return res
		reason = res["reason"]
	return {"ok": false, "pos": Vector3(want.x, 0.0, want.y), "reason": reason}


func _check(p: Vector2, y_hint: float, max_above: float, keep_apart: bool) -> Dictionary:
	var fail := func(why: String) -> Dictionary:
		return {"ok": false, "pos": Vector3(p.x, 0.0, p.y), "reason": why}
	var v := SpawnValidator.check(world, p, y_hint, 25.0, 0.5, float(cfg.get("edge_margin", 5.0)))
	if not v["ok"]:
		return fail.call(v["reason"])
	var pos: Vector3 = v["position"]
	if pos.y - world.terrain_height(p.x, p.y) > max_above:
		return fail.call("on a roof or ledge (%.1f m above ground)" % (pos.y - world.terrain_height(p.x, p.y)))
	var space := world.get_world_3d().direct_space_state
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.9, pos + Vector3.UP * 7.0, Layers.WORLD))
	if not up.is_empty():
		return fail.call("covered")
	if on_road(p):
		return fail.call("on a road")
	for z in _zones:
		if KingdomPlan.zone_distance(z, p) < float(cfg.get("mission_clearance", 4.0)):
			return fail.call("inside " + String(z["name"]))
	if keep_apart:
		var gap := float(cfg.get("min_spacing", 3.0))
		for q in _accepted:
			if Vector2(q.x - p.x, q.z - p.y).length() < gap:
				return fail.call("too close to another guard")
		for q in _avoid:
			if Vector2(q.x - p.x, q.z - p.y).length() < gap:
				return fail.call("too close to a muster post")
	return {"ok": true, "pos": pos, "reason": ""}


func on_road(p: Vector2) -> bool:
	var clearance := float(cfg.get("road_clearance", 1.0))
	for r in _roads:
		var pts: PackedVector2Array = r[0]
		var lim: float = float(r[1]) + clearance
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if p.distance_to(a + ab * t) < lim:
				return true
	return false


func _collect_roads() -> void:
	_roads.clear()
	for t in world.layout.list("trails"):
		_roads.append([WorldLayout.points(t["points"]), float(t.get("half_width", 2.0))])
	for d in world.layout.dict("kingdom").get("districts", []):
		if String(d.get("kind", "")) == "street":
			_roads.append([WorldLayout.points(d["points"]), 3.0])


func _collect_zones() -> void:
	_zones.clear()
	if plan == null:
		return
	for z in plan.fight_zones:
		_zones.append(z)
	for z in plan.zones:
		if String(z["name"]).contains("Cemetery"):
			_zones.append(z)


## Posts just inside the curtain wall at every n-th tower (lowland, away from the gate),
## looking out over the wall; every `patrol_every`-th one walks a short beat along it.
func _wall_entries(group: Dictionary) -> Array:
	var out: Array = []
	if plan == null:
		return out
	var usable: Array[int] = []
	for i in plan.towers.size():
		var t := plan.towers[i]
		if float(plan.tower_info[i]["mountain"]) > 0.3 or t.distance_to(plan.gate_center) < 40.0:
			continue
		usable.append(i)
	var want := mini(int(group.get("count", 8)), usable.size())
	if want <= 0:
		return out
	var inset := float(group.get("inset", 8.0))
	var every := int(group.get("patrol_every", 0))
	for n in want:
		var t := plan.towers[usable[int(floor(float(n) * float(usable.size()) / float(want)))]]
		var inward := (-t).normalized()
		var pos := t + inward * inset
		var e := {"pos": [pos.x, pos.y], "face": [t.x + (-inward.x) * 30.0, t.y + (-inward.y) * 30.0]}
		if every > 0 and n % every == every - 1:
			e["beat"] = [-inward.y, inward.x]
			e["patrol_length"] = float(group.get("patrol_length", 10.0))
		out.append(e)
	return out


# --- running ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_clock += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	_clear_corpses()
	if player == null or not is_instance_valid(player):
		return
	var sleep_r := float(cfg.get("sleep_radius", 170.0))
	var wake_r := float(cfg.get("wake_radius", 140.0))
	for b in guards:
		if not is_instance_valid(b) or not b.is_alive():
			continue
		var d := CampaignUtil.flat_dist(b.avatar.global_position, player.global_position)
		if _asleep.has(b):
			if d < wake_r or _enemy_near(b, 70.0):
				_set_asleep(b, false)
		elif d > sleep_r and b.mode in [SoldierBrain.Mode.HOLD, SoldierBrain.Mode.PATROL] and not _enemy_near(b, 70.0):
			_set_asleep(b, true)


func _enemy_near(b: SoldierBrain, r: float) -> bool:
	for o in SoldierBrain.all:
		if o.team != b.team and o.is_alive() and CampaignUtil.flat_dist(o.avatar.global_position, b.avatar.global_position) < r:
			return true
	return false


func _set_asleep(b: SoldierBrain, on: bool) -> void:
	if on:
		_asleep[b] = true
		b.avatar.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_asleep.erase(b)
		b.avatar.process_mode = Node.PROCESS_MODE_INHERIT


func asleep_count() -> int:
	return _asleep.size()


func _on_guard_died(b: SoldierBrain) -> void:
	_asleep.erase(b)
	_corpses.append([b.avatar, _clock])
	guard_died.emit(b)


func _clear_corpses() -> void:
	for i in range(_corpses.size() - 1, -1, -1):
		var c: Array = _corpses[i]
		var av: PlayerController = c[0]
		if not is_instance_valid(av):
			_corpses.remove_at(i)
			continue
		if _clock - float(c[1]) > float(cfg.get("corpse_seconds", 25.0)) and not CampaignUtil.in_view(player, av.global_position + Vector3.UP, 120.0):
			for k in range(guards.size() - 1, -1, -1):
				if not is_instance_valid(guards[k]) or guards[k].avatar == av:
					guards.remove_at(k)
			av.queue_free()
			_corpses.remove_at(i)
