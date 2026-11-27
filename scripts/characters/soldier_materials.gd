class_name SoldierMaterials
extends RefCounted
## Faction materials for soldiers built from the commander's model. Every material
## here is a DUPLICATE of the commander's tuned material (CommanderMaterials), so the
## commander never changes; one set per faction is cached and shared by all soldiers of
## that faction (no per-soldier copies).
##
## kingdom: the cloth layers (cloak, quilt, wool, tabard) in a deep, muted maroon.
## enemy:   the same layers near-black charcoal; brass trims blackened.
## Cloth is matte and weathered; leather and steel keep the commander's materials.
## Recolouring reuses the commander's idea: only blue-dominant cloth texels of the
## ORIGINAL imported atlas are remapped, so embroidery, seams and folds keep their detail.

const CLOTH := ["CloakBlue", "QuiltNavy", "WoolDark", "TabardNavy"]

## Per layer tint over the recoloured atlas (a little variation between layers).
const TINTS := {
	"kingdom": {"CloakBlue": Color(0.78, 0.74, 0.74), "QuiltNavy": Color(0.92, 0.88, 0.88),
		"WoolDark": Color(0.7, 0.66, 0.66), "TabardNavy": Color(1.0, 0.95, 0.95)},
	"enemy": {"CloakBlue": Color(0.82, 0.82, 0.86), "QuiltNavy": Color(0.95, 0.95, 0.98),
		"WoolDark": Color(0.78, 0.78, 0.8), "TabardNavy": Color(1.0, 1.0, 1.0)},
}

static var _cache := {}      ## "faction/material" -> Material
static var _textures := {}   ## "faction/texture" -> Texture2D


## Applies the faction's materials as surface overrides on every mesh under `root`
## (the soldier's own instance of the model; the shared meshes are not touched).
static func apply(root: Node, faction: String) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var m := material(src, faction)
			if m:
				mi.set_surface_override_material(s, m)


static func material(src: Material, faction: String) -> Material:
	var key := src.resource_name
	var ck := faction + "/" + key
	if _cache.has(ck):
		return _cache[ck]
	var tuned := CommanderMaterials._tuned(src)
	if tuned == null:
		return null
	if not (key in CLOTH or (faction == "enemy" and key in ["Bronze", "SteelDark"])):
		# Leather, skin, steel...: the commander's own tuned material, shared as is.
		_cache[ck] = tuned
		return tuned
	var m := (tuned as BaseMaterial3D).duplicate() as BaseMaterial3D
	m.resource_name = key + "_" + faction
	if key in CLOTH:
		m.albedo_texture = _recolored((src as BaseMaterial3D).albedo_texture, faction)
		m.albedo_color = TINTS[faction][key]
		# Matte, weathered wool: no sheen.
		m.roughness = 0.96
		m.metallic_specular = 0.14
	elif key == "Bronze":
		# Blackened fittings for the enemy.
		m.albedo_color = Color(0.3, 0.27, 0.24)
		m.metallic = 0.7
		m.roughness = 0.55
	elif key == "SteelDark":
		m.albedo_color = Color(0.55, 0.55, 0.58)
		m.roughness = 0.6
	_cache[ck] = m
	return m


## The atlas with its blue cloth texels remapped to the faction colour (luminance kept).
static func _recolored(texture: Texture2D, faction: String) -> Texture2D:
	if texture == null:
		return null
	var ck := faction + "/" + (texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id()))
	if _textures.has(ck):
		return _textures[ck]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var had_mipmaps := image.has_mipmaps()
	image.clear_mipmaps()
	var px := image.get_data()
	for i in range(0, px.size(), 4):
		var r := int(px[i])
		var g := int(px[i + 1])
		var b := int(px[i + 2])
		if faction == "enemy" and px[i + 3] > 2 and r > b * 1.4 and g > b * 1.1 and r > 40:
			# The kingdom's gold griffin and trims are not the enemy's: blacken them to a
			# dull iron grey (the embroidery still reads as relief, not as gold).
			var gv := (r * 0.3 + g * 0.5 + b * 0.2) * 0.42
			px[i] = mini(roundi(gv), 255)
			px[i + 1] = mini(roundi(gv), 255)
			px[i + 2] = mini(roundi(gv * 1.06), 255)
			continue
		if px[i + 3] > 2 and b > r * 1.2 and b > g * 1.12 and b > 12:
			var v := r * 0.18 + g * 0.32 + b * 0.50
			if faction == "kingdom":
				# Deep muted maroon (madder-dyed wool).
				px[i] = mini(roundi(v * 0.95), 255)
				px[i + 1] = mini(roundi(v * 0.22), 255)
				px[i + 2] = mini(roundi(v * 0.26), 255)
			else:
				# Near-black charcoal with a faint cool cast.
				px[i] = mini(roundi(v * 0.36), 255)
				px[i + 1] = mini(roundi(v * 0.36), 255)
				px[i + 2] = mini(roundi(v * 0.40), 255)
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, px)
	if had_mipmaps:
		image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	_textures[ck] = tex
	return tex
