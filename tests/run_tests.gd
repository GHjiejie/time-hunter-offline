extends SceneTree

var checks := 0
var failures := 0
const Model := preload("res://scripts/arena_model.gd")
const Store := preload("res://scripts/save_store.gd")

func _initialize() -> void:
	_test_movement_and_jump()
	_test_combo_and_skills()
	_test_enemy_damage()
	_test_waves_and_rewards()
	_test_save()
	print("CHECKS: %d / FAILED: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func enemy_at(model: ArenaModel, pos: Vector2, health: float = 500.0) -> Fighter:
	var enemy := Fighter.new()
	enemy.pos = pos
	enemy.hp = health
	enemy.max_hp = health
	enemy.speed = 0
	enemy.attack_clock = 100
	model.enemies.append(enemy)
	return enemy

func _test_movement_and_jump() -> void:
	var model := Model.new()
	model.start(0, 42)
	enemy_at(model, Vector2(1100, 400))
	for index in range(120): model.step(1.0 / 60.0, Vector2(-1, -1))
	check(model.player.pos.x >= Model.BOUNDS.position.x and model.player.pos.y >= Model.BOUNDS.position.y, "arena bounds")
	check(model.jump(), "ground jump")
	check(not model.jump(), "no double jump")
	for index in range(80): model.step(1.0 / 60.0, Vector2.ZERO)
	check(is_zero_approx(model.player.height), "jump lands")
	check(model.jump(), "can jump after landing")

func _test_combo_and_skills() -> void:
	var model := Model.new()
	model.start(0, 42)
	var front := enemy_at(model, model.player.pos + Vector2(65, 0))
	var behind := enemy_at(model, model.player.pos - Vector2(65, 0))
	var wrong_lane := enemy_at(model, model.player.pos + Vector2(65, -90))
	check(model.attack(), "first attack")
	check(front.hp < 500 and behind.hp == 500 and wrong_lane.hp == 500, "direction and lane hitboxes")
	check(not model.attack(), "attack cooldown")
	for index in range(17): model.step(1.0 / 60.0, Vector2.ZERO)
	check(model.attack() and model.combo == 2, "second combo hit")
	for index in range(17): model.step(1.0 / 60.0, Vector2.ZERO)
	check(model.attack() and model.combo == 3, "third combo hit")
	check(front.vertical_speed > 0, "third hit launches")
	var start_x := model.player.pos.x
	check(model.skill("dash"), "dash activation")
	check(model.player.pos.x > start_x and model.energy == 78.0, "dash displacement and energy")
	check(not model.skill("dash"), "dash cooldown prevents repeats")
	model.energy = 10
	check(not model.skill("burst"), "insufficient energy rejects burst")
	model.energy = 100
	check(model.skill("burst") and model.energy == 52.0, "burst energy")
	for index in range(300): model.step(1.0 / 60.0, Vector2.ZERO)
	check(model.cooldowns.dash == 0 and model.energy > 52.0, "cooldown and energy regeneration")

func _test_enemy_damage() -> void:
	var model := Model.new()
	model.start(0, 2)
	var enemy := enemy_at(model, model.player.pos + Vector2(50, 0))
	enemy.attack_clock = 0
	for index in range(35): model.step(1.0 / 60.0, Vector2.ZERO)
	check(model.player.hp < model.player.max_hp, "enemy telegraph deals damage")
	var remaining := model.player.hp
	model._damage_player(30)
	check(model.player.hp == remaining, "damage immunity window")
	model.player.invincible = 0
	model.player.height = 90
	model._damage_player(30)
	check(model.player.hp == remaining, "jump dodges enemy damage")
	model.player.height = 0
	model.player.invincible = 0
	model._damage_player(9999)
	var losses := [0]
	model.finished.connect(func(won, _reward):
		if not won: losses[0] += 1)
	model.step(0.01, Vector2.ZERO)
	model.step(0.01, Vector2.ZERO)
	check(not model.running and losses[0] == 1, "defeat emitted once")

func _test_waves_and_rewards() -> void:
	var model := Model.new()
	model.start(0, 21)
	var victories := [0]
	model.finished.connect(func(won, _reward):
		if won: victories[0] += 1)
	model.step(0.7, Vector2.ZERO)
	check(model.wave == 1 and model.enemies.size() == 4, "first wave")
	for wave_index in range(3):
		for enemy in model.enemies: enemy.hp = 0
		for index in range(120): model.step(1.0 / 60.0, Vector2.ZERO)
		if wave_index == 1:
			check(model.enemies.any(func(enemy): return enemy.kind == "boss"), "boss in final wave")
	check(not model.running and victories[0] == 1, "three waves complete with single reward")

func _test_save() -> void:
	var test_path := "user://test-progress.json"
	var store := Store.new()
	store.coins = 80
	store.level = 3
	store.best_score = 500
	check(store.save_progress(test_path) == OK, "save succeeds")
	var restored := Store.new()
	restored.load_progress(test_path)
	check(restored.coins == 80 and restored.level == 3 and restored.best_score == 500, "progress persists")
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string('{"coins": "bad", "level": 999, "best_score": -10}')
	file.close()
	restored.load_progress(test_path)
	check(restored.coins == 0 and restored.level == Store.MAX_LEVEL and restored.best_score == 0, "invalid values clamped")
	file = FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string("broken json")
	file.close()
	restored.load_progress(test_path)
	check(restored.level == Store.MAX_LEVEL, "corrupt save does not crash")
	check(not restored.upgrade(), "max level cannot upgrade")
	restored.storage_path = test_path
	restored.level = 0
	restored.coins = 120
	check(restored.upgrade() and restored.level == 1 and restored.coins == 60, "upgrade deducts coins and increases level")
	var upgraded := Store.new()
	upgraded.load_progress(test_path)
	check(upgraded.level == 1 and upgraded.coins == 60, "upgrade saved")
	DirAccess.remove_absolute(test_path)
