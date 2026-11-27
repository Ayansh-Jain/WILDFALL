extends CanvasLayer
## Minimal combat HUD for the arena and training: health, lesson, short feedback, incoming
## attack warnings and openings. Every cue is words and shapes, not colour alone.

var arena: Node
var _health: ProgressBar
var _health_text: Label
var _lesson: Label
var _lesson_panel: PanelContainer
var _flash: Label
var _flash_t := 0.0
var _opening: Label
var _banner: Label
var _banner_t := 0.0
var _help: Label
var _warnings: Array = []  ## [Label, ProgressBar]
var _telegraphs := {}  ## enemy id -> {start, duration, class}


func setup(p_arena: Node) -> void:
	arena = p_arena
	_health = ProgressBar.new()
	_health.show_percentage = false
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.06, 0.8)
	back.border_color = Color(0.85, 0.8, 0.7, 0.8)
	back.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.62, 0.14, 0.12)
	_health.add_theme_stylebox_override("background", back)
	_health.add_theme_stylebox_override("fill", fill)
	_health.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health.offset_left = 20
	_health.offset_right = 280
	_health.offset_top = -78
	_health.offset_bottom = -60
	add_child(_health)
	_health_text = _label(14)
	_health_text.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_health_text.offset_left = 20
	_health_text.offset_top = -102
	_health_text.offset_bottom = -80

	_lesson_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.78)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_lesson_panel.add_theme_stylebox_override("panel", style)
	_lesson_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lesson_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lesson_panel.offset_top = 14
	_lesson_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lesson_panel)
	_lesson = Label.new()
	_lesson.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lesson.add_theme_font_size_override("font_size", 16)
	_lesson_panel.add_child(_lesson)
	_lesson_panel.visible = false

	_banner = _centered(26, 0.22)
	_flash = _centered(20, 0.66)
	_opening = _centered(18, 0.74)
	_help = _label(13)
	_help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.offset_top = -28
	_help.offset_bottom = -8
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Combat.swords.event.connect(_on_event)


func _exit_tree() -> void:
	if Combat.swords.event.is_connected(_on_event):
		Combat.swords.event.disconnect(_on_event)


func flash(text: String, good := true) -> void:
	_flash.text = ("+  " if good else "!  ") + text
	_flash.modulate = Color(0.75, 1.0, 0.7) if good else Color(1.0, 0.82, 0.55)
	_flash_t = 2.6


func banner(text: String, seconds := 2.5) -> void:
	_banner.text = text
	_banner_t = seconds


func lesson_text(text: String) -> void:
	_lesson.text = text
	_lesson_panel.visible = text != ""


func flash_text() -> String:
	return _flash.text


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _centered(font_size: int, height: float) -> Label:
	var l := _label(font_size)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = height
	l.anchor_bottom = height
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _on_event(data: Dictionary) -> void:
	var player: PlayerController = arena.player
	var kind := String(data.kind)
	if data.actor == player.player_id:
		match kind:
			"perfect_parry": flash("PERFECT PARRY")
			"parry": flash("Parried")
			"block": flash("Blocked", false)
			"guard_break": flash("Guard broken", false)
		return
	if kind == "telegraph":
		_telegraphs[data.actor] = {"start": Combat.now(), "duration": float(data.duration), "class": String(data.get("class", "normal"))}
	elif kind in ["canceled", "completed", "recovery"]:
		_telegraphs.erase(data.actor)


func _process(delta: float) -> void:
	var player: PlayerController = arena.player
	if player == null:
		return
	_health.max_value = player.combatant.max_health
	_health.value = player.combatant.health
	_health_text.text = "Health %d / %d" % [player.combatant.health, player.combatant.max_health]
	_flash_t -= delta
	_flash.visible = _flash_t > 0.0
	_banner_t -= delta
	_banner.visible = _banner_t > 0.0
	_help.text = "%s Attack  %s Guard/Parry  %s Dodge  %s Finisher  %s Swords  %s Escort    [1] Training [2] Duel [3] Group [4] Elite [5] Army [0] Clear   Esc Menu" % [
		Settings.get_binding_text("attack"), Settings.get_binding_text("guard"), Settings.get_binding_text("ability_1"),
		Settings.get_binding_text("special_attack"), Settings.get_binding_text("toggle_weapons"), Settings.get_binding_text("army_command")]
	_help.visible = not player.riding
	_update_openings(player)
	_update_warnings(player)


func _update_openings(player: PlayerController) -> void:
	var text := ""
	var state: Dictionary = Combat.swords.actors.get(player.player_id, {})
	if float(state.get("counter_until", 0.0)) > Combat.now():
		text = "<> COUNTER  [%s]" % Settings.get_binding_text("attack")
	for id in arena.director.members.keys() + arena.training_ids():
		var enemy := Combat.avatar(id)
		if enemy == null or enemy.is_defeated:
			continue
		var to := enemy.global_position - player.global_position
		to.y = 0.0
		if to.length() < 1.9 and player.forward().dot(to.normalized()) > 0.85 \
				and (enemy.combatant.is_stunned() or enemy.combatant.health <= 35):
			text = "<<>> FINISHING STRIKE  [%s]" % Settings.get_binding_text("special_attack")
	_opening.text = text


func _update_warnings(player: PlayerController) -> void:
	var camera := player.camera
	var size := get_viewport().get_visible_rect().size
	var used := 0
	for id in _telegraphs.keys():
		var data: Dictionary = _telegraphs[id]
		var enemy := Combat.avatar(id)
		var left: float = data.start + data.duration - Combat.now()
		if enemy == null or enemy.is_defeated or left < -0.1:
			_telegraphs.erase(id)
			continue
		if used >= _warnings.size():
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.size = Vector2(90, 8)
			bar.max_value = 1.0
			add_child(bar)
			_warnings.append([_label(17), bar])
		var label: Label = _warnings[used][0]
		var meter: ProgressBar = _warnings[used][1]
		used += 1
		var heavy: bool = data.class != "normal"
		label.text = "X  UNBLOCKABLE - DODGE" if data.class == "unblockable" else ("!!  HEAVY" if heavy else "!  Strike")
		label.modulate = Color(1.0, 0.45, 0.35) if heavy else Color(1.0, 0.92, 0.6)
		var head := enemy.global_position + Vector3.UP * 2.15
		var at := camera.unproject_position(head)
		# Off screen: pin to the edge on its side so attacks from behind are announced.
		var local := camera.global_transform.affine_inverse() * head
		if camera.is_position_behind(head) or at.x < 60 or at.x > size.x - 60:
			var right := local.x >= 0.0
			label.text = (label.text + "  >>") if right else ("<<  " + label.text)
			at = Vector2(size.x - 260 if right else 30, size.y * 0.45 + used * 34)
		else:
			at.x -= label.size.x * 0.5
		label.position = at
		label.visible = true
		meter.position = at + Vector2(0, 26)
		meter.value = clampf(left / maxf(data.duration, 0.01), 0.0, 1.0)
		meter.visible = true
	for i in range(used, _warnings.size()):
		_warnings[i][0].visible = false
		_warnings[i][1].visible = false
