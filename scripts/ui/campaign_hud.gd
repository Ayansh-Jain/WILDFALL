class_name CampaignHUD
extends CanvasLayer
## Campaign UI in the story HUD's style: the mission panel under the objective line
## (mission name, state, objective, elimination progress such as 7 / 10, the current
## phase and the destination with its distance and bearing), the army button
## (status, living / roster, key), centre banners (objective complete, mission
## complete / failed), the failed screen with Retry and Quit, and a fade used to
## hide teleports during retry / quit / waiting for the council.

signal army_button_pressed
signal retry_pressed
signal quit_pressed

const GOLD := Color(0.86, 0.73, 0.5)
const TEXT := Color(0.92, 0.9, 0.85)
const DIM := Color(0.7, 0.68, 0.62)

var _panel: PanelContainer
var _title: Label
var _state: Label
var _objective: Label
var _progress: Label
var _bar: ProgressBar
var _phase: Label
var _dest: Label
var _army: Button
var _banner: Label
var _banner_sub: Label
var _banner_tween: Tween
var _failed: Control
var _failed_sub: Label
var _retry: Button
var _quit: Button
var _fade: ColorRect
var _fade_tween: Tween


func _ready() -> void:
	layer = 11
	_build_panel()
	_build_army()
	_build_banner()
	_build_failed()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _label(size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style(alpha := 0.62) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.02, 0.025, alpha)
	s.border_color = Color(0.55, 0.47, 0.33, 0.6)
	s.border_width_top = 1
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 10
	return s


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _style())
	# Top left: the story objective and the combat feed share the top right.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 20
	_panel.offset_right = 400
	_panel.offset_top = 18
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	_title = _label(15, GOLD)
	_state = _label(13, DIM)
	_objective = _label(17, TEXT)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress = _label(22, TEXT)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.72, 0.2, 0.16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.13, 0.12, 0.8)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_phase = _label(14, Color(0.95, 0.75, 0.45))
	_phase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dest = _label(14, Color(0.75, 0.85, 0.9))
	for c in [_title, _state, _objective, _progress, _bar, _phase, _dest]:
		box.add_child(c)
	_panel.add_child(box)
	_panel.visible = false
	add_child(_panel)


func _build_army() -> void:
	_army = Button.new()
	_army.focus_mode = Control.FOCUS_NONE
	_army.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_army.offset_left = 18
	_army.offset_right = 330
	_army.offset_top = -138
	_army.offset_bottom = -102
	_army.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_army.add_theme_font_size_override("font_size", 15)
	_army.add_theme_color_override("font_color", TEXT)
	var normal := _style(0.58)
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.08, 0.08, 0.75)
	_army.add_theme_stylebox_override("normal", normal)
	_army.add_theme_stylebox_override("hover", hover)
	_army.add_theme_stylebox_override("pressed", hover)
	_army.pressed.connect(func() -> void: army_button_pressed.emit())
	add_child(_army)


func _build_banner() -> void:
	_banner = _label(44, Color(0.95, 0.85, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -500
	_banner.offset_right = 500
	_banner.offset_top = -170
	_banner.offset_bottom = -110
	_banner.modulate.a = 0.0
	add_child(_banner)
	_banner_sub = _label(20, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner_sub.offset_left = -500
	_banner_sub.offset_right = 500
	_banner_sub.offset_top = -108
	_banner_sub.offset_bottom = -78
	_banner_sub.modulate.a = 0.0
	add_child(_banner_sub)


func _build_failed() -> void:
	_failed = ColorRect.new()
	(_failed as ColorRect).color = Color(0.05, 0.0, 0.0, 0.62)
	_failed.set_anchors_preset(Control.PRESET_FULL_RECT)
	_failed.visible = false
	var title := _label(52, Color(0.85, 0.25, 0.2), HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "MISSION FAILED"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	title.offset_left = -500
	title.offset_right = 500
	title.offset_top = -150
	title.offset_bottom = -80
	_failed.add_child(title)
	_failed_sub = _label(20, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_failed_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_failed_sub.offset_left = -500
	_failed_sub.offset_right = 500
	_failed_sub.offset_top = -70
	_failed_sub.offset_bottom = -10
	_failed_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_failed.add_child(_failed_sub)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	row.offset_left = -230
	row.offset_right = 230
	row.offset_top = 20
	row.offset_bottom = 70
	row.add_theme_constant_override("separation", 30)
	_retry = _menu_button("Retry", func() -> void: retry_pressed.emit())
	_quit = _menu_button("Quit", func() -> void: quit_pressed.emit())
	row.add_child(_retry)
	row.add_child(_quit)
	_failed.add_child(row)
	add_child(_failed)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 48)
	b.add_theme_font_size_override("font_size", 22)
	var s := _style(0.85)
	s.border_width_bottom = 1
	s.border_width_left = 1
	s.border_width_right = 1
	var h := s.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.35, 0.08, 0.06, 0.9)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("focus", h)
	b.add_theme_stylebox_override("pressed", h)
	b.pressed.connect(cb)
	return b


# --- API -------------------------------------------------------------------------------------

## info: {title, state, objective, kills, target, phase, destination}; empty hides the panel.
func set_mission(info: Dictionary) -> void:
	_panel.visible = not info.is_empty()
	if info.is_empty():
		return
	_title.text = String(info.get("title", "")).to_upper()
	_state.text = String(info.get("state", ""))
	_objective.text = String(info.get("objective", ""))
	var target := int(info.get("target", 0))
	_progress.visible = target > 0
	_bar.visible = target > 0
	if target > 0:
		var k := int(info.get("kills", 0))
		_progress.text = "%d / %d" % [k, target]
		_bar.max_value = target
		_bar.value = k
	var ph := String(info.get("phase", ""))
	_phase.visible = ph != ""
	_phase.text = ph
	var d := String(info.get("destination", ""))
	_dest.visible = d != ""
	_dest.text = d


func mission_visible() -> bool:
	return _panel.visible


func progress_text() -> String:
	return _progress.text if _progress.visible else ""


func objective_text() -> String:
	return _objective.text


func title_text() -> String:
	return _title.text


func destination_text() -> String:
	return _dest.text if _dest.visible else ""


func set_army(text: String) -> void:
	_army.text = text
	_army.visible = text != ""


func army_text() -> String:
	return _army.text


func banner(title: String, sub := "", seconds := 3.5) -> void:
	_banner.text = title
	_banner_sub.text = sub
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween().set_parallel()
	for l in [_banner, _banner_sub]:
		l.modulate.a = 0.0
		_banner_tween.tween_property(l, "modulate:a", 1.0, 0.5)
	_banner_tween.chain().tween_interval(seconds)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 1.0)
	_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 1.0)


func banner_text() -> String:
	return _banner.text if _banner.modulate.a > 0.01 else ""


func show_failed(sub: String) -> void:
	_failed_sub.text = sub
	_failed.visible = true
	_retry.grab_focus()


func hide_failed() -> void:
	_failed.visible = false


func failed_visible() -> bool:
	return _failed.visible


## Fades to black (to = 1) or back (to = 0); await the returned tween's `finished`.
func fade(to: float, seconds := 0.6) -> Tween:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", to, seconds)
	return _fade_tween
