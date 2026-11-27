class_name WorldPoi
extends Node3D
## One reusable world interaction (road sign, monument, abandoned camp, viewpoint,
## resting place). It exists only while the Commander is nearby; anything that must
## survive is kept in Persist under its id. No per-frame processing. The small marker
## meshes have no collision; `scene` in the data replaces them with authored art.

signal used(poi: WorldPoi)

static var _materials := {}

var cfg := {}
var id := ""
var kind := ""
var trigger: Interactable


func setup(p_cfg: Dictionary) -> WorldPoi:
	cfg = p_cfg
	id = String(cfg["id"])
	kind = String(cfg.get("kind", "sign"))
	name = "Poi_" + id
	var scene := String(cfg.get("scene", ""))
	if scene != "" and ResourceLoader.exists(scene):
		add_child((load(scene) as PackedScene).instantiate())
	else:
		_build_marker()
	trigger = Interactable.new()
	trigger.name = "Use"
	trigger.prompt_text = String(cfg.get("prompt", "Look"))
	trigger.max_view_angle = 60.0
	trigger.position.y = 1.0
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	var cs := CollisionShape3D.new()
	cs.shape = sphere
	trigger.add_child(cs)
	trigger.interacted.connect(func(_by: Node) -> void: used.emit(self))
	add_child(trigger)
	return self


func _build_marker() -> void:
	var wood := Color(0.32, 0.22, 0.12)
	var stone := Color(0.42, 0.43, 0.40)
	match kind:
		"sign":
			_box(Vector3(0.14, 1.9, 0.14), Vector3(0, 0.95, 0), wood)
			_box(Vector3(0.9, 0.2, 0.06), Vector3(0.3, 1.7, 0), wood * 1.25)
			_box(Vector3(0.8, 0.2, 0.06), Vector3(-0.28, 1.42, 0), wood * 1.25)
		"monument":
			_box(Vector3(0.9, 0.25, 0.7), Vector3(0, 0.12, 0), stone * 0.85)
			_box(Vector3(0.6, 1.25, 0.28), Vector3(0, 0.85, 0), stone)
		"view":
			for i in 4:
				_box(Vector3(0.55 - i * 0.11, 0.18, 0.5 - i * 0.09), Vector3(0.03 * (i % 2), 0.09 + i * 0.17, 0), stone * (1.0 - i * 0.06))
		"camp":
			for i in 6:
				var a := TAU * i / 6.0
				_box(Vector3(0.24, 0.16, 0.24), Vector3(cos(a) * 0.55, 0.07, sin(a) * 0.55), stone * 0.7)
			_box(Vector3(0.7, 0.08, 0.12), Vector3(0, 0.08, 0), Color(0.07, 0.05, 0.04))
			_box(Vector3(1.4, 0.06, 0.7), Vector3(1.4, 0.04, 0.3), Color(0.16, 0.13, 0.10))
		"rest":
			_box(Vector3(1.6, 0.1, 0.45), Vector3(0, 0.48, 0), wood * 1.15)
			for x: float in [-0.65, 0.65]:
				_box(Vector3(0.12, 0.45, 0.4), Vector3(x, 0.22, 0), wood)


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var key := color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 1.0
		_materials[key] = m
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _materials[key]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.visibility_range_end = 90.0
	add_child(mi)
