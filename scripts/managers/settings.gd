extends Node
## Player-facing settings and key bindings, persisted to user://settings.cfg.
##
## Default bindings live in DEFAULT_BINDINGS below. Actions are registered in the
## InputMap at startup, so the in-game Controls menu (Esc > Controls) and this
## table are the two places to change controls.

signal settings_changed
signal bindings_changed

const SAVE_PATH := "user://settings.cfg"

## action -> [label, [event specs]]. Specs: "key:<Key enum name>" or "mouse:<button index>".
const DEFAULT_BINDINGS := {
	"move_forward": ["Move forward", ["key:W"]],
	"move_back": ["Move back", ["key:S"]],
	"move_left": ["Move left", ["key:A"]],
	"move_right": ["Move right", ["key:D"]],
	"jump": ["Jump / swim up", ["key:Space"]],
	"sprint": ["Sprint", ["key:Shift"]],
	"crouch": ["Crouch", ["key:Ctrl", "key:C"]],
	"interact": ["Interact", ["key:E"]],
	"attack": ["Attack (sword / claw)", ["mouse:1"]],
	"heavy_attack": ["Heavy Strike (beast)", ["mouse:2"]],
	"ability_1": ["Dodge / Pounce", ["key:Q"]],
	"ability_2": ["Ward / Roar", ["key:R"]],
	"transform": ["Transform / return to human", ["key:F"]],
	"pause": ["Pause menu", ["key:Escape"]],
	"debug_overlay": ["Debug overlay", ["key:F3"]],
	"debug_los_probe": ["[Dev] Drop sight probe", ["key:F4"]],
	"debug_teleport": ["[Dev] Next point of interest", ["key:F6"]],
	"debug_scroll": ["[Dev] Go to scroll", ["key:F7"]],
	"debug_noclip": ["[Dev] Toggle noclip", ["key:F8"]],
	"debug_spawn_monster": ["[Dev] Spawn hostile test monster", ["key:F9"]],
	"debug_grant_monster": ["[Dev] Give yourself the monster", ["key:F10"]],
	"debug_spawn_humans": ["[Dev] Spawn 3 wanderers nearby", ["key:F11"]],
}

## Actions shown in the rebinding menu, in order.
const REBINDABLE := [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "sprint", "crouch", "interact", "attack", "heavy_attack",
	"ability_1", "ability_2", "transform", "debug_overlay",
]

var mouse_sensitivity: float = 0.12  # degrees per pixel
var invert_y: bool = false
var fov: float = 75.0
var head_bob: bool = true
var master_volume_db: float = 0.0

var _overrides: Dictionary = {}  # action -> Array[String] of specs


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_apply_all_bindings()
	_apply_audio()


func get_action_label(action: String) -> String:
	return DEFAULT_BINDINGS.get(action, [action])[0]


func get_specs(action: String) -> Array:
	if _overrides.has(action):
		return _overrides[action]
	return DEFAULT_BINDINGS[action][1]


## Human-readable text for the first binding of an action, e.g. "E".
func get_binding_text(action: String) -> String:
	var specs := get_specs(action)
	if specs.is_empty():
		return "Unbound"
	return spec_to_text(specs[0])


func rebind(action: String, event: InputEvent) -> void:
	var spec := event_to_spec(event)
	if spec == "":
		return
	_overrides[action] = [spec]
	_apply_binding(action)
	save()
	bindings_changed.emit()


func reset_bindings() -> void:
	_overrides.clear()
	_apply_all_bindings()
	save()
	bindings_changed.emit()


func set_value(key: String, value) -> void:
	set(key, value)
	if key == "master_volume_db":
		_apply_audio()
	save()
	settings_changed.emit()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("general", "invert_y", invert_y)
	cfg.set_value("general", "fov", fov)
	cfg.set_value("general", "head_bob", head_bob)
	cfg.set_value("general", "master_volume_db", master_volume_db)
	for action in _overrides:
		cfg.set_value("bindings", action, _overrides[action])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("general", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("general", "invert_y", invert_y)
	fov = cfg.get_value("general", "fov", fov)
	head_bob = cfg.get_value("general", "head_bob", head_bob)
	master_volume_db = cfg.get_value("general", "master_volume_db", master_volume_db)
	if cfg.has_section("bindings"):
		for action in cfg.get_section_keys("bindings"):
			if DEFAULT_BINDINGS.has(action):
				_overrides[action] = cfg.get_value("bindings", action)


func _apply_all_bindings() -> void:
	for action in DEFAULT_BINDINGS:
		_apply_binding(action)


func _apply_binding(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for spec in get_specs(action):
		var ev := spec_to_event(spec)
		if ev:
			InputMap.action_add_event(action, ev)


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, master_volume_db)


static func spec_to_event(spec: String) -> InputEvent:
	var parts := spec.split(":")
	if parts.size() != 2:
		return null
	if parts[0] == "key":
		var ev := InputEventKey.new()
		ev.physical_keycode = OS.find_keycode_from_string(parts[1])
		return ev
	if parts[0] == "mouse":
		var mb := InputEventMouseButton.new()
		mb.button_index = int(parts[1]) as MouseButton
		return mb
	return null


static func event_to_spec(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return "key:" + OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		return "mouse:%d" % event.button_index
	return ""


static func spec_to_text(spec: String) -> String:
	var parts := spec.split(":")
	if parts[0] == "mouse":
		match int(parts[1]):
			MOUSE_BUTTON_LEFT: return "Mouse L"
			MOUSE_BUTTON_RIGHT: return "Mouse R"
			MOUSE_BUTTON_MIDDLE: return "Mouse M"
			_: return "Mouse " + parts[1]
	return parts[1] if parts.size() > 1 else spec
