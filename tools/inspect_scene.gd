extends SceneTree
## Prints the node tree, skeleton bones and animation tracks of imported scenes:
##   godot --headless --path . --script res://tools/inspect_scene.gd -- res://a.glb [res://b.glb]

func _init() -> void:
	for path in OS.get_cmdline_user_args():
		var ps: PackedScene = load(path)
		if ps == null:
			print("cannot load ", path)
			continue
		var root := ps.instantiate()
		print("=== ", path)
		_print(root, 0)
		var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			for n in ap.get_animation_list():
				var a := ap.get_animation(n)
				print("ANIM %s len %.3f tracks %d first %s" % [n, a.length, a.get_track_count(), a.track_get_path(0) if a.get_track_count() > 0 else "-"])
		var sk := root.find_child("Skeleton3D", true, false) as Skeleton3D
		if sk:
			print("BONES ", sk.get_bone_count())
		root.free()
	quit()


func _print(n: Node, depth: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		extra = " surfaces %d" % m.get_surface_count()
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			extra += " [%s]" % (mat.resource_name if mat else "-")
	print("  ".repeat(depth), n.name, " (", n.get_class(), ")", extra)
	if depth < 4:
		for c in n.get_children():
			_print(c, depth + 1)
