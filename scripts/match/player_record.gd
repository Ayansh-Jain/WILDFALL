class_name PlayerRecord
extends RefCounted
## Server-side record of one player. `monster_id` is secret: it must only ever
## be sent to the owning player (see GameState.private_view).

var id := -1
var display_name := ""
var is_local := false
var is_bot := false
var state: int = PlayerState.State.HUMAN
var monster_id := ""


func has_monster() -> bool:
	return monster_id != ""
