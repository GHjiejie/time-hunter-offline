class_name ArenaModel
extends RefCounted

signal impact(position: Vector2, color: Color, strength: float)
signal message(text: String)
signal finished(won: bool, reward: int)

const BOUNDS := Rect2(65, 334, 1150, 145)
const MAX_WAVES := 3
const SKILL_COST := {"dash": 22.0, "burst": 48.0}
const SKILL_COOLDOWN := {"dash": 3.5, "burst": 7.0}
var player: Fighter
var enemies: Array[Fighter] = []
var effects: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var cooldowns := {"dash": 0.0, "burst": 0.0}
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

func start(level: int = 0, random_seed: int = 0) -> void:
	if random_seed == 0:
		rng.randomize()
	else:
		rng.seed = random_seed
	player = Fighter.new()
	player.kind = "player"
	player.pos = Vector2(300, 418)
	player.max_hp = 220.0 + level * 25.0
	player.hp = player.max_hp
	player.speed = 265.0
	player.tint = Color("76eee6")
	enemies.clear()
	effects.clear()
	projectiles.clear()
	pickups.clear()
	cooldowns = {"dash": 0.0, "burst": 0.0}
	energy = 100.0
	wave = 0
	wave_wait = 0.6
	score = 0
	kills = 0
	combo = 0
	combo_window = 0.0
	streak = 0
	streak_window = 0.0
	power = level
	elapsed = 0.0
	running = true
	next_id = 0

func step(delta: float, movement: Vector2, attacking: bool = false) -> void:
	if not running:
		return
	elapsed += delta
	player.tick(delta)
	energy = minf(100.0, energy + delta * 9.0)
	for key in cooldowns:
		cooldowns[key] = maxf(0.0, cooldowns[key] - delta)
	combo_window = maxf(0.0, combo_window - delta)
	streak_window = maxf(0.0, streak_window - delta)
	if combo_window <= 0.0:
		combo = 0
	if streak_window <= 0.0:
		streak = 0
	if player.stun <= 0.0:
		if movement.length() > 1.0:
			movement = movement.normalized()
		player.pos += Vector2(movement.x, movement.y * 0.55) * player.speed * delta
		player.pos = constrain(player.pos)
		if absf(movement.x) > 0.15:
			player.facing = signf(movement.x)
		if attacking:
			attack()
	for enemy in enemies:
		_update_enemy(enemy, delta)
	_update_projectiles(delta)
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
			if wave >= MAX_WAVES:
				_end(true)
			else:
				_spawn_wave()
	else:
		wave_wait = 1.8

func constrain(pos: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, BOUNDS.position.x, BOUNDS.end.x), clampf(pos.y, BOUNDS.position.y, BOUNDS.end.y))

func jump() -> bool:
	if not running or player.height > 0.0 or player.stun > 0.0:
		return false
	player.vertical_speed = 660.0
	player.height = 0.1
	return true

func attack() -> bool:
	if not running or player.attack_clock > 0.0 or player.stun > 0.0:
		return false
	combo = combo % 3 + 1
	combo_window = 0.9
	player.attack_clock = 0.24 if combo < 3 else 0.43
	var reach := 125.0 if combo < 3 else 165.0
	var origin := player.pos + Vector2(player.facing * reach * 0.5, 0.0)
	effects.append({"kind": "slash", "pos": player.pos, "face": player.facing, "life": 0.2, "max": 0.2, "size": reach, "color": Color("76eee6")})
	for enemy in enemies:
		var difference := enemy.pos - player.pos
		if difference.x * player.facing > -28.0 and difference.x * player.facing < reach and absf(difference.y) < 58.0 and absf(enemy.height - player.height) < 140.0:
			_hit_enemy(enemy, (19.0 if combo < 3 else 36.0) + power * 4.0, 28.0 if combo < 3 else 65.0)
	impact.emit(origin - Vector2(0, player.height + 45), Color("76eee6"), 0.12)
	return true

func skill(name: String) -> bool:
	if not running or not SKILL_COST.has(name) or cooldowns[name] > 0.0 or energy < SKILL_COST[name] or player.stun > 0.0:
		return false
	energy -= SKILL_COST[name]
	cooldowns[name] = SKILL_COOLDOWN[name]
	player.invincible = 0.55
	var previous := player.pos
	if name == "dash":
		player.pos = constrain(player.pos + Vector2(player.facing * 270.0, 0.0))
		effects.append({"kind": "dash", "pos": previous, "end": player.pos, "life": 0.4, "max": 0.4, "color": Color("76eee6")})
		for enemy in enemies:
			if enemy.pos.x >= minf(previous.x, player.pos.x) - 55 and enemy.pos.x <= maxf(previous.x, player.pos.x) + 55 and absf(enemy.pos.y - previous.y) < 65:
				_hit_enemy(enemy, 43.0 + power * 6.0, 65.0)
	else:
		effects.append({"kind": "burst", "pos": player.pos, "life": 0.55, "max": 0.55, "color": Color("bfa2ff")})
		for enemy in enemies:
			if enemy.pos.distance_to(player.pos) < 270:
				_hit_enemy(enemy, 80.0 + power * 8.0, 100.0)
		projectiles = projectiles.filter(func(projectile): return projectile.pos.distance_to(player.pos) >= 270)
	impact.emit(player.pos - Vector2(0, 45), Color("bfa2ff"), 1.0)
	return true

func _hit_enemy(enemy: Fighter, damage: float, knockback: float) -> void:
	if enemy.hp <= 0.0:
		return
	enemy.hp = maxf(0.0, enemy.hp - damage)
	enemy.stun = 0.24 if enemy.kind == "boss" else 0.5
	enemy.windup = 0.0
	enemy.pos.x = clampf(enemy.pos.x + player.facing * knockback, BOUNDS.position.x, BOUNDS.end.x)
	if combo == 3:
		enemy.vertical_speed = 420.0
		enemy.height = 0.1
	streak += 1
	streak_window = 2.0
	score += int(damage) * 2
	effects.append({"kind": "number", "pos": enemy.pos - Vector2(0, 105 + enemy.height), "text": str(int(damage)), "life": 0.65, "max": 0.65, "color": Color("fff0c8")})
	impact.emit(enemy.pos - Vector2(0, 55), enemy.tint, 0.45)
	if enemy.hp <= 0.0:
		kills += 1
		score += 150 if enemy.kind != "boss" else 1200
		if rng.randf() < 0.4:
			pickups.append({"pos": enemy.pos, "life": 16.0})

func _damage_player(damage: float) -> void:
	if player.invincible > 0.0 or player.height > 48.0:
		return
	player.hp = maxf(0.0, player.hp - damage)
	player.invincible = 0.7
	player.stun = 0.18
	streak = 0
	impact.emit(player.pos - Vector2(0, 40), Color("ff667e"), 0.8)

func _update_enemy(enemy: Fighter, delta: float) -> void:
	if enemy.hp <= 0.0:
		return
	enemy.tick(delta)
	if enemy.stun > 0.0:
		return
	var difference := player.pos - enemy.pos
	enemy.facing = 1.0 if difference.x >= 0.0 else -1.0
	if enemy.windup > 0.0:
		enemy.windup -= delta
		if enemy.windup <= 0.0:
			_resolve_enemy_attack(enemy)
		return
	var range_x := 440.0 if enemy.kind == "ranged" else (155.0 if enemy.kind == "boss" else 66.0)
	if absf(difference.x) < range_x and absf(difference.y) < 46.0 and enemy.attack_clock <= 0.0:
		enemy.windup = 0.9 if enemy.kind == "boss" else 0.5
		enemy.target = player.pos
		enemy.attack_clock = 2.4 if enemy.kind == "boss" else 1.8
	elif absf(difference.x) > range_x * 0.8 or absf(difference.y) > 25.0:
		var motion := difference.normalized()
		enemy.pos = constrain(enemy.pos + Vector2(motion.x, motion.y * 0.7) * enemy.speed * delta)

func _resolve_enemy_attack(enemy: Fighter) -> void:
	if enemy.kind == "ranged":
		projectiles.append({"pos": enemy.pos, "velocity": (enemy.target - enemy.pos).normalized() * 330.0, "life": 4.0})
	elif enemy.kind == "boss":
		effects.append({"kind": "shock", "pos": enemy.target, "life": 0.35, "max": 0.35, "color": Color("ff8568")})
		if player.pos.distance_to(enemy.target) < 125.0:
			_damage_player(36.0)
		impact.emit(enemy.target, Color("ff8568"), 0.8)
	else:
		if absf(player.pos.x - enemy.pos.x) < 86 and absf(player.pos.y - enemy.pos.y) < 47:
			_damage_player(18.0)

func _update_projectiles(delta: float) -> void:
	for projectile in projectiles:
		projectile.pos += projectile.velocity * delta
		projectile.life -= delta
		if projectile.pos.distance_to(player.pos) < 27.0:
			_damage_player(15.0)
			projectile.life = 0.0
	projectiles = projectiles.filter(func(projectile): return projectile.life > 0.0)

func _spawn_wave() -> void:
	wave += 1
	message.emit("第 %d / %d 波 · %s" % [wave, MAX_WAVES, "裂隙守卫" if wave == MAX_WAVES else "清除入侵者"])
	var count := 3 + wave
	for index in range(count):
		var enemy := Fighter.new()
		enemy.id = next_id
		next_id += 1
		enemy.pos = Vector2(830 + index * 58, 350 + index % 3 * 48)
		enemy.pos = constrain(enemy.pos)
		enemy.kind = "ranged" if index % 3 == 2 else "drone"
		enemy.max_hp = 62.0 + wave * 14.0
		enemy.hp = enemy.max_hp
		enemy.speed = 88.0 + wave * 11.0
		enemy.tint = Color("ed9b77") if enemy.kind == "drone" else Color("c499ff")
		enemy.attack_clock = rng.randf_range(0.4, 1.5)
		enemies.append(enemy)
	if wave == MAX_WAVES:
		var boss := Fighter.new()
		boss.kind = "boss"
		boss.pos = Vector2(1080, 425)
		boss.max_hp = 650.0
		boss.hp = boss.max_hp
		boss.speed = 74.0
		boss.tint = Color("ff6d67")
		boss.id = next_id
		enemies.append(boss)

func _end(won: bool) -> void:
	if not running:
		return
	running = false
	finished.emit(won, kills * 6 + (90 if won else 10))
