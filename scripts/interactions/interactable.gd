class_name Interactable
extends Area3D
## Attach to anything the player can use. The player's Interactor finds these
## by overlap, checks view angle and line of sight, then shows `prompt_text`.

signal interacted(by: Node)

@export var prompt_text := "Use"
@export var input_action := "interact"
@export var enabled := true
## Point used for focus and line-of-sight checks, relative to this node.
@export var focus_offset := Vector3.ZERO
## Maximum angle (degrees) between the view direction and this object to focus it.
@export var max_view_angle := 40.0


func _ready() -> void:
	collision_layer = Layers.INTERACTABLE
	collision_mask = 0
	monitoring = false
	monitorable = true


func focus_point() -> Vector3:
	return global_transform * focus_offset


func can_interact(by: Node) -> bool:
	var owner := get_parent()
	return owner.can_interact(by) if owner and owner.has_method("can_interact") else enabled


func interact(by: Node) -> void:
	if enabled:
		interacted.emit(by)
