class_name Combatant
extends Node
## Health and status effects for one player. No visuals and no rules: only the
## Combat authority changes these values; everything else reads them.

signal health_changed(current: int, maximum: int)

var player_id := -1
var max_health := 100
var health := 100
var invulnerable_until := -INF
var stunned_until := -INF
var slowed_until := -INF
var slow_factor := 1.0
## Shaken players cannot sprint (Roar).
var shaken_until := -INF
## Last time this player dealt or took damage (combat lockout for reverting).
var last_combat_time := -INF
## attacker id -> last time they damaged us (assists).
var recent_attackers := {}


func now() -> float:
	return Combat.now()


func is_alive() -> bool:
	return health > 0


func is_invulnerable() -> bool:
	return now() < invulnerable_until


func is_stunned() -> bool:
	return now() < stunned_until


func is_shaken() -> bool:
	return now() < shaken_until


func speed_multiplier() -> float:
	return slow_factor if now() < slowed_until else 1.0


func set_max_health(value: int, keep_ratio := true) -> void:
	var ratio := float(health) / maxf(1.0, float(max_health))
	max_health = value
	health = clampi(int(round(ratio * value)) if keep_ratio else value, 1 if health > 0 else 0, value)
	health_changed.emit(health, max_health)


func set_health(value: int) -> void:
	health = clampi(value, 0, max_health)
	health_changed.emit(health, max_health)


func reset_status() -> void:
	stunned_until = -INF
	slowed_until = -INF
	shaken_until = -INF
	recent_attackers.clear()
