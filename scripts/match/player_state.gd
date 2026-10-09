class_name PlayerState
extends RefCounted
## The single source of truth for what a player is doing, with validated
## transitions. "Has monster powers" is stored separately on the PlayerRecord
## (monster_id); this enum says whether those powers are currently revealed.

enum State { HUMAN, MONSTER_HIDDEN, MONSTER_REVEALED, DEFEATED, RESPAWNING }

const NAMES := ["HUMAN", "MONSTER_HIDDEN", "MONSTER_REVEALED", "DEFEATED", "RESPAWNING"]

## from -> allowed targets
const TRANSITIONS := {
	State.HUMAN: [State.MONSTER_HIDDEN, State.DEFEATED],
	State.MONSTER_HIDDEN: [State.MONSTER_REVEALED, State.DEFEATED],
	State.MONSTER_REVEALED: [State.MONSTER_HIDDEN, State.DEFEATED],
	State.DEFEATED: [State.RESPAWNING],
	State.RESPAWNING: [State.HUMAN, State.MONSTER_HIDDEN],
}


## `has_monster` is whether the player holds monster powers after the change.
static func can_transition(from: int, to: int, has_monster: bool) -> bool:
	if not TRANSITIONS.get(from, []).has(to):
		return false
	match to:
		State.HUMAN:
			return not has_monster
		State.MONSTER_HIDDEN, State.MONSTER_REVEALED:
			return has_monster
	return true


static func name_of(state: int) -> String:
	return NAMES[state] if state >= 0 and state < NAMES.size() else "?"


static func is_alive_state(state: int) -> bool:
	return state in [State.HUMAN, State.MONSTER_HIDDEN, State.MONSTER_REVEALED]
