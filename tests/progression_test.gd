extends SceneTree

const Store := preload("res://scripts/save_store.gd")
const Content := preload("res://scripts/game_content.gd")
const Bindings := preload("res://scripts/input_bindings.gd")
var checks := 0
var failures := 0
var test_directory := ""

func _initialize() -> void:
	test_directory = "user://p0-progress-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_directory))
	_test_catalog_and_new_game()
	_test_rewards_and_checkpoints()
	_test_inventory_and_config()
	_test_failure_rollback()
	_test_migration_and_recovery()
	_test_corrupt_and_future_files()
	_test_bindings()
	_cleanup()
	print("PROGRESSION CHECKS: %d / FAILED: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func _store(name: String) -> SaveStore:
	var store := Store.new()
	store.storage_path = test_directory + "/" + name + ".json"
	return store

func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()

func _win(store: SaveStore, stage_id: String) -> Dictionary:
	check(store.begin_run(stage_id, 42), "start valid stage " + stage_id)
	return store.settle_run(true, {"run_id": store.active_run.id, "score": 1200, "elapsed": 25.0})

func _test_catalog_and_new_game() -> void:
	check(Content.STAGE_IDS.size() == 3 and Content.ITEM_IDS.size() == 9, "catalog has three stages and nine defined items")
	for id in Content.STAGE_IDS:
		var data := Content.stage(id)
		check(data.id == id and data.waves.size() >= 2 and data.bounds.size.x > 0, "stage is playable " + id)
	var store := _store("new")
	store.load_progress()
	check(not store.has_progress and store.load_status == "new" and not FileAccess.file_exists(store.storage_path), "missing progress remains missing until explicit creation")
	check(store.new_game() and store.has_progress, "explicit new game safely creates progress")
	check(store.inventory.size() == 6 and store.equipped_item("weapon").id == "training_blade", "new game has safe equipped items and immediate alternatives")
	check(store.combat_config().health == 220 and store.combat_config().attack == 22 and store.unlocked_skills() == ["dash", "burst"], "new stats and skills are deliberately limited")
	check(not store.begin_run("core", 42), "locked stage rejects start")
	check(not store.set_variant("ultimate", "precision") and store.set_variant("burst", "focused"), "skill variants respect skill unlock")

func _test_rewards_and_checkpoints() -> void:
	var store := _store("rewards")
	check(store.new_game() and store.begin_run("outskirts", 991), "new run is saved before battle")
	var run_id: String = store.active_run.id
	check(store.update_checkpoint(1) and not store.update_checkpoint(0) and not store.update_checkpoint(2), "checkpoint only advances to a valid encounter")
	var resumed := _store("rewards")
	resumed.load_progress()
	check(resumed.active_run.id == run_id and resumed.active_run.wave == 1 and resumed.active_run.seed == 991, "reload restores same run ID seed and safe encounter")
	check(not resumed.equip_item("starter_cautious_blade") and not resumed.set_passive("guard") and not resumed.enhance("weapon"), "active run prevents changing combat configuration")
	var result := resumed.settle_run(true, {"run_id": run_id, "score": 1500, "elapsed": 30.0})
	check(result.ok and result.first_clear and result.coins == 105 and result.xp == 105 and resumed.coins == 105, "first clear combines fixed and repeat coins exactly once")
	check(resumed.level == 1 and resumed.xp == 5 and result.level_before == 0 and result.level_after == 1, "first short stage grants experience level")
	check(result.items == ["twin_fang"] and result.unlocks.has("corridor") and result.unlocks.has("ultimate") and resumed.unlocked_skills().has("ultimate"), "first clear gives guaranteed gear stage and ultimate")
	check(resumed.records.outskirts.best_score == 1500 and resumed.records.outskirts.best_time == 30.0, "victory record stores score and clear time")
	var coins_before: int = resumed.coins
	check(not resumed.settle_run(true, {"run_id": run_id}).ok and resumed.coins == coins_before, "duplicate callback cannot award again")
	var reopened := _store("rewards")
	reopened.load_progress()
	check(not reopened.settle_run(true, {"run_id": run_id}).ok and reopened.coins == coins_before, "duplicate settlement after restart cannot award again")
	var repeat := _win(reopened, "outskirts")
	check(repeat.ok and not repeat.first_clear and repeat.coins == 45 and repeat.xp == 45 and repeat.items.is_empty(), "repeated stage grants only deterministic repeat rewards")
	check(reopened.begin_run("outskirts", 10), "failure run begins")
	coins_before = reopened.coins
	var inventory_before := reopened.inventory.duplicate(true)
	var failure := reopened.settle_run(false, {"score": 99000, "elapsed": 1.0, "bonus_coins": 8})
	check(failure.ok and failure.coins == 0 and failure.bonus_coins == 0 and failure.xp == 0 and reopened.coins == coins_before and reopened.inventory == inventory_before, "failure preserves prior growth and gives no room rewards")
	check(reopened.records.outskirts.best_score == 1500, "failure does not improve victory record")
	check(reopened.begin_run("corridor", 7) and reopened.abandon_run() and reopened.coins == coins_before and reopened.active_run.is_empty(), "abandon clears checkpoint without awarding currency")
	check(_win(reopened, "corridor").ok and _win(reopened, "core").ok and reopened.first_clears.size() == 3, "all chapter stages unlock and award once")
	check(reopened.inventory.size() == 9 and reopened.unlocked_stages.size() == 3 and reopened.clears == 4, "chapter completion contains all guaranteed gear and accurate clear count")
	check(reopened.begin_run("outskirts", 13), "optional crate run begins")
	var crate_id: String = reopened.active_run.id
	var crate_result := reopened.settle_run(true, {"run_id": crate_id, "bonus_coins": 999})
	check(crate_result.ok and crate_result.bonus_coins == 8 and crate_result.coins == 53, "optional crate banks at most one stage crate only on victory")
	coins_before = reopened.coins
	check(not reopened.settle_run(true, {"run_id": crate_id, "bonus_coins": 8}).ok and reopened.coins == coins_before, "duplicate crate settlement cannot multiply bonus")

func _test_inventory_and_config() -> void:
	var store := _store("inventory")
	check(store.new_game(), "inventory test progress created")
	var baseline := store.combat_config()
	for index in range(8):
		check(store.equip_item("starter_cautious_blade") and store.equip_item("starter_training_blade"), "equip replacement cycle %d" % index)
	check(store.combat_config() == baseline, "repeated equip computes from base and never stacks attributes")
	check(store.set_passive("guard") and store.equip_item("starter_shell_coat") and store.equip_item("starter_guard_charm"), "guard equipment and passive can be selected safely")
	var guard := store.combat_config()
	check(guard.health == 285 and guard.attack == 20 and guard.energy_regen == 8 and is_equal_approx(guard.cooldown_scale, 1.10) and guard.passive == "guard", "guard build trades output and cooldown for life")
	check(not store.discard_item("starter_shell_coat"), "equipped item is protected")
	check(store.lock_item("starter_field_coat") and not store.discard_item("starter_field_coat"), "locked item is protected")
	check(store.lock_item("starter_field_coat") and store.discard_item("starter_field_coat"), "unlocked unequipped alternative can be disposed")
	check(store.unequip_item("armor") and not store.discard_item("starter_shell_coat"), "last armor remains protected even when unequipped")
	check(store.equip_item("starter_shell_coat"), "remaining critical item can be equipped again")
	store.coins = 1000
	check(store.save_progress() == OK and store.enhance("weapon") and store.enhance("weapon") and store.enhance("weapon"), "fixed enhancement can reach visible cap")
	check(store.coins == 550 and int(store.enhancements.weapon) == 3 and not store.enhance("weapon"), "enhancement costs are 90/150/210 and cap has no failure RNG")
	check(store.combat_config().attack == 26, "slot enhancement has deterministic bounded combat effect")
	var restored := _store("inventory")
	restored.load_progress()
	check(restored.combat_config() == store.combat_config() and restored.inventory == store.inventory, "readback exactly preserves item instances enhancements and combat config")

func _test_failure_rollback() -> void:
	var store := _store("rollback")
	check(store.new_game() and store.begin_run("outskirts", 42), "transaction test run created")
	var run_before := store.active_run.duplicate(true)
	var inventory_before := store.inventory.duplicate(true)
	var valid_path: String = store.storage_path
	store.storage_path = test_directory + "/missing-parent/progress.json"
	var failed := store.settle_run(true, {"run_id": run_before.id})
	check(not failed.ok and store.coins == 0 and store.level == 0 and store.first_clears.is_empty() and store.inventory == inventory_before and store.active_run == run_before, "failed settlement rolls back all rewards unlocks gear and run closure")
	store.storage_path = valid_path
	check(store.settle_run(true, {"run_id": run_before.id}).ok, "same run can settle after storage recovers")
	var coins_before: int = store.coins
	store.storage_path = test_directory + "/missing-parent/progress.json"
	check(not store.equip_item("starter_cautious_blade") and store.equipped.weapon == "starter_training_blade", "failed equip rolls back selection")
	check(not store.enhance("weapon") and store.coins == coins_before and store.enhancements.weapon == 0, "failed enhancement rolls back coins and enhancement")
	var level_before: int = store.level
	store.coins = 1000
	check(not store.upgrade() and store.level == level_before and store.coins == 1000, "legacy upgrade also rolls back when writing fails")
	store.record(true, 80, 99000)
	check(store.coins == 1000 and store.best_score == 0 and store.clears == 1, "legacy record rolls back when writing fails")
	store.storage_path = valid_path

func _test_migration_and_recovery() -> void:
	var old := _store("old")
	_write(old.storage_path, '{"version":1,"coins":240,"level":3,"best_score":940,"clears":2,"muted":true}')
	old.load_progress()
	check(old.load_status == "migrated" and old.coins == 240 and old.level == 3 and old.best_score == 940 and old.muted and old.unlocked_skills().has("ultimate"), "v1 migration preserves earned values and previously available skills")
	check(old.save_progress() == OK and int(JSON.parse_string(FileAccess.get_file_as_string(old.storage_path)).version) == 2, "first authorized save writes validated new schema")
	var recovery := _store("recovery")
	check(recovery.new_game(), "backup recovery game created")
	recovery.coins = 20
	check(recovery.save_progress() == OK, "previous valid progress preserved as backup")
	recovery.coins = 70
	check(recovery.save_progress() == OK, "backup advances to previous valid save")
	_write(recovery.storage_path, "interrupted json")
	var recovered := _store("recovery")
	recovered.load_progress()
	check(recovered.load_status == "backup" and recovered.has_progress and recovered.coins == 20, "corrupted main recovers last independently valid backup")
	check(FileAccess.get_file_as_string(recovered.storage_path) == "interrupted json", "loading backup does not silently mutate source")
	check(recovered.save_progress() == OK, "explicit resumed save rebuilds main without replacing valid backup with corruption")
	var readback := _store("recovery")
	readback.load_progress()
	check(readback.load_status == "loaded" and readback.coins == 20, "recovered data becomes valid main")
	_write(readback.storage_path + ".tmp", "partial replacement")
	var stable := _store("recovery")
	stable.load_progress()
	check(stable.coins == 20 and stable.load_status == "loaded", "interrupted temporary write cannot displace valid main")

func _test_corrupt_and_future_files() -> void:
	var corrupt := _store("corrupt")
	_write(corrupt.storage_path, '{"version":2,"coins":3}')
	corrupt.load_progress()
	check(not corrupt.has_progress and corrupt.load_status == "corrupt", "missing required v2 fields reject unsafe progress")
	var source := FileAccess.get_file_as_string(corrupt.storage_path)
	check(corrupt.save_progress() != OK and FileAccess.get_file_as_string(corrupt.storage_path) == source, "corrupt save cannot be silently overwritten by default state")
	check(corrupt.new_game() and corrupt.has_progress, "explicit new game is only path to replacing unrecoverable progress")
	var malformed := JSON.parse_string(FileAccess.get_file_as_string(corrupt.storage_path)) as Dictionary
	malformed.inventory[0].item_id = "removed_or_unknown_item"
	_write(corrupt.storage_path, JSON.stringify(malformed))
	var malformed_store := _store("corrupt")
	malformed_store.load_progress()
	check(malformed_store.load_status == "backup", "unknown stable item identifiers invalidate main and recover backup")
	var future := _store("future")
	_write(future.storage_path, '{"version":99,"coins":2000,"level":8,"best_score":0}')
	future.load_progress()
	check(not future.has_progress and future.load_status == "unsupported" and not future.load_message.is_empty(), "future version gives understandable status")
	source = FileAccess.get_file_as_string(future.storage_path)
	future.record(true, 100, 100)
	check(FileAccess.get_file_as_string(future.storage_path) == source and future.coins == 0, "unsupported files and attempted rewards remain untouched")
	var unknown := _store("unknown")
	_write(unknown.storage_path, '{"arbitrary":"not a save"}')
	unknown.load_progress()
	check(not unknown.has_progress and unknown.load_status == "corrupt", "unversioned arbitrary dictionary cannot silently migrate into a new game")

func _test_bindings() -> void:
	var store := _store("bindings")
	check(store.new_game() and not store.settings.has("bindings"), "optional absent bindings keep all defaults valid")
	check(Bindings.try_rebind(store.settings, "attack", KEY_H).ok and store.save_progress() == OK, "valid custom attack binding safely saves")
	var restored := _store("bindings")
	restored.load_progress()
	check(restored.load_status == "loaded" and Bindings.key_for(restored.settings, "attack") == KEY_H and Bindings.key_for(restored.settings, "dash") == KEY_K, "custom and implicit bindings survive a round trip")
	restored.settings.bindings = {"attack": KEY_K, "dash": KEY_J}
	check(restored.save_progress() == OK, "validation accepts an already valid final key swap")
	var swapped := _store("bindings")
	swapped.load_progress()
	check(Bindings.key_for(swapped.settings, "attack") == KEY_K and Bindings.key_for(swapped.settings, "dash") == KEY_J, "valid key swap persists without default-map false conflict")
	Bindings.restore_defaults(swapped.settings)
	check(swapped.save_progress() == OK and swapped.settings.bindings.pause == KEY_ESCAPE, "restoring full defaults including fixed pause is valid")
	var defaulted := _store("bindings")
	defaulted.load_progress()
	check(defaulted.load_status == "loaded" and Bindings.key_for(defaulted.settings, "attack") == KEY_J and Bindings.key_for(defaulted.settings, "pause") == KEY_ESCAPE, "restored defaults persist and preserve navigation")
	var invalid_cases: Array = [
		{"name": "string", "bindings": "broken"},
		{"name": "array", "bindings": []},
		{"name": "null", "bindings": null},
		{"name": "unknown-action", "bindings": {"teleport": KEY_H}},
		{"name": "string-key", "bindings": {"attack": "H"}},
		{"name": "bool-key", "bindings": {"attack": true}},
		{"name": "fraction-key", "bindings": {"attack": 72.5}},
		{"name": "zero-key", "bindings": {"attack": 0}},
		{"name": "negative-key", "bindings": {"attack": -1}},
		{"name": "out-of-range", "bindings": {"attack": 9999999999}},
		{"name": "surrogate", "bindings": {"attack": 0xd800}},
		{"name": "enum-gap", "bindings": {"attack": KEY_SPECIAL + 199}},
		{"name": "unknown-key", "bindings": {"attack": KEY_UNKNOWN}},
		{"name": "reserved-enter", "bindings": {"attack": KEY_ENTER}},
		{"name": "reserved-arrow", "bindings": {"attack": KEY_LEFT}},
		{"name": "reserved-escape", "bindings": {"attack": KEY_ESCAPE}},
		{"name": "pause-rebound", "bindings": {"pause": KEY_H}},
		{"name": "implicit-duplicate", "bindings": {"attack": KEY_K}},
		{"name": "explicit-duplicate", "bindings": {"attack": KEY_H, "dash": KEY_H}},
	]
	for index in range(invalid_cases.size()):
		var case: Dictionary = invalid_cases[index]
		var name: String = "bad-binding-%d" % index
		var damaged := _store(name)
		check(damaged.new_game(), "binding corruption fixture creates verified backup " + case.name)
		var data := JSON.parse_string(FileAccess.get_file_as_string(damaged.storage_path)) as Dictionary
		data.settings.bindings = case.bindings
		var corrupt_source := JSON.stringify(data)
		_write(damaged.storage_path, corrupt_source)
		var recovered := _store(name)
		recovered.load_progress()
		check(recovered.load_status == "backup" and recovered.has_progress and Bindings.key_for(recovered.settings, "attack") == KEY_J and Bindings.hint(recovered.settings, "pause") == "Esc", "invalid binding safely recovers before input helpers run: " + case.name)
		check(FileAccess.get_file_as_string(recovered.storage_path) == corrupt_source, "binding recovery preserves source until an explicit save: " + case.name)
	# A malformed mapping without a usable backup must stop before the real menu
	# asks InputBindings.key_for to assign it to its typed Dictionary local.
	var no_backup := _store("bindings-no-backup")
	var data := JSON.parse_string(FileAccess.get_file_as_string(defaulted.storage_path)) as Dictionary
	data.settings.bindings = "broken"
	_write(no_backup.storage_path, JSON.stringify(data))
	no_backup.load_progress()
	check(no_backup.load_status == "corrupt" and not no_backup.has_progress and Bindings.key_for(no_backup.settings, "attack") == KEY_J, "malformed bindings without backup expose safe defaults and an explicit corrupt status")

func _cleanup() -> void:
	var directory := DirAccess.open(test_directory)
	for filename in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory + "/" + filename))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory))
