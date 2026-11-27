class_name GoldenValleyShowcase
extends Node3D
## Playable cinematic environment showcase ("Silverrun / Golden Valley").
## Demonstrates Ghost-of-Tsushima-inspired composition, layered PBR terrain,
## wind-swept golden grass fields, flowing river & waterfall, arched stone bridge,
## riverside hamlet & watchtower, distant mountain silhouettes, Atmosphere
## profiles (C-14), and Codex battlefield wf_marker nodes (C-13).

signal showcase_ready

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HORSE_SCENE := preload("res://scenes/horse/horse.tscn")
const TERRAIN_MAT := preload("res://assets/materials/terrain.tres")
const WATER_MAT := preload("res://assets/materials/water.tres")
const WATERFALL_SHADER := preload("res://assets/materials/waterfall.gdshader")
const DISTANT_MOUNTAIN_MAT := preload("res://assets/materials/distant_mountain.tres")
const STONE_MAT := preload("res://assets/materials/stone.tres")
const PROPS_MAT := preload("res://assets/materials/props.tres")
const HOUSE_MAT := preload("res://assets/materials/village_props.tres")
const GLOW_WARM := preload("res://assets/materials/glow_warm.tres")
const SKY_MAT := preload("res://assets/materials/sky.tres")

const HALF_SIZE := 280.0
const CELL := 2.0
const CHUNK_CELLS := 35
const WATER_LEVEL := 0.0

@export var spawn_player := true
@export var spawn_horse := true
@export var auto_capture_mouse := false
@export var initial_profile := "golden_day"

var td: TerrainData
var layout: WorldLayout
var player: PlayerController
var horse: Horse
var atmosphere: Atmosphere
var water_wheel: MeshInstance3D
var wind_particles: CPUParticles3D
var _lamps: Array[Light3D] = []
var _flicker: Array[Dictionary] = []
var _flicker_t := 0.0
var _scenic_cams: Array[Dictionary] = []
var _scenic_idx := -1
var _scenic_cam: Camera3D
var _hud_label: Label
var _hud_layer: CanvasLayer
var _fps_accum := 0.0
var _fps_frames := 0
var _fps_display := 0.0

@onready var sun: DirectionalLight3D = $Sun
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var terrain_node: Terrain = $Terrain
@onready var structures_root: Node3D = $Structures
@onready var vegetation_root: Node3D = $Vegetation
@onready var markers_root: Node3D = $WorldMarkers


func _ready() -> void:
	_build_showcase()
	if spawn_player:
		_spawn_actors()
		_setup_hud()
	if auto_capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	showcase_ready.emit()


func _process(delta: float) -> void:
	if is_instance_valid(water_wheel):
		water_wheel.rotate_z(-delta * 0.95)
	if is_instance_valid(wind_particles) and is_instance_valid(player):
		var target_pos := player.global_position + Vector3(0, 3.5, 0)
		wind_particles.global_position = wind_particles.global_position.lerp(target_pos, clampf(delta * 2.5, 0.0, 1.0))
	_flicker_t += delta
	for f in _flicker:
		var light := f["light"] as Light3D
		if is_instance_valid(light) and light.visible:
			var base := float(f["base"])
			var ph := float(f["phase"])
			light.light_energy = base * (1.0 + 0.08 * sin(_flicker_t * 8.1 + ph) + 0.05 * sin(_flicker_t * 17.5 + ph * 2.3))
	if _hud_label:
		_fps_accum += delta
		_fps_frames += 1
		if _fps_accum >= 0.4:
			_fps_display = float(_fps_frames) / _fps_accum
			_fps_accum = 0.0
			_fps_frames = 0
			_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			apply_profile("golden_day", 1.2)
		KEY_2:
			apply_profile("atmospheric_evening", 1.2)
		KEY_3:
			apply_profile("moonlit_night", 1.2)
		KEY_4:
			apply_profile("misty_valley", 1.2)
		KEY_H:
			if is_instance_valid(horse) and is_instance_valid(player):
				horse.come_to(player.global_position + player.global_transform.basis.x * 2.5)
		KEY_F9:
			_cycle_scenic_camera()
		KEY_0:
			_restore_player_camera()
		KEY_F2:
			if _hud_layer:
				_hud_layer.visible = not _hud_layer.visible


func apply_profile(profile_id: String, fade_s: float = 0.8) -> Dictionary:
	if atmosphere == null:
		return {"ok": false, "reason": "no_atmosphere", "data": {}}
	var res := atmosphere.apply(profile_id, fade_s)
	_sync_distant_mountains_to_env()
	_refresh_hud()
	return res


func _sync_distant_mountains_to_env() -> void:
	if world_env and world_env.environment:
		var env := world_env.environment
		var sky_h := Color(0.68, 0.74, 0.80)
		if SKY_MAT:
			var hc = SKY_MAT.get_shader_parameter("horizon_color")
			if hc is Color:
				sky_h = hc
		DISTANT_MOUNTAIN_MAT.set_shader_parameter("haze_color", env.fog_light_color.lerp(sky_h, 0.42))
		var is_night := atmosphere and atmosphere.current() == "moonlit_night"
		DISTANT_MOUNTAIN_MAT.set_shader_parameter("foothill_color", Color(0.06, 0.09, 0.12) if is_night else Color(0.15, 0.22, 0.14))
		DISTANT_MOUNTAIN_MAT.set_shader_parameter("ridge_color", Color(0.18, 0.22, 0.30) if is_night else Color(0.36, 0.39, 0.44))


# --- Build Showcase -----------------------------------------------------------

func _build_showcase() -> void:
	_setup_layout_and_terrain_data()
	terrain_node.build(td)
	_build_water()
	_build_waterfall()
	_build_distant_mountains()
	_build_bridge()
	_build_watchtower()
	_build_hamlet()
	_build_combat_clearing_ruins()
	_build_overlook_trailhead()
	_build_vegetation()
	_build_wind_particles()
	_build_markers()
	_setup_scenic_cameras()

	atmosphere = Atmosphere.new()
	atmosphere.name = "Atmosphere"
	add_child(atmosphere)
	atmosphere.bind_environment(world_env.environment, sun, SKY_MAT)
	atmosphere.register_lamps(_lamps)
	atmosphere.apply(initial_profile, 0.0)
	_sync_distant_mountains_to_env()


func _setup_layout_and_terrain_data() -> void:
	layout = WorldLayout.new()
	layout.half_size = HALF_SIZE
	layout.playable_half = 248.0
	layout.cell = CELL
	layout.water_level = WATER_LEVEL
	layout.base_height = 4.0
	layout.chunk_cells = CHUNK_CELLS
	layout.data = {
		"world": {"half_size": HALF_SIZE, "playable_half": 248.0, "cell": CELL, "water_level": WATER_LEVEL, "base_height": 4.0, "chunk_cells": CHUNK_CELLS},
		"bridges": [{"name": "SilverrunStoneBridge", "style": "stone", "a": [16.0, 22.0], "b": [52.0, 10.0], "width": 4.6}],
		"rivers": [{"name": "SilverrunValley", "half_width": 7.5, "depth": 2.6, "bank": 10.0,
			"points": [[-18, -190], [-18, -155], [-6, -105], [14, -40], [34, 16], [62, 82], [108, 160], [164, 250]]}],
		"trails": [
			{"name": "OverlookToBridge", "half_width": 2.6, "points": [[-148, 122], [-115, 96], [-84, 68], [-48, 42], [-12, 29], [16, 22]]},
			{"name": "BridgeToClearing", "half_width": 2.6, "points": [[52, 10], [78, 4], [98, -12], [114, -36]]},
			{"name": "HamletSpur", "half_width": 2.0, "points": [[68, 8], [84, 18], [94, 34]]},
			{"name": "ForestGroveTrail", "half_width": 2.0, "points": [[-48, 42], [-64, 10], [-82, -28], [-104, -68]]},
		],
	}

	td = TerrainData.new()
	td.layout = layout
	td.cell = CELL
	td.origin = -HALF_SIZE
	td.water_level = WATER_LEVEL
	td.n = int(round(HALF_SIZE * 2.0 / CELL)) + 1
	var count := td.n * td.n
	td.heights.resize(count)
	td.trail_dist.resize(count)
	td.trail_dist.fill(1e6)
	td.forest.resize(count)
	td.forest.fill(0.0)
	td.wet.resize(count)
	td.wet.fill(0.0)
	td.paving.resize(count)
	td.paving.fill(0.0)
	td.water_influence.resize(count)
	td.water_influence.fill(0.0)
	td.holes.resize((td.n - 1) * (td.n - 1))
	td.holes.fill(0)

	var nb := FastNoiseLite.new()
	nb.seed = 20261
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nb.frequency = 1.0 / 165.0
	nb.fractal_octaves = 4

	var nr := FastNoiseLite.new()
	nr.seed = 20267
	nr.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nr.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	nr.frequency = 1.0 / 72.0
	nr.fractal_octaves = 3

	var nf := FastNoiseLite.new()
	nf.seed = 20273
	nf.frequency = 1.0 / 55.0
	nf.fractal_octaves = 3

	# Stamp trails first so hills/bluffs remain rideable along the route.
	for t in layout.list("trails"):
		var pts := WorldLayout.points(t["points"])
		var hw := float(t["half_width"])
		for s in pts.size() - 1:
			var a := pts[s]
			var b := pts[s + 1]
			_for_verts_near(a, b, hw + 9.0, func(k: int, x: float, z: float) -> void:
				var d := TerrainData.seg_dist(Vector2(x, z), a, b) - hw
				if d < td.trail_dist[k]:
					td.trail_dist[k] = d)

	# Sculpt natural valley geography: ridges, rolling hills, waterfall gorge, clearing.
	for j in td.n:
		var z := td.vx(j)
		for i in td.n:
			var x := td.vx(i)
			var k := td.idx(i, j)
			var p2 := Vector2(x, z)
			var on_trail := 1.0 - smoothstep(0.0, 7.0, td.trail_dist[k])

			var broad := nb.get_noise_2d(x, z) * 4.5
			var ridge := (nr.get_noise_2d(x, z) * 0.5 + 0.5)
			var h := 3.6 + broad * (1.0 - 0.35 * on_trail)

			# Broad valley walls: high scenic ridges framing NW, SW overlook, and SE hills.
			h += _hill(p2, Vector2(-162, 128), 78.0, 14.5, 0.15, ridge, on_trail) # Overlook ridge
			h += _hill(p2, Vector2(-165, -135), 115.0, 26.0, 0.55, ridge, on_trail) # NW Forest Mountain
			h += _hill(p2, Vector2(-22, -210), 95.0, 24.5, 0.75, ridge, on_trail) # Waterfall Gorge Rim
			h += _hill(p2, Vector2(95, -185), 95.0, 22.0, 0.65, ridge, on_trail) # NE Crags
			h += _hill(p2, Vector2(-46, -94), 34.0, 9.5, 0.45, ridge, on_trail) # Watchtower Bluff
			h += _hill(p2, Vector2(195, 130), 105.0, 20.0, 0.45, ridge, on_trail) # SE Valley Ridge
			h += _hill(p2, Vector2(-190, 10), 85.0, 17.5, 0.35, ridge, on_trail) # West Valley Wall

			# Gentle flatten around Hamlet (84, 18) and Combat Clearing (118, -42)
			var d_hamlet := p2.distance_to(Vector2(84, 18))
			if d_hamlet < 32.0:
				var hw := 1.0 - smoothstep(14.0, 32.0, d_hamlet)
				h = lerpf(h, 3.2, hw * 0.85)
				if d_hamlet < 12.0:
					td.paving[k] = maxf(td.paving[k], 0.55 * (1.0 - smoothstep(6.0, 12.0, d_hamlet)))

			var d_clear := p2.distance_to(Vector2(118, -42))
			if d_clear < 48.0:
				var cw := 1.0 - smoothstep(26.0, 48.0, d_clear)
				h = lerpf(h, 4.4, cw * 0.88)

			# Outer rim rise near map edge so cliffs transition cleanly to horizon mesh.
			var edge := maxf(absf(x), absf(z))
			if edge > 235.0:
				var et := smoothstep(235.0, 280.0, edge)
				h += (12.0 + ridge * 14.0) * et * (1.0 - 0.6 * on_trail)

			td.heights[k] = maxf(h, 1.0)

	# Flatten bridge approaches & watchtower terrace.
	for b in layout.list("bridges"):
		for key in ["a", "b"]:
			var bp := WorldLayout.v2(b[key])
			_flatten_area(bp, 4.2, 6.0, 2.3)
	_flatten_area(Vector2(-44, -92), 7.0, 8.0, 13.8, 0.7)

	# Carve river & waterfall plunge pool.
	var rpts := WorldLayout.points(layout.list("rivers")[0]["points"])
	var rdist := PackedFloat32Array()
	rdist.resize(count)
	rdist.fill(1e6)
	for s in rpts.size() - 1:
		var a := rpts[s]
		var b := rpts[s + 1]
		_for_verts_near(a, b, 20.0, func(k: int, x: float, z: float) -> void:
			var d := TerrainData.seg_dist(Vector2(x, z), a, b)
			if d < rdist[k]:
				rdist[k] = d)
	for k in count:
		var x := td.vx(k % td.n)
		var z := td.vx(k / td.n)
		var p2 := Vector2(x, z)
		# Keep upper waterfall cliff above z < -166 elevated!
		if z < -166.0:
			var wf_d := absf(x + 18.0)
			if wf_d < 12.0:
				var fall_t := smoothstep(-166.0, -186.0, z)
				var channel := lerpf(2.0, 20.5, fall_t)
				td.heights[k] = minf(td.heights[k], channel + wf_d * 0.55)
			continue
		var d := rdist[k]
		var pool_d := p2.distance_to(Vector2(-18, -148))
		var eff_hw := 15.0 if pool_d < 22.0 else 7.5
		if d < eff_hw + 11.0 or pool_d < 26.0:
			var dist_bank := minf(d, pool_d - 6.0)
			var target := WATER_LEVEL - 0.45
			if dist_bank < eff_hw:
				target = WATER_LEVEL - 0.45 - 2.3 * (1.0 - clampf((dist_bank * dist_bank) / (eff_hw * eff_hw), 0.0, 1.0))
			else:
				var t := smoothstep(eff_hw, eff_hw + 11.0, dist_bank)
				target = lerpf(WATER_LEVEL - 0.45, td.heights[k], t)
			td.heights[k] = minf(td.heights[k], target)
			var wi := 1.0 - smoothstep(eff_hw, eff_hw + 11.0, dist_bank)
			td.water_influence[k] = maxf(td.water_influence[k], wi)
			td.wet[k] = maxf(td.wet[k], 1.0 - smoothstep(eff_hw - 1.0, eff_hw + 5.0, dist_bank))

	# Smooth trails gently for smooth horseback gallop.
	_grade_showcase_trails()

	# Paint forest density zones: Whispering Grove NW, East woods behind clearing, South ridge.
	var fzones := [
		[Vector2(-108, -78), 88.0, 0.85],
		[Vector2(-175, 25), 62.0, 0.58],
		[Vector2(185, 95), 75.0, 0.72],
		[Vector2(175, -135), 72.0, 0.65],
		[Vector2(28, -120), 48.0, 0.52],
	]
	for k in count:
		var x := td.vx(k % td.n)
		var z := td.vx(k / td.n)
		var p2 := Vector2(x, z)
		var dens := 0.06
		for fz in fzones:
			var d := p2.distance_to(fz[0])
			if d < fz[1]:
				dens = maxf(dens, float(fz[2]) * (1.0 - smoothstep(float(fz[1]) * 0.48, float(fz[1]), d)))
		# Carve open golden valley meadows, hamlet, watchtower bluff, and combat clearing!
		var clearings := [
			[Vector2(-148, 122), 26.0, 12.0],
			[Vector2(-68, 56), 44.0, 18.0],
			[Vector2(20, 20), 28.0, 12.0],
			[Vector2(84, 18), 32.0, 14.0],
			[Vector2(118, -42), 40.0, 14.0],
			[Vector2(-44, -92), 18.0, 8.0],
		]
		for cl in clearings:
			var dc := p2.distance_to(cl[0])
			if dc < float(cl[1]) + float(cl[2]):
				dens *= smoothstep(float(cl[1]), float(cl[1]) + float(cl[2]), dc)
		dens *= clampf(0.6 + nf.get_noise_2d(x, z) * 0.9, 0.0, 1.2)
		dens *= smoothstep(0.0, 3.8, td.trail_dist[k])
		dens *= smoothstep(WATER_LEVEL + 0.6, WATER_LEVEL + 1.8, td.heights[k])
		dens *= 1.0 - smoothstep(24.0, 34.0, td.heights[k])
		td.forest[k] = clampf(dens, 0.0, 1.0)

	PlayerController.terrain_height_query = td.height_at
	PlayerController.terrain_hole_query = td.is_hole_at


func _hill(p: Vector2, center: Vector2, radius: float, height: float, rocky: float, ridge: float, on_trail: float) -> float:
	var d2 := p.distance_squared_to(center)
	if d2 >= radius * radius:
		return 0.0
	var f := 1.0 - d2 / (radius * radius)
	f *= f
	return height * f * (1.0 + rocky * (1.0 - on_trail) * (ridge - 0.45) * 0.75)


func _flatten_area(center: Vector2, radius: float, blend: float, target: float, pave := 0.0) -> void:
	var r_out := radius + blend
	_for_verts_near(center, center, r_out, func(k: int, x: float, z: float) -> void:
		var d := Vector2(x, z).distance_to(center)
		if d >= r_out:
			return
		var w := 1.0 - smoothstep(radius, r_out, d)
		td.heights[k] = lerpf(td.heights[k], target, w)
		if pave > 0.0:
			td.paving[k] = maxf(td.paving[k], pave * (1.0 - smoothstep(radius * 0.7, radius, d))))


func _grade_showcase_trails() -> void:
	var src := td.heights.duplicate()
	var r := 3
	for j in range(r, td.n - r):
		for i in range(r, td.n - r):
			var k := td.idx(i, j)
			if td.trail_dist[k] > 5.5 or td.heights[k] < WATER_LEVEL + 0.4:
				continue
			var sum := 0.0
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					sum += src[td.idx(i + di, j + dj)]
			var avg := sum / float((2 * r + 1) * (2 * r + 1))
			td.heights[k] = lerpf(src[k], avg, 0.8 * (1.0 - smoothstep(0.0, 5.5, td.trail_dist[k])))


func _for_verts_near(a: Vector2, b: Vector2, r: float, fn: Callable) -> void:
	var i0 := clampi(int(floor((minf(a.x, b.x) - r - td.origin) / td.cell)), 0, td.n - 1)
	var i1 := clampi(int(ceil((maxf(a.x, b.x) + r - td.origin) / td.cell)), 0, td.n - 1)
	var j0 := clampi(int(floor((minf(a.y, b.y) - r - td.origin) / td.cell)), 0, td.n - 1)
	var j1 := clampi(int(ceil((maxf(a.y, b.y) + r - td.origin) / td.cell)), 0, td.n - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			fn.call(td.idx(i, j), td.vx(i), td.vx(j))


# --- Water & Waterfall --------------------------------------------------------

func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * HALF_SIZE * 2.0
	plane.material = WATER_MAT
	var mi := MeshInstance3D.new()
	mi.name = "RiverWater"
	mi.mesh = plane
	mi.position.y = WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# Bake 256x256 shore depth + river flow map.
	var sz := 256
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var rpts := WorldLayout.points(layout.list("rivers")[0]["points"])
	var segs: Array = []
	for i in rpts.size() - 1:
		segs.append([rpts[i], rpts[i + 1], (rpts[i + 1] - rpts[i]).normalized(), 18.0])
	var wf_bot := Vector2(-18, -155)
	for py in sz:
		var z := lerpf(-HALF_SIZE, HALF_SIZE, (float(py) + 0.5) / float(sz))
		for px in sz:
			var x := lerpf(-HALF_SIZE, HALF_SIZE, (float(px) + 0.5) / float(sz))
			var h := td.height_at(x, z)
			var depth := clampf((WATER_LEVEL - h) / 2.8, 0.0, 1.0)
			var flow := Vector2.ZERO
			var rapids := 0.0
			var p2 := Vector2(x, z)
			for seg in segs:
				var d := TerrainData.seg_dist(p2, seg[0], seg[1])
				if d < seg[3]:
					var w := 1.0 - smoothstep(6.0, seg[3], d)
					flow += (seg[2] as Vector2) * w
					rapids = maxf(rapids, 0.35 * w)
			var d_wf := p2.distance_to(wf_bot)
			if d_wf < 24.0:
				rapids = maxf(rapids, 1.0 - smoothstep(4.0, 24.0, d_wf))
			if flow.length_squared() > 0.001:
				flow = flow.normalized() * 0.85
			img.set_pixel(px, py, Color(depth, flow.x * 0.5 + 0.5, flow.y * 0.5 + 0.5, clampf(rapids, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	WATER_MAT.set_shader_parameter("shore_map", tex)
	WATER_MAT.set_shader_parameter("map_half_size", HALF_SIZE)
	WATER_MAT.set_shader_parameter("use_shore_map", 1.0)


func _build_waterfall() -> void:
	var top := Vector2(-18, -182)
	var bottom := Vector2(-18, -155)
	var steps := 14
	var width := 12.0
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in steps + 1:
		var t := float(i) / steps
		var p := top.lerp(bottom, t)
		var y := maxf(td.height_at(p.x, p.y) + 0.65, WATER_LEVEL + 0.05)
		verts.append(Vector3(p.x - width * 0.5, y, p.y))
		verts.append(Vector3(p.x + width * 0.5, y, p.y))
		uvs.append(Vector2(0, t))
		uvs.append(Vector2(1, t))
		if i < steps:
			var b := i * 2
			idx.append_array([b, b + 1, b + 3, b, b + 3, b + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = WATERFALL_SHADER
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "ValleyWaterfall"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	structures_root.add_child(mi)

	var foam := CPUParticles3D.new()
	foam.name = "WaterfallMist"
	foam.position = Vector3(bottom.x, WATER_LEVEL + 0.5, bottom.y + 1.5)
	foam.amount = 36
	foam.lifetime = 2.4
	foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	foam.emission_box_extents = Vector3(width * 0.5, 0.4, 1.8)
	foam.direction = Vector3(0, 1, 0.4)
	foam.spread = 45.0
	foam.initial_velocity_min = 0.8
	foam.initial_velocity_max = 2.2
	foam.gravity = Vector3(0, -1.0, 0)
	var fm := QuadMesh.new()
	fm.size = Vector2(3.0, 3.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_texture = Sites._soft_mist_texture()
	fmat.albedo_color = Color(0.86, 0.93, 0.95, 0.34)
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fm.material = fmat
	foam.mesh = fm
	structures_root.add_child(foam)

	# Framing cliff boulders grounded firmly into the gorge walls.
	var cliffs := MeshKit.new(3301, 0.08)
	for sx: float in [-1.0, 1.0]:
		for step in 3:
			var cx := bottom.x + sx * (8.5 + step * 5.0)
			var cz := bottom.y - 5.0 - step * 8.0
			var cy := td.height_at(cx, cz)
			cliffs.add_blob(Transform3D(Basis(Vector3.UP, sx * 0.7 + step).scaled(Vector3(4.0, 4.4, 3.6)), Vector3(cx, cy - 0.6, cz)), 1.0, PropMeshes.ROCK * 0.84, true, 0.3)
	var cmi := MeshInstance3D.new()
	cmi.name = "WaterfallGorgeCliffs"
	cmi.mesh = cliffs.to_mesh(PropMeshes.ROCK_MAT)
	structures_root.add_child(cmi)


# --- Distant Mountain Silhouettes --------------------------------------------

func _build_distant_mountains() -> void:
	var rings: Array[float] = [-4.0, 18.0, 65.0, 145.0, 260.0, 430.0, 680.0, 1020.0, 1480.0]
	var per_side := 56
	var count := per_side * 4
	var noise := FastNoiseLite.new()
	noise.seed = 9901
	noise.frequency = 1.0 / 320.0
	noise.fractal_octaves = 4
	var ridge := FastNoiseLite.new()
	ridge.seed = 9907
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.frequency = 1.0 / 380.0
	ridge.fractal_octaves = 4

	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for ri in rings.size():
		var s := HALF_SIZE + rings[ri]
		for i in count:
			var p := _ring_point(i, per_side, s)
			var h := _mountain_height(p, rings[ri], noise, ridge, ri == 0)
			var woods := clampf(1.0 - smoothstep(14.0, 48.0, h), 0.0, 0.8)
			verts.append(Vector3(p.x, h, p.y))
			cols.append(Color(0.0, woods, 0.0, 0.0))
	var idx := PackedInt32Array()
	for ri in rings.size() - 1:
		for i in count:
			var a := ri * count + i
			var b := ri * count + (i + 1) % count
			var c := (ri + 1) * count + (i + 1) % count
			var d := (ri + 1) * count + i
			idx.append_array([a, c, b, a, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, DISTANT_MOUNTAIN_MAT)
	var mi := MeshInstance3D.new()
	mi.name = "DistantMountains"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 400.0
	structures_root.add_child(mi)


func _ring_point(i: int, per_side: int, s: float) -> Vector2:
	var side := i / per_side
	var f := float(i % per_side) / per_side
	match side:
		0: return Vector2(lerpf(-s, s, f), -s)
		1: return Vector2(s, lerpf(-s, s, f))
		2: return Vector2(lerpf(s, -s, f), s)
	return Vector2(-s, lerpf(s, -s, f))


func _mountain_height(p: Vector2, beyond: float, noise: FastNoiseLite, ridge: FastNoiseLite, inner: bool) -> float:
	var edge := Vector2(clampf(p.x, -HALF_SIZE, HALF_SIZE), clampf(p.y, -HALF_SIZE, HALF_SIZE))
	var edge_h := td.height_at(edge.x, edge.y)
	if inner:
		return edge_h - 1.5
	var t := clampf(beyond / 1480.0, 0.0, 1.0)
	var nval := noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	var rval := clampf(ridge.get_noise_2d(p.x, p.y) * 0.5 + 0.5, 0.0, 1.0)
	# Keep a scenic valley saddle to the NE (sunlight window) while raising tall northern/western ranges.
	var north_bias := smoothstep(60.0, -350.0, p.y)
	var saddle := 1.0 - 0.55 * exp(-pow((atan2(p.x, -p.y) - 0.85) * 2.2, 2.0))
	var far := (22.0 + nval * 48.0 + (70.0 + rval * 155.0) * smoothstep(0.18, 0.92, t)) * lerpf(0.65, 1.25, north_bias) * saddle
	return lerpf(edge_h, far, smoothstep(0.0, 0.22, t))


# --- Architecture & Landmarks -------------------------------------------------

func _build_bridge() -> void:
	var proxy := World.new()
	proxy.terrain_data = td
	proxy.water_level = WATER_LEVEL
	proxy.layout = layout
	var bridge_def: Dictionary = layout.list("bridges")[0]
	var _body := Bridge.build(structures_root, proxy, bridge_def)
	proxy.free()
	# Warm lantern posts framing the bridge ends.
	for pt: Vector2 in [Vector2(14.5, 25.5), Vector2(53.5, 6.5)]:
		_add_lantern_post(pt)


func _build_watchtower() -> void:
	var c := Vector2(-44, -92)
	var gy := td.height_at(c.x, c.y)
	var body := StaticBody3D.new()
	body.name = "ValleyWatchtower"
	body.collision_layer = Layers.WORLD
	structures_root.add_child(body)
	var stone := MeshKit.new(5101, 0.06)
	var detail := MeshKit.new(5102, 0.04)
	var banners := MeshKit.new(5103, 0.02)
	var glow := MeshKit.new(5104)

	var col := Color(0.42, 0.40, 0.37)
	# Battered plinth + tower shaft + corbelled battlement + slate roof.
	stone.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(c.x, gy - 1.5, c.y)), 4.6, 4.1, 4.0, 12, col * 0.88)
	stone.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(c.x, gy + 2.4, c.y)), 3.9, 3.6, 11.5, 12, col)
	stone.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(c.x, gy + 13.7, c.y)), 3.6, 4.3, 0.9, 12, col * 0.85)
	for m in 8:
		var a := TAU * float(m) / 8.0
		var mp := Vector3(c.x + cos(a) * 3.85, gy + 15.1, c.y + sin(a) * 3.85)
		detail.add_box(Transform3D(Basis(Vector3.UP, -a), mp), Vector3(0.75, 1.1, 1.25), Sites.tagged(PropMeshes.ROCK * 0.9, Sites.SURF_RUBBLE))
	# Slate spire cap + maroon war banner.
	detail.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(c.x, gy + 14.4, c.y)), 4.5, 0.0, 4.2, 12, Sites.tagged(Sites.SLATE, Sites.SURF_RUBBLE))
	banners.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(c.x, gy + 18.4, c.y)), 0.08, 0.05, 3.8, 6, Color(0.28, 0.2, 0.14))
	banners.add_box(Transform3D(Basis.IDENTITY, Vector3(c.x + 1.1, gy + 20.8, c.y)), Vector3(2.1, 1.1, 0.05), Color(0.45, 0.08, 0.08), 0.75)

	# Brazier & warm light at base.
	var bz := Vector2(c.x + 5.2, c.y + 4.0)
	var by := td.height_at(bz.x, bz.y)
	stone.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(bz.x, by, bz.y)), 0.5, 0.35, 0.9, 8, col * 0.8)
	glow.add_blob(Transform3D(Basis.IDENTITY.scaled(Vector3(0.35, 0.45, 0.35)), Vector3(bz.x, by + 1.05, bz.y)), 1.0, Color(1.0, 0.58, 0.22), false, 0.0)
	_add_local_light("WatchtowerBrazier", Vector3(bz.x, by + 1.4, bz.y), Color(1.0, 0.62, 0.28), 2.0, 14.0, true)

	var shape := CylinderShape3D.new()
	shape.radius = 4.2
	shape.height = 16.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(c.x, gy + 7.5, c.y)
	body.add_child(cs)

	_emit_mesh(body, stone, STONE_MAT, true, "WatchtowerStone")
	_emit_mesh(body, detail, Sites.CASTLE_PROPS_MAT, true, "WatchtowerDetail")
	_emit_mesh(body, banners, PROPS_MAT, true, "WatchtowerBanner")
	_emit_mesh(body, glow, GLOW_WARM, false, "WatchtowerGlow")


func _build_hamlet() -> void:
	var hamlet_root := Node3D.new()
	hamlet_root.name = "SilverrunMillHamlet"
	structures_root.add_child(hamlet_root)
	var origin := Vector3(84.0, td.height_at(84.0, 18.0), 18.0)
	var dummy_sites := Sites.new()
	var vb := VillageBuilder.new(dummy_sites, hamlet_root, origin, td, WATER_LEVEL)
	vb.solid = StaticBody3D.new()
	vb.solid.name = "HamletProps"
	vb.solid.collision_layer = Layers.WORLD
	vb.solid.collision_mask = 0
	hamlet_root.add_child(vb.solid)

	# Riverbank watermill & two lived-in cottages with props, carts, dry-stone walls.
	vb._building("MillHouse", Vector2(-12.0, -4.0), PI * 0.58, 7.6, 6.2, {
		"roof": "slate", "walls": "stone", "chimney": 1, "lit": true, "h1": 3.3, "gable_front": true})
	vb._building("FerryCottage", Vector2(7.0, 10.0), -PI * 0.72, 6.2, 5.4, {
		"roof": "thatch", "wall": VillageBuilder.c(0.56, 0.51, 0.42, VillageBuilder.PLASTER), "chimney": -1, "lit": true, "h1": 2.8})
	vb._building("GranaryShed", Vector2(12.0, -9.0), PI * 0.85, 5.6, 5.2, {
		"roof": "thatch", "walls": "plank", "staddles": true, "windows": false, "thatch_tint": 0.88})

	vb._cart(Transform3D.IDENTITY, Vector3(-1.5, 0.0, 4.5), 0.45)
	vb._firewood(Transform3D.IDENTITY, Vector3(3.5, 0.0, 8.0), 0.2, 2.0)
	vb._well(Vector2(2.0, -2.5))
	vb._dry_stone_wall([Vector2(-4, -14), Vector2(6, -15), Vector2(18, -14)])
	vb._dry_stone_wall([Vector2(-6, 15), Vector2(4, 17), Vector2(15, 16)])
	vb._emit(vb.props, HOUSE_MAT, true, "HamletDetail")
	vb._emit(vb.glow, GLOW_WARM, false, "HamletGlow")
	for f_entry in dummy_sites._flicker:
		_flicker.append(f_entry)
		if f_entry.get("light") is Light3D:
			_lamps.append(f_entry["light"])
	dummy_sites.free()

	# Rotating wooden waterwheel on the mill's river-facing flank.
	var wheel_kit := MeshKit.new(6101, 0.04)
	var wood := VillageBuilder.c(0.32, 0.22, 0.14, VillageBuilder.PLANK)
	for i in 12:
		var a := TAU * float(i) / 12.0
		var r := 2.1
		wheel_kit.add_box(Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a) * r, sin(a) * r, 0.0)), Vector3(0.14, 1.15, 0.85), wood)
		wheel_kit.add_box(Transform3D(Basis(Vector3.BACK, a), Vector3(cos(a) * r * 0.5, sin(a) * r * 0.5, 0.0)), Vector3(r, 0.12, 0.16), wood)
	wheel_kit.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.55)), 0.22, 0.22, 1.1, 8, wood)
	water_wheel = MeshInstance3D.new()
	water_wheel.name = "MillWaterwheel"
	water_wheel.mesh = wheel_kit.to_mesh(HOUSE_MAT)
	var wy := td.height_at(67.5, 14.0)
	water_wheel.position = Vector3(67.5, maxf(wy + 1.4, WATER_LEVEL + 1.85), 14.0)
	water_wheel.rotation.y = 0.25
	hamlet_root.add_child(water_wheel)

	_add_lantern_post(Vector2(82.0, 12.0))
	_add_lantern_post(Vector2(90.0, 22.0))


func _build_combat_clearing_ruins() -> void:
	var c := Vector2(118.0, -42.0)
	var kit := MeshKit.new(7201, 0.06)
	var banners := MeshKit.new(7202, 0.02)
	var body := StaticBody3D.new()
	body.name = "CombatClearingRuins"
	body.collision_layer = Layers.WORLD
	structures_root.add_child(body)

	var col := Color(0.42, 0.41, 0.39)
	# Ancient perimeter standing stones & weathered low walls framing the duel arena.
	for i in 6:
		var a := deg_to_rad(-145.0 + float(i) * 58.0)
		var p := c + Vector2(cos(a), sin(a)) * 31.0
		var y := td.height_at(p.x, p.y)
		var h := 3.2 + float(i % 3) * 0.9
		kit.add_box(Transform3D(Basis(Vector3.UP, -a), Vector3(p.x, y + h * 0.5 - 0.3, p.y)), Vector3(1.1, h + 0.6, 1.4), col * (0.9 + 0.06 * (i % 3)))
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.1, h, 1.4)
		var cs := CollisionShape3D.new()
		cs.shape = bs
		cs.transform = Transform3D(Basis(Vector3.UP, -a), Vector3(p.x, y + h * 0.5, p.y))
		body.add_child(cs)
		if i % 2 == 0:
			var bp := p + Vector2(-sin(a), cos(a)) * 1.6
			var by := td.height_at(bp.x, bp.y)
			banners.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(bp.x, by, bp.y)), 0.06, 0.04, 4.2, 6, Color(0.28, 0.20, 0.13))
			banners.add_box(Transform3D(Basis(Vector3.UP, -a), Vector3(bp.x + 0.65, by + 3.2, bp.y)), Vector3(1.2, 1.6, 0.05), Color(0.46, 0.09, 0.09), 0.8)

	_emit_mesh(body, kit, STONE_MAT, true, "ClearingStones")
	_emit_mesh(body, banners, PROPS_MAT, true, "ClearingBanners")


func _build_overlook_trailhead() -> void:
	var p := Vector2(-139.5, 114.0)
	var y := td.height_at(p.x, p.y)
	var kit := MeshKit.new(7301, 0.05)
	var col := Color(0.44, 0.42, 0.38)
	kit.add_box(Transform3D(Basis(Vector3.UP, 0.45), Vector3(p.x, y + 0.75, p.y)), Vector3(0.62, 1.8, 0.52), col)
	kit.add_box(Transform3D(Basis(Vector3.UP, 0.45), Vector3(p.x, y + 1.7, p.y)), Vector3(0.82, 0.24, 0.70), col * 1.08)
	_emit_mesh(structures_root, kit, STONE_MAT, true, "OverlookWaymarker")
	_add_lantern_post(Vector2(-142.5, 121.0))


func _add_lantern_post(at: Vector2) -> void:
	var y := td.height_at(at.x, at.y)
	var kit := MeshKit.new(hash(at) & 0xffff, 0.04)
	var glow := MeshKit.new((hash(at) + 17) & 0xffff)
	var xf := Transform3D(Basis.IDENTITY, Vector3(at.x, y, at.y))
	var wood := Color(0.24, 0.16, 0.11)
	var iron := Color(0.12, 0.12, 0.13)
	kit.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0)), 0.12, 0.09, 2.8, 6, wood)
	kit.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.32, 2.5, 0)), Vector3(0.75, 0.1, 0.1), wood)
	var lp := Vector3(0.62, 2.2, 0)
	kit.add_cylinder(xf * Transform3D(Basis.IDENTITY, lp + Vector3(0, 0.15, 0)), 0.16, 0.03, 0.14, 6, iron)
	glow.add_blob(xf * Transform3D(Basis.IDENTITY.scaled(Vector3(0.09, 0.13, 0.09)), lp), 1.0, Color(1.0, 0.62, 0.28), false, 0.0)
	_emit_mesh(structures_root, kit, PROPS_MAT, true, "LanternPost_%d_%d" % [int(at.x), int(at.y)])
	_emit_mesh(structures_root, glow, GLOW_WARM, false, "LanternGlow_%d_%d" % [int(at.x), int(at.y)])
	_add_local_light("LanternLight_%d_%d" % [int(at.x), int(at.y)], Vector3(at.x + 0.62, y + 2.15, at.y), Color(1.0, 0.68, 0.34), 1.35, 11.0, true)


func _add_local_light(node_name: String, pos: Vector3, col: Color, energy: float, range_m: float, flicker := false) -> void:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = pos
	light.light_color = col
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.add_to_group("day_night_lights")
	structures_root.add_child(light)
	_lamps.append(light)
	if flicker:
		_flicker.append({"light": light, "base": energy, "phase": randf() * TAU})


func _emit_mesh(parent: Node3D, kit: MeshKit, mat: Material, shadows: bool, node_name: String) -> void:
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = kit.to_mesh(mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# --- Vegetation & Wind Particles ---------------------------------------------

func _build_vegetation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261125
	var drift_n := FastNoiseLite.new()
	drift_n.seed = 301
	drift_n.frequency = 0.022
	var gold_n := FastNoiseLite.new()
	gold_n.seed = 307
	gold_n.frequency = 0.016

	var inst := {}
	var occupied := {}
	var solid := StaticBody3D.new()
	solid.name = "ShowcaseVegCollision"
	solid.collision_layer = Layers.WORLD
	vegetation_root.add_child(solid)

	var half := HALF_SIZE - 10.0

	# 1. Trees (natural clusters, sparse in golden valley meadows, dense in Whispering Grove).
	var tree_step := 4.8
	var tcnt := int(ceil(half * 2.0 / tree_step))
	for j in tcnt:
		for i in tcnt:
			var x := -half + (i + rng.randf_range(0.15, 0.85)) * tree_step
			var z := -half + (j + rng.randf_range(0.15, 0.85)) * tree_step
			var f := td.sample(td.forest, x, z)
			if rng.randf() > f:
				continue
			var h := td.height_at(x, z)
			if h < WATER_LEVEL + 0.8 or td.normal_at(x, z).y < 0.84:
				continue
			if td.sample(td.trail_dist, x, z) < 2.2:
				continue
			var p2 := Vector2(x, z)
			if p2.distance_to(Vector2(84, 18)) < 26.0 or p2.distance_to(Vector2(-44, -92)) < 14.0 or p2.distance_to(Vector2(118, -42)) < 36.0:
				continue
			var near_w := td.sample(td.water_influence, x, z) > 0.05
			var roll := rng.randf()
			var prop := "pine"
			if near_w:
				prop = "birch" if roll < 0.48 else ("oak" if roll < 0.85 else "pine")
			elif f > 0.55:
				prop = "fir" if roll < 0.42 else ("pine" if roll < 0.78 else "oak")
			else:
				prop = "oak" if roll < 0.42 else ("birch" if roll < 0.68 else "pine")
			var sc := rng.randf_range(0.85, 1.38)
			if f > 0.62 and rng.randf() < 0.14:
				sc = rng.randf_range(1.42, 1.78)
			var key_o := Vector2i(int(floor(x / 4.0)), int(floor(z / 4.0)))
			if occupied.has(key_o):
				continue
			occupied[key_o] = true
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc)
			var tint := Color(rng.randf_range(0.88, 1.08), rng.randf_range(0.90, 1.06), rng.randf_range(0.84, 1.02))
			_push_mm(inst, prop, Transform3D(b, Vector3(x, h - 0.2, z)), tint, 68.0)
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = float(PropMeshes.TRUNK_RADIUS.get(prop, 0.3)) * sc
			cyl.height = 6.5 * sc
			cs.shape = cyl
			cs.position = Vector3(x, h + cyl.height * 0.5 - 0.2, z)
			solid.add_child(cs)

	# Framed foreground hero pine on the Overlook Ridge left!
	_push_mm(inst, "pine", Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 1.25), Vector3(-156.0, td.height_at(-156.0, 114.0) - 0.25, 114.0)), Color(1.0, 0.96, 0.9), 68.0)

	# 2. Rocks & supporting stones on slopes and banks.
	var rstep := 10.0
	var rcnt := int(ceil(half * 2.0 / rstep))
	for j in rcnt:
		for i in rcnt:
			var x := -half + (i + rng.randf_range(0.15, 0.85)) * rstep
			var z := -half + (j + rng.randf_range(0.15, 0.85)) * rstep
			var nrm := td.normal_at(x, z)
			var steep := 1.0 - smoothstep(0.74, 0.92, nrm.y)
			var chance := 0.04 + 0.42 * steep + 0.14 * td.sample(td.water_influence, x, z)
			if rng.randf() > chance or td.sample(td.trail_dist, x, z) < 2.2:
				continue
			var h := td.height_at(x, z)
			if h < WATER_LEVEL - 0.5:
				continue
			var s := lerpf(0.6, 2.3, pow(rng.randf(), 2.0))
			var prop := "rock%d" % rng.randi_range(0, 3)
			_push_mm(inst, prop, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - 0.25 * s, z)), Color.WHITE * rng.randf_range(0.88, 1.12), 68.0)
			if s >= 1.2:
				for k in 2:
					var a := rng.randf() * TAU
					var d := s * rng.randf_range(0.75, 1.15)
					var sx := x + cos(a) * d
					var sz := z + sin(a) * d
					if td.sample(td.trail_dist, sx, sz) > 1.2:
						var ss := s * rng.randf_range(0.28, 0.44)
						_push_mm(inst, "rock%d" % rng.randi_range(0, 3), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * ss), Vector3(sx, td.height_at(sx, sz) - 0.2 * ss, sz)), Color.WHITE * 0.92, 68.0)

	# 3. Rolling golden-sage grass fields (dense sweeping meadow drifts, spatial 20 m chunks).
	var gstep := 1.28
	var gcnt := int(ceil(half * 2.0 / gstep))
	for j in gcnt:
		for i in gcnt:
			var x := -half + (i + rng.randf_range(0.1, 0.9)) * gstep
			var z := -half + (j + rng.randf_range(0.1, 0.9)) * gstep
			var f := td.sample(td.forest, x, z)
			var drift := smoothstep(-0.26, 0.44, drift_n.get_noise_2d(x, z))
			var chance := (1.0 - f * 0.88) * lerpf(0.24, 0.88, drift)
			if rng.randf() > chance:
				continue
			var h := td.height_at(x, z)
			if h < WATER_LEVEL + 0.3 or h > 28.0 or td.sample(td.trail_dist, x, z) < 0.45 or td.sample(td.paving, x, z) > 0.25:
				continue
			if td.normal_at(x, z).y < 0.80:
				continue
			var gold_w := smoothstep(-0.18, 0.42, gold_n.get_noise_2d(x, z))
			var is_tall := drift > 0.34 and rng.randf() < (0.48 * drift)
			var s := rng.randf_range(0.92, 1.52) if is_tall else rng.randf_range(0.82, 1.38)
			var col := Color(0.76, 0.84, 0.56).lerp(Color(1.16, 0.96, 0.52), gold_w) * rng.randf_range(0.88, 1.12)
			_push_mm(inst, "grass_tall" if is_tall else "grass", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - 0.04, z)), col, 20.0)

	# 4. Forest undergrowth (ferns, bushes) and riverbank reeds/wildflowers.
	var ustep := 2.4
	var ucnt := int(ceil(half * 2.0 / ustep))
	for j in ucnt:
		for i in ucnt:
			var x := -half + (i + rng.randf_range(0.1, 0.9)) * ustep
			var z := -half + (j + rng.randf_range(0.1, 0.9)) * ustep
			var h := td.height_at(x, z)
			if h < WATER_LEVEL + 0.15 or td.sample(td.trail_dist, x, z) < 0.6:
				continue
			var f := td.sample(td.forest, x, z)
			var wi := td.sample(td.water_influence, x, z)
			if f > 0.3 and rng.randf() < f * 0.55:
				_push_mm(inst, "fern", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), Vector3(x, h - 0.04, z)), Color.WHITE * rng.randf_range(0.84, 1.12), 20.0)
			elif f > 0.12 and f < 0.52 and rng.randf() < 0.14:
				_push_mm(inst, "bush%d" % rng.randi_range(0, 2), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.35)), Vector3(x, h - 0.08, z)), Color.WHITE * rng.randf_range(0.86, 1.1), 68.0)
			elif wi > 0.12 and h < WATER_LEVEL + 0.75 and rng.randf() < 0.5:
				_push_mm(inst, "reeds", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.35)), Vector3(x, h - 0.05, z)), Color.WHITE * rng.randf_range(0.85, 1.12), 20.0)
			elif rng.randf() < 0.065:
				var fl := "flower%d" % [0, 1, 2, 4][rng.randi_range(0, 3)]
				_push_mm(inst, fl, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.85, 1.25)), Vector3(x, h - 0.03, z)), Color.WHITE, 20.0)

	# Emit MultiMeshes with visibility range + LOD.
	for key in inst:
		var parts: PackedStringArray = key.split("|")
		var prop := parts[0]
		var list: Array = inst[key]
		var r: Array = Vegetation.RENDER.get(prop, [180.0, false])
		if r.size() > 2:
			_emit_mm(key, prop, list, 0.0, float(r[0]), bool(r[1]))
			_emit_mm(key + "|far", prop + "_far", list, float(r[0]) - 6.0, float(r[2]), false)
		else:
			_emit_mm(key, prop, list, 0.0, float(r[0]), bool(r[1]))


func _push_mm(table: Dictionary, prop: String, xf: Transform3D, col: Color, chunk_m: float) -> void:
	var key := "%s|%d|%d" % [prop, floori(xf.origin.x / chunk_m), floori(xf.origin.z / chunk_m)]
	if not table.has(key):
		table[key] = []
	table[key].append([xf, col])


func _emit_mm(key: String, mesh_name: String, list: Array, begin: float, end: float, shadows: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PropMeshes.get_mesh(mesh_name)
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i][0])
		mm.set_instance_color(i, list[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = key.replace("|", "_")
	mmi.multimesh = mm
	mmi.visibility_range_begin = begin
	mmi.visibility_range_begin_margin = 6.0 if begin > 0.0 else 0.0
	mmi.visibility_range_end = end
	mmi.visibility_range_end_margin = 6.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vegetation_root.add_child(mmi)


func _build_wind_particles() -> void:
	wind_particles = CPUParticles3D.new()
	wind_particles.name = "ValleyWindMotes"
	wind_particles.amount = 48
	wind_particles.lifetime = 5.0
	wind_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	wind_particles.emission_box_extents = Vector3(22.0, 4.5, 22.0)
	wind_particles.direction = Vector3(0.85, -0.05, 0.52)
	wind_particles.spread = 18.0
	wind_particles.initial_velocity_min = 2.4
	wind_particles.initial_velocity_max = 4.6
	wind_particles.gravity = Vector3(0.0, -0.08, 0.0)
	var qm := QuadMesh.new()
	qm.size = Vector2(0.11, 0.08)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = Sites._soft_mist_texture()
	mat.albedo_color = Color(0.95, 0.82, 0.46, 0.44)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	qm.material = mat
	wind_particles.mesh = qm
	add_child(wind_particles)


# --- Codex / Integration Markers (Contract C-13) ------------------------------

func _build_markers() -> void:
	var defs := [
		{"id": "gv_clearing_center", "kind": "battle_cell", "pos": Vector2(118.0, -42.0), "radius": 34.0},
		{"id": "gv_enemy_spawn_n", "kind": "spawn_point", "pos": Vector2(118.0, -64.0), "radius": 2.5},
		{"id": "gv_enemy_spawn_ne", "kind": "spawn_point", "pos": Vector2(134.0, -56.0), "radius": 2.5},
		{"id": "gv_enemy_spawn_e", "kind": "spawn_point", "pos": Vector2(140.0, -40.0), "radius": 2.5},
		{"id": "gv_enemy_spawn_se", "kind": "spawn_point", "pos": Vector2(132.0, -24.0), "radius": 2.5},
		{"id": "gv_escort_left", "kind": "escort_anchor", "pos": Vector2(102.0, -36.0), "radius": 2.0},
		{"id": "gv_escort_right", "kind": "escort_anchor", "pos": Vector2(104.0, -28.0), "radius": 2.0},
		{"id": "gv_patrol_1", "kind": "patrol_node", "pos": Vector2(96.0, -14.0), "radius": 3.0},
		{"id": "gv_patrol_2", "kind": "patrol_node", "pos": Vector2(112.0, -38.0), "radius": 3.0},
		{"id": "gv_patrol_3", "kind": "patrol_node", "pos": Vector2(128.0, -58.0), "radius": 3.0},
		{"id": "gv_camera_overlook", "kind": "camera_hint", "pos": Vector2(-148.0, 122.0), "radius": 5.0},
		{"id": "gv_no_spawn_ruin", "kind": "no_spawn", "pos": Vector2(-44.0, -92.0), "radius": 6.5},
	]
	for d in defs:
		var m := Marker3D.new()
		m.name = "WF_" + String(d["id"])
		var p: Vector2 = d["pos"]
		m.position = Vector3(p.x, td.height_at(p.x, p.y), p.y)
		m.set_meta("marker_id", d["id"])
		m.set_meta("kind", d["kind"])
		m.set_meta("radius", float(d["radius"]))
		m.add_to_group("wf_marker")
		markers_root.add_child(m)


# --- Player, Horse & Scenic Cameras ------------------------------------------

func _spawn_actors() -> void:
	player = PLAYER_SCENE.instantiate() as PlayerController
	player.is_local = true
	player.auto_register = true
	player.water_level = WATER_LEVEL
	add_child(player)
	var sp := Vector2(-146.0, 120.0)
	var sy := td.height_at(sp.x, sp.y) + 0.15
	# Face NE down the winding valley toward the stone bridge & waterfall.
	var aim := Vector2(18.0, 16.0) - sp
	var yaw := atan2(-aim.x, -aim.y)
	player.teleport(Vector3(sp.x, sy, sp.y), yaw)

	if spawn_horse:
		horse = HORSE_SCENE.instantiate() as Horse
		horse.water_level = WATER_LEVEL
		add_child(horse)
		var hp := sp + Vector2(3.2, 1.4)
		horse.teleport(Vector3(hp.x, td.height_at(hp.x, hp.y) + 0.15, hp.y), yaw)


func _setup_scenic_cameras() -> void:
	_scenic_cams = [
		{"name": "overlook_vista", "pos": Vector3(-148, td.height_at(-148, 122) + 3.2, 122), "look": Vector3(24, 5.0, -18)},
		{"name": "stone_bridge", "pos": Vector3(6, td.height_at(6, 30) + 3.4, 30), "look": Vector3(44, 4.5, 12)},
		{"name": "waterfall_gorge", "pos": Vector3(-8, td.height_at(-8, -116) + 4.2, -116), "look": Vector3(-18, 9.0, -166)},
		{"name": "hamlet_mill", "pos": Vector3(58, td.height_at(58, 10) + 3.2, 10), "look": Vector3(88, 6.0, 18)},
		{"name": "combat_clearing", "pos": Vector3(92, td.height_at(92, -14) + 4.0, -14), "look": Vector3(122, 5.0, -46)},
	]
	_scenic_cam = Camera3D.new()
	_scenic_cam.fov = 64.0
	_scenic_cam.far = 2200.0
	add_child(_scenic_cam)


func get_scenic_views() -> Array[Dictionary]:
	return _scenic_cams


func activate_scenic_camera(index: int) -> void:
	if _scenic_cams.is_empty():
		return
	_scenic_idx = posmod(index, _scenic_cams.size())
	var v: Dictionary = _scenic_cams[_scenic_idx]
	_scenic_cam.global_position = v["pos"]
	_scenic_cam.look_at(v["look"], Vector3.UP)
	_scenic_cam.current = true


func _cycle_scenic_camera() -> void:
	activate_scenic_camera(_scenic_idx + 1)
	_refresh_hud()


func _restore_player_camera() -> void:
	_scenic_idx = -1
	if is_instance_valid(player) and player.camera:
		player.camera.current = true
	_refresh_hud()


func _setup_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "ShowcaseHUD"
	add_child(_hud_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.72)
	style.border_color = Color(0.75, 0.62, 0.34, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_hud_layer.add_child(panel)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 14)
	_hud_label.add_theme_color_override("font_color", Color(0.94, 0.91, 0.84))
	panel.add_child(_hud_label)
	_refresh_hud()


func _refresh_hud() -> void:
	if _hud_label == null:
		return
	var prof := atmosphere.current() if atmosphere else initial_profile
	var cam_txt: String = String(_scenic_cams[_scenic_idx]["name"]) if _scenic_idx >= 0 and _scenic_idx < _scenic_cams.size() else "player"
	_hud_label.text = "WILDFALL | Golden Valley Showcase  (%.0f FPS)\nProfile: %s  [1:Day  2:Evening  3:Night  4:Misty]\nCamera: %s  [F9:Scenic  0:Player]   Horse: [H:Call  E:Mount]   [F2:Hide]" % [_fps_display, prof, cam_txt]


class _WorldProxy:
	var terrain_data: TerrainData
	var water_level: float
	func _init(p_td: TerrainData, p_wl: float) -> void:
		terrain_data = p_td
		water_level = p_wl
