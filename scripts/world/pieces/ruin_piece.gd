@tool
class_name RuinPiece
extends StaticBody3D
## One reusable, parameterised ruin piece (wall, pillar, archway, stairs...).
## Geometry and collision are rebuilt from the exported values, so pieces can
## be placed and tweaked in the editor as well as by the site builders.
## Origin is at the base centre unless noted. Stairs ascend towards +Z.

enum Kind { WALL, PILLAR, ARCHWAY, STAIRS, PLATFORM, BRAZIER, MENHIR, STATUE, RUBBLE, FALLEN_PILLAR, BLOCK }

const STONE_MAT := preload("res://assets/materials/stone.tres")
const GLOW_WARM := preload("res://assets/materials/glow_warm.tres")
const GLOW_MAGIC := preload("res://assets/materials/glow_magic.tres")

const STONE := Color(0.36, 0.35, 0.33)
const STONE_DARK := Color(0.27, 0.27, 0.26)
const MOSS := Color(0.24, 0.31, 0.17)

@export var kind: Kind = Kind.WALL:
	set(v):
		kind = v
		_queue_rebuild()
## WALL: length, height, thickness. PILLAR: diameter, height. ARCHWAY: opening
## width, opening height, depth. STAIRS: width, rise, run. RUBBLE: radius, height.
## FALLEN_PILLAR: length, diameter. Others: bounding size.
@export var size := Vector3(6.0, 4.0, 1.2):
	set(v):
		size = v
		_queue_rebuild()
@export_range(0.0, 1.0) var broken := 0.4:
	set(v):
		broken = v
		_queue_rebuild()
@export var seed_value := 1:
	set(v):
		seed_value = v
		_queue_rebuild()
@export var color := STONE:
	set(v):
		color = v
		_queue_rebuild()
## BRAZIER only: add a warm OmniLight3D.
@export var lit := true:
	set(v):
		lit = v
		_queue_rebuild()

var _rng := RandomNumberGenerator.new()
var _kit: MeshKit
var _glow: MeshKit
var _glow_mat: Material
var _pending := false
var _light: OmniLight3D
var _flicker_t := 0.0


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	rebuild()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	(func() -> void:
		_pending = false
		rebuild()).call_deferred()


func rebuild() -> void:
	for c in get_children():
		if c.has_meta("_generated"):
			remove_child(c)
			c.queue_free()
	_light = null
	_rng.seed = seed_value * 7349 + int(kind) * 131
	_kit = MeshKit.new(seed_value, 0.07)
	_glow = MeshKit.new(seed_value)
	_glow_mat = GLOW_MAGIC
	match kind:
		Kind.WALL: _wall()
		Kind.PILLAR: _pillar()
		Kind.ARCHWAY: _archway()
		Kind.STAIRS: _stairs()
		Kind.PLATFORM: _platform()
		Kind.BRAZIER: _brazier()
		Kind.MENHIR: _menhir()
		Kind.STATUE: _statue()
		Kind.RUBBLE: _rubble()
		Kind.FALLEN_PILLAR: _fallen_pillar()
		Kind.BLOCK: _block()
	_emit_mesh(_kit, STONE_MAT, true)
	_emit_mesh(_glow, _glow_mat, false)


func _process(delta: float) -> void:
	if _light and not Engine.is_editor_hint():
		_flicker_t += delta
		_light.light_energy = 1.7 + 0.25 * sin(_flicker_t * 9.0) + 0.15 * sin(_flicker_t * 23.0 + 1.0)


# --- helpers -------------------------------------------------------------------

func _emit_mesh(kit: MeshKit, mat: Material, shadows: bool) -> void:
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 360.0
	_own(mi)


func _own(n: Node) -> void:
	n.set_meta("_generated", true)
	add_child(n)


func _shape(shape: Shape3D, xform: Transform3D) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	_own(cs)


func _box_shape(center: Vector3, box_size: Vector3, basis := Basis.IDENTITY) -> void:
	var b := BoxShape3D.new()
	b.size = box_size
	_shape(b, Transform3D(basis, center))


func _stone_col(base := Color(-1, 0, 0)) -> Color:
	var c := color if base.r < 0.0 else base
	return c * _rng.randf_range(0.85, 1.12)


## Solid box with matching collision, centred at `center`.
func _solid_box(center: Vector3, box_size: Vector3, basis := Basis.IDENTITY, col := Color(-1, 0, 0)) -> void:
	_kit.add_box(Transform3D(basis, center), box_size, _stone_col(col))
	_box_shape(center, box_size, basis)


# --- kinds -----------------------------------------------------------------------

func _wall() -> void:
	var length := size.x
	var height := size.y
	var thick := size.z
	var segs := maxi(1, int(round(length / 1.3)))
	var seg_len := length / segs
	for i in segs:
		var cut := broken * pow(_rng.randf(), 1.4)
		var h := maxf(height * (1.0 - cut), minf(0.7, height))
		var x := -length * 0.5 + seg_len * (i + 0.5)
		var zoff := _rng.randf_range(-0.04, 0.04)
		_solid_box(Vector3(x, h * 0.5, zoff), Vector3(seg_len + 0.02, h, thick))
		if cut < 0.08:
			_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, h + 0.09, 0)), Vector3(seg_len + 0.05, 0.18, thick + 0.16), _stone_col(STONE_DARK))
		elif _rng.randf() < 0.35:
			_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(x, h + 0.02, zoff)), Vector3(seg_len * 0.9, 0.08, thick * 0.9), MOSS)
	var fallen := int(broken * 4.0 * _rng.randf())
	for i in fallen:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var bs := Vector3(_rng.randf_range(0.5, 0.9), _rng.randf_range(0.3, 0.45), _rng.randf_range(0.4, 0.7))
		var p := Vector3(_rng.randf_range(-length * 0.45, length * 0.45), bs.y * 0.5 - 0.05, side * (thick * 0.5 + _rng.randf_range(0.5, 1.4)))
		_solid_box(p, bs, Basis(Vector3.UP, _rng.randf() * TAU))


func _pillar() -> void:
	var r := size.x * 0.5
	var h := size.y
	_solid_box(Vector3(0, 0.25, 0), Vector3(r * 2.6, 0.5, r * 2.6))
	var shaft_h := h * (1.0 - broken * _rng.randf_range(0.3, 0.8))
	_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), r, r * 0.9, shaft_h - 0.5, 8, _stone_col())
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = shaft_h - 0.5
	_shape(cyl, Transform3D(Basis.IDENTITY, Vector3(0, 0.5 + (shaft_h - 0.5) * 0.5, 0)))
	if broken < 0.2:
		_solid_box(Vector3(0, shaft_h + 0.2, 0), Vector3(r * 2.5, 0.4, r * 2.5))
	else:
		# Jagged break: a few chunks of drum on top.
		for i in 3:
			var a := _rng.randf() * TAU
			_kit.add_box(Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * r * 0.3, shaft_h + 0.1, sin(a) * r * 0.3)),
					Vector3(r * 0.9, _rng.randf_range(0.15, 0.4), r * 0.7), _stone_col())
	if r > 1.5:
		# Large tower stumps get window slits and moss bands for scale.
		for i in 4:
			var a := TAU * i / 4.0 + 0.4
			if shaft_h > 4.0:
				_kit.add_box(Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * r * 0.93, shaft_h * 0.6, sin(a) * r * 0.93)), Vector3(0.25, 1.2, 0.5), Color(0.05, 0.05, 0.06))
		_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)), r * 1.02, r * 1.0, 0.6, 8, MOSS)


func _archway() -> void:
	var w := size.x
	var h := size.y
	var d := size.z
	var pier := 1.0
	for s in [-1.0, 1.0]:
		_solid_box(Vector3(s * (w * 0.5 + pier * 0.5), h * 0.5, 0), Vector3(pier, h, d))
	var r := w * 0.5 + pier * 0.5
	var stones := 9
	var skip := -1
	if broken > 0.6:
		skip = stones / 2
	for i in stones:
		if i == skip:
			continue
		var a0 := PI * float(i) / stones
		var a1 := PI * float(i + 1) / stones
		var am := (a0 + a1) * 0.5
		var c := Vector3(cos(am) * r, h + sin(am) * r * 0.75, 0)
		var basis := Basis(Vector3.BACK, am - PI * 0.5)
		_solid_box(c, Vector3(r * (a1 - a0) * 1.05, pier * 0.95, d), basis)
	# Spandrels fill the corners above the piers.
	for s in [-1.0, 1.0]:
		_solid_box(Vector3(s * (w * 0.5 + pier * 0.5), h + r * 0.45, 0), Vector3(pier * 1.1, r * 0.9, d * 0.95))


func _stairs() -> void:
	var w := size.x
	var rise := size.y
	var run := size.z
	var steps := maxi(2, int(ceil(rise / 0.24)))
	var sh := rise / steps
	var sd := run / steps
	for i in steps:
		var top := sh * (i + 1)
		_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, top * 0.5 - 0.2, sd * (i + 0.5))), Vector3(w, top + 0.4, sd), _stone_col())
	# Smooth ramp collision so the controller glides up instead of catching on steps.
	var hw := w * 0.5
	var ramp := ConvexPolygonShape3D.new()
	ramp.points = PackedVector3Array([
		Vector3(-hw, 0, 0), Vector3(hw, 0, 0), Vector3(-hw, 0, run), Vector3(hw, 0, run),
		Vector3(-hw, rise, run), Vector3(hw, rise, run),
	])
	_shape(ramp, Transform3D.IDENTITY)


func _platform() -> void:
	_solid_box(Vector3(0, size.y * 0.5, 0), size)
	var trim := Vector3(size.x + 0.3, 0.3, size.z + 0.3)
	_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, size.y - 0.15, 0)), trim, _stone_col(STONE_DARK))
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(cx * size.x * 0.5, size.y * 0.5, cz * size.z * 0.5)), Vector3(0.7, size.y + 0.05, 0.7), _stone_col(STONE_DARK))
	_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), Vector3(size.x + 0.15, 0.6, size.z + 0.15), MOSS * 0.9)


func _brazier() -> void:
	_kit.add_cylinder(Transform3D.IDENTITY, 0.32, 0.24, 0.85, 6, _stone_col())
	_kit.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0)), 0.38, 0.52, 0.28, 8, _stone_col(STONE_DARK))
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.45
	cyl.height = 1.15
	_shape(cyl, Transform3D(Basis.IDENTITY, Vector3(0, 0.575, 0)))
	_glow_mat = GLOW_WARM
	_glow.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.4, 1)), Vector3(0, 1.12, 0)), 0.36, Color(0.9, 0.5, 0.3))
	for i in 3:
		var a := TAU * i / 3.0
		_glow.add_cylinder(Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 0.12, 1.12, sin(a) * 0.12)), 0.11, 0.0, 0.45 + 0.1 * i, 4, Color(1, 0.75, 0.4))
	if lit:
		_light = OmniLight3D.new()
		_light.position = Vector3(0, 1.6, 0)
		_light.light_color = Color(1.0, 0.62, 0.32)
		_light.light_energy = 1.8
		_light.omni_range = 10.0
		_light.omni_attenuation = 1.4
		_light.distance_fade_enabled = true
		_light.distance_fade_begin = 70.0
		_light.distance_fade_length = 20.0
		_own(_light)


func _menhir() -> void:
	var tilt := Basis(Vector3(1, 0, 0.3).normalized(), _rng.randf_range(-0.06, 0.06))
	_kit.add_cylinder(Transform3D(tilt * Basis(Vector3.UP, PI * 0.25), Vector3(0, -0.3, 0)), size.x * 0.7, size.x * 0.42, size.y + 0.3, 4, _stone_col(STONE_DARK))
	_box_shape(Vector3(0, size.y * 0.5, 0), Vector3(size.x * 0.9, size.y, size.z * 0.9), tilt)
	for i in 4:
		var y := size.y * (0.3 + 0.15 * i)
		_glow.add_box(Transform3D(tilt, Vector3(0, y, size.z * 0.42 - y * 0.06)), Vector3(size.x * 0.4 * _rng.randf_range(0.5, 1.0), 0.07, 0.04), Color(1, 1, 1))


func _statue() -> void:
	var s := size.y / 2.0
	_solid_box(Vector3(0, 0.2 * s, 0), Vector3(1.3, 0.4, 1.3) * s)
	var lean := Basis(Vector3.RIGHT, -0.35)
	_kit.add_cylinder(Transform3D(lean, Vector3(0, 0.4 * s, 0.1 * s)), 0.5 * s, 0.22 * s, 1.15 * s, 7, _stone_col())
	_kit.add_blob(Transform3D(Basis.IDENTITY, Vector3(0, 1.45 * s, -0.32 * s)), 0.24 * s, _stone_col())
	_kit.add_cylinder(Transform3D(lean, Vector3(0, 1.35 * s, -0.3 * s)), 0.3 * s, 0.0, 0.55 * s, 6, _stone_col(STONE_DARK))
	_kit.add_box(Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0, 0.95 * s, -0.45 * s)), Vector3(0.75, 0.16, 0.5) * s, _stone_col())
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.5 * s
	cyl.height = 1.3 * s
	_shape(cyl, Transform3D(Basis.IDENTITY, Vector3(0, 1.05 * s, 0)))


func _rubble() -> void:
	var count := 6 + _rng.randi_range(0, 4)
	for i in count:
		var a := _rng.randf() * TAU
		var d := _rng.randf() * size.x
		var bs := Vector3(_rng.randf_range(0.4, 1.0), _rng.randf_range(0.25, 0.5), _rng.randf_range(0.4, 0.9)) * (1.2 - d / size.x * 0.6)
		var y := bs.y * 0.4 + (1.0 - d / size.x) * (size.y - 0.4) * 0.6
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.25, 0.25))
		_solid_box(Vector3(cos(a) * d, y, sin(a) * d), bs, basis)


func _fallen_pillar() -> void:
	var r := size.y * 0.5
	var drums := maxi(1, int(size.x / 1.6))
	var drum_len := size.x / drums
	for i in drums:
		var off := Vector3(-size.x * 0.5 + drum_len * i, r * 0.85, _rng.randf_range(-0.15, 0.15))
		var basis := Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12)) * Basis(Vector3.FORWARD, PI * 0.5)
		_kit.add_cylinder(Transform3D(basis, off), r, r * 0.95, drum_len * 0.94, 8, _stone_col())
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = drum_len * 0.94
		_shape(cyl, Transform3D(basis, off + basis * Vector3(0, drum_len * 0.47, 0)))


func _block() -> void:
	_solid_box(Vector3(0, size.y * 0.5, 0), size)
	if broken > 0.3:
		_kit.add_box(Transform3D(Basis.IDENTITY, Vector3(0, size.y + 0.02, 0)), Vector3(size.x * 0.8, 0.05, size.z * 0.7), MOSS)
