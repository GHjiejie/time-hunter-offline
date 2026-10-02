extends SceneTree

var checks := 0
var failures := 0
const Model := preload("res://scripts/arena_model.gd")
const Store := preload("res://scripts/save_store.gd")

func _initialize() -> void:
	_test_movement_and_jump()
	_test_combo_and_skills()
	_test_dash_sweep()
	_test_staged_skills()
	_test_restart_and_death_rewards()
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

func advance(model: ArenaModel, seconds: float, movement: Vector2 = Vector2.ZERO) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var delta := minf(1.0 / 120.0, remaining)
		model.step(delta, movement)
		remaining -= delta

func has_effect(model: ArenaModel, kind: String, stage: int = -1) -> bool:
	return model.effects.any(func(effect): return effect.kind == kind and (stage < 0 or effect.get("stage", -1) == stage))

func _test_movement_and_jump() -> void:
	var model := Model.new()
	model.start(0, 42)
	enemy_at(model, Vector2(1100, 400))
	advance(model, 0.2, Vector2.RIGHT)
	check(model.player.pose == "run" and model.player.pose_time > 0.1, "running animation clock advances")
	var run_time := model.player.pose_time
	advance(model, 0.1, Vector2.RIGHT)
	check(model.player.pose_time > run_time, "running animation clock persists across movement frames")
	advance(model, 0.1)
	check(model.player.pose == "idle" and model.player.pose_time > 0.0 and model.player.pose_time < 0.1, "idle resets on transition and advances its animation clock")
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
	check(model.player.pose == "slash_1" and model.player.pose_time == 0.0, "attack exposes animation state")
	advance(model, 0.04)
	check(front.hp == 500, "attack damage waits for blade contact")
	advance(model, 0.04)
	check(front.hp < 500 and behind.hp == 500 and wrong_lane.hp == 500, "direction and lane hitboxes")
	check(has_effect(model, "slash", 1) and model.hitstop > 0, "contact produces timed slash and hitstop")
	check(front.velocity.x > 0, "hit imparts damped knockback velocity")
	check(not model.attack(), "attack cooldown")
	check(not model.skill("dash") and not model.jump(), "attack cannot overlap a skill or jump")
	advance(model, 0.23)
	check(model.attack() and model.combo == 2, "second combo hit")
	advance(model, 0.31)
	check(model.attack() and model.combo == 3, "third combo hit")
	advance(model, 0.15)
	check(front.vertical_speed > 0, "third hit launches")
	advance(model, 1.1)
	check(model.combo == 0, "combo expires without follow-up")
	model.player.stun = 0.2
	check(not model.attack() and not model.skill("burst") and not model.jump(), "stun gates all actions")

func _test_dash_sweep() -> void:
	var model := Model.new()
	model.start(0, 42)
	var front := enemy_at(model, model.player.pos + Vector2(150, 0))
	var wrong_lane := enemy_at(model, model.player.pos + Vector2(150, -84))
	var previous := model.player.pos
	check(model.skill("dash"), "dash activation")
	check(model.player.pos == previous and model.energy == 78.0, "dash starts without teleport and spends energy")
	check(not model.attack() and not model.skill("burst") and not model.skill("ultimate"), "dash locks simultaneous actions")
	model._damage_player(20)
	check(model.player.hp == model.player.max_hp, "dash grants invincibility")
	advance(model, 0.10, Vector2(-1, 1))
	check(model.player.pos.x > previous.x and model.player.pos.y == previous.y, "dash follows cast direction and ignores movement")
	advance(model, 0.25)
	check(is_equal_approx(model.player.pos.x, previous.x + 285.0), "dash lands at bounded target")
	check(front.hp == 454 and wrong_lane.hp == 500, "dash sweeps each target once within lane")
	check(not model.skill("dash"), "dash cooldown prevents repeats")
	advance(model, 3.4)
	check(model.cooldowns.dash == 0 and model.energy > 78.0, "cooldown and energy regenerate")
	model.player.pos.x = Model.BOUNDS.end.x - 5.0
	check(model.skill("dash"), "boundary dash activates")
	advance(model, 0.31)
	check(is_equal_approx(model.player.pos.x, Model.BOUNDS.end.x), "dash clamps arena boundary")

func _test_staged_skills() -> void:
	var model := Model.new()
	model.start(0, 42)
	model.player.pos.y = Model.BOUNDS.position.y
	var front := enemy_at(model, model.player.pos + Vector2(150, 0))
	var wrong_lane := enemy_at(model, Vector2(330, Model.BOUNDS.end.y))
	var casts: Array[String] = []
	model.skill_cast.connect(func(name): casts.append(name))
	model.energy = 10
	check(not model.skill("burst"), "insufficient energy rejects burst")
	model.energy = 100
	check(model.skill("burst") and model.energy == 52.0, "burst energy cost")
	check(model.player.pose == "burst" and has_effect(model, "rift_charge"), "burst telegraph and animation")
	advance(model, 0.12)
	check(front.hp == 500, "burst telegraph does not damage")
	advance(model, 0.06)
	check(front.hp == 476 and front.vertical_speed > 0 and has_effect(model, "rift", 1), "burst first rising cut")
	advance(model, 0.22)
	check(front.hp == 449 and has_effect(model, "rift", 2), "burst second cut deals once")
	advance(model, 0.32)
	check(front.hp == 401 and has_effect(model, "rift", 3), "burst heavy follow-through")
	check(wrong_lane.hp == 500, "burst respects combat lane")
	advance(model, 0.25)
	model.energy = 100
	var health := front.hp
	check(model.skill("ultimate") and model.energy == 25.0 and model.cooldowns.ultimate == 15.0, "ultimate cost and cooldown")
	check(model.player.pose == "ultimate" and has_effect(model, "ultimate_charge"), "ultimate telegraph and animation")
	var cast_position := model.player.pos
	advance(model, 0.42, Vector2.ONE)
	check(front.hp == health and model.player.pos == cast_position, "ultimate telegraphs before damage and locks movement")
	advance(model, 0.04)
	check(front.hp == health - 28 and has_effect(model, "ultimate", 1), "ultimate first strike")
	advance(model, 0.22)
	check(front.hp == health - 56, "ultimate second strike")
	advance(model, 0.24)
	check(front.hp == health - 88, "ultimate third strike")
	advance(model, 0.40)
	check(front.hp == health - 213 and has_effect(model, "ultimate", 4) and front.vertical_speed > 0, "ultimate heavy finisher")
	check(wrong_lane.hp == 500, "ultimate respects combat lane")
	check(casts == ["burst", "ultimate"], "successful casts emit one signal each")
	advance(model, 0.4)
	model.energy = 100
	check(not model.skill("ultimate"), "ultimate cooldown cannot be bypassed with energy")
	var before := model.energy
	check(not model.skill("missing") and model.energy == before, "unknown skill never spends energy")

func _test_restart_and_death_rewards() -> void:
	var model := Model.new()
	model.start(0, 42)
	var victim := enemy_at(model, model.player.pos + Vector2(100, 0), 10.0)
	check(model.skill("burst"), "kill test burst")
	advance(model, 0.8)
	check(victim.hp == 0 and model.kills == 1 and model.score == 170, "multi-hit kill awards once and scores actual damage")
	model._hit_enemy(victim, 999, 100)
	check(model.kills == 1 and model.score == 170, "dead targets cannot award repeated rewards")
	model.start(0, 42)
	enemy_at(model, Vector2(900, 400))
	model.skill("ultimate")
	check(not model.pending_hits.is_empty(), "ultimate schedules strikes")
	model.start(0, 42)
	check(model.pending_hits.is_empty() and model.effects.is_empty() and model.active_dash.is_empty() and model.hitstop == 0, "restart clears scheduled hits effects dash and hitstop")
	check(model.cooldowns.ultimate == 0 and model.energy == 100 and model.player.pose == "idle", "restart clears resources and animation")
	var fresh := enemy_at(model, model.player.pos + Vector2(100, 0))
	advance(model, 1.4)
	check(fresh.hp == 500, "cancelled cast cannot hit after restart")
	model.start(0, 42)
	model.wave = Model.MAX_WAVES
	enemy_at(model, model.player.pos + Vector2(100, 0), 10.0)
	model.skill("ultimate")
	advance(model, 1.32)
	check(model.running and has_effect(model, "ultimate", 4), "last-enemy early kill still presents ultimate finisher before victory")
	advance(model, 1.1)
	check(not model.running, "victory resolves after ultimate presentation")

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
