class_name CombatHUD
extends CanvasLayer
## Local player's combat interface: health, stamina, Power, ability slots with
## cooldowns, a private transformation status line, hit/hurt feedback, roar
## markers and a short event feed. Everything shown is from the local player's
## own point of view; nothing marks another player as the monster.

const EMBER := Color(1.0, 0.55, 0.25)
const GOLD := Color(1.0, 0.85, 0.5)
const FEED_MAX := 6
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity = 0.0;
uniform vec4 tint : source_color = vec4(0.6, 0.0, 0.0, 1.0);
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(tint.rgb, smoothstep(0.35, 0.85, d) * intensity);
}
"""

var player: PlayerController

var _health_bar: Bar
var _stamina_bar: Bar
var _power_label: Label
var _status_label: Label
var _notice: Label
var _slots_box: HBoxContainer
var _controls_panel: PanelContainer
var _controls_label: Label
var _controls_text := ""
var _feed: VBoxContainer
var _vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _hitmark: HitMarker
var _markers: RoarMarkers
var _slots := {}  ## ability id -> Slot
var _form_id := ""
var _hurt := 0.0
var _notice_t := 0.0


class Bar extends Control:
	var value := 1.0
	var max_value := 1.0
	var fill := Color.RED
	var label := ""

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
		var f := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
		draw_rect(Rect2(Vector2(2, 2), Vector2((size.x - 4) * f, size.y - 4)), fill)
		draw_string(ThemeDB.fallback_font, Vector2(6, size.y - 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.9))


class Slot extends Control:
	var key_text := ""
	var title := ""
	var cooldown := 0.0
	var cooldown_total := 1.0
	var charges := -1
	var ready_col := Color(0.85, 0.88, 0.85)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.04, 0.05, 0.06, 0.75))
		draw_rect(r, Color(ready_col, 0.5 if cooldown > 0.0 else 0.9), false, 1.5)
		if cooldown > 0.0:
			var f := clampf(cooldown / maxf(cooldown_total, 0.01), 0.0, 1.0)
			draw_rect(Rect2(Vector2(0, size.y * (1.0 - f)), Vector2(size.x, size.y * f)), Color(0, 0, 0, 0.6))
			draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.55), "%.1f" % cooldown, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color(1, 1, 1, 0.95))
		draw_string(ThemeDB.fallback_font, Vector2(4, 13), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.9, 0.6))
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y - 5), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, ready_col)
		if charges >= 0:
			draw_string(ThemeDB.fallback_font, Vector2(0, 13), "x%d" % charges, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 11, Color(1, 1, 1))


class HitMarker extends Control:
	var t := 0.0

	func _draw() -> void:
		if t <= 0.0:
			return
		var c := size * 0.5
		var col := Color(1, 0.85, 0.7, t)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 6.0, c + d * 13.0, col, 2.0, true)


class RoarMarkers extends Control:
	var marks: Array = []  ## [Vector3, expires_at]
	var camera: Camera3D

	func _draw() -> void:
		if camera == null:
			return
		for m in marks:
			var p: Vector3 = m[0] + Vector3.UP * 1.0
			if camera.is_position_behind(p):
				continue
			var s := camera.unproject_position(p)
			var pts := PackedVector2Array([s + Vector2(0, -8), s + Vector2(7, 0), s + Vector2(0, 8), s + Vector2(-7, 0)])
			draw_colored_polygon(pts, Color(1.0, 0.25, 0.15, 0.85))


func _ready() -> void:
	layer = 9
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = sh
	_vignette.material = _vignette_mat
	add_child(_vignette)

	_markers = RoarMarkers.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_markers)

	_hitmark = HitMarker.new()
	_hitmark.set_anchors_preset(Control.PRESET_CENTER)
	_hitmark.size = Vector2(40, 40)
	_hitmark.position = -_hitmark.size * 0.5
	_hitmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hitmark)

	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 18
	left.offset_top = -92
	left.offset_right = 260
	left.offset_bottom = -16
	left.add_theme_constant_override("separation", 5)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	_power_label = _label(15, GOLD)
	left.add_child(_power_label)
	_health_bar = Bar.new()
	_health_bar.custom_minimum_size = Vector2(230, 16)
	_health_bar.fill = Color(0.7, 0.12, 0.1)
	left.add_child(_health_bar)
	_stamina_bar = Bar.new()
	_stamina_bar.custom_minimum_size = Vector2(230, 10)
	_stamina_bar.fill = Color(0.35, 0.7, 0.6)
	left.add_child(_stamina_bar)
	_stamina_bar.hide()

	_slots_box = HBoxContainer.new()
	_slots_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_slots_box.offset_top = -70
	_slots_box.offset_bottom = -16
	_slots_box.offset_left = -150
	_slots_box.offset_right = 150
	_slots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_box.add_theme_constant_override("separation", 6)
	_slots_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots_box)
	_controls_panel = PanelContainer.new()
	_controls_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_controls_panel.offset_left = -520
	_controls_panel.offset_right = 520
	_controls_panel.offset_top = -116
	_controls_panel.offset_bottom = -88
	_controls_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var controls_style := StyleBoxFlat.new()
	controls_style.bg_color = Color(0.025, 0.03, 0.035, 0.78)
	controls_style.border_color = Color(0.48, 0.4, 0.29, 0.72)
	controls_style.border_width_top = 1
	controls_style.border_width_bottom = 1
	controls_style.content_margin_left = 18
	controls_style.content_margin_right = 18
	controls_style.content_margin_top = 3
	controls_style.content_margin_bottom = 3
	_controls_panel.add_theme_stylebox_override("panel", controls_style)
	_controls_label = _label(14, Color(0.91, 0.87, 0.78))
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_panel.add_child(_controls_label)
	add_child(_controls_panel)

	_status_label = _label(14, EMBER)
	_status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status_label.offset_top = -144
	_status_label.offset_bottom = -122
	_status_label.offset_left = -300
	_status_label.offset_right = 300
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)

	_notice = _label(15, Color(1, 0.8, 0.7))
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_notice.offset_top = 70
	_notice.offset_bottom = 95
	_notice.offset_left = -300
	_notice.offset_right = 300
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_notice)

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -360
	_feed.offset_right = -16
	_feed.offset_top = 78
	_feed.offset_bottom = 262
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)


func _label(font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func attach_player(p: PlayerController) -> void:
	player = p
	_markers.camera = p.camera
	Combat.damage_dealt.connect(_on_damage)
	Combat.attack_dodged.connect(_on_dodged)
	Combat.player_defeated.connect(_on_defeated)
	Combat.player_respawned.connect(_on_respawned)
	Combat.ability_rejected.connect(_on_rejected)
	Combat.ability_resolved.connect(_on_resolved)
	Combat.transform_started.connect(_on_transform)
	Combat.roar_marks.connect(_on_roar_marks)
	Combat.roar_heard.connect(_on_roar_heard)
	PowerScore.power_changed.connect(_on_power)
	GameState.identity_granted.connect(_on_identity)


# --- per-frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if player == null or player.player_id < 0:
		return
	var id := player.player_id
	var c := player.combatant
	_health_bar.value = move_toward(_health_bar.value, float(c.health), delta * 100.0)
	_health_bar.max_value = c.max_health
	_health_bar.label = "%d / %d" % [c.health, c.max_health]
	_health_bar.queue_redraw()
	_stamina_bar.value = player.stamina
	_stamina_bar.max_value = player.max_stamina
	_stamina_bar.fill = Color(0.6, 0.35, 0.2) if player.exhausted else Color(0.35, 0.7, 0.6)
	_stamina_bar.label = ""
	_stamina_bar.queue_redraw()
	_power_label.text = "POWER  %d" % PowerScore.score(id)
	_update_slots()
	_update_weapon_controls()
	_status_label.text = status_text()
	_status_label.visible = not player.riding
	_hurt = move_toward(_hurt, 0.0, delta * 1.5)
	_vignette_mat.set_shader_parameter("intensity", _hurt + (0.25 if player.is_defeated else 0.0))
	_hitmark.t = move_toward(_hitmark.t, 0.0, delta * 4.0)
	_hitmark.queue_redraw()
	var now := Combat.now()
	_markers.marks = _markers.marks.filter(func(m: Array) -> bool: return m[1] > now)
	_markers.queue_redraw()
	_notice_t -= delta
	if _notice_t <= 0.0:
		_notice.text = ""


## Private status line (local player only). Empty for humans.
func status_text() -> String:
	var id := player.player_id
	var st := Combat.transform_status(id)
	var key := Settings.get_binding_text("transform")
	match st["phase"]:
		"hidden_ready": return "EMBER BEAST (hidden)   [%s] transform" % key
		"hidden_cooldown": return "Hidden   transform ready in %ds" % ceili(st["time_left"])
		"transforming": return "Transforming..."
		"revealed_locked": return "REVEALED   can return to human in %ds" % ceili(st["time_left"])
		"revealed_free": return "REVEALED   [%s] return to human" % key
	return ""


func _update_slots() -> void:
	_slots_box.visible = not player.riding
	var form := GameState.current_form(player.player_id)
	if form.id != _form_id:
		_form_id = form.id
		for ch in _slots_box.get_children():
			ch.queue_free()
		_slots.clear()
		for ab in form.abilities:
			var s := Slot.new()
			s.custom_minimum_size = Vector2(68, 54)
			s.title = ab.display_name
			s.cooldown_total = ab.cooldown
			s.ready_col = EMBER if form is MonsterDefinition else Color(0.85, 0.88, 0.85)
			_slots_box.add_child(s)
			_slots[ab.id] = s
	for ab in form.abilities:
		var s: Slot = _slots.get(ab.id)
		if s == null:
			continue
		s.key_text = Settings.get_binding_text(ab.input_action)
		s.cooldown = Combat.cooldown_remaining(player.player_id, ab.id)
		s.charges = Combat.charges_left(player.player_id, ab)
		s.queue_redraw()


func slot_ids() -> Array:
	return _slots.keys()


func _update_weapon_controls() -> void:
	var controls := ""
	var rig: CommanderRig
	var visual := player.get_node_or_null("AvatarVisual") as AvatarVisual
	if visual and not GameState.is_revealed(player.player_id) and not Combat.is_transforming(player.player_id):
		rig = visual.human_rig as CommanderRig
	if player.riding:
		controls = "HORSE   WASD Steer   %s Slash   %s Gait   %s Walk / trot   %s Dismount   %s Lamp" % [
			Settings.get_binding_text("attack"), Settings.get_binding_text("sprint"), Settings.get_binding_text("crouch"),
			Settings.get_binding_text("interact"), Settings.get_binding_text("toggle_lamp")]
	elif GameState.is_revealed(player.player_id):
		controls = "BEAST   %s Claw   %s Fire Breath   %s Dodge / Pounce   %s Ward / Roar" % [
			Settings.get_binding_text("attack"), Settings.get_binding_text("heavy_attack"),
			Settings.get_binding_text("ability_1"), Settings.get_binding_text("ability_2")]
	elif rig and rig.sword_drawn and rig.offhand_sword != null and rig.offhand_sword.visible:
		controls = "DUAL   LMB Combo   RMB Alt. cut   %s Finisher   %s Dodge   %s Ward   %s Sheathe   %s Army   %s Lamp" % [
			Settings.get_binding_text("special_attack"), Settings.get_binding_text("ability_1"), Settings.get_binding_text("ability_2"),
			Settings.get_binding_text("toggle_weapons"), Settings.get_binding_text("army_command"), Settings.get_binding_text("toggle_lamp")]
	elif rig:
		controls = "EXPLORE   LMB Dual strike   %s Finisher   %s Dodge   %s Ward   %s Draw both   %s Army   %s Lamp" % [
			Settings.get_binding_text("special_attack"), Settings.get_binding_text("ability_1"), Settings.get_binding_text("ability_2"),
			Settings.get_binding_text("toggle_weapons"), Settings.get_binding_text("army_command"), Settings.get_binding_text("toggle_lamp")]
	if controls != _controls_text:
		_controls_text = controls
		_controls_label.text = controls
		_controls_panel.visible = controls != ""


# --- feed --------------------------------------------------------------------------------------

func feed(text: String, col := Color(0.9, 0.92, 0.9)) -> void:
	var l := _label(14, col)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	while _feed.get_child_count() > FEED_MAX:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func feed_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for ch in _feed.get_children():
		if ch is Label and not ch.is_queued_for_deletion():
			out.append(ch.text)
	return out


func notice(text: String, seconds := 1.6) -> void:
	_notice.text = text
	_notice_t = seconds


## How another player appears to the local player: a revealed beast is shown
## as its form; anyone else only by their public name.
func _who(id: int) -> String:
	var v := GameState.public_view(id)
	if v.is_empty():
		return "Something"
	if v["visible_form"] != "human":
		return "An " + GameState.monster_definition(v["visible_form"]).display_name
	return v["name"]


func _near(pos: Vector3, radius: float) -> bool:
	return player.global_position.distance_to(pos) <= radius


func _on_damage(e: Dictionary) -> void:
	var me := player.player_id
	if e["target"] == me:
		_hurt = clampf(_hurt + 0.45 + e["amount"] / 60.0, 0.0, 1.0)
		player.add_shake(0.25 + e["amount"] / 80.0)
		feed("%s hits you  -%d" % [_who(e["source"]), e["amount"]], Color(1.0, 0.55, 0.5))
	elif e["source"] == me:
		_hitmark.t = 1.0
		feed("You hit %s  -%d" % [GameState.public_view(e["target"]).get("name", "?"), e["amount"]], Color(1.0, 0.9, 0.75))


func _on_dodged(target: int, source: int, _ability: String) -> void:
	if target == player.player_id:
		feed("Dodged!", Color(0.7, 0.85, 1.0))
	elif source == player.player_id:
		feed("%s dodged" % GameState.public_view(target).get("name", "?"))


func _on_defeated(e: Dictionary) -> void:
	var me := player.player_id
	if e["victim"] == me:
		feed("You were defeated", Color(1.0, 0.4, 0.35))
		if Combat.respawn_mode(me) == Combat.Respawn.AUTO:
			notice("Defeated - returning shortly", float(Combat.defeat_duration))
		else:
			notice("The commander has fallen", 2.5)
	elif e["killer"] == me:
		feed("You defeated %s" % GameState.public_view(e["victim"]).get("name", "?"), GOLD)
	else:
		var av := Combat.avatar(e["victim"])
		if av and _near(av.global_position, 40.0):
			feed("%s has fallen" % GameState.public_view(e["victim"]).get("name", "?"))


func _on_respawned(id: int) -> void:
	if id == player.player_id:
		feed("You find your feet again (protected for %ds)" % int(Combat.respawn_invulnerability), Color(0.75, 0.9, 0.8))


func _on_rejected(id: int, action: String, reason: String) -> void:
	if id != player.player_id or reason == "no ability":
		return
	var what := action.capitalize()
	if action == "transform":
		var st := Combat.transform_status(id)
		if reason == "cooldown":
			notice("Transform ready in %ds" % ceili(st["time_left"]))
			return
		if reason == "locked":
			notice("Too soon to hide again (%ds)" % ceili(st["time_left"]))
			return
		if reason == "no room":
			notice("Not enough room to transform")
			return
		if reason == "no monster powers":
			return
	if reason == "cooldown":
		return
	notice("%s: %s" % [what, reason])


func _on_resolved(id: int, ability_id: String, hits: Array) -> void:
	var me := player.player_id
	if id == me and ability_id == "ward":
		var ab := GameState.HUMAN_FORM.ability("ward")
		feed("Ward flare! (%d left)" % Combat.charges_left(me, ab), GOLD)
	elif ability_id == "ward" and hits.has(me):
		feed("A ward flare sears you!", Color(1.0, 0.85, 0.5))
	elif ability_id == "roar" and hits.has(me):
		feed("The roar shakes you - you can't sprint", Color(1.0, 0.6, 0.4))


func _on_transform(id: int, _monster: String, _d: float) -> void:
	if id == player.player_id:
		return
	var av := Combat.avatar(id)
	if av and _near(av.global_position, 50.0):
		feed("Something monstrous emerges nearby!", Color(1.0, 0.45, 0.3))


func _on_roar_marks(id: int, positions: PackedVector3Array, duration: float) -> void:
	if id != player.player_id:
		return
	for p in positions:
		_markers.marks.append([p, Combat.now() + duration])
	if not positions.is_empty():
		feed("Your roar exposes %d nearby" % positions.size(), EMBER)


func _on_roar_heard(id: int, pos: Vector3, radius: float) -> void:
	if id != player.player_id and _near(pos, radius):
		feed("A terrible roar nearby...", Color(1.0, 0.55, 0.4))


func _on_power(id: int, value: int, delta: int, reason: String) -> void:
	if id != player.player_id:
		return
	feed("%+d Power - %s" % [delta, reason], GOLD if delta >= 0 else Color(1.0, 0.5, 0.4))
	var lib := AudioLib.get_instance()
	var s := AudioStreamPlayer.new()
	s.stream = lib.get_stream("power_up")
	s.volume_db = -8.0
	add_child(s)
	s.play()
	s.finished.connect(s.queue_free)


func _on_identity(id: int, monster_id: String) -> void:
	if id != player.player_id:
		return
	var def := GameState.monster_definition(monster_id)
	feed("An ancient hunger awakens: the %s" % def.display_name, EMBER)
	notice("You look human. Press [%s] to reveal the %s." % [Settings.get_binding_text("transform"), def.display_name], 5.0)
