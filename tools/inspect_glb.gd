extends SceneTree
## Prints the structure of an imported character scene: meshes, surfaces,
## material names, triangle counts, skeleton bones, blend shapes, animations.
##   godot --headless --path . --script res://tools/inspect_glb.gd -- res://assets/characters/commander/commander.glb


func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "res://assets/characters/commander/commander.glb"
	var scene: PackedScene = load(path)
	var root := scene.instantiate()
	var total := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		var tris := 0
		var mats: PackedStringArray = []
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			tris += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var mat := m.surface_get_material(s)
			mats.append(mat.resource_name if mat else "-")
		total += tris
		var bs := (m as ArrayMesh).get_blend_shape_count() if m is ArrayMesh else 0
		print("[glb] mesh %-22s tris %6d  blend shapes %2d  skin %s  materials %s" % [mi.name, tris, bs, str((mi as MeshInstance3D).skin != null), ", ".join(mats)])
	print("[glb] total triangles %d" % total)
	for sk in root.find_children("*", "Skeleton3D", true, false):
		print("[glb] skeleton %s: %d bones" % [sk.name, (sk as Skeleton3D).get_bone_count()])
	for ap in root.find_children("*", "AnimationPlayer", true, false):
		print("[glb] animations: ", (ap as AnimationPlayer).get_animation_list())
	print("[glb] tree: ", _tree(root, 0))
	root.free()
	quit()


func _tree(n: Node, depth: int) -> String:
	if depth > 2:
		return ""
	var s := "%s(%s)" % [n.name, n.get_class()]
	var kids: PackedStringArray = []
	for c in n.get_children():
		if c is Skeleton3D or depth < 1:
			kids.append(_tree(c, depth + 1))
	return s + ("[" + ", ".join(kids) + "]" if kids.size() > 0 and depth < 2 else "")
