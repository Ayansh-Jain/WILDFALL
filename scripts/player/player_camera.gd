class_name PlayerCamera
extends RefCounted
## Framing for the Commander's follow camera, and the cinematic hand-over.
##
## PlayerController owns one instance (`cam`) and keeps the wall/terrain-safe orbit;
## this class only decides *how* to frame (offset, field of view, downward tilt) and
## when something else is allowed to hold the view. It never turns the player's view.
##
## Hooks for later work: `impact()` (parries, heavy hits, finishers), `emphasize()`
## (boss introductions), `begin_cinematic()` / `end_cinematic()` (authored camera tracks).

signal mode_changed(mode: int)
signal cinematic_finished(owner_id: String)

enum Mode { EXPLORE, SPRINT, COMBAT, HALL, TIGHT, SIT, MOUNTED, GALLOP }

## Seconds the combat framing lingers after the last blow.
const COMBAT_LINGER := 3.5
## A campaign enemy this close brings up the combat framing before the first blow.
const THREAT_RADIUS := 11.0
const SENSE_INTERVAL := 0.2

var player: PlayerController
var mode: int = Mode.EXPLORE
var offset := Vector3.ZERO  ## right, up, back (metres) from the pivot
var fov_bonus := 0.0
var pitch_bias := 0.0  ## radians

var _snap := true
var _sense_t := 0.0
var _ceiling := INF
var _roof_votes := 0
var _roof_state := 0  ## 0 open, 1 hall, 2 tight
var _threat := false
var _combat_t := 0.0
var _shake := 0.0
var _shake_t := 0.0
var _punch := 0.0
var _emph_t := 0.0
var _emph_scale := 1.0
var _emph_fov := 0.0

var _cine: Camera3D
var _cine_owner := ""
var _cine_token := 0
var _blend_t := -1.0
var _blend_len := 0.0
var _blend_from := Transform3D()
var _blend_fov := 75.0


func _init(p: PlayerController) -> void:
	player = p


## Jump straight to the target framing (teleport, respawn, scene entry).
func snap() -> void:
	_snap = true
	_sense_t = 0.0
	_combat_t = 0.0
	_punch = 0.0
	_emph_t = 0.0


## Frame-rate independent blend factor.
static func blend(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


func mode_name() -> String:
	return Mode.keys()[mode]


## The framing each mode wants: [offset, fov bonus (deg), downward tilt (deg)].
func profile(m: int) -> Array:
	var on_foot := player.third_person_offset
	var mounted := player.riding_camera_offset
	var bias := player.third_person_pitch_bias
	match m:
		Mode.SPRINT:
			return [on_foot * Vector3(0.8, 0.9, 1.12), player.sprint_fov_bonus, bias - 1.0]
		Mode.COMBAT:
			# Higher, wider and tilted down so wind-ups around the Commander stay readable.
			return [on_foot * Vector3(1.35, 1.6, 1.14), 4.0, bias + 4.0]
		Mode.HALL:
			return [on_foot * Vector3(0.9, 0.8, 0.76), 2.0, bias - 1.0]
		Mode.TIGHT:
			return [on_foot * Vector3(0.8, 0.5, 0.58), 5.0, bias - 2.0]
		Mode.SIT:
			return [on_foot * Vector3(1.2, 0.9, 0.92), -3.0, bias - 2.0]
		Mode.MOUNTED:
			return [mounted, 0.0, 5.0]
		Mode.GALLOP:
			return [mounted * Vector3(0.6, 1.14, 1.14), 7.0, 6.0]
		_:
			return [on_foot, 0.0, bias]


func update(delta: float) -> void:
	_sense_t -= delta
	if _sense_t <= 0.0:
		_sense_t = SENSE_INTERVAL
		_sense()
	_combat_t = maxf(0.0, _combat_t - delta)
	var m := _pick_mode()
	if m != mode:
		mode = m
		mode_changed.emit(m)

	var want: Array = profile(mode)
	var want_offset: Vector3 = want[0] * Vector3(1.0, 1.0, Settings.camera_distance)
	var want_fov: float = 0.0 if Settings.reduce_motion else float(want[1])
	var want_bias := deg_to_rad(float(want[2]))
	if _emph_t > 0.0:
		_emph_t -= delta
		want_offset.z *= _emph_scale
		if not Settings.reduce_motion:
			want_fov += _emph_fov
	if _snap:
		_snap = false
		offset = want_offset
		fov_bonus = want_fov
		pitch_bias = want_bias
	else:
		# Pull out for a fight or a gallop quickly; settle back more gently.
		var rate := 5.0 if mode in [Mode.COMBAT, Mode.TIGHT, Mode.HALL] else 2.8
		offset = offset.lerp(want_offset, blend(rate, delta))
		fov_bonus = lerpf(fov_bonus, want_fov, blend(5.0, delta))
		pitch_bias = lerpf(pitch_bias, want_bias, blend(3.0, delta))
	_punch = lerpf(_punch, 0.0, blend(9.0, delta))
	_apply_shake(delta)


## Field of view the follow camera should show this frame (degrees).
func target_fov(form_bonus: float) -> float:
	return Settings.fov + form_bonus + fov_bonus + (0.0 if Settings.reduce_motion else _punch)


# --- effects --------------------------------------------------------------------------------

func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func shake_amount() -> float:
	return 0.0 if Settings.reduce_motion else _shake * Settings.camera_shake


## A short jolt for a parry, heavy hit or finisher (strength 0..1).
func impact(strength: float) -> void:
	add_shake(0.8 * clampf(strength, 0.0, 1.0))
	_punch = -4.0 * clampf(strength, 0.0, 1.0)


## Temporarily changes the framing (distance multiplier, FOV delta) without taking the
## camera or turning it: boss introductions, finishers, story beats.
func emphasize(seconds: float, distance_scale: float, fov_delta := 0.0) -> void:
	_emph_t = seconds
	_emph_scale = clampf(distance_scale, 0.4, 1.8)
	_emph_fov = clampf(fov_delta, -20.0, 20.0)


func _apply_shake(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 2.5)
	_shake_t += delta
	var a := shake_amount() * 0.05
	player.camera.h_offset = (sin(_shake_t * 47.0) + sin(_shake_t * 29.0)) * 0.5 * a
	player.camera.v_offset = (sin(_shake_t * 41.0 + 1.7) + sin(_shake_t * 23.0)) * 0.5 * a


# --- sensing --------------------------------------------------------------------------------

func _pick_mode() -> int:
	if player.riding:
		var rider := player.get_node_or_null("Rider") as Rider
		var h: Horse = rider.horse if rider else null
		if h and (h.gait == Horse.Gait.GALLOP or (mode == Mode.GALLOP and h.gait == Horse.Gait.CANTER)):
			return Mode.GALLOP
		return Mode.MOUNTED
	if player.is_sitting:
		return Mode.SIT
	if _roof_state == 2:
		return Mode.TIGHT
	if _combat_t > 0.0:
		return Mode.COMBAT
	if _roof_state == 1:
		return Mode.HALL
	if player.is_sprinting and player.ground_speed() > player.walk_speed:
		return Mode.SPRINT
	return Mode.EXPLORE


## Cheap, throttled look at the surroundings: one ray up, and the nearby fighters.
func _sense() -> void:
	if not player.is_inside_tree():
		return
	var from := player.global_position + Vector3.UP * 1.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 14.0, Layers.WORLD, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	_ceiling = INF if hit.is_empty() else float(hit["position"].y) - player.global_position.y
	if player.is_underground(from):
		_ceiling = minf(_ceiling, 3.2)
	var state := 0
	if _ceiling < 3.7:
		state = 2
	elif _ceiling < INF:
		state = 1
	# Two agreeing samples before switching, so a beam or a doorway does not pump the view.
	if state == _roof_state:
		_roof_votes = 0
	else:
		_roof_votes += 1
		if _roof_votes >= 2 or _snap:
			_roof_state = state
			_roof_votes = 0

	_threat = _enemy_near()
	var recent := Combat.now() - player.combatant.last_combat_time < COMBAT_LINGER and player.combatant.last_combat_time > 0.0
	if _threat or recent or Combat.is_busy(player.player_id):
		_combat_t = maxf(_combat_t, SENSE_INTERVAL * 2.0 if not _threat else 1.0)


func _enemy_near() -> bool:
	var id := player.player_id
	if id < 0:
		return false
	for other in Combat.actor_ids():
		if other == id or Combat.team_of(other) == "" or not Combat.are_hostile(id, other):
			continue
		var av: PlayerController = Combat.avatar(other)
		if av and not av.is_defeated and av.global_position.distance_squared_to(player.global_position) < THREAT_RADIUS * THREAT_RADIUS:
			return true
	return false


# --- cinematic hand-over --------------------------------------------------------------------

func in_cinematic() -> bool:
	return _cine_owner != ""


## Gives `owner_id` its own current camera (starting at the player's view) and holds the
## Commander still. Returns null if someone else holds the view.
func begin_cinematic(owner_id: String) -> Camera3D:
	if owner_id == "" or (_cine_owner != "" and _cine_owner != owner_id):
		return null
	if _cine == null or not is_instance_valid(_cine):
		_cine = Camera3D.new()
		_cine.name = "CinematicCamera"
		_cine.top_level = true
		player.add_child(_cine)
	if _cine_owner == "":
		_cine.global_transform = player.camera.global_transform
		_cine.fov = player.camera.fov
		_cine.near = player.camera.near
		_cine.far = player.camera.far
		_cine.cull_mask = player.camera.cull_mask | CharacterRig.SELF_LAYER
		_cine_token = player.locks.acquire("cinematic:" + owner_id, ControlLock.MOVE | ControlLock.COMBAT | ControlLock.INTERACT | ControlLock.CAMERA | ControlLock.MOUNT)
	_cine_owner = owner_id
	_blend_t = -1.0
	_cine.make_current()
	return _cine


## Returns the view to the follow camera, blending over `seconds`.
func end_cinematic(owner_id: String, seconds := 0.6) -> bool:
	if _cine_owner == "" or owner_id != _cine_owner:
		return false
	if seconds <= 0.0 or Settings.reduce_motion:
		abort_cinematic()
		return true
	_blend_t = 0.0
	_blend_len = seconds
	_blend_from = _cine.global_transform
	_blend_fov = _cine.fov
	return true


## Immediate, unconditional return of the view and of control (defeat, scene exit).
func abort_cinematic() -> void:
	if _cine_owner == "":
		return
	var who := _cine_owner
	_cine_owner = ""
	_blend_t = -1.0
	player.locks.release(_cine_token)
	_cine_token = 0
	player.camera.make_current()
	cinematic_finished.emit(who)


## Advances the return blend; call after the follow camera has been placed.
func update_cinematic(delta: float) -> void:
	if _blend_t < 0.0:
		return
	_blend_t += delta
	var k := smoothstep(0.0, 1.0, clampf(_blend_t / _blend_len, 0.0, 1.0))
	_cine.global_transform = _blend_from.interpolate_with(player.camera.global_transform, k)
	_cine.fov = lerpf(_blend_fov, player.camera.fov, k)
	if _blend_t >= _blend_len:
		abort_cinematic()
