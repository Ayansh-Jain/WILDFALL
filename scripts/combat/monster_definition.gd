class_name MonsterDefinition
extends FormDefinition
## A monster form granted by the scroll. Adds the transformation rules.
## New monster types: add a .tres in data/monsters/ and a rig in CharacterRigs.

## Visual rig id used by AvatarVisual (see CharacterRigs.create).
@export var rig_id := "ember_beast"

@export_group("Transformation")
## Seconds of transformation animation; no abilities during it.
@export var transform_time := 0.9
## Once revealed, the monster must stay revealed at least this long.
@export var min_reveal_duration := 12.0
## After returning to human form, wait this long before transforming again.
@export var transform_cooldown := 20.0
## Cannot return to human form within this many seconds of dealing or taking damage.
@export var combat_lockout := 4.0
## Movement speed multiplier while the transformation plays.
@export var transform_move_scale := 0.5
