class_name HealingPickup
extends Node3D
## An enemy drop that restores health only when the player can benefit from it.

const PROPS_MAT := preload("res://assets/materials/props.tres")

@export var heal_amount := 35
@export var bob_height := 0.07

var _time := 0.0
var _taken := false
var _visual: Node3D
var _light: OmniLight3D
var _interactable: Interactable


func _ready() -> void:
	add_to_group("healing_pickup")
	_build_visual()
	_build_interaction()


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Flask"
	_visual.position.y = 0.46
	add_child(_visual)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.45, 0.11, 0.055, 0.9)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.32
	glass.metallic_specular = 0.36
	glass.emission_enabled = true
	glass.emission = Color(0.28, 0.06, 0.025)
	glass.emission_energy_multiplier = 0.45
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.48, 0.31, 0.12)
	metal.metallic = 0.72
	metal.roughness = 0.4
	var body := MeshInstance3D.new()
	var bottle := SphereMesh.new()
	bottle.radius = 0.15
	bottle.height = 0.3
	bottle.radial_segments = 12
	bottle.rings = 6
	bottle.material = glass
	body.mesh = bottle
	_visual.add_child(body)
	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.055
	neck_mesh.bottom_radius = 0.065
	neck_mesh.height = 0.12
	neck_mesh.radial_segments = 10
	neck_mesh.material = glass
	neck.position.y = 0.17
	neck.mesh = neck_mesh
	_visual.add_child(neck)
	var stopper := MeshInstance3D.new()
	var stopper_mesh := CylinderMesh.new()
	stopper_mesh.top_radius = 0.06
	stopper_mesh.bottom_radius = 0.06
	stopper_mesh.height = 0.045
	stopper_mesh.radial_segments = 8
	stopper_mesh.material = metal
	stopper.position.y = 0.25
	stopper.mesh = stopper_mesh
	_visual.add_child(stopper)
	_light = OmniLight3D.new()
	_light.name = "WarmGlow"
	_light.light_color = Color(1.0, 0.49, 0.24)
	_light.light_energy = 0.45
	_light.omni_range = 2.0
	_light.position.y = 0.5
	add_child(_light)


func _build_interaction() -> void:
	_interactable = Interactable.new()
	_interactable.name = "Interactable"
	_interactable.prompt_text = "Take Healing Flask"
	_interactable.max_view_angle = 55.0
	_interactable.focus_offset = Vector3.UP * 0.45
	add_child(_interactable)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	shape.shape = sphere
	_interactable.add_child(shape)
	_interactable.interacted.connect(_on_interacted)


func _process(delta: float) -> void:
	if _taken:
		return
	_time += delta
	_visual.position.y = 0.46 + sin(_time * 1.8) * bob_height
	_visual.rotation.y += delta * 0.45
	_light.light_energy = 0.42 + 0.04 * sin(_time * 2.1)


func can_interact(by: Node) -> bool:
	if _taken or not (by is PlayerController):
		return false
	var player := by as PlayerController
	return player.combatant.is_alive() and player.combatant.health < player.combatant.max_health


func _on_interacted(by: Node) -> void:
	if _taken or not (by is PlayerController):
		return
	var player := by as PlayerController
	var restored := Combat.heal_player(player.player_id, heal_amount)
	if restored <= 0:
		return
	_taken = true
	_interactable.enabled = false
	_interactable.set_deferred("monitorable", false)
	_light.visible = false
	var pickup_sound := AudioStreamPlayer3D.new()
	pickup_sound.stream = AudioLib.get_instance().get_stream("power_up")
	pickup_sound.volume_db = -8.0
	add_child(pickup_sound)
	pickup_sound.play()
	var hud := player.get_parent().get_node_or_null("HUD") as HUD
	if hud:
		hud.toast("Healing Flask  +%d health" % restored, 2.0)
	_visual.create_tween().tween_property(_visual, "scale", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	get_tree().create_timer(0.3).timeout.connect(queue_free)
