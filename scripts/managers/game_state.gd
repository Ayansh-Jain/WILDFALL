extends Node
## Match-state model, written as the future server's authority.
##
## Owns players (PlayerRecord), their validated state transitions, the scroll
## and the secret monster identity. Public signals never carry the identity of
## the scroll holder; `identity_granted` is a private, per-player message (in
## Phase 3 it becomes an RPC sent only to that peer).
##
## Command-line options (pass after `--`):
##   --world-seed=N    seed for terrain noise and prop scattering (default 1337)
##   --scroll-seed=N   reproducible scroll placement
##   --random-scroll   random scroll placement even in debug builds
##   --no-dev          disable developer tools in a debug build
##   --bots=N          number of simulated opponents (default 4)

signal scroll_spawned(marker_name: String)
## Public: the scroll is gone. Deliberately does not say who took it.
signal scroll_taken
## Private: only the player with this id may react to it.
signal identity_granted(player_id: int, monster_id: String)
signal player_state_changed(player_id: int, old_state: int, new_state: int)
signal player_registered(player_id: int)
signal match_reset

const DEFAULT_WORLD_SEED := 1337
const DEV_SCROLL_SEED := 20240
const SCROLL_MONSTER := "ember_beast"
const HUMAN_FORM := preload("res://data/forms/human.tres")

var world_seed: int = DEFAULT_WORLD_SEED
var scroll_seed: int = 0
var dev_mode: bool = false
var bot_count := 4
var args := {}

var scroll_marker: String = ""
var scroll_position: Vector3 = Vector3.ZERO
var scroll_is_collected: bool = false

var local_player_id := -1

var _players := {}  ## id -> PlayerRecord
var _next_id := 1
var _monster_cache := {}


func _ready() -> void:
	dev_mode = OS.is_debug_build()
	args = _parse_args()
	if args.has("no-dev"):
		dev_mode = false
	world_seed = int(args.get("world-seed", DEFAULT_WORLD_SEED))
	bot_count = int(args.get("bots", bot_count))
	if args.has("scroll-seed"):
		scroll_seed = int(args["scroll-seed"])
	elif dev_mode and not args.has("random-scroll"):
		scroll_seed = DEV_SCROLL_SEED
	else:
		scroll_seed = _random_seed()
	print("[GameState] world_seed=%d scroll_seed=%d dev_mode=%s" % [world_seed, scroll_seed, dev_mode])


# --- players ---------------------------------------------------------------------

func register_player(display_name: String, is_local := false, is_bot := false) -> int:
	var rec := PlayerRecord.new()
	rec.id = _next_id
	_next_id += 1
	rec.display_name = display_name
	rec.is_local = is_local
	rec.is_bot = is_bot
	_players[rec.id] = rec
	if is_local:
		local_player_id = rec.id
	player_registered.emit(rec.id)
	return rec.id


func unregister_player(id: int) -> void:
	_players.erase(id)
	if id == local_player_id:
		local_player_id = -1


func player_ids() -> Array:
	return _players.keys()


## Full record. Server-side only: never hand this to another player's client.
func record(id: int) -> PlayerRecord:
	return _players.get(id)


## What any player may know about player `id`.
func public_view(id: int) -> Dictionary:
	var r: PlayerRecord = _players.get(id)
	if r == null:
		return {}
	var revealed := r.state == PlayerState.State.MONSTER_REVEALED
	return {
		"id": r.id,
		"name": r.display_name,
		"alive": PlayerState.is_alive_state(r.state),
		# A revealed beast is visible to everyone, so its form is public.
		"visible_form": (r.monster_id if revealed else "human"),
	}


## What player `id` may know about itself.
func private_view(id: int) -> Dictionary:
	var r: PlayerRecord = _players.get(id)
	if r == null:
		return {}
	var v := public_view(id)
	v["monster_id"] = r.monster_id
	v["state"] = r.state
	return v


func get_state(id: int) -> int:
	var r: PlayerRecord = _players.get(id)
	return r.state if r else -1


func has_monster(id: int) -> bool:
	var r: PlayerRecord = _players.get(id)
	return r != null and r.has_monster()


func is_revealed(id: int) -> bool:
	return get_state(id) == PlayerState.State.MONSTER_REVEALED


## Validated state change. Returns false (and changes nothing) if not allowed.
func transition(id: int, to: int, reason := "") -> bool:
	var r: PlayerRecord = _players.get(id)
	if r == null:
		return false
	if not PlayerState.can_transition(r.state, to, r.has_monster()):
		push_warning("GameState: rejected %s -> %s for player %d (%s)" % [
			PlayerState.name_of(r.state), PlayerState.name_of(to), id, reason])
		return false
	var old := r.state
	r.state = to
	player_state_changed.emit(id, old, to)
	return true


func monster_definition(monster_id: String) -> MonsterDefinition:
	if monster_id == "":
		return null
	if not _monster_cache.has(monster_id):
		_monster_cache[monster_id] = load("res://data/monsters/%s.tres" % monster_id)
	return _monster_cache[monster_id]


## The form a player currently fights in (revealed monster or human body).
func current_form(id: int) -> FormDefinition:
	var r: PlayerRecord = _players.get(id)
	if r and r.state == PlayerState.State.MONSTER_REVEALED:
		return monster_definition(r.monster_id)
	return HUMAN_FORM


# --- scroll ------------------------------------------------------------------------

func register_scroll(marker_name: String, pos: Vector3) -> void:
	scroll_marker = marker_name
	scroll_position = pos
	scroll_is_collected = false
	scroll_spawned.emit(marker_name)


## Validates and applies a scroll pickup. Returns true only for the first
## successful collection by a living human.
func collect_scroll(player_id: int) -> bool:
	if scroll_is_collected:
		return false
	var r: PlayerRecord = _players.get(player_id)
	if r == null or r.state != PlayerState.State.HUMAN:
		return false
	scroll_is_collected = true
	_grant_monster(r, SCROLL_MONSTER)
	scroll_taken.emit()
	return true


## Developer/test hook: give a player monster powers without the scroll.
func grant_monster_for_testing(player_id: int, monster_id := SCROLL_MONSTER) -> bool:
	var r: PlayerRecord = _players.get(player_id)
	if r == null or r.has_monster() or r.state != PlayerState.State.HUMAN:
		return false
	_grant_monster(r, monster_id)
	return true


func _grant_monster(r: PlayerRecord, monster_id: String) -> void:
	r.monster_id = monster_id
	transition(r.id, PlayerState.State.MONSTER_HIDDEN, "scroll")
	identity_granted.emit(r.id, monster_id)


## Server-side query for tests and scoring; never shown in public UI.
func scroll_holder() -> int:
	for id in _players:
		if _players[id].monster_id == SCROLL_MONSTER:
			return id
	return -1


func reset_match(new_scroll_seed: int = -1) -> void:
	scroll_seed = new_scroll_seed if new_scroll_seed >= 0 else _random_seed()
	scroll_marker = ""
	scroll_is_collected = false
	for id in _players:
		var r: PlayerRecord = _players[id]
		r.monster_id = ""
		r.state = PlayerState.State.HUMAN
	match_reset.emit()


func _random_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x7fffffff


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
