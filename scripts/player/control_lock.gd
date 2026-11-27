class_name ControlLock
extends RefCounted
## Contract C-08: token-based control restrictions (adopted R01, 2026-11-26).
##
## Effective mask = OR of live tokens, so overlapping restrictions can never unlock the
## Commander early: each owner releases only its own token. Releasing an unknown token is a
## no-op. Not an autoload; the PlayerController owns one instance (`locks`). With no tokens
## held (the default) it has no effect, so existing `controls_enabled` code is unaffected.
##
## Scripted movement is a record on a token that holds MOVE: the controller walks the body
## to `target` at `speed`, and the record vanishes the moment its token is released.

signal mask_changed(new_mask: int, old_mask: int)

const MOVE := 1
const CAMERA := 2
const COMBAT := 4
const INTERACT := 8
const MOUNT := 16
const PAUSE := 32
const ALL := 63

## Debug-build warning threshold for a forgotten token (seconds, `Time` based).
const MAX_HOLD_S := 300.0

var _next_token := 1
var _tokens := {}  ## token:int -> {"owner": String, "mask": int, "t": int(msec)}
var _scripted := {}  ## token:int -> {"target": Vector3, "speed": float}
var _mask := 0


func acquire(owner_id: String, lock_mask: int) -> int:
	var token := _next_token
	_next_token += 1
	_tokens[token] = {"owner": owner_id, "mask": lock_mask & ALL, "t": Time.get_ticks_msec()}
	_recompute()
	return token


func release(token: int) -> void:
	if not _tokens.has(token):
		return
	_tokens.erase(token)
	_scripted.erase(token)
	_recompute()


func release_all(owner_id: String) -> void:
	for token in _tokens.keys():
		if _tokens[token]["owner"] == owner_id:
			_tokens.erase(token)
			_scripted.erase(token)
	_recompute()


func mask() -> int:
	return _mask


func blocks(flag: int) -> bool:
	return (_mask & flag) != 0


func is_held(token: int) -> bool:
	return _tokens.has(token)


func token_count() -> int:
	return _tokens.size()


## The scripted walk is only accepted for a live token that holds MOVE.
func begin_scripted_move(target: Vector3, speed: float, token: int) -> bool:
	if not _tokens.has(token) or (int(_tokens[token]["mask"]) & MOVE) == 0:
		return false
	_scripted[token] = {"target": target, "speed": speed}
	return true


func end_scripted_move(token: int) -> void:
	_scripted.erase(token)


## The most recently started scripted move still alive, or {} (no allocation when idle).
func active_scripted() -> Dictionary:
	if _scripted.is_empty():
		return {}
	var last := -1
	for token in _scripted:
		last = maxi(last, token)
	return _scripted[last]


func active_scripted_token() -> int:
	var last := -1
	for token in _scripted:
		last = maxi(last, token)
	return last


## Owners of tokens older than MAX_HOLD_S (for a debug warning).
func stale_owners() -> PackedStringArray:
	var out := PackedStringArray()
	var now := Time.get_ticks_msec()
	for token in _tokens:
		if (now - int(_tokens[token]["t"])) / 1000.0 > MAX_HOLD_S:
			out.append(String(_tokens[token]["owner"]))
	return out


func _recompute() -> void:
	var m := 0
	for token in _tokens:
		m |= int(_tokens[token]["mask"])
	if m != _mask:
		var old := _mask
		_mask = m
		mask_changed.emit(m, old)
