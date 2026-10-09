class_name PlayerAbilities
extends Node
## Turns the local player's input into requests to the Combat authority.
## Bots and tests call Combat directly; nothing here decides outcomes.

const ACTIONS := ["attack", "heavy_attack", "ability_1", "ability_2"]

@onready var player: PlayerController = get_parent()


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local or not player.controls_enabled or player.is_defeated:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_echo():
		return
	if event.is_action_pressed("transform"):
		trigger("transform")
		return
	for action in ACTIONS:
		if event.is_action_pressed(action):
			trigger(action)
			return


## Sends an action as if its key was pressed. Returns Combat's result.
func trigger(action: String) -> Dictionary:
	if action == "transform":
		if GameState.is_revealed(player.player_id):
			return Combat.request_revert(player.player_id)
		return Combat.request_transform(player.player_id)
	return Combat.request_action(player.player_id, action)
