class_name CombatKit
extends RefCounted
## Helpers for Phase 2 tests: a flat arena on the North Meadow, controllable
## dummies (bots with their brain switched off), walls, and clean resets.

var t
var main: Node
var world: World
var local: PlayerController
var center := Vector3.ZERO
var spawned: Array[PlayerController] = []
var props: Array[Node] = []


func _init(runner) -> void:
	t = runner
	main = runner.main
	world = runner.world
	local = main.player
	var res := SpawnValidator.find(world, Vector2(150, -62), NAN, 10.0, {"max_slope_deg": 8.0})
	center = res["position"]


func frames(n: int) -> void:
	for i in n:
		await local.get_tree().physics_frame


func seconds(s: float) -> void:
	await frames(int(ceil(s * Engine.physics_ticks_per_second)))


## Puts an avatar on the ground at center + offset, facing yaw (radians).
func place(av: PlayerController, offset: Vector3, yaw := 0.0) -> void:
	var p := center + offset
	var y := world.terrain_height(p.x, p.z)
	av.teleport(Vector3(p.x, y + 0.05, p.z), yaw)


func face(av: PlayerController, target: Vector3) -> void:
	var d := target - av.global_position
	av.set_look(atan2(-d.x, -d.z), 0.0)


## A bot whose AI is disabled, so the test drives it.
func dummy(offset := Vector3.ZERO, role := SimBot.Role.WANDERER) -> PlayerController:
	var bot: PlayerController = main.spawn_bot(center + offset, role)
	bot.get_node("Brain").process_mode = Node.PROCESS_MODE_DISABLED
	bot.input_override = {}
	spawned.append(bot)
	place(bot, offset)
	return bot


func wall(offset: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	world.add_child(body)
	var p := center + offset
	body.global_position = Vector3(p.x, world.terrain_height(p.x, p.z) + size.y * 0.5 + offset.y, p.z)
	props.append(body)
	return body


## Makes `av` a revealed monster and waits for the transformation to finish.
func reveal(av: PlayerController) -> void:
	if not GameState.has_monster(av.player_id):
		GameState.grant_monster_for_testing(av.player_id)
	Combat.request_transform(av.player_id)
	await seconds(1.0)


func cleanup() -> void:
	for b in spawned:
		if is_instance_valid(b):
			main.bots.erase(b)
			b.queue_free()
	spawned.clear()
	for p in props:
		if is_instance_valid(p):
			p.queue_free()
	props.clear()
	GameState.reset_match(GameState.scroll_seed)
	local.input_override = null
	local.combatant.reset_status()
	local.combatant.set_health(local.combatant.max_health)
	local.combatant.invulnerable_until = -INF
	local.stamina = local.max_stamina
	local.exhausted = false
	await frames(3)


## Signature of an avatar's visible node tree (names + types), used to prove
## that a hidden monster looks exactly like everyone else.
static func tree_signature(n: Node, depth := 0) -> String:
	var nm := String(n.name)
	if depth == 0 or nm.begins_with("@"):
		nm = "auto"  # creation counters, not identity
	var s := "%s:%s(" % [n.get_class(), nm]
	for c in n.get_children():
		if c is Node3D or c is CanvasItem or c is AudioStreamPlayer3D:
			s += tree_signature(c, depth + 1) + ","
	return s + ")"


static func first_diff(a: String, b: String) -> String:
	for i in mini(a.length(), b.length()):
		if a[i] != b[i]:
			return "...%s  vs  ...%s" % [a.substr(maxi(0, i - 40), 90), b.substr(maxi(0, i - 40), 90)]
	return "" if a.length() == b.length() else "length %d vs %d" % [a.length(), b.length()]
