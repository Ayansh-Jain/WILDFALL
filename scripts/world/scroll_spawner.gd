class_name ScrollSpawner
extends Node3D
## Validates the designated scroll markers from the layout and places exactly
## one scroll at a marker chosen by GameState.scroll_seed.
## Markers that fail validation (underwater, steep, blocked) are skipped and
## reported in `rejected`.

const SCROLL_SCENE := preload("res://scenes/interactables/scroll.tscn")

var candidates: Array = []  ## [{name, position}]
var rejected: Array = []    ## [{name, reason}]
var scroll: Scroll


func validate_markers(world: World) -> void:
	candidates.clear()
	rejected.clear()
	for m in world.layout.list("scroll_spawns"):
		var xz := WorldLayout.v2(m["pos"])
		var from_y := world.resolve_y_hint(m.get("y_hint", ""))
		var res := SpawnValidator.find(world, xz, from_y, 4.0, {"max_slope_deg": 26.0, "min_above_water": 0.5})
		if res["ok"]:
			candidates.append({"name": m["name"], "position": res["position"]})
		else:
			rejected.append({"name": m["name"], "reason": res["reason"]})
	if not rejected.is_empty():
		push_warning("ScrollSpawner: rejected markers %s" % str(rejected))


## Removes any existing scroll and spawns one. Returns the chosen marker name.
func spawn(seed_value: int) -> String:
	if scroll and is_instance_valid(scroll):
		scroll.queue_free()
	scroll = null
	if candidates.is_empty():
		push_error("ScrollSpawner: no valid scroll markers")
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pick: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	scroll = SCROLL_SCENE.instantiate()
	add_child(scroll)
	scroll.global_position = pick["position"]
	GameState.register_scroll(pick["name"], pick["position"])
	print("[ScrollSpawner] seed %d -> marker '%s'" % [seed_value, pick["name"]])
	return pick["name"]
