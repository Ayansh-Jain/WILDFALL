extends Node
## Mission-one boss, using the existing soldier body and central melee authority.
var encounter: Encounter
var campaign: CampaignDirector
var boss: SoldierBrain
var player: PlayerController
var started := false
var defeated := false
var duel := false
var approaching := false
var emerging := false
var emergence_target := Vector3.ZERO
var heavy: AbilityDefinition
var settings: Dictionary
var camera: Camera3D
var original_camera: Camera3D
var previous_input: Variant
var controls_before := true
var bar: ProgressBar
var title: Label
var ui: CanvasLayer
var elapsed := 0.0

func setup(e: Encounter) -> void:
	encounter=e
	campaign=e.get_parent() as CampaignDirector
	player=e.leader
	settings=JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay_upgrade.json"))["boss"]
	boss=SoldierFactory.spawn(self,e.world,{"faction":"enemy","id":11,"mission":1,"name":"The Black Giant","pos":e.tent_positions.back(),"exact":true,"max_health":int(settings.health)})
	boss.paused=true
	boss.set_physics_process(false)
	var av := boss.avatar
	av.visible=false
	av.set_physics_process(false)
	av.set_meta("duel_locked",true)
	av.set_meta("duel_opponent",player.player_id)
	av.collision.set_deferred("disabled",true)
	var scale_factor := float(settings.scale)
	boss.rig().scale=Vector3.ONE*scale_factor
	av.stand_height*=scale_factor
	av.crouch_height*=scale_factor
	av.capsule=av.capsule.duplicate()
	av.collision.shape=av.capsule
	av.capsule.radius*=scale_factor
	av._set_height(av.stand_height)
	av.walk_speed=float(settings.speed)
	av.sprint_speed=av.walk_speed
	heavy=AbilityDefinition.new()
	heavy.id="giant_heavy"
	heavy.damage=int(settings.damage)
	heavy.hit_range=float(settings.range)
	heavy.windup=float(settings.windup)
	heavy.recovery=float(settings.recovery)
	heavy.cooldown=float(settings.cooldown)
	heavy.arc_degrees=70
	heavy.max_targets=1
	ui=CanvasLayer.new()
	add_child(ui)
	bar=ProgressBar.new()
	ui.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.offset_left=-240
	bar.offset_right=240
	bar.offset_top=52
	bar.offset_bottom=70
	bar.max_value=float(settings.health)
	bar.value=bar.max_value
	bar.show_percentage=false
	var fill := StyleBoxFlat.new()
	fill.bg_color=Color(0.65,0.06,0.04)
	bar.add_theme_stylebox_override("fill",fill)
	title=Label.new()
	bar.add_child(title)
	title.position=Vector2(0,-25)
	title.size.x=480
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.text="THE BLACK GIANT"
	bar.hide()

func begin() -> void:
	if started:
		return
	started=true
	controls_before=player.controls_enabled
	previous_input=player.input_override
	player.controls_enabled=false
	player.look_when_locked=true
	player.input_override={}
	player.set_meta("duel_locked",true)
	campaign.army.set_paused(true)
	for b in campaign.army.living():
		b.weapons_free=false
		b.rig().play_once("jump_start")
	encounter.phase_text="A moment of victory..."
	await get_tree().create_timer(2.5*campaign.speed).timeout
	if player.is_defeated:
		return
	encounter.phase_text="Heavy footsteps from the black tent"
	campaign.play_transition_sound("giant_rumble")
	original_camera=get_viewport().get_camera_3d()
	camera=Camera3D.new()
	add_child(camera)
	camera.global_transform=original_camera.global_transform
	camera.fov=62
	camera.make_current()
	await _shot(boss.avatar.global_position+Vector3(7,2,9),boss.avatar.global_position+Vector3.UP,2.0,true)
	boss.avatar.visible=true
	boss.avatar.set_physics_process(true)
	boss.avatar.collision.disabled=false
	var curtain: Node3D=encounter.get_node("CampProps/GiantTent/Curtain")
	var tween:=create_tween()
	tween.tween_property(curtain,"scale:x",0.04,1.2*campaign.speed)
	emergence_target=encounter.tent_positions.back()+Vector3(0,0,5.5)
	emerging=true
	approaching=true
	await _shot(boss.avatar.global_position+Vector3(3,0.7,7),boss.avatar.global_position+Vector3.UP*0.6,2.0,true)
	await _shot(player.global_position+Vector3(5,3,5),player.global_position+Vector3.UP,2.0)
	await _shot(player.global_position+Vector3(7,7,9),(player.global_position+boss.avatar.global_position)*0.5+Vector3.UP,2.0)
	var wait := 0.0
	while (emerging or CampaignUtil.flat_dist(boss.avatar.global_position,player.global_position)>20.5) and wait<20.0:
		await get_tree().process_frame
		wait+=get_process_delta_time()
	approaching=false
	boss.avatar.input_override={}
	await _shot(boss.avatar.global_position+boss.avatar.forward()*4+Vector3.UP*3,boss.avatar.global_position+Vector3.UP*2.6,1.2)
	await campaign.story.play_dialogue([["Black Giant","You command these men? Face me alone. Let us see what your courage is worth."],["Commander","Stand back, soldiers. I accept your challenge."]])
	await _shot(original_camera.global_position,player.global_position+Vector3.UP*1.5,0.8)
	var toward := boss.avatar.global_position-player.global_position
	player.set_look(atan2(-toward.x,-toward.z),0.0)
	_restore_camera()
	player.remove_meta("duel_locked")
	boss.avatar.set_meta("duel_locked",false)
	player.input_override=previous_input
	player.controls_enabled=controls_before
	player.look_when_locked=false
	duel=true
	bar.show()
	encounter.phase_text="Defeat the Black Giant alone"

func _shot(at: Vector3, target: Vector3, seconds: float, shake := false) -> void:
	var from:=camera.global_transform
	var to:=Transform3D(Basis.IDENTITY,at).looking_at(target,Vector3.UP)
	var time:=0.0
	var duration:=maxf(0.05,seconds*campaign.speed)
	while time<duration:
		await get_tree().process_frame
		time+=get_process_delta_time()
		camera.global_transform=from.interpolate_with(to,smoothstep(0,1,minf(1,time/duration)))
		camera.h_offset=sin(time*31)*0.025 if shake else 0.0
		camera.v_offset=sin(time*23)*0.018 if shake else 0.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(boss) or not started or defeated:
		return
	elapsed+=delta
	if not boss.is_alive():
		defeated=true
		duel=false
		bar.hide()
		campaign.army.set_paused(false)
		encounter._check_complete()
		return
	if player.is_defeated:
		boss.avatar.input_override={}
		return
	if not duel and not approaching:
		return
	var av:=boss.avatar
	if emerging and CampaignUtil.flat_dist(av.global_position,emergence_target)<0.7:
		emerging=false
	var goal:=emergence_target if emerging else player.global_position
	var direction:=goal-av.global_position
	direction.y=0
	if not Combat.is_busy(av.player_id):
		av.rotation.y=lerp_angle(av.rotation.y,atan2(-direction.x,-direction.z),minf(1,delta*2.5))
	var distance:=direction.length()
	var stop:=0.6 if emerging else (20.0 if approaching else heavy.hit_range-0.4)
	av.input_override={"move":Vector2(0,1)} if distance>stop and not Combat.is_busy(av.player_id) else {}
	if duel and distance<=heavy.hit_range and not Combat.is_busy(av.player_id):
		Combat._request_ability(av.player_id,heavy)
	bar.value=move_toward(bar.value,float(av.combatant.health),delta*180)

func _restore_camera() -> void:
	if is_instance_valid(original_camera):
		original_camera.make_current()
	if is_instance_valid(camera):
		camera.queue_free()
	camera=null

func _exit_tree() -> void:
	_restore_camera()
	if is_instance_valid(player):
		player.remove_meta("duel_locked")
	if is_instance_valid(boss) and is_instance_valid(boss.avatar):
		boss.avatar.queue_free()
