class_name HUD
extends CanvasLayer
## Crosshair, interaction prompt, toasts, story dialogue and objective, loading
## screen, underwater tint and the developer overlay. Built in code so it stays
## easy to restyle.

const PROMPT_COLOR := Color(0.93, 0.88, 0.76)

var player: PlayerController
var debug_lines: Callable  ## Returns extra overlay text from Main.

var _crosshair: Crosshair
var _prompt: Label
var _prompt_refresh := 0.0
var _toast: Label
var _toast_tween: Tween
var _loading: Control
var _underwater: ColorRect
var _debug: Label
var _debug_timer := 0.0
var _dialogue: PanelContainer
var _speaker: Label
var _line: Label
var _objective: Label


class Crosshair extends Control:
	var focused := false

	func _draw() -> void:
		var c := size * 0.5
		if focused:
			draw_arc(c, 7.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.55, 0.85), 1.5, true)
			draw_circle(c, 2.0, Color(1.0, 0.9, 0.7, 0.95))
		else:
			draw_circle(c, 1.8, Color(1, 1, 1, 0.55))


func _ready() -> void:
	add_to_group("hud")
	layer = 10
	_underwater = ColorRect.new()
	_underwater.color = Color(0.03, 0.2, 0.24, 0.55)
	_underwater.set_anchors_preset(Control.PRESET_FULL_RECT)
	_underwater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underwater.visible = false
	add_child(_underwater)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.size = Vector2(24, 24)
	_crosshair.position = -_crosshair.size * 0.5
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_prompt = _make_label(20, PROMPT_COLOR)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = 34
	_prompt.offset_bottom = 64
	add_child(_prompt)

	_toast = _make_label(22, Color(0.85, 0.95, 0.92))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 70
	_toast.offset_bottom = 110
	_toast.modulate.a = 0.0
	add_child(_toast)

	_debug = Label.new()
	_debug.position = Vector2(12, 10)
	_debug.add_theme_font_size_override("font_size", 14)
	_debug.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85))
	_debug.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_debug.add_theme_constant_override("shadow_offset_x", 1)
	_debug.add_theme_constant_override("shadow_offset_y", 1)
	_debug.visible = false
	add_child(_debug)

	_build_story_ui()
	_loading = _build_loading()
	add_child(_loading)


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_story_ui() -> void:
	_dialogue = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.025, 0.72)
	style.border_color = Color(0.55, 0.47, 0.33, 0.6)
	style.border_width_top = 1
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	_dialogue.add_theme_stylebox_override("panel", style)
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue.offset_left = -430
	_dialogue.offset_right = 430
	_dialogue.offset_top = -250
	_dialogue.offset_bottom = -150
	_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue.visible = false
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker = _make_label(17, Color(0.86, 0.73, 0.5))
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_line = _make_label(21, Color(0.92, 0.9, 0.85))
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_speaker)
	box.add_child(_line)
	_dialogue.add_child(box)
	add_child(_dialogue)
	_objective = _make_label(17, Color(0.86, 0.8, 0.66))
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_objective.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_objective.offset_left = -560
	_objective.offset_right = -24
	_objective.offset_top = 18
	_objective.offset_bottom = 48
	add_child(_objective)


## Shows one line of story dialogue; an empty speaker shows narration.
func show_dialogue(speaker: String, text: String) -> void:
	_speaker.text = speaker.to_upper()
	_speaker.visible = speaker != ""
	_line.text = text
	_dialogue.visible = true


func hide_dialogue() -> void:
	_dialogue.visible = false


func dialogue_text() -> String:
	return _line.text if _dialogue.visible else ""


func set_objective(text: String) -> void:
	_objective.text = "" if text == "" else "Objective: " + text


func objective_text() -> String:
	return _objective.text


func _build_loading() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var title := _make_label(54, Color(0.82, 0.86, 0.8))
	title.text = "W I L D F A L L"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.offset_left = -400
	title.offset_right = 400
	title.offset_top = -60
	title.offset_bottom = 10
	bg.add_child(title)
	var sub := _make_label(18, Color(0.55, 0.65, 0.62))
	sub.text = "The forest is waking..."
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.offset_left = -400
	sub.offset_right = 400
	sub.offset_top = 20
	sub.offset_bottom = 50
	bg.add_child(sub)
	return bg


func attach_player(p: PlayerController) -> void:
	player = p
	var interactor: PlayerInteractor = p.get_node("Interactor")
	interactor.focus_changed.connect(_on_focus_changed)
	Settings.bindings_changed.connect(func() -> void: _on_focus_changed(interactor.focused))


func show_loading(on: bool) -> void:
	_loading.visible = on


func toast(text: String, duration := 4.0) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.4)
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 1.2)


func toggle_debug() -> void:
	_debug.visible = not _debug.visible


func is_debug_visible() -> bool:
	return _debug.visible


func prompt_text() -> String:
	return _prompt.text


func _on_focus_changed(target: Interactable) -> void:
	_crosshair.focused = target != null
	_crosshair.queue_redraw()
	_update_interaction_prompt()


func _process(delta: float) -> void:
	if player:
		_underwater.visible = player.is_camera_underwater() and not player.noclip
		_prompt_refresh -= delta
		if _prompt_refresh <= 0.0:
			_prompt_refresh = 0.15
			_update_interaction_prompt()
	if _debug.visible:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = 0.25
			_debug.text = _debug_text()


func _update_interaction_prompt() -> void:
	if player == null:
		_prompt.text = ""
		return
	if player.is_sitting:
		_prompt.text = ""
		return
	var interactor := player.get_node_or_null("Interactor") as PlayerInteractor
	var target: Interactable = interactor.focused if interactor else null
	if target and target.input_action != "sit":
		_prompt.text = "[%s]  %s" % [Settings.get_binding_text(target.input_action), target.prompt_text]
	elif player.can_offer_sit_prompt():
		_prompt.text = ""
	elif target and target.input_action != "sit":
		_prompt.text = "[%s]  %s" % [Settings.get_binding_text(target.input_action), target.prompt_text]
	else:
		_prompt.text = ""


func _debug_text() -> String:
	var lines: PackedStringArray = []
	lines.append("FPS %d   frame %.1f ms   draw calls %d   objects %d" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	if player:
		var p := player.global_position
		lines.append("pos %.1f, %.1f, %.1f   speed %.1f m/s" % [p.x, p.y, p.z, Vector2(player.velocity.x, player.velocity.z).length()])
		var state := "swimming" if player.is_swimming else ("wading" if player.water_depth > 0.1 else ("airborne" if not player.is_on_floor() else "grounded"))
		lines.append("state %s%s%s%s" % [state, "  crouch" if player.is_crouching else "", "  sprint" if player.is_sprinting else "", "  NOCLIP" if player.noclip else ""])
	if debug_lines.is_valid():
		lines.append_array(debug_lines.call())
	return "\n".join(lines)
