class_name SoldierRig
extends CommanderRig
## A kingdom or enemy soldier built from the COMMANDER'S OWN MODEL: the same glTF body
## mesh, proportions, skeleton, cape (geometry and spring chains), locomotion and
## sword clips, gait blending and riding clips. Only the look differs, and only through
## per-instance overrides (CommanderRig and its materials are never modified):
##
## - faction "kingdom": deep maroon uniform and cape; "enemy" (spies and the enemy
##   host): near-black uniform and cape, blackened fittings (SoldierMaterials).
## - a closed great helm on the head bone that hides the whole face (GreatHelm); the
##   hair cards and eyes sit inside it and are not drawn, nor are brows and lashes.
## - exactly ONE sword (the commander's longsword) and one scabbard; no facial
##   animation and no dual-sword sprint layer.
## - kingdom line soldiers carry the commander's belt lantern; its warm light is in
##   the "day_night_lights" group, so the day/night cycle fades it on at dusk and off
##   at dawn. Spies and the enemy carry none.
##
## API kept for the soldier brain: `faction`, `variant` ("" | "spy" | "captain"),
## `combat_ready` (draws the sword, squares up to the foe), `sword_count()`,
## hold("mount" / "ride" / "defeat"), release(), ride_with(horse), play(...).
##
## Level of detail (a battle has ~85 of these; the look is unchanged at gameplay
## distances): the animation advances every frame within 8 m, at 30 Hz to 20 m, 15 Hz
## to 45 m and 7.5 Hz beyond (updates staggered across frames); the cape springs run
## within 8 m; shadows within 35 m;
## belt pouches, gloves, scabbard and lantern are not drawn beyond 45 m; nothing beyond
## 170 m. Helm, scabbard and lantern are single merged meshes (one draw call each), and
## the head is drawn from one shared copy holding only its skin surface (the brows,
## lashes and teeth surfaces sit inside the helm).

var faction := "kingdom"
var variant := ""
var combat_ready := false
var helm: MeshInstance3D
var lantern_light: OmniLight3D

var _head_socket: BoneAttachment3D
var _springs: SpringBoneSimulator3D
var _lod_acc := 0.0
var _shadows := true
var _hidden_near := false


func _build() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	if f:
		_meta = JSON.parse_string(f.get_as_text())
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	model = MODEL.instantiate()
	# The glTF character faces +Z; the game's rigs face -Z.
	model.rotation.y = PI
	_pivot.add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false)
	player_anim = model.find_child("AnimationPlayer", true, false)
	for clip in _meta.get("clips", {}):
		if player_anim.has_animation(clip):
			player_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if _meta["clips"][clip].get("loop", false) else Animation.LOOP_NONE
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.name == "Longsword":
			sword = m
		# Inside the helm: hair cards and eyes would only cost draw time. The head mesh
		# stays (the neck shows below the helm's lip).
		if m.name in ["Hair", "Eyes"]:
			m.visible = false
			continue
		m.set_meta("casts", true)
		_meshes.append(m)
	head_mesh = null  # no face rig under a closed helm
	_use_skin_only_head()
	SoldierMaterials.apply(model, faction)
	_load_ride_clips()
	_setup_sockets()
	if faction == "kingdom" and variant != "spy":
		_setup_lantern()
		_setup_lantern_light()
	_setup_tree()
	_setup_cloak()
	_springs = skeleton.get_node_or_null("CloakSprings") as SpringBoneSimulator3D
	_setup_helm()
	for m in _meshes:
		var small := bool(m.get_meta("small", false)) or m.name in ["Gear", "Gloves"]
		m.visibility_range_end = 45.0 if small else 170.0
		m.visibility_range_end_margin = 5.0 if small else 10.0
	# The animation is advanced by hand, at a rate set by distance (see _process);
	# a random phase spreads the crowd's updates over different frames.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_lod_acc = randf() * 0.12


static var _skin_head: ArrayMesh


## The head mesh without its brows / lashes / teeth surfaces (inside the helm) and
## without blend shapes: built once from the commander's mesh and shared by all.
func _use_skin_only_head() -> void:
	var head := model.find_child("Head", true, false) as MeshInstance3D
	if head == null:
		return
	if _skin_head == null:
		var src := head.mesh
		_skin_head = ArrayMesh.new()
		for s in src.get_surface_count():
			var mat := src.surface_get_material(s)
			if mat and mat.resource_name in ["Brows", "Lashes", "Teeth"]:
				continue
			_skin_head.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
			_skin_head.surface_set_material(_skin_head.get_surface_count() - 1, mat)
		_skin_head.resource_name = "SoldierHead"
	head.mesh = _skin_head


func _setup_helm() -> void:
	_head_socket = BoneAttachment3D.new()
	_head_socket.name = "HelmSocket"
	skeleton.add_child(_head_socket)
	_head_socket.bone_name = "head"
	helm = MeshInstance3D.new()
	helm.name = "GreatHelm"
	helm.mesh = GreatHelm.mesh(faction, variant)
	helm.set_meta("casts", true)
	_head_socket.add_child(helm)
	_meshes.append(helm)


## The commander's horn lantern at the belt, with a warm light the day/night cycle
## switches on at dusk (kingdom line soldiers only).
func _setup_lantern_light() -> void:
	if _lantern == null:
		return
	lantern_light = OmniLight3D.new()
	lantern_light.name = "ArmyLanternLight"
	lantern_light.position = Vector3(0.0, 0.0, 0.1)
	lantern_light.light_color = Color(1.0, 0.62, 0.32)
	lantern_light.light_energy = 1.35
	lantern_light.omni_range = 9.0
	lantern_light.omni_attenuation = 1.2
	lantern_light.visible = false
	lantern_light.shadow_enabled = false
	lantern_light.add_to_group("day_night_lights")
	_lantern.add_child(lantern_light)


## One sword in the right hand's weapon socket and one scabbard; no second blade.
func _setup_sockets() -> void:
	_hand_socket = BoneAttachment3D.new()
	_hand_socket.name = "HandSocket"
	skeleton.add_child(_hand_socket)
	_hand_socket.bone_name = "weapon_r"
	_hip_socket = BoneAttachment3D.new()
	_hip_socket.name = "HipSocket"
	skeleton.add_child(_hip_socket)
	_hip_socket.bone_name = "pelvis"
	_soldier_scabbard(_hip_socket, -1.0)
	offhand_sword = null
	dual_wield = false
	if sword:
		sword.reparent(_hip_socket, false)
		sword.transform = Transform3D.IDENTITY
		sword.visible = false
	var wr := skeleton.find_bone("weapon_r")
	if wr >= 0:
		blade_in_hand_r = (skeleton.get_bone_rest(wr).basis * Vector3.UP).normalized()


## The commander's scabbard (same parts, sizes and slant) as one merged mesh.
func _soldier_scabbard(socket: BoneAttachment3D, side: float) -> void:
	var leather := Color(0.09, 0.055, 0.035)
	var bronze := Color(0.34, 0.23, 0.11) if faction == "kingdom" else Color(0.16, 0.15, 0.14)
	var parts := []
	for spec in [[0.0, 0.72, 0.024, leather], [-0.12, 0.035, 0.03, bronze], [-0.5, 0.035, 0.026, bronze], [-0.73, 0.04, 0.022, bronze]]:
		var cm := CylinderMesh.new()
		cm.top_radius = spec[2]
		cm.bottom_radius = spec[2] * (0.82 if spec[1] > 0.1 else 1.0)
		cm.height = spec[1]
		cm.radial_segments = 8
		parts.append([cm, Transform3D(Basis.IDENTITY, Vector3(0, spec[0] - (spec[1] * 0.5 if spec[1] > 0.1 else 0.0), 0)), spec[3]])
	var mi := MeshInstance3D.new()
	mi.name = "Scabbard"
	mi.mesh = _merge(parts, 0.3, 0.7)
	mi.rotation = Vector3(deg_to_rad(30.0), 0.0, deg_to_rad(8.0) * side)
	mi.position = Vector3(side * 0.22, -0.08, 0.18)
	mi.set_meta("casts", true)
	mi.set_meta("small", true)
	socket.add_child(mi)
	_meshes.append(mi)


## The commander's horn lantern (same shape) as two meshes: iron frame, glowing horn.
func _setup_lantern() -> void:
	var att := BoneAttachment3D.new()
	att.name = "LanternSocket"
	skeleton.add_child(att)
	att.bone_name = "pelvis"
	_lantern = Node3D.new()
	_lantern.name = "Lantern"
	att.add_child(_lantern)
	_lantern.position = Vector3(-0.2, -0.13, 0.13)
	var iron := Color(0.13, 0.11, 0.09)
	var cap_a := CylinderMesh.new()
	cap_a.top_radius = 0.05
	cap_a.bottom_radius = 0.05
	cap_a.height = 0.018
	cap_a.radial_segments = 10
	var ring := TorusMesh.new()
	ring.inner_radius = 0.012
	ring.outer_radius = 0.022
	var frame := MeshInstance3D.new()
	frame.mesh = _merge([[cap_a, Transform3D(Basis.IDENTITY, Vector3(0, 0.058, 0)), iron],
		[cap_a, Transform3D(Basis.IDENTITY, Vector3(0, -0.058, 0)), iron],
		[ring, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.085, 0)), iron]], 0.45, 0.7)
	var horn := CylinderMesh.new()
	horn.top_radius = 0.045
	horn.bottom_radius = 0.045
	horn.height = 0.1
	horn.radial_segments = 10
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(1.0, 0.72, 0.42)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.62, 0.3)
	glass.emission_energy_multiplier = 2.2
	horn.material = glass
	var glow := MeshInstance3D.new()
	glow.mesh = horn
	for mi in [frame, glow]:
		mi.set_meta("casts", false)
		mi.set_meta("small", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lantern.add_child(mi)
		_meshes.append(mi)


## Several primitive meshes merged into one vertex-coloured surface (one draw call).
static func _merge(parts: Array, roughness: float, metallic: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var pm: PrimitiveMesh = p[0]
		var xf: Transform3D = p[1]
		var arrays := pm.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		st.set_color(p[2])
		for i in idx:
			st.set_normal((xf.basis * normals[i]).normalized())
			st.add_vertex(xf * verts[i])
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = roughness
	mat.metallic = metallic
	m.surface_set_material(0, mat)
	return m


## Swords this soldier carries (always exactly 1, drawn or sheathed).
func sword_count() -> int:
	return 1 if sword != null and is_instance_valid(sword) else 0


func _carry_belt_light() -> void:
	pass  # the lantern hangs where _setup_lantern put it; its light is the cycle's


# --- poses the brain asks for ------------------------------------------------------------------

func hold(anim: String, length := 1.0) -> void:
	match anim:
		"ride", "mount":
			# Seated on the commander's riding clips; the brain keeps ride_basis,
			# ride_gait and ride_rate up to date from the horse (ride_with).
			riding = true
			_hold = anim
			return
		"defeat":
			riding = false  # falls from the saddle onto the ground beside the horse
	super.hold(anim, length)


func release() -> void:
	riding = false
	super.release()


func ride_with(h: Horse) -> void:
	var hr := h.get_node_or_null("Rig") as HorseRig
	ride_basis = (hr.seat.global_transform.basis if hr and hr.seat else h.global_basis).orthonormalized()
	var g := h.gait_name()
	ride_gait = "ride_" + (g if g in ["walk", "trot", "canter", "gallop"] else "idle")
	var nominal: float = Horse.GAIT_SPEED.get(h.gait, 0.0)
	ride_rate = clampf(absf(h.speed) / nominal, 0.6, 1.6) if nominal > 0.1 else 1.0


# --- per frame ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(global_position + Vector3.UP) if cam else 0.0
	_set_lod(d)
	_lod_acc += delta
	var step := 0.0 if d < 8.0 else (1.0 / 30.0 if d < 20.0 else (1.0 / 15.0 if d < 45.0 else 1.0 / 7.5))
	if _lod_acc < step:
		return
	var dt := _lod_acc
	_lod_acc = 0.0
	_time += dt
	if combat_ready:
		danger = true
	_pose(dt)
	if combat_ready and not riding and _hold_anim == "":
		# Square up to the enemy instead of turning to the strafe direction.
		_yaw = lerp_angle(_yaw, 0.0, clampf(dt * 10.0, 0.0, 1.0))
		_pivot.rotation = Vector3(0.0, _yaw, 0.0)
	tree.advance(dt)
	# Never fill the follow camera's lens.
	var near := cam != null and d < 1.2 and cam.get_parent() != null and cam.get_parent().get_parent() is PlayerController
	if near != _hidden_near:
		_hidden_near = near
		for m in _meshes:
			if is_instance_valid(m):
				m.visible = not near


func _set_lod(d: float) -> void:
	if _springs:
		_springs.active = d < 8.0
	var cast := d < 35.0
	if cast != _shadows:
		_shadows = cast
		for m in _meshes:
			if is_instance_valid(m):
				var on := cast and bool(m.get_meta("casts", true))
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
