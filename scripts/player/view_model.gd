class_name ViewModel
extends Node3D
## Owner of the local player's belt lantern light. The game is third person only:
## the first-person hands, sword and claws that used to live here were removed
## together with the first-person camera mode, and nothing is ever drawn by this
## node (it stays hidden). The light is parented to the player (CommanderRig
## carries it at the belt lantern) and flares briefly when a ward is raised.

var lantern_light: OmniLight3D
var _ward := 0.0

@onready var player: PlayerController = owner if owner is PlayerController else get_parent().get_parent().get_parent()


func _ready() -> void:
	visible = false
	if not player.is_local:
		set_process(false)
		return
	# Belt lantern: warm light on the ground ahead, carried by the body.
	lantern_light = OmniLight3D.new()
	lantern_light.name = "BeltLantern"
	lantern_light.position = Vector3(-0.22, 0.95, -0.2)
	lantern_light.light_color = Color(1.0, 0.68, 0.4)
	# Stronger lantern pool so the player can read the ground and nearby objects
	# clearly during the night sections.
	lantern_light.light_energy = 1.8
	lantern_light.omni_range = 12.0
	lantern_light.omni_attenuation = 1.15
	player.add_child.call_deferred(lantern_light)
	Combat.ability_started.connect(func(id: int, ability_id: String, _w: float) -> void:
		if id == player.player_id and ability_id == "ward":
			_ward = 1.0)


func _process(delta: float) -> void:
	visible = false
	_ward = move_toward(_ward, 0.0, delta * 1.8)
	if lantern_light:
		lantern_light.light_energy = 1.8 + sin(_ward * PI) * 3.0
