class_name StoryNPC
extends Node3D
## A non-combat story character: a rig (CivilianRig, or the realistic ReveRig for
## style "reve"), a talk prompt and a solid capsule so players and bots walk around it. Not registered with Combat or GameState,
## so it is never a combat target and carries no identity.

signal talked(by: Node)

var rig: CharacterRig
var talk: Interactable
var _turn_tween: Tween
var _last_pos := Vector3.ZERO


func setup(style: String, prompt: String, height := 1.7) -> StoryNPC:
	if style == "soldier":
		rig = SoldierRig.new()
	elif style == "reve":
		rig = ReveRig.new()
	elif style == "king":
		rig = KingRig.new()
	else:
		var civ := CivilianRig.new()
		civ.style = style
		rig = civ
	add_child(rig)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3 if height > 1.4 else 0.22
	capsule.height = height
	var cs := CollisionShape3D.new()
	cs.shape = capsule
	cs.position.y = height * 0.5
	body.add_child(cs)
	add_child(body)
	talk = Interactable.new()
	talk.name = "Talk"
	talk.prompt_text = prompt
	talk.max_view_angle = 50.0
	talk.position.y = height * 0.62
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	var tcs := CollisionShape3D.new()
	tcs.shape = sphere
	talk.add_child(tcs)
	talk.interacted.connect(func(by: Node) -> void: talked.emit(by))
	add_child(talk)
	return self


## Rotates the character to face a world position (yaw only).
func face(target: Vector3, seconds := 0.6) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() < 0.05:
		return
	var yaw := atan2(-d.x, -d.z)
	face_yaw(yaw, seconds)


func face_yaw(yaw: float, seconds := 0.6) -> void:
	if _turn_tween:
		_turn_tween.kill()
	var from := rotation.y
	var to := from + wrapf(yaw - from, -PI, PI)
	# A realistic body does not pivot on the spot: take a small step into the turn.
	if rig is ReveRig and absf(to - from) > deg_to_rad(25.0):
		(rig as ReveRig).gesture("turn_step")
	_turn_tween = create_tween()
	_turn_tween.tween_property(self, "rotation:y", to, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func say_gesture(seconds: float) -> void:
	rig.play("talk", seconds if rig is ReveRig else minf(seconds, 1.6))


func _physics_process(delta: float) -> void:
	# Movement speed for the rig's walk blend (story characters are moved by tweens).
	if delta > 0.0 and rig:
		var d := global_position - _last_pos
		rig.move_speed = lerpf(rig.move_speed, Vector2(d.x, d.z).length() / delta, 0.3) if _last_pos != Vector3.ZERO else 0.0
	_last_pos = global_position
