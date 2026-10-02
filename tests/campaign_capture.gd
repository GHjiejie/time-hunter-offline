extends SceneTree

const TEST_PROGRESS := "user://campaign-capture-progress.json"
var scene: Node2D
var output := ""
var failures := 0

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	cleanup()
	output = OS.get_environment("CAPTURE_DIR")
	if output.is_empty():
		output = "/tmp/rift-hunter-campaign"
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scenes/main.tscn").instantiate()
	scene.store.storage_path = TEST_PROGRESS
	root.add_child(scene)
	root.size = Vector2i(1280, 720)
	scene.set_process(false)
	if not is_instance_valid(scene.campaign_ui):
		quit(1)
		return
	await shot("campaign-menu.png")
	scene._ui_action("begin")
	await shot("campaign-prepare.png")
	scene._ui_action("page", {"page": "stages"})
	await shot("campaign-stages.png")
	scene._ui_action("start_stage", {"stage": "outskirts"})
	await advance(40)
	scene.model.player.pos = Vector2(670, 398)
	scene.model.attack()
	await advance(4)
	await shot("campaign-outskirts.png")
	await complete_stage()
	await shot("campaign-result.png")
	scene._ui_action("page", {"page": "inventory"})
	scene.campaign_ui._selected_uid = scene.store.inventory[-1].uid
	scene.campaign_ui._rebuild()
	await shot("campaign-inventory.png")
	scene._ui_action("page", {"page": "prepare"})
	scene._ui_action("variant", {"skill": "burst", "variant": "focused"})
	scene._ui_action("passive", {"passive": "guard"})
	scene._ui_action("equip", {"uid": scene.store.inventory[-1].uid})
	scene._ui_action("start_stage", {"stage": "corridor"})
	await advance(40)
	scene.model.player.pos = Vector2(650, 430)
	for enemy in scene.model.enemies:
		enemy.speed = 0
		enemy.attack_clock = 100
		enemy.pos = Vector2(840, 425) if enemy.kind == "heavy" else Vector2(985, 356)
		if enemy.kind == "heavy":
			scene.model._begin_enemy_attack(enemy)
	scene.model.hazards.append({"rect": Rect2(345, 334, 150, 145), "phase": "telegraph", "life": 0.95, "max": 0.95, "damage": 22.0})
	await shot("campaign-corridor.png")
	await complete_stage()
	scene._ui_action("next_stage")
	await advance(40)
	for enemy in scene.model.enemies:
		scene.model._hit_enemy(enemy, enemy.max_hp * 10.0, 0, 0, 1, Color("76eee6"), 0, 0)
	for index in range(240):
		if scene.model.enemies.any(func(enemy): return enemy.kind == "boss"):
			break
		await advance(1)
	var boss: Fighter
	for enemy in scene.model.enemies:
		if enemy.kind == "boss":
			boss = enemy
	if boss == null:
		printerr("FAIL: Boss encounter did not spawn")
		failures += 1
	else:
		scene.model.player.pos = Vector2(600, 410)
		boss.pos = Vector2(905, 420)
		boss.attack_index = 2
		boss.windup = 0
		boss.recovery = 0
		scene.model._begin_enemy_attack(boss)
		await shot("campaign-boss.png")
		boss.hp = boss.max_hp * 0.45
		scene.model._update_enemy(boss, 0.01)
		await shot("campaign-boss-phase.png")
	await complete_stage()
	await shot("campaign-chapter-clear.png")
	scene._ui_action("page", {"page": "settings"})
	await shot("campaign-settings.png")
	scene._ui_action("setting", {"key": "large_text", "value": true})
	root.size = Vector2i(960, 540)
	await shot("campaign-small-large-text.png")
	print("CAMPAIGN CAPTURE: %s / FAILED: %d" % [output, failures])
	scene.queue_free()
	await process_frame
	cleanup()
	quit(0 if failures == 0 else 1)

func complete_stage() -> void:
	# Controlled encounters verify that the production scene reaches settlement;
	# this fixture is not a playability or difficulty measurement.
	for index in range(500):
		if scene.mode == "result":
			return
		for enemy in scene.model.enemies:
			scene.model._hit_enemy(enemy, enemy.max_hp * 10.0, 0, 0, 1, Color("76eee6"), 0, 0)
		scene.model.player.hp = scene.model.player.max_hp
		await advance(1)
	printerr("FAIL: stage did not reach settlement")
	failures += 1

func advance(frames: int) -> void:
	for index in range(frames):
		# Desktop capture loses focus to tooling; this fixture intentionally drives
		# the live simulation while production focus-loss behavior has its own test.
		if scene.model.running:
			scene.mode = "play"
			scene.campaign_ui.hide_ui()
			scene._process(1.0 / 60.0)
		await process_frame

func shot(filename: String) -> void:
	scene.queue_redraw()
	for index in range(5):
		await process_frame
	if filename == "campaign-settings.png":
		var slider: Control = scene.campaign_ui.action_controls.setting_master_volume
		var scroll: ScrollContainer = scene.campaign_ui._body.get_parent()
		if not scroll.get_global_rect().encloses(slider.get_global_rect()):
			printerr("FAIL: initial volume control is outside the settings viewport")
			failures += 1
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(output.path_join(filename)) != OK:
		printerr("FAIL: screenshot " + filename)
		failures += 1

func cleanup() -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROGRESS + suffix))
