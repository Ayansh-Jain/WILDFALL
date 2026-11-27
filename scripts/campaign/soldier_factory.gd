class_name SoldierFactory
extends RefCounted
## The ONE place a campaign soldier is assembled: a bot PlayerController (the same
## body, combat, navigation and collision the commander uses) wearing the shared
## SoldierRig ("soldier:<faction>[:<variant>]" body style - one glTF body, skeleton,
## cape and animation set; only the faction palette and helm differ) with a
## SoldierBrain. The army, the mission encounters and the garrison all call this, so
## every soldier is configured the same way and nothing here is duplicated per faction.
##
## Config keys (all optional unless noted):
##   faction      "kingdom" (maroon) | "enemy" (black); default "kingdom"
##   variant      "" | "spy" | "captain"
##   name         display name
##   node_name    scene node name
##   id           roster id / spawn serial (seeds the brain's randomness)
##   pos, yaw     where to stand (snapped to valid ground within `snap`)
##   snap         search radius for valid ground (default 6)
##   max_health   maximum health
##   health       current health
##   mode         SoldierBrain.Mode the soldier starts in (default HOLD)
##   order        the mode it returns to after a fight (default = mode)
##   aggression, sight_range, alert_radius  brain tuning
##   role         "line" | "guard" | "spy" | "captain" | "raider" (informational + AI flavour)
##   mission      mission id this soldier belongs to (-1 = none)
##   hold_yaw     facing a stationary soldier returns to
##   exact        place at `pos` as given (the caller already validated it)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")


static func faction_team(faction: String) -> String:
	return "enemy" if faction == "enemy" else "kingdom"


static func spawn(parent: Node, world: World, cfg: Dictionary) -> SoldierBrain:
	var faction := String(cfg.get("faction", "kingdom"))
	var variant := String(cfg.get("variant", ""))
	var av: PlayerController = PLAYER_SCENE.instantiate()
	av.is_local = false
	av.is_bot = true
	av.display_name = String(cfg.get("name", "Soldier"))
	av.body_style = "soldier:" + faction + (":" + variant if variant != "" else "")
	av.name = String(cfg.get("node_name", "Soldier_%d" % int(cfg.get("id", 0))))
	av.get_node("Head/Camera3D").current = false
	var brain := SoldierBrain.new()
	brain.name = "Brain"
	brain.team = faction_team(faction)
	brain.soldier_id = int(cfg.get("id", 0))
	brain.role = String(cfg.get("role", "line"))
	brain.mission_id = int(cfg.get("mission", -1))
	var mode: int = int(cfg.get("mode", SoldierBrain.Mode.HOLD))
	brain.order = int(cfg.get("order", mode))
	if cfg.has("aggression"):
		brain.aggression = float(cfg["aggression"])
	if cfg.has("sight_range"):
		brain.sight_range = float(cfg["sight_range"])
	if cfg.has("alert_radius"):
		brain.alert_radius = float(cfg["alert_radius"])
	av.add_child(brain)
	parent.add_child(av)
	av.water_level = world.water_level
	var pos: Vector3 = cfg.get("pos", Vector3.ZERO)
	var yaw := float(cfg.get("yaw", 0.0))
	if bool(cfg.get("exact", false)):
		av.teleport(pos + Vector3.UP * 0.05, yaw)
	else:
		var res := SpawnValidator.find(world, Vector2(pos.x, pos.z), pos.y + 3.0, float(cfg.get("snap", 6.0)))
		av.teleport((res["position"] if res["ok"] else pos) + Vector3.UP * 0.05, yaw)
	Combat.set_team(av.player_id, brain.team)
	Combat.set_respawn_mode(av.player_id, Combat.Respawn.NEVER)
	if cfg.has("max_health") and int(cfg["max_health"]) != av.combatant.max_health:
		av.combatant.set_max_health(int(cfg["max_health"]), false)
	if cfg.has("health"):
		av.combatant.set_health(clampi(int(cfg["health"]), 1, av.combatant.max_health))
	brain.hold_pos = av.global_position
	if cfg.has("hold_yaw"):
		brain.hold_yaw = float(cfg["hold_yaw"])
	brain.mode = mode
	return brain
