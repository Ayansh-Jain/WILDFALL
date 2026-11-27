extends Node
## Phase 3 soldiers: the shared factory, the allied garrison at the kingdom's key
## positions (placement validity, coverage, spacing), guards ignoring the army-follow
## order, both factions hurting and killing each other through the one combat system,
## dead soldiers staying dead, and the distance sleep that keeps ~40 guards cheap.

var t
var main: Node
var c: CampaignDirector
var player: PlayerController
var world: World
var g: Garrison
var made: Array[PlayerController] = []


func run(runner) -> void:
	t = runner
	main = t.main
	c = main.campaign
	player = main.player
	world = t.world
	if not t.check(c != null and c.garrison != null, "the campaign builds a garrison"):
		return
	g = c.garrison
	c.speed = 0.05
	await _frames(30)
	_placement()
	_coverage()
	await _army_order_ignored()
	await _fighting()
	await _sleep()
	for av in made:
		if is_instance_valid(av):
			av.queue_free()


func _placement() -> void:
	var guards := g.living()
	t.check(guards.size() >= 28, "the kingdom has a garrison of at least 28 guards", "%d" % guards.size())
	var failed_posts: Array[String] = []
	for p in g.posts:
		if not p["ok"]:
			failed_posts.append("%s %s: %s" % [p["group"], p["want"], p["reason"]])
	t.check(failed_posts.size() <= 4, "nearly every listed post resolves to a valid spot", str(failed_posts))
	var space := world.get_world_3d().direct_space_state
	var min_gap := INF
	var bad := []
	for i in guards.size():
		var b := guards[i]
		var p := b.avatar.global_position
		var rig := b.rig()
		if rig == null or rig.faction != "kingdom" or rig.helm == null or rig.sword_count() != 1:
			bad.append("%s rig" % b.avatar.name)
		if b.role != "guard" or b.team != "kingdom" or b.army != null:
			bad.append("%s role" % b.avatar.name)
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = capsule
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.05)
		q.collision_mask = Layers.WORLD
		if not space.intersect_shape(q, 1).is_empty():
			bad.append("%s inside geometry" % b.avatar.name)
		if p.y < world.water_level + 0.3:
			bad.append("%s in water" % b.avatar.name)
		var hit := world.ground_ray(p.x, p.z, p.y + 1.0, 4.0)
		if hit.is_empty() or absf(float(hit["position"].y) - p.y) > 0.6:
			bad.append("%s floating" % b.avatar.name)
		if g.on_road(Vector2(p.x, p.z)):
			bad.append("%s on a road" % b.avatar.name)
		for z in g._zones:
			if KingdomPlan.zone_distance(z, Vector2(p.x, p.z)) < 0.0:
				bad.append("%s in %s" % [b.avatar.name, z["name"]])
		for j in range(i + 1, guards.size()):
			min_gap = minf(min_gap, CampaignUtil.flat_dist(p, guards[j].avatar.global_position))
	t.check(bad.is_empty(), "every guard is a helmeted one-sword kingdom soldier standing on valid dry ground, off roads, outside mission spaces", str(bad.slice(0, 6)))
	t.check(min_gap >= 2.9, "no two guards stand on top of each other", "closest %.1f m" % min_gap)
	var modes_ok := true
	for b in guards:
		modes_ok = modes_ok and b.mode in [SoldierBrain.Mode.HOLD, SoldierBrain.Mode.PATROL]
	t.check(modes_ok, "guards start stationary or on patrol (never following)")


func _coverage() -> void:
	var places := {
		"castle entrance": [Vector2(172, 150 + (world.get_node("Sites/Structures") as Sites).castle_gate_z), 30.0, 3],
		"castle corners": [Vector2(212, 150), 48.0, 4],
		"castle approach": [Vector2(136, 160), 14.0, 2],
		"watchtower": [Vector2(-200, 190), 12.0, 3],
		"great gate": [Vector2(-296, 70), 20.0, 3],
		"training ground": [Vector2(-160, -60), 40.0, 3],
		"north bridge": [Vector2(100, -150), 26.0, 2],
		"stone bridge": [Vector2(58, 172), 26.0, 2],
	}
	for k in places:
		var n := 0
		for b in g.living():
			var p := b.avatar.global_position
			if Vector2(p.x, p.z).distance_to(places[k][0]) <= float(places[k][1]):
				n += 1
		t.check(n >= int(places[k][2]), "guards stand at the %s" % k, "%d found" % n)
	var wall := 0
	for b in g.living():
		var p := Vector2(b.avatar.global_position.x, b.avatar.global_position.z)
		for tw in c.plan.towers:
			if p.distance_to(tw) < 12.0:
				wall += 1
				break
	t.check(wall >= 6, "guards watch the curtain wall's towers", "%d" % wall)
	var tower_guard := false
	for b in g.living():
		var p := b.avatar.global_position
		if Vector2(p.x, p.z).distance_to(Vector2(-200, 190)) < 6.0 and p.y > world.terrain_height(p.x, p.z) + 4.0:
			tower_guard = true
	t.check(tower_guard, "a sentry stands on the watchtower's roof")


func _army_order_ignored() -> void:
	var guards := g.living()
	var start := {}
	for b in guards:
		start[b] = b.avatar.global_position
	var was_following := c.army.is_following()
	if not was_following:
		c.army.toggle_follow()
	player.teleport(guards[0].avatar.global_position + Vector3(12, 0.2, 0))
	await _frames(240)
	var moved := 0.0
	var in_army := 0
	for b in guards:
		moved = maxf(moved, b.avatar.global_position.distance_to(start[b]))
		if c.army.brains.has(b.soldier_id) and c.army.brains[b.soldier_id] == b:
			in_army += 1
	var following := 0
	for b in guards:
		if b.mode in [SoldierBrain.Mode.FOLLOW, SoldierBrain.Mode.REGROUP]:
			following += 1
	t.check(following == 0 and in_army == 0, "guards are not on the army roster and never follow the commander", "%d following" % following)
	t.check(moved < 14.0, "guards do not leave their posts when the army is ordered to follow", "max drift %.1f m" % moved)
	t.check(c.army.living().size() == c.state.alive_count(), "the army still counts only the roster", "%d / %d" % [c.army.living().size(), c.state.alive_count()])
	if not was_following:
		c.army.toggle_follow()


func _fighting() -> void:
	var guard: SoldierBrain = null
	for b in g.living():
		if b.mode == SoldierBrain.Mode.HOLD and b.avatar.global_position.y < world.terrain_height(b.avatar.global_position.x, b.avatar.global_position.z) + 1.0:
			guard = b
			break
	if not t.check(guard != null, "found a ground-level guard to test"):
		return
	var post := guard.avatar.global_position
	player.teleport(post + Vector3(0, 0.2, 40))
	await _frames(30)
	var living_before := g.living().size()
	var foe := SoldierFactory.spawn(self, world, {"faction": "enemy", "variant": "spy", "name": "Test spy", "node_name": "TestSpy",
		"id": 9001, "pos": post + Vector3(5, 0, 0), "yaw": 0.0, "mode": SoldierBrain.Mode.PATROL, "role": "spy",
		"max_health": 60, "mission": 2})
	made.append(foe.avatar)
	await _frames(10)
	var a := foe.rig()
	t.check(a != null and a.faction == "enemy" and a.sword_count() == 1 and a.helm != null, "an enemy soldier from the same factory wears black and a helm")
	var same := guard.rig().model.find_child("Cloak", true, false) as MeshInstance3D
	var other := a.model.find_child("Cloak", true, false) as MeshInstance3D
	t.check(same.mesh == other.mesh and guard.rig().skeleton.get_bone_count() == a.skeleton.get_bone_count(), "both factions share the cape mesh and skeleton")
	# The enemy hurts the guard; the guard answers.
	var hp := guard.avatar.combatant.health
	Combat.apply_damage(guard.avatar.player_id, 10, foe.avatar.player_id, "test")
	await _frames(30)
	t.check(guard.avatar.combatant.health < hp, "an enemy can damage a guard")
	t.check(guard.mode == SoldierBrain.Mode.COMBAT and guard.target_id == foe.avatar.player_id, "the attacked guard fights back at its attacker")
	var foe_hp := foe.avatar.combatant.health
	Combat.apply_damage(foe.avatar.player_id, 10, guard.avatar.player_id, "test")
	t.check(foe.avatar.combatant.health < foe_hp, "a guard can damage an enemy")
	# Kill it: the guard stops attacking the dead and walks back to its post.
	Combat.apply_damage(foe.avatar.player_id, 999, guard.avatar.player_id, "test")
	await _frames(20)
	t.check(foe.mode == SoldierBrain.Mode.DEAD and foe.avatar.is_defeated, "the enemy dies")
	var swings := [0]
	var count := func(e: Dictionary) -> void:
		if e["target"] == foe.avatar.player_id:
			swings[0] += 1
	Combat.damage_dealt.connect(count)
	await _frames(240)
	Combat.damage_dealt.disconnect(count)
	t.check(swings[0] == 0 and guard.target_id < 0, "nobody keeps striking a dead soldier")
	t.check(guard.mode == SoldierBrain.Mode.HOLD, "the guard stands down after the fight", guard.mode_name())
	t.check(guard.avatar.global_position.distance_to(post) < 2.5, "the guard walks back to its post", "%.1f m away" % guard.avatar.global_position.distance_to(post))
	# An enemy kills a guard; the guard stays dead.
	var killer := SoldierFactory.spawn(self, world, {"faction": "enemy", "name": "Test raider", "node_name": "TestRaider",
		"id": 9002, "pos": post + Vector3(4, 0, 0), "yaw": 0.0, "mode": SoldierBrain.Mode.HOLD, "role": "raider", "max_health": 60})
	made.append(killer.avatar)
	await _frames(10)
	Combat.apply_damage(guard.avatar.player_id, 9999, killer.avatar.player_id, "test")
	await _frames(20)
	t.check(guard.mode == SoldierBrain.Mode.DEAD and guard.avatar.is_defeated, "an enemy can kill a guard")
	t.check(g.living().size() == living_before - 1, "the garrison count drops by exactly one", "%d -> %d" % [living_before, g.living().size()])
	await _frames(600)
	t.check(guard.mode == SoldierBrain.Mode.DEAD and g.living().size() == living_before - 1, "a dead guard does not come back")
	t.check(c.encounter.kills == 0, "guard and test-soldier deaths never count as mission kills")


func _sleep() -> void:
	var guards := g.living()
	player.teleport(guards[0].avatar.global_position + Vector3(0, 0.2, 10))
	await _frames(40)
	t.check(not g._asleep.has(guards[0]), "a guard beside the commander is awake")
	var far := 0
	for b in guards:
		if CampaignUtil.flat_dist(b.avatar.global_position, player.global_position) > 175.0:
			far += 1
	var wrongly := 0
	for b in guards:
		var near := CampaignUtil.flat_dist(b.avatar.global_position, player.global_position) < 140.0
		if g._asleep.has(b) and near:
			wrongly += 1
	t.check(g.asleep_count() >= far and far > 0 and wrongly == 0, "guards far from the commander sleep (no AI, animation or physics)", "%d asleep, %d beyond sleep range, %d near but asleep" % [g.asleep_count(), far, wrongly])
	var woke := 0
	for b in guards:
		if g._asleep.has(b):
			woke += 1
	player.teleport(g.living()[g.living().size() - 1].avatar.global_position + Vector3(0, 0.2, 8))
	await _frames(60)
	t.check(g.asleep_count() != woke or woke == 0, "moving across the kingdom wakes the guards that are now near", "%d -> %d" % [woke, g.asleep_count()])


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame
