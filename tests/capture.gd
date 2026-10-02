extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("CAPTURE_DIR")
	if path.is_empty(): path = "user://"
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join("menu.png"))
	scene._pointer(1, Vector2(1000, 330), true)
	assert(scene.mode == "play", "Start button must begin game")
	scene._pointer(1, Vector2(1000, 330), false)
	scene._pointer(15, Vector2(207, 587), true)
	scene._pointer(16, Vector2(1110, 592), true)
	assert(scene.stick.x > 0 and scene.touch_actions.values().has("attack"), "Move and attack must work together")
	scene._pointer(16, Vector2(1110, 592), false)
	assert(scene.stick.x > 0 and scene.touch_actions.is_empty(), "Attack release must preserve joystick")
	scene._pointer(15, Vector2(207, 587), false)
	assert(scene.stick == Vector2.ZERO, "Joystick release must stop movement")
	scene._pointer(15, Vector2(207, 587), true)
	scene._pause()
	assert(scene.stick == Vector2.ZERO and scene.touch_actions.is_empty(), "Pause must clear touches")
	scene._menu_action("resume")
	assert(scene.mode == "play", "Resume must continue")
	scene.model.wave_wait = 0.0
	scene.model.step(0.01, Vector2.ZERO)
	scene.model.player.pos = Vector2(725, 418)
	scene.model.skill("burst")
	scene.model.attack()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join("combat.png"))
	print("CAPTURE: " + path)
	scene.queue_free()
	await process_frame
	quit()
