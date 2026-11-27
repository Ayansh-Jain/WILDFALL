extends Node
## P06 movement regression: locomotion feel (start / stop / sprint ramp / reversals), analog
## and diagonal input, slopes, stairs, walls, seams and drops, the ControlLock prototype
## (PROPOSED contract C-08), scripted moves, death / respawn, mounted hand-off and combat
## locomotion. Geometry is built in isolated "labs" high above the world so nothing here
## touches the real terrain, saves or settings.

const LAB_Y := 420.0

var _nodes: Array[Node] = []
var _lab_count := 0


func run(t) -> void:
	var w: World = t.world
	var player: PlayerController = t.main.player
	var drv := PlayerDriver.new(player)
	var base := _flat_spot(w)
	if not t.check(base != Vector3.INF, "P06: found a flat spot for the lab origin"):
		return
	var saved_controls := player.controls_enabled
	player.controls_enabled = true

	# --- input contract ---------------------------------------------------------------------
	t.check(Settings.DEFAULT_BINDINGS.has("walk") and InputMap.has_action("walk"), "P06: the hold-to-walk action exists")

	# --- feel: start, stop, sprint ramp ------------------------------------------------------
	var lab := _lab(base, 0)
	await _settle(drv, player, lab)
	var s := await _record(drv, player, Vector2(0, 1), false, 60)
	t.check(s[2] < player.walk_speed * 0.8, "P06: running starts with a short ramp, not instantly", "%.2f m/s after 3 ticks" % s[2])
	var t90 := _first_at_least(s, player.walk_speed * 0.9)
	t.check(t90 >= 5 and t90 <= 24, "P06: reaches 90%% of run speed in 0.1-0.4 s", "%d ticks" % t90)
	t.check(absf(s[59] - player.walk_speed) < 0.3, "P06: run speed is walk_speed (%.1f)" % player.walk_speed, "%.2f" % s[59])

	var before := player.global_position
	var st := await _record(drv, player, Vector2.ZERO, false, 30)
	var stop_ticks := _first_at_most(st, 0.2)
	var stop_dist := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	t.check(stop_ticks >= 3 and stop_ticks <= 18, "P06: stops in 0.05-0.3 s", "%d ticks" % stop_ticks)
	t.check(stop_dist > 0.1 and stop_dist < 1.0, "P06: stopping distance is short but not a teleport", "%.2f m" % stop_dist)

	await _settle(drv, player, lab)
	var sp := await _record(drv, player, Vector2(0, 1), true, 90)
	var t95 := _first_at_least(sp, player.sprint_speed * 0.95)
	t.check(t95 > 0 and t95 <= 54, "P06: sprint reaches 95%% speed within 0.9 s", "%d ticks" % t95)
	t.check(sp[89] > player.walk_speed + 1.5, "P06: sprint is faster than run, unlimited (no stamina)", "%.2f m/s" % sp[89])
	t.check(sp[89] < player.sprint_speed + 0.3, "P06: sprint does not exceed sprint_speed", "%.2f m/s" % sp[89])

	# --- walk, analog and diagonal input -----------------------------------------------------
	await _settle(drv, player, lab)
	player.input_override = {"move": Vector2(0, 1), "walk": true}
	await drv.frames(60)
	var walk_v := player.ground_speed()
	t.check(absf(walk_v - player.slow_walk_speed) < 0.3, "P06: holding walk gives the deliberate walk speed", "%.2f vs %.2f" % [walk_v, player.slow_walk_speed])
	t.check(player.locomotion_state() == PlayerController.Loco.WALK, "P06: locomotion state is WALK", player.locomotion_name())

	await _settle(drv, player, lab)
	var half := await _record(drv, player, Vector2(0, 0.5), false, 60)
	t.check(absf(half[59] - player.walk_speed * 0.5) < 0.3, "P06: analog half-tilt moves at half speed", "%.2f" % half[59])

	await _settle(drv, player, lab)
	var diag := await _record(drv, player, Vector2(1, 1), false, 60)
	t.check(diag[59] < player.walk_speed * 1.03, "P06: a full diagonal is not faster than straight", "%.2f vs %.2f" % [diag[59], player.walk_speed])
	await _settle(drv, player, lab)
	var diag2 := await _record(drv, player, Vector2(0.7071, 0.7071), false, 60)
	t.check(absf(diag2[59] - player.walk_speed) < 0.3, "P06: a unit-length diagonal equals straight speed", "%.2f" % diag2[59])

	# --- rapid direction changes ---------------------------------------------------------------
	await _settle(drv, player, lab)
	var max_v := 0.0
	var changes := 0
	var last_loco := player.locomotion_state()
	var min_during_flip := 99.0
	for i in 90:
		var dir := 1.0 if (i / 6) % 2 == 0 else -1.0
		drv.set_input(Vector2(dir, 0.0))
		await drv.frames(1)
		var v := player.ground_speed()
		max_v = maxf(max_v, v)
		if i > 12 and i % 6 == 2:
			min_during_flip = minf(min_during_flip, v)
		if player.locomotion_state() != last_loco:
			changes += 1
			last_loco = player.locomotion_state()
	t.check(max_v <= player.walk_speed * 1.02, "P06: reversals never overshoot run speed", "%.2f m/s" % max_v)
	t.check(is_finite(player.global_position.x) and absf(player.global_position.y - lab.y) < 0.2, "P06: rapid reversals stay grounded and finite")
	t.check(changes <= 10, "P06: reversals do not thrash the locomotion state", "%d changes" % changes)
	drv.set_input()

	# --- backward gait latch (rig hysteresis) -------------------------------------------------
	var rig := (player.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig
	await _settle(drv, player, lab)
	drv.set_input(Vector2(0, -1))
	await drv.frames(45)
	t.check(rig._backing, "P06: walking backwards latches the backward gait")
	drv.set_input(Vector2(0, 1))
	await drv.frames(60)
	t.check(not rig._backing, "P06: walking forward releases the backward gait")
	drv.set_input()

	# --- combat locomotion --------------------------------------------------------------------
	await _settle(drv, player, lab)
	rig.draw_sword()
	await drv.frames(30)
	changes = 0
	last_loco = player.locomotion_state()
	drv.set_input(Vector2(0, 1))
	var combat_max := 0.0
	for i in 90:
		await drv.frames(1)
		combat_max = maxf(combat_max, player.ground_speed())
		if player.locomotion_state() != last_loco:
			changes += 1
			last_loco = player.locomotion_state()
	t.check(rig.sword_drawn, "P06: sword stays drawn while moving")
	t.check(absf(combat_max - player.walk_speed) < 0.4, "P06: movement with the sword drawn keeps run speed", "%.2f" % combat_max)
	t.check(changes <= 3, "P06: combat locomotion state is stable (IDLE->RUN)", "%d changes" % changes)
	drv.set_input()
	await drv.frames(20)

	# --- terrain: slopes ---------------------------------------------------------------------
	for deg in [15.0, 30.0, 40.0]:
		var sl := _lab(base, 1)
		_ramp(sl, deg, 12.0)
		await _settle(drv, player, sl)
		drv.set_input(Vector2(0, 1))
		var grounded := 0
		for i in 150:
			await drv.frames(1)
			if player.is_on_floor():
				grounded += 1
		var gain := player.global_position.y - sl.y
		t.check(gain > 6.0 * sin(deg_to_rad(deg)) * 0.6,"P06: climbs a %d degree slope" % int(deg), "gain %.2f m" % gain)
		t.check(grounded > 120, "P06: stays grounded on a %d degree slope" % int(deg), "%d/150 ticks" % grounded)
		drv.set_input()
		_clear()
	var steep := _lab(base, 1)
	_ramp(steep, 55.0, 12.0)
	await _settle(drv, player, steep)
	drv.set_input(Vector2(0, 1))
	await drv.frames(180)
	var steep_gain := player.global_position.y - steep.y
	t.check(steep_gain < 1.0, "P06: a 55 degree slope (above floor_max_angle) cannot be walked up", "gain %.2f m" % steep_gain)
	drv.set_input()
	_clear()

	# Downhill remains attached to the ground.
	var down := _lab(base, 1)
	_ramp(down, 25.0, 12.0)
	player.teleport(down + Vector3(0, 11.0 * sin(deg_to_rad(25.0)) + 0.05, -2.0 - 11.0 * cos(deg_to_rad(25.0))), 0.0)
	await drv.frames(20)
	player.set_look(PI, 0.0)
	drv.set_input(Vector2(0, 1))
	var airborne := 0
	for i in 90:
		await drv.frames(1)
		if not player.is_on_floor():
			airborne += 1
	t.check(airborne < 8, "P06: walking downhill keeps the feet on the ground", "%d airborne ticks" % airborne)
	drv.set_input()
	_clear()

	# --- terrain: stairs, ledge, wall, seam, drops -----------------------------------------------
	var stairs := _lab(base, 2)
	for i in 10:
		var h := 0.18 * (i + 1)
		_slab(stairs + Vector3(-2, 0, -2.0 - 0.3 * i), Vector3(4, h, 0.3), stairs.y + h)
	_slab(stairs + Vector3(-2, 0, -15.0), Vector3(4, 1.8, 10.0), stairs.y + 1.8)  # top landing, z -15..-5
	await _settle(drv, player, stairs)
	drv.set_input(Vector2(0, 1))
	await drv.frames(150)
	t.check(player.global_position.y - stairs.y > 1.7, "P06: climbs a 10-step staircase (0.18 m risers) onto the landing", "gain %.2f m" % (player.global_position.y - stairs.y))
	# Descend the same stairs: the feet must stay on the steps, not hop down them.
	player.set_look(PI, 0.0)
	var hop := 0
	var low_y := 99.0
	for i in 200:
		await drv.frames(1)
		if i > 20 and not player.is_on_floor() and player.global_position.y > stairs.y + 0.1:
			hop += 1
		low_y = minf(low_y, player.global_position.y)
	t.check(hop < 20, "P06: walking down the staircase stays mostly on the steps", "%d airborne ticks of 180" % hop)
	drv.set_input()
	_clear()

	var wall := _lab(base, 2)
	_slab(wall + Vector3(-5, 0, -6.0), Vector3(10, 4.0, 0.5), wall.y + 4.0)
	await _settle(drv, player, wall)
	drv.set_input(Vector2(0, 1), true)
	await drv.frames(150)
	t.check(player.global_position.z > wall.z - 5.8, "P06: a sprint into a wall does not pass or climb it", "z %.2f, wall face at %.2f" % [player.global_position.z - wall.z, -5.75])
	t.check(player.global_position.y - wall.y < 0.5, "P06: nor does it climb the wall", "%.2f m" % (player.global_position.y - wall.y))
	drv.set_input()
	_clear()

	# A wall met almost head-on (about 9 degrees off perpendicular): slide along it, never freeze.
	var slide_lab := _lab(base, 2)
	_slab(slide_lab + Vector3(-20, 0, -6.0), Vector3(40, 4.0, 0.5), slide_lab.y + 4.0)
	await _settle(drv, player, slide_lab)
	var x0 := player.global_position.x
	drv.set_input(Vector2(0.16, 1.0), true)
	await drv.frames(150)
	t.check(absf(player.global_position.x - x0) > 1.0, "P06: a near head-on wall is slid along, not stuck to", "moved %.2f m along the wall" % absf(player.global_position.x - x0))
	t.check(player.global_position.z > slide_lab.z - 5.8, "P06: ... while still being stopped by it")
	drv.set_input()
	_clear()

	var seam := _lab(base, 2)
	_slab(seam + Vector3(-10, 0, -5.0), Vector3(20, 0.2, 0.04), seam.y + 0.02)  # 2 cm lip across the route
	await _settle(drv, player, seam)
	drv.set_input(Vector2(0, 1))
	var slowest := 99.0
	for i in 120:
		await drv.frames(1)
		if i > 30:
			slowest = minf(slowest, player.ground_speed())
	t.check(slowest > player.walk_speed * 0.85, "P06: a 2 cm terrain seam does not slow the Commander", "min %.2f m/s" % slowest)
	drv.set_input()
	_clear()

	var drop_lab := _lab(base, 3)
	_clear_floor_part(drop_lab)
	_slab(drop_lab + Vector3(-5, 0, 0), Vector3(10, 1.0, 12.0), drop_lab.y)  # upper, z in [0, 12]
	_slab(drop_lab + Vector3(-5, 0, -30), Vector3(10, 1.0, 30.0), drop_lab.y - 0.3)  # 0.3 m lower
	player.teleport(drop_lab + Vector3(0, 0.05, 3), 0.0)
	await drv.frames(20)
	drv.set_input(Vector2(0, 1))
	var air_small := 0
	for i in 60:
		await drv.frames(1)
		if not player.is_on_floor():
			air_small += 1
	t.check(air_small < 4 and absf(player.global_position.y - (drop_lab.y - 0.3)) < 0.15, "P06: a 0.3 m drop is walked down, not fallen", "%d airborne ticks" % air_small)
	drv.set_input()
	_clear()

	var big := _lab(base, 3)
	_clear_floor_part(big)
	_slab(big + Vector3(-5, 0, 0), Vector3(10, 1.0, 12.0), big.y)
	_slab(big + Vector3(-5, 0, -30), Vector3(10, 1.0, 30.0), big.y - 3.0)  # 3 m cliff
	player.teleport(big + Vector3(0, 0.05, 3), 0.0)
	await drv.frames(20)
	drv.set_input(Vector2(0, 1))
	var fell := false
	for i in 90:
		await drv.frames(1)
		fell = fell or not player.is_on_floor()
	await drv.frames(40)
	drv.set_input()
	t.check(fell and player.is_on_floor() and absf(player.global_position.y - (big.y - 3.0)) < 0.3, "P06: a 3 m cliff is fallen from and landed on", "y %.2f" % (player.global_position.y - big.y))
	_clear()

	# --- control locks -------------------------------------------------------------------------
	var l := ControlLock.new()
	var changes_seen := []
	l.mask_changed.connect(func(n: int, o: int) -> void: changes_seen.append([n, o]))
	var a := l.acquire("cinematic", ControlLock.MOVE | ControlLock.CAMERA)
	var b := l.acquire("dialogue", ControlLock.MOVE)
	t.check(l.mask() == (ControlLock.MOVE | ControlLock.CAMERA), "P06 lock: mask is the OR of live tokens")
	l.release(a)
	t.check(l.blocks(ControlLock.MOVE) and not l.blocks(ControlLock.CAMERA), "P06 lock: releasing one of two MOVE locks does not unlock movement")
	l.release(a)
	l.release(9999)
	t.check(l.blocks(ControlLock.MOVE), "P06 lock: releasing an unknown or already-released token is a no-op")
	l.release(b)
	t.check(l.mask() == 0 and l.token_count() == 0, "P06 lock: releasing the last token frees everything")
	l.acquire("x", ControlLock.MOVE)
	l.acquire("x", ControlLock.COMBAT)
	l.acquire("y", ControlLock.INTERACT)
	l.release_all("x")
	t.check(l.mask() == ControlLock.INTERACT, "P06 lock: release_all(owner) frees only that owner's tokens")
	t.check(changes_seen.size() >= 4 and changes_seen[0][0] == (ControlLock.MOVE | ControlLock.CAMERA) and changes_seen[0][1] == 0, "P06 lock: mask_changed reports new and old masks")

	await _settle(drv, player, lab_again(base))
	var inp_dict := {"move": Vector2(0, 1)}
	player.input_override = inp_dict
	var tok := player.locks.acquire("test", ControlLock.MOVE)
	var p_locked := player.global_position
	await drv.frames(40)
	t.check(player.global_position.distance_to(p_locked) < 0.05, "P06 lock: a MOVE lock stops the Commander even with input held")
	t.check(player.locomotion_state() != PlayerController.Loco.RUN, "P06 lock: state is not RUN while locked", player.locomotion_name())
	var tok2 := player.locks.acquire("test2", ControlLock.MOVE)
	player.locks.release(tok)
	await drv.frames(20)
	t.check(player.global_position.distance_to(p_locked) < 0.05, "P06 lock: overlapping lock keeps the Commander still after the first releases")
	player.locks.release(tok2)
	await drv.frames(30)
	t.check(player.global_position.distance_to(p_locked) > 1.0, "P06 lock: movement resumes after the last release")

	# Pause mask and a real tree pause.
	await _settle(drv, player, lab_again(base))
	player.input_override = {"move": Vector2(0, 1)}
	var tp := player.locks.acquire("pause", ControlLock.PAUSE)
	await drv.frames(20)
	t.check(player.ground_speed() < 0.05, "P06 lock: the PAUSE mask freezes movement input")
	player.locks.release(tp)
	await drv.frames(20)
	t.check(player.ground_speed() > 1.0, "P06 lock: movement resumes when PAUSE is released")
	var p_pause := player.global_position
	get_tree().paused = true
	await drv.frames(20)
	get_tree().paused = false
	t.check(player.global_position.distance_to(p_pause) < 0.05, "P06: a paused tree does not move the Commander, and resumes cleanly")
	drv.set_input()

	# --- scripted movement ------------------------------------------------------------------------
	await _settle(drv, player, lab_again(base))
	var target := player.global_position + Vector3(4.0, 0.0, -5.0)
	var bad := player.locks.acquire("nomove", ControlLock.CAMERA)
	t.check(not player.locks.begin_scripted_move(target, 3.0, bad), "P06 scripted: refused for a token that does not hold MOVE")
	player.locks.release(bad)
	var st_tok := player.locks.acquire("quest", ControlLock.MOVE)
	player.input_override = {"move": Vector2(0, -1)}  # the player fights it: must be ignored
	t.check(player.locks.begin_scripted_move(target, 3.0, st_tok), "P06 scripted: accepted for a MOVE token")
	await drv.frames(240)
	var flat_d := Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length()
	t.check(flat_d < 0.6, "P06 scripted: the Commander walks to the target against held input", "%.2f m away" % flat_d)
	t.check(player.consume_scripted_arrival() and not player.consume_scripted_arrival(), "P06 scripted: arrival is reported exactly once")
	player.locks.release(st_tok)

	# Cancellation mid-walk returns control.
	await _settle(drv, player, lab_again(base))
	var far := player.global_position + Vector3(0, 0, -15)
	var ct := player.locks.acquire("quest2", ControlLock.MOVE)
	player.locks.begin_scripted_move(far, 3.5, ct)
	await drv.frames(40)
	var mid := player.global_position
	t.check(mid.distance_to(far) < 15.0 - 1.0, "P06 scripted: it is moving toward the target")
	player.locks.release(ct)
	await drv.frames(40)
	t.check(player.locks.active_scripted().is_empty(), "P06 scripted: releasing the token cancels the scripted move")
	t.check(player.ground_speed() < 0.3, "P06 scripted: the body stops after cancellation (no ghost walking)", "%.2f m/s" % player.ground_speed())
	player.input_override = {"move": Vector2(0, 1)}
	await drv.frames(30)
	t.check(player.ground_speed() > 2.0, "P06 scripted: player control returns after cancellation")
	drv.set_input()

	# --- death and respawn ------------------------------------------------------------------------
	await _settle(drv, player, lab_again(base))
	player.input_override = {"move": Vector2(0, 1)}
	player.on_defeated()
	await drv.frames(40)
	t.check(player.ground_speed() < 0.3 and player.locomotion_state() == PlayerController.Loco.DEAD, "P06: a defeated Commander ignores input", player.locomotion_name())
	player.on_respawned()
	await drv.frames(40)
	t.check(player.ground_speed() > 2.0 and player.locomotion_state() == PlayerController.Loco.RUN, "P06: movement returns after respawn", player.locomotion_name())
	drv.set_input()

	# --- mounted hand-off -----------------------------------------------------------------------
	await _settle(drv, player, lab_again(base))
	player.riding = true
	await drv.frames(5)
	t.check(player.locomotion_state() == PlayerController.Loco.MOUNTED, "P06: riding reports MOUNTED")
	var rp := player.global_position
	player.input_override = {"move": Vector2(0, 1)}
	await drv.frames(20)
	t.check(player.global_position.distance_to(rp) < 0.05, "P06: the controller does not move the body while a horse carries it")
	player.riding = false
	await drv.frames(30)
	t.check(player.ground_speed() > 2.0 and player.locomotion_state() != PlayerController.Loco.MOUNTED, "P06: control returns after dismount")
	drv.set_input()

	# Restore everything later suites rely on.
	if rig.sword_drawn:
		rig.sheath_sword()
		await drv.frames(40)
	_clear()
	player.locks.release_all("test")
	player.controls_enabled = saved_controls
	player.input_override = null
	player.teleport(base, 0.0)
	await drv.frames(30)


# --- helpers -------------------------------------------------------------------------------------

func lab_again(base: Vector3) -> Vector3:
	var o := Vector3(base.x, LAB_Y, base.z)
	_clear()
	_slab(o + Vector3(-30, 0, -30), Vector3(60, 1.0, 60), o.y)
	return o


func _lab(base: Vector3, k: int) -> Vector3:
	var o := Vector3(base.x + 100.0 * k, LAB_Y, base.z)
	_slab(o + Vector3(-20, 0, -30), Vector3(40, 1.0, 60), o.y)
	return o


func _clear_floor_part(_o: Vector3) -> void:
	# The drop labs build their own floors; remove the generic one created by _lab.
	if not _nodes.is_empty():
		_nodes.pop_back().queue_free()


## A slab whose top surface is at `top`, spanning `size` from `corner` (x, z extents), 1 m+ thick.
func _slab(corner: Vector3, size: Vector3, top: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := BoxShape3D.new()
	var thick := maxf(size.y, 0.5)
	shape.size = Vector3(size.x, thick, size.z)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(corner.x + size.x * 0.5, top - thick * 0.5, corner.z + size.z * 0.5)
	_nodes.append(body)


## A ramp rising toward -Z at `deg`, its low edge 2 m in front of the lab origin.
func _ramp(o: Vector3, deg: float, length: float) -> void:
	var a := deg_to_rad(deg)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 0.5, length)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	var dir := Vector3(0, sin(a), -cos(a))
	var normal := Vector3(0, cos(a), sin(a))
	var start := o + Vector3(0, 0, -2.0)
	body.global_transform = Transform3D(Basis(Vector3.RIGHT, a), start + dir * (length * 0.5) - normal * 0.25)
	_nodes.append(body)


func _clear() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()


func _settle(drv: PlayerDriver, player: PlayerController, origin: Vector3) -> void:
	drv.set_input()
	player.teleport(origin + Vector3(0, 0.05, 0), 0.0)
	await drv.frames(25)


## Holds an input for n physics ticks and returns the horizontal speed after every tick.
func _record(drv: PlayerDriver, player: PlayerController, move: Vector2, sprint: bool, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	drv.set_input(move, sprint)
	for i in n:
		await drv.frames(1)
		out.append(player.ground_speed())
	return out


func _first_at_least(a: PackedFloat32Array, v: float) -> int:
	for i in a.size():
		if a[i] >= v:
			return i + 1
	return -1


func _first_at_most(a: PackedFloat32Array, v: float) -> int:
	for i in a.size():
		if a[i] <= v:
			return i + 1
	return -1


func _flat_spot(w: World) -> Vector3:
	for c in w.layout.list("clearings"):
		if c["name"] == "North Meadow":
			var p := WorldLayout.v2(c["center"])
			var res := SpawnValidator.find(w, p, NAN, 10.0, {"max_slope_deg": 8.0})
			if res["ok"]:
				return res["position"]
	return Vector3.INF
