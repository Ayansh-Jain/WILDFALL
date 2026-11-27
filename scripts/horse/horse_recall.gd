class_name HorseRecall
extends Node
## The whistle (H). One persistent horse is called; nothing is computed until a valid
## whistle, and this node only processes while the horse is on its way.
##
## Near: the horse routes and trots over. Far: the screen fades and it is placed beside
## the Commander. Stuck on the way: it is moved, out of view, to open ground behind the
## camera and finishes the journey from there.

signal whistled
signal finished(arrived: bool)

const CONFIG := "res://data/gameplay_upgrade.json"
const WHISTLE := "res://assets/audio/commander_whistle.wav"
const STUCK_SECONDS := 4.0

var player: PlayerController
var horse: Horse
var water_level := 0.0
var far_distance := 100.0
## Answer the whistle key itself (scenes without Main's input handling).
var listen := false
var busy := false  ## fading / relocating
var _best := INF
var _stuck := 0.0
var _relocated := false
var _fade: ColorRect


func setup(p: PlayerController, h: Horse, water := 0.0) -> void:
	player = p
	horse = h
	water_level = water
	if FileAccess.file_exists(CONFIG):
		var cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if cfg is Dictionary:
			far_distance = float(cfg.get("horse_recall_distance", far_distance))
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if listen and event.is_action_pressed("call_horse") and not event.is_echo():
		get_viewport().set_input_as_handled()
		call_horse()


## Why a whistle would be ignored right now ("" = it will be answered).
func refusal() -> String:
	if horse == null or not is_instance_valid(horse) or player == null:
		return "no horse"
	if horse.is_ridden() or player.riding:
		return "riding"
	if busy or not player.controls_enabled or player.is_defeated or player.locks.blocks(ControlLock.MOVE | ControlLock.PAUSE):
		return "busy"
	if player.is_underground(player.eye_position()) or SafeSpot.roofed(_space(), player.global_position, 14.0, [player.get_rid()]):
		return "Your horse cannot reach you in here."
	return ""


func call_horse() -> void:
	var why := refusal()
	if why != "":
		if why.length() > 10:
			_toast(why)
		return
	_play_whistle()
	whistled.emit()
	_best = INF
	_stuck = 0.0
	_relocated = false
	if horse.global_position.distance_to(player.global_position) > far_distance:
		await _fade_to_side()
		return
	horse.come_to(_meet_point())
	set_process(true)
	_toast("You whistle for your horse.", 1.8)


func _process(delta: float) -> void:
	if horse == null or not is_instance_valid(horse) or horse.is_ridden() or not horse.is_recalled():
		set_process(false)
		finished.emit(horse != null and is_instance_valid(horse) and horse.global_position.distance_to(player.global_position) < 8.0)
		return
	var d := horse.global_position.distance_to(player.global_position)
	if d < _best - 1.0:
		_best = d
		_stuck = 0.0
		return
	_stuck += delta
	if _stuck < STUCK_SECONDS or d < 6.0 or busy:
		return
	_stuck = 0.0
	_best = INF
	if not _relocated and _relocate_unseen():
		_relocated = true
		horse.come_to(_meet_point())
	else:
		horse.stop_recall()
		set_process(false)
		_fade_to_side()


func _meet_point() -> Vector3:
	var right := player.global_basis.x
	for side: float in [3.0, -3.0, 4.2, -4.2]:
		var g := SafeSpot.standing(_space(), player.global_position + right * side, player.global_position + Vector3.UP, water_level, [player.get_rid()])
		if g != Vector3.INF:
			return g
	return player.global_position


## Moves the horse to open ground behind the camera, never where it can be seen.
func _relocate_unseen() -> bool:
	var camera := player.get_viewport().get_camera_3d()
	var look := -camera.global_basis.z if camera else player.forward()
	look.y = 0.0
	look = look.normalized() if look.length() > 0.01 else player.forward()
	if camera and camera.is_position_in_frustum(horse.global_position + Vector3.UP):
		return false  # it is on screen: never make it vanish
	var back := -look
	for dist: float in [18.0, 14.0, 24.0]:
		for ang: float in [0.0, 0.6, -0.6, 1.2, -1.2]:
			var p := player.global_position + back.rotated(Vector3.UP, ang) * dist
			var yaw := atan2(back.x, back.z)
			var g := SafeSpot.horse_stand(_space(), p, yaw, water_level, [player.get_rid(), horse.get_rid()])
			if g == Vector3.INF or (camera and camera.is_position_in_frustum(g + Vector3.UP)):
				continue
			horse.teleport(g + Vector3.UP * 0.05, yaw)
			return true
	return false


## Places the horse beside the Commander on open ground. False if there is none.
func place_beside() -> bool:
	var right := player.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var yaw := player.rotation.y
	var exclude: Array[RID] = [player.get_rid(), horse.get_rid()]
	for offset: Vector3 in [right * 3.2, -right * 3.2, right * 4.8, -right * 4.8, -player.forward() * 5.0, right * 6.5, -right * 6.5]:
		var g := SafeSpot.horse_stand(_space(), player.global_position + offset, yaw, water_level, exclude)
		if g == Vector3.INF or absf(g.y - player.global_position.y) > 2.5:
			continue
		var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, g + Vector3.UP, Layers.WORLD, exclude)
		if not _space().intersect_ray(ray).is_empty():
			continue
		horse.teleport(g + Vector3.UP * 0.05, yaw)
		return true
	return false


func _fade_to_side() -> void:
	busy = true
	var token := player.locks.acquire("horse_recall", ControlLock.MOVE | ControlLock.COMBAT | ControlLock.INTERACT)
	await _fade_alpha(1.0)
	var ok := is_instance_valid(horse) and not horse.is_ridden() and place_beside()
	await _fade_alpha(0.0)
	player.locks.release(token)
	busy = false
	_toast("Your horse finds you." if ok else "There is no room for your horse here.", 2.0)
	finished.emit(ok)


func _fade_alpha(to: float) -> void:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_fade)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", to, 0.45)
	await tween.finished


func _play_whistle() -> void:
	if not ResourceLoader.exists(WHISTLE):
		return
	var sound := AudioStreamPlayer.new()
	add_child(sound)
	sound.stream = load(WHISTLE)
	sound.volume_db = -15
	sound.finished.connect(sound.queue_free)
	sound.play()


func _space() -> PhysicsDirectSpaceState3D:
	return player.get_world_3d().direct_space_state


func _toast(text: String, seconds := 2.5) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("toast"):
		hud.toast(text, seconds)
