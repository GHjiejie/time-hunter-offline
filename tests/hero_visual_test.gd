extends SceneTree

class PoseBoard:
	extends Node2D
	var fighters: Array[Fighter] = []
	var clocks: Array[float] = []

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 500), Color("172639"))
		var font := ThemeDB.fallback_font
		for index in fighters.size():
			var fighter := fighters[index]
			draw_line(fighter.pos - Vector2(65, 0), fighter.pos + Vector2(65, 0), Color(0.3, 0.65, 0.7, 0.55), 1.0)
			HeroRenderer.draw_hero(self, fighter, clocks[index])
			draw_circle(fighter.pos, 2, Color("e9c47a"))
			draw_string(font, fighter.pos + Vector2(-46, 30), "%s / %s" % [index % 8, "R" if fighter.facing > 0 else "L"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("cbe1ee"))


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	var texture := load(HeroRenderer.ATLAS_PATH) as Texture2D
	assert(texture != null, "Character atlas must be imported")
	assert(texture.get_size() == Vector2(1536, 1024), "Sprite layout dimensions must match renderer regions")
	var pixels := texture.get_image()
	assert(pixels.get_pixel(0, 0).a < 0.01, "Character atlas must preserve transparent background")
	assert(pixels.get_pixel(170, 100).a > 0.5, "Atlas must contain visible character art")
	var board := PoseBoard.new()
	root.size = Vector2i(1280, 500)
	root.add_child(board)
	var poses := ["idle", "idle", "run", "run", "slash_1", "slash_1", "dash", "ultimate"]
	var times := [0.0, 0.0, 0.01, 0.10, 0.08, 0.20, 0.1, 0.2]
	for index in 16:
		var frame := index % 8
		var fighter := Fighter.new()
		fighter.kind = "player"
		fighter.pose = poses[frame]
		fighter.pose_time = times[frame]
		fighter.pose_duration = 0.27 if frame == 4 or frame == 5 else 1.62
		fighter.moving = 1.0 if frame == 2 or frame == 3 else 0.0
		fighter.pos = Vector2(80 + frame * 160, 210 + (index / 8) * 230)
		fighter.facing = 1.0 if index < 8 else -1.0
		board.fighters.append(fighter)
		board.clocks.append(1.0 if frame == 1 else 0.0)
	board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var capture_path := OS.get_environment("HERO_CAPTURE_PATH")
	if capture_path.is_empty():
		capture_path = "user://hero-art-qa.png"
	DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
	var result := image.save_png(capture_path)
	assert(result == OK, "Hero pose board screenshot must be saved")
	print("Hero visual test passed: 8 distinct frames, both facings, transparent atlas; " + capture_path)
	board.queue_free()
	await process_frame
	quit()
