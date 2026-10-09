class_name Scroll
extends Node3D
## The match's single magical scroll. Collecting it asks GameState (the
## authority) to grant the collector a hidden monster identity, then removes
## the scroll. The pickup effect plays at the scroll, which anyone nearby could
## witness, but nothing announces who took it.

signal collected(by: Node)

const PROPS_MAT := preload("res://assets/materials/props.tres")
const GLOW_MAT := preload("res://assets/materials/glow_magic.tres")

@export var bob_height := 0.08
@export var spin_speed := 0.6

var _t := 0.0
var _taken := false

@onready var visual: Node3D = $Visual
@onready var light: OmniLight3D = $Light
@onready var sparkles: CPUParticles3D = $Sparkles
@onready var hum: AudioStreamPlayer3D = $Hum
@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	_build_visual()
	interactable.interacted.connect(_on_interacted)
	var lib := AudioLib.get_instance()
	hum.stream = lib.get_stream("scroll_hum_loop")
	hum.play()


func _build_visual() -> void:
	var kit := MeshKit.new(5, 0.05)
	var roll := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.22, 0, 0))
	kit.add_cylinder(roll, 0.075, 0.075, 0.44, 10, Color(0.86, 0.78, 0.6))
	for x: float in [-0.28, 0.22]:
		var cap := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(x, 0, 0))
		kit.add_cylinder(cap, 0.095, 0.095, 0.06, 10, Color(0.72, 0.55, 0.22))
	kit.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-0.03, 0, 0)), 0.082, 0.082, 0.06, 10, Color(0.45, 0.08, 0.1))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(PROPS_MAT)
	visual.add_child(mi)
	var runes := MeshKit.new(6)
	for i in 10:
		var a := TAU * i / 10.0
		var p := Vector3(cos(a) * 0.42, -0.02, sin(a) * 0.42)
		runes.add_box(Transform3D(Basis(Vector3.UP, -a), p), Vector3(0.05, 0.012, 0.12), Color(1, 1, 1))
	var rm := MeshInstance3D.new()
	rm.name = "Runes"
	rm.mesh = runes.to_mesh(GLOW_MAT)
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(rm)


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	visual.position.y = sin(_t * 1.6) * bob_height
	visual.rotation.y += spin_speed * delta
	light.light_energy = 1.4 + 0.25 * sin(_t * 2.3)


func _on_interacted(by: Node) -> void:
	collect(by)


func collect(by: Node) -> bool:
	if _taken:
		return false
	var id: int = by.player_id if by is PlayerController else -1
	if not GameState.collect_scroll(id):
		return false
	_taken = true
	interactable.enabled = false
	interactable.set_deferred("monitorable", false)
	hum.stop()
	var pickup := AudioStreamPlayer3D.new()
	pickup.stream = AudioLib.get_instance().get_stream("scroll_pickup")
	pickup.unit_size = 6.0
	add_child(pickup)
	pickup.play()
	sparkles.initial_velocity_max = 3.0
	sparkles.restart()
	var tw := create_tween().set_parallel()
	tw.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(visual, "position:y", 0.8, 0.6)
	tw.tween_property(light, "light_energy", 0.0, 1.5)
	collected.emit(by)
	get_tree().create_timer(2.5).timeout.connect(queue_free)
	return true


func is_taken() -> bool:
	return _taken
