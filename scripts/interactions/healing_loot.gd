class_name HealingLoot
extends Node
## One healing drop roll per defeat. Ordinary and monster-form drops are tuned separately.

const PICKUP_SCENE := preload("res://scenes/interactables/healing_flask.tscn")

@export_range(0.0, 1.0) var enemy_drop_chance := 0.2
@export_range(0.0, 1.0) var boss_drop_chance := 0.35

var _rng := RandomNumberGenerator.new()
var _handled_defeats: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	Combat.player_defeated.connect(_on_player_defeated)


func _on_player_defeated(event: Dictionary) -> void:
	var key := String(event.get("defeat_id", ""))
	if key.is_empty() or _handled_defeats.has(key):
		return
	_handled_defeats[key] = true
	if int(event.get("killer", -1)) < 0:
		return
	var chance := boss_drop_chance if bool(event.get("victim_had_monster", false)) else enemy_drop_chance
	if _rng.randf() >= clampf(chance, 0.0, 1.0):
		return
	var victim := Combat.avatar(int(event.get("victim", -1)))
	if victim == null:
		return
	var pickup := PICKUP_SCENE.instantiate() as HealingPickup
	if pickup == null:
		return
	var world := get_parent().get_node_or_null("World")
	if world == null and get_tree().current_scene:
		world = get_tree().current_scene.get_node_or_null("World")
	if world == null:
		return
	world.add_child(pickup)
	pickup.global_position = victim.global_position + Vector3.UP * 0.25
