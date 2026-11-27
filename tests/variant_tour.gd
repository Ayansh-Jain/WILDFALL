extends Node
## Visual check of the commander and the two soldier variants built from his model:
## line-up from front / side / rear, helmet close-ups (front, three-quarter, side, rear,
## below), and each variant walking, sprinting, attacking, dodging, hit, dying and
## riding. Prints helmet-fit numbers for every animation state.
##   godot --path . res://tests/variant_tour.tscn -- --out=<dir> [--only=a,b]

const MAIN_SCENE := preload("res://scenes/main/main.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var out_dir := "user://variant_tour"
var only := ""
var main: Node
var world: World
var player: PlayerController
var photo: Camera3D
var ally: PlayerController
var spy: PlayerController
var spot := Vector3.ZERO


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--only="):
			only = arg.substr(7)
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = MAIN_SCENE.instantiate()
	main.auto_capture_mouse = false
	main.spawn_bots = false
	main.campaign_persist = false
	add_child(main)
	await main.ready_for_play
	world = main.world
	player = main.player
	var cycle := world.get_node("DayNightCycle") as DayNightCycle
	cycle.start_automatically = false
	cycle.advance_to_hour(13.0)
	main.hud.visible = false
	main.combat_hud.visible = false
	main.campaign.chud.visible = false
	photo = Camera3D.new()
	photo.fov = 40.0
	add_child(photo)
	var res := SpawnValidator.find(world, Vector2(-232, 100), NAN, 8.0)
	spot = res["position"]
	player.teleport(spot + Vector3.UP * 0.1, 0.0)
	ally = _make("soldier:kingdom", spot + Vector3(1.6, 0.1, 0))
	spy = _make("soldier:enemy:spy", spot + Vector3(3.2, 0.1, 0))
	await _frames(90)

	if _want("lineup"):
		var mid := spot + Vector3(1.6, 0, 0)
		await _shot_from(mid + Vector3(0, 1.3, -6.5), mid + Vector3(0, 1.0, 0), "lineup_front")
		await _shot_from(mid + Vector3(-6.5, 1.3, 0.5), mid + Vector3(0, 1.0, 0), "lineup_side")
		await _shot_from(mid + Vector3(0, 1.3, 6.5), mid + Vector3(0, 1.0, 0), "lineup_rear")
	if _want("helm"):
		for who in [["ally", ally], ["spy", spy], ["commander", player]]:
			var av: PlayerController = who[1]
			var head := _rig(av).bone_socket("head").global_position + Vector3.UP * 0.06
			var f := -av.global_transform.basis.z
			var r := av.global_transform.basis.x
			await _shot_from(head + f * 0.95, head, "helm_%s_front" % who[0])
			await _shot_from(head + (f + r).normalized() * 0.95, head, "helm_%s_34" % who[0])
			await _shot_from(head + r * 0.95, head, "helm_%s_side" % who[0])
			await _shot_from(head - f * 0.95, head, "helm_%s_rear" % who[0])
			await _shot_from(head + f * 0.6 - Vector3.UP * 0.45, head, "helm_%s_below" % who[0])
	if _want("motion"):
		for who in [["ally", ally], ["spy", spy]]:
			var av: PlayerController = who[1]
			av.teleport(spot + Vector3(-6, 0.1, 10), 0.0)
			await _frames(20)
			await _move(av, Vector2(0, 1), false, 70)
			await _side(av, "%s_walk" % who[0])
			await _move(av, Vector2(0, 1), true, 60)
			await _side(av, "%s_sprint" % who[0])
			av.input_override = {"move": Vector2.ZERO}
			await _frames(40)
			Combat.request_action(av.player_id, "attack")
			await _frames(14)
			await _side(av, "%s_attack" % who[0])
			await _frames(60)
			Combat.request_action(av.player_id, "ability_1")
			await _frames(10)
			await _side(av, "%s_dodge" % who[0])
			await _frames(60)
			Combat.apply_damage(av.player_id, 5, -1, "test")
			await _frames(8)
			await _side(av, "%s_hit" % who[0])
			await _frames(60)
	if _want("ride"):
		var hs: Array = main.campaign.army.horses
		if hs.size() > 0:
			var h: Horse = hs[0]
			h.teleport(spot + Vector3(-4, 0.1, 4), 0.0)
			ally.teleport(spot + Vector3(-5, 0.1, 4.4), 0.0)
			var brain := SoldierBrain.new()
			brain.name = "Brain"
			brain.team = "kingdom"
			ally.add_child(brain)
			await _frames(5)
			Combat.set_team(spy.player_id, "kingdom")  # no fight next to the photo
			brain.mount(h)
			for k in 8:
				await _frames(25)
				print("[ride] mode %s pos %s horse %s rider %s" % [brain.mode_name(), str(ally.global_position.snapped(Vector3.ONE * 0.1)), str(h.global_position.snapped(Vector3.ONE * 0.1)), str(h.rider)])
			await _shot_from(h.global_position + h.global_transform.basis.x * -4.0 + Vector3.UP * 1.8, h.global_position + Vector3.UP * 1.5, "ally_riding")
			await _shot_from(h.global_position - h.forward() * 4.0 + Vector3.UP * 1.8, h.global_position + Vector3.UP * 1.6, "ally_riding_rear")
			brain.dismount()
			brain.queue_free()
			Combat.set_team(spy.player_id, "enemy")
			await _frames(30)
	if _want("death"):
		for who in [["ally", ally], ["spy", spy]]:
			var av: PlayerController = who[1]
			Combat.apply_damage(av.player_id, 999, -1, "test")
		await _frames(150)
		var mid := (ally.global_position + spy.global_position) * 0.5
		await _shot_from(mid + Vector3(-3.5, 2.0, 2.5), mid, "death")
	get_tree().quit()


func _want(n: String) -> bool:
	return only == "" or Array(only.split(",")).has(n)


func _make(style: String, pos: Vector3) -> PlayerController:
	var av: PlayerController = PLAYER_SCENE.instantiate()
	av.is_local = false
	av.is_bot = true
	av.body_style = style
	av.display_name = style
	av.get_node("Head/Camera3D").current = false
	add_child(av)
	av.teleport(pos, 0.0)
	Combat.set_team(av.player_id, "kingdom" if style.contains("kingdom") else "enemy")
	Combat.set_respawn_mode(av.player_id, Combat.Respawn.NEVER)
	av.input_override = {"move": Vector2.ZERO}
	return av


func _rig(av: PlayerController) -> CommanderRig:
	return (av.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig


func _move(av: PlayerController, m: Vector2, sprint: bool, n: int) -> void:
	for i in n:
		av.input_override = {"move": m, "sprint": sprint}
		await get_tree().physics_frame


func _side(av: PlayerController, name: String) -> void:
	var p := av.global_position
	await _shot_from(p + av.global_transform.basis.x * 4.0 + Vector3.UP * 1.1, p + Vector3.UP * 0.95, name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot_from(from: Vector3, look: Vector3, name: String) -> void:
	photo.global_position = from
	photo.look_at(look)
	photo.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	photo.current = false
	print("[variant] ", name, "  ", _fit(ally), "  ", _fit(spy))


## How far the helm sits from the head bone (0 = exactly on it) and whether any of
## the head mesh pokes outside the helm's shell at this pose.
func _fit(av: PlayerController) -> String:
	if not is_instance_valid(av):
		return ""
	var r := _rig(av) as SoldierRig
	if r == null or r.helm == null:
		return "-"
	var head_xf := r.bone_socket("head").global_transform
	var off := r.helm.global_transform.origin.distance_to(head_xf.origin)
	return "helm offset %.4f m, visible %s" % [off, r.helm.is_visible_in_tree()]
