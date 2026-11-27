class_name Army
extends Node3D
## The commander's company: one SoldierBrain-driven avatar per LIVING roster
## soldier (the dead are never respawned), the follow / hold order, formation
## slots, the commander's breadcrumb trail, long-distance regrouping along the
## route graph, and the company's horses.
##
## Following: soldiers keep slots in ranks behind the commander. Where walls are in
## the way they walk his own footsteps; from far away they march the trail and road
## network (status "Regrouping"). They wait outside the keep, the crypt and the cave
## instead of crowding in after him. A fight near them (or near him) switches them to
## combat; when it is over they fall back in.
## Holding: they stop where they are and only defend themselves.
## Mounted: when the commander mounts, soldiers with a free horse nearby walk to it
## and climb up; the rest keep marching on foot (nobody is teleported onto a horse).

signal status_changed(text: String)
signal soldier_died(roster_id: int)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HORSE_SCENE := preload("res://scenes/horse/horse.tscn")
const CRUMB_STEP := 2.5
const MAX_CRUMBS := 600

enum Order { HOLD, FOLLOW }

var order: int = Order.HOLD
var leader: PlayerController
var world: World
var state: CampaignState
var route: RouteGraph
var spacing := 2.4
var soldiers := {}   ## roster id -> PlayerController
var brains := {}     ## roster id -> SoldierBrain
var horses: Array[Horse] = []
var corpses: Array = []  ## [avatar, died_at]

var _crumbs := PackedVector3Array()
var _last_outdoor := Vector3.INF
var _last_outdoor_yaw := 0.0
var _status := ""
var _tick := 0.0
var _interiors: Array = []
var _mounted_order := false
var _narrow_t := 0.0
var travel_yaw := 0.0
var transitioning := false
var _recovery_watch := {}


func setup(p_world: World, p_leader: PlayerController, p_state: CampaignState, p_route: RouteGraph) -> void:
	world = p_world
	leader = p_leader
	state = p_state
	route = p_route
	spacing = float(state.army().get("follow_spacing", 2.4))
	var sites := world.get_node_or_null("Sites/Structures")
	if sites and "interior_zones" in sites:
		_interiors = sites.interior_zones
	var rider := leader.get_node_or_null("Rider") as Rider
	if rider:
		rider.transition_started.connect(_mount_transition)
		rider.mounted.connect(func(_h: Horse) -> void: _on_leader_mounted())
		rider.dismounted.connect(func(_h: Horse) -> void: _on_leader_dismounted())


# --- roster <-> world ------------------------------------------------------------------------

## Spawns every living roster soldier that is not in the world yet, around `center`
## in ranks facing `yaw` (a fresh campaign uses the training-ground posts).
func spawn_missing(center: Vector3, yaw: float, posts: Array = []) -> void:
	var i := 0
	for rec in state.roster:
		var id := int(rec["id"])
		if not rec["alive"] or soldiers.has(id):
			continue
		var pos: Vector3 = posts[i] if i < posts.size() else _rank_point(center, yaw, i - posts.size())
		_spawn(rec, pos, yaw)
		i += 1
	_emit_status()


func _spawn(rec: Dictionary, pos: Vector3, yaw: float) -> PlayerController:
	var id := int(rec["id"])
	var start_mode := SoldierBrain.Mode.FOLLOW if order == Order.FOLLOW else SoldierBrain.Mode.HOLD
	var brain := SoldierFactory.spawn(self, world, {"faction": "kingdom", "name": String(rec["name"]),
		"node_name": "Soldier_%d" % id, "id": id, "pos": pos, "yaw": yaw, "mode": start_mode,
		"health": int(rec["health"]), "role": "line"})
	brain.army = self
	brain.weapons_free = false
	var av := brain.avatar
	brain.died.connect(_on_brain_died)
	soldiers[id] = av
	brains[id] = brain
	return av


func _rank_point(center: Vector3, yaw: float, i: int) -> Vector3:
	var cols := 2 if state.roster_size() <= 4 else 5
	var row := i / cols
	var col := i % cols
	var local := Vector3((col - (cols - 1) * 0.5) * spacing, 0.0, row * spacing)
	return center + Basis(Vector3.UP, yaw) * local


## Removes every soldier avatar (the roster itself is unchanged).
func despawn_all() -> void:
	_mounted_order = false
	for id in soldiers.keys():
		var av: PlayerController = soldiers[id]
		var b: SoldierBrain = brains.get(id)
		if b and b.horse:
			b.dismount()
		if is_instance_valid(av):
			av.queue_free()
	soldiers.clear()
	brains.clear()
	_slot_cache.clear()
	for c in corpses:
		if is_instance_valid(c[0]):
			c[0].queue_free()
	corpses.clear()
	for h in horses:
		if is_instance_valid(h):
			h.queue_free()
	horses.clear()


## Writes every soldier's life and health back into the roster.
func sync_to_state() -> void:
	for id in soldiers:
		var av: PlayerController = soldiers[id]
		if not is_instance_valid(av):
			continue
		var alive := not av.is_defeated and av.combatant.is_alive()
		state.set_soldier(id, alive, av.combatant.health)


## Moves the living company into ranks at `center` (under a fade: retry / quit).
func place_at(center: Vector3, yaw: float) -> void:
	var i := 0
	for id in soldiers:
		var av: PlayerController = soldiers[id]
		var b: SoldierBrain = brains[id]
		if not b.is_alive():
			continue
		if b.horse:
			b.dismount()
		var pos := _rank_point(center, yaw, i)
		var res := SpawnValidator.find(world, Vector2(pos.x, pos.z), pos.y + 3.0, 6.0)
		av.teleport((res["position"] if res["ok"] else pos) + Vector3.UP * 0.05, yaw)
		b.hold_pos = av.global_position
		b._enter(b.order)
		i += 1
	_crumbs.clear()


func living() -> Array[SoldierBrain]:
	var out: Array[SoldierBrain] = []
	for id in brains:
		var b: SoldierBrain = brains[id]
		if b.is_alive():
			out.append(b)
	return out


func set_paused(p: bool) -> void:
	for b in living():
		b.paused = p


func _on_brain_died(b: SoldierBrain) -> void:
	state.set_soldier(b.soldier_id, false, 0)
	corpses.append([b.avatar, Combat.now()])
	soldiers.erase(b.soldier_id)
	brains.erase(b.soldier_id)
	_slot_cache.erase(b.soldier_id)
	soldier_died.emit(b.soldier_id)
	_emit_status()


# --- orders ----------------------------------------------------------------------------------

func toggle_follow() -> void:
	set_follow(order != Order.FOLLOW)


func set_follow(on: bool) -> void:
	order = Order.FOLLOW if on else Order.HOLD
	for b in living():
		if not on:
			b.hold_pos = b.avatar.global_position
		b.set_order(SoldierBrain.Mode.FOLLOW if on else SoldierBrain.Mode.HOLD)
	if on and leader.riding:
		_on_leader_mounted()
	_emit_status()


func is_following() -> bool:
	return order == Order.FOLLOW


func status() -> String:
	var alive := living()
	if alive.is_empty():
		return "No soldiers"
	if order == Order.HOLD:
		for b in alive:
			if b.mode == SoldierBrain.Mode.COMBAT:
				return "Holding (fighting)"
		return "Holding position"
	var regroup_count := 0
	var mounted := 0
	for b in alive:
		if b.mode == SoldierBrain.Mode.COMBAT:
			return "In combat"
		if b.mode == SoldierBrain.Mode.REGROUP or (b.mode == SoldierBrain.Mode.FOLLOW and b._flat(slot_position(b)) > 14.0):
			regroup_count += 1
		if b.mode == SoldierBrain.Mode.MOUNTED or b.mode == SoldierBrain.Mode.MOUNT:
			mounted += 1
	if regroup_count > alive.size() / 3:
		return "Regrouping"
	if mounted > 0:
		return "Following (%d mounted)" % mounted
	return "Following"


func _emit_status() -> void:
	var s := status()
	if s != _status:
		_status = s
		status_changed.emit(s)


# --- formation and routes --------------------------------------------------------------------

## Where the commander effectively is for the company: himself outdoors, or the
## spot where he went indoors / underground (they wait there).
func anchor() -> Vector3:
	if leader_inside() and _last_outdoor != Vector3.INF:
		return _last_outdoor
	return leader.global_position


func leader_inside() -> bool:
	var eye := leader.global_position + Vector3.UP * 1.5
	for z: Dictionary in _interiors:
		if (z["aabb"] as AABB).has_point(z.get("inverse", Transform3D.IDENTITY) * eye):
			return true
	return world.terrain_height(leader.global_position.x, leader.global_position.z) > leader.global_position.y + 2.5


var _slot_frame := -1
var _slot_idx := {}


## Each living soldier's rank-and-file index, computed once per physics frame. When he
## rides, the mounted soldiers take the front ranks (they keep up with the horses).
func _slot_index(b: SoldierBrain) -> int:
	var f := Engine.get_physics_frames()
	if f != _slot_frame:
		_slot_frame = f
		_slot_idx.clear()
		var ordered: Array = []
		var rest: Array = []
		for id in brains:
			var o: SoldierBrain = brains[id]
			if not o.is_alive():
				continue
			var o_mounted := o.mode == SoldierBrain.Mode.MOUNTED or o.mode == SoldierBrain.Mode.MOUNT
			if leader.riding and o_mounted:
				ordered.append(o)
			else:
				rest.append(o)
		ordered.append_array(rest)
		for i in ordered.size():
			_slot_idx[ordered[i]] = i
	return int(_slot_idx.get(b, 0))


## The slot a soldier should keep, cached for a few frames per soldier (the brains ask
## often; riders every frame) and pulled back inside whatever walls the ideal spot is behind.
func slot_position(b: SoldierBrain) -> Vector3:
	var f := Engine.get_physics_frames()
	var c: Array = _slot_cache.get(b.soldier_id, [])
	if not c.is_empty() and f < int(c[0]):
		return c[1]
	var p := _clamp_to_open(_raw_slot(b))
	_slot_cache[b.soldier_id] = [f + 10 + b.soldier_id % 5, p]
	return p


var _slot_cache := {}
var _narrow := false


func _raw_slot(b: SoldierBrain) -> Vector3:
	var idx: int = _slot_index(b)
	var yaw := _last_outdoor_yaw if leader_inside() else travel_yaw
	if leader.riding:
		var rider := leader.get_node_or_null("Rider") as Rider
		if rider and rider.horse:
			yaw = rider.horse.rotation.y
	# Ranks behind him, starting beyond the follow camera (3.9 m back) so the company does
	# not stand in front of the lens; wider and looser when mounted, a two-file column
	# where the way is narrow (roads between houses, gates, bridges).
	var cols := 2 if living().size() <= 4 or _narrow else 4
	var row := idx / cols
	var col := idx % cols
	var wide := 1.5 if leader.riding else (0.9 if _narrow else 1.25)
	var back := 5.2 + (2.5 if leader.riding else 0.0) + row * spacing * (1.6 if leader.riding else 1.0)
	# A loose, uneven line rather than a parade: a stable per-slot wobble.
	var wob_x := 0.0
	var wob_z := 0.0
	var local := Vector3((col - (cols - 1) * 0.5) * spacing * wide + wob_x, 0.0, back + wob_z)
	var p := anchor() + Basis(Vector3.UP, yaw) * local
	p.y = world.terrain_height(p.x, p.z) if not leader_inside() else anchor().y
	return p


## If a wall, house or rock stands between the commander and the ideal slot, stand in
## front of it instead of inside or behind it.
func _clamp_to_open(p: Vector3) -> Vector3:
	var a := anchor() + Vector3.UP
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, p + Vector3.UP, Layers.WORLD))
	if hit.is_empty():
		return p
	var dir := (p + Vector3.UP - a).normalized()
	var q: Vector3 = hit["position"] - dir * 1.1
	q.y = p.y
	return q


## Narrow way: walls close in on both sides of the commander (checked twice a second).
func _check_narrow() -> void:
	if leader_inside():
		_narrow = false
		return
	var yaw := travel_yaw
	var rider := leader.get_node_or_null("Rider") as Rider
	if leader.riding and rider and rider.horse:
		yaw = rider.horse.rotation.y
	var space := get_world_3d().direct_space_state
	var o := leader.global_position + Vector3.UP * 1.0
	var hits := 0
	for sgn in [-1.0, 1.0]:
		var side := Basis(Vector3.UP, yaw) * Vector3(sgn * 3.4, 0.0, 0.0)
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(o, o + side, Layers.WORLD)).is_empty():
			hits += 1
	_narrow = hits >= 1


## Cross country when nothing solid stands between (open fields, forest edges);
## along the trail and road network when walls or houses are in the way. The one
## implementation lives in Battlefield, shared with the soldiers' combat movement.
func route_to(from: Vector3, to: Vector3) -> PackedVector3Array:
	return Battlefield.route_to(from, to)


## The commander's footsteps from the one nearest `pos` (that `pos` can see) onward.
func crumbs_from(pos: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _crumbs.is_empty():
		return out
	var best := -1
	var best_d := 30.0
	var space := get_world_3d().direct_space_state
	for i in range(_crumbs.size() - 1, -1, -1):
		var d := Vector2(_crumbs[i].x - pos.x, _crumbs[i].z - pos.z).length()
		if d < best_d and LineOfSight.is_clear(space, pos + Vector3.UP, _crumbs[i] + Vector3.UP, [], Layers.WORLD):
			best_d = d
			best = i
			if d < 4.0:
				break
	if best < 0:
		return out
	for i in range(best, _crumbs.size()):
		out.append(_crumbs[i])
	return out


# --- horses -----------------------------------------------------------------------------------

func spawn_horses(center: Vector3, yaw: float) -> void:
	var want := mini(living().size(),int(state.army().get("horses", 4)))
	while horses.size() < want:
		var h: Horse = HORSE_SCENE.instantiate()
		h.name = "ArmyHorse%d" % (horses.size() + 1)
		add_child(h)
		h.water_level = world.water_level
		h.add_to_group("army_horses")
		# The company's horses are led, not ridden by the commander.
		var mp := h.get_node_or_null("MountPoint") as Interactable
		if mp:
			mp.enabled = false
		var pos := center + Basis(Vector3.UP, yaw) * Vector3(-6.0 - horses.size() * 2.4, 0.0, 4.0)
		var res := SpawnValidator.find(world, Vector2(pos.x, pos.z), pos.y + 3.0, 8.0)
		h.teleport((res["position"] if res["ok"] else pos) + Vector3.UP * 0.05, yaw)
		horses.append(h)
	_keep_mount_points_closed()


func _keep_mount_points_closed() -> void:
	for h in horses:
		var mp := h.get_node_or_null("MountPoint") as Interactable
		if mp:
			mp.enabled = false


func free_horses() -> Array[Horse]:
	var out: Array[Horse] = []
	for h in horses:
		if not is_instance_valid(h) or h.rider != null:
			continue
		var claimed := false
		for b in living():
			if b.horse == h:
				claimed = true
		if not claimed:
			out.append(h)
	return out


func _on_leader_mounted() -> void:
	_mounted_order = true
	if order != Order.FOLLOW:
		return
	# Each free horse goes to the nearest soldier on foot who can reach it (60 m).
	for h in free_horses():
		var best: SoldierBrain = null
		var best_d := 60.0
		for b in living():
			if b.horse != null or b.mode in [SoldierBrain.Mode.COMBAT, SoldierBrain.Mode.MOUNT, SoldierBrain.Mode.MOUNTED]:
				continue
			var d := b.avatar.global_position.distance_to(h.global_position)
			if d < best_d:
				best_d = d
				best = b
		if best:
			best.mount(h)


func _on_leader_dismounted() -> void:
	if not transitioning and not horses.is_empty() and order == Order.FOLLOW:
		_mount_transition(false)
		return
	_mounted_order = false
	for b in living():
		if b.mode == SoldierBrain.Mode.MOUNTED or b.mode == SoldierBrain.Mode.MOUNT:
			b.dismount()


# --- per frame ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if leader == null:
		return
	var movement := leader.velocity
	if leader.riding:
		var rider := leader.get_node("Rider") as Rider
		if rider.horse:
			movement = rider.horse.velocity
	if Vector2(movement.x, movement.z).length() > 0.5:
		travel_yaw = lerp_angle(travel_yaw, atan2(-movement.x, -movement.z), minf(1.0, delta * 5.0))
	var inside := leader_inside()
	if not inside:
		var lp := leader.global_position
		if _crumbs.is_empty() or Vector2(lp.x - _crumbs[_crumbs.size() - 1].x, lp.z - _crumbs[_crumbs.size() - 1].z).length() > CRUMB_STEP:
			if leader.is_on_floor() or leader.riding:
				_crumbs.append(lp)
				if _crumbs.size() > MAX_CRUMBS:
					_crumbs = _crumbs.slice(_crumbs.size() - MAX_CRUMBS)
		_last_outdoor = lp
		_last_outdoor_yaw = travel_yaw
	_narrow_t -= delta
	if _narrow_t <= 0.0:
		_narrow_t = 0.5
		_check_narrow()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	for b in living():
		var rec: Array = _recovery_watch.get(b.soldier_id,[b.avatar.global_position,0.0])
		var waiting:=order==Order.FOLLOW and not leader_inside() and b._flat(slot_position(b))>12.0 and b.mode not in [SoldierBrain.Mode.COMBAT,SoldierBrain.Mode.MOUNTED]
		rec[1]=float(rec[1])+1.0 if waiting and b.avatar.global_position.distance_to(rec[0])<0.6 else 0.0
		rec[0]=b.avatar.global_position
		_recovery_watch[b.soldier_id]=rec
	_emit_status()
	# Late mounting: soldiers who were fighting when he mounted take a free horse after.
	if _mounted_order and leader.riding and order == Order.FOLLOW:
		_on_leader_mounted()
	# Spare horses that stand idle far from the camera sleep (no animation or physics).
	var cam := get_viewport().get_camera_3d()
	for h in horses:
		if not is_instance_valid(h):
			continue
		var idle := h.rider == null and absf(h.speed) < 0.05 and h._come_target == Vector3.INF
		var claimed := false
		for b in living():
			if b.horse == h:
				claimed = true
		var far := cam == null or cam.global_position.distance_to(h.global_position) > 45.0
		h.set_dormant(idle and not claimed and far and not CampaignUtil.in_view(leader, h.global_position + Vector3.UP, 45.0))
	# Led horses trail the company when it moves on.
	if order == Order.FOLLOW:
		for h in free_horses():
			var hi := horses.find(h)
			var target := anchor() + Basis(Vector3.UP, leader.rotation.y) * Vector3(-5.0 - (hi % 2) * 3.5, 0.0, 10.0 + (hi / 2) * 4.0 + spacing * 3.0)
			if h.global_position.distance_to(target) > 18.0:
				h.come_to(target)
	# Clear the fallen once nobody is looking (never in front of the player).
	for i in range(corpses.size() - 1, -1, -1):
		var c: Array = corpses[i]
		var av: PlayerController = c[0]
		if not is_instance_valid(av):
			corpses.remove_at(i)
			continue
		if Combat.now() - float(c[1]) > 25.0 and not CampaignUtil.in_view(leader, av.global_position + Vector3.UP, 120.0):
			av.queue_free()
			corpses.remove_at(i)


func _mount_transition(mounting: bool) -> void:
	if transitioning:
		return
	# A holding company stays where it was posted: his mounting is his own business.
	if order != Order.FOLLOW and horses.is_empty():
		return
	transitioning = true
	var had_controls := leader.controls_enabled
	var previous_input: Variant = leader.input_override
	leader.controls_enabled = false
	leader.input_override = {}
	var director := get_parent() as CampaignDirector
	if director == null:
		leader.controls_enabled = had_controls
		transitioning = false
		return
	if mounting:
		await director._fade(1.0)
		if order == Order.FOLLOW:
			spawn_horses(anchor(), travel_yaw)
			var company := living()
			for i in company.size():
				var b: SoldierBrain = company[i]
				if i >= horses.size():
					break
				var h: Horse = horses[i]
				var spot := _raw_slot(b)
				var valid := SpawnValidator.find(world, Vector2(spot.x, spot.z), spot.y+3, 6)
				if valid.ok:
					h.teleport(valid.position+Vector3.UP*0.05, travel_yaw)
					b.avatar.teleport(h.global_transform*Vector3(-1.1,0,-0.3),travel_yaw)
					b.mount(h)
		await director._fade(0.0)
		var elapsed := 0.0
		while elapsed < 8.0:
			var ready := (leader.get_node("Rider") as Rider).is_riding()
			for b in living():
				if order == Order.FOLLOW and b.mode != SoldierBrain.Mode.MOUNTED:
					ready = false
			if ready:
				break
			await get_tree().process_frame
			elapsed += get_process_delta_time()
	else:
		_mounted_order = false
		for b in living():
			if b.horse and b.rig():
				b.paused = true
				b.rig().play_once("dismount")
		await get_tree().create_timer(0.8).timeout
		await director._fade(1.0)
		_on_leader_dismounted()
		for h in horses:
			h.queue_free()
		horses.clear()
		place_at(anchor() + Basis(Vector3.UP,travel_yaw)*Vector3(0,0,5.2),travel_yaw)
		set_paused(false)
		await director._fade(0.0)
	leader.input_override = previous_input
	leader.controls_enabled = had_controls
	transitioning = false


func regroup() -> void:
	_slot_cache.clear()
	set_follow(true)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay_upgrade.json"))
	for b in living():
		if b.horse:
			continue
		b._enter(SoldierBrain.Mode.FOLLOW)
		b._path = route_to(b.avatar.global_position, slot_position(b))
		b._path_i = 0
		var far := b.avatar.global_position.distance_to(anchor()) > float(cfg.get("army_recovery_distance",75.0))
		var target := slot_position(b)
		var trapped := float(_recovery_watch.get(b.soldier_id,[Vector3.ZERO,0.0])[1]) > 12.0
		if (far or trapped) and not CampaignUtil.in_view(leader,b.avatar.global_position+Vector3.UP,2000) and not CampaignUtil.in_view(leader,target+Vector3.UP,2000):
			var valid := SpawnValidator.find(world,Vector2(target.x,target.z),target.y+3,5)
			if valid.ok:
				b.avatar.teleport(valid.position+Vector3.UP*0.05,travel_yaw)
