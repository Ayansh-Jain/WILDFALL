class_name HorseMaterials
extends RefCounted
## Real-time tuning of the horse's imported glTF materials for the Compatibility
## renderer: a soft rim on the coat (the sheen of short hair along silhouettes), the
## mane and tail as alpha-tested, double-sided cards with alpha-to-coverage, glossy
## dark eyes; the tack atlases import as standard PBR materials. Small tack parts fade
## out with distance.

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
		match String(mi.name):
			"Bridle", "Straps", "Stirrup_l", "Stirrup_r":
				mi.visibility_range_end = 70.0
				mi.visibility_range_end_margin = 6.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			"Hair":
				mi.visibility_range_end = 120.0
			"Eyes":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = 40.0


static func _tuned(src: Material) -> Material:
	var key := src.resource_name.get_slice(".", 0)
	if _cache.has(key):
		return _cache[key]
	if not (src is BaseMaterial3D):
		return null
	var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match key:
		"HorseCoat":
			m.rim_enabled = true
			m.rim = 0.28
			m.rim_tint = 0.75
		"HorseHair":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.4
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.55
			m.metallic_specular = 0.45
		"HorseEye":
			m.roughness = 0.04
			m.metallic_specular = 0.9
			m.albedo_color = Color(0.05, 0.035, 0.028)
		"HorseCloth":
			m.rim_enabled = true
			m.rim = 0.15
			m.rim_tint = 0.9
	_cache[key] = m
	return m
