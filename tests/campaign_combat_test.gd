extends SceneTree

const Model := preload("res://scripts/arena_model.gd")
const Content := preload("res://scripts/game_content.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_stage_encounters_and_resume()
	_test_loadout_and_skill_choices()
	_test_heavy_counterplay()
	_test_charger_locked_rush()
	_test_ranged_and_swept_collision()
	_test_boss_patterns_and_transition()
	_test_passives_require_actual_events()
	_test_hazards_chest_and_cleanup()
	print("CAMPAIGN COMBAT CHECKS: %d / FAILED: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func advance(model: ArenaModel, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var delta := minf(1.0 / 120.0, remaining)
		model.step(delta, Vector2.ZERO)
		remaining -= delta

func target(model: ArenaModel, kind: String, pos: Vector2, health: float = 1000.0) -> Fighter:
	var fighter := Fighter.new()
	fighter.kind = kind
	fighter.pos = pos
	fighter.hp = health
	fighter.max_hp = health
	fighter.speed = 0.0
	fighter.attack_clock = 100.0
	fighter.facing = -1.0
	model.enemies.append(fighter)
	return fighter

func isolated(build: Dictionary = {}) -> ArenaModel:
	var model := Model.new()
	model.start(0, 1701, "", build)
	model.wave_wait = 100.0
	return model

func strike(model: ArenaModel, fighter: Fighter, stage: int = 1) -> void:
	model._resolve_hit({"kind": "slash", "stage": stage, "damage": 22.0 if stage < 3 else 42.0, "reach": 200.0, "lane": 58.0, "knockback": 0.0, "launch": 0.0, "color": Color.WHITE, "shape": "forward", "pos": model.player.pos, "face": model.player.facing, "height": 0.0})

func _test_stage_encounters_and_resume() -> void:
	for id in Content.STAGE_IDS:
		var model := Model.new()
		var checkpoints: Array[int] = []
		model.checkpoint_reached.connect(func(index): checkpoints.append(index))
		model.start(0, 707, id)
		var waves: Array = Content.stage(id).waves
		for index in range(waves.size()):
			advance(model, 1.9 if index > 0 else 0.61)
			check(model.wave == index + 1 and model.total_waves == waves.size(), "%s displays encounter count" % id)
			var kinds: Array[String] = []
			for fighter in model.enemies:
				kinds.append(fighter.kind)
			check(kinds == Array(waves[index]), "%s encounter %d matches fixed composition" % [id, index])
			for fighter in model.enemies:
				fighter.hp = 0.0
		check(checkpoints.size() == waves.size() and checkpoints[0] == 0 and checkpoints[-1] == waves.size() - 1, "%s persists upcoming zero-based encounters" % id)
		advance(model, 1.9)
		check(not model.running, "%s always clears after last encounter" % id)
	var first := Model.new()
	first.start(2, 551, "corridor", {"health": 301.0, "skills": ["dash"]}, 1)
	advance(first, 0.61)
	var restored := Model.new()
	restored.start(2, 551, "corridor", {"health": 301.0, "skills": ["dash"]}, 1)
	advance(restored, 0.61)
	check(first.wave == 2 and restored.wave == 2 and restored.player.hp == 301.0 and restored.energy == 100.0, "checkpoint resumes room at full health and energy")
	check(first.enemies[0].kind == restored.enemies[0].kind and first.enemies[0].pos == restored.enemies[0].pos and is_equal_approx(first.enemies[0].attack_clock, restored.enemies[0].attack_clock), "room seed gives identical rebuilt encounter")
	check(first.constrain(Vector2.ZERO).x == 180.0, "corridor uses narrower tactical bounds")

func _test_loadout_and_skill_choices() -> void:
	var model := isolated({"health": 280.0, "attack": 33.0, "damage_scale": 1.5, "cooldown_scale": 0.8, "skills": ["dash"], "energy_regen": 7.0})
	var victim := target(model, "drone", model.player.pos + Vector2(65, 0))
	check(model.attack(), "configured basic attack starts")
	advance(model, 0.06)
	check(is_equal_approx(victim.hp, 967.0), "final attack multiplier applies exactly once")
	check(not model.skill("burst") and not model.has_skill("ultimate"), "locked skills cannot spend resources")
	advance(model, 0.3)
	check(model.skill("dash") and is_equal_approx(model.cooldowns.dash, 2.8), "equipment cooldown scales skill once")
	model.start(0, 1, "", {"health": 280.0, "attack": 33.0, "damage_scale": 1.5})
	check(model.player.max_hp == 280.0 and model.damage_scale == 1.5, "repeated start does not stack equipment")
	model.start(0, 1)
	check(model.player.max_hp == 220.0 and model.damage_scale == 1.0 and model.has_skill("ultimate"), "legacy defaults restored after configured run")
	var wide := isolated({"burst_variant": "wide"})
	var focused := isolated({"burst_variant": "focused"})
	wide.skill("burst")
	focused.skill("burst")
	check(wide.pending_hits[0].reach == 300.0 and focused.pending_hits[0].reach == 200.0, "burst choices change actual collision range")
	check(is_equal_approx(wide.pending_hits[0].damage, 19.2) and is_equal_approx(focused.pending_hits[0].damage, 28.8), "burst range trades against damage")
	var precision := isolated({"ultimate_variant": "precision"})
	precision.skill("ultimate")
	check(precision.pending_hits[0].reach < 470.0 and precision.pending_hits[0].damage > 28.0, "precision ultimate narrows range for greater damage")

func _test_heavy_counterplay() -> void:
	var model := isolated()
	model.player.pos = Vector2(400, 418)
	var heavy := target(model, "heavy", Vector2(480, 418))
	strike(model, heavy)
	check(is_equal_approx(heavy.hp, 995.6) and heavy.stun == 0.0 and model.effects.any(func(effect): return effect.kind == "guard"), "heavy front guard reduces damage and exposes feedback")
	strike(model, heavy, 3)
	check(is_equal_approx(heavy.hp, 953.6) and heavy.guard_open > 0.0 and heavy.recovery > 0.0, "third ordinary combo stage opens heavy guard")
	var back := target(model, "heavy", Vector2(480, 418))
	back.facing = 1.0
	strike(model, back)
	check(back.hp == 978.0 and back.guard_open > 0.0, "back attack bypasses and opens heavy guard")
	var committed := target(model, "heavy", Vector2(490, 418))
	committed.attack_clock = 0.0
	model._begin_enemy_attack(committed)
	var committed_target := committed.target
	model.player.pos = Vector2(550, 418)
	model._update_enemy(committed, 0.05)
	check(committed.target == committed_target and committed.facing < 0.0, "heavy commits facing during clear windup")
	model._resolve_enemy_attack(committed)
	check(model.player.hp == model.player.max_hp, "heavy frontal strike is avoided by walking behind it")
	check(committed.recovery >= 1.0, "heavy missed strike leaves punishable recovery")
	committed.guard_open = 2.0
	for index in range(30):
		model._hit_enemy(committed, 0.1, 0.0)
		model._update_enemy(committed, 0.05)
	check(committed.recovery < 1.0 and committed.stagger_cooldown > 0.0, "repeated light hits cannot indefinitely freeze heavy recovery")

func _test_charger_locked_rush() -> void:
	var model := isolated()
	model.player.pos = Vector2(450, 410)
	var charger := target(model, "charger", Vector2(850, 410))
	model._begin_enemy_attack(charger)
	var locked := charger.rush_end
	check(is_equal_approx(charger.windup, 0.7) and model.telegraphs()[0].attack == "rush", "charger gives directional warning before moving")
	model._hit_enemy(charger, 1.0, 400.0)
	check(charger.velocity == Vector2.ZERO, "committed rush cannot be displaced into a teleporting start")
	charger.stun = 0.0
	model.player.pos = Vector2(450, 478)
	model._update_enemy(charger, 0.4)
	check(charger.pos == Vector2(850, 410) and charger.rush_end == locked, "charger does not follow player during warning")
	model._update_enemy(charger, 0.31)
	model._update_enemy(charger, 0.32)
	check(charger.rush_end == locked and charger.attack_phase == "recovery" and is_equal_approx(charger.recovery, 0.9), "charger completes fixed rush then long recovery")
	check(model.player.hp == model.player.max_hp, "sidestepping locked rush lane avoids its damage")
	model.player.pos = Vector2(550, 410)
	charger.pos = Vector2(850, 410)
	charger.recovery = 0.0
	model._begin_enemy_attack(charger)
	model._resolve_enemy_attack(charger)
	model._update_enemy(charger, 0.32)
	check(model.player.hp == model.player.max_hp - 25.0 and charger.rush_hit, "coarse rush sweeps player once without tunneling")
	model.player.invincible = 0.0
	model._update_enemy(charger, 0.01)
	check(model.player.hp == model.player.max_hp - 25.0, "same rush cannot hit a second time")

func _test_ranged_and_swept_collision() -> void:
	var model := isolated()
	var ranged := target(model, "ranged", Vector2(700, 418))
	model._begin_enemy_attack(ranged)
	var locked := ranged.target
	model.player.pos.y = 470.0
	model._update_enemy(ranged, 0.3)
	check(ranged.target == locked and model.telegraphs()[0].kind == "line", "ranged aim stays locked and visible through windup")
	model._update_enemy(ranged, 0.36)
	check(model.projectiles.size() == 1 and ranged.recovery >= 0.8, "ranged shot creates an approach gap")
	model.projectiles.clear()
	model.player.pos = Vector2(500, 418)
	model.projectiles.append({"pos": Vector2(350, 418), "velocity": Vector2(1000, 0), "life": 2.0})
	model._update_projectiles(0.3)
	check(model.player.hp == model.player.max_hp - 15.0 and model.projectiles.is_empty(), "fast projectile crossing player hits despite distant endpoint")
	model.player.invincible = 0.0
	model.projectiles.append({"pos": Vector2(350, 360), "velocity": Vector2(1000, 0), "life": 2.0})
	model._update_projectiles(0.3)
	check(model.player.hp == model.player.max_hp - 15.0, "projectile sweep preserves lane dodge")

func _test_boss_patterns_and_transition() -> void:
	var model := isolated()
	model.player.pos = Vector2(600, 418)
	var boss := target(model, "boss", Vector2(820, 418), 580.0)
	var patterns: Array[String] = []
	for index in range(3):
		model._begin_enemy_attack(boss)
		patterns.append(boss.attack_kind)
		model.player.pos = Vector2(300, 334)
		model._resolve_enemy_attack(boss)
		boss.recovery = 0.0
	check(patterns == ["cleave", "projectile", "slam"], "boss alternates close, ranged and floor attacks")
	boss.hp = 280.0
	var before := model.player.hp
	model._update_enemy(boss, 0.01)
	check(boss.phase == 2 and boss.attack_kind == "transition" and is_equal_approx(boss.windup, 0.9), "boss half health gives announced phase transition")
	model._update_enemy(boss, 0.91)
	check(model.player.hp == before and boss.recovery > 0.0, "phase transition has no hidden damage")
	boss.recovery = 0.0
	model._begin_enemy_attack(boss)
	check(boss.attack_kind == "rush", "phase two changes opening to fixed rush")
	model._resolve_enemy_attack(boss)
	model._update_enemy_rush(boss, 0.32)
	boss.recovery = 0.0
	model._begin_enemy_attack(boss)
	var circles := model.telegraphs().filter(func(warning): return warning.kind == "circle")
	check(boss.attack_kind == "slam" and circles.size() == 2, "phase two floor slam visibly pressures two positions")
	model.player.pos = Vector2(1190, 334)
	model.player.invincible = 0.0
	before = model.player.hp
	model._resolve_enemy_attack(boss)
	check(model.player.hp == before, "leaving marked boss floor circles avoids slam")

func _test_passives_require_actual_events() -> void:
	var model := isolated({"passive": "guard"})
	target(model, "drone", Vector2(1000, 418))
	model.skill("dash")
	check(model.retaliation_time == 0.0, "casting dash alone does not award retaliation")
	model._damage_player(20.0)
	check(model.retaliation_time == 0.0, "manual invulnerability probe cannot award retaliation")
	model._damage_player(20.0, model.player.pos + Vector2(80, 0), "追击者攻击", true)
	check(model.retaliation_time == 4.0 and model.retaliation_cooldown == 3.0, "real enemy hit avoided in dash arms capped retaliation")
	model.player.action_lock = 0.0
	model.player.attack_clock = 0.0
	model.active_dash.clear()
	model.attack()
	check(is_equal_approx(model.pending_hits[0].damage, 29.7) and model.retaliation_time == 0.0, "retaliation amplifies one next action then consumes")
	model.player.height = 90.0
	model._damage_player(20.0, Vector2.ZERO, "真实攻击", true)
	check(model.retaliation_time == 0.0, "retaliation internal cooldown blocks repeated grants")
	var protected := isolated({"passive": "guard"})
	target(protected, "drone", Vector2(1000, 418))
	protected.skill("burst")
	protected._damage_player(20.0, Vector2.ZERO, "真实攻击", true)
	check(protected.retaliation_time == 0.0, "burst invulnerability is not a successful dodge passive event")
	var assault := isolated({"passive": "assault"})
	assault.energy = 40.0
	strike(assault, Fighter.new())
	check(assault.assault_hits == 0 and assault.energy == 40.0, "whiff has no combo refund")
	var victim := target(assault, "drone", assault.player.pos + Vector2(60, 0))
	target(assault, "drone", assault.player.pos + Vector2(70, 0))
	strike(assault, victim)
	check(assault.assault_hits == 1 and assault.energy == 40.0, "multi target slash counts as one confirmed ordinary hit")
	strike(assault, victim, 2)
	strike(assault, victim, 3)
	check(assault.energy == 46.0 and assault.assault_cooldown == 2.0, "three confirmed stages refund six energy once")
	for index in range(3):
		strike(assault, victim)
	check(assault.energy == 46.0, "assault refund cannot loop within internal cooldown")
	var expired := isolated({"passive": "assault"})
	var slow_target := target(expired, "drone", expired.player.pos + Vector2(60, 0))
	expired.energy = 20.0
	strike(expired, slow_target)
	advance(expired, 1.1)
	strike(expired, slow_target)
	advance(expired, 1.0)
	check(expired.assault_hits == 0, "assault requires all three hits within a fixed two second window")

func _test_hazards_chest_and_cleanup() -> void:
	var model := Model.new()
	model.start(0, 15, "corridor")
	advance(model, 0.61)
	model.hazard_clock = 0.01
	model._update_hazards(0.02)
	check(model.hazards.size() == 1 and model.hazards[0].phase == "telegraph", "corridor floor lane announces before active damage")
	var rect: Rect2 = model.hazards[0].rect
	model.player.pos = rect.get_center()
	var before := model.player.hp
	model._update_hazards(0.3)
	check(model.player.hp == before, "hazard warning causes no damage")
	model._update_hazards(0.66)
	check(model.hazards[0].phase == "active" and model.player.hp < before and model.damage_taken > 0.0, "marked floor becomes active and records failure cause")
	model.player.pos = model.chests[0].pos - Vector2(50, 0)
	model.player.facing = 1.0
	strike(model, Fighter.new())
	strike(model, Fighter.new(), 3)
	check(model.chests[0].opened and model.bonus_coins == 8, "attacking visible chest reserves bonus once")
	var endings := [0]
	model.finished.connect(func(_won, _reward): endings[0] += 1)
	model.player.hp = 0.0
	model.pending_hits.append({"kind": "slash", "delay": 99.0})
	model.active_dash = {"elapsed": 0.0, "duration": 1.0, "start": model.player.pos, "end": model.player.pos, "face": 1.0, "height": 0.0, "damage": 46.0}
	model.step(0.01, Vector2.ZERO)
	model.step(0.01, Vector2.ZERO)
	check(endings[0] == 1 and not model.running and model.hazards.is_empty() and model.projectiles.is_empty() and model.pending_hits.is_empty() and model.active_dash.is_empty(), "death clears attacks and hazards and signals once")
	var summary := model.stats()
	check(summary.bonus_coins == 8 and summary.damage > 0.0 and not summary.last_damage_reason.is_empty(), "settlement exposes reserved chest and concrete failure stats")
	model.start(0, 15, "corridor")
	check(model.bonus_coins == 0 and not model.chests[0].opened and model.damage_taken == 0.0 and model.hazards.is_empty(), "restart resets room loot and damage without residual state")
