class_name CaveStoryScroll
extends Node3D
## A readable cave clue kept separate from the secret identity granting scroll.

var inspected := false

@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	_build_visual()
	interactable.interacted.connect(_on_interacted)


func _build_visual() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.22, 0.2, 0.18)
	stone.roughness = 0.94
	var rock := MeshInstance3D.new()
	var plinth := BoxMesh.new()
	plinth.size = Vector3(0.78, 0.16, 0.58)
	plinth.material = stone
	rock.mesh = plinth
	rock.position.y = 0.08
	add_child(rock)

	var parchment := StandardMaterial3D.new()
	parchment.albedo_color = Color(0.55, 0.39, 0.22)
	parchment.roughness = 0.9
	var sheet := MeshInstance3D.new()
	var paper := PlaneMesh.new()
	paper.size = Vector2(0.42, 0.34)
	paper.material = parchment
	sheet.mesh = paper
	sheet.position = Vector3(0, 0.2, -0.015)
	sheet.rotation.x = deg_to_rad(-12.0)
	add_child(sheet)
	for x in [-0.23, 0.23]:
		var roll := MeshInstance3D.new()
		var tube := CylinderMesh.new()
		tube.top_radius = 0.035
		tube.bottom_radius = 0.035
		tube.height = 0.39
		tube.radial_segments = 8
		tube.material = parchment
		roll.mesh = tube
		roll.position = Vector3(x, 0.22, 0)
		roll.rotation.z = PI * 0.5
		add_child(roll)


func can_interact(by: Node) -> bool:
	return by is PlayerController and (by as PlayerController).combatant.is_alive()


func _on_interacted(by: Node) -> void:
	if not can_interact(by):
		return
	inspected = true
	var hud := (by as PlayerController).get_parent().get_node_or_null("HUD") as HUD
	if hud:
		hud.toast("The parchment bears a scorched crest and a warning written in ash.", 4.0)
