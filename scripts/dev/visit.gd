class_name DevVisit
extends Node
## Walk through a standalone scene (graphics showcase, battlefield demo) with the real
## Commander and horse, then return to the kingdom. The visited scene is run as it is;
## this wrapper only adds the pause menu, the whistle and the way home.
##
## Enter from the pause menu, or run `res://scenes/dev/visit.tscn` with `-- --visit=<id>`.

const SCENE := "res://scenes/dev/visit.tscn"
const MAIN := "res://scenes/main/main.tscn"
## id -> [menu label, scene path]. A missing scene is simply not offered.
const DESTINATIONS := {
	"valley": ["Golden Valley (graphics showcase)", "res://scenes/world/showcase/golden_valley_showcase.tscn"],
	"arena": ["Combat arena and training", "res://scenes/arena/combat_arena.tscn"],
}
const META_TARGET := "visit_target"
const META_RETURN := "visit_return"

var destination: Node
var recall: HorseRecall
var menu: PauseMenu


static func available() -> Array:
	return DESTINATIONS.keys().filter(func(id: String) -> bool: return ResourceLoader.exists(DESTINATIONS[id][1]))


## Leaves the kingdom for `id`, remembering where the Commander stood.
static func go(tree: SceneTree, id: String, from: PlayerController = null) -> void:
	GameState.set_meta(META_TARGET, id)
	if from and not from.riding:
		GameState.set_meta(META_RETURN, {"position": from.global_position, "yaw": from.rotation.y})
	_reset_world_hooks()
	tree.paused = false
	tree.change_scene_to_file(SCENE)


static func go_home(tree: SceneTree) -> void:
	_reset_world_hooks()
	tree.paused = false
	tree.change_scene_to_file(MAIN)


## Statics that point into the scene being left.
static func _reset_world_hooks() -> void:
	Battlefield.route = null
	PlayerController.terrain_height_query = Callable()
	PlayerController.terrain_hole_query = Callable()
	GameState.reset_match()


func _ready() -> void:
	var id := String(GameState.get_meta(META_TARGET, GameState.args.get("visit", "valley")))
	if not DESTINATIONS.has(id) or not ResourceLoader.exists(DESTINATIONS[id][1]):
		push_warning("Visit: no destination '%s'" % id)
		go_home.call_deferred(get_tree())
		return
	destination = (load(DESTINATIONS[id][1]) as PackedScene).instantiate()
	add_child(destination)
	menu = PauseMenu.new()
	menu.name = "PauseMenu"
	menu.visiting = true
	add_child(menu)
	var player := destination.get("player") as PlayerController
	var horse := destination.get("horse") as Horse
	if player and horse:
		horse.enable_self_dormancy()
		# Added after the destination so it hears the whistle key first.
		recall = HorseRecall.new()
		recall.name = "HorseRecall"
		recall.listen = true
		add_child(recall)
		recall.setup(player, horse, player.water_level)
	var layer := CanvasLayer.new()
	add_child(layer)
	var hint := Label.new()
	hint.visible = destination.get("custom_hint") != true
	hint.text ="WASD move   Shift sprint   X swords   H whistle   E mount / dismount   Esc menu and return"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 4)
	layer.add_child(hint)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
