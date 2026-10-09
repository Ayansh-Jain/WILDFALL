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
	var h := rng.randf_range(0.22, 0.3) + h_shift
	var c := Color.from_hsv(h, rng.randf_range(0.5, 0.75), rng.randf_range(0.32, 0.55))
	return c


func _leaves() -> Image:
	var img := _new(512, Color(0.2, 0.3, 0.12))
	var center := Vector2(256, 256)
	# Twigs fanning out from the bottom centre, leaves along them.
	var twigs: Array = []
	for i in 7:
		var a := deg_to_rad(-90.0 + rng.randf_range(-70, 70))
		var start := Vector2(256 + rng.randf_range(-30, 30), 500)
		var end := center + Vector2.from_angle(a) * rng.randf_range(150, 230)
		twigs.append([start, end])
		_stroke(img, start, end, 4.0, 1.5, Color(0.25, 0.18, 0.12, 1), Color(0.3, 0.24, 0.16, 1))
	for i in 420:
		var tw: Array = twigs[rng.randi_range(0, twigs.size() - 1)]
		var t := rng.randf_range(0.25, 1.0)
		var p: Vector2 = (tw[0] as Vector2).lerp(tw[1], t) + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		if p.distance_to(center) > 245:
			continue
		var ang := (p - (tw[0] as Vector2)).angle() + rng.randf_range(-1.2, 1.2)
		var length := rng.randf_range(26, 44)
		_leaf(img, p, ang, length, length * rng.randf_range(0.42, 0.55), _green())
	return img


func _needles() -> Image:
	var img := _new(512, Color(0.1, 0.2, 0.15))
	# u: 0 = trunk end (x = 0), 1 = branch tip (x = 512). Card is wide, so taper.
	var main_a := Vector2(0, 256)
	var main_b := Vector2(500, 250)
	_stroke(img, main_a, main_b, 6.0, 1.5, Color(0.22, 0.15, 0.1, 1), Color(0.28, 0.2, 0.12, 1))
	var twigs: Array = [[main_a, main_b]]
	for i in 16:
		var t := rng.randf_range(0.05, 0.88)
		var base := main_a.lerp(main_b, t)
		var side := 1.0 if i % 2 == 0 else -1.0
		var reach := (1.0 - t) * 220.0 + 40.0
		var end := base + Vector2(reach * 0.75, side * reach * 0.6)
		end.y = clampf(end.y, 20, 492)
		twigs.append([base, end])
		_stroke(img, base, end, 3.0, 1.0, Color(0.24, 0.17, 0.11, 1), Color(0.3, 0.22, 0.14, 1))
	for tw in twigs:
		var a: Vector2 = tw[0]
		var b: Vector2 = tw[1]
		var dir := (b - a).normalized()
		var steps := int(a.distance_to(b) / 3.5)
		for s in steps:
			var p := a.lerp(b, float(s) / steps)
			for k in 2:
				var side := 1.0 if k == 0 else -1.0
				var nd := dir.rotated(side * deg_to_rad(rng.randf_range(40, 70)))
				var nl := rng.randf_range(22, 36)
				var col := Color.from_hsv(rng.randf_range(0.36, 0.44), rng.randf_range(0.45, 0.65), rng.randf_range(0.22, 0.4))
				_stroke(img, p, p + nd * nl, 2.1, 1.0, col, col.lightened(0.15))
	return img


func _grass() -> Image:
	var img := _new(256, Color(0.25, 0.35, 0.15))
	for i in 46:
		var x := rng.randf_range(20, 236)
		var h := rng.randf_range(110, 240)
		var lean := rng.randf_range(-40, 40)
		var base := Vector2(x, 255)
		var tip := Vector2(x + lean, 255 - h)
		var mid := base.lerp(tip, 0.5) + Vector2(lean * 0.2, 0)
		var col := Color.from_hsv(rng.randf_range(0.2, 0.28), rng.randf_range(0.45, 0.7), rng.randf_range(0.3, 0.5))
		var tip_col := col.lerp(Color(0.62, 0.6, 0.35), rng.randf_range(0.1, 0.5))
		_stroke(img, base, mid, rng.randf_range(3.0, 4.5), 2.4, col.darkened(0.2), col)
		_stroke(img, mid, tip, 2.4, 0.6, col, tip_col)
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
