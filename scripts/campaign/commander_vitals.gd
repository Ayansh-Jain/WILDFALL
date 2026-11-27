extends Node
## Local commander regeneration and campaign wallet; Combat remains the authority.
var c: CampaignDirector
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay_upgrade.json"))
var since_damage := 0.0
var healing_credit := 0.0
var coin_label: Label
var coin_tween: Tween
func setup(campaign: CampaignDirector) -> void:
	c = campaign
	Combat.damage_dealt.connect(_damaged)
	Combat.player_defeated.connect(_defeated)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -210
	panel.offset_right = -24
	panel.offset_top = 18
	panel.offset_bottom = 60
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06,0.045,0.02,0.88)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel",style)
	coin_label = Label.new()
	coin_label.add_theme_color_override("font_color",Color(1,0.78,0.28))
	coin_label.add_theme_font_size_override("font_size",22)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var icon := Control.new()
	icon.set_script(load("res://scripts/ui/coin_icon.gd"))
	row.add_child(icon)
	row.add_child(coin_label)
	c.chud.add_child(panel)
	_update_coins()
func _damaged(e: Dictionary) -> void:
	if int(e.target)==c.player.player_id:
		since_damage = 0
		healing_credit = 0
func _process(delta: float) -> void:
	if not c:
		return
	_update_coins()
	if c.player.is_defeated or not c.player.combatant.is_alive():
		healing_credit = 0
		since_damage = 0
		return
	var previous := since_damage
	since_damage += delta
	var elapsed := maxf(0,since_damage-maxf(previous,float(config.regen_delay)))
	if c.player.combatant.health >= c.player.combatant.max_health:
		healing_credit = 0
		return
	healing_credit += elapsed * float(config.regen_hp_per_second)
	var hp := int(healing_credit)
	if hp>0:
		healing_credit -= hp
		Combat.heal_player(c.player.player_id,hp)
func _defeated(e: Dictionary) -> void:
	var victim := Combat.avatar(int(e.victim))
	if not victim or not victim.body_style.begins_with("soldier:enemy"):
		return
	var killer := int(e.killer)
	var valid := killer == c.player.player_id
	for b in c.army.living():
		valid = valid or b.avatar.player_id == killer
	if not valid:
		return
	var brain := victim.get_node_or_null("Brain") as SoldierBrain
	if not brain or brain.mission_id < 0:
		return
	var key := "%d:%d" % [brain.mission_id,brain.soldier_id]
	if c.state.coin_rewards.has(key):
		return
	c.state.coin_rewards[key] = true
	c.state.coins += int(config.kill_coins)
	_update_coins()
	if coin_tween:
		coin_tween.kill()
	coin_label.scale = Vector2.ONE * 1.12
	coin_tween = create_tween()
	coin_tween.tween_property(coin_label,"scale",Vector2.ONE,0.3)
	c.save()
func _update_coins() -> void:
	coin_label.text = "%d" % c.state.coins
