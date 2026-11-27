extends Node
## The soldier variants built from the commander's model: they reuse his meshes,
## skeleton and clips (no copies), wear faction materials that never reach the
## commander, a closed helm that contains every head and hair vertex of the model in
## any pose, exactly one sword, and keep the helm on through every animation.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MODEL := "res://assets/characters/commander/commander.glb"

var t
var spawned: Array[PlayerController] = []


func run(runner) -> void:
	t = runner
	var main: Node = t.main
	var player: PlayerController = main.player
	var cmd := (player.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig
	var w: World = t.world
	var spot: Vector3 = SpawnValidator.find(w, Vector2(-232, 112), NAN, 8.0)["position"]
	var ally := _make("soldier:kingdom", spot + Vector3(2, 0.1, 0))
	var spy := _make("soldier:enemy:spy", spot + Vector3(4, 0.1, 0))
	await _frames(20)
	var ar := _rig(ally)
	var sr := _rig(spy)

	# --- the commander is untouched -------------------------------------------------------
	t.check(not (cmd is SoldierRig) and cmd.find_child("GreatHelm", true, false) == null, "the commander wears no helm")
	t.check(cmd.model.find_child("Hair", true, false).visible and cmd.head_mesh != null, "the commander keeps his hair and his animated face")
	t.check(cmd.offhand_sword != null and cmd.dual_wield, "the commander keeps both swords")
	var leaked := false
	for mi in cmd.model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.get_surface_override_material_count():
			var mat := m.get_surface_override_material(s)
			if mat and (mat.resource_name.ends_with("_kingdom") or mat.resource_name.ends_with("_enemy")):
				leaked = true
	t.check(not leaked, "no soldier material reaches the commander")

	# --- the same model, not a copy -----------------------------------------------------------
	t.check(ar is CommanderRig and sr is CommanderRig, "both variants are built on the commander's rig")
	var shared := true
	for part in ["Armour", "Boots", "Cloak", "Clothes", "Coat", "Gear", "Gloves"]:
		var a := ar.model.find_child(part, true, false) as MeshInstance3D
		var c := cmd.model.find_child(part, true, false) as MeshInstance3D
		if a == null or c == null or a.mesh != c.mesh:
			shared = false
	t.check(shared, "the soldiers share the commander's body, cloak and outfit meshes (no duplicates)")
	t.check(ar.skeleton.get_bone_count() == cmd.skeleton.get_bone_count() and ar.player_anim.get_animation_list() == cmd.player_anim.get_animation_list(),
		"the same skeleton and the same animation clips", "%d bones" % ar.skeleton.get_bone_count())
	t.check(_rig(ally).model.find_child("Head", true, false).mesh == _rig(spy).model.find_child("Head", true, false).mesh,
		"one shared skin-only head mesh for every soldier")

	# --- faction materials -----------------------------------------------------------------------
	var ac := _cloth(ar)
	var sc := _cloth(sr)
	var cc := _cloth(cmd)
	t.check(ac != null and sc != null and ac != sc and ac != cc and sc != cc, "uniform and cape materials are faction-specific")
	if ac and sc:
		var src := ((ar.model.find_child("Cloak", true, false) as MeshInstance3D).mesh.surface_get_material(0) as BaseMaterial3D).albedo_texture
		# Headless runs have no texture pixels on the GPU side: recolour the source
		# atlas from disk with the same function and measure that.
		var disk := ImageTexture.create_from_image(Image.load_from_file(src.resource_path))
		var a_col := _mean(SoldierMaterials._recolored(disk, "kingdom"), disk) * ac.albedo_color
		var s_col := _mean(SoldierMaterials._recolored(disk, "enemy"), disk) * sc.albedo_color
		t.check(a_col.r > a_col.g * 2.0 and a_col.r > a_col.b * 1.8 and a_col.v < 0.45, "the allied cape is a deep, muted maroon", str(a_col))
		t.check(s_col.v < 0.2 and absf(s_col.r - s_col.b) < 0.05, "the enemy cape is near-black", str(s_col))
		t.check(ac.roughness > 0.9 and sc.roughness > 0.9, "the cloth is matte")

	# --- helm ---------------------------------------------------------------------------------
	t.check(ar.helm != null and sr.helm != null and ar.helm.get_parent() is BoneAttachment3D
		and (ar.helm.get_parent() as BoneAttachment3D).bone_name == "head", "the helm rides the head bone")
	t.check(not ar.model.find_child("Hair", true, false).visible and not ar.model.find_child("Eyes", true, false).visible,
		"hair and eyes are not drawn inside the helm")
	var out := _head_outside_helm()
	t.check(out[0] == 0, "every head and hair vertex of the model lies inside the closed helm", "%d of %d outside, worst %s" % [out[0], out[1], str(out[2])])

	# --- weapons ------------------------------------------------------------------------------
	t.check(ar.sword_count() == 1 and ar.offhand_sword == null and ar.find_child("OffhandSword", true, false) == null,
		"an allied soldier carries exactly one sword")
	t.check(sr.sword_count() == 1 and sr.find_child("OffhandSword", true, false) == null, "a spy carries exactly one sword")

	# --- animations keep the helm on ----------------------------------------------------------
	var drift := 0.0
	var states := []
	for step in [["walk", Vector2(0, 1), false], ["sprint", Vector2(0, 1), true], ["idle", Vector2.ZERO, false]]:
		for i in 50:
			ally.input_override = {"move": step[1], "sprint": step[2]}
			await t.get_tree().physics_frame
			drift = maxf(drift, _helm_drift(ar))
		states.append(step[0])
	for action in ["attack", "ability_1"]:
		Combat.request_action(ally.player_id, action)
		for i in 50:
			await t.get_tree().physics_frame
			drift = maxf(drift, _helm_drift(ar))
		states.append(action)
	Combat.apply_damage(ally.player_id, 5, -1, "test")
	await _frames(30)
	Combat.apply_damage(ally.player_id, 999, -1, "test")
	for i in 120:
		await t.get_tree().physics_frame
		drift = maxf(drift, _helm_drift(ar))
	t.check(drift < 0.002, "walk, sprint, cuts, dodge, hit and death: the helm never leaves the head", "max %.4f m" % drift)
	t.check(ar.tree.get("parameters/hold/blend_amount") > 0.5, "the soldier plays the commander's death clip")
	t.check(sr.sword_count() == 1 and ar.sword_count() == 1, "still one sword each after the actions")
	for av in spawned:
		av.queue_free()
	await _frames(5)


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
	spawned.append(av)
	return av


func _rig(av: PlayerController) -> CommanderRig:
	return (av.get_node("AvatarVisual") as AvatarVisual).human_rig as CommanderRig


func _cloth(r: CommanderRig) -> StandardMaterial3D:
	var cloak := r.model.find_child("Cloak", true, false) as MeshInstance3D
	return cloak.get_active_material(0) as StandardMaterial3D if cloak else null


## Mean colour of the cloth texels (blue in the commander's source atlas) in `tex`.
func _mean(tex: Texture2D, src: Texture2D) -> Color:
	if tex == null or src == null:
		return Color.WHITE
	var img := tex.get_image()
	var ref := src.get_image()
	for im in [img, ref]:
		if (im as Image).is_compressed():
			(im as Image).decompress()
	var sum := Vector3.ZERO
	var n := 0
	for y in range(0, ref.get_height(), 8):
		for x in range(0, ref.get_width(), 8):
			var o := ref.get_pixel(x, y)
			if o.a > 0.01 and o.b > o.r * 1.2 and o.b > o.g * 1.12:
				var c := img.get_pixel(x * img.get_width() / ref.get_width(), y * img.get_height() / ref.get_height())
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	sum /= maxf(n, 1)
	return Color(sum.x, sum.y, sum.z)


func _helm_drift(r: SoldierRig) -> float:
	var sock := r.helm.get_parent() as Node3D
	return r.helm.global_position.distance_to(sock.global_position)


## Every vertex of the model's Head and Hair meshes that the head bone carries, in the
## head bone's rest frame (where the helm is built), tested against the helm shell.
func _head_outside_helm() -> Array:
	var scene: Node3D = (load(MODEL) as PackedScene).instantiate()
	var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	var head := sk.find_bone("head")
	var inv := sk.get_bone_global_rest(head).affine_inverse()
	var outside := 0
	var total := 0
	var worst := Vector3.ZERO
	var worst_e := 0.0
	for name in ["Head", "Hair", "Eyes"]:
		var mi := scene.find_child(name, true, false) as MeshInstance3D
		var m := mi.mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / verts.size()
			for i in verts.size():
				var hw := 0.0
				for k in per:
					if bones[i * per + k] == head:
						hw += weights[i * per + k]
				if hw < 0.99:
					continue  # neck vertices shared with the neck bone move with it, below the lip
				total += 1
				var p: Vector3 = inv * verts[i]
				if p.y < -0.118:
					continue  # under the lip: the neck
				var e := _ellipse(p)
				if e > 1.0 or p.y > 0.222:
					outside += 1
					if e > worst_e:
						worst_e = e
						worst = p
	scene.free()
	return [outside, total, worst.snapped(Vector3.ONE * 0.001)]


## > 1 when p is outside the helm's shell at p's height (GreatHelm's oval).
func _ellipse(p: Vector3) -> float:
	var s := GreatHelm._scale_at(p.y)
	if s <= 0.0:
		return 99.0
	var rz := GreatHelm.RZ_FRONT if p.z - GreatHelm.CZ >= 0.0 else GreatHelm.RZ_BACK
	var x := p.x / (GreatHelm.RX * s)
	var z := (p.z - GreatHelm.CZ) / (rz * s)
	return x * x + z * z


func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame
