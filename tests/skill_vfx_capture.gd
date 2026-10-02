extends SceneTree

# Run with the graphical renderer. Simulation advances exactly once per saved
# frame, independently of PNG encoding speed or the desktop refresh rate.
const FRAME_DELTA := 1.0 / 60.0
const CAPTURE_SEED := 8217
const TEST_PROGRESS := "user://skill-vfx-capture-progress.json"

var scene: Node2D
var capture_dir := ""
var frame_index := 0
var frames: Array[Dictionary] = []
var named_shots: Dictionary = {}
var clip := ""
var facing := 1.0
var clip_frame := 0


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	cleanup_progress()
	capture_dir = OS.get_environment("CAPTURE_DIR")
	if capture_dir.is_empty():
		capture_dir = "user://skill-vfx-showcase"
	capture_dir = ProjectSettings.globalize_path(capture_dir)
	assert(DirAccess.make_dir_recursive_absolute(capture_dir) == OK, "Showcase output folder must be writable")
	seed(CAPTURE_SEED)
	scene = load("res://scenes/main.tscn").instantiate()
	scene.store.storage_path = TEST_PROGRESS
	scene.store.muted = true
	root.size = Vector2i(1280, 720)
	root.add_child(scene)
	scene.set_process(false)
	if not is_instance_valid(scene.campaign_ui):
		printerr("Campaign UI failed to initialize; skill capture cancelled")
		cleanup_progress()
		scene.queue_free()
		quit(1)
		return
	assert(scene.store.new_game(), "Showcase must create an isolated campaign save")
	scene.store.legacy_skills = true
	scene.store.variants.burst = "wide"
	scene.store.muted = true
	for direction in [1.0, -1.0]:
		facing = direction
		prepare("idle")
		await record_frames(12)
		prepare("combo")
		assert(scene.model.attack())
		var combo_casts := 1
		for index in range(76):
			if scene.model.player.action_lock <= 0.0 and combo_casts < 3:
				assert(scene.model.attack())
				combo_casts += 1
			await record_frame()
		assert(combo_casts == 3, "Showcase must complete all three combo attacks")
		prepare("dash")
		assert(scene.model.skill("dash"))
		await record_frames(38)
		prepare("rift")
		assert(scene.model.skill("burst"))
		await record_frames(76)
		prepare("ultimate")
		assert(scene.model.skill("ultimate"))
		await record_frames(120)
	write_manifest()
	cleanup_progress()
	print("SKILL VFX CAPTURE: %d frames at 60 fps; %s" % [frames.size(), capture_dir])
	print("NAMED SHOTS: " + str(named_shots.keys()))
	scene.queue_free()
	await process_frame
	quit()


func prepare(name: String) -> void:
	clip = name
	clip_frame = 0
	scene.store.level = 0
	assert(scene.store.abandon_run(), "Previous showcase run must be safely abandoned")
	scene._start("outskirts")
	assert(scene.mode == "play" and scene.model.has_skill("ultimate"), "Showcase starts with all legacy skills")
	scene.model.rng.seed = CAPTURE_SEED
	scene.model.player.pos = Vector2(640, 422)
	if name == "dash":
		scene.model.player.pos.x = 500.0 if facing > 0.0 else 780.0
	scene.model.player.facing = facing
	scene.model.wave = scene.model.total_waves
	scene.model.wave_wait = 100.0
	scene.store.level = 0
	scene.store.muted = true
	scene.time = 0.0
	scene.toast_time = 0.0
	for index in range(2):
		var target := Fighter.new()
		target.kind = "drone" if index == 0 else "boss"
		target.id = index
		target.pos = scene.model.player.pos + Vector2(facing * (120.0 + index * 135.0), 0.0)
		target.hp = 100000.0
		target.max_hp = target.hp
		target.tint = Color("ed9b77") if index == 0 else Color("ff6d67")
		target.speed = 0.0
		target.attack_clock = 1000.0
		scene.model.enemies.append(target)


func record_frames(count: int) -> void:
	for index in range(count):
		await record_frame()


func record_frame() -> void:
	# The real scene's simulation, hitstop, poses, effects and feedback are used.
	scene.mode = "play"
	scene.campaign_ui.hide_ui()
	scene._process(FRAME_DELTA)
	var effects_before_draw: Array[Dictionary] = scene.model.effects.duplicate(true)
	var target_health: Array[float] = []
	for target in scene.model.enemies:
		target_health.append(target.hp)
	scene.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	assert(scene.model.effects == effects_before_draw, "Renderer must not mutate simulation effect data")
	for index in range(scene.model.enemies.size()):
		assert(scene.model.enemies[index].hp == target_health[index], "Drawing skill effects must never cause damage")
	var pixels: Image = root.get_texture().get_image()
	var filename := "frame-%05d.png" % frame_index
	assert(pixels.save_png(capture_dir.path_join(filename)) == OK, "Showcase PNG must save")
	var effect_stages: Array[String] = []
	for effect in scene.model.effects:
		var stage_name := "%s_%d" % [effect.kind, effect.get("stage", 0)]
		if not effect_stages.has(stage_name):
			effect_stages.append(stage_name)
		var ratio: float = float(effect.life) / float(effect.max)
		if effect.kind in ["slash", "rift", "ultimate"] and ratio <= 0.82 and ratio >= 0.58:
			named_shot(pixels, "%s-stage-%d-%s.png" % [clip, effect.get("stage", 0), side()])
		elif effect.kind in ["rift_charge", "ultimate_charge"] and ratio <= 0.45 and ratio >= 0.20:
			named_shot(pixels, "%s-charge-%s.png" % [clip, side()])
	if clip == "idle" and clip_frame == 6:
		named_shot(pixels, "idle-%s.png" % side())
	if clip == "dash" and clip_frame == 11:
		named_shot(pixels, "dash-travel-%s.png" % side())
	frames.append({
		"file": filename,
		"frame": frame_index,
		"clip": clip,
		"facing": side(),
		"clip_time": clip_frame * FRAME_DELTA,
		"combat_time": scene.combat_time,
		"pose": scene.model.player.pose,
		"pose_time": scene.model.player.pose_time,
		"effects": effect_stages,
	})
	frame_index += 1
	clip_frame += 1


func named_shot(pixels: Image, filename: String) -> void:
	if named_shots.has(filename):
		return
	assert(pixels.save_png(capture_dir.path_join(filename)) == OK, "Named skill PNG must save")
	named_shots[filename] = frame_index


func side() -> String:
	return "right" if facing > 0.0 else "left"


func write_manifest() -> void:
	var file := FileAccess.open(capture_dir.path_join("manifest.json"), FileAccess.WRITE)
	assert(file != null, "Showcase manifest must be writable")
	file.store_string(JSON.stringify({
		"fps": 60,
		"seed": CAPTURE_SEED,
		"frame_count": frames.size(),
		"size": [1280, 720],
		"named_shots": named_shots,
		"frames": frames,
	}, "\t"))
	file.close()


func cleanup_progress() -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROGRESS + suffix))
