extends SceneTree
## Measures the commander's locomotion clips: cycle length, the ground speed implied
## by the planted foot (how fast it slides backwards under the body while lowest),
## and the phase at which each foot touches down. Used to phase-align the gait blend
## and to match playback rate to movement speed.
##   godot --headless --path . --script res://tools/analyze_gait.gd

const MODEL := "res://assets/characters/commander/commander.glb"
const CLIPS := ["walk", "walk_formal", "jog", "run", "sword_dash", "carry_walk", "crouch_walk"]


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	var scene: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(scene)
	var sk: Skeleton3D = scene.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
	var fl := sk.find_bone("foot_l")
	var fr := sk.find_bone("foot_r")
	var bl := sk.find_bone("ball_l")
	var br := sk.find_bone("ball_r")
	print("bones foot_l %d foot_r %d ball_l %d ball_r %d" % [fl, fr, bl, br])
	for clip in CLIPS:
		if not ap.has_animation(clip):
			print(clip, ": missing")
			continue
		var a := ap.get_animation(clip)
		ap.play(clip)
		var n := 120
		var len := a.length
		var ys_l := PackedFloat32Array()
		var ys_r := PackedFloat32Array()
		var zs_l := PackedFloat32Array()
		var zs_r := PackedFloat32Array()
		var hip_y := PackedFloat32Array()
		for i in n:
			var t := len * float(i) / n
			ap.seek(t, true)
			ap.advance(0.0)
			var pl := sk.get_bone_global_pose(bl if bl >= 0 else fl).origin
			var pr := sk.get_bone_global_pose(br if br >= 0 else fr).origin
			ys_l.append(pl.y)
			ys_r.append(pr.y)
			zs_l.append(pl.z)
			zs_r.append(pr.z)
			hip_y.append(sk.get_bone_global_pose(sk.find_bone("pelvis")).origin.y)
		# Planted foot = lower one; its z velocity (model faces +Z) is the ground speed.
		var speeds := PackedFloat32Array()
		var contact_l := -1.0
		var contact_r := -1.0
		var min_l := INF
		var min_r := INF
		for i in n:
			min_l = minf(min_l, ys_l[i])
			min_r = minf(min_r, ys_r[i])
		for i in n:
			var j := (i + 1) % n
			var dt := len / n
			var low_l := ys_l[i] < min_l + 0.02
			var low_r := ys_r[i] < min_r + 0.02
			if low_l and ys_l[i] <= ys_r[i]:
				speeds.append(-(zs_l[j] - zs_l[i]) / dt)
			elif low_r and ys_r[i] < ys_l[i]:
				speeds.append(-(zs_r[j] - zs_r[i]) / dt)
			var pi := (i - 1 + n) % n
			if contact_l < 0.0 and low_l and not (ys_l[pi] < min_l + 0.02):
				contact_l = float(i) / n
			if contact_r < 0.0 and low_r and not (ys_r[pi] < min_r + 0.02):
				contact_r = float(i) / n
		speeds.sort()
		var med := speeds[speeds.size() / 2] if speeds.size() > 0 else 0.0
		var stride := absf(med) * len
		var hip_min := INF
		var hip_max := -INF
		for v in hip_y:
			hip_min = minf(hip_min, v)
			hip_max = maxf(hip_max, v)
		print("%-12s len %.3f s  ground speed %.2f m/s  cycle stride %.2f m  contact L %.2f R %.2f  hip bob %.3f m  loop %d" % [
			clip, len, med, stride, contact_l, contact_r, hip_max - hip_min, a.loop_mode])
