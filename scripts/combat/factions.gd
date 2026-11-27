class_name Factions
extends RefCounted
## The ONE place that decides who may target whom. Teams are registered with Combat
## (SoldierFactory does it for every soldier); everything else asks here, so no script
## compares team-name strings itself.
##   kingdom  the commander and every maroon soldier (army, garrison)
##   enemy    the black-clad enemy kingdom (spies, raiders, captain)
## Combat's own rule still decides who can be HURT (different teams, or no team); the
## AI never aims at anything Combat would not let it hurt.

const KINGDOM := "kingdom"
const ENEMY := "enemy"


static func team_for(faction: String) -> String:
	return ENEMY if faction == "enemy" else KINGDOM


static func team_of(id: int) -> String:
	return Combat.team_of(id)


static func hostile(a: int, b: int) -> bool:
	return Combat.are_hostile(a, b)


static func allied(a: int, b: int) -> bool:
	return a != b and not Combat.are_hostile(a, b)


static func hostile_teams(a: String, b: String) -> bool:
	return a == "" or b == "" or a != b


## True while `id` is a living fighter that can be aimed at.
static func targetable(id: int) -> bool:
	if id < 0 or not PlayerState.is_alive_state(GameState.get_state(id)):
		return false
	var av := Combat.avatar(id)
	return av != null and not av.is_defeated
