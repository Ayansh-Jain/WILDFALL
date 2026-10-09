class_name FormDefinition
extends Resource
## A playable body: movement profile, health, stamina and its abilities.
## The human form and every monster form are FormDefinitions.

@export var id := ""
@export var display_name := ""
@export var max_health := 100

@export_group("Movement")
@export var walk_speed := 4.6
@export var sprint_speed := 7.4
@export var jump_velocity := 5.6
@export var stand_height := 1.8
@export var stand_eye := 1.62
@export var capsule_radius := 0.35
@export var can_crouch := true
@export var fov_bonus := 0.0

@export_group("Stamina")
@export var max_stamina := 100.0
## Per second while sprinting.
@export var sprint_drain := 22.0
@export var stamina_regen := 16.0
## Seconds after spending stamina before it regenerates.
@export var regen_delay := 0.8
## After running dry, sprint is locked until stamina reaches this value.
@export var exhausted_threshold := 30.0

@export_group("Abilities")
## AbilityDefinition resources (untyped so .tres files stay hand-editable).
@export var abilities: Array = []


func ability_for_action(action: String) -> AbilityDefinition:
	for a in abilities:
		if a.input_action == action:
			return a
	return null


func ability(ability_id: String) -> AbilityDefinition:
	for a in abilities:
		if a.id == ability_id:
			return a
	return null
