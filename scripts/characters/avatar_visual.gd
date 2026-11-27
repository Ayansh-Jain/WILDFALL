class_name AvatarVisual
extends Node3D
## Third-person presentation of one avatar: the human body everyone sees, the
## revealed monster form, animation, effects and positional sound.
##
## Secret identity: every avatar has exactly the same nodes while hidden. The
## monster rig is only created when Combat announces a (public) transformation
## and is freed again on reverting, so nothing in the scene tree marks the
## scroll holder. For the local first-person player the bodies only cast
## shadows; the ViewModel draws hands/claws instead.

const SOUNDS := {
	"sword_strike": "sword_swing", "dodge": "dodge", "ward": "ward", "claw": "claw_swipe",
	"heavy_strike": "heavy_slam", "pounce": "pounce", "roar": "roar",
}

## The human body: the realistic commander for the local (story) player, the
## low-poly explorer for bots and other peers. The choice depends only on whether
## the avatar is this machine's player, never on the secret identity.
var human_rig: CharacterRig
var form_rig: CharacterRig  ## Revealed monster form, null while human/hidden.
## Set false to give the local player the low-poly explorer body (tests, low-end).
static var commander_body := true

var _danger_check := 0.0

var _sfx: AudioStreamPlayer3D
var _telegraph: MeshInstance3D
var _flame_fx: Node3D

@onready var player: PlayerController = get_parent()


static func create_rig(rig_id: String) -> CharacterRig:
	match rig_id:
		"ember_beast":
			return EmberBeastRig.new()
	return HumanRig.new()


func _ready() -> void:
	if player.body_style.begins_with("soldier"):
		var parts := player.body_style.split(":")
		var soldier := SoldierRig.new()
		soldier.faction = parts[1] if parts.size() > 1 else "kingdom"
		soldier.variant = parts[2] if parts.size() > 2 else ""
		human_rig = soldier
	else:
		human_rig = CommanderRig.new() if (commander_body and player.is_local and not player.is_bot) else HumanRig.new()
	human_rig.name = "Body"
	add_child(human_rig)
	human_rig.shadow_only = player.is_local
	_sfx = AudioStreamPlayer3D.new()
	_sfx.unit_size = 8.0
	_sfx.max_distance = 70.0
	add_child(_sfx)
	Combat.ability_started.connect(_on_started)
	Combat.ability_resolved.connect(_on_resolved)
	Combat.ability_phase.connect(_on_ability_phase)
	Combat.ability_interrupted.connect(_on_interrupted)
	Combat.damage_dealt.connect(_on_damage)
	Combat.attack_dodged.connect(_on_dodged)
	Combat.transform_started.connect(_on_transform)
	Combat.reverted_to_human.connect(_on_reverted)
	Combat.player_defeated.connect(_on_defeated)
	Combat.player_respawned.connect(_on_respawned)


func active_rig() -> CharacterRig:
	return form_rig if form_rig else human_rig


func _process(_delta: float) -> void:
	var rig := active_rig()
	rig.move_speed = Vector2(player.velocity.x, player.velocity.z).length()
	rig.grounded = player.is_on_floor() or player.is_swimming or player.riding
	rig.crouching = player.is_crouching
	if rig is CommanderRig:
		var c := rig as CommanderRig
		c.velocity = player.velocity
		c.swimming = player.is_swimming
		c.sprinting = player.is_sprinting
		c.stamina_ratio = player.stamina / maxf(player.max_stamina, 1.0)
		_danger_check -= _delta
		if _danger_check <= 0.0:
			_danger_check = 0.5
			c.danger = _danger_near()
	if form_rig is EmberBeastRig:
		if player.is_leaping() and rig.current_hold() != "leap":
			rig.hold("leap")
		elif not player.is_leaping() and rig.current_hold() == "leap":
			rig.release()


## A revealed monster (public knowledge) within 20 m makes the commander draw his sword.
func _danger_near() -> bool:
	for id in Combat.actor_ids():
		if id == player.player_id or not GameState.is_revealed(id):
			continue
		var av := Combat.avatar(id)
		if av and av.global_position.distance_to(player.global_position) < 20.0:
			return true
	return false


func _mine(id: int) -> bool:
	return id == player.player_id


func play_sound(sound: String, volume := 0.0, pitch := 1.0) -> void:
	var s := AudioLib.get_instance().get_stream(sound)
	if s == null:
		return
	_sfx.stream = s
	_sfx.volume_db = volume
	_sfx.pitch_scale = pitch * randf_range(0.95, 1.05)
	_sfx.play()


func _fx_parent() -> Node:
	return get_tree().current_scene if get_tree().current_scene else get_tree().root


func _local_shake(origin: Vector3, strength: float, radius: float) -> void:
	var local := Combat.avatar(GameState.local_player_id)
	if local and local.global_position.distance_to(origin) < radius:
		local.add_shake(strength * (1.0 - local.global_position.distance_to(origin) / radius))


func _hit_spark(target_id: int) -> void:
	var target := Combat.avatar(target_id)
	if target == null:
		return
	var impact := target.global_position + Vector3.UP * target.current_height() * 0.56
	Fx.burst(_fx_parent(), impact, Color(0.95, 0.82, 0.55), 10, 2.6, 0.035, 0.28, -1.8)
	play_sound("hit", -8.0)


func _attack_forward() -> Vector3:
	if player.riding:
		var rider := player.get_node_or_null("Rider") as Rider
		if rider and rider.horse:
			return rider.horse.forward()
	return player.forward()


# --- combat events ------------------------------------------------------------------------

func _on_started(id: int, ability_id: String, windup: float) -> void:
	if not _mine(id):
		return
	var rig := active_rig()
	match ability_id:
		"sword_strike":
			rig.play("attack", 0.45)
			play_sound("sword_swing", -6.0)
		"mounted_sword_strike":
			rig.play("mounted_attack", 0.62)
			play_sound("sword_swing", -4.0)
		"sword_finisher", "giant_heavy":
			rig.play("finisher", 0.92)
			play_sound("sword_swing", -1.0, 0.78)
		"dodge":
			rig.play("dodge", 0.4)
			play_sound("dodge", -8.0)
		"ward":
			rig.play("ward", 0.6)
			play_sound("ward", 0.0)
			var c := player.global_position + Vector3.UP * 1.1
			Fx.flash(_fx_parent(), c, Color(1.0, 0.85, 0.55), 5.0, 12.0, 0.5)
			Fx.ring(_fx_parent(), player.global_position + Vector3.UP * 0.2, Color(1.0, 0.85, 0.5, 0.8), 6.0, 0.5)
			Fx.burst(_fx_parent(), c, Color(1.0, 0.9, 0.6), 40, 6.0, 0.05, 0.6, 0.0)
		"claw":
			rig.play("claw", 0.5)
		"heavy_strike":
			rig.hold("flame_windup", windup)
			if rig is EmberBeastRig:
				(rig as EmberBeastRig).charge = 1.0
			var ab := GameState.current_form(id).ability(ability_id)
			_telegraph = Fx.telegraph(_fx_parent(), player.global_position, player.rotation.y, ab.hit_range + 0.4, ab.arc_degrees, windup)
			play_sound("roar", -2.0, 0.72)
		"pounce":
			rig.hold("pounce_windup", windup)
		"roar":
			rig.play("roar", 1.2)
			play_sound("roar", 6.0)


func _on_resolved(id: int, ability_id: String, hits: Array) -> void:
	if not _mine(id):
		return
	var rig := active_rig()
	var fwd := player.forward()
	match ability_id:
		"claw":
			var xf := Transform3D(Basis(Vector3.UP, player.rotation.y) * Basis(Vector3.BACK, 0.5), player.global_position + Vector3.UP * 1.5)
			Fx.slash(_fx_parent(), xf, Color(1.0, 0.25, 0.15), 2.4, 130.0, 0.35, 0.22)
			play_sound("claw_swipe", 0.0)
		"sword_strike":
			if not hits.is_empty():
				var xf := Transform3D(Basis(Vector3.UP, player.rotation.y) * Basis(Vector3.BACK, -0.4), player.global_position + Vector3.UP * 1.2)
				if not human_rig is CommanderRig:
					Fx.slash(_fx_parent(), xf, Color(0.85, 0.9, 1.0), 1.8, 105.0, 0.15, 0.18)
				_hit_spark(hits[0])
		"mounted_sword_strike":
			if not hits.is_empty():
				fwd = _attack_forward()
				var xf := Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)) * Basis(Vector3.BACK, -0.45), player.global_position + Vector3.UP * 1.55)
				if not human_rig is CommanderRig:
					Fx.slash(_fx_parent(), xf, Color(0.92, 0.82, 0.6), 2.1, 125.0, 0.18, 0.2)
				_hit_spark(hits[0])
		"sword_finisher", "giant_heavy":
			fwd = _attack_forward()
			var xf := Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)) * Basis(Vector3.BACK, -0.35), player.global_position + Vector3.UP * 1.25)
			if not human_rig is CommanderRig:
				Fx.slash(_fx_parent(), xf, Color(1.0, 0.86, 0.58), 2.4, 125.0, 0.22, 0.28)
			if not hits.is_empty():
				for target_id in hits:
					_hit_spark(target_id)
				play_sound("heavy_slam", -5.0)
		"pounce":
			rig.release()
			Fx.smoke(_fx_parent(), player.global_position + Vector3.UP * 0.3, 14, 1.4, 1.5, Color(0.2, 0.17, 0.15, 0.5))
			Fx.burst(_fx_parent(), player.global_position + Vector3.UP * 0.3, Color(1.0, 0.45, 0.15), 24, 4.0, 0.06, 0.6)
			play_sound("pounce", 2.0)
			_local_shake(player.global_position, 0.5, 10.0)
		"roar":
			var c := player.global_position + Vector3.UP * 0.4
			Fx.ring(_fx_parent(), c, Color(1.0, 0.35, 0.1, 0.9), 10.0, 0.7, 0.15)
			Fx.ring(_fx_parent(), c + Vector3.UP * 0.8, Color(0.9, 0.2, 0.1, 0.6), 7.0, 0.9, 0.1)
			Fx.burst(_fx_parent(), player.global_position + Vector3.UP * 2.0, Color(1.0, 0.4, 0.1), 50, 5.0, 0.05, 1.0, 0.5)
			_local_shake(c, 0.7, 16.0)


func _on_interrupted(id: int, _ability_id: String) -> void:
	if not _mine(id):
		return
	var rig := active_rig()
	rig.release()
	rig.play("stagger", 0.6)
	if rig is EmberBeastRig:
		(rig as EmberBeastRig).charge = 0.0
	_clear_flame_fx()
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()


func _on_ability_phase(id: int, ability_id: String, phase: String, duration: float) -> void:
	if not _mine(id) or ability_id != "heavy_strike":
		return
	var rig := active_rig()
	if phase == "active":
		if rig is EmberBeastRig:
			(rig as EmberBeastRig).charge = 0.4
			rig.hold("flame_breath", duration + 0.2)
		_start_flame_fx()
	else:
		_clear_flame_fx()
		rig.release()
		if rig is EmberBeastRig:
			(rig as EmberBeastRig).charge = 0.0
			rig.play("flame_recover", 0.5)


func _start_flame_fx() -> void:
	_clear_flame_fx()
	_flame_fx = Node3D.new()
	_flame_fx.name = "FireBreathFX"
	_flame_fx.position = Vector3(0.0, 2.12, -0.72)
	add_child(_flame_fx)
	var stream := CPUParticles3D.new()
	stream.name = "Flame"
	stream.amount = 70
	stream.lifetime = 0.34
	stream.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	stream.emission_sphere_radius = 0.12
	stream.direction = Vector3(0.0, 0.0, -1.0)
	stream.spread = 17.0
	stream.initial_velocity_min = 5.0
	stream.initial_velocity_max = 8.0
	stream.gravity = Vector3(0.0, -0.4, 0.0)
	stream.scale_amount_min = 0.5
	stream.scale_amount_max = 1.4
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.11
	flame_mesh.height = 0.22
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_color = Color(1.0, 0.3, 0.055, 0.8)
	flame_mesh.material = flame_mat
	stream.mesh = flame_mesh
	var colors := Gradient.new()
	colors.set_color(0, Color(1.0, 0.82, 0.28, 0.95))
	colors.add_point(0.42, Color(1.0, 0.25, 0.035, 0.82))
	colors.set_color(1, Color(0.45, 0.05, 0.01, 0.0))
	stream.color_ramp = colors
	_flame_fx.add_child(stream)
	stream.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.28, 0.07)
	light.light_energy = 1.0
	light.omni_range = 3.5
	_flame_fx.add_child(light)


func _clear_flame_fx() -> void:
	if _flame_fx and is_instance_valid(_flame_fx):
		_flame_fx.queue_free()
	_flame_fx = null


func _on_damage(e: Dictionary) -> void:
	if not _mine(e["target"]):
		return
	if player.is_sitting:
		player.cancel_sitting()
	var rig := active_rig()
	if rig.current_hold() == "":
		rig.play("hurt", 0.35)
	var beast := form_rig != null
	Fx.burst(_fx_parent(), e["position"], Color(1.0, 0.45, 0.1) if beast else Color(0.75, 0.12, 0.1), 16, 3.0, 0.05, 0.5)
	play_sound("hit", 0.0, 0.8 if beast else 1.0)


func _on_dodged(target_id: int, _source: int, _ability: String) -> void:
	if _mine(target_id):
		Fx.burst(_fx_parent(), player.global_position + Vector3.UP, Color(0.8, 0.85, 1.0), 10, 2.0, 0.04, 0.4, 0.0)


func _on_transform(id: int, monster_id: String, duration: float) -> void:
	if not _mine(id):
		return
	_clear_form()
	var def := GameState.monster_definition(monster_id)
	form_rig = create_rig(def.rig_id)
	form_rig.name = "RevealedForm"
	add_child(form_rig)
	form_rig.shadow_only = player.is_local
	var final_scale := form_rig.scale
	form_rig.scale = final_scale * 0.5
	form_rig.play("transform", duration + 0.4)
	var tw := form_rig.create_tween()
	tw.tween_property(form_rig, "scale", final_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var ht := human_rig.create_tween()
	ht.tween_property(human_rig, "scale", Vector3(1.2, 0.3, 1.2), duration * 0.35)
	ht.tween_callback(func() -> void: human_rig.visible = false)
	var c := player.global_position + Vector3.UP * 1.2
	Fx.burst(_fx_parent(), c, Color(1.0, 0.4, 0.1), 70, 6.0, 0.07, 1.2, 1.0)
	Fx.smoke(_fx_parent(), c, 22, 1.2, 2.2)
	Fx.ring(_fx_parent(), player.global_position + Vector3.UP * 0.15, Color(1.0, 0.35, 0.08, 0.9), 5.0, 0.8)
	Fx.flash(_fx_parent(), c, Color(1.0, 0.45, 0.15), 6.0, 14.0, duration)
	play_sound("transform", 6.0)
	_local_shake(c, 0.5, 18.0)


func _on_reverted(id: int) -> void:
	if not _mine(id):
		return
	if form_rig:
		Fx.smoke(_fx_parent(), player.global_position + Vector3.UP * 1.0, 18, 1.0, 1.8)
	_clear_form()
	human_rig.visible = true
	human_rig.scale = Vector3.ONE


func _on_defeated(e: Dictionary) -> void:
	if not _mine(e["victim"]):
		return
	active_rig().hold("defeat")
	play_sound("defeat", 0.0)


func _on_respawned(id: int) -> void:
	if not _mine(id):
		return
	_clear_form()
	human_rig.visible = true
	human_rig.scale = Vector3.ONE
	human_rig.release()


func _clear_form() -> void:
	if form_rig and is_instance_valid(form_rig):
		remove_child(form_rig)
		form_rig.queue_free()
	form_rig = null
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
