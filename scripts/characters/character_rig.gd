class_name CharacterRig
extends Node3D
## Procedural low-poly character: a small pivot skeleton built from MeshKit
## parts, animated in code. Subclasses build parts in _build() and set poses in
## _pose(). Swap for an imported, skinned model later without touching gameplay:
## AvatarVisual only calls play(), hold(), release() and the locomotion fields.

const PROPS_MAT := preload("res://assets/materials/props.tres")
## Render layer for the local player's own body: the local camera skips it,
## lights still see it, so the body casts shadows without blocking the view.
const SELF_LAYER := 1 << 19

## Horizontal speed in m/s, grounded and crouching flags: set every frame.
var move_speed := 0.0
var grounded := true
var crouching := false
## Story pose to hold ("" = plain idle); each rig maps the names it knows.
var mood := ""
## Cast shadows but stay invisible (the local first-person player's own body).
var shadow_only := false:
	set(v):
		shadow_only = v
		_apply_shadow_mode()

var parts := {}
var _rest_pos := {}
var _rest_rot := {}
var _meshes: Array[GeometryInstance3D] = []
var _time := 0.0
var _phase := 0.0
var _one_shot := ""
var _one_t := 0.0
var _one_len := 1.0
var _hold := ""
var _hold_t := 0.0
var _hold_len := 1.0


func _ready() -> void:
	_build()
	for k in parts:
		_rest_pos[k] = parts[k].position
		_rest_rot[k] = parts[k].rotation
	_apply_shadow_mode()


## Starts a one-shot animation (overrides locomotion while it plays).
func play(anim: String, length: float) -> void:
	_one_shot = anim
	_one_t = 0.0
	_one_len = maxf(length, 0.01)


## Holds a pose until release() (wind-ups, airborne, defeated).
func hold(anim: String, length := 1.0) -> void:
	_hold = anim
	_hold_t = 0.0
	_hold_len = maxf(length, 0.01)


func release() -> void:
	_hold = ""


func current_hold() -> String:
	return _hold


func current_one_shot() -> String:
	return _one_shot


func _process(delta: float) -> void:
	_time += delta
	_phase += move_speed * delta * _stride_rate()
	if _one_shot != "":
		_one_t += delta
		if _one_t >= _one_len:
			_one_shot = ""
	_hold_t += delta
	for k in parts:
		parts[k].position = _rest_pos[k]
		parts[k].rotation = _rest_rot[k]
	_pose(delta)


# --- for subclasses ------------------------------------------------------------------------

func _build() -> void:
	pass


func _pose(_delta: float) -> void:
	pass


func _stride_rate() -> float:
	return 1.6


func one_shot_p() -> float:
	return clampf(_one_t / _one_len, 0.0, 1.0)


func hold_p() -> float:
	return clampf(_hold_t / _hold_len, 0.0, 1.0)


func add_part(part_name: String, parent: String, pos: Vector3, rest_rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = part_name
	n.position = pos
	n.rotation = rest_rot
	var p: Node3D = self if parent == "" else parts[parent]
	p.add_child(n)
	parts[part_name] = n
	return n


func add_mesh(part_name: String, kit: MeshKit, mat: Material = PROPS_MAT, shadows := true) -> MeshInstance3D:
	if kit.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = kit.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("casts", shadows)
	var p: Node3D = self if part_name == "" else parts[part_name]
	p.add_child(mi)
	_meshes.append(mi)
	return mi


## Cylinder hanging down from `top` (limbs).
static func cyl_down(kit: MeshKit, top: Vector3, r_top: float, r_bottom: float, length: float, sides: int, col: Color) -> void:
	kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI), top), r_top, r_bottom, length, sides, col)


## Cone pointing along `dir` from `base`.
static func spike(kit: MeshKit, base: Vector3, dir: Vector3, length: float, radius: float, col: Color, sides := 5) -> void:
	var y := dir.normalized()
	var ref := Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	kit.add_cylinder(Transform3D(Basis(x, y, x.cross(y)), base), radius, 0.0, length, sides, col)


func _apply_shadow_mode() -> void:
	for m in _meshes:
		if not is_instance_valid(m):
			continue
		m.layers = SELF_LAYER if shadow_only else 1
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if m.get_meta("casts", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func bell(p: float) -> float:
	return sin(clampf(p, 0.0, 1.0) * PI)
