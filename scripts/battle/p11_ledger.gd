extends RefCounted
## Isolated P11 state. No scene identity, physics, or autonomous targeting.
signal soldier_fell(id: String, cause: String)
var soldiers: Dictionary = {}
var pairs: Dictionary = {}
var clock := 0.0
var token := ""
var reactive: Dictionary = {}
var token_generation := 0
var token_deadline := 0.0
signal attack_invalidated(id: String, generation: int)

func setup(seed_value: int = 1337) -> void:
	reactive.clear()
	invalidate_attack()
	soldiers.clear()
	pairs.clear()
	clock = 0.0
	token = ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for side in ["a", "e"]:
		for i in range(100):
			var id := "%s.%03d" % [side, i]
			soldiers[id] = {"alive": true, "side": side, "role": "front" if i < 90 else ("reserve" if side == "a" else "elite"), "pair": ""}
	for i in range(90):
		var id := "pair.%03d" % i
		var a := "a.%03d" % i
		var e := "e.%03d" % i
		pairs[id] = {"a": a, "e": e, "generation": 0, "active": true, "due": rng.randf_range(25, 120), "victim": a if rng.randf() < 0.5 else e}
		soldiers[a].pair = id
		soldiers[e].pair = id

func interrupt(id: String) -> bool:
	if not soldiers.has(id) or not soldiers[id].alive:
		return false
	if token == id:
		invalidate_attack()
	var pair_id: String = soldiers[id].pair
	if pair_id.is_empty():
		return true
	var pair: Dictionary = pairs[pair_id]
	pair.active = false
	pair.generation += 1
	soldiers[pair.a].pair = ""
	soldiers[pair.e].pair = ""
	return true

func fall(id: String, cause: String) -> bool:
	if not interrupt(id):
		return false
	soldiers[id].alive = false
	reactive.erase(id)
	if token == id:
		token = ""
	soldier_fell.emit(id, cause)
	return true

func resolve(pair_id: String, generation: int) -> bool:
	if not pairs.has(pair_id):
		return false
	var pair: Dictionary = pairs[pair_id]
	if not pair.active or pair.generation != generation:
		return false
	return fall(pair.victim, "scripted")

func advance(delta: float) -> void:
	clock += maxf(delta, 0.0)
	if token != "" and clock >= token_deadline:
		invalidate_attack()
	for id in pairs:
		var pair: Dictionary = pairs[id]
		if pair.active and pair.due <= clock:
			resolve(id, pair.generation)

func request_token(id: String) -> bool:
	if not reactive.has(id) or not soldiers.has(id) or not soldiers[id].alive or soldiers[id].side != "e":
		return false
	if token != "" and token != id:
		return false
	if token == id:
		return true
	token_generation += 1
	token_deadline = clock + 5.0
	token = id
	return true

func set_reactive(id: String, encounter: String) -> bool:
	if not soldiers.has(id) or not soldiers[id].alive or soldiers[id].side != "e":
		return false
	if reactive.has(id):
		return reactive[id] == encounter
	if reactive.values().count(encounter) >= 5:
		return false
	reactive[id] = encounter
	return true

func invalidate_attack() -> void:
	if token.is_empty():
		return
	var old := token
	var generation := token_generation
	token = ""
	token_generation += 1
	attack_invalidated.emit(old, generation)

func finish_attack(id: String, generation: int) -> bool:
	if token != id or generation != token_generation:
		return false
	invalidate_attack()
	return true

func end_encounter(encounter: String) -> void:
	for id in reactive.keys():
		if reactive[id] == encounter:
			if token == id:
				invalidate_attack()
			reactive.erase(id)