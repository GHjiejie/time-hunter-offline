extends Node2D

const FONT_BASE := preload("res://assets/fonts/NotoSansSC.ttf")
const Model := preload("res://scripts/arena_model.gd")
const Store := preload("res://scripts/save_store.gd")
const Hero := preload("res://scripts/hero_renderer.gd")
const VFX := preload("res://scripts/combat_vfx.gd")
const Sounds := preload("res://scripts/combat_audio.gd")
const KEYART := preload("res://assets/characters/renfeng-keyart.png")
const CYAN := Color("76eee6")
const GOLD := Color("ffbd7c")
const WHITE := Color("e9eef7")
const DIM := Color("8794af")
const ATTACK_CENTER := Vector2(1110, 592)
const DASH_CENTER := Vector2(968, 598)
const BURST_CENTER := Vector2(1046, 487)
const JUMP_CENTER := Vector2(1188, 472)
const ULTIMATE_CENTER := Vector2(875, 494)
const STICK_CENTER := Vector2(157, 587)
var model := Model.new()
var store := Store.new()
var mode := "menu"
var time := 0.0
var stick_id := -100
var stick := Vector2.ZERO
var touch_actions: Dictionary = {}
var shake := 0.0
var particles: Array[Dictionary] = []
var toast := ""
var toast_time := 0.0
var won := false
var reward := 0
var sound_players: Array[AudioStreamPlayer] = []
var sound_clock := 0.0
var click_rects: Dictionary = {}
var ui_font := FontVariation.new()
var combat_time := 0.0
var world_offset := Vector2.ZERO
var flash := 0.0
var flash_color := CYAN
var skill_banner := ""
var skill_banner_time := 0.0
var sound_bank: Dictionary = {}
var pending_skill := ""
var pending_skill_time := 0.0

func _ready() -> void:
	ui_font.base_font = FONT_BASE
	ui_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 550.0}
	store.load_progress()
	model.start(store.level, 87)
	model.running = false
	model.impact.connect(_on_impact)
	model.message.connect(_show_message)
	model.finished.connect(_on_finished)
	model.skill_cast.connect(_on_skill_cast)
	for kind in ["hit", "heavy", "dash", "burst", "ultimate"]:
		sound_bank[kind] = Sounds.make_sound(kind)
	for index in range(6):
		var audio := AudioStreamPlayer.new()
		add_child(audio)
		audio.volume_db = -4.0
		sound_players.append(audio)
	get_tree().auto_accept_quit = true

func _process(delta: float) -> void:
	time += delta
	sound_clock = maxf(0.0, sound_clock - delta)
	toast_time = maxf(0.0, toast_time - delta)
	skill_banner_time = maxf(0.0, skill_banner_time - delta)
	flash = maxf(0.0, flash - delta * 5.0)
	shake = move_toward(shake, 0.0, delta * 22.0)
	for particle in particles:
		particle.pos += particle.velocity * delta
		particle.velocity.y += 280.0 * delta
		particle.life -= delta
	particles = particles.filter(func(particle): return particle.life > 0.0)
	if mode == "play":
		if not pending_skill.is_empty():
			pending_skill_time = maxf(0.0, pending_skill_time - delta)
			if pending_skill_time <= 0.0 or (model.player.action_lock > 0.0 and not model.player.pose.begins_with("slash_")):
				pending_skill = ""
				pending_skill_time = 0.0
		var motion := stick
		motion.x += float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		motion.y += float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		if model.hitstop > 0.0:
			model.hitstop = maxf(0.0, model.hitstop - delta)
		else:
			var combat_delta := minf(delta, 0.05)
			combat_time += combat_delta
			var held_attack := Input.is_physical_key_pressed(KEY_J) or touch_actions.values().has("attack")
			model.step(combat_delta, motion.limit_length(), held_attack and pending_skill.is_empty())
			if mode == "play" and not pending_skill.is_empty() and model.player.action_lock <= 0.0:
				var requested_skill := pending_skill
				pending_skill = ""
				pending_skill_time = 0.0
				_use_skill(requested_skill)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if mode == "play":
			_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == "play":
			_pause()
		elif mode == "pause":
			mode = "play"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if mode == "play":
				_pause()
			elif mode == "pause":
				mode = "play"
		elif event.physical_keycode == KEY_ENTER and mode != "play":
			if mode == "pause":
				mode = "play"
			else:
				_start()
		elif mode == "play":
			match event.physical_keycode:
				KEY_SPACE: model.jump()
				KEY_K: _use_skill("dash")
				KEY_L: _use_skill("burst")
				KEY_U: _use_skill("ultimate")
	elif event is InputEventScreenTouch:
		_pointer(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer(-1, event.position, event.pressed)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag(-1, event.position)

func _pointer(id: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		if id == stick_id:
			stick_id = -100
			stick = Vector2.ZERO
		touch_actions.erase(id)
		return
	if Rect2(1140, 28, 48, 44).has_point(pos):
		store.muted = not store.muted
		store.save_progress()
		return
	if mode != "play":
		for action in click_rects:
			if click_rects[action].has_point(pos):
				_menu_action(action)
				return
		return
	if Rect2(1200, 28, 48, 44).has_point(pos):
		_pause()
	elif pos.distance_to(STICK_CENTER) < 104.0 and stick_id == -100:
		stick_id = id
		_drag(id, pos)
	elif pos.distance_to(ATTACK_CENTER) < 67.0:
		touch_actions[id] = "attack"
		model.attack()
	elif pos.distance_to(DASH_CENTER) < 49.0:
		_use_skill("dash")
	elif pos.distance_to(BURST_CENTER) < 46.0:
		_use_skill("burst")
	elif pos.distance_to(JUMP_CENTER) < 44.0:
		model.jump()
	elif pos.distance_to(ULTIMATE_CENTER) < 53.0:
		_use_skill("ultimate")

func _drag(id: int, pos: Vector2) -> void:
	if id == stick_id:
		stick = ((pos - STICK_CENTER) / 65.0).limit_length()
		if stick.length() < 0.12:
			stick = Vector2.ZERO

func _clear_input() -> void:
	stick_id = -100
	stick = Vector2.ZERO
	touch_actions.clear()
	pending_skill = ""
	pending_skill_time = 0.0

func _pause() -> void:
	mode = "pause"
	_clear_input()

func _start() -> void:
	_clear_input()
	particles.clear()
	combat_time = 0.0
	flash = 0.0
	shake = 0.0
	skill_banner_time = 0.0
	model.start(store.level)
	mode = "play"
	_show_message("遗落港 · 闭合裂隙，击败守卫")

func _menu_action(action: String) -> void:
	match action:
		"start": _start()
		"resume": mode = "play"
		"menu":
			mode = "menu"
			model.running = false
			_clear_input()
		"upgrade":
			if store.upgrade():
				_show_message("强化成功 · 生命 +25，技能伤害提升")
			elif store.level >= Store.MAX_LEVEL:
				_show_message("已达到最高强化等级")
			else:
				_show_message("晶币不足 · 战斗后可获得晶币")

func _use_skill(name: String) -> void:
	if mode != "play" or not pending_skill.is_empty():
		return
	if model.player.action_lock > 0.0 and model.player.pose.begins_with("slash_"):
		if Model.SKILL_COST.has(name) and model.cooldowns.get(name, 0.0) <= 0.0 and model.energy >= Model.SKILL_COST[name]:
			pending_skill = name
			pending_skill_time = 0.8
		return
	if not model.skill(name):
		if model.player.action_lock > 0.0 or model.player.stun > 0.0:
			return
		_show_message("技能冷却中" if model.cooldowns.get(name, 0.0) > 0.0 else "能量不足")

func _on_skill_cast(name: String) -> void:
	skill_banner = {"dash": "瞬斩 · 折光穿袭", "burst": "裂隙 · 三重连斩", "ultimate": "终式 · 断界"}.get(name, name)
	skill_banner_time = 1.5 if name == "ultimate" else 0.9
	_play_sound(name)
	if name == "ultimate":
		flash = 0.14
		flash_color = GOLD

func _show_message(text: String) -> void:
	toast = text
	toast_time = 2.6

func _on_finished(victory: bool, coins: int) -> void:
	won = victory
	reward = coins
	mode = "result"
	_clear_input()
	store.record(victory, coins, model.score)
	if store.last_error != OK:
		_show_message("存档失败，进度暂存在内存中")

func _on_impact(pos: Vector2, color: Color, strength: float) -> void:
	shake = maxf(shake, minf(12.0, strength * 11.0))
	if strength >= 0.7:
		flash = maxf(flash, 0.16 if strength < 1.0 else 0.28)
		flash_color = color
	for index in range(int(strength * 23) + 4):
		if particles.size() < 400:
			particles.append({"pos": pos, "velocity": Vector2.from_angle(randf() * TAU) * randf_range(110, 430), "life": randf_range(0.14, 0.38), "color": color})
	if sound_clock <= 0.0 and not store.muted:
		_play_sound("heavy" if strength >= 0.7 else "hit")
		sound_clock = 0.045

func _play_sound(kind: String) -> void:
	if store.muted or not sound_bank.has(kind):
		return
	for audio in sound_players:
		if audio.playing:
			continue
		audio.stream = sound_bank[kind]
		audio.play()
		break

func _draw() -> void:
	click_rects.clear()
	_draw_world()
	if mode == "play":
		_draw_skill_presentation()
	if mode == "play" or mode == "pause" or mode == "result":
		_draw_hud()
	if mode == "play":
		_draw_controls()
	elif mode == "menu":
		_draw_menu()
	elif mode == "pause":
		_draw_panel("战斗暂停", "休息一下，裂隙会等你。")
		_button("resume", Rect2(470, 337, 340, 62), "继续战斗", true)
		_button("menu", Rect2(470, 415, 340, 58), "返回基地")
	elif mode == "result":
		_draw_panel("裂隙已关闭" if won else "暂时撤退", "继续强化，再次出击。" if not won else "遗落港恢复了平静。")
		_text("%d 分   /   %d 击破   /   +%d 晶币" % [model.score, model.kills, reward], Vector2(640, 318), 23, GOLD, true)
		_button("start", Rect2(470, 356, 340, 62), "再次出击", true)
		_button("menu", Rect2(470, 434, 340, 58), "返回基地 · 强化装备")
	_draw_top_buttons()
	if toast_time > 0.0:
		_box(Rect2(320, 120, 640, 44), Color(0.035, 0.055, 0.1, 0.94), Color(0.46, 0.94, 0.9, 0.25))
		_text(toast, Vector2(640, 150), 21, WHITE, true)

func _draw_world() -> void:
	world_offset = Vector2(sin(time * 97.0), cos(time * 83.0)) * shake
	draw_set_transform(world_offset)
	var gradient := 36
	for index in range(gradient):
		var value := float(index) / gradient
		draw_rect(Rect2(0, index * 20, 1280, 21), Color(0.035 + value * 0.035, 0.045 + value * 0.035, 0.11 + value * 0.035))
	draw_circle(Vector2(935, 125), 100, Color(0.24, 0.27, 0.42, 0.28))
	draw_arc(Vector2(935, 125), 125, 0.0, TAU, 64, Color(0.4, 0.6, 0.67, 0.14), 2.0, true)
	for index in range(32):
		var point := Vector2(fmod(index * 113.0 + 35.0, 1280), fmod(index * 73.0, 270))
		draw_circle(point, 1.3, Color(0.5, 0.72, 0.82, 0.25 + sin(time + index) * 0.15))
	for index in range(18):
		var x := index * 82.0 - 25
		var roof := 173.0 + fmod(index * 37.0, 130)
		draw_rect(Rect2(x, roof, 62, 190), Color("111b2e"))
		for floor_index in range(6):
			draw_line(Vector2(x + 12, roof + 15 + floor_index * 23), Vector2(x + 45, roof + 15 + floor_index * 23), Color(0.27, 0.68, 0.7, 0.13), 3)
	# Platform columns and industrial detail.
	for x in [45, 420, 890, 1220]:
		draw_rect(Rect2(x, 205, 15, 155), Color("23314b"))
		draw_rect(Rect2(x + 3, 218, 3, 110), Color(0.46, 0.94, 0.9, 0.38))
	draw_line(Vector2(0, 320), Vector2(1280, 320), Color("26364b"), 20)
	draw_line(Vector2(0, 321), Vector2(1280, 321), Color(0.46, 0.94, 0.9, 0.33), 2)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 328), Vector2(1280, 328), Vector2(1280, 518), Vector2(0, 518)]), Color("172335"))
	for y in [340, 373, 418, 475, 518]:
		draw_line(Vector2(0, y), Vector2(1280, y), Color("2b3b50"), 1)
	for index in range(17):
		var x := index * 100.0 - 160
		draw_line(Vector2(640 + (x - 640) * 0.65, 328), Vector2(x, 518), Color("29394b"), 1)
	draw_rect(Rect2(0, 518, 1280, 15), Color("374259"))
	for index in range(22):
		draw_line(Vector2(index * 66, 521), Vector2(index * 66 + 24, 530), Color("e0a16a"), 3)
	draw_rect(Rect2(0, 533, 1280, 187), Color(0.02, 0.025, 0.055, 0.74))
	_text("SECTOR 07   /   RIFT TERMINAL", Vector2(38, 302), 13, Color(0.46, 0.94, 0.9, 0.45))
	# Animated rift behind the boss spawn.
	for radius in [36, 56, 78]:
		draw_arc(Vector2(1100, 279), radius, time * 0.3 + radius, time * 0.3 + radius + PI * 1.6, 42, Color(0.62, 0.42, 0.94, 0.4), 3, true)
	if mode == "menu":
		draw_set_transform(Vector2.ZERO)
		return
	if mode == "play" and model.player.pose == "ultimate":
		draw_rect(Rect2(0, 0, 1280, 533), Color(0.01, 0.015, 0.04, 0.22))
	for enemy in model.enemies:
		if enemy.kind == "boss" and enemy.windup > 0.0:
			draw_circle(enemy.target, 125, Color(1, 0.25, 0.2, 0.12 + sin(time * 15) * 0.05))
			draw_arc(enemy.target, 125, 0, TAU, 64, Color("ff796e"), 3, true)
			_text("!", enemy.target + Vector2(0, 10), 30, GOLD, true)
	for drop in model.pickups:
		draw_circle(drop.pos - Vector2(0, 16 + sin(time * 4) * 4), 14, Color(0.4, 1, 0.7, 0.2))
		draw_line(drop.pos - Vector2(7, 16), drop.pos + Vector2(7, -16), CYAN, 4)
		draw_line(drop.pos - Vector2(0, 23), drop.pos - Vector2(0, 9), CYAN, 4)
	var fighters: Array[Fighter] = []
	for effect in model.effects:
		if effect.kind == "dash":
			var trail_start: Vector2 = effect.pos
			var trail_end: Vector2 = model.player.pos if model.player.pose == "dash" else effect.end
			for index in range(1, 5):
				Hero.draw_ghost(self, trail_start.lerp(trail_end, float(index) / 5.0), effect.face, combat_time,
					float(effect.life) / float(effect.max) * 0.12, {"base_offset": world_offset, "height": effect.get("height", 0.0)})
	fighters.append_array(model.enemies)
	fighters.append(model.player)
	fighters.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for fighter in fighters:
		_draw_fighter(fighter)
	for projectile in model.projectiles:
		draw_circle(projectile.pos - Vector2(0, 44), 8, Color("d6a0ff"))
		draw_line(projectile.pos - Vector2(0, 44), projectile.pos - projectile.velocity.normalized() * 22 - Vector2(0, 44), Color("895cb7"), 5)
	for effect in model.effects:
		_draw_effect(effect)
	for particle in particles:
		var color: Color = particle.color
		color.a = minf(1.0, particle.life * 4)
		draw_line(particle.pos, particle.pos - particle.velocity.normalized() * 8.0, color, 1.8, true)
		draw_circle(particle.pos, 1.2, Color(1, 1, 0.9, color.a))
	draw_set_transform(Vector2.ZERO)
	if flash > 0.0 and mode == "play":
		draw_rect(Rect2(0, 115, 1280, 418), Color(flash_color.r, flash_color.g, flash_color.b, flash * 0.45))

func _draw_fighter(fighter: Fighter) -> void:
	if fighter.hp <= 0.0:
		return
	if fighter.kind == "player":
		Hero.draw_hero(self, fighter, combat_time, {"base_offset": world_offset})
		return
	var scale_factor := 1.55 if fighter.kind == "boss" else 1.0
	var pos := fighter.pos - Vector2(0, fighter.height)
	var color := fighter.tint
	var hit_flash := 0.0
	if fighter.stun > 0.35:
		hit_flash = 0.7
		color = color.lerp(Color.WHITE, hit_flash)
	draw_set_transform(fighter.pos + world_offset, 0, Vector2(scale_factor, 0.33))
	draw_circle(Vector2.ZERO, 32, Color(0, 0, 0, 0.35))
	draw_set_transform(pos + world_offset, -0.06 * fighter.facing if fighter.stun > 0.0 else 0.0, Vector2(fighter.facing * scale_factor, scale_factor))
	var walking := sin(combat_time * 5 + fighter.id) * 5
	var armor := Color("394057").lerp(Color.WHITE, hit_flash)
	draw_line(Vector2(-12, -24), Vector2(-22 + walking, -1), armor, 13)
	draw_line(Vector2(10, -24), Vector2(21 - walking, -1), armor, 13)
	draw_rect(Rect2(-24, -68, 48, 43), armor)
	draw_rect(Rect2(-17, -61, 34, 16), color)
	draw_circle(Vector2(0, -88), 20, armor)
	draw_line(Vector2(-13, -87), Vector2(13, -87), color, 5)
	draw_line(Vector2(-27, -62), Vector2(-35, -30), armor.lightened(0.12), 13)
	draw_line(Vector2(27, -62), Vector2(35, -32), armor.lightened(0.12), 13)
	if fighter.kind == "ranged":
		draw_rect(Rect2(25, -57, 42, 15), color)
		draw_rect(Rect2(51, -60, 18, 22), Color("463458").lerp(Color.WHITE, hit_flash))
	if fighter.kind == "boss":
		draw_colored_polygon(PackedVector2Array([Vector2(-18, -103), Vector2(-28, -123), Vector2(-5, -106)]), color)
		draw_colored_polygon(PackedVector2Array([Vector2(18, -103), Vector2(28, -123), Vector2(5, -106)]), color)
	if fighter.windup > 0.0:
		draw_circle(Vector2(0, -125), 13, GOLD)
		draw_line(Vector2(0, -132), Vector2(0, -124), Color("282335"), 3)
		draw_circle(Vector2(0, -118), 1.5, Color("282335"))
	draw_set_transform(world_offset)
	if fighter.kind != "boss":
		var origin := pos - Vector2(28, 145)
		draw_rect(Rect2(origin, Vector2(56, 4)), Color("302e45"))
		draw_rect(Rect2(origin, Vector2(56 * fighter.hp / fighter.max_hp, 4)), color)

func _draw_effect(effect: Dictionary) -> void:
	if effect.kind == "number":
		var ratio := clampf(float(effect.life) / float(effect.max), 0.0, 1.0)
		var color: Color = effect.color
		color.a = ratio
		var heavy: bool = effect.get("heavy", false)
		var progress := 1.0 - ratio
		var size := int((31.0 if heavy else 23.0) * (1.0 + 0.24 * sin(progress * PI)))
		var pos: Vector2 = effect.pos - Vector2(0, progress * 56)
		for outline in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
			_text(effect.text, pos + outline, size, Color(0.02, 0.04, 0.06, ratio), true)
		_text(effect.text, pos, size, color, true)
	else:
		VFX.draw_effect(self, effect, combat_time, world_offset)

func _draw_skill_presentation() -> void:
	if skill_banner_time > 0.0:
		var color := GOLD if model.player.pose == "ultimate" else CYAN
		color.a = minf(1.0, skill_banner_time * 3.0)
		_text(skill_banner, Vector2(46, 200), 25, color)
		draw_line(Vector2(46, 215), Vector2(290, 215), Color(color.r, color.g, color.b, color.a * 0.45), 2)
	if model.player.pose == "ultimate" and model.player.pose_time < 0.44:
		var alpha := sin(clampf(model.player.pose_time / 0.44, 0.0, 1.0) * PI)
		draw_colored_polygon(PackedVector2Array([Vector2(0, 229), Vector2(550, 229), Vector2(490, 345), Vector2(0, 345)]), Color(0.025, 0.045, 0.085, alpha * 0.95))
		draw_texture_rect_region(KEYART, Rect2(28, 190, 174, 198), Rect2(260, 0, 570, 650), Color(1, 1, 1, alpha))
		_text("终式 · 断界", Vector2(220, 283), 34, Color(1, 0.84, 0.58, alpha))
		_text("折光刃  /  空间切割", Vector2(224, 312), 16, Color(0.73, 0.94, 1, alpha))

func _draw_hud() -> void:
	_box(Rect2(28, 26, 350, 85), Color(0.035, 0.055, 0.1, 0.88), Color("2b4458"))
	draw_texture_rect_region(KEYART, Rect2(37, 31, 69, 75), Rect2(295, 0, 470, 510))
	_text("刃锋", Vector2(116, 56), 23, WHITE)
	_text("LV.%02d" % (store.level + 1), Vector2(316, 53), 15, CYAN)
	_meter(Rect2(116, 65, 240, 10), model.player.hp / model.player.max_hp, Color("ef8794"))
	_meter(Rect2(116, 83, 240, 6), model.energy / 100.0, CYAN)
	_text("%d / %d    EN %d" % [model.player.hp, model.player.max_hp, model.energy], Vector2(355, 104), 12, DIM, false, true)
	_text("遗落港 / %02d" % maxi(1, model.wave), Vector2(640, 55), 23, WHITE, true)
	_text("%06d  分" % model.score, Vector2(640, 83), 16, DIM, true)
	if model.streak > 1:
		_text(str(model.streak), Vector2(868, 176), 49, GOLD, true)
		_text("连击", Vector2(868, 202), 18, WHITE, true)
	for enemy in model.enemies:
		if enemy.kind == "boss":
			_text("裂隙守卫", Vector2(640, 191), 18, Color("f4a0a2"), true)
			_meter(Rect2(425, 204, 430, 8), enemy.hp / enemy.max_hp, Color("ed7683"))

func _draw_controls() -> void:
	draw_circle(STICK_CENTER, 82, Color(0.05, 0.1, 0.17, 0.7))
	draw_arc(STICK_CENTER, 82, 0, TAU, 64, Color(0.6, 0.75, 0.85, 0.2), 2, true)
	draw_arc(STICK_CENTER, 49, 0, TAU, 48, Color(0.6, 0.75, 0.85, 0.12), 1, true)
	for angle in range(4):
		var direction := Vector2.from_angle(angle * PI / 2)
		draw_line(STICK_CENTER + direction * 63, STICK_CENTER + direction * 71, Color(0.7, 0.84, 0.9, 0.4), 3)
	draw_circle(STICK_CENTER + stick * 47, 30, Color(0.35, 0.57, 0.65, 0.55))
	draw_arc(STICK_CENTER + stick * 47, 30, 0, TAU, 40, CYAN, 1.5, true)
	_round_button(ATTACK_CENTER, 62, "攻击", "J · 连招", CYAN, 0.0, true)
	_round_button(DASH_CENTER, 45, "瞬斩", "K · 22能量", CYAN, model.cooldowns.dash, model.energy >= 22)
	_round_button(BURST_CENTER, 43, "裂隙", "L · 48能量", Color("bfa2ff"), model.cooldowns.burst, model.energy >= 48)
	_round_button(JUMP_CENTER, 41, "跳跃", "SPACE", GOLD, 0, true)
	_round_button(ULTIMATE_CENTER, 48, "断界", "U · 75能量", GOLD, model.cooldowns.ultimate, model.energy >= 75)
	if model.cooldowns.ultimate <= 0.0 and model.energy >= 75:
		draw_arc(ULTIMATE_CENTER, 55, time * 1.6, time * 1.6 + PI * 1.4, 48, Color(1, 0.76, 0.47, 0.6), 2, true)
	_text("移动 WASD / 方向键   ·   J 连招   K 瞬斩   L 裂隙   U 断界", Vector2(548, 682), 15, DIM, true)

func _round_button(center: Vector2, radius: float, label: String, hint: String, color: Color, cooldown: float, available: bool) -> void:
	draw_circle(center, radius + 5, Color(color.r, color.g, color.b, 0.06))
	draw_circle(center, radius, Color(0.045, 0.08, 0.13, 0.92))
	draw_arc(center, radius, 0, TAU, 64, Color(color.r, color.g, color.b, 0.75 if available else 0.25), 2, true)
	_text("%.1f" % cooldown if cooldown > 0.0 else label, center + Vector2(0, 8), 23 if radius > 50 else 21, color if available else DIM, true)
	_text(hint, center + Vector2(0, radius + 22), 12, DIM, true)

func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.03, 0.07, 0.55))
	for radius in [135, 170, 205]:
		draw_arc(Vector2(615, 330), radius, time * 0.15 + radius, time * 0.15 + radius + PI * 1.6, 60, Color(0.3, 0.9, 0.95, 0.15), 2, true)
	draw_texture_rect(KEYART, Rect2(387, 59, 410, 615), false)
	_text("R I F T   H U N T E R", Vector2(64, 176), 16, CYAN)
	_text("裂隙猎人", Vector2(59, 266), 67, WHITE)
	_text("刃锋  /  折光剑士", Vector2(65, 313), 23, CYAN)
	draw_line(Vector2(65, 340), Vector2(123, 340), CYAN, 3)
	_text("遗落港的最后一道防线", Vector2(65, 379), 21, Color("b4c3d7"))
	_text("瞬斩穿袭 · 裂隙连斩", Vector2(65, 422), 19, DIM)
	_text("终式 · 断界", Vector2(65, 455), 25, GOLD)
	_text("横版格斗  /  离线单机", Vector2(65, 509), 17, DIM)
	_box(Rect2(798, 173, 410, 381), Color(0.025, 0.045, 0.085, 0.94), Color("2c4357"))
	_text("出击准备", Vector2(829, 220), 26, WHITE)
	_text("刃锋 · 强化等级 %d" % store.level, Vector2(829, 266), 20, CYAN)
	_button("start", Rect2(829, 299, 348, 66), "进入遗落港", true)
	var upgrade_label := "强化已满级" if store.level >= Store.MAX_LEVEL else "强化装备 · %d 晶币" % store.upgrade_cost()
	_button("upgrade", Rect2(829, 382, 348, 58), upgrade_label)
	_text("晶币  %d     最高分  %d" % [store.coins, store.best_score], Vector2(829, 482), 18, GOLD)
	_text("通关 %d 次 · 进度保存在本机" % store.clears, Vector2(829, 515), 15, DIM)
	_text("v0.2.0   /   刃锋 · 断界", Vector2(65, 660), 14, DIM)
	_text("耳机推荐  ·  横屏游玩", Vector2(1178, 660), 14, DIM, false, true)

func _draw_panel(title: String, subtitle: String) -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.025, 0.055, 0.8))
	_box(Rect2(392, 176, 496, 370), Color("0d1728"), Color("2d465e"))
	_text(title, Vector2(640, 246), 39, CYAN if won or mode == "pause" else GOLD, true)
	_text(subtitle, Vector2(640, 283), 18, DIM, true)

func _draw_top_buttons() -> void:
	_box(Rect2(1140, 28, 48, 44), Color("142336"), Color("33465b"))
	_text("静" if store.muted else "音", Vector2(1164, 57), 20, DIM, true)
	if mode == "play":
		_box(Rect2(1200, 28, 48, 44), Color("142336"), Color("33465b"))
		draw_line(Vector2(1218, 40), Vector2(1218, 60), WHITE, 4)
		draw_line(Vector2(1230, 40), Vector2(1230, 60), WHITE, 4)

func _button(action: String, rect: Rect2, label: String, primary: bool = false) -> void:
	click_rects[action] = rect
	_box(rect, CYAN if primary else Color("17293b"), CYAN if primary else Color("3b5366"))
	_text(label, rect.get_center() + Vector2(0, 9), 23 if primary else 20, Color("11252e") if primary else WHITE, true)

func _box(rect: Rect2, fill: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	draw_style_box(style, rect)

func _meter(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect, Color("28364c"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color)

func _text(value: String, pos: Vector2, size: int = 20, color: Color = WHITE, centered: bool = false, right: bool = false) -> void:
	var width := ui_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := pos
	if centered:
		origin.x -= width * 0.5
	elif right:
		origin.x -= width
	draw_string(ui_font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
