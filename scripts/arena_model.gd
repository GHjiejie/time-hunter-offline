class_name ArenaModel
extends RefCounted

signal impact(position: Vector2, color: Color, strength: float)
signal message(text: String)
signal finished(won: bool, reward: int)
signal skill_cast(name: String)
## Presentation events follow the same timeline as damage, including a whiff.
signal skill_released(name: String, stage: int)

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
	cooldowns = {"dash": 0.0, "burst": 0.0, "ultimate": 0.0}
	pending_hits.clear()
	active_dash.clear()
	dash_targets.clear()
	hitstop = 0.0
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
	player.pos = constrain(player.pos)
	energy = minf(100.0, energy + delta * 9.0)
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
	player.attack_clock = duration
	player.set_pose("slash_%d" % combo, duration)
	player.moving = 0.0
	_queue_hit("slash", [0.055, 0.075, 0.13][combo - 1], combo,
		(22.0 if combo < 3 else 42.0) + power * 4.0,
		145.0 if combo < 3 else 200.0, 58.0,
		310.0 if combo < 3 else 580.0, 460.0 if combo == 3 else 0.0,
		Color("76eee6"), "forward")
	return true

func skill(name: String) -> bool:
	if not _can_act() or not SKILL_COST.has(name) or cooldowns[name] > 0.0 or energy < SKILL_COST[name]:
		return false
	energy -= SKILL_COST[name]
	cooldowns[name] = SKILL_COOLDOWN[name]
	player.moving = 0.0
	player.velocity = Vector2.ZERO
	combo = 0
	combo_window = 0.0
	if name == "dash":
		player.set_pose("dash", 0.30)
		player.invincible = 0.44
		active_dash = {"start": player.pos, "end": constrain(player.pos + Vector2(player.facing * 285.0, 0.0)), "elapsed": 0.0, "duration": 0.30, "face": player.facing, "height": player.height}
		dash_targets.clear()
		_add_effect("dash", player.pos, 0.42, Color("76eee6"), {"end": active_dash.end, "size": 140.0, "duration": 0.30})
	elif name == "burst":
		player.set_pose("burst", 0.92)
		player.invincible = 0.94
		_add_effect("rift_charge", player.pos, 0.16, Color("bfa2ff"), {"size": 245.0})
		_queue_hit("rift", 0.16, 1, 24.0 + power * 2.0, 250.0, 85.0, 130.0, 360.0, Color("91cfff"))
		_queue_hit("rift", 0.38, 2, 27.0 + power * 2.0, 270.0, 90.0, 170.0, 340.0, Color("bfa2ff"))
		_queue_hit("rift", 0.68, 3, 48.0 + power * 4.0, 290.0, 95.0, 640.0, 560.0, Color("dcbdff"))
	else:
		player.set_pose("ultimate", 1.62)
		player.invincible = 1.7
		_add_effect("ultimate_charge", player.pos, 0.44, Color("ffcc87"), {"size": 470.0})
		_queue_hit("ultimate", 0.44, 1, 28.0 + power * 2.0, 470.0, 135.0, 30.0, 0.0, Color("93e7ff"))
		_queue_hit("ultimate", 0.66, 2, 28.0 + power * 2.0, 470.0, 135.0, 40.0, 0.0, Color("cdb8ff"))
		_queue_hit("ultimate", 0.90, 3, 32.0 + power * 2.0, 470.0, 135.0, 60.0, 0.0, Color("94eeff"))
		_queue_hit("ultimate", 1.28, 4, 125.0 + power * 8.0, 485.0, 140.0, 780.0, 650.0, Color("ffda91"))
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
			_hit_enemy(enemy, hit.damage, hit.knockback, hit.launch, direction, hit.color, 0.9 if heavy else 0.42, 0.075 if heavy else 0.028)
	if hit.kind == "rift" or hit.kind == "ultimate":
		projectiles = projectiles.filter(func(projectile): return pow((projectile.pos.x - hit.pos.x) / hit.reach, 2) + pow((projectile.pos.y - hit.pos.y) / hit.lane, 2) > 1.0)
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
			_hit_enemy(enemy, 46.0 + power * 6.0, 450.0, 130.0, active_dash.face, Color("8decff"), 0.65, 0.04)
	if progress >= 1.0:
		_add_effect("slash", player.pos, 0.20, Color("a6f5ff"), {"stage": 2, "size": 130.0})
		active_dash.clear()

func _hit_enemy(enemy: Fighter, damage: float, knockback: float, launch: float = 0.0, direction: float = 0.0, color: Color = Color("fff0c8"), strength: float = 0.45, stop: float = 0.03) -> void:
	if enemy.hp <= 0.0:
		return
	var dealt := minf(enemy.hp, damage)
	enemy.hp = maxf(0.0, enemy.hp - damage)
	enemy.stun = maxf(enemy.stun, 0.27 if enemy.kind == "boss" else 0.52)
	enemy.windup = 0.0
	if is_zero_approx(direction):
		direction = player.facing
	enemy.velocity.x = direction * knockback * (0.35 if enemy.kind == "boss" else 1.0)
	if launch > 0.0 and enemy.kind != "boss":
		enemy.vertical_speed = launch
		enemy.height = maxf(enemy.height, 0.1)
	if enemy.kind != "boss":
		enemy.set_pose("hurt", 0.3)
	streak += 1
	streak_window = 2.0
	score += int(dealt) * 2
	_add_effect("number", enemy.pos - Vector2(0, 105 + enemy.height), 0.65, color, {"text": str(int(dealt)), "heavy": strength > 0.7})
	_add_effect("hit", enemy.pos - Vector2(0, 55 + enemy.height), 0.20, color, {"size": 68.0 if strength > 0.7 else 38.0, "strength": strength, "face": direction, "direction": Vector2(direction, -0.16).normalized()})
	hitstop = maxf(hitstop, stop)
	impact.emit(enemy.pos - Vector2(0, 55 + enemy.height), color, strength)
	if enemy.hp <= 0.0:
		kills += 1
		score += 150 if enemy.kind != "boss" else 1200
		if rng.randf() < 0.4:
			pickups.append({"pos": enemy.pos, "life": 16.0})

func _damage_player(damage: float, from: Vector2 = Vector2.ZERO) -> void:
	if player.invincible > 0.0 or player.height > 48.0:
		return
	player.hp = maxf(0.0, player.hp - damage)
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
	if enemy.stun > 0.0 or enemy.height > 5.0:
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
			_damage_player(36.0, enemy.pos)
		impact.emit(enemy.target, Color("ff8568"), 0.8)
	else:
		if absf(player.pos.x - enemy.pos.x) < 86 and absf(player.pos.y - enemy.pos.y) < 47:
			_damage_player(18.0, enemy.pos)

func _update_projectiles(delta: float) -> void:
	for projectile in projectiles:
		projectile.pos += projectile.velocity * delta
		projectile.life -= delta
		if projectile.pos.distance_to(player.pos) < 27.0:
			_damage_player(15.0, projectile.pos)
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
	pending_hits.clear()
	active_dash.clear()
	finished.emit(won, kills * 6 + (90 if won else 10))
