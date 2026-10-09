class_name ScoringRules
extends Resource
## Power score values. Prototype numbers, intentionally unbalanced.
## Edit data/scoring_rules.tres rather than code.

@export var base_score := 100
@export var min_score := 0
## Revealed monster defeats a player.
@export var prey_reward := 25
## Player defeated by a revealed monster.
@export var prey_penalty := 5
## Monster defeated (any form while holding monster powers).
@export var monster_defeat_penalty := 40
## Player who lands the final blow on a monster.
@export var monster_slayer_reward := 30
## Other players who damaged the monster within the assist window.
@export var monster_assist_reward := 15
@export var assist_window := 15.0
## A player hurt by a revealed monster who then survives and gets clear.
@export var escape_reward := 10
@export var escape_time := 15.0
@export var escape_distance := 20.0
