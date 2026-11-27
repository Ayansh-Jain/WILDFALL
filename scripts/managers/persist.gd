extends Node
## The single save authority (contract C-09, save format v2). Autoload "Persist".
##
## One versioned JSON file holds named sections: "campaign", "player", "horse",
## "exploration", "story", "escort", plus "flags" and "entities". Systems either set a
## section directly or register a provider that is asked for it at save time.
##
## Inactive by default: nothing is read or written until Main calls begin_session(), so
## tests, labs and visits never touch a save.
##
## Safety: write to .tmp, verify it parses, copy the previous good file to .bak1 (and
## .bak1 to .bak2), then rename. A damaged file is copied aside (never deleted) and the
## newest good backup is used. A file from a newer version is never overwritten. The v1
## campaign save is only ever read.

signal saved(path: String, reason: String)
signal save_failed(reason: String)
signal load_failed(reason: String, quarantined_path: String)
signal flag_changed(key: String, new_value: Variant, old_value: Variant)
signal entity_changed(entity_id: String)

const VERSION := 2
const DEFAULT_PATH := "user://wildfall_save.json"
const LEGACY_PATH := "user://campaign_save.json"

var active := false
## Set when the file on disk must not be replaced (written by a newer version).
var read_only := false
var path := DEFAULT_PATH
var legacy_path := LEGACY_PATH
## "new", "loaded", "recovered", "migrated" or "newer".
var status := "new"

var _sections := {}
var _providers := {}


## Opens (or starts) the save. Returns the status.
func begin_session(p_path := DEFAULT_PATH, p_legacy := LEGACY_PATH) -> String:
	end_session()
	path = p_path
	legacy_path = p_legacy
	active = true
	status = _load_into_memory()
	return status


## Forgets everything in memory without writing.
func end_session() -> void:
	active = false
	read_only = false
	status = "new"
	_sections = {}
	_providers = {}


## `snapshot` returns a Dictionary; an empty one keeps what was saved before.
func register_provider(section_name: String, snapshot: Callable) -> void:
	_providers[section_name] = snapshot


func unregister_provider(section_name: String) -> void:
	_providers.erase(section_name)


func section(section_name: String) -> Dictionary:
	var v: Variant = _sections.get(section_name, {})
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


func set_section(section_name: String, data: Dictionary) -> void:
	_sections[section_name] = data.duplicate(true)


func erase_section(section_name: String) -> void:
	_sections.erase(section_name)


## Reads one section from disk without opening a session or changing anything.
func peek_section(section_name: String, p_path := DEFAULT_PATH) -> Dictionary:
	var file := _read(p_path)
	if file["state"] != "ok":
		return {}
	return (file["sections"] as Dictionary).get(section_name, {})


# --- flags and entities ----------------------------------------------------------------------

func set_flag(key: String, value: Variant = true) -> void:
	var flags: Dictionary = _sections.get("flags", {})
	var old: Variant = flags.get(key)
	flags[key] = value
	_sections["flags"] = flags
	if typeof(old) != typeof(value) or old != value:
		flag_changed.emit(key, value, old)


func get_flag(key: String, default: Variant = false) -> Variant:
	return (_sections.get("flags", {}) as Dictionary).get(key, default)


func has_flag(key: String) -> bool:
	return (_sections.get("flags", {}) as Dictionary).has(key)


## Persistent facts about one world object, keyed by its stable id (never a node path).
func entity(entity_id: String) -> Dictionary:
	return ((_sections.get("entities", {}) as Dictionary).get(entity_id, {}) as Dictionary).duplicate(true)


func set_entity(entity_id: String, patch: Dictionary) -> void:
	var all: Dictionary = _sections.get("entities", {})
	var record: Dictionary = all.get(entity_id, {})
	record.merge(patch.duplicate(true), true)
	all[entity_id] = record
	_sections["entities"] = all
	entity_changed.emit(entity_id)


# --- writing ---------------------------------------------------------------------------------

func save(reason := "auto") -> bool:
	if not active:
		return false
	if read_only:
		save_failed.emit("the save on disk is from a newer version; it is left untouched")
		return false
	for section_name in _providers:
		var snapshot: Callable = _providers[section_name]
		if not snapshot.is_valid():
			continue
		var data: Variant = snapshot.call()
		if data is Dictionary and not (data as Dictionary).is_empty():
			_sections[section_name] = data
	var text := JSON.stringify({"version": VERSION, "saved_at": Time.get_datetime_string_from_system(),
		"reason": reason, "sections": _sections}, "\t")
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail("cannot open %s" % tmp)
	f.store_string(text)
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK or _read(tmp).get("state") != "ok":
		return _fail("the new save could not be written completely")
	# Only a good file may enter the backup chain.
	if _read(path).get("state") == "ok":
		if FileAccess.file_exists(path + ".bak1"):
			DirAccess.copy_absolute(path + ".bak1", path + ".bak2")
		DirAccess.copy_absolute(path, path + ".bak1")
	if DirAccess.rename_absolute(tmp, path) != OK:
		return _fail("cannot replace %s" % path)
	saved.emit(path, reason)
	return true


func _fail(reason: String) -> bool:
	push_warning("Persist: %s" % reason)
	save_failed.emit(reason)
	return false


# --- reading ---------------------------------------------------------------------------------

## {state: "missing" | "bad" | "newer" | "ok", sections}
static func _read(file: String) -> Dictionary:
	if not FileAccess.file_exists(file):
		return {"state": "missing"}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK or not (json.data is Dictionary):
		return {"state": "bad"}
	var d: Dictionary = json.data
	var version := int(d.get("version", -1)) if d.get("version") is float or d.get("version") is int else -1
	if version > VERSION:
		return {"state": "newer"}
	if version != VERSION or not (d.get("sections") is Dictionary):
		return {"state": "bad"}
	for key in d["sections"]:
		if not (d["sections"][key] is Dictionary):
			return {"state": "bad"}
	return {"state": "ok", "sections": d["sections"]}


func _load_into_memory() -> String:
	var main_file := _read(path)
	match String(main_file["state"]):
		"ok":
			_sections = main_file["sections"]
			return "loaded"
		"newer":
			read_only = true
			load_failed.emit("this save was made by a newer version of the game", "")
			return "newer"
		"bad":
			var aside := "%s.corrupt-%d" % [path, int(Time.get_unix_time_from_system())]
			DirAccess.copy_absolute(path, aside)
			load_failed.emit("the save file is damaged", aside)
	for backup in [path + ".bak1", path + ".bak2"]:
		var older := _read(backup)
		if older["state"] == "ok":
			_sections = older["sections"]
			return "recovered"
	return _migrate_v1()


## The v1 campaign file becomes the "campaign" section. The old file is not touched.
func _migrate_v1() -> String:
	if not FileAccess.file_exists(legacy_path):
		return "new"
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(legacy_path)) != OK or not (json.data is Dictionary):
		load_failed.emit("the old campaign save is unreadable", legacy_path)
		return "new"
	var d: Dictionary = json.data
	if int(d.get("version", -1)) != 1:
		return "new"
	_sections = {"campaign": d}
	return "migrated"
