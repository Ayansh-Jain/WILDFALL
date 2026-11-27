extends Node3D
var actors := {}
var ledger: RefCounted
var elapsed := 0.0
var commander: PlayerController
var material_a: StandardMaterial3D
var material_e: StandardMaterial3D
var metal: StandardMaterial3D
var meshes := {}
func material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m

func box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func piece(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	parent.add_child(node)
	return node


func setup(owner_ledger: RefCounted, player: PlayerController) -> void:
	ledger = owner_ledger
	commander = player
	material_a = material(Color("742b32"))
	material_e = material(Color("253944"))
	metal = material(Color("969ca2"))
	meshes = {"torso": box_mesh(Vector3(.48,.65,.28)), "head": box_mesh(Vector3(.27,.32,.28)), "limb": box_mesh(Vector3(.15,.65,.16)), "sword": box_mesh(Vector3(.055,.85,.025))}
	for i in range(1,100):
		for side in ["a","e"]:
			var id := "%s.%03d" % [side,i]
			var root := Node3D.new()
			add_child(root)
			var pos := Vector3((i%10-4.5)*3.2,0,-6-floori(i/10.0)*3.0)
			pos.z += -.8 if side == "e" else .8
			root.position = pos
			root.rotation.y = PI if side == "e" else 0
			var mat := material_a if side == "a" else material_e
			piece(root,meshes.torso,mat,Vector3(0,1.05,0))
			piece(root,meshes.head,metal,Vector3(0,1.57,0))
			piece(root,meshes.limb,mat,Vector3(-.14,.37,0))
			piece(root,meshes.limb,mat,Vector3(.14,.37,0))
			var arm := Node3D.new()
			arm.position = Vector3(.32,1.3,0)
			root.add_child(arm)
			piece(arm,meshes.limb,mat,Vector3(0,-.25,0))
			piece(arm,meshes.sword,metal,Vector3(0,-.25,-.42)).rotation.x = PI/2
			var shield := piece(root,box_mesh(Vector3(.12,.55,.45)),metal,Vector3(-.34,1.05,-.12))
			var logical_id := -1000 - i*2 - (1 if side == "e" else 0)
			actors[id] = {"node":root,"arm":arm,"shield":shield,"anchor":pos,"phase":float(i)*2.399963,"tier":1,"acc":0.0,"combat_id":logical_id}
			Combat.register_logical(logical_id,{"health":100,"position":pos,"soldier":id},"enemy" if side == "e" else "kingdom")
	Combat.damage_dealt.connect(_on_damage)

func _on_damage(data: Dictionary) -> void:
	if not Combat.logical_actors.has(data.target):
		return
	var id: String = Combat.logical_actors[data.target].soldier
	if not actors.has(id):
		return
	ledger.interrupt(id)
	if data.health_after <= 0:
		ledger.fall(id,"player")

func _physics_process(delta: float) -> void:
	elapsed += delta
	ledger.advance(delta)
	for id in actors:
		var actor: Dictionary = actors[id]
		var distance: float = commander.global_position.distance_to(actor.anchor)
		if actor.tier == 1 and distance > 28: actor.tier = 2
		elif actor.tier == 2 and distance < 22: actor.tier = 1
		actor.acc += delta
		if actor.tier == 2 and actor.acc < .1: continue
		var update_delta: float = actor.acc
		actor.acc = 0.0
		var node: Node3D = actor.node
		if not ledger.soldiers[id].alive:
			node.rotation.z = PI/2
			node.position.y = .25
			Combat.logical_actors[actor.combat_id].health = 0
			continue
		if actor.has("destination"):
			node.position = node.position.move_toward(actor.destination,update_delta*2.0)
			actor.anchor = node.position
			Combat.logical_actors[actor.combat_id].position = node.global_position
			if node.position.distance_to(actor.destination)<0.05:
				actor.erase("destination")
		var phase: float = elapsed*1.8+actor.phase
		if String(ledger.soldiers[id].pair).is_empty():
			actor.arm.rotation.x = -.5
			continue
		var offset := PI if id.begins_with("e") else 0.0
		actor.arm.rotation.x = -1.1 + .9*sin(phase+offset)
		actor.shield.rotation.x = .25*sin(phase+offset+PI)
		node.position = actor.anchor + Vector3(0,.02*sin(phase*2),.16*sin(phase))
		Combat.logical_actors[actor.combat_id].position = node.global_position

func _exit_tree() -> void:
	for actor in actors.values():
		Combat.unregister_logical(actor.combat_id)


## T places reserve support at fixed validated anchors; no continuous following.
func summon_reserves(origin: Vector3, yaw: float) -> void:
	for i in range(90,100):
		var id := "a.%03d" % i
		if not ledger.soldiers[id].alive:
			continue
		var candidate := origin + Basis(Vector3.UP,yaw)*Vector3((i%5-2)*1.5,0,3.0+floori((i-90)/5.0)*1.5)
		var ray := PhysicsRayQueryParameters3D.create(origin+Vector3.UP,candidate+Vector3.UP,Layers.WORLD)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		actors[id]["destination"] = candidate
