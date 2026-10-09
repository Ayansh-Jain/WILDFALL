extends Node
## Power score (autoload "PowerScore"). The only place score changes happen.
##
## Power is deliberately separate from combat strength: nothing here touches
## health or damage. Every award has a unique key, so replayed or duplicated
## events can never pay out twice.

signal power_changed(player_id: int, value: int, delta: int, reason: String)

var rules: ScoringRules = preload("res://data/scoring_rules.tres")

var _scores := {}     ## player id -> int
var _awarded := {}    ## award key -> true
var _encounters := {} ## "monster>human" -> {monster, human, last_hit, serial}
var _encounter_serial := 0


func _ready() -> void:
	process_physics_priority = -5
	GameState.player_registered.connect(register)
	Combat.player_defeated.connect(_on_defeated)
	Combat.damage_dealt.connect(_on_damage)


func register(player_id: int) -> void:
	if not _scores.has(player_id):
		_scores[player_id] = rules.base_score


func score(player_id: int) -> int:
	return _scores.get(player_id, rules.base_score)


func was_awarded(key: String) -> bool:
	return _awarded.has(key)


## Applies a change once per key. Returns false if the key was already used.
func change(player_id: int, delta: int, reason: String, key: String) -> bool:
	if _awarded.has(key) or player_id < 0:
		return false
	_awarded[key] = true
	register(player_id)
	var old: int = _scores[player_id]
	var value := maxi(rules.min_score, old + delta)
	_scores[player_id] = value
	power_changed.emit(player_id, value, value - old, reason)
	return true


func _on_defeated(e: Dictionary) -> void:
	var did: String = e["defeat_id"]
	var victim: int = e["victim"]
	var killer: int = e["killer"]
	_close_encounters_for(victim)
	if e["victim_was_revealed"]:
		change(victim, -rules.monster_defeat_penalty, "defeated as a monster", "defeat:%s:victim" % did)
		if killer >= 0 and killer != victim:
			change(killer, rules.monster_slayer_reward, "slew a monster", "defeat:%s:killer" % did)
		for c in e["contributors"]:
			if c != killer and c != victim:
				change(c, rules.monster_assist_reward, "helped slay a monster", "defeat:%s:assist:%d" % [did, c])
	elif e["killer_was_revealed"]:
		change(killer, rules.prey_reward, "prey defeated", "defeat:%s:killer" % did)
		change(victim, -rules.prey_penalty, "taken by a monster", "defeat:%s:victim" % did)


func _on_damage(e: Dictionary) -> void:
	var src: int = e["source"]
	var tgt: int = e["target"]
	if src < 0 or not GameState.is_revealed(src) or GameState.is_revealed(tgt):
		return
	var key := "%d>%d" % [src, tgt]
	if not _encounters.has(key):
		_encounter_serial += 1
		_encounters[key] = {"monster": src, "human": tgt, "serial": _encounter_serial, "last_hit": 0.0}
	_encounters[key]["last_hit"] = Combat.now()


func _close_encounters_for(player_id: int) -> void:
	for key in _encounters.keys():
		var enc: Dictionary = _encounters[key]
		if enc["human"] == player_id:
			_encounters.erase(key)


## Escape: the human survives `escape_time` since the last hit and is far away.
func _physics_process(_delta: float) -> void:
	for key in _encounters.keys():
		var enc: Dictionary = _encounters[key]
		if Combat.now() - float(enc["last_hit"]) < rules.escape_time:
			continue
		var m := Combat.avatar(enc["monster"])
		var h := Combat.avatar(enc["human"])
		if h == null or not PlayerState.is_alive_state(GameState.get_state(enc["human"])):
			_encounters.erase(key)
			continue
		if m == null or m.global_position.distance_to(h.global_position) >= rules.escape_distance:
			change(enc["human"], rules.escape_reward, "escaped a monster", "escape:%d" % enc["serial"])
			_encounters.erase(key)
