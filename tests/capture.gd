extends SceneTree

var scene: Node2D
var capture_path := ""
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("capture")

func verify(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func capture() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	await create_timer(0.5).timeout
	scene.set_process(false)
	capture_path = OS.get_environment("CAPTURE_DIR")
	if capture_path.is_empty(): capture_path = "user://"
	DirAccess.make_dir_recursive_absolute(capture_path)
	await shot("menu.png")
	scene._pointer(1, Vector2(1000, 330), true)
	verify(scene.mode == "play", "Start button begins game")
	scene._pointer(1, Vector2(1000, 330), false)
	scene._pointer(15, Vector2(207, 587), true)
	scene._pointer(16, scene.ATTACK_CENTER, true)
	verify(scene.stick.x > 0 and scene.touch_actions.values().has("attack"), "Move and attack together")
	scene._pointer(16, scene.ATTACK_CENTER, false)
	verify(scene.stick.x > 0 and scene.touch_actions.is_empty(), "Attack release preserves joystick")
	scene._pointer(15, Vector2(207, 587), false)
	verify(scene.stick == Vector2.ZERO, "Joystick release stops movement")
	scene._pointer(15, Vector2(207, 587), true)
	scene._pause()
	verify(scene.stick == Vector2.ZERO and scene.touch_actions.is_empty(), "Pause clears touches")
	var paused_elapsed: float = scene.model.elapsed
	scene._process(0.05)
	verify(scene.model.elapsed == paused_elapsed, "Pause suspends combat")
	scene._menu_action("resume")
	verify(scene.mode == "play", "Resume continues")
	prepare_arena(Vector2(595, 420))
	await advance(2)
	await shot("renfeng-idle.png")
	scene._pointer(17, scene.ATTACK_CENTER, true)
	await advance(4)
	verify(scene.model.enemies[0].hp < 1200.0, "Touch attack contacts target")
	verify(scene.model.hitstop > 0.0, "Real hit requests pause")
	var held_elapsed: float = scene.model.elapsed
	var held_pose: float = scene.model.player.pose_time
	scene._process(0.005)
	verify(scene.model.elapsed == held_elapsed and scene.model.player.pose_time == held_pose, "Hitstop freezes simulation and pose")
	await shot("renfeng-slash.png")
	scene._pointer(17, scene.ATTACK_CENTER, false)
	prepare_arena(Vector2(450, 420))
	scene._pointer(18, scene.DASH_CENTER, true)
	await advance(11)
	verify(scene.model.player.pos.x > 450.0 and scene.model.cooldowns.dash > 0, "Touch dash sweeps arena")
	await shot("renfeng-dash.png")
	scene._pointer(18, scene.DASH_CENTER, false)
	prepare_arena(Vector2(695, 420))
	scene._pointer(19, scene.BURST_CENTER, true)
	await advance(51)
	verify(scene.model.effects.any(func(effect): return effect.kind == "rift" and effect.stage == 3), "Rift final visual stage")
	verify(scene.model.enemies[0].height > 0.0, "Rift launches target")
	await shot("renfeng-rift.png")
	scene._pointer(19, scene.BURST_CENTER, false)
	prepare_arena(Vector2(695, 420))
	scene._pointer(20, scene.ULTIMATE_CENTER, true)
	verify(scene.model.player.pose == "ultimate" and scene.model.energy == 25.0, "Touch ultimate spends energy")
	await advance(12)
	await shot("renfeng-ultimate-charge.png")
	await advance_until_effect("ultimate", 4, 110)
	verify(scene.model.effects.any(func(effect): return effect.kind == "ultimate" and effect.stage == 4), "Ultimate final strike rendered")
	verify(scene.model.enemies[3].hp < 1800, "Ultimate hits boss")
	await shot("combat.png")
	scene._pointer(20, scene.ULTIMATE_CENTER, false)
	prepare_arena(Vector2(500, 420))
	var event := InputEventKey.new()
	event.physical_keycode = KEY_U
	event.pressed = true
	scene._unhandled_input(event)
	verify(scene.model.cooldowns.ultimate > 0, "Keyboard ultimate activation")
	verify(scene.sound_bank.size() == 8, "Cached charge, release and combat sounds available")
	print("VISUAL / INPUT CHECKS: %d / FAILED: %d" % [checks, failures])
	print("CAPTURE: " + capture_path)
	scene.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func prepare_arena(pos: Vector2) -> void:
	scene._start()
	scene.toast_time = 0.0
	scene.model.player.pos = pos
	scene.model.wave = 3
	scene.model.wave_wait = 2.0
	for index in range(4):
		var enemy := Fighter.new()
		enemy.pos = Vector2(690 + index * 76, 416 + index % 2 * 22)
		enemy.kind = "boss" if index == 3 else ("ranged" if index == 2 else "drone")
		enemy.id = index
		enemy.max_hp = 1800.0 if index == 3 else 1200.0
		enemy.hp = enemy.max_hp
		enemy.tint = Color("ff6d67") if index == 3 else Color("ed9b77")
		enemy.speed = 0.0
		enemy.attack_clock = 100.0
		scene.model.enemies.append(enemy)

func advance(frames: int) -> void:
	for index in range(frames):
		# Desktop focus notifications are unrelated to synthetic touch input.
		scene.mode = "play"
		scene._process(1.0 / 60.0)
		await process_frame

func advance_until_effect(kind: String, stage: int, limit: int) -> void:
	for index in range(limit):
		if scene.model.effects.any(func(effect): return effect.kind == kind and effect.get("stage", -1) == stage):
			return
		await advance(1)

func shot(filename: String) -> void:
	scene.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(capture_path.path_join(filename))
	verify(error == OK, "Screenshot saved: " + filename)
