extends SceneTree
## Lists the commander model's meshes (surfaces, materials, triangles, LODs) and the
## bounds of the head region in the head bone's rest frame (for fitting a helmet).
##   godot --headless --path . --script res://tools/inspect_commander.gd

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	var scene: Node3D = (load("res://assets/characters/commander/commander.glb") as PackedScene).instantiate()
	root.add_child(scene)
	var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	var head := sk.find_bone("head")
	var head_rest := sk.get_bone_global_rest(head)
	var inv := head_rest.affine_inverse()
	print("head bone rest ", head_rest.origin, "  neck_01 ", sk.get_bone_global_rest(sk.find_bone("neck_01")).origin)
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh as ArrayMesh
		var tris := 0
		var mats := []
		for s in m.get_surface_count():
			tris += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var mat := m.surface_get_material(s)
			mats.append(mat.resource_name if mat else "-")
		print("%-16s parent %-10s tris %6d  blend %d  surfaces %s" % [mi.name, mi.get_parent().name, tris, m.get_blend_shape_count(), str(mats)])
		# Head region: vertices weighted mostly to head (or above the neck) in rest pose.
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var n := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var weights = arr[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null:
				continue
			var per := (bones as PackedInt32Array).size() / verts.size()
			for i in verts.size():
				var hw := 0.0
				for k in per:
					var bi: int = bones[i * per + k]
					if bi == head or sk.get_bone_name(bi).begins_with("eye") or sk.get_bone_name(bi).begins_with("jaw"):
						hw += float(weights[i * per + k])
				if hw < 0.5:
					continue
				var p: Vector3 = inv * verts[i]
				lo = lo.min(p)
				hi = hi.max(p)
				n += 1
		if n > 0:
			print("    head-weighted verts %d  bounds in head frame  min %s  max %s" % [n, str(lo.snapped(Vector3.ONE * 0.005)), str(hi.snapped(Vector3.ONE * 0.005))])
	return true
