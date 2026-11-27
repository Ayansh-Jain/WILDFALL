class_name LocationDB
extends RefCounted
## Typed access to data/exploration.json: the shared, id-keyed list of places,
## interactions, settlements and encounters. Positions are world [x, z]; heights come
## from the terrain, so moving a place is a data edit.

const PATH := "res://data/exploration.json"

var data := {}
var _by_id := {}


static func load_default(path := PATH) -> LocationDB:
	var db := LocationDB.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("LocationDB: cannot parse %s" % path)
		return db
	db.data = parsed
	for loc in db.locations():
		db._by_id[String(loc["id"])] = loc
	return db


func locations() -> Array:
	return data.get("locations", [])


func interactions() -> Array:
	return data.get("interactions", [])


func settlements() -> Array:
	return data.get("settlements", [])


func encounters() -> Array:
	return data.get("encounters", [])


func location(id: String) -> Dictionary:
	return _by_id.get(id, {})


static func xz(entry: Dictionary, key := "pos") -> Vector2:
	var a: Array = entry.get(key, [0, 0])
	return Vector2(float(a[0]), float(a[1]))


## The location whose area `p` is inside (the most central one), or "".
func location_at(p: Vector3) -> String:
	var best := ""
	var best_score := 1.0
	for loc in locations():
		var score := Vector2(p.x, p.z).distance_to(xz(loc)) / float(loc["radius"])
		if score < best_score:
			best_score = score
			best = String(loc["id"])
	return best


## Where a traveller is put down at this place (road side, open ground).
func travel_point(id: String) -> Vector2:
	var loc := location(id)
	return xz(loc, "travel") if loc.has("travel") else xz(loc)


func is_safe(id: String) -> bool:
	return bool(location(id).get("safe", false))
