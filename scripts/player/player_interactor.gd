class_name PlayerInteractor
extends Area3D
## Picks the best Interactable near the player and triggers it on "interact".

signal focus_changed(target: Interactable)

@export var reach := 2.8

var focused: Interactable = null

@onready var player: PlayerController = get_parent()


func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.INTERACTABLE
	monitoring = true
	monitorable = false
	var shape := SphereShape3D.new()
	shape.radius = reach
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


func _physics_process(_delta: float) -> void:
	var best: Interactable = null
	var best_score := -INF
	var eye := player.eye_position()
	# The head's facing, not the camera's: the third-person camera sits behind and tilts down.
	var forward := -player.head.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	for area in get_overlapping_areas():
		var it := area as Interactable
		if it == null or not it.enabled:
			continue
		if it.has_method("can_interact") and not it.can_interact(player):
			continue
		var p := it.focus_point()
		var to := p - eye
		var dist := to.length()
		if dist > reach + 0.6:
			continue
		var angle := rad_to_deg(forward.angle_to(to))
		if angle > it.max_view_angle:
			continue
		if not LineOfSight.is_clear(space, eye, p, [player.get_rid()], Layers.WORLD):
			continue
		var score := -angle - dist * 4.0
		if score > best_score:
			best_score = score
			best = it
	if best != focused:
		focused = best
		focus_changed.emit(focused)


func _unhandled_input(event: InputEvent) -> void:
	if focused == null or (player.is_sitting and focused.input_action != "sit"):
		return
	if event.is_action_pressed(focused.input_action) and not event.is_echo():
		try_interact()


func try_interact() -> bool:
	if player.controls_enabled and not player.locks.blocks(ControlLock.INTERACT | ControlLock.PAUSE) and focused and focused.enabled:
		focused.interact(player)
		return true
	return false
