class_name WorldEncounter
extends Node3D
## A small authored enemy group in the open world (patrol, camp). It uses the same
## soldiers, brains and CombatDirector hand-off as the campaign, so the one-attacker /
## five-reactive rules apply unchanged.
##
## Actors exist only between activate() and deactivate(). What survives is the logical
## record Persist.entity("enc:<id>") = {dead: [indices], cleared: bool}.

signal engaged(id: String)
signal disengaged(id: String)
signal cleared(id: String)

const ENGAGE_DISTANCE := 17.0
const LEASH_DISTANCE := 48.0

var cfg := {}
var id := ""
var world: World
var player: PlayerController
var brains: Array = []  ## SoldierBrain or null (already dead), by authored index
var fighting := false


func setup(p_cfg: Dictionary, p_world: World, p_player: PlayerController) -> WorldEncounter:
	cfg = p_cfg
	id = String(cfg["id"])
	name = "Encounter_" + id
	world = p_world
	player = p_player
	return self


static func is_cleared(encounter_id: String) -> bool:
	return bool(Persist.entity("enc:" + encounter_id).get("cleared", false))


func center() -> Vector3:
	var p := LocationDB.xz(cfg, "center")
	return Vector3(p.x, world.terrain_height(p.x, p.y), p.y)


func is_active() -> bool:
	return not brains.is_empty()


func living() -> Array:
	return brains.filter(func(b) -> bool: return b != null and is_instance_valid(b) and b.is_alive())


func activate() -> void:
	if is_active() or is_cleared(id):
		return
	var dead := _dead()
	var middle := center()
	var list: Array = cfg.get("enemies", [])
	for i in list.size():
		if dead.has(i):
			brains.append(null)
			continue
		var e: Dictionary = list[i]
		var offset: Array = e.get("offset", [0, 0])
		var pos := middle + Vector3(float(offset[0]), 0, float(offset[1]))
		pos.y = world.terrain_height(pos.x, pos.z)
		var brain := SoldierFactory.spawn(self, world, {"faction": "enemy", "name": "Raider",
			"node_name": "Raider_%d" % i, "id": 9000 + i, "pos": pos, "yaw": float(i) * 2.1,
			"mode": SoldierBrain.Mode.HOLD, "max_health": int(e.get("health", 70)),
			"aggression": 0.4, "role": "raider", "mission": -1})
		brain.weapons_free = false
		brain.set_meta("pattern", String(e.get("pattern", "standard")))
		brain.died.connect(_on_died.bind(i))
		brains.append(brain)


func deactivate() -> void:
	if fighting:
		fighting = false
		disengaged.emit(id)
	for b in brains:
		if b != null and is_instance_valid(b) and is_instance_valid(b.avatar):
			b.avatar.queue_free()
	brains.clear()


## Called a few times a second while active.
func tick() -> void:
	if not is_active():
		return
	var alive := living()
	if alive.is_empty():
		return
	var from_center := Vector2(player.global_position.x - center().x, player.global_position.z - center().z).length()
	if player.is_defeated or from_center > LEASH_DISTANCE:
		stand_down()
		return
	if not fighting:
		for b in alive:
			var near: bool = b.avatar.global_position.distance_to(player.global_position) < ENGAGE_DISTANCE
			if near or b.avatar.combatant.health < b.avatar.combatant.max_health:
				engage()
				break


func engage() -> void:
	if fighting or living().is_empty():
		return
	fighting = true
	for b in living():
		b.weapons_free = true
		b.alert(player.player_id, true)
	engaged.emit(id)


## The Commander got away (or fell): the survivors go back to their posts.
func stand_down() -> void:
	if not fighting:
		return
	fighting = false
	for b in living():
		b.weapons_free = false
		b._set_target(-1)
		b.order = SoldierBrain.Mode.HOLD
		b._enter(SoldierBrain.Mode.HOLD)
	disengaged.emit(id)


func _dead() -> Array:
	return (Persist.entity("enc:" + id).get("dead", []) as Array).map(func(v: Variant) -> int: return int(v))


func _on_died(_brain: SoldierBrain, index: int) -> void:
	var dead := _dead()
	if not dead.has(index):
		dead.append(index)
	var done: bool = dead.size() >= (cfg.get("enemies", []) as Array).size()
	Persist.set_entity("enc:" + id, {"dead": dead, "cleared": done})
	if done:
		fighting = false
		cleared.emit(id)
