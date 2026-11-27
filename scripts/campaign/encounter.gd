class_name Encounter
extends Node3D
## One mission's enemy force. Spawns it from the mission's FIXED layout (the same
## positions and counts every attempt), starts it, counts each designated enemy's
## death exactly once, and reports when the objective is met:
##   spies  - 20 spies on their own patrol points across the kingdom; after
##            `kill_target` kills the rest stop fighting, run for the nearest escape
##            point and are removed only out of the player's sight. Complete when
##            the last of them is gone.
##   battle - squads waiting at the battlefield; on contact they advance (in
##            staggered groups if `advance_groups`). Complete when all are dead.
##   final  - `enemy_total` enemies in waves, never more than `max_active` alive at
##            once; the captain comes with the last wave. Complete when all are dead.
## reset() removes everything so the next spawn starts from the initial state.

signal progress_changed(kills: int, target: int)
signal phase_changed(text: String)
signal objective_completed
## An enemy was hurt (or hurt someone) before the encounter started: start it.
signal contact

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var cfg := {}
var world: World
var leader: PlayerController
var route: RouteGraph
var plan: KingdomPlan
var mission_type := ""
var kills := 0
var target := 0
var active := false
var retreating := false
var done := false
var enemies: Array[SoldierBrain] = []
## Where each enemy of this attempt was placed (the fixed layout; identical every attempt).
var spawn_layout: Array[Vector3] = []
var phase_text := ""

var _counted := {}       ## player id -> true (each enemy counts once)
var _enemy_ids := {}     ## player id -> SoldierBrain
var _serial := 0
var _escaped := 0
var _retreat_t := 0.0
var _tick := 0.0
var _clock := 0.0
var _groups: Array = []  ## battle: [[start_time, [brains]]]
var _waves: Array = []
var _wave_i := -1
var _wave_t := 0.0
var _pending := 0
var _spawned := 0
var _captain: SoldierBrain
var _spawn_t := 0.0
var boss_stage: Node
var tent_positions: Array[Vector3] = []
var _corpses: Array = []


## One-time wiring (the director keeps a single Encounter and reconfigures it).
func init(p_world: World, p_leader: PlayerController, p_route: RouteGraph, p_plan: KingdomPlan) -> void:
	world = p_world
	leader = p_leader
	route = p_route
	plan = p_plan
	Combat.player_defeated.connect(_on_defeated)
	Combat.damage_dealt.connect(_on_damage)


## Selects the mission whose force this encounter fields (call reset() first).
func configure(mission_cfg: Dictionary) -> void:
	cfg = mission_cfg
	mission_type = String(cfg.get("type", "battle"))
	match mission_type:
		"spies":
			target = int(cfg.get("kill_target", 10))
		"final":
			target = int(cfg.get("enemy_total", 100))
		_:
			target = int(cfg.get("enemy_count", 20))


func _on_damage(e: Dictionary) -> void:
	if not active and not done and (_enemy_ids.has(e["target"]) or _enemy_ids.has(e["source"])):
		contact.emit()


## Total enemies this encounter is designed to field.
func designated_count() -> int:
	return int(cfg.get("enemy_total", cfg.get("enemy_count", 0)))


func area() -> Dictionary:
	for m in world.layout.dict("kingdom").get("missions", []):
		if String(m["id"]) == String(cfg.get("area", "")):
			return m
	return {}


func area_center() -> Vector3:
	var a := area()
	if a.has("center"):
		return CampaignUtil.v3(world, a["center"])
	if not enemies.is_empty():
		return enemies[0].avatar.global_position
	return leader.global_position


# --- spawning ------------------------------------------------------------------------------------

## Places the initial force (dormant; spies already on their routes).
func spawn_initial() -> void:
	reset()
	match mission_type:
		"camp":
			_spawn_camp()
		"spies":
			_spawn_spies()
		"battle":
			_spawn_squads()
		"final":
			_waves = cfg.get("waves", []).duplicate(true)
			_wave_i = -1
			_start_wave()
			# Wave one is placed at once and waits on the field.
			while _pending > 0 and alive_count() < int(cfg.get("max_active", 40)):
				_spawn_reinforcement(true)
	_emit_progress()


func _make_enemy(pos: Vector3, yaw: float, variant := "", health := 100, exact := false) -> SoldierBrain:
	_serial += 1
	var label := "Spy %d" % _serial if variant == "spy" else ("Enemy captain" if variant == "captain" else "Enemy %d" % _serial)
	var brain := SoldierFactory.spawn(self, world, {"faction": "enemy", "variant": variant, "name": label,
		"node_name": "Enemy_%d" % _serial, "id": _serial, "pos": pos, "yaw": yaw,
		"mode": SoldierBrain.Mode.DORMANT, "max_health": health, "exact": exact, "aggression": float(cfg.get("enemy_aggression", 0.35)),
		"role": variant if variant != "" else "raider", "mission": int(cfg.get("id", -1))})
	brain.encounter = self
	var av := brain.avatar
	spawn_layout.append(av.global_position)
	enemies.append(brain)
	_enemy_ids[av.player_id] = brain
	return brain


func _spawn_spies() -> void:
	var routes: Array = area().get("routes", [])
	var pts: Array = []
	for sp in (plan.spy_points if plan else []):
		if sp["ok"]:
			pts.append(sp)
	var count := int(cfg.get("enemy_count", 20))
	var health := int(cfg.get("enemy_health", 70))
	for i in mini(count, pts.size()):
		var sp: Dictionary = pts[i]
		var p: Vector2 = sp["pos"]
		var pos := Vector3(p.x, world.terrain_height(p.x, p.y), p.y)
		var b := _make_enemy(pos, float(i) * 1.7, String(cfg.get("enemy_variant", "spy")), health)
		b.sight_range = float(cfg.get("sight_range", 20.0))
		b.alert_radius = float(cfg.get("alert_radius", 26.0))
		var r: Array = routes[int(sp["route"])] if int(sp["route"]) < routes.size() else []
		var line := PackedVector3Array()
		for q in r:
			line.append(CampaignUtil.v3(world, q))
		b.patrol = line
		b._patrol_i = _nearest_index(line, pos)
		b._patrol_dir = 1 if i % 2 == 0 else -1
	if pts.size() < count:
		push_warning("Encounter: only %d valid spy points for %d spies" % [pts.size(), count])


static func _nearest_index(line: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	for i in line.size():
		if CampaignUtil.flat_dist(line[i], p) < CampaignUtil.flat_dist(line[best], p):
			best = i
	return best


func _spawn_squads() -> void:
	var stage := CampaignUtil.v3(world, cfg.get("ally_stage", [0, 0]))
	var health := int(cfg.get("enemy_health", 100))
	var spacing := Battlefield.setting("spawn_spacing", 3.6)
	var jitter := Battlefield.setting("spawn_jitter", 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4040 + int(cfg.get("id", 0))  # the same layout on every attempt
	_groups.clear()
	var g := 0
	for sq in cfg.get("squads", []):
		var c := Vector3(float(sq[0]), 0.0, float(sq[1]))
		c.y = world.terrain_height(c.x, c.z)
		var n := int(sq[2])
		var to := stage - c
		var yaw := atan2(-to.x, -to.z)
		var members: Array = []
		var cols := 5 if n >= 8 else 3
		# Each squad marches on its own point in front of the defenders, on its own bearing.
		var lane := Vector3(-to.x, 0.0, -to.z).normalized() * Battlefield.setting("lane_distance", 9.0)
		for i in n:
			var row := i / cols
			var col := i % cols
			var local := Vector3((col - (cols - 1) * 0.5) * spacing + rng.randf_range(-jitter, jitter), 0.0, row * spacing + rng.randf_range(-jitter, jitter))
			var want := c + Basis(Vector3.UP, yaw) * local
			want.y = world.terrain_height(want.x, want.z)
			var b := _make_enemy(_free_spot(want), yaw, "", health, true)
			b.lane_offset = lane + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
			members.append(b)
		var delay := g * float(cfg.get("advance_interval", 0.0)) if bool(cfg.get("advance_groups", false)) else 0.0
		_groups.append([delay, members, false])
		g += 1


## Valid ground at (or near) `pos` that no earlier spawn of this attempt already stands on.
func _free_spot(pos: Vector3, snap := 6.0) -> Vector3:
	var gap := Battlefield.setting("min_spawn_gap", 1.9)
	for ring in 5:
		for k in (1 if ring == 0 else 8):
			var q := pos
			if ring > 0:
				var a := TAU * float(k) / 8.0 + float(ring)
				q += Vector3(cos(a), 0.0, sin(a)) * 2.4 * float(ring)
				q.y = world.terrain_height(q.x, q.z)
			var res := SpawnValidator.find(world, Vector2(q.x, q.z), q.y + 3.0, snap)
			if not res["ok"]:
				continue
			var p: Vector3 = res["position"]
			var clear := true
			for o in spawn_layout:
				if CampaignUtil.flat_dist(o, p) < gap:
					clear = false
					break
			if clear:
				return p
	return pos


# --- final battle waves -------------------------------------------------------------------------

func _start_wave() -> void:
	_wave_i += 1
	if _wave_i >= _waves.size():
		return
	var w: Dictionary = _waves[_wave_i]
	var room := int(cfg.get("enemy_total", 100)) - _spawned - _pending
	_pending += mini(int(w.get("count", 0)), maxi(room, 0))
	_wave_t = 0.0
	if bool(w.get("captain", false)):
		phase_text = String(cfg.get("captain_objective", "Defeat their captain"))
	else:
		phase_text = "Wave %d of %d" % [_wave_i + 1, _waves.size()]
	phase_changed.emit(phase_text)


func _spawn_reinforcement(initial: bool) -> void:
	var spawns: Array = cfg.get("wave_spawns", [])
	if spawns.is_empty():
		return
	# The spawn point farthest from the commander that he cannot see.
	var best := Vector3.INF
	var best_score := -INF
	for i in spawns.size():
		var p := CampaignUtil.v3(world, spawns[(i + _spawned) % spawns.size()])
		p += Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		var score := CampaignUtil.flat_dist(p, leader.global_position)
		if not initial and CampaignUtil.in_view(leader, p + Vector3.UP, 200.0):
			score -= 1000.0
		if score > best_score:
			best_score = score
			best = p
	var w: Dictionary = _waves[clampi(_wave_i, 0, _waves.size() - 1)] if not _waves.is_empty() else {}
	var last := _pending == 1 and bool(w.get("captain", false))
	var stage := CampaignUtil.v3(world, cfg.get("ally_stage", [0, 0]))
	var to := stage - best
	var b := _make_enemy(_free_spot(best), atan2(-to.x, -to.z), "captain" if last else "",
		int(cfg.get("captain_health", 400)) if last else int(cfg.get("enemy_health", 100)), true)
	b.lane_offset = _lane_for(b)
	if last:
		_captain = b
		b.aggression = 0.6
	_pending -= 1
	_spawned += 1
	if active:
		_advance(b)


# --- running -----------------------------------------------------------------------------------

func activate() -> void:
	if active or done:
		return
	active = true
	_clock = 0.0
	match mission_type:
		"spies":
			for b in enemies:
				b.order = SoldierBrain.Mode.PATROL
				b._enter(SoldierBrain.Mode.PATROL)
		"battle":
			for g in _groups:
				if float(g[0]) <= 0.0:
					_release_group(g)
		"final":
			for b in enemies:
				_advance(b)
	_emit_progress()


func _release_group(g: Array) -> void:
	g[2] = true
	for b in g[1]:
		_advance(b)


func _advance(b: SoldierBrain) -> void:
	if not b.is_alive():
		return
	if b.lane_offset == Vector3.ZERO:
		b.lane_offset = _lane_for(b)
	b.advance_target = _defenders_center() + b.lane_offset
	b.order = SoldierBrain.Mode.ADVANCE
	b._enter(SoldierBrain.Mode.ADVANCE)


## Where an enemy lines up for its approach: out in front of the defenders on its own
## bearing, fanned by its spawn index, so a host arrives from several directions.
func _lane_for(b: SoldierBrain) -> Vector3:
	var from := b.avatar.global_position - _defenders_center()
	from.y = 0.0
	var dir := from.normalized() if from.length() > 1.0 else Vector3.FORWARD
	var fan := float((b.soldier_id * 5) % 7 - 3) * 0.16
	return dir.rotated(Vector3.UP, fan) * Battlefield.setting("lane_distance", 9.0)


func _defenders_center() -> Vector3:
	return leader.global_position


func set_paused(p: bool) -> void:
	for b in enemies:
		if is_instance_valid(b) and b.is_alive():
			b.paused = p


func _physics_process(delta: float) -> void:
	_clock += delta
	_tick -= delta
	if active and not done and mission_type == "final":
		_tick_waves(delta)
	if _tick > 0.0:
		return
	_tick = 0.5
	_clear_corpses()
	if not active or done:
		return
	if mission_type == "battle":
		for g in _groups:
			if not g[2] and _clock >= float(g[0]):
				_release_group(g)
	# Marching enemies keep heading for the defenders.
	for b in enemies:
		if is_instance_valid(b) and b.is_alive() and b.mode == SoldierBrain.Mode.ADVANCE:
			b.advance_target = _defenders_center() + b.lane_offset
	if retreating:
		_tick_retreat(0.5)
	_check_complete()


func _tick_waves(delta: float) -> void:
	_wave_t += delta
	if _wave_i + 1 < _waves.size():
		var nxt: Dictionary = _waves[_wave_i + 1]
		var remaining := alive_count() + _pending
		var when := int(nxt.get("when_remaining", -1))
		if (when >= 0 and remaining <= when) or _wave_t >= float(nxt.get("after_seconds", 1e9)):
			_start_wave()
	_spawn_t -= delta
	if _pending > 0 and alive_count() < int(cfg.get("max_active", 40)) and _spawn_t <= 0.0:
		_spawn_t = 0.35
		_spawn_reinforcement(false)


func alive_count() -> int:
	var n := 0
	for b in enemies:
		if is_instance_valid(b) and b.is_alive():
			n += 1
	return n


func spawned_count() -> int:
	return _spawned if mission_type == "final" else enemies.size()


func _on_defeated(e: Dictionary) -> void:
	var vid: int = e["victim"]
	if not _enemy_ids.has(vid) or _counted.has(vid):
		return
	_counted[vid] = true
	var b: SoldierBrain = _enemy_ids[vid]
	_corpses.append([b.avatar, _clock])
	if done:
		return
	kills += 1
	_emit_progress()
	if mission_type == "spies" and not retreating and kills >= target:
		_begin_retreat()


func _emit_progress() -> void:
	progress_changed.emit(mini(kills, target), target)


# --- spies: retreat ----------------------------------------------------------------------------

func _begin_retreat() -> void:
	retreating = true
	_retreat_t = 0.0
	phase_text = String(cfg.get("retreat_text", "The enemy is fleeing."))
	phase_changed.emit(phase_text)
	var exits: Array[Vector3] = []
	for p in cfg.get("escape_points", []):
		var v := CampaignUtil.v3(world, p)
		var res := SpawnValidator.find(world, Vector2(v.x, v.z), NAN, 12.0)
		exits.append(res["position"] if res["ok"] else v)
	for b in enemies:
		if not is_instance_valid(b) or not b.is_alive():
			continue
		var best := Vector3.INF
		var best_score := INF
		for x in exits:
			# Nearest exit that does not lead through the commander.
			var score := CampaignUtil.flat_dist(x, b.avatar.global_position)
			if CampaignUtil.flat_dist(x, leader.global_position) < CampaignUtil.flat_dist(b.avatar.global_position, leader.global_position):
				score += 80.0
			if score < best_score:
				best_score = score
				best = x
		if best == Vector3.INF:
			var away := b.avatar.global_position - leader.global_position
			away.y = 0.0
			best = b.avatar.global_position + away.normalized() * 80.0
		b.retreat_to(best, route.route(b.avatar.global_position, best) if route else PackedVector3Array())


func retreating_count() -> int:
	var n := 0
	for b in enemies:
		if is_instance_valid(b) and b.is_alive() and b.mode == SoldierBrain.Mode.RETREAT:
			n += 1
	return n


func _tick_retreat(dt: float) -> void:
	_retreat_t += dt
	for i in range(enemies.size() - 1, -1, -1):
		var b := enemies[i]
		if not is_instance_valid(b) or not b.is_alive() or b.mode != SoldierBrain.Mode.RETREAT:
			continue
		var p := b.avatar.global_position
		var arrived := CampaignUtil.flat_dist(p, b.retreat_target) < 5.0
		var far := CampaignUtil.flat_dist(p, leader.global_position) > 90.0
		var late := _retreat_t > 120.0
		if (arrived or far or late) and not CampaignUtil.in_view(leader, p + Vector3.UP * 1.0, 400.0):
			_escaped += 1
			_enemy_ids.erase(b.avatar.player_id)
			enemies.remove_at(i)
			b.avatar.queue_free()


func escaped_count() -> int:
	return _escaped


# --- completion -----------------------------------------------------------------------------------

func _check_complete() -> void:
	if done:
		return
	var finished := false
	match mission_type:
		"spies":
			finished = retreating and kills >= target and retreating_count() == 0 and alive_count() == 0
		"battle":
			finished = alive_count() == 0 and kills >= designated_count()
		"camp":
			if alive_count() == 0 and kills >= designated_count() and is_instance_valid(boss_stage):
				if not boss_stage.started:
					boss_stage.begin()
				finished = boss_stage.defeated
		"final":
			finished = _spawned >= designated_count() and _pending == 0 and alive_count() == 0
	if finished:
		done = true
		active = false
		objective_completed.emit()


func _clear_corpses() -> void:
	for i in range(_corpses.size() - 1, -1, -1):
		var c: Array = _corpses[i]
		var av: PlayerController = c[0]
		if not is_instance_valid(av):
			_corpses.remove_at(i)
			continue
		if _clock - float(c[1]) > 20.0 and not CampaignUtil.in_view(leader, av.global_position + Vector3.UP, 120.0):
			for k in range(enemies.size() - 1, -1, -1):
				if not is_instance_valid(enemies[k]) or enemies[k].avatar == av:
					enemies.remove_at(k)
			av.queue_free()
			_corpses.remove_at(i)


## Removes the whole force at once (under a fade, or when the mission is over) and
## clears every counter, so the next spawn_initial() starts from scratch.
func reset() -> void:
	if is_instance_valid(boss_stage):
		remove_child(boss_stage)
		boss_stage.queue_free()
	boss_stage = null
	tent_positions.clear()
	var props := get_node_or_null("CampProps")
	if props:
		remove_child(props)
		props.queue_free()
	for b in enemies:
		if is_instance_valid(b) and is_instance_valid(b.avatar):
			b.avatar.queue_free()
	for c in _corpses:
		if is_instance_valid(c[0]):
			c[0].queue_free()
	Battlefield.reset()
	enemies.clear()
	spawn_layout.clear()
	_enemy_ids.clear()
	_counted.clear()
	_corpses.clear()
	_groups.clear()
	_waves.clear()
	_wave_i = -1
	_pending = 0
	_spawned = 0
	_captain = null
	kills = 0
	_escaped = 0
	active = false
	retreating = false
	done = false
	phase_text = ""


func captain() -> SoldierBrain:
	return _captain


func _spawn_camp() -> void:
	var center := area_center()
	_camp_props(center)
	for i in int(cfg.get("enemy_count", 10)):
		var angle := float(i) * 2.39996
		var p := center + Vector3(cos(angle), 0, sin(angle)) * (4.0 + float(i % 3) * 2.5)
		p.y = world.terrain_height(p.x, p.z)
		var b := _make_enemy(_free_spot(p), angle, "", int(cfg.get("enemy_health", 100)), true)
		b.sight_range = float(cfg.get("sight_range", 10.0))
		b.hear_range = float(cfg.get("hear_range", 2.5))
		b.weapons_free = false
		if i % 3 == 1 and b.rig():
			b.rig().hold("sit_idle")
	boss_stage = load("res://scripts/campaign/giant_duel.gd").new()
	add_child(boss_stage)
	boss_stage.setup(self)



func _camp_props(center: Vector3) -> void:
	var root := Node3D.new()
	root.name = "CampProps"
	add_child(root)
	for offset in [Vector3(-14,0,8),Vector3(12,0,-7),Vector3(12,0,9),Vector3(-16,0,-16)]:
		var point: Vector3 = center + offset
		point.y = world.terrain_height(point.x,point.z)
		tent_positions.append(point)
		_build_tent(root,point,tent_positions.size()==4)
	# Low bedrolls and a stone fire ring leave the existing landscape untouched.
	for i in 3:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8,0.08,1.9)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.20,0.16,0.11)
		mesh.material_override = mat
		root.add_child(mesh)
		var p := center + Vector3(-2.2 + i * 2.2,0,2.0)
		mesh.global_position = Vector3(p.x,world.terrain_height(p.x,p.z)+0.07,p.z)
		mesh.rotation.y = i * 0.7
	for i in 9:
		var stone := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.24
		sphere.height = 0.32
		sphere.radial_segments = 8
		sphere.rings = 4
		stone.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25,0.24,0.21)
		stone.material_override = mat
		root.add_child(stone)
		var p := center + Vector3(cos(i*TAU/9),0,sin(i*TAU/9)) * 0.8
		stone.global_position = Vector3(p.x,world.terrain_height(p.x,p.z)+0.1,p.z)


func _camp_box(parent: Node3D, at: Vector3, size: Vector3, material: Material, solid := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = at
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		mesh.add_child(body)
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
	return mesh


func _build_tent(root: Node3D, at: Vector3, giant: bool) -> void:
	var tent := Node3D.new()
	tent.name = "GiantTent" if giant else "BlackTent%d" % tent_positions.size()
	root.add_child(tent)
	tent.global_position = at
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.045,0.042,0.04)
	cloth.roughness = 0.95
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	var timber := StandardMaterial3D.new()
	timber.albedo_color = Color(0.19,0.12,0.07)
	for x in [-3.0,3.0]:
		_camp_box(tent,Vector3(x,1.5,0),Vector3(0.12,3,6),cloth)
		var roof := _camp_box(tent,Vector3(x*0.5,3.65,0),Vector3(3.4,0.10,6.1),cloth)
		roof.rotation.z = -signf(x)*0.43
	_camp_box(tent,Vector3(0,1.5,-3),Vector3(6,3,0.12),cloth)
	for x in [-2.3,2.3]:
		_camp_box(tent,Vector3(x,1.5,3),Vector3(1.4,3,0.12),cloth)
	var curtain := _camp_box(tent,Vector3(0,1.55,3.03),Vector3(3.2,3.1,0.06),cloth,false)
	curtain.name = "Curtain"
	for z in [-3.0,3.0]:
		_camp_box(tent,Vector3(0,2.2,z),Vector3(0.12,4.4,0.12),timber,false)
	_camp_box(tent,Vector3(-4,0.6,1),Vector3(1.2,1.2,1.2),timber)
	_camp_box(tent,Vector3(-4,1.65,1),Vector3(0.8,0.9,0.8),timber)
	var barrel := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius=0.45
	cylinder.bottom_radius=0.45
	cylinder.height=1.2
	cylinder.radial_segments=10
	barrel.mesh=cylinder
	barrel.material_override=timber
	tent.add_child(barrel)
	barrel.position=Vector3(4,0.6,1)
