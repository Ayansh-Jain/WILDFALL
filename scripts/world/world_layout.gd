class_name WorldLayout
extends RefCounted
## Typed access to data/world_layout.json.

const DEFAULT_PATH := "res://data/world_layout.json"

var data: Dictionary = {}
var half_size: float
var playable_half: float
var cell: float
var water_level: float
var base_height: float
var chunk_cells: int


static func load_default() -> WorldLayout:
	var layout := WorldLayout.new()
	var text := FileAccess.get_file_as_string(DEFAULT_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WorldLayout: could not parse %s" % DEFAULT_PATH)
		return layout
	layout.data = parsed
	var w: Dictionary = parsed["world"]
	layout.half_size = w["half_size"]
	layout.playable_half = w["playable_half"]
	layout.cell = w["cell"]
	layout.water_level = w["water_level"]
	layout.base_height = w["base_height"]
	layout.chunk_cells = int(w["chunk_cells"])
	return layout


func list(key: String) -> Array:
	return data.get(key, [])


func dict(key: String) -> Dictionary:
	return data.get(key, {})


func find_site(site_name: String) -> Dictionary:
	for s in list("sites"):
		if s["name"] == site_name:
			return s
	return {}


static func v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func points(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(v2(p))
	return out
