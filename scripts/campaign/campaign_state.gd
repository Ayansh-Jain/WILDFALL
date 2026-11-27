class_name CampaignState
extends RefCounted
## The campaign's persistent model: which missions are reserved / unlocked /
## complete, the state of each mission slot, the allied roster (every soldier's
## name, life and health) and the encounter checkpoint used by Retry. Pure data
## with validated transitions and JSON (de)serialisation, so it is tested without
## a scene and saved as one small versioned file. CampaignDirector is the only
## thing that changes it.

enum M {
	RESERVED,            ## Future content, disabled until the developer enables it.
	LOCKED,              ## An earlier mission is not complete yet.
	AWAITING_BRIEFING,   ## Next mission; the King briefs it at the evening council.
	BRIEFING_AVAILABLE,  ## Evening: speak with the King.
	BRIEFING,            ## The King is giving the orders.
	ACTIVE,              ## Briefed: travel to the target area.
	ENCOUNTER_ACTIVE,    ## Fighting.
	OBJECTIVE_COMPLETED, ## Won (spies have fled / the field is clear).
	RETURN_TO_CASTLE,    ## Report to the King.
	COMPLETE,            ## Reported; the reward has been granted.
	FAILED,              ## The commander fell: Retry or Quit.
	RETRY_AVAILABLE,     ## Quit after a failure: the same encounter waits at its area.
}

const NAMES := {
	M.RESERVED: "Reserved", M.LOCKED: "Locked", M.AWAITING_BRIEFING: "Awaiting briefing",
	M.BRIEFING_AVAILABLE: "Briefing available", M.BRIEFING: "Briefing", M.ACTIVE: "Mission active",
	M.ENCOUNTER_ACTIVE: "Encounter active", M.OBJECTIVE_COMPLETED: "Objective completed",
	M.RETURN_TO_CASTLE: "Return to castle", M.COMPLETE: "Mission complete", M.FAILED: "Mission failed",
	M.RETRY_AVAILABLE: "Retry available",
}

## Every allowed change. Anything else is refused (and reported), so duplicate
## activation, double completion and skipped steps cannot happen.
const TRANSITIONS := {
	M.RESERVED: [M.LOCKED],
	M.LOCKED: [M.AWAITING_BRIEFING],
	M.AWAITING_BRIEFING: [M.BRIEFING_AVAILABLE],
	M.BRIEFING_AVAILABLE: [M.AWAITING_BRIEFING, M.BRIEFING],
	M.BRIEFING: [M.ACTIVE],
	M.ACTIVE: [M.ENCOUNTER_ACTIVE],
	M.ENCOUNTER_ACTIVE: [M.OBJECTIVE_COMPLETED, M.FAILED],
	M.OBJECTIVE_COMPLETED: [M.RETURN_TO_CASTLE],
	M.RETURN_TO_CASTLE: [M.COMPLETE],
	M.COMPLETE: [],
	M.FAILED: [M.ENCOUNTER_ACTIVE, M.RETRY_AVAILABLE],
	M.RETRY_AVAILABLE: [M.ENCOUNTER_ACTIVE],
}

const SAVE_VERSION := 1

var coins := 0
var coin_rewards := {}
var config := {}
## mission id -> M
var states := {}
var completed: Array[int] = []
## [{id, name, alive, health}] - the allied roster, commander excluded.
var roster: Array[Dictionary] = []
var next_soldier_id := 1
## The encounter checkpoint: the roster as it stood when the encounter began.
var checkpoint := {}
## Absolute campaign hours (days * 24 + hour) before which no new briefing is given.
var next_briefing_after := -1.0
var campaign_complete := false
## Refused transitions (diagnostics and tests).
var rejected: Array[String] = []


static func load_config(path := "res://data/campaign.json") -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CampaignState: cannot read %s" % path)
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _init(p_config := {}) -> void:
	config = p_config


## A fresh campaign: the starting soldiers, Mission 1 reserved, the first enabled
## mission awaiting its briefing, everything after it locked.
func new_campaign() -> void:
	coins = 0
	coin_rewards.clear()
	states.clear()
	completed.clear()
	roster.clear()
	next_soldier_id = 1
	checkpoint = {}
	next_briefing_after = -1.0
	campaign_complete = false
	for m in missions():
		states[int(m["id"])] = M.RESERVED if not bool(m.get("enabled", true)) else M.LOCKED
	recruit(int(army().get("start_size", 4)))
	_advance_to_next()


func missions() -> Array:
	return config.get("missions", [])


func mission(id: int) -> Dictionary:
	for m in missions():
		if int(m["id"]) == id:
			return m
	return {}


func army() -> Dictionary:
	return config.get("army", {})


func state_of(id: int) -> int:
	return states.get(id, M.LOCKED)


func state_name(id: int) -> String:
	return NAMES.get(state_of(id), "?")


static func can_transition(from: int, to: int) -> bool:
	return to in TRANSITIONS.get(from, [])


## Validated mission state change. Returns false and changes nothing if refused.
func transition(id: int, to: int) -> bool:
	var from := state_of(id)
	# One open mission at a time: a mission unlocks only when nothing else is open.
	var early := from == M.LOCKED and to == M.AWAITING_BRIEFING and current_mission() >= 0
	if early or not can_transition(from, to):
		rejected.append("%d: %s -> %s" % [id, NAMES.get(from, "?"), NAMES.get(to, "?")])
		return false
	states[id] = to
	if to == M.COMPLETE and not completed.has(id):
		completed.append(id)
		var reward := int(mission(id).get("reward_soldiers", army().get("growth_per_mission", 10)))
		if reward > 0:
			recruit(reward)
		_advance_to_next()
	return true


## The mission the King will brief or is running: the first enabled, unfinished one.
func current_mission() -> int:
	for m in missions():
		var id := int(m["id"])
		var s := state_of(id)
		if s != M.RESERVED and s != M.LOCKED and s != M.COMPLETE:
			return id
	return -1


## Missions that are not complete, not reserved and not locked (0 or 1 of them).
func open_missions() -> Array[int]:
	var out: Array[int] = []
	for m in missions():
		var s := state_of(int(m["id"]))
		if s != M.RESERVED and s != M.LOCKED and s != M.COMPLETE:
			out.append(int(m["id"]))
	return out


## Unlocks the next enabled mission after one completes (or at a new campaign).
func _advance_to_next() -> void:
	if current_mission() >= 0:
		return
	for m in missions():
		var id := int(m["id"])
		if state_of(id) == M.LOCKED:
			transition(id, M.AWAITING_BRIEFING)
			return
	campaign_complete = completed.size() > 0 and current_mission() < 0


## Developer switch for the reserved Mission 1 (kept disabled in this phase).
func enable_reserved(id: int) -> bool:
	if state_of(id) != M.RESERVED:
		return false
	transition(id, M.LOCKED)
	return true


# --- roster ---------------------------------------------------------------------------------

func recruit(count: int) -> void:
	var names: Array = army().get("names", [])
	for i in count:
		var n := "Soldier %d" % next_soldier_id
		if next_soldier_id - 1 < names.size():
			n = String(names[next_soldier_id - 1])
		roster.append({"id": next_soldier_id, "name": n, "alive": true, "health": 100})
		next_soldier_id += 1


func roster_size() -> int:
	return roster.size()


func alive_count() -> int:
	var n := 0
	for s in roster:
		if s["alive"]:
			n += 1
	return n


func soldier(id: int) -> Dictionary:
	for s in roster:
		if int(s["id"]) == id:
			return s
	return {}


func set_soldier(id: int, alive: bool, health: int) -> void:
	var s := soldier(id)
	if s.is_empty():
		return
	s["alive"] = alive
	s["health"] = clampi(health, 0, 100) if alive else 0


## The explicit encounter checkpoint: the roster (who lives, at what health) and
## the mission's configuration, captured as the encounter begins.
func take_checkpoint(mission_id: int) -> void:
	checkpoint = {"mission": mission_id, "roster": roster.duplicate(true)}


## Retry: the roster returns exactly to the checkpoint (same size, same survivors,
## same health). Returns false when there is no checkpoint for this mission.
func restore_checkpoint(mission_id: int) -> bool:
	if checkpoint.is_empty() or int(checkpoint.get("mission", -1)) != mission_id:
		return false
	var saved: Array = checkpoint["roster"]
	roster.clear()
	for s in saved:
		roster.append((s as Dictionary).duplicate())
	return true


# --- persistence ----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var st := {}
	for id in states:
		st[str(id)] = NAMES[states[id]]
	return {
		"version": SAVE_VERSION,
		"coins": coins,
		"coin_rewards": coin_rewards.duplicate(),
		"states": st,
		"completed": completed.duplicate(),
		"roster": roster.duplicate(true),
		"next_soldier_id": next_soldier_id,
		"checkpoint": checkpoint.duplicate(true),
		"next_briefing_after": next_briefing_after,
		"campaign_complete": campaign_complete,
	}


## Loads a saved campaign. Unknown versions are refused. A save made mid-encounter
## (a crash) resumes as "retry available" with the checkpoint roster, and a save
## made mid-briefing resumes with the briefing available again.
func from_dict(d: Dictionary) -> bool:
	if int(d.get("version", -1)) != SAVE_VERSION:
		return false
	new_campaign()
	coins = maxi(0, int(d.get("coins", 0)))
	coin_rewards = d.get("coin_rewards", {}).duplicate()
	var by_name := {}
	for k in NAMES:
		by_name[NAMES[k]] = k
	var st: Dictionary = d.get("states", {})
	for key in st:
		var id := int(key)
		if mission(id).is_empty() or not by_name.has(st[key]):
			continue
		var s: int = by_name[st[key]]
		# Reserved stays reserved unless the config enables it.
		if not bool(mission(id).get("enabled", true)):
			s = M.RESERVED
		elif s == M.RESERVED:
			# Preserve existing campaigns: the new opening is available through New Campaign.
			s = M.COMPLETE if id == 1 else M.LOCKED
		states[id] = s
	completed.clear()
	for id in d.get("completed", []):
		completed.append(int(id))
	if states.get(1) == M.COMPLETE and not completed.has(1):
		completed.append(1)
	roster.clear()
	for s in d.get("roster", []):
		roster.append({"id": int(s["id"]), "name": String(s["name"]), "alive": bool(s["alive"]), "health": int(s["health"])})
	next_soldier_id = int(d.get("next_soldier_id", roster.size() + 1))
	checkpoint = d.get("checkpoint", {})
	next_briefing_after = float(d.get("next_briefing_after", -1.0))
	campaign_complete = bool(d.get("campaign_complete", false))
	for id in states.keys():
		match int(states[id]):
			M.ENCOUNTER_ACTIVE, M.FAILED:
				restore_checkpoint(id)
				states[id] = M.RETRY_AVAILABLE
			M.BRIEFING:
				states[id] = M.BRIEFING_AVAILABLE
			M.OBJECTIVE_COMPLETED:
				states[id] = M.RETURN_TO_CASTLE
	_advance_to_next()
	return true
