class_name ViewModel
extends Node3D
## First-person arms for the local player. Human form: a gloved right hand
## holding a longsword and an open left hand (see FirstPersonArms), with a
## belt lantern lighting the ground ahead. Revealed: two clawed, ember-cracked
## forearms. Animates from movement and Combat events; never affects gameplay.

const PROPS_MAT := preload("res://assets/materials/props.tres")
const GLOW_EMBER := preload("res://assets/materials/glow_ember.tres")

const SWORD_REST_POS := Vector3(0.2, -0.255, -0.43)
const SWORD_REST_ROT := Vector3(-0.32, 0.12, 0.22)
const OPEN_REST_POS := Vector3(-0.23, -0.27, -0.4)
const OPEN_REST_ROT := Vector3(0.38, -0.3, 0.3)

## Sword swing keyframes: [time 0..1, position offset, rotation offset].
const SWING_KEYS := [
	[0.0, Vector3.ZERO, Vector3.ZERO],
	[0.28, Vector3(0.07, 0.09, 0.06), Vector3(0.4, 0.25, -0.95)],
	[0.5, Vector3(-0.3, -0.1, -0.12), Vector3(-0.55, -0.35, 1.45)],
	[0.62, Vector3(-0.34, -0.14, -0.08), Vector3(-0.6, -0.4, 1.6)],
	[1.0, Vector3.ZERO, Vector3.ZERO],
]

var human_root: Node3D
var beast_root: Node3D
var sword_hand: Node3D
var open_hand: Node3D
var claw_l: Node3D
var claw_r: Node3D
var lantern_light: OmniLight3D

var _bob := 0.0
var _time := 0.0
var _swing := 0.0       ## 0..1 progress of a sword swing
var _claw_swing := 0.0
var _heavy := 0.0       ## heavy wind-up amount
var _slam := 0.0
var _ward := 0.0
var _dip := 0.0
var _shake := 0.0
var _sprint := 0.0
var _sway := Vector2.ZERO
var _last_look := Vector2.ZERO
var _was_on_floor := true
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
	sword_hand = FirstPersonArms.sword_hand()
	human_root.add_child(sword_hand)
	open_hand = FirstPersonArms.open_hand()
	human_root.add_child(open_hand)
	# Belt lantern: warm light on the ground ahead, carried by the body, not the view.
	lantern_light = OmniLight3D.new()
	lantern_light.name = "BeltLantern"
	lantern_light.position = Vector3(-0.22, 0.95, -0.2)
	lantern_light.light_color = Color(1.0, 0.68, 0.4)
	lantern_light.light_energy = 0.55
	lantern_light.omni_range = 7.0
	lantern_light.omni_attenuation = 1.3
	player.add_child.call_deferred(lantern_light)


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


static func _swing_offsets(t: float) -> Array:
	for i in SWING_KEYS.size() - 1:
		var a: Array = SWING_KEYS[i]
		var b: Array = SWING_KEYS[i + 1]
		if t <= b[0]:
			var u := smoothstep(0.0, 1.0, (t - a[0]) / (b[0] - a[0]))
			return [(a[1] as Vector3).lerp(b[1], u), (a[2] as Vector3).lerp(b[2], u)]
	return [Vector3.ZERO, Vector3.ZERO]


func _process(delta: float) -> void:
	visible = not player.is_defeated and not player.noclip
	_time += delta
	_form_blend = move_toward(_form_blend, _target_form, delta * 1.8)
	human_root.visible = _form_blend < 0.5
	beast_root.visible = _form_blend >= 0.5
	var hide_human := clampf(_form_blend * 2.0, 0.0, 1.0)
	var show_beast := clampf((_form_blend - 0.5) * 2.0, 0.0, 1.0)

	# Shared motion: walk bob, landing dip, look sway, shake.
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var on_floor := player.is_on_floor()
	if on_floor and speed > 0.5:
		_bob += delta * speed * 1.75
	if on_floor and not _was_on_floor and player.velocity.y < -1.0:
		_dip = maxf(_dip, 0.5)
	_was_on_floor = on_floor
	_sprint = move_toward(_sprint, 1.0 if player.is_sprinting and speed > 5.0 else 0.0, delta * 4.0)
	var amp := clampf(speed / 4.6, 0.0, 1.6) * (1.0 + _sprint * 0.6)
	var bob := Vector3(cos(_bob) * 0.011, absf(sin(_bob)) * 0.017 - 0.008, 0.0) * amp
	var breathe := sin(_time * 1.4) * 0.0035
	var look := Vector2(player.rotation.y, player.head.rotation.x)
	var dl := look - _last_look
	_last_look = look
	_sway = _sway.lerp(Vector2(clampf(dl.x * 2.5, -0.07, 0.07), clampf(-dl.y * 2.5, -0.06, 0.06)), clampf(delta * 8.0, 0.0, 1.0))
	_dip = move_toward(_dip, 0.0, delta * 3.0)
	_shake = move_toward(_shake, 0.0, delta * 1.2)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.02
	position = bob + Vector3(_sway.x * 0.15, breathe - 0.1 * _dip, 0.0) + shake
	rotation = Vector3(_sway.y, _sway.x, sin(_bob) * 0.012 * amp)

	# Human arms
	human_root.position.y = -0.6 * hide_human
	var sw_pos := SWORD_REST_POS + Vector3(0.05, -0.08, 0.05) * _sprint
	var sw_rot := SWORD_REST_ROT + Vector3(0.6, 0.0, -0.4) * _sprint + Vector3(sin(_time * 1.4) * 0.012, 0, 0)
	if _swing > 0.0:
		_swing = minf(1.0, _swing + delta / 0.42)
		var off := _swing_offsets(_swing)
		sw_pos += off[0]
		sw_rot += off[1]
		if _swing >= 1.0:
			_swing = 0.0
	sword_hand.position = sword_hand.position.lerp(sw_pos, clampf(delta * 22.0, 0.0, 1.0))
	sword_hand.rotation = sword_hand.rotation.lerp(sw_rot, clampf(delta * 22.0, 0.0, 1.0))
	_ward = move_toward(_ward, 0.0, delta * 1.8)
	var wb := sin(_ward * PI)
	var pump := sin(_bob) * 0.03 * _sprint
	open_hand.position = OPEN_REST_POS + Vector3(0.1 * wb, 0.18 * wb + pump, -0.2 * wb) + Vector3(-0.03, -0.1, 0.06) * _sprint
	open_hand.rotation = OPEN_REST_ROT + Vector3(-0.5 * wb, 0.3 * wb, 0.0) + Vector3(0.4, 0.0, 0.2) * _sprint
	lantern_light.light_energy = 0.55 + wb * 3.0

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
