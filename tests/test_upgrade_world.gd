extends Node
func run(t) -> void:
	var cave: Cave=t.world.get_node("Sites/Cave")
	var expected:=0
	for cell: Vector2i in cave.info.cells:
		if cave.info.cells[cell]!="m":
			continue
		for direction in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if cave._outside_grid(cell+direction):
				expected+=1
	t.check(expected>0 and cave.sealed_entrances.size()==expected,"every authored cave entrance has a rockfall seal",str(expected))
	var space:=cave.get_world_3d().direct_space_state
	for entrance in cave.sealed_entrances:
		var center:=entrance.global_position
		var shape: BoxShape3D=entrance.get_child(0).shape
		var axis:=Vector3.RIGHT if shape.size.x<shape.size.z else Vector3.BACK
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(center-axis*5,center+axis*5,Layers.WORLD))
		t.check(not hit.is_empty(),"rockfall blocks its entrance collision ray")
	t.check(t.main.scroll_spawner.scroll.global_position.y<cave.info.floor+1,"single original scroll remains inside preserved cave")
	var h: Horse=t.main.horse
	var p: PlayerController=t.main.player
	var start: Dictionary=t.world.ground_ray(44,164,30,80)
	t.check(not start.is_empty(),"stone bridge approach is grounded")
	var heading:=Vector3(28,0,16).normalized()
	h.teleport(start.position+Vector3.UP*0.1,atan2(-heading.x,-heading.z))
	h._come_target=Vector3.INF
	h.cruise=Horse.Gait.WALK
	h.drive={"move":Vector2(0,1)}
	for i in 1000:
		await t.get_tree().physics_frame
		if (h.global_position-start.position).dot(heading)>31:
			break
	h.drive={}
	t.check((h.global_position-start.position).dot(heading)>28,"horse physically crosses stone bridge without bypassing collision",str(h.global_position))
