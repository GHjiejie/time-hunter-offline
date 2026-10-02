class_name SaveStore
extends RefCounted

const Content := preload("res://scripts/game_content.gd")
const Bindings := preload("res://scripts/input_bindings.gd")
const PATH := "user://progress.json"
const SCHEMA_VERSION := 2
const MAX_LEVEL := 10
const MAX_ENHANCEMENT := 3
const DEFAULT_SETTINGS := {"master_volume": 1.0, "sfx_volume": 0.8, "shake": 1.0, "flash": 0.5, "particles": 1.0, "damage_numbers": true, "large_text": false, "fullscreen": false}
var coins := 0
var level := 0
var xp := 0
var best_score := 0
var clears := 0
var muted := false
var inventory: Array = []
var equipped := {"weapon": "", "armor": "", "charm": ""}
var enhancements := {"weapon": 0, "armor": 0, "charm": 0}
var first_clears: Array = []
var unlocked_stages: Array = ["outskirts"]
var passive := "assault"
var variants := {"burst": "wide", "ultimate": "normal"}
var legacy_skills := false
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
var records: Dictionary = {}
var active_run: Dictionary = {}
var settled_runs: Array = []
var last_error := OK
var storage_path := PATH
var load_status := "new"
var load_message := "尚无存档，开始新游戏后自动保存。"
var has_progress := false
var _write_blocked := false
var _using_backup := false
var _force_replace := false

func _init() -> void:
	_reset_data()

func _reset_data() -> void:
	coins = 0
	level = 0
	xp = 0
	best_score = 0
	clears = 0
	muted = false
	inventory = []
	equipped = {"weapon": "", "armor": "", "charm": ""}
	enhancements = {"weapon": 0, "armor": 0, "charm": 0}
	for item_id in Content.STARTER_ITEMS:
		var uid := "starter_" + item_id
		inventory.append({"uid": uid, "item_id": item_id, "locked": false, "new": false})
	for item_id in ["training_blade", "field_coat", "pulse_charm"]:
		equipped[Content.item(item_id).slot] = "starter_" + item_id
	first_clears = []
	unlocked_stages = ["outskirts"]
	passive = "assault"
	variants = {"burst": "wide", "ultimate": "normal"}
	legacy_skills = false
	settings = DEFAULT_SETTINGS.duplicate(true)
	records = {}
	for id in Content.STAGE_IDS:
		records[id] = {"best_score": 0, "best_time": 0.0, "clears": 0}
	active_run = {}
	settled_runs = []

func load_progress(path: String = "") -> void:
	if not path.is_empty():
		storage_path = path
	path = storage_path
	var primary := _read_file(path)
	if primary.ok:
		_apply(primary.data)
		has_progress = true
		_write_blocked = false
		_using_backup = false
		load_status = "migrated" if primary.migrated else "loaded"
		load_message = "已迁移旧版进度；原有技能、金币与等级保留。" if primary.migrated else "进度已读取。"
		last_error = OK
		return
	# Preserve an already loaded in-memory game if a later read fails. A fresh
	# startup can recover the last verified backup without mutating either file.
	if has_progress:
		load_status = "unsupported" if primary.get("unsupported", false) else "corrupt"
		load_message = "存档读取失败，当前已读取的进度保留。"
		_write_blocked = primary.get("unsupported", false)
		_using_backup = not _write_blocked
		last_error = primary.error
		return
	var backup := _read_file(path + ".bak")
	if backup.ok:
		_apply(backup.data)
		has_progress = true
		_using_backup = true
		_write_blocked = false
		load_status = "backup"
		load_message = "主存档不可用，已恢复上次有效备份；继续游戏会保留该备份并重建主存档。"
		last_error = OK
		return
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		load_status = "new"
		load_message = "尚无存档，开始新游戏后自动保存。"
		_write_blocked = false
		last_error = OK
		return
	_write_blocked = true
	load_status = "unsupported" if primary.get("unsupported", false) else "corrupt"
	load_message = "存档版本无法读取，原文件保留；新游戏需要确认覆盖。" if load_status == "unsupported" else "存档与备份无法读取，原文件保留；新游戏需要确认覆盖。"
	last_error = primary.error

func save_progress(path: String = "") -> Error:
	if path.is_empty():
		path = storage_path
	if _write_blocked and not _force_replace:
		last_error = ERR_FILE_CORRUPT
		return last_error
	var payload := _snapshot()
	if not _validate_v2(payload):
		last_error = ERR_INVALID_DATA
		return last_error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	file.store_string(JSON.stringify(payload))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = write_error
		return last_error
	var verification := _read_file(temporary)
	if not verification.ok or verification.migrated:
		last_error = ERR_FILE_CORRUPT
		return last_error
	# Only an independently verified main file is eligible to replace the backup.
	# A corrupt or future-version file remains untouched unless new_game was called.
	var existing := _read_file(path)
	if FileAccess.file_exists(path) and not existing.ok and not _using_backup and not _force_replace:
		last_error = ERR_FILE_CORRUPT
		return last_error
	if existing.ok and not _force_replace:
		var backup_temporary := path + ".bak.tmp"
		var copy_error := DirAccess.copy_absolute(_absolute(path), _absolute(backup_temporary))
		if copy_error != OK or not _read_file(backup_temporary).ok:
			last_error = copy_error if copy_error != OK else ERR_FILE_CORRUPT
			return last_error
		var backup_error := DirAccess.rename_absolute(_absolute(backup_temporary), _absolute(path + ".bak"))
		if backup_error != OK:
			last_error = backup_error
			return last_error
	var replace_error := DirAccess.rename_absolute(_absolute(temporary), _absolute(path))
	last_error = replace_error
	if replace_error == OK:
		has_progress = true
		_write_blocked = false
		_using_backup = false
		load_status = "loaded"
		load_message = "进度已安全保存。"
	return replace_error

func new_game() -> bool:
	var previous := _snapshot()
	var previous_has_progress := has_progress
	var previous_blocked := _write_blocked
	_reset_data()
	_force_replace = true
	var result := save_progress()
	_force_replace = false
	if result != OK:
		_apply(previous)
		has_progress = previous_has_progress
		_write_blocked = previous_blocked
		return false
	# Never expose progress from a superseded game after the new game succeeds.
	# The new verified main is also the first recovery point of this new game.
	var backup_result := DirAccess.copy_absolute(_absolute(storage_path), _absolute(storage_path + ".bak.tmp"))
	if backup_result == OK and _read_file(storage_path + ".bak.tmp").ok:
		DirAccess.rename_absolute(_absolute(storage_path + ".bak.tmp"), _absolute(storage_path + ".bak"))
	return true

func begin_run(stage_id: String, seed: int) -> bool:
	if not has_progress or not active_run.is_empty() or not unlocked_stages.has(stage_id) or Content.stage(stage_id).is_empty():
		return false
	var previous := _snapshot()
	active_run = {"id": "%d-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), randi()], "stage": stage_id, "seed": seed, "wave": 0}
	return _commit_or_restore(previous)

func update_checkpoint(wave_index: int) -> bool:
	if active_run.is_empty():
		return false
	var stage_data := Content.stage(active_run.stage)
	if wave_index < int(active_run.wave) or wave_index < 0 or wave_index >= stage_data.waves.size():
		return false
	var previous := _snapshot()
	active_run.wave = wave_index
	return _commit_or_restore(previous)

func abandon_run() -> bool:
	if active_run.is_empty():
		return true
	var previous := _snapshot()
	settled_runs.append(active_run.id)
	_trim_journal()
	active_run = {}
	return _commit_or_restore(previous)

func settle_run(won: bool, stats: Dictionary = {}) -> Dictionary:
	var requested_id: String = str(stats.get("run_id", active_run.get("id", "")))
	if requested_id.is_empty() or settled_runs.has(requested_id) or active_run.is_empty() or requested_id != str(active_run.id):
		return {"ok": false, "duplicate": settled_runs.has(requested_id), "error": "这次出战已经结算或无法识别。"}
	var previous := _snapshot()
	var stage_id: String = active_run.stage
	var stage_data := Content.stage(stage_id)
	var first := won and not first_clears.has(stage_id)
	# There is one optional supply crate per stage. Checkpoint recovery rebuilds
	# the room and its crate together; only this successful run can bank its loot.
	var bonus_coins := _safe_int(stats.get("bonus_coins", 0), 0, 8) if won else 0
	var reward_coins: int = int(stage_data.coins) + (int(stage_data.first_coins) if first else 0) + bonus_coins if won else 0
	var reward_xp: int = int(stage_data.xp) + (int(stage_data.first_xp) if first else 0) if won and level < MAX_LEVEL else 0
	var result := {"ok": false, "won": won, "first_clear": first, "coins": reward_coins, "bonus_coins": bonus_coins, "xp": reward_xp, "items": [], "unlocks": [], "level_before": level, "level_after": level, "stage": stage_id, "run_id": requested_id}
	if won:
		coins += reward_coins
		_add_xp(reward_xp)
		clears += 1
		var score := _safe_int(stats.get("score", 0), 0, 100000000)
		best_score = maxi(best_score, score)
		var record_data: Dictionary = records[stage_id]
		record_data.clears = int(record_data.clears) + 1
		record_data.best_score = maxi(int(record_data.best_score), score)
		var duration := _safe_float(stats.get("elapsed", stats.get("time", 0.0)), 0.0, 86400.0)
		if duration > 0.0 and (float(record_data.best_time) <= 0.0 or duration < float(record_data.best_time)):
			record_data.best_time = duration
		if first:
			first_clears.append(stage_id)
			var reward_id: String = stage_data.first_item
			if not reward_id.is_empty():
				inventory.append({"uid": "reward_" + requested_id + "_" + reward_id, "item_id": reward_id, "locked": false, "new": true})
				result.items.append(reward_id)
			var next_stage: String = stage_data.first_unlock
			if not next_stage.is_empty() and not unlocked_stages.has(next_stage):
				unlocked_stages.append(next_stage)
				result.unlocks.append(next_stage)
			if stage_id == "outskirts" and not legacy_skills:
				result.unlocks.append("ultimate")
	result.level_after = level
	settled_runs.append(requested_id)
	_trim_journal()
	active_run = {}
	if not _commit_or_restore(previous):
		result.error = "奖励尚未到账，保存失败；请重试结算。"
		return result
	result.ok = true
	return result

func item_instance(uid: String) -> Dictionary:
	for instance in inventory:
		if instance.uid == uid:
			return instance.duplicate(true)
	return {}

func equipped_item(slot: String) -> Dictionary:
	var instance := item_instance(str(equipped.get(slot, "")))
	if instance.is_empty():
		return {}
	var result := Content.item(instance.item_id)
	result.merge(instance, true)
	return result

func equip_item(uid: String) -> bool:
	if not active_run.is_empty():
		return false
	var instance := item_instance(uid)
	if instance.is_empty():
		return false
	var previous := _snapshot()
	equipped[Content.item(instance.item_id).slot] = uid
	_mark_seen(uid)
	return _commit_or_restore(previous)

func unequip_item(slot: String) -> bool:
	if not active_run.is_empty() or not Content.SLOTS.has(slot):
		return false
	var previous := _snapshot()
	equipped[slot] = ""
	return _commit_or_restore(previous)

func lock_item(uid: String) -> bool:
	if not active_run.is_empty() or item_instance(uid).is_empty():
		return false
	var previous := _snapshot()
	for instance in inventory:
		if instance.uid == uid:
			instance.locked = not instance.locked
	return _commit_or_restore(previous)

func discard_item(uid: String) -> bool:
	if not active_run.is_empty():
		return false
	var instance := item_instance(uid)
	if instance.is_empty() or instance.locked or equipped.values().has(uid):
		return false
	var slot: String = Content.item(instance.item_id).slot
	var count := 0
	for owned in inventory:
		if Content.item(owned.item_id).slot == slot:
			count += 1
	if count <= 1:
		return false
	var previous := _snapshot()
	inventory = inventory.filter(func(owned): return owned.uid != uid)
	return _commit_or_restore(previous)

func set_passive(id: String) -> bool:
	if not active_run.is_empty() or not ["assault", "guard"].has(id):
		return false
	var previous := _snapshot()
	passive = id
	return _commit_or_restore(previous)

func set_variant(skill: String, variant: String) -> bool:
	if not active_run.is_empty():
		return false
	if (skill == "burst" and not ["wide", "focused"].has(variant)) or (skill == "ultimate" and (not unlocked_skills().has("ultimate") or not ["normal", "precision"].has(variant))) or not variants.has(skill):
		return false
	var previous := _snapshot()
	variants[skill] = variant
	return _commit_or_restore(previous)

func unlocked_skills() -> Array[String]:
	var result: Array[String] = ["dash", "burst"]
	if legacy_skills or first_clears.has("outskirts"):
		result.append("ultimate")
	return result

func combat_config() -> Dictionary:
	var health := 220.0 + level * 12.0
	var attack := 22.0 + level * 2.0
	var cooldown_scale := 1.0
	var energy_regen := 9.0
	for slot in Content.SLOTS:
		var data := equipped_item(slot)
		if data.is_empty():
			continue
		health += float(data.health)
		attack += float(data.attack)
		cooldown_scale *= float(data.cooldown_scale)
		energy_regen += float(data.energy_regen)
	attack += int(enhancements.weapon) * 2.0
	health += int(enhancements.armor) * 10.0
	energy_regen += int(enhancements.charm) * 0.5
	return {"health": maxf(120.0, health), "attack": maxf(10.0, attack), "damage_scale": maxf(10.0, attack) / 22.0, "cooldown_scale": clampf(cooldown_scale, 0.65, 1.5), "energy_regen": clampf(energy_regen, 3.0, 18.0), "passive": passive, "skills": unlocked_skills(), "burst_variant": variants.burst, "ultimate_variant": variants.ultimate}

func xp_needed() -> int:
	return 0 if level >= MAX_LEVEL else 100 + level * 60

func _add_xp(amount: int) -> void:
	xp += maxi(0, amount)
	while level < MAX_LEVEL and xp >= xp_needed():
		xp -= xp_needed()
		level += 1
	if level >= MAX_LEVEL:
		xp = 0

func enhancement_cost(slot: String) -> int:
	return 90 + int(enhancements.get(slot, 0)) * 60

func enhance(slot: String) -> bool:
	if not active_run.is_empty() or not Content.SLOTS.has(slot) or int(enhancements[slot]) >= MAX_ENHANCEMENT or coins < enhancement_cost(slot):
		return false
	var previous := _snapshot()
	coins -= enhancement_cost(slot)
	enhancements[slot] = int(enhancements[slot]) + 1
	return _commit_or_restore(previous)

# Kept for older test clients and legacy saves. Production growth uses earned XP,
# while coins buy deterministic equipment enhancements rather than hero levels.
func upgrade_cost() -> int:
	return 60 + level * 35

func upgrade() -> bool:
	if not active_run.is_empty() or level >= MAX_LEVEL or coins < upgrade_cost():
		return false
	var previous := _snapshot()
	coins -= upgrade_cost()
	level += 1
	xp = mini(xp, maxi(0, xp_needed() - 1))
	return _commit_or_restore(previous)

func record(won: bool, reward: int, score: int) -> void:
	var previous := _snapshot()
	coins += maxi(0, reward)
	best_score = maxi(best_score, score)
	if won:
		clears += 1
	_commit_or_restore(previous)

func _mark_seen(uid: String) -> void:
	for instance in inventory:
		if instance.uid == uid:
			instance.new = false

func _trim_journal() -> void:
	while settled_runs.size() > 64:
		settled_runs.pop_front()

func _commit_or_restore(previous: Dictionary) -> bool:
	if save_progress() == OK:
		return true
	_apply(previous)
	return false

func _snapshot() -> Dictionary:
	return {"version": SCHEMA_VERSION, "coins": coins, "level": level, "xp": xp, "best_score": best_score, "clears": clears, "muted": muted, "inventory": inventory.duplicate(true), "equipped": equipped.duplicate(true), "enhancements": enhancements.duplicate(true), "first_clears": first_clears.duplicate(), "unlocked_stages": unlocked_stages.duplicate(), "passive": passive, "variants": variants.duplicate(true), "legacy_skills": legacy_skills, "settings": settings.duplicate(true), "records": records.duplicate(true), "active_run": active_run.duplicate(true), "settled_runs": settled_runs.duplicate()}

func _apply(data: Dictionary) -> void:
	coins = int(data.coins)
	level = int(data.level)
	xp = int(data.xp)
	best_score = int(data.best_score)
	clears = int(data.clears)
	muted = data.muted
	inventory = data.inventory.duplicate(true)
	equipped = data.equipped.duplicate(true)
	enhancements = data.enhancements.duplicate(true)
	first_clears = data.first_clears.duplicate()
	unlocked_stages = data.unlocked_stages.duplicate()
	passive = data.passive
	variants = data.variants.duplicate(true)
	legacy_skills = data.legacy_skills
	settings = data.settings.duplicate(true)
	records = data.records.duplicate(true)
	active_run = data.active_run.duplicate(true)
	settled_runs = data.settled_runs.duplicate()

func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": ERR_FILE_NOT_FOUND}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": FileAccess.get_open_error()}
	var parser := JSON.new()
	var parse_result := parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK or not parser.data is Dictionary:
		return {"ok": false, "error": ERR_FILE_CORRUPT}
	var data: Dictionary = parser.data
	var version: Variant = data.get("version", 1)
	if not _integer_in(version, 1, SCHEMA_VERSION):
		return {"ok": false, "error": ERR_FILE_UNRECOGNIZED, "unsupported": true}
	if int(version) == 1:
		for key in ["coins", "level", "best_score"]:
			if not data.has(key):
				return {"ok": false, "error": ERR_FILE_CORRUPT}
		return {"ok": true, "data": _migrate_v1(data), "migrated": true, "error": OK}
	if not _validate_v2(data):
		return {"ok": false, "error": ERR_FILE_CORRUPT}
	return {"ok": true, "data": data, "migrated": false, "error": OK}

func _migrate_v1(data: Dictionary) -> Dictionary:
	var defaults := SaveStore.new()._snapshot()
	defaults.coins = _safe_int(data.get("coins", 0), 0, 10000000)
	defaults.level = _safe_int(data.get("level", 0), 0, MAX_LEVEL)
	defaults.best_score = _safe_int(data.get("best_score", 0), 0, 100000000)
	defaults.clears = _safe_int(data.get("clears", 0), 0, 1000000)
	defaults.muted = data.get("muted", false) == true
	defaults.legacy_skills = true
	return defaults

func _validate_v2(data: Dictionary) -> bool:
	for key in ["coins", "level", "xp", "best_score", "clears", "muted", "inventory", "equipped", "enhancements", "first_clears", "unlocked_stages", "passive", "variants", "legacy_skills", "settings", "records", "active_run", "settled_runs"]:
		if not data.has(key):
			return false
	if not _integer_in(data.get("version"), SCHEMA_VERSION, SCHEMA_VERSION) or not _integer_in(data.coins, 0, 10000000) or not _integer_in(data.level, 0, MAX_LEVEL) or not _integer_in(data.xp, 0, 10000) or not _integer_in(data.best_score, 0, 100000000) or not _integer_in(data.clears, 0, 1000000):
		return false
	if int(data.level) < MAX_LEVEL and int(data.xp) >= 100 + int(data.level) * 60 or int(data.level) == MAX_LEVEL and int(data.xp) != 0:
		return false
	if not data.muted is bool or not data.legacy_skills is bool or not data.passive in ["assault", "guard"]:
		return false
	if not data.inventory is Array or data.inventory.size() > 10000 or not data.equipped is Dictionary or not data.enhancements is Dictionary:
		return false
	var instances := {}
	for instance in data.inventory:
		if not instance is Dictionary or not instance.get("uid") is String or instance.uid.is_empty() or instances.has(instance.uid) or not Content.ITEM_IDS.has(instance.get("item_id")) or not instance.get("locked") is bool or not instance.get("new") is bool:
			return false
		instances[instance.uid] = instance.item_id
	for slot in Content.SLOTS:
		if not data.equipped.get(slot) is String or not _integer_in(data.enhancements.get(slot), 0, MAX_ENHANCEMENT):
			return false
		var uid: String = data.equipped[slot]
		if not uid.is_empty() and (not instances.has(uid) or Content.item(instances[uid]).slot != slot):
			return false
		var available := 0
		for item_id in instances.values():
			if Content.item(item_id).slot == slot:
				available += 1
		if available == 0:
			return false
	if not _known_unique_array(data.first_clears, Content.STAGE_IDS) or not _known_unique_array(data.unlocked_stages, Content.STAGE_IDS) or not data.unlocked_stages.has("outskirts"):
		return false
	if data.unlocked_stages.has("corridor") != data.first_clears.has("outskirts") or data.unlocked_stages.has("core") != data.first_clears.has("corridor"):
		return false
	for id in data.first_clears:
		if not data.unlocked_stages.has(id):
			return false
	if not data.variants is Dictionary or not data.variants.get("burst") in ["wide", "focused"] or not data.variants.get("ultimate") in ["normal", "precision"]:
		return false
	if not data.settings is Dictionary:
		return false
	for key in DEFAULT_SETTINGS:
		if DEFAULT_SETTINGS[key] is bool:
			if not data.settings.get(key) is bool:
				return false
		elif not _number_in(data.settings.get(key), 0.0, 1.0):
			return false
	if data.settings.has("bindings") and not _validate_bindings(data.settings.bindings):
		return false
	if not data.records is Dictionary:
		return false
	for id in Content.STAGE_IDS:
		var record_data: Variant = data.records.get(id)
		if not record_data is Dictionary or not _integer_in(record_data.get("best_score"), 0, 100000000) or not _number_in(record_data.get("best_time"), 0.0, 86400.0) or not _integer_in(record_data.get("clears"), 0, 1000000):
			return false
	if not data.settled_runs is Array or data.settled_runs.size() > 64:
		return false
	var journal_ids := {}
	for id in data.settled_runs:
		if not id is String or id.is_empty() or journal_ids.has(id):
			return false
		journal_ids[id] = true
	if not data.active_run is Dictionary:
		return false
	if not data.active_run.is_empty():
		var run: Dictionary = data.active_run
		if not run.get("id") is String or run.id.is_empty() or journal_ids.has(run.id) or not data.unlocked_stages.has(run.get("stage")) or not _integer_in(run.get("seed"), -9223372036854775807, 9223372036854775807):
			return false
		if not _integer_in(run.get("wave"), 0, Content.stage(run.stage).waves.size() - 1):
			return false
	return true

func _validate_bindings(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var final_mapping: Dictionary = Bindings.DEFAULTS.duplicate()
	for action in value:
		if not action is String or not Bindings.DEFAULTS.has(action) or not _integer_in(value[action], 1, KEY_UNKNOWN - 1):
			return false
		var code := int(value[action])
		if not _valid_key_code(code) or action == "pause" and code != KEY_ESCAPE:
			return false
		final_mapping[action] = code
	# Validate the complete final map, including implicit defaults. Valid saved
	# swaps must not be rejected merely because a default action once used a key.
	var candidate := {"bindings": final_mapping}
	for action in Bindings.ACTIONS:
		if action != "pause" and not Bindings.try_rebind(candidate, action, int(final_mapping[action])).ok:
			return false
	return true

func _valid_key_code(code: int) -> bool:
	# Printable Unicode keycodes and the defined Godot special-key ranges. Do
	# not accept surrogate points, unknown keys, modifier masks or enum gaps.
	if code >= 32 and code <= 0x10ffff:
		return not (code >= 127 and code <= 159 or code >= 0xd800 and code <= 0xdfff)
	return (code >= KEY_ESCAPE and code <= KEY_F35
		or code in [KEY_MENU, KEY_HYPER, KEY_HELP]
		or code >= KEY_BACK and code <= KEY_VOLUMEUP
		or code >= KEY_MEDIAPLAY and code <= KEY_JIS_KANA
		or code >= KEY_KP_MULTIPLY and code <= KEY_KP_9)

func _known_unique_array(values: Variant, known: Array) -> bool:
	if not values is Array:
		return false
	var seen := {}
	for value in values:
		if not value is String or not known.has(value) or seen.has(value):
			return false
		seen[value] = true
	return true

func _integer_in(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= low and value <= high

func _number_in(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

func _safe_int(value: Variant, low: int, high: int) -> int:
	return clampi(int(value), low, high) if (value is float or value is int) and is_finite(float(value)) else low

func _safe_float(value: Variant, low: float, high: float) -> float:
	return clampf(float(value), low, high) if (value is float or value is int) and is_finite(float(value)) else low

func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path
