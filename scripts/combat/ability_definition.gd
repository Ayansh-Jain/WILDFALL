class_name AbilityDefinition
extends Resource
## One ability (attack, movement or utility), fully data-driven.
## Abilities live in data/abilities/*.tres and are listed by a FormDefinition.
## Combat (the authority) reads these values; visuals only react to events.

enum Kind { MELEE, LEAP, ROAR, DASH, WARD, FLAME }

@export var id := ""
@export var display_name := ""
@export var kind: Kind = Kind.MELEE
## Input action that triggers it: attack, heavy_attack, ability_1, ability_2.
@export var input_action := "attack"

@export_group("Timing")
@export var cooldown := 1.0
## Telegraph time before the effect resolves (0 = immediate).
@export var windup := 0.0
## Lockout after resolving before another ability can start.
@export var recovery := 0.2

@export_group("Hit")
@export var damage := 0
@export var hit_range := 2.5
## Full width of the hit cone in degrees (MELEE only).
@export_range(0.0, 360.0) var arc_degrees := 60.0
@export var max_targets := 1
@export var stun_on_hit := 0.0
@export var knockback := 0.0

@export_group("Interruption")
@export var interruptible := false
## Damage taken during the wind-up that cancels it.
@export var interrupt_damage := 15
@export var stagger_on_interrupt := 0.6

@export_group("Movement")
@export var move_distance := 0.0
@export var move_duration := 0.25
@export var leap_height := 0.0
@export var invulnerable_time := 0.0
@export var stamina_cost := 0.0

@export_group("Area")
## LEAP: landing hit radius. ROAR: pressure radius. WARD: effect radius.
@export var radius := 0.0
## ROAR: opponents within this radius are marked for the roaring player only.
@export var reveal_radius := 0.0
@export var mark_duration := 0.0
## ROAR: slow duration. WARD: stun duration.
@export var effect_duration := 0.0
## FLAME: active breath duration and interval between damage ticks.
@export var flame_duration := 1.2
@export var damage_interval := 0.4
@export var slow_factor := 1.0
## Uses per life; -1 = unlimited.
@export var charges := -1
## WARD: only affects players in revealed monster form.
@export var affects_revealed_only := false


@export_group("Sword choreography")
@export var animation_id := "sword_light"
@export var sword := "right"
@export var active_duration := 0.10
@export var hit_times: PackedFloat32Array = PackedFloat32Array()
@export var attack_class := "normal"
@export var combo_next := ""
@export var buffer_window := 0.25
@export var guard_break := false
@export var dodge_cancel := true
@export var audio_event := "sword_swing"
@export var visual_event := "blade_trail"
