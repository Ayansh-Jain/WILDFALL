class_name CommanderMaterials
extends RefCounted
## Real-time tuning of the commander's imported glTF materials for the
## Compatibility renderer: alpha-tested hair cards with alpha-to-coverage (the
## project uses MSAA), wrapped diffuse on the skin in place of subsurface
## scattering, glossy eyes. The outfit atlases (albedo / normal / ORM) import as
## standard PBR materials and only get filtering tweaks.

static var _cache := {}
static var _brown_textures := {}


static func apply(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var tuned := _tuned(src)
			if tuned:
				mi.set_surface_override_material(s, tuned)


static func _tuned(src: Material) -> Material:
	var key := src.resource_name
	if _cache.has(key):
		return _cache[key]
	if not (src is BaseMaterial3D):
		return null
	var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if key in ["CloakBlue", "QuiltNavy", "WoolDark", "TabardNavy"]:
		m.albedo_texture = _brown_cloth_texture(m.albedo_texture)
	match key:
		"Hair", "Brows", "Lashes":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.42 if key == "Hair" else 0.3
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.62
			m.metallic_specular = 0.28
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		"Skin":
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			m.roughness = 0.6
			m.metallic = 0.0
			m.metallic_specular = 0.38
			if m.normal_enabled:
				m.normal_scale = 0.85
			# A faint warm rim stands in for light scattering through the ears and edges.
			m.rim_enabled = true
			m.rim = 0.12
			m.rim_tint = 0.65
		"Eye":
			m.roughness = 0.06
			m.metallic_specular = 0.7
		"Teeth":
			m.albedo_color = Color(0.8, 0.76, 0.68)
			m.albedo_texture = null
			m.roughness = 0.35
		"CloakBlue", "QuiltNavy", "WoolDark", "TabardNavy":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED  # cloak and skirts are seen from inside too
			m.metallic = 0.0
			m.metallic_texture = null
			m.roughness = 0.92
			m.metallic_specular = 0.22
			# Keep the imported PBR detail and give each cloth layer a slightly
			# different warm brown value after blue pixels have been hue-shifted.
			m.albedo_color = {
				"CloakBlue": Color(0.88, 0.78, 0.66),
				"QuiltNavy": Color(0.98, 0.90, 0.79),
				"WoolDark": Color(0.84, 0.73, 0.61),
				"TabardNavy": Color(1.0, 0.90, 0.78),
			}[key]
		"SteelDark", "Bronze", "BladeSteel":
			# Metalness is per material (the atlas' metal channel is unused). Not fully
			# metallic: under a dark night sky pure metal has nothing to reflect and turns
			# black, so keep a little diffuse response for the plates to hold their form.
			m.metallic_texture = null
			m.metallic = {"SteelDark": 0.8, "Bronze": 0.85, "BladeSteel": 0.92}[key]
		"LeatherBrigandine", "LeatherBrown", "LeatherStrap", "LeatherBoot", "LeatherGlove":
			# The imported ORM is shared by metal and leather surfaces. Keep its
			# roughness channel, but do not let the metallic channel make leather shine.
			m.metallic = 0.0
			m.metallic_texture = null
			m.roughness = 0.78
			m.metallic_specular = 0.25
		_:
			pass
	m.resource_name = key
	_cache[key] = m
	return m


static func _brown_cloth_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var cache_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if _brown_textures.has(cache_key):
		return _brown_textures[cache_key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var had_mipmaps := image.has_mipmaps()
	image.clear_mipmaps()
	# Recolor only blue-dominant cloth texels. Gold embroidery, skin, leather,
	# grayscale and transparent atlas padding keep their original color and detail.
	var pixels := image.get_data()
	for i in range(0, pixels.size(), 4):
		var r := int(pixels[i])
		var g := int(pixels[i + 1])
		var b := int(pixels[i + 2])
		if pixels[i + 3] > 2 and b > r * 1.2 and b > g * 1.12 and b > 12:
			var value := r * 0.18 + g * 0.32 + b * 0.50
			pixels[i] = mini(roundi(value * 1.7), 255)
			pixels[i + 1] = mini(roundi(value * 1.02), 255)
			pixels[i + 2] = mini(roundi(value * 0.56), 255)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels)
	if had_mipmaps:
		image.generate_mipmaps()
	var recolored := ImageTexture.create_from_image(image)
	_brown_textures[cache_key] = recolored
	return recolored
