class_name ReveMaterials
extends RefCounted
## Real-time tuning of Princess Reve's imported glTF materials for the
## Compatibility renderer: alpha-tested hair cards with alpha-to-coverage, wrapped
## diffuse and a faint warm rim on the skin in place of subsurface scattering,
## glossy eyes, a soft sheen on the black crepe so the dress keeps its folds at
## night, glossier leather, and metals that keep some diffuse response under a
## dark sky (pure metal would turn black with nothing bright to reflect).

static var _cache := {}


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
	match key:
		"Hair", "Brows", "Lashes":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4 if key == "Hair" else 0.3
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.55
			m.metallic = 0.0
			m.metallic_specular = 0.3
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			if key == "Hair":
				# Warm, soft highlights along the length rather than a plastic shine.
				m.rim_enabled = true
				m.rim = 0.08
				m.rim_tint = 0.6
		"Skin":
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			m.metallic = 0.0
			m.metallic_specular = 0.36
			if m.normal_enabled:
				m.normal_scale = 0.6
			m.rim_enabled = true
			m.rim = 0.14
			m.rim_tint = 0.7
		"Eye":
			m.roughness = 0.05
			m.metallic_specular = 0.75
		"Teeth":
			m.albedo_color = Color(0.82, 0.78, 0.72)
			m.albedo_texture = null
			m.roughness = 0.35
		"DressCrepe":
			m.cull_mode = BaseMaterial3D.CULL_DISABLED   # the skirt is seen from inside at the hem
			m.metallic = 0.0
			m.metallic_specular = 0.32
			m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
			# Crepe catches light at grazing angles: a cool sheen that keeps the
			# folds readable on deep black fabric in moonlight.
			m.rim_enabled = true
			m.rim = 0.22
			m.rim_tint = 0.3
		"BeltLeather", "BagLeather", "LaceCord":
			m.metallic = 0.0
			m.metallic_specular = 0.55
		"EyeletMetal":
			m.metallic = 0.75
			m.roughness = 0.3
			m.albedo_color = Color(0.66, 0.66, 0.68)
		"Gold":
			m.metallic = 0.8
			m.roughness = 0.22
			m.albedo_color = Color(1.0, 0.78, 0.42)
		"Shoes":
			m.albedo_color = Color(0.03, 0.03, 0.033)
			m.albedo_texture = null
			m.roughness = 0.4
		_:
			pass
	m.resource_name = key
	_cache[key] = m
	return m
