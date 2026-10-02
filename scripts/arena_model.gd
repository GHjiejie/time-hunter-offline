class_name ArenaModel
extends RefCounted

signal impact(position: Vector2, color: Color, strength: float)
signal message(text: String)
signal finished(won: bool, reward: int)
signal skill_cast(name: String)
## Presentation events follow the same timeline as damage, including a whiff.
signal skill_released(name: String, stage: int)
signal checkpoint_reached(wave_index: int)

const BOUNDS := Rect2(65, 334, 1150, 145)
const MAX_WAVES := 3
const SKILL_COST := {"dash": 22.0, "burst": 48.0, "ultimate": 75.0}
const SKILL_COOLDOWN := {"dash": 3.5, "burst": 7.0, "ultimate": 15.0}
var player: Fighter
var enemies: Array[Fighter] = []
var effects: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var cooldowns := {"dash": 0.0, "burst": 0.0, "ultimate": 0.0}
var pending_hits: Array[Dictionary] = []
var active_dash: Dictionary = {}
var dash_targets: Array[Fighter] = []
# This is a request in real seconds. The presentation layer consumes it while
# suspending simulation, so a heavy hit also pauses the attack animation.
var hitstop := 0.0
var rng := RandomNumberGenerator.new()
var energy := 100.0
var wave := 0
var wave_wait := 0.0
var score := 0
var kills := 0
var combo := 0
var combo_window := 0.0
var streak := 0
var streak_window := 0.0
var power := 0
var elapsed := 0.0
var running := false
var next_id := 0
var stage_id := ""
var stage: Dictionary = {}
var total_waves := MAX_WAVES
var run_seed := 0
var loadout: Dictionary = {}
var damage_scale := 1.0
var cooldown_scale := 1.0
var energy_regen := 9.0
var unlocked_skills: Array = ["dash", "burst", "ultimate"]
var passive := ""
var burst_variant := "normal"
var ultimate_variant := "normal"
var damage_taken := 0.0
var last_damage_reason := ""
var hazards: Array[Dictionary] = []
var chests: Array[Dictionary] = []
var bonus_coins := 0
var hazard_clock := 2.6
var hazard_index := 0
var retaliation_time := 0.0
var retaliation_cooldown := 0.0
var buff_label := ""
var assault_hits := 0
var assault_window := 0.0
var assault_cooldown := 0.0

func start(level: int = 0, random_seed: int = 0, selected_stage: String = "", build: Dictionary = {}, checkpoint: int = 0) -> void:
	stage_id = selected_stage
	stage = {}
	if not stage_id.is_empty():
		var content = load("res://scripts/game_content.gd")
		stage = content.stage(stage_id)
		if stage.is_empty():
			stage_id = ""
	total_waves = stage.get("waves", []).size() if not stage_id.is_empty() else MAX_WAVES
	loadout = build.duplicate(true)
	# The catalog supplies absolute health and a final attack multiplier. Legacy
	# callers retain their original level growth and all three skills.
	power = level if loadout.is_empty() else 0
	damage_scale = clampf(float(loadout.get("damage_scale", float(loadout.get("attack", 22.0)) / 22.0)), 0.25, 3.0)
	cooldown_scale = clampf(float(loadout.get("cooldown_scale", 1.0)), 0.5, 1.5)
	energy_regen = clampf(float(loadout.get("energy_regen", 9.0)), 3.0, 18.0)
	unlocked_skills = loadout.get("skills", ["dash", "burst", "ultimate"]).duplicate()
	passive = str(loadout.get("passive", ""))
	burst_variant = str(loadout.get("burst_variant", "normal"))
	ultimate_variant = str(loadout.get("ultimate_variant", "normal"))
	if random_seed == 0:
		rng.randomize()
		run_seed = int(rng.randi())
	else:
		run_seed = random_seed
	rng.seed = run_seed
	player = Fighter.new()
	player.kind = "player"
	player.pos = Vector2(300, 418)
	player.max_hp = clampf(float(loadout.get("health", 220.0 + level * 25.0)), 80.0, 600.0)
	player.hp = player.max_hp
	player.speed = 265.0
	player.tint = Color("76eee6")
	player.pos = constrain(player.pos)
	enemies.clear()
	effects.clear()
	projectiles.clear()
	pickups.clear()
	hazards.clear()
	chests.clear()
	if not stage_id.is_empty():
		chests.append({"pos": Vector2(_bounds().end.x - 70.0, 462.0), "opened": false})
	cooldowns = {"dash": 0.0, "burst": 0.0, "ultimate": 0.0}
	pending_hits.clear()
	active_dash.clear()
	dash_targets.clear()
	hitstop = 0.0
	energy = 100.0
	wave = clampi(checkpoint, 0, maxi(0, total_waves - 1)) if not stage_id.is_empty() else 0
	wave_wait = 0.6
	score = 0
	kills = 0
	combo = 0
	combo_window = 0.0
	streak = 0
	streak_window = 0.0
	elapsed = 0.0
	damage_taken = 0.0
	last_damage_reason = ""
	bonus_coins = 0
	hazard_clock = 2.6
	hazard_index = wave
	retaliation_time = 0.0
	retaliation_cooldown = 0.0
	buff_label = ""
	assault_hits = 0
	assault_window = 0.0
	assault_cooldown = 0.0
	running = true
	next_id = 0

func stats() -> Dictionary:
	return {"time": elapsed, "kills": kills, "damage": damage_taken, "score": score, "bonus_coins": bonus_coins, "last_damage_reason": last_damage_reason}

func _bounds() -> Rect2:
	return stage.get("bounds", BOUNDS)

func has_skill(name: String) -> bool:
	return unlocked_skills.has(name)

func _action_multiplier() -> float:
	var result := damage_scale
	if retaliation_time > 0.0:
		result *= 1.35
		retaliation_time = 0.0
		buff_label = ""
	return result

func step(delta: float, movement: Vector2, attacking: bool = false) -> void:
	if not running:
		return
	elapsed += delta
	player.tick(delta)
	player.pos = constrain(player.pos)
	energy = minf(100.0, energy + delta * energy_regen)
	retaliation_time = maxf(0.0, retaliation_time - delta)
	retaliation_cooldown = maxf(0.0, retaliation_cooldown - delta)
	assault_window = maxf(0.0, assault_window - delta)
	assault_cooldown = maxf(0.0, assault_cooldown - delta)
	if retaliation_time <= 0.0:
		buff_label = ""
	if assault_window <= 0.0:
		assault_hits = 0
	for key in cooldowns:
		cooldowns[key] = maxf(0.0, cooldowns[key] - delta)
	combo_window = maxf(0.0, combo_window - delta)
	streak_window = maxf(0.0, streak_window - delta)
	if combo_window <= 0.0:
		combo = 0
	if streak_window <= 0.0:
		streak = 0
	_update_dash(delta)
	player.moving = 0.0
	if player.stun <= 0.0 and player.action_lock <= 0.0:
		if movement.length() > 1.0:
			movement = movement.normalized()
		player.pos += Vector2(movement.x, movement.y * 0.55) * player.speed * delta
		player.moving = movement.length()
		var locomotion_pose := "run" if player.moving > 0.08 else "idle"
		if player.pose != locomotion_pose:
			player.pose_time = 0.0
		player.pose = locomotion_pose
		player.pos = constrain(player.pos)
		if absf(movement.x) > 0.15:
			player.facing = signf(movement.x)
		if attacking:
			attack()
	_update_pending_hits(delta)
	for enemy in enemies:
		_update_enemy(enemy, delta)
	_update_projectiles(delta)
	_update_hazards(delta)
	for drop in pickups:
		drop.life -= delta
		if player.pos.distance_to(drop.pos) < 48.0:
			player.hp = minf(player.max_hp, player.hp + 32.0)
			drop.life = 0.0
			message.emit("生命恢复 +32")
	pickups = pickups.filter(func(drop): return drop.life > 0.0)
	for effect in effects:
		effect.life -= delta
	effects = effects.filter(func(effect): return effect.life > 0.0)
	enemies = enemies.filter(func(enemy): return enemy.hp > 0.0)
	if player.hp <= 0.0:
		_end(false)
		return
	if enemies.is_empty():
		wave_wait -= delta
		if wave_wait <= 0.0:
			if wave >= total_waves:
				_end(true)
			else:
				_spawn_wave()
	else:
		wave_wait = 1.8

func constrain(pos: Vector2) -> Vector2:
	var bounds := _bounds()
	return Vector2(clampf(pos.x, bounds.position.x, bounds.end.x), clampf(pos.y, bounds.position.y, bounds.end.y))

func jump() -> bool:
	if not running or player.height > 0.0 or player.stun > 0.0 or player.action_lock > 0.0:
		return false
	player.vertical_speed = 660.0
	player.height = 0.1
	return true

func attack() -> bool:
	if not _can_act() or player.attack_clock > 0.0:
		return false
	combo = combo % 3 + 1
	combo_window = 1.05
	var duration := [0.27, 0.29, 0.52][combo - 1] as float
	var multiplier := _action_multiplier()
	player.attack_clock = duration
	player.set_pose("slash_%d" % combo, duration)
	player.moving = 0.0
	_queue_hit("slash", [0.055, 0.075, 0.13][combo - 1], combo,
		((22.0 if combo < 3 else 42.0) + power * 4.0) * multiplier,
		145.0 if combo < 3 else 200.0, 58.0,
		310.0 if combo < 3 else 580.0, 460.0 if combo == 3 else 0.0,
		Color("76eee6"), "forward")
	return true

func skill(name: String) -> bool:
	if not _can_act() or not SKILL_COST.has(name) or not has_skill(name) or cooldowns[name] > 0.0 or energy < SKILL_COST[name]:
		return false
	energy -= SKILL_COST[name]
	cooldowns[name] = SKILL_COOLDOWN[name] * cooldown_scale
	var multiplier := _action_multiplier()
	player.moving = 0.0
	player.velocity = Vector2.ZERO
	combo = 0
	combo_window = 0.0
	if name == "dash":
		player.set_pose("dash", 0.30)
		player.invincible = 0.44
		active_dash = {"start": player.pos, "end": constrain(player.pos + Vector2(player.facing * 285.0, 0.0)), "elapsed": 0.0, "duration": 0.30, "face": player.facing, "height": player.height, "damage": (46.0 + power * 6.0) * multiplier}
		dash_targets.clear()
		_add_effect("dash", player.pos, 0.42, Color("76eee6"), {"end": active_dash.end, "size": 140.0, "duration": 0.30})
	elif name == "burst":
		player.set_pose("burst", 0.92)
		player.invincible = 0.94
		_add_effect("rift_charge", player.pos, 0.16, Color("bfa2ff"), {"size": 245.0})
		var reach_scale := 1.2 if burst_variant == "wide" else (0.8 if burst_variant == "focused" else 1.0)
		var burst_scale := (0.8 if burst_variant == "wide" else (1.2 if burst_variant == "focused" else 1.0)) * multiplier
		_queue_hit("rift", 0.16, 1, (24.0 + power * 2.0) * burst_scale, 250.0 * reach_scale, 85.0 * reach_scale, 130.0, 360.0, Color("91cfff"))
		_queue_hit("rift", 0.38, 2, (27.0 + power * 2.0) * burst_scale, 270.0 * reach_scale, 90.0 * reach_scale, 170.0, 340.0, Color("bfa2ff"))
		_queue_hit("rift", 0.68, 3, (48.0 + power * 4.0) * burst_scale, 290.0 * reach_scale, 95.0 * reach_scale, 640.0, 560.0, Color("dcbdff"))
	else:
		player.set_pose("ultimate", 1.62)
		player.invincible = 1.7
		_add_effect("ultimate_charge", player.pos, 0.44, Color("ffcc87"), {"size": 470.0})
		var ultimate_range := 0.7 if ultimate_variant == "precision" else 1.0
		var ultimate_scale := multiplier * (1.3 if ultimate_variant == "precision" else 1.0)
		_queue_hit("ultimate", 0.44, 1, (28.0 + power * 2.0) * ultimate_scale, 470.0 * ultimate_range, 135.0 * ultimate_range, 30.0, 0.0, Color("93e7ff"))
		_queue_hit("ultimate", 0.66, 2, (28.0 + power * 2.0) * ultimate_scale, 470.0 * ultimate_range, 135.0 * ultimate_range, 40.0, 0.0, Color("cdb8ff"))
		_queue_hit("ultimate", 0.90, 3, (32.0 + power * 2.0) * ultimate_scale, 470.0 * ultimate_range, 135.0 * ultimate_range, 60.0, 0.0, Color("94eeff"))
		_queue_hit("ultimate", 1.28, 4, (125.0 + power * 8.0) * ultimate_scale, 485.0 * ultimate_range, 140.0 * ultimate_range, 780.0, 650.0, Color("ffda91"))
	skill_cast.emit(name)
	if name == "dash":
		skill_released.emit(name, 1)
	return true

func _can_act() -> bool:
	return running and player.hp > 0.0 and player.stun <= 0.0 and player.action_lock <= 0.0

func _add_effect(kind: String, pos: Vector2, duration: float, color: Color, extra: Dictionary = {}) -> void:
	var effect := {"kind": kind, "pos": pos, "face": player.facing, "height": player.height, "life": duration, "max": duration, "color": color}
	effect.merge(extra, true)
	effects.append(effect)

func _queue_hit(kind: String, delay: float, stage: int, damage: float, reach: float, lane: float, knockback: float, launch: float, color: Color, shape: String = "ellipse") -> void:
	pending_hits.append({"kind": kind, "delay": delay, "stage": stage, "damage": damage, "reach": reach, "lane": lane, "knockback": knockback, "launch": launch, "color": color, "shape": shape, "pos": player.pos, "face": player.facing, "height": player.height})

func _update_pending_hits(delta: float) -> void:
	var due: Array[Dictionary] = []
	for hit in pending_hits:
		hit.delay -= delta
		if hit.delay <= 0.0:
			due.append(hit)
	pending_hits = pending_hits.filter(func(hit): return hit.delay > 0.0)
	for hit in due:
		_resolve_hit(hit)

func _resolve_hit(hit: Dictionary) -> void:
	var duration := (0.27 if hit.stage == 3 else 0.20) if hit.kind == "slash" else (0.36 if hit.stage >= 3 else 0.24)
	if hit.kind == "ultimate":
		duration = 0.48 if hit.stage == 4 else 0.24
	_add_effect(hit.kind, hit.pos, duration, hit.color, {"face": hit.face, "height": hit.height, "stage": hit.stage, "size": hit.reach, "lane": hit.lane})
	skill_released.emit("burst" if hit.kind == "rift" else hit.kind, hit.stage)
	var heavy: bool = (hit.kind == "slash" and hit.stage == 3) or (hit.kind == "rift" and hit.stage == 3) or (hit.kind == "ultimate" and hit.stage == 4)
	var confirmed_hit := false
	_open_chests(hit)
	for enemy in enemies:
		if enemy.hp <= 0.0:
			continue
		var difference: Vector2 = enemy.pos - hit.pos
		var inside := false
		if hit.shape == "forward":
			inside = difference.x * hit.face >= -28.0 and difference.x * hit.face <= hit.reach and absf(difference.y) < hit.lane and absf(enemy.height - hit.height) < 190.0
		else:
			inside = pow(difference.x / hit.reach, 2) + pow(difference.y / hit.lane, 2) <= 1.0 and enemy.height < 310.0
		if inside:
			confirmed_hit = true
			var direction: float = hit.face if hit.shape == "forward" else (1.0 if difference.x >= 0.0 else -1.0)
			_hit_enemy(enemy, hit.damage, hit.knockback, hit.launch, direction, hit.color, 0.9 if heavy else 0.42, 0.075 if heavy else 0.028, str(hit.kind), int(hit.stage), hit.pos)
	if hit.kind == "rift" or hit.kind == "ultimate":
		projectiles = projectiles.filter(func(projectile): return pow((projectile.pos.x - hit.pos.x) / hit.reach, 2) + pow((projectile.pos.y - hit.pos.y) / hit.lane, 2) > 1.0)
	if hit.kind == "slash" and confirmed_hit and passive == "assault" and assault_cooldown <= 0.0:
		if assault_hits == 0:
			assault_window = 2.0
		assault_hits += 1
		if assault_hits >= 3:
			energy = minf(100.0, energy + 6.0)
			assault_hits = 0
			assault_cooldown = 2.0
			message.emit("连击回能 +6 · 2秒内最多一次")
	if heavy and confirmed_hit:
		impact.emit(hit.pos - Vector2(0, 45), hit.color, 1.1 if hit.kind == "ultimate" else 0.7)

func _update_dash(delta: float) -> void:
	if active_dash.is_empty():
		return
	var previous := player.pos
	active_dash.elapsed = minf(active_dash.duration, active_dash.elapsed + delta)
	var progress: float = active_dash.elapsed / active_dash.duration
	player.pos = active_dash.start.lerp(active_dash.end, 1.0 - pow(1.0 - progress, 2.0))
	for enemy in enemies:
		if enemy.hp > 0.0 and not dash_targets.has(enemy) and enemy.pos.x >= minf(previous.x, player.pos.x) - 45.0 and enemy.pos.x <= maxf(previous.x, player.pos.x) + 45.0 and absf(enemy.pos.y - player.pos.y) < 58.0 and absf(enemy.height - active_dash.height) < 190.0:
			dash_targets.append(enemy)
			_hit_enemy(enemy, active_dash.damage, 450.0, 130.0, active_dash.face, Color("8decff"), 0.65, 0.04, "dash", 1, active_dash.start)
	for chest in chests:
		if not chest.opened and _segment_distance(chest.pos, previous, player.pos) < 48.0:
			_open_chest(chest)
	if progress >= 1.0:
		_add_effect("slash", player.pos, 0.20, Color("a6f5ff"), {"stage": 2, "size": 130.0})
		active_dash.clear()

func _hit_enemy(enemy: Fighter, damage: float, knockback: float, launch: float = 0.0, direction: float = 0.0, color: Color = Color("fff0c8"), strength: float = 0.45, stop: float = 0.03, attack_kind: String = "", attack_stage: int = 0, source: Vector2 = Vector2.ZERO) -> void:
	if enemy.hp <= 0.0:
		return
	if is_zero_approx(direction):
		direction = player.facing
	var guarded := false
	if enemy.kind == "heavy" and enemy.guard_open <= 0.0 and enemy.recovery <= 0.0:
		var attacker := player.pos if source == Vector2.ZERO else source
		var frontal := (attacker.x - enemy.pos.x) * enemy.facing >= -12.0
		var breaker := attack_kind == "slash" and attack_stage == 3
		if not frontal or breaker:
			enemy.guard_open = 1.6
			enemy.recovery = maxf(enemy.recovery, 0.65)
			enemy.attack_phase = "recovery"
			enemy.windup = 0.0
			message.emit("重装破防 · 绕后或第三段普攻")
		else:
			guarded = true
			damage *= 0.2
			knockback *= 0.15
			launch = 0.0
			_add_effect("guard", enemy.pos - Vector2(0, 55), 0.35, Color("ffd68c"), {"size": 36.0, "text": "格挡"})
	var dealt := minf(enemy.hp, damage)
	enemy.hp = maxf(0.0, enemy.hp - damage)
	if not guarded:
		if enemy.kind == "boss" or enemy.kind == "heavy" or enemy.kind == "charger":
			# Limited stagger protects a readable enemy commitment from an endless
			# light-attack stun loop. Recovery and guard breaks remain punishable.
			if enemy.stagger_cooldown <= 0.0 and enemy.attack_phase != "rush" and enemy.attack_kind != "transition":
				enemy.stun = maxf(enemy.stun, 0.10 if enemy.kind == "boss" else 0.22)
				enemy.stagger_cooldown = 1.25
		else:
			enemy.stun = maxf(enemy.stun, 0.52)
			enemy.windup = 0.0
			enemy.attack_phase = "recovery"
			enemy.recovery = maxf(enemy.recovery, 0.25)
			enemy.set_pose("hurt", 0.3)
		if enemy.attack_kind == "rush" and enemy.attack_phase in ["windup", "rush"]:
			enemy.velocity = Vector2.ZERO
		else:
			enemy.velocity.x = direction * knockback * (0.20 if enemy.kind == "boss" else (0.35 if enemy.kind == "heavy" else 1.0))
		if launch > 0.0 and enemy.kind != "boss" and enemy.kind != "heavy" and enemy.kind != "charger":
			enemy.vertical_speed = launch
			enemy.height = maxf(enemy.height, 0.1)
	streak += 1
	streak_window = 2.0
	score += int(dealt) * 2
	_add_effect("number", enemy.pos - Vector2(0, 105 + enemy.height), 0.65, color, {"text": str(int(dealt)), "heavy": strength > 0.7})
	_add_effect("hit", enemy.pos - Vector2(0, 55 + enemy.height), 0.20, color, {"size": 68.0 if strength > 0.7 else 38.0, "strength": strength, "face": direction, "direction": Vector2(direction, -0.16).normalized()})
	hitstop = maxf(hitstop, stop)
	impact.emit(enemy.pos - Vector2(0, 55 + enemy.height), color, strength)
	if enemy.hp <= 0.0:
		enemy.windup = 0.0
		enemy.rush_left = 0.0
		kills += 1
		score += 150 if enemy.kind != "boss" else 1200
		if rng.randf() < 0.4:
			pickups.append({"pos": enemy.pos, "life": 16.0})

func _damage_player(damage: float, from: Vector2 = Vector2.ZERO, reason: String = "", actual_attack: bool = false) -> void:
	if player.hp <= 0.0 or not running:
		return
	if player.invincible > 0.0 or player.height > 48.0:
		# A cast alone gives no bonus. Only an enemy attack that crosses the
		# player's footprint while a dash/jump avoids it can arm retaliation.
		var evaded := player.height > 48.0 or (player.invincible > 0.0 and player.pose == "dash")
		if actual_attack and evaded and passive == "guard" and retaliation_cooldown <= 0.0:
			retaliation_time = 4.0
			retaliation_cooldown = 3.0
			buff_label = "反击 +35% · 下一次攻击"
			message.emit("成功闪避 · 4秒内下一次攻击 +35%")
		return
	var dealt := minf(player.hp, damage)
	player.hp = maxf(0.0, player.hp - damage)
	damage_taken += dealt
	last_damage_reason = reason if not reason.is_empty() else "近身攻击"
	player.invincible = 0.7
	player.stun = 0.18
	player.set_pose("hurt", 0.22)
	player.velocity.x = (1.0 if player.pos.x >= from.x else -1.0) * 180.0
	pending_hits = pending_hits.filter(func(hit): return hit.kind != "slash")
	hitstop = maxf(hitstop, 0.055)
	streak = 0
	impact.emit(player.pos - Vector2(0, 40), Color("ff667e"), 0.8)

func _update_enemy(enemy: Fighter, delta: float) -> void:
	if enemy.hp <= 0.0:
		return
	enemy.tick(delta)
	enemy.pos = constrain(enemy.pos)
	enemy.guard_open = maxf(0.0, enemy.guard_open - delta)
	enemy.stagger_cooldown = maxf(0.0, enemy.stagger_cooldown - delta)
	if enemy.kind == "boss" and enemy.phase == 1 and enemy.hp <= enemy.max_hp * 0.5:
		enemy.phase = 2
		enemy.attack_index = 0
		enemy.attack_kind = "transition"
		enemy.attack_phase = "windup"
		enemy.windup = 0.9
		enemy.recovery = 0.0
		enemy.rush_left = 0.0
		enemy.velocity = Vector2.ZERO
		enemy.stun = 0.0
		message.emit("守卫第二阶段 · 冲锋后双重落点，转换期间安全")
		return
	if enemy.attack_phase == "rush":
		_update_enemy_rush(enemy, delta)
		return
	if enemy.stun > 0.0 or enemy.height > 5.0:
		return
	if enemy.windup > 0.0:
		enemy.windup -= delta
		if enemy.windup <= 0.0:
			_resolve_enemy_attack(enemy)
		return
	if enemy.recovery > 0.0:
		enemy.recovery = maxf(0.0, enemy.recovery - delta)
		enemy.attack_phase = "recovery"
		if enemy.recovery <= 0.0:
			enemy.attack_phase = "idle"
		return
	var difference := player.pos - enemy.pos
	enemy.facing = 1.0 if difference.x >= 0.0 else -1.0
	var range_x := 440.0 if enemy.kind == "ranged" else (550.0 if enemy.kind == "charger" or enemy.kind == "boss" else (160.0 if enemy.kind == "heavy" else 66.0))
	if absf(difference.x) < range_x and absf(difference.y) < (80.0 if enemy.kind == "boss" else 46.0) and enemy.attack_clock <= 0.0:
		_begin_enemy_attack(enemy)
	elif absf(difference.x) > range_x * 0.8 or absf(difference.y) > 25.0:
		var motion := difference.normalized()
		enemy.pos = constrain(enemy.pos + Vector2(motion.x, motion.y * 0.7) * enemy.speed * delta)

func _begin_enemy_attack(enemy: Fighter) -> void:
	enemy.target = player.pos
	enemy.attack_phase = "windup"
	enemy.rush_hit = false
	if enemy.kind == "boss":
		var order: Array = ["cleave", "projectile", "slam"] if enemy.phase == 1 else ["rush", "slam", "cleave", "projectile"]
		enemy.attack_kind = str(order[enemy.attack_index % order.size()])
		enemy.attack_index += 1
		enemy.windup = 0.85 if enemy.attack_kind == "slam" else 0.75
		enemy.attack_clock = 2.6 if enemy.phase == 1 else 2.25
	elif enemy.kind == "ranged":
		enemy.attack_kind = "projectile"
		enemy.windup = 0.65
		enemy.attack_clock = 2.2
	elif enemy.kind == "heavy":
		enemy.attack_kind = "cleave"
		enemy.windup = 0.85
		enemy.attack_clock = 2.3
	elif enemy.kind == "charger":
		enemy.attack_kind = "rush"
		enemy.windup = 0.7
		enemy.attack_clock = 2.5
	else:
		enemy.attack_kind = "melee"
		enemy.windup = 0.5
		enemy.attack_clock = 1.8
	if enemy.attack_kind == "rush":
		enemy.rush_start = enemy.pos
		enemy.rush_direction = (enemy.target - enemy.pos).normalized()
		if enemy.rush_direction.length_squared() < 0.01:
			enemy.rush_direction = Vector2(enemy.facing, 0.0)
		enemy.rush_end = constrain(enemy.pos + enemy.rush_direction * (560.0 if enemy.kind == "boss" else 480.0))

func _resolve_enemy_attack(enemy: Fighter) -> void:
	if enemy.hp <= 0.0:
		return
	if enemy.attack_kind == "transition":
		enemy.attack_kind = ""
		enemy.recovery = 0.45
		enemy.attack_clock = 0.45
	elif enemy.attack_kind == "projectile":
		var direction := (enemy.target - enemy.pos).normalized()
		projectiles.append({"pos": enemy.pos, "velocity": direction * (390.0 if enemy.kind == "boss" else 330.0), "life": 4.0, "damage": 24.0 if enemy.kind == "boss" else 15.0, "reason": "守卫瞄准弹" if enemy.kind == "boss" else "射手瞄准弹"})
		enemy.recovery = 0.8
	elif enemy.attack_kind == "rush":
		enemy.rush_left = enemy.rush_duration
		enemy.attack_phase = "rush"
		enemy.velocity = Vector2.ZERO
		return
	elif enemy.attack_kind == "slam":
		var positions: Array[Vector2] = [enemy.target]
		if enemy.phase == 2:
			positions.append(constrain(enemy.target + Vector2(-180.0 * enemy.facing, 0.0)))
		for pos in positions:
			effects.append({"kind": "shock", "pos": pos, "life": 0.35, "max": 0.35, "color": Color("ff8568")})
			if player.pos.distance_to(pos) < 110.0:
				_damage_player(34.0, enemy.pos, "守卫标记地面 · 离开圆形预警", true)
			impact.emit(pos, Color("ff8568"), 0.8)
		enemy.recovery = 1.0
	elif enemy.attack_kind == "cleave":
		var reach := 190.0 if enemy.kind == "boss" else 180.0
		var lane := 63.0 if enemy.kind == "boss" else 54.0
		var relative := player.pos - enemy.pos
		if relative.x * enemy.facing >= -12.0 and relative.x * enemy.facing < reach and absf(relative.y) < lane:
			_damage_player(32.0 if enemy.kind == "boss" else 28.0, enemy.pos, "守卫横扫 · 绕后或跳跃" if enemy.kind == "boss" else "重装重击 · 绕后或躲避", true)
		enemy.recovery = 1.05
	else:
		var relative := player.pos - enemy.pos
		if relative.x * enemy.facing >= -12.0 and relative.x * enemy.facing < 86.0 and absf(relative.y) < 47.0:
			_damage_player(18.0, enemy.pos, "追击者近身攻击 · 观察前摇", true)
		enemy.recovery = 0.55
	enemy.attack_phase = "recovery"

func _update_enemy_rush(enemy: Fighter, delta: float) -> void:
	var previous := enemy.pos
	enemy.rush_left = maxf(0.0, enemy.rush_left - delta)
	var fraction := 1.0 - enemy.rush_left / enemy.rush_duration
	enemy.pos = constrain(enemy.rush_start.lerp(enemy.rush_end, fraction))
	if not enemy.rush_hit and _segment_distance(player.pos, previous, enemy.pos) < 36.0:
		enemy.rush_hit = true
		_damage_player(30.0 if enemy.kind == "boss" else 25.0, previous, "守卫定向冲锋 · 移出预警路线" if enemy.kind == "boss" else "冲锋者直线冲撞 · 撞空后反击", true)
	if enemy.rush_left <= 0.0:
		enemy.attack_phase = "recovery"
		enemy.recovery = 1.0 if enemy.kind == "boss" else 0.9

func _segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	if segment.length_squared() < 0.0001:
		return point.distance_to(start)
	var fraction := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * fraction)

func _update_projectiles(delta: float) -> void:
	for projectile in projectiles:
		var previous: Vector2 = projectile.pos
		projectile.pos += projectile.velocity * delta
		projectile.life -= delta
		# Swept collision makes fast bolts reliable at low and high frame rates.
		if _segment_distance(player.pos, previous, projectile.pos) < 27.0:
			_damage_player(float(projectile.get("damage", 15.0)), previous, str(projectile.get("reason", "射手瞄准弹")), true)
			projectile.life = 0.0
	projectiles = projectiles.filter(func(projectile): return projectile.life > 0.0)

func _update_hazards(delta: float) -> void:
	if stage_id == "corridor" and not enemies.is_empty():
		hazard_clock -= delta
		if hazard_clock <= 0.0:
			var lane_x := [420.0, 730.0, 945.0][hazard_index % 3] as float
			hazards.append({"rect": Rect2(lane_x - 75.0, _bounds().position.y, 150.0, _bounds().size.y), "phase": "telegraph", "life": 0.95, "max": 0.95, "damage": 22.0})
			hazard_index += 1
			hazard_clock = 4.4
	for hazard in hazards:
		hazard.life -= delta
		if hazard.phase == "telegraph" and hazard.life <= 0.0:
			hazard.phase = "active"
			hazard.life = 1.05
			hazard.max = 1.05
		var rect: Rect2 = hazard.rect
		if hazard.phase == "active" and hazard.life > 0.0 and rect.has_point(player.pos):
			_damage_player(float(hazard.damage), rect.get_center(), "回廊地面放电 · 预警后移出条形区域", true)
	hazards = hazards.filter(func(hazard): return hazard.life > 0.0)
	if enemies.is_empty():
		hazards.clear()

func telegraphs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy in enemies:
		if enemy.hp <= 0.0 or (enemy.windup <= 0.0 and enemy.attack_phase != "rush"):
			continue
		if enemy.attack_kind == "slam":
			result.append({"kind": "circle", "pos": enemy.target, "radius": 110.0, "enemy_id": enemy.id, "attack": "slam"})
			if enemy.phase == 2:
				result.append({"kind": "circle", "pos": constrain(enemy.target + Vector2(-180.0 * enemy.facing, 0.0)), "radius": 110.0, "enemy_id": enemy.id, "attack": "slam"})
		elif enemy.attack_kind == "rush":
			result.append({"kind": "line", "start": enemy.rush_start, "end": enemy.rush_end, "width": 72.0, "enemy_id": enemy.id, "attack": "rush"})
		elif enemy.attack_kind == "projectile":
			var direction := (enemy.target - enemy.pos).normalized()
			result.append({"kind": "line", "start": enemy.pos, "end": enemy.pos + direction * 1320.0, "width": 54.0, "enemy_id": enemy.id, "attack": "projectile"})
		elif enemy.attack_kind == "transition":
			result.append({"kind": "transition", "pos": enemy.pos, "radius": 95.0, "enemy_id": enemy.id, "attack": "transition"})
		else:
			var reach := 190.0 if enemy.kind == "boss" else (180.0 if enemy.kind == "heavy" else 86.0)
			var lane := 63.0 if enemy.kind == "boss" else (54.0 if enemy.kind == "heavy" else 47.0)
			var x := enemy.pos.x - reach if enemy.facing < 0.0 else enemy.pos.x - 12.0
			result.append({"kind": "rect", "rect": Rect2(x, enemy.pos.y - lane, reach + 12.0, lane * 2.0), "enemy_id": enemy.id, "attack": enemy.attack_kind})
	return result

func _open_chests(hit: Dictionary) -> void:
	for chest in chests:
		if chest.opened:
			continue
		var difference: Vector2 = chest.pos - hit.pos
		var inside: bool = difference.x * hit.face >= -28.0 and difference.x * hit.face <= hit.reach and absf(difference.y) < hit.lane if hit.shape == "forward" else pow(difference.x / hit.reach, 2) + pow(difference.y / hit.lane, 2) <= 1.0
		if inside:
			_open_chest(chest)

func _open_chest(chest: Dictionary) -> void:
	if chest.opened:
		return
	chest.opened = true
	bonus_coins += 8
	_add_effect("number", chest.pos - Vector2(0, 50), 0.8, Color("ffd68c"), {"text": "宝箱 +8", "heavy": false})
	message.emit("发现宝箱 · 胜利结算额外 8 晶币，失败不入账")

func _spawn_wave() -> void:
	# The saved checkpoint describes the upcoming room, before any object exists.
	# Its seed is independent of RNG consumed in previous rooms.
	if not stage_id.is_empty():
		checkpoint_reached.emit(wave)
		rng.seed = run_seed + wave * 1009
		hazards.clear()
		projectiles.clear()
		pickups.clear()
		hazard_clock = 2.6
		hazard_index = wave
	wave += 1
	var kinds: Array = []
	if stage_id.is_empty():
		for index in range(3 + wave):
			kinds.append("ranged" if index % 3 == 2 else "drone")
		if wave == MAX_WAVES:
			kinds.append("boss")
	else:
		kinds = stage.waves[wave - 1]
	message.emit("第 %d / %d 波 · %s" % [wave, total_waves, "裂隙守卫" if kinds.has("boss") else "清除当前遭遇"])
	for index in range(kinds.size()):
		var enemy := Fighter.new()
		enemy.id = next_id
		next_id += 1
		enemy.kind = str(kinds[index])
		enemy.pos = constrain(Vector2(830 + index * 78, 350 + index % 3 * 48))
		enemy.max_hp = 62.0 + wave * 14.0
		enemy.speed = 88.0 + wave * 11.0
		enemy.tint = Color("ed9b77")
		match enemy.kind:
			"ranged":
				enemy.tint = Color("c499ff")
				enemy.speed = 72.0
			"heavy":
				enemy.max_hp = 150.0
				enemy.speed = 64.0
				enemy.tint = Color("dfc283")
			"charger":
				enemy.max_hp = 112.0
				enemy.speed = 115.0
				enemy.tint = Color("ee9b67")
			"boss":
				enemy.pos = Vector2(1030, 418)
				enemy.max_hp = 580.0 if not stage_id.is_empty() else 650.0
				enemy.speed = 74.0
				enemy.tint = Color("ff6d67")
		enemy.hp = enemy.max_hp
		enemy.attack_clock = rng.randf_range(0.4, 1.5)
		enemy.facing = -1.0
		enemies.append(enemy)

func _end(won: bool) -> void:
	if not running:
		return
	running = false
	pending_hits.clear()
	active_dash.clear()
	dash_targets.clear()
	hazards.clear()
	projectiles.clear()
	pickups.clear()
	retaliation_time = 0.0
	buff_label = ""
	player.velocity = Vector2.ZERO
	for enemy in enemies:
		enemy.windup = 0.0
		enemy.rush_left = 0.0
		enemy.attack_phase = "idle"
	finished.emit(won, kills * 6 + (90 if won else 10))
