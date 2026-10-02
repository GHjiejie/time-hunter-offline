extends Node2D

const FONT_BASE := preload("res://assets/fonts/NotoSansSC.ttf")
const Model := preload("res://scripts/arena_model.gd")
const Store := preload("res://scripts/save_store.gd")
const Hero := preload("res://scripts/hero_renderer.gd")
const VFX := preload("res://scripts/combat_vfx.gd")
const Sounds := preload("res://scripts/combat_audio.gd")
const Campaign := preload("res://scripts/campaign_ui.gd")
const Bindings := preload("res://scripts/input_bindings.gd")
const Content := preload("res://scripts/game_content.gd")
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
var blade_trail: Array[Dictionary] = []
var blade_trail_key := ""
var blade_trail_face := 1.0
var campaign_ui: CanvasLayer
var selected_stage := "outskirts"
var last_run: Dictionary = {}
var settlement: Dictionary = {}
var result_stats: Dictionary = {}
var settlement_pending := false
var practice_mode := false
var page_back := "prepare"
var blocked_keys: Array[int] = []
var pending_checkpoint := -1

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
	model.skill_released.connect(_on_skill_released)
	model.checkpoint_reached.connect(_on_checkpoint)
	for kind in ["hit", "heavy", "slash", "dash", "burst", "ultimate", "charge", "finisher"]:
		sound_bank[kind] = Sounds.make_sound(kind)
	for index in range(6):
		var audio := AudioStreamPlayer.new()
		add_child(audio)
		audio.volume_db = -4.0
		sound_players.append(audio)
	campaign_ui = Campaign.new()
	add_child(campaign_ui)
	campaign_ui.action_requested.connect(_ui_action)
	_apply_settings()
	_show_page("menu")
	get_tree().auto_accept_quit = true

func _process(delta: float) -> void:
	time += delta
	sound_clock = maxf(0.0, sound_clock - delta)
	toast_time = maxf(0.0, toast_time - delta)
	if mode == "play":
		if not pending_skill.is_empty():
			pending_skill_time = maxf(0.0, pending_skill_time - delta)
			if pending_skill_time <= 0.0 or (model.player.action_lock > 0.0 and not model.player.pose.begins_with("slash_")):
				pending_skill = ""
				pending_skill_time = 0.0
		var motion := stick
		motion.x += float(_key_held("move_right")) - float(_key_held("move_left"))
		motion.y += float(_key_held("move_down")) - float(_key_held("move_up"))
		if model.hitstop > 0.0:
			model.hitstop = maxf(0.0, model.hitstop - delta)
		else:
			var combat_delta := minf(delta, 0.05)
			combat_time += combat_delta
			_advance_feedback(combat_delta)
			var held_attack := _key_held("attack") or touch_actions.values().has("attack")
			model.step(combat_delta, motion.limit_length(), held_attack and pending_skill.is_empty())
			_sample_blade_trail()
			if mode == "play" and not pending_skill.is_empty() and model.player.action_lock <= 0.0:
				var requested_skill := pending_skill
				pending_skill = ""
				pending_skill_time = 0.0
				_use_skill(requested_skill)
	queue_redraw()

func _advance_feedback(delta: float) -> void:
	skill_banner_time = maxf(0.0, skill_banner_time - delta)
	flash = maxf(0.0, flash - delta * 1.5)
	shake = move_toward(shake, 0.0, delta * 30.0)
	for particle in particles:
		particle.pos += particle.velocity * delta
		particle.velocity.y += 180.0 * delta
		particle.life -= delta
	particles = particles.filter(func(particle): return particle.life > 0.0)

func _sample_blade_trail() -> void:
	var fighter: Fighter = model.player
	var anchors := Hero.blade_anchors(fighter, combat_time)
	var key := "%s:%d" % [fighter.pose, anchors.frame]
	var attacking := fighter.pose.begins_with("slash_") or fighter.pose in ["burst", "ultimate", "dash"]
	if key != blade_trail_key or fighter.facing != blade_trail_face:
		blade_trail.clear()
	if not blade_trail.is_empty() and blade_trail[-1].root.distance_to(anchors.root) > 90.0:
		blade_trail.clear()
	blade_trail_key = key
	blade_trail_face = fighter.facing
	blade_trail = blade_trail.filter(func(sample): return combat_time - sample.time < 0.10)
	if attacking and fighter.hp > 0.0:
		blade_trail.append({"root": anchors.root, "tip": anchors.tip, "time": combat_time})
		if blade_trail.size() > 8:
			blade_trail.pop_front()
	else:
		blade_trail.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if mode == "play":
			_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == "play":
			_pause()
		elif mode == "pause":
			_ui_action("resume")
		elif is_instance_valid(campaign_ui):
			campaign_ui._back()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if mode != "play" or blocked_keys.has(event.physical_keycode):
			return
		if Bindings.matches(store.settings, "pause", event):
			_pause()
		elif Bindings.matches(store.settings, "jump", event):
			model.jump()
		else:
			for skill_name in ["dash", "burst", "ultimate"]:
				if Bindings.matches(store.settings, skill_name, event):
					_use_skill(skill_name)
	elif event is InputEventScreenTouch:
		_pointer(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_pointer(-1, event.position, event.pressed)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			_drag(-1, event.position)

func _pointer(id: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		if id == stick_id:
			stick_id = -100
			stick = Vector2.ZERO
		touch_actions.erase(id)
		return
	if mode != "play":
		return
	if Rect2(1140, 28, 48, 44).has_point(pos):
		var previous := store.muted
		store.muted = not store.muted
		if store.save_progress() != OK:
			store.muted = previous
			_show_message("音量设置未保存，请稍后重试")
		_apply_settings()
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
	blocked_keys.clear()
	for action in Bindings.DEFAULTS:
		var code: int = Bindings.key_for(store.settings, action)
		if Input.is_physical_key_pressed(code):
			blocked_keys.append(code)
	for code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		if Input.is_physical_key_pressed(code) and not blocked_keys.has(code):
			blocked_keys.append(code)

func _key_held(action: String) -> bool:
	for code in blocked_keys.duplicate():
		if not Input.is_physical_key_pressed(code):
			blocked_keys.erase(code)
	var code: int = Bindings.key_for(store.settings, action)
	if not blocked_keys.has(code) and Input.is_physical_key_pressed(code):
		return true
	var arrows := {"move_left": KEY_LEFT, "move_right": KEY_RIGHT, "move_up": KEY_UP, "move_down": KEY_DOWN}
	return arrows.has(action) and not blocked_keys.has(arrows[action]) and Input.is_physical_key_pressed(arrows[action])

func _pause() -> void:
	_clear_input()
	_show_page("pause")

func _start(stage_id: String = "", checkpoint: int = -1, resume_existing: bool = false) -> void:
	if stage_id.is_empty():
		stage_id = selected_stage
	if not store.unlocked_stages.has(stage_id):
		_show_message("先完成上一关，才能进入这里")
		return
	selected_stage = stage_id
	pending_checkpoint = -1
	practice_mode = false
	settlement_pending = false
	settlement.clear()
	result_stats.clear()
	var run_seed := int(Time.get_ticks_msec() % 2147483647) + 1
	if resume_existing and not store.active_run.is_empty():
		run_seed = int(store.active_run.seed)
		checkpoint = int(store.active_run.wave)
	elif checkpoint >= 0 and not last_run.is_empty():
		run_seed = int(last_run.seed)
	else:
		checkpoint = 0
	if not resume_existing and not store.begin_run(stage_id, run_seed):
		_show_message("无法保存出战记录，请检查存档后再出发")
		_show_page("prepare")
		return
	if checkpoint > 0 and not store.update_checkpoint(checkpoint):
		_show_message("无法保存续玩断点，请重试")
		_show_page("prepare")
		return
	_reset_presentation()
	model.start(store.level, run_seed, stage_id, store.combat_config(), maxi(0, checkpoint))
	mode = "play"
	campaign_ui.hide_ui()
	_show_message(Content.stage(stage_id).hint)

func _show_page(page: String) -> void:
	_clear_input()
	mode = page
	var context := {"stage_id": selected_stage, "result": settlement, "stats": result_stats,
		"has_checkpoint": not last_run.is_empty() or not store.active_run.is_empty(),
		"back_page": page_back, "source_page": page_back, "practice": practice_mode,
		"message": toast if toast_time > 0.0 else ""}
	if not str(result_stats.get("last_damage_reason", "")).is_empty():
		context.reason = "最后受击：" + str(result_stats.last_damage_reason) + "。先移出预警范围，再利用收招破绽。"
	campaign_ui.show_page(page, store, context)

func _resume() -> void:
	if not model.running:
		return
	_clear_input()
	mode = "play"
	campaign_ui.hide_ui()

func _on_checkpoint(index: int) -> void:
	if practice_mode:
		return
	if not store.update_checkpoint(index):
		pending_checkpoint = index
		_show_message("断点保存失败，战斗已暂停；重试保存后可继续")
		_pause()

func _practice() -> void:
	practice_mode = true
	_reset_presentation()
	var build := store.combat_config()
	build.skills = ["dash", "burst", "ultimate"]
	model.start(store.level, 87, "outskirts", build)
	model.chests.clear()
	mode = "play"
	campaign_ui.hide_ui()
	_show_message("训练场 · 全技能试用，不发放奖励，不改变出战断点")

func _ui_action(action: String, payload: Dictionary = {}) -> void:
	if settlement_pending and mode == "result" and action != "retry_settlement":
		_show_message("本次结算尚未保存，请先重试保存")
		_show_page("result")
		return
	var successful := true
	match action:
		"begin", "new_game":
			if store.new_game():
				selected_stage = "outskirts"
				last_run.clear()
				practice_mode = false
				model.running = false
				_apply_settings()
				_show_page("prepare")
			else:
				_show_message("新游戏未保存，原有进度已保留")
				_show_page("menu")
		"continue":
			if not store.active_run.is_empty():
				_start(str(store.active_run.stage), -1, true)
			else:
				_show_page("prepare")
		"page":
			var target := str(payload.get("page", "prepare"))
			if target in ["settings", "help", "inventory", "stages"] and mode not in ["settings", "help", "inventory", "stages"]:
				page_back = mode
			_show_page(target)
		"start_stage": _start(str(payload.get("stage", selected_stage)))
		"resume":
			var checkpoint := pending_checkpoint if pending_checkpoint >= 0 else int(store.active_run.get("wave", 0))
			if not practice_mode and not store.active_run.is_empty() and not store.update_checkpoint(checkpoint):
				_show_message("断点仍未保存，暂停已保留，请重试")
				_show_page("pause")
			else:
				pending_checkpoint = -1
				_resume()
		"practice": _practice()
		"retry_checkpoint":
			if not store.active_run.is_empty():
				_start(str(store.active_run.stage), -1, true)
			elif not last_run.is_empty():
				_start(str(last_run.stage), int(last_run.wave))
		"restart_stage":
			if practice_mode:
				_practice()
				return
			if not practice_mode and not store.abandon_run():
				_show_message("无法保存退出记录，战斗仍保留")
				_show_page(mode)
				return
			_start(selected_stage)
		"next_stage":
			var next := str(Content.stage(selected_stage).first_unlock)
			if next.is_empty():
				_show_page("prepare")
			else:
				_start(next)
		"abandon":
			if practice_mode or store.abandon_run():
				model.running = false
				practice_mode = false
				last_run.clear()
				_show_page("prepare")
			else:
				_show_message("退出记录未保存，断点仍保留")
				_show_page(mode)
		"retry_settlement":
			_on_finished(won, 0)
		"equip": successful = store.equip_item(str(payload.get("uid", "")))
		"unequip": successful = store.unequip_item(str(payload.get("slot", "")))
		"lock": successful = store.lock_item(str(payload.get("uid", "")))
		"discard": successful = store.discard_item(str(payload.get("uid", "")))
		"enhance": successful = store.enhance(str(payload.get("slot", "")))
		"passive": successful = store.set_passive(str(payload.get("passive", "assault")))
		"variant": successful = store.set_variant(str(payload.get("skill", "")), str(payload.get("variant", "")))
		"setting", "binding", "reset_bindings":
			var previous := store.settings.duplicate(true)
			var previous_muted := store.muted
			if action == "setting":
				if payload.key == "muted":
					store.muted = bool(payload.value)
				else:
					store.settings[str(payload.key)] = payload.value
			elif action == "binding":
				var result: Dictionary = Bindings.try_rebind(store.settings, str(payload.action), int(payload.code))
				if not result.ok:
					_show_message(result.error)
					_show_page("settings")
					return
			else:
				Bindings.restore_defaults(store.settings)
			successful = store.save_progress() == OK
			if not successful:
				store.settings = previous
				store.muted = previous_muted
			_apply_settings()
			if action == "setting" and successful and payload.get("key", "") != "large_text":
				return # Keep a dragging slider and its keyboard focus alive.
	if action in ["equip", "unequip", "lock", "discard", "enhance", "passive", "variant", "setting", "binding", "reset_bindings"]:
		if not successful:
			_show_message("操作未保存，请检查晶币、装备保护或存档状态")
		_show_page(mode)

func _apply_settings() -> void:
	var volume := float(store.settings.get("master_volume", 1.0)) * float(store.settings.get("sfx_volume", 0.8))
	for audio in sound_players:
		audio.volume_db = linear_to_db(maxf(0.0001, volume)) - 4.0
		if store.muted or volume <= 0.0:
			audio.stop()
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		var desired := DisplayServer.WINDOW_MODE_FULLSCREEN if store.settings.get("fullscreen", false) else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != desired:
			DisplayServer.window_set_mode(desired)

func _reset_presentation() -> void:
	_clear_input()
	toast_time = 0.0
	particles.clear()
	blade_trail.clear()
	blade_trail_key = ""
	combat_time = 0.0
	flash = 0.0
	shake = 0.0
	skill_banner_time = 0.0

func _menu_action(action: String) -> void:
	# Kept for scene-level input regressions; menus use native focused Controls.
	if action == "resume":
		_ui_action("resume")
	elif action == "menu":
		_ui_action("abandon")

func _use_skill(name: String) -> void:
	if mode != "play" or not pending_skill.is_empty():
		return
	if model.player.action_lock > 0.0 and model.player.pose.begins_with("slash_"):
		if model.has_skill(name) and Model.SKILL_COST.has(name) and model.cooldowns.get(name, 0.0) <= 0.0 and model.energy >= Model.SKILL_COST[name]:
			pending_skill = name
			pending_skill_time = 0.8
		return
	if not model.skill(name):
		if model.player.action_lock > 0.0 or model.player.stun > 0.0:
			return
		var label := "首通遗迹外围后解锁断界" if not model.has_skill(name) else ("技能冷却中" if model.cooldowns.get(name, 0.0) > 0.0 else "能量不足")
		_show_message(label)

func _on_skill_cast(name: String) -> void:
	skill_banner = {"dash": "瞬斩 · 折光穿袭", "burst": "裂隙 · 三重连斩", "ultimate": "终式 · 断界"}.get(name, name)
	skill_banner_time = 1.5 if name == "ultimate" else 0.9
	if name in ["burst", "ultimate"]:
		_play_sound("charge")

func _on_skill_released(name: String, stage: int) -> void:
	var final_strike := (name == "burst" and stage == 3) or (name == "ultimate" and stage == 4)
	_play_sound("finisher" if final_strike else name)

func _show_message(text: String) -> void:
	toast = text
	toast_time = 2.6

func _on_finished(victory: bool, coins: int) -> void:
	if mode == "result" and not settlement_pending:
		return
	won = victory
	_clear_input()
	toast_time = 0.0
	model.running = false
	result_stats = model.stats()
	if practice_mode:
		practice_mode = false
		_show_page("prepare")
		return
	if not store.active_run.is_empty():
		last_run = store.active_run.duplicate(true)
	result_stats.run_id = last_run.get("id", "")
	settlement = store.settle_run(victory, result_stats)
	settlement_pending = not settlement.get("ok", false)
	reward = int(settlement.get("coins", 0)) if not settlement_pending else 0
	if settlement_pending:
		_show_message("结算尚未保存：请在结算页重试保存")
	_show_page("result")

func _on_impact(pos: Vector2, color: Color, strength: float) -> void:
	shake = maxf(shake, minf(7.0, strength * 6.0))
	if strength >= 0.7:
		flash = maxf(flash, 0.045 if strength < 1.0 else 0.085)
		flash_color = color
	for index in range(int((strength * 9 + 3) * float(store.settings.get("particles", 1.0)))):
		if particles.size() < 160:
			var direction := (pos - model.player.pos + Vector2(0, 60)).normalized()
			if direction.length_squared() < 0.1:
				direction = Vector2(model.player.facing, -0.2)
			particles.append({"pos": pos, "velocity": direction.rotated(randf_range(-1.1, 1.1)) * randf_range(95, 300), "life": randf_range(0.12, 0.28), "color": color})
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
	_draw_world()
	if mode == "play":
		_draw_skill_presentation()
	if mode == "play" or mode == "pause" or mode == "result":
		_draw_hud()
	if mode == "play":
		_draw_controls()
		_draw_top_buttons()
	if toast_time > 0.0 and mode == "play":
		_box(Rect2(320, 120, 640, 44), Color(0.035, 0.055, 0.1, 0.94), Color(0.46, 0.94, 0.9, 0.25))
		_text(toast, Vector2(640, 150), 21, WHITE, true)

func _draw_world() -> void:
	world_offset = Vector2(sin(combat_time * 97.0), cos(combat_time * 83.0)) * shake * float(store.settings.get("shake", 1.0))
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
	_text({"outskirts": "SECTOR 01   /   OUTSKIRTS", "corridor": "SECTOR 02   /   MACHINE CORRIDOR", "core": "SECTOR 03   /   RIFT CORE"}.get(selected_stage, "RIFT TERMINAL"), Vector2(38, 302), 13, Color(0.46, 0.94, 0.9, 0.45))
	# Animated rift behind the boss spawn.
	for radius in [36, 56, 78]:
		draw_arc(Vector2(1100, 279), radius, time * 0.3 + radius, time * 0.3 + radius + PI * 1.6, 42, Color(0.62, 0.42, 0.94, 0.4), 3, true)
	if mode not in ["play", "pause", "result"]:
		draw_set_transform(Vector2.ZERO)
		return
	if mode == "play" and model.player.pose == "ultimate":
		draw_rect(Rect2(0, 0, 1280, 533), Color(0.01, 0.015, 0.04, 0.22))
	_draw_danger_zones()
	for chest in model.chests:
		var pos: Vector2 = chest.pos
		draw_rect(Rect2(pos - Vector2(20, 31), Vector2(40, 31)), Color("243a48"), true)
		draw_rect(Rect2(pos - Vector2(20, 31), Vector2(40, 31)), GOLD if not chest.opened else DIM, false, 2)
		draw_line(pos - Vector2(20, 21), pos + Vector2(20, -21), GOLD, 2)
		_text("已收集" if chest.opened else "补给箱 · 攻击开启", pos - Vector2(0, 48), 13, DIM if chest.opened else GOLD, true)
	for drop in model.pickups:
		draw_circle(drop.pos - Vector2(0, 16 + sin(time * 4) * 4), 14, Color(0.4, 1, 0.7, 0.2))
		draw_line(drop.pos - Vector2(7, 16), drop.pos + Vector2(7, -16), CYAN, 4)
		draw_line(drop.pos - Vector2(0, 23), drop.pos - Vector2(0, 9), CYAN, 4)
	var fighters: Array[Fighter] = []
	for effect in model.effects:
		VFX.draw_ground(self, effect, world_offset)
	VFX.draw_blade_trail(self, blade_trail, combat_time, world_offset)
	for effect in model.effects:
		if effect.kind == "dash":
			var trail_start: Vector2 = effect.pos
			var trail_end: Vector2 = model.player.pos if model.player.pose == "dash" else effect.end
			for index in range(1, 5):
				Hero.draw_ghost(self, trail_start.lerp(trail_end, float(index) / 5.0), effect.face, combat_time,
					pow(float(effect.life) / float(effect.max), 1.5) * (0.035 + index * 0.026),
					{"base_offset": world_offset, "height": effect.get("height", 0.0), "color": Color("83d2ec"), "tilt": 0.0})
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
		draw_rect(Rect2(0, 115, 1280, 418), Color(flash_color.r, flash_color.g, flash_color.b, flash * 0.45 * float(store.settings.get("flash", 0.5))))

func _draw_danger_zones() -> void:
	var bounds: Rect2 = model._bounds()
	if model.stage_id == "corridor":
		for x in [bounds.position.x, bounds.end.x]:
			draw_line(Vector2(x, 328), Vector2(x, 518), Color(0.5, 0.85, 0.9, 0.65), 3)
	var danger := Color("ff947d")
	for hazard in model.hazards:
		var rect: Rect2 = hazard.rect
		var active: bool = hazard.phase == "active"
		draw_rect(rect, Color(danger.r, danger.g, danger.b, 0.28 if active else 0.10))
		draw_rect(rect, danger, false, 3 if active else 2)
		for x in range(int(rect.position.x) + 8, int(rect.end.x), 24):
			draw_line(Vector2(x, rect.position.y + 7), Vector2(x + 10, rect.position.y + 18), danger, 2)
		_text("危险" if active else "即将激活 · 离开此区域", rect.get_center() + Vector2(0, 5), 14, danger, true)
	for zone in model.telegraphs():
		var harmless: bool = zone.kind == "transition"
		var color := Color("bca8ff") if harmless else danger
		match zone.kind:
			"circle", "transition":
				draw_circle(zone.pos, zone.radius, Color(color.r, color.g, color.b, 0.10))
				draw_arc(zone.pos, zone.radius, 0, TAU, 64, color, 2, true)
				_text("阶段转换" if harmless else "落点 · 离开圆圈", zone.pos + Vector2(0, 10), 16, color, true)
			"rect":
				draw_rect(zone.rect, Color(color.r, color.g, color.b, 0.12))
				draw_rect(zone.rect, color, false, 2)
			"line":
				var start: Vector2 = zone.start
				var end: Vector2 = zone.end
				var normal := (end - start).normalized().orthogonal() * float(zone.width) * 0.5
				var polygon := PackedVector2Array([start + normal, end + normal, end - normal, start - normal])
				draw_colored_polygon(polygon, Color(color.r, color.g, color.b, 0.15))
				polygon.append(polygon[0])
				draw_polyline(polygon, color, 2, true)
				draw_line(start, end, color, 1.5, true)
				if zone.attack == "rush":
					_text("冲锋线 · 侧向移动", (start + end) * 0.5 + Vector2(0, 22), 14, color, true)

func _draw_fighter(fighter: Fighter) -> void:
	if fighter.hp <= 0.0:
		return
	if fighter.kind == "player":
		Hero.draw_hero(self, fighter, combat_time, {"base_offset": world_offset})
		var glow := _blade_glow(fighter)
		if glow > 0.0:
			var color := VFX.GOLD if fighter.pose == "ultimate" else (VFX.VIOLET if fighter.pose == "burst" else VFX.CYAN)
			VFX.draw_blade_aura(self, Hero.blade_anchors(fighter, combat_time), glow, color, world_offset)
		return
	var scale_factor := 1.55 if fighter.kind == "boss" else (1.18 if fighter.kind == "heavy" else 1.0)
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
	if fighter.kind == "heavy":
		var shield_color := DIM if fighter.guard_open > 0.0 else color
		draw_colored_polygon(PackedVector2Array([Vector2(28, -80), Vector2(52, -72), Vector2(52, -31), Vector2(35, -17), Vector2(24, -35)]), armor.darkened(0.25))
		draw_line(Vector2(38, -71), Vector2(38, -32), shield_color, 5)
		draw_line(Vector2(-34, -88), Vector2(-24, -72), color, 5)
	if fighter.kind == "charger":
		draw_colored_polygon(PackedVector2Array([Vector2(-22, -94), Vector2(-43, -111), Vector2(-18, -80)]), color)
		draw_colored_polygon(PackedVector2Array([Vector2(16, -91), Vector2(39, -84), Vector2(16, -76)]), color)
		draw_line(Vector2(-12, -52), Vector2(14, -52), color, 5)
	if fighter.kind == "boss":
		draw_colored_polygon(PackedVector2Array([Vector2(-18, -103), Vector2(-28, -123), Vector2(-5, -106)]), color)
		draw_colored_polygon(PackedVector2Array([Vector2(18, -103), Vector2(28, -123), Vector2(5, -106)]), color)
		draw_circle(Vector2(0, -52), 11, Color("c8a4ff") if fighter.phase == 2 else color)
	if fighter.windup > 0.0:
		draw_circle(Vector2(0, -125), 13, GOLD)
		draw_line(Vector2(0, -132), Vector2(0, -124), Color("282335"), 3)
		draw_circle(Vector2(0, -118), 1.5, Color("282335"))
	draw_set_transform(world_offset)
	if fighter.kind != "boss":
		var origin := pos - Vector2(28, 145)
		draw_rect(Rect2(origin, Vector2(56, 4)), Color("302e45"))
		draw_rect(Rect2(origin, Vector2(56 * fighter.hp / fighter.max_hp, 4)), color)
		_text({"drone": "近战", "ranged": "射手", "heavy": "重装", "charger": "冲锋"}.get(fighter.kind, ""), origin + Vector2(28, -7), 12, color, true)
	if fighter.recovery > 0.15 or fighter.guard_open > 0.0:
		_text("破绽", pos + Vector2(0, -115 * scale_factor), 14, CYAN, true)

func _blade_glow(fighter: Fighter) -> float:
	if fighter.pose == "dash":
		return 0.7
	if not Hero.RELEASE_TIMES.has(fighter.pose):
		return 0.0
	var releases: Array = Hero.RELEASE_TIMES[fighter.pose]
	if fighter.pose_time < releases[0]:
		return clampf(fighter.pose_time / releases[0], 0.0, 1.0) * 0.75
	var last_release: float = releases[0]
	for release in releases:
		if fighter.pose_time >= release:
			last_release = release
	return exp(-(fighter.pose_time - last_release) * 16.0) * 0.8

func _draw_effect(effect: Dictionary) -> void:
	if effect.kind == "guard":
		var color: Color = effect.color
		color.a = clampf(float(effect.life) / float(effect.max), 0.0, 1.0)
		draw_arc(effect.pos, float(effect.get("size", 36.0)), 0, TAU, 32, color, 3, true)
		_text("格挡 · 绕后或第三击", effect.pos - Vector2(0, 48), 14, color, true)
	elif effect.kind == "number":
		if not store.settings.get("damage_numbers", true):
			return
		var ratio := clampf(float(effect.life) / float(effect.max), 0.0, 1.0)
		var color: Color = effect.color
		color.a = ratio
		var heavy: bool = effect.get("heavy", false)
		var progress := 1.0 - ratio
		var size := int((27.0 if heavy else 20.0) * (1.0 + 0.14 * sin(progress * PI)))
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
	var stage_name: String = model.stage.get("name", "遗落港")
	_text("训练 · 无奖励" if practice_mode else "%s / %d-%d" % [stage_name, maxi(1, model.wave), model.total_waves], Vector2(640, 55), 23, WHITE, true)
	_text(model.stage.get("objective", "清除当前敌人"), Vector2(640, 82), 15, DIM, true)
	_text("击破 %d / 分数 %06d" % [model.kills, model.score], Vector2(1096, 103), 14, DIM, false, true)
	if model.player.hp / model.player.max_hp <= 0.25:
		_text("生命危险 · 躲避前摇再反击", Vector2(42, 141), 18, GOLD)
	if model.retaliation_time > 0.0:
		_text("反击就绪 · %.1f秒" % model.retaliation_time, Vector2(42, 170), 18, CYAN)
	if model.streak > 1:
		_text(str(model.streak), Vector2(868, 176), 49, GOLD, true)
		_text("连击", Vector2(868, 202), 18, WHITE, true)
	for enemy in model.enemies:
		if enemy.kind == "boss":
			_text("裂隙守卫 · 阶段 %d" % enemy.phase, Vector2(640, 191), 18, Color("f4a0a2"), true)
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
	_round_button(ATTACK_CENTER, 62, "攻击", Bindings.hint(store.settings, "attack") + " · 连招", CYAN, 0.0, true)
	_round_button(DASH_CENTER, 45, "瞬斩", Bindings.hint(store.settings, "dash") + " · 22能量", CYAN, model.cooldowns.dash, model.energy >= 22)
	_round_button(BURST_CENTER, 43, "裂隙", Bindings.hint(store.settings, "burst") + " · 48能量", Color("bfa2ff"), model.cooldowns.burst, model.energy >= 48)
	_round_button(JUMP_CENTER, 41, "跳跃", Bindings.hint(store.settings, "jump"), GOLD, 0, true)
	_round_button(ULTIMATE_CENTER, 48, "断界" if model.has_skill("ultimate") else "未解锁", Bindings.hint(store.settings, "ultimate") + (" · 75能量" if model.has_skill("ultimate") else " · 首通外围"), GOLD, model.cooldowns.ultimate, model.has_skill("ultimate") and model.energy >= 75)
	if model.has_skill("ultimate") and model.cooldowns.ultimate <= 0.0 and model.energy >= 75:
		draw_arc(ULTIMATE_CENTER, 55, time * 1.6, time * 1.6 + PI * 1.4, 48, Color(1, 0.76, 0.47, 0.6), 2, true)
	_text("移动 %s%s%s%s / 方向键  ·  %s 连招  %s 瞬斩  %s 裂隙  %s 断界" % [Bindings.hint(store.settings, "move_up"), Bindings.hint(store.settings, "move_left"), Bindings.hint(store.settings, "move_down"), Bindings.hint(store.settings, "move_right"), Bindings.hint(store.settings, "attack"), Bindings.hint(store.settings, "dash"), Bindings.hint(store.settings, "burst"), Bindings.hint(store.settings, "ultimate")], Vector2(530, 682), 14, DIM, true)

func _round_button(center: Vector2, radius: float, label: String, hint: String, color: Color, cooldown: float, available: bool) -> void:
	draw_circle(center, radius + 5, Color(color.r, color.g, color.b, 0.06))
	draw_circle(center, radius, Color(0.045, 0.08, 0.13, 0.92))
	draw_arc(center, radius, 0, TAU, 64, Color(color.r, color.g, color.b, 0.75 if available else 0.25), 2, true)
	_text("%.1f" % cooldown if cooldown > 0.0 else label, center + Vector2(0, 8), 23 if radius > 50 else 21, color if available else DIM, true)
	_text(hint, center + Vector2(0, radius + 22), 12, DIM, true)

func _draw_top_buttons() -> void:
	_box(Rect2(1140, 28, 48, 44), Color("142336"), Color("33465b"))
	_text("静" if store.muted else "音", Vector2(1164, 57), 20, DIM, true)
	if mode == "play":
		_box(Rect2(1200, 28, 48, 44), Color("142336"), Color("33465b"))
		draw_line(Vector2(1218, 40), Vector2(1218, 60), WHITE, 4)
		draw_line(Vector2(1230, 40), Vector2(1230, 60), WHITE, 4)

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
	if store.settings.get("large_text", false):
		size += 2
	var width := ui_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := pos
	if centered:
		origin.x -= width * 0.5
	elif right:
		origin.x -= width
	draw_string(ui_font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
