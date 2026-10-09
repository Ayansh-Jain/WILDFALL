class_name ViewModel
extends Node3D
## First-person hands for the local player: a gloved hand with a short sword
## and a lantern in human form (as in the reference's first-person views), and
## two clawed, ember-cracked forearms when revealed. Animates from Combat
## events; never affects gameplay.

const PROPS_MAT := preload("res://assets/materials/props.tres")
const GLOW_WARM := preload("res://assets/materials/glow_warm.tres")
const GLOW_EMBER := preload("res://assets/materials/glow_ember.tres")

var human_root: Node3D
var beast_root: Node3D
var sword_hand: Node3D
var lantern_hand: Node3D
var claw_l: Node3D
var claw_r: Node3D
var lantern_light: OmniLight3D

var _bob := 0.0
var _swing := 0.0       ## 0..1 progress of a sword swing
var _claw_swing := 0.0
var _heavy := 0.0       ## heavy wind-up amount
var _slam := 0.0
var _ward := 0.0
var _dip := 0.0
var _shake := 0.0
var _form_blend := 0.0  ## 0 = human hands, 1 = claws
var _target_form := 0.0

@onready var player: PlayerController = owner if owner is PlayerController else get_parent().get_parent().get_parent()


func _ready() -> void:
	if not player.is_local:
		visible = false
		set_process(false)
		return
	_build_human()
	_build_beast()
	beast_root.visible = false
	Combat.ability_started.connect(_on_started)
	Combat.ability_resolved.connect(_on_resolved)
	Combat.ability_interrupted.connect(func(id: int, _a: String) -> void:
		if id == player.player_id:
			_heavy = 0.0)
	Combat.damage_dealt.connect(func(e: Dictionary) -> void:
		if e["target"] == player.player_id:
			_dip = 1.0)
	Combat.transform_started.connect(func(id: int, _m: String, _d: float) -> void:
		if id == player.player_id:
			_target_form = 1.0)
	Combat.reverted_to_human.connect(func(id: int) -> void:
		if id == player.player_id:
			_target_form = 0.0)
	Combat.player_respawned.connect(func(id: int) -> void:
		if id == player.player_id:
			_target_form = 0.0
			_form_blend = 0.0)


func _mesh(parent: Node3D, kit: MeshKit, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _build_human() -> void:
	human_root = Node3D.new()
	add_child(human_root)
	sword_hand = Node3D.new()
	sword_hand.position = Vector3(0.27, -0.3, -0.45)
	human_root.add_child(sword_hand)
	var k := MeshKit.new(301, 0.05)
	k.add_cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.25), Vector3(0.05, -0.08, 0.32)), 0.05, 0.045, 0.33, 6, HumanRig.LEATHER)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(0.08, 0.09, 0.1), HumanRig.GLOVE)
	k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.02, -0.02)), Vector3(0.03, 0.12, 0.03), HumanRig.LEATHER_DARK)
	k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.08, -0.04)), Vector3(0.15, 0.022, 0.03), HumanRig.METAL * 0.7)
	k.add_box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.37, -0.15)), Vector3(0.04, 0.58, 0.012), HumanRig.METAL)
	_mesh(sword_hand, k, PROPS_MAT)
	lantern_hand = Node3D.new()
	lantern_hand.position = Vector3(-0.3, -0.33, -0.5)
	human_root.add_child(lantern_hand)
	k = MeshKit.new(302, 0.05)
	k.add_cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.3), Vector3(-0.04, -0.06, 0.3)), 0.05, 0.045, 0.32, 6, HumanRig.LEATHER)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(0.08, 0.09, 0.1), HumanRig.GLOVE)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.07, 0)), Vector3(0.012, 0.08, 0.012), HumanRig.METAL * 0.5)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.12, 0)), Vector3(0.09, 0.015, 0.09), HumanRig.LEATHER_DARK)
	k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, -0.24, 0)), Vector3(0.1, 0.02, 0.1), HumanRig.LEATHER_DARK)
	for cx in [-0.04, 0.04]:
		for cz in [-0.04, 0.04]:
			k.add_box(Transform3D(Basis.IDENTITY, Vector3(cx, -0.18, cz)), Vector3(0.012, 0.12, 0.012), HumanRig.LEATHER_DARK)
	_mesh(lantern_hand, k, PROPS_MAT)
	var flame := MeshKit.new(303)
	flame.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.4, 1)), Vector3(0, -0.18, 0)), 0.03, Color(1, 1, 1))
	_mesh(lantern_hand, flame, GLOW_WARM)
	lantern_light = OmniLight3D.new()
	lantern_light.position = Vector3(0, -0.15, 0)
	lantern_light.light_color = Color(1.0, 0.68, 0.38)
	lantern_light.light_energy = 0.75
	lantern_light.omni_range = 7.0
	lantern_light.omni_attenuation = 1.4
	lantern_hand.add_child(lantern_light)


func _build_beast() -> void:
	beast_root = Node3D.new()
	add_child(beast_root)
	for s in [-1.0, 1.0]:
		var hand := Node3D.new()
		hand.position = Vector3(0.36 * s, -0.42, -0.6)
		hand.scale = Vector3.ONE * 0.55
		beast_root.add_child(hand)
		var k := MeshKit.new(310 + int(s), 0.1)
		var g := MeshKit.new(312 + int(s))
		k.add_cylinder(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.35) * Basis(Vector3.BACK, -0.2 * s), Vector3(0.12 * s, -0.25, 0.75)), 0.2, 0.15, 0.8, 7, EmberBeastRig.CHAR)
		for i in 3:
			CharacterRig.spike(k, Vector3(0.13 * s, -0.08 - i * 0.02, 0.5 - i * 0.18), Vector3(0.7 * s, 0.6, 0.3), 0.16, 0.045, EmberBeastRig.CHAR2, 4)
		g.add_box(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + 0.35), Vector3(0.0, 0.0, 0.35)), Vector3(0.012, 0.35, 0.012), Color(1, 1, 1))
		k.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(0.24, 0.14, 0.24), EmberBeastRig.CHAR2)
		for c in 4:
			var x := (c - 1.5) * 0.06
			CharacterRig.spike(k, Vector3(x, 0.0, -0.1), Vector3(-0.1 * s, -0.25, -1.0), 0.34, 0.03, EmberBeastRig.CLAW, 4)
			CharacterRig.spike(g, Vector3(x - 0.03 * s, -0.08, -0.42), Vector3(-0.1 * s, -0.25, -1.0), 0.06, 0.014, Color(1, 0.7, 0.5), 4)
		_mesh(hand, k, PROPS_MAT)
		_mesh(hand, g, GLOW_EMBER)
		if s < 0:
			claw_l = hand
		else:
			claw_r = hand


func _on_started(id: int, ability_id: String, _windup: float) -> void:
	if id != player.player_id:
		return
	match ability_id:
		"sword_strike": _swing = 0.001
		"dodge": _dip = 0.8
		"ward": _ward = 1.0
		"claw": _claw_swing = 0.001
		"heavy_strike": _heavy = 0.001
		"pounce": _dip = 0.5
		"roar": _shake = 1.0


func _on_resolved(id: int, ability_id: String, _hits: Array) -> void:
	if id != player.player_id:
		return
	if ability_id == "heavy_strike":
		_heavy = 0.0
		_slam = 1.0


func _process(delta: float) -> void:
	visible = not player.is_defeated and not player.noclip
	_form_blend = move_toward(_form_blend, _target_form, delta * 1.8)
	human_root.visible = _form_blend < 0.5
	beast_root.visible = _form_blend >= 0.5
	var hide_human := clampf(_form_blend * 2.0, 0.0, 1.0)
	var show_beast := clampf((_form_blend - 0.5) * 2.0, 0.0, 1.0)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	if player.is_on_floor() and speed > 0.5:
		_bob += delta * speed * 1.7
	var bob := Vector3(cos(_bob) * 0.012, absf(sin(_bob)) * 0.018, 0) * clampf(speed / 4.6, 0.0, 1.5)
	_dip = move_toward(_dip, 0.0, delta * 3.0)
	_shake = move_toward(_shake, 0.0, delta * 1.2)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.02
	position = bob + Vector3(0, -0.12 * _dip, 0) + shake

	# Human hands
	human_root.position.y = -0.6 * hide_human
	if _swing > 0.0:
		_swing = minf(1.0, _swing + delta / 0.4)
		var w := sin(_swing * PI)
		sword_hand.rotation = Vector3(0.6 * w - 0.4 * _swing * w, 0, lerpf(0.9, -0.9, _swing) * w)
		sword_hand.position = Vector3(lerpf(0.27, -0.05, w * 0.6), -0.3 + 0.1 * w, -0.45 - 0.15 * w)
		if _swing >= 1.0:
			_swing = 0.0
	else:
		sword_hand.rotation = sword_hand.rotation.lerp(Vector3.ZERO, delta * 10.0)
		sword_hand.position = sword_hand.position.lerp(Vector3(0.27, -0.3, -0.45), delta * 10.0)
	_ward = move_toward(_ward, 0.0, delta * 1.8)
	var wb := sin(_ward * PI)
	lantern_hand.position = Vector3(-0.3 + 0.12 * wb, -0.33 + 0.2 * wb, -0.5 - 0.2 * wb)
	lantern_light.light_energy = 0.75 + wb * 3.0

	# Claws
	beast_root.position.y = -0.8 * (1.0 - show_beast)
	var lift := 0.35 * minf(_heavy * 2.5, 1.0)
	if _heavy > 0.0:
		_heavy = minf(1.0, _heavy + delta)
	_slam = move_toward(_slam, 0.0, delta * 3.0)
	for c in [claw_l, claw_r]:
		var s := -1.0 if c == claw_l else 1.0
		c.position = Vector3(0.48 * s, -0.46 + lift - 0.2 * _slam, -0.64 - 0.12 * _slam)
		c.rotation = Vector3(0.8 * lift - 0.6 * _slam, 0, 0)
	if _claw_swing > 0.0:
		_claw_swing = minf(1.0, _claw_swing + delta / 0.45)
		var w := sin(_claw_swing * PI)
		claw_r.position += Vector3(lerpf(0.25, -0.65, _claw_swing) * w, 0.12 * w, -0.2 * w)
		claw_r.rotation += Vector3(0.3 * w, 0, lerpf(0.9, -0.9, _claw_swing) * w)
		if _claw_swing >= 1.0:
			_claw_swing = 0.0
