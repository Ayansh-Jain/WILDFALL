extends SceneTree
## Paints the alpha-cut foliage card textures used by the trees, bushes, ferns
## and grass (res://assets/textures/foliage_*.png). Deterministic: rerun to
## regenerate after changing colours or shapes.
##   godot --headless --path . -s res://tools/generate_foliage_textures.gd

const OUT := "res://assets/textures/"

var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 4242
	_save(_leaves(), "foliage_leaves.png")
	_save(_needles(), "foliage_needles.png")
	_save(_grass(), "foliage_grass.png")
	_save(_fern(), "foliage_fern.png")
	quit()


func _save(img: Image, file: String) -> void:
	_bleed(img)
	var err := img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("%-22s %s" % [file, "ok" if err == OK else "error %d" % err])


func _new(size: int, bg: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(bg.r, bg.g, bg.b, 0.0))
	return img


## Transparent pixels take the average leaf colour so mipmaps do not darken edges.
func _bleed(img: Image) -> void:
	var sum := Color(0, 0, 0)
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sum += c
				n += 1
	if n == 0:
		return
	var avg := sum / n
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a < 0.5:
				img.set_pixel(x, y, Color(avg.r, avg.g, avg.b, 0.0))


func _disc(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var s := img.get_width()
	for y in range(maxi(0, int(cy - r)), mini(s, int(cy + r) + 1)):
		for x in range(maxi(0, int(cx - r)), mini(s, int(cx + r) + 1)):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				img.set_pixel(x, y, col)


## Tapered stroke from a to b (radius r0 -> r1).
func _stroke(img: Image, a: Vector2, b: Vector2, r0: float, r1: float, c0: Color, c1: Color) -> void:
	var steps := int(maxf(2.0, a.distance_to(b) / 0.8))
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(b, t)
		_disc(img, p.x, p.y, lerpf(r0, r1, t), c0.lerp(c1, t))


## A leaf: pointed ellipse with a darker base and a pale midrib.
func _leaf(img: Image, c: Vector2, angle: float, length: float, width: float, col: Color) -> void:
	var dir := Vector2.from_angle(angle)
	var side := dir.orthogonal()
	var s := img.get_width()
	var r := length * 0.6
	for y in range(maxi(0, int(c.y - r)), mini(s, int(c.y + r) + 1)):
		for x in range(maxi(0, int(c.x - r)), mini(s, int(c.x + r) + 1)):
			var d := Vector2(x, y) - c
			var u := d.dot(dir) / (length * 0.5)   # -1 base .. 1 tip
			var v := d.dot(side) / (width * 0.5)
			if absf(u) > 1.0:
				continue
			var half := sqrt(1.0 - u * u) * (1.0 - 0.35 * maxf(u, 0.0))
			if absf(v) > half:
				continue
			var shade := 0.75 + 0.35 * (u * 0.5 + 0.5) - 0.12 * absf(v)
			var pc := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
			if absf(v) < 0.08:
				pc = pc.lightened(0.18)
			img.set_pixel(x, y, pc)


func _green(h_shift := 0.0) -> Color:
	var h := rng.randf_range(0.20, 0.30) + h_shift
	var c := Color.from_hsv(h, rng.randf_range(0.45, 0.72), rng.randf_range(0.32, 0.58))
	return c


func _leaves() -> Image:
	var img := _new(512, Color(0.24, 0.34, 0.14))
	var center := Vector2(256, 256)
	var twigs: Array = []
	for i in 8:
		var a := deg_to_rad(-90.0 + rng.randf_range(-72, 72))
		var start := Vector2(256 + rng.randf_range(-34, 34), 502)
		var end := center + Vector2.from_angle(a) * rng.randf_range(155, 236)
		twigs.append([start, end])
		_stroke(img, start, end, 4.2, 1.4, Color(0.24, 0.17, 0.11, 1), Color(0.32, 0.24, 0.15, 1))
	for i in 480:
		var tw: Array = twigs[rng.randi_range(0, twigs.size() - 1)]
		var t := rng.randf_range(0.22, 1.0)
		var p: Vector2 = (tw[0] as Vector2).lerp(tw[1], t) + Vector2(rng.randf_range(-42, 42), rng.randf_range(-42, 42))
		if p.distance_to(center) > 246:
			continue
		var ang := (p - (tw[0] as Vector2)).angle() + rng.randf_range(-1.2, 1.2)
		var length := rng.randf_range(24, 44)
		var col := _green(rng.randf_range(-0.03, 0.02))
		if t > 0.7:
			col = col.lerp(Color(0.54, 0.58, 0.24), rng.randf_range(0.05, 0.25))
		_leaf(img, p, ang, length, length * rng.randf_range(0.42, 0.56), col)
	return img


func _needles() -> Image:
	var img := _new(512, Color(0.11, 0.22, 0.15))
	var main_a := Vector2(0, 256)
	var main_b := Vector2(502, 250)
	_stroke(img, main_a, main_b, 6.0, 1.5, Color(0.22, 0.15, 0.1, 1), Color(0.28, 0.2, 0.12, 1))
	var twigs: Array = [[main_a, main_b]]
	for i in 18:
		var t := rng.randf_range(0.05, 0.88)
		var base := main_a.lerp(main_b, t)
		var side := 1.0 if i % 2 == 0 else -1.0
		var reach := (1.0 - t) * 224.0 + 42.0
		var end := base + Vector2(reach * 0.75, side * reach * 0.62)
		end.y = clampf(end.y, 18, 494)
		twigs.append([base, end])
		_stroke(img, base, end, 3.0, 1.0, Color(0.24, 0.17, 0.11, 1), Color(0.3, 0.22, 0.14, 1))
	for tw in twigs:
		var a: Vector2 = tw[0]
		var b: Vector2 = tw[1]
		var dir := (b - a).normalized()
		var steps := int(a.distance_to(b) / 3.0)
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			for k in 2:
				var side := 1.0 if k == 0 else -1.0
				var nd := dir.rotated(side * deg_to_rad(rng.randf_range(38, 68)))
				var nl := rng.randf_range(22, 38)
				var col := Color.from_hsv(rng.randf_range(0.34, 0.43), rng.randf_range(0.42, 0.64), rng.randf_range(0.24, 0.44))
				_stroke(img, p, p + nd * nl, 2.0, 0.9, col, col.lightened(0.18))
	return img


func _grass() -> Image:
	var img := _new(256, Color(0.34, 0.40, 0.18))
	# Dense arching meadow grass blades + taller golden seed-head stalks.
	for i in 68:
		var x := rng.randf_range(14, 242)
		var h := rng.randf_range(105, 244)
		var lean := rng.randf_range(-46, 46)
		var base := Vector2(x, 255)
		var tip := Vector2(x + lean, 255 - h)
		var mid := base.lerp(tip, 0.52) + Vector2(lean * 0.14, -8.0)
		var col := Color.from_hsv(rng.randf_range(0.16, 0.26), rng.randf_range(0.42, 0.68), rng.randf_range(0.32, 0.54))
		var tip_col := col.lerp(Color(0.78, 0.68, 0.34), rng.randf_range(0.25, 0.68))
		var w0 := rng.randf_range(2.6, 4.0)
		_stroke(img, base, mid, w0, w0 * 0.62, col.darkened(0.28), col)
		_stroke(img, mid, tip, w0 * 0.62, 0.55, col, tip_col)
		if i % 6 == 0 and h > 185.0:
			# Subtle pale golden seed plume near the blade tip.
			var plume_a := mid.lerp(tip, 0.65)
			var plume_c := Color(0.84, 0.76, 0.48, 1.0)
			_stroke(img, plume_a, tip, 2.4, 1.1, col.lerp(plume_c, 0.5), plume_c)
	return img


func _fern() -> Image:
	var img := _new(256, Color(0.15, 0.3, 0.12))
	# Frond runs from the bottom centre to the top, curving slightly.
	var a := Vector2(128, 255)
	var b := Vector2(140, 6)
	_stroke(img, a, b, 2.5, 1.0, Color(0.2, 0.28, 0.1, 1), Color(0.25, 0.35, 0.12, 1))
	var steps := 22
	for s in range(2, steps):
		var t := float(s) / steps
		var p := a.lerp(b, t)
		var reach := sin(t * PI) * 95.0 * (1.0 - t * 0.3)
		for side: float in [-1.0, 1.0]:
			var end := p + Vector2(side * reach, -reach * 0.35)
			var col := Color.from_hsv(rng.randf_range(0.24, 0.3), rng.randf_range(0.55, 0.75), rng.randf_range(0.3, 0.48))
			var seg := 7
			for k in seg:
				var q := p.lerp(end, float(k) / seg)
				_leaf(img, q, (end - p).angle() + side * 1.2, 14.0 * (1.0 - float(k) / seg * 0.6), 7.0, col)
	return img
