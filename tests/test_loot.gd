extends Node


func run(t) -> void:
	var main: Node = t.main
	var player: PlayerController = main.player
	var loot: HealingLoot = main.healing_loot
	t.check(loot != null and is_instance_valid(loot), "the live match has a healing loot manager")
	if loot == null:
		return
	t.check(is_equal_approx(loot.enemy_drop_chance, 0.2), "ordinary enemy healing drops start at a 20% chance")
	t.check(loot.boss_drop_chance >= 0.0 and loot.boss_drop_chance <= 1.0, "boss healing drops have a separate configurable chance")
	loot.enemy_drop_chance = 1.0
	var before := get_tree().get_nodes_in_group("healing_pickup").size()
	var event := {"defeat_id": "loot-test:%d" % player.player_id, "victim": player.player_id,
		"killer": player.player_id, "victim_had_monster": false}
	loot._on_player_defeated(event)
	var pickups := get_tree().get_nodes_in_group("healing_pickup")
	t.check(pickups.size() == before + 1, "a successful configured loot roll spawns one flask")
	loot._on_player_defeated(event)
	pickups = get_tree().get_nodes_in_group("healing_pickup")
	t.check(pickups.size() == before + 1, "a repeated defeat event cannot duplicate the flask")
	if pickups.size() <= before:
		return
	var pickup := pickups.back() as HealingPickup
	player.combatant.set_health(player.combatant.max_health)
	t.check(not pickup.can_interact(player), "a full health player cannot waste the flask")
	player.combatant.set_health(player.combatant.max_health - 20)
	t.check(pickup.can_interact(player), "the flask becomes usable when the player is injured")
	pickup._on_interacted(player)
	t.check(player.combatant.health == player.combatant.max_health and pickup._taken,
		"the flask restores health without exceeding maximum")
	await t.physics_frames(2)
	player.combatant.set_health(player.combatant.max_health)
	loot.enemy_drop_chance = 0.2
