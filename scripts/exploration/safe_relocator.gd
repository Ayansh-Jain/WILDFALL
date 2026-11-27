class_name SafeRelocator
extends Node
## Puts the Commander somewhere only when that place can hold him (loading a save,
## respawning). Control is withheld while waiting and always returned.
##
## Streaming hook (Codex): set `provider` to an object with
##   prepare(pos: Vector3) -> void     start loading terrain and collision there
##   is_ready(pos: Vector3) -> bool    true once the ground there is solid
## Without a provider the ground is probed directly. The wait is bounded; if the place
## never becomes usable the nearest safe fallback point is used instead.

signal relocating(position: Vector3)
signal relocated(position: Vector3, used_fallback: bool)

const MAX_WAIT_FRAMES := 300

var world: World
var player: PlayerController
var provider: Object
## () -> Array[Vector2]: known good places, for fallback.
var fallbacks: Callable
var busy := false


func setup(p_world: World, p_player: PlayerController, p_fallbacks: Callable) -> void:
	world = p_world
	player = p_player
	fallbacks = p_fallbacks


## Where a person can stand for a requested position, or Vector3.INF.
## Keeps the exact spot when it is fine (indoors and upper floors included).
func resolve(pos: Vector3) -> Vector3:
	if not pos.is_finite() or not world.terrain_data.in_playable(pos.x, pos.z, 0.5):
		return Vector3.INF
	var space := world.get_world_3d().direct_space_state
	var exact := SafeSpot.standing(space, pos, Vector3.INF, world.water_level, [player.get_rid()])
	if exact != Vector3.INF and absf(exact.y - pos.y) < 1.5:
		return exact
	var near := SpawnValidator.find(world, Vector2(pos.x, pos.z), pos.y + 2.0, 12.0, {"edge_margin": 1.0, "min_above_water": 0.1})
	if near["ok"] and absf((near["position"] as Vector3).y - pos.y) < 12.0:
		return near["position"]
	return Vector3.INF


func fallback_for(pos: Vector3) -> Vector3:
	var points: Array = fallbacks.call() if fallbacks.is_valid() else []
	var from := Vector2(pos.x, pos.z) if pos.is_finite() else Vector2.ZERO
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(from) < b.distance_squared_to(from))
	for p: Vector2 in points:
		var res := SpawnValidator.find(world, p, world.terrain_height(p.x, p.y) + 3.0, 14.0, {"edge_margin": 1.0})
		if res["ok"]:
			return res["position"]
	return Vector3.INF


## Moves the Commander. Returns {ok, position, fallback}. ok = false leaves him where he was.
func relocate(pos: Vector3, yaw := NAN) -> Dictionary:
	if busy:
		return {"ok": false, "position": player.global_position, "fallback": false}
	busy = true
	var token := player.locks.acquire("relocate", ControlLock.MOVE | ControlLock.COMBAT | ControlLock.INTERACT | ControlLock.MOUNT)
	relocating.emit(pos)
	var ready := true
	if provider and pos.is_finite():
		provider.call("prepare", pos)
		var waited := 0
		while not bool(provider.call("is_ready", pos)) and waited < MAX_WAIT_FRAMES:
			waited += 1
			await get_tree().physics_frame
		ready = waited < MAX_WAIT_FRAMES
	await get_tree().physics_frame
	var spot := resolve(pos) if ready else Vector3.INF
	var used_fallback := spot == Vector3.INF
	if used_fallback:
		spot = fallback_for(pos)
	var ok := spot != Vector3.INF
	if ok:
		player.teleport(spot + Vector3.UP * 0.1, yaw)
	player.locks.release(token)
	busy = false
	relocated.emit(spot, used_fallback)
	return {"ok": ok, "position": spot if ok else player.global_position, "fallback": used_fallback}
