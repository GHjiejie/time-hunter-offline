extends SceneTree

var scene: Node2D
var checks := 0
var failures := 0
var casts: Array[String] = []
const TEST_PROGRESS := "user://skill-buffer-test-progress.json"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	cleanup_progress()
	scene = load("res://scenes/main.tscn").instantiate()
	scene.store.storage_path = TEST_PROGRESS
	scene.store.muted = true
	root.add_child(scene)
	scene.set_process(false)
	check(is_instance_valid(scene.campaign_ui), "Campaign UI and main scene initialize without dependency errors")
	if not is_instance_valid(scene.campaign_ui):
		cleanup_progress()
		scene.queue_free()
		quit(1)
		return
	check(scene.store.new_game(), "Buffer test creates an isolated campaign save")
	scene.store.legacy_skills = true
	scene.store.variants.burst = "wide"
	scene.store.muted = true
	scene.model.skill_cast.connect(func(name): casts.append(name))
	prepare()
	scene._pointer(1, scene.ATTACK_CENTER, true)
	scene._pointer(2, scene.BURST_CENTER, true)
	check(scene.pending_skill == "burst" and casts.is_empty(), "skill tap buffers during held attack without overlapping")
	check(scene.model.player.pose == "slash_1" and scene.model.energy == 100.0, "buffer preserves current attack and resources")
	scene._pointer(3, scene.ULTIMATE_CENTER, true)
	check(scene.pending_skill == "burst", "additional tap cannot stack or replace buffered skill")
	for index in range(100):
		scene._process(0.01)
		if not casts.is_empty():
			break
	check(casts == ["burst"] and scene.model.player.pose == "burst", "buffered skill wins priority over next held combo")
	check(scene.pending_skill.is_empty() and scene.model.energy <= 52.1, "buffer consumes once and spends energy once")
	scene._pointer(10, scene.DASH_CENTER, true)
	check(scene.pending_skill.is_empty() and casts == ["burst"], "active skill cannot buffer or stack another skill")
	for index in range(200):
		scene._process(0.01)
		if scene.model.player.pose.begins_with("slash_"):
			break
	check(scene.model.player.pose.begins_with("slash_") and scene.touch_actions.get(1) == "attack", "held attack resumes after buffered skill")
	for index in range(80):
		scene._process(0.01)
	check(casts == ["burst"], "held attack does not repeat a buffered skill")
	prepare()
	scene._pointer(4, scene.ATTACK_CENTER, true)
	scene._pointer(5, scene.DASH_CENTER, true)
	check(scene.pending_skill == "dash", "dash also buffers from touch")
	scene._pause()
	check(scene.pending_skill.is_empty() and scene.pending_skill_time == 0.0 and scene.touch_actions.is_empty(), "pause clears queue and held touches")
	scene._menu_action("resume")
	advance(100)
	check(casts == ["burst"], "resume cannot cast stale buffered input")
	prepare()
	scene._pointer(6, scene.ATTACK_CENTER, true)
	scene._use_skill("dash")
	scene.model.hitstop = 1.0
	scene._process(0.81)
	check(scene.pending_skill.is_empty() and scene.pending_skill_time == 0.0, "buffer expires after 0.8 real seconds")
	prepare()
	scene._pointer(7, scene.ATTACK_CENTER, true)
	scene.model.energy = 0.0
	scene._use_skill("ultimate")
	check(scene.pending_skill.is_empty(), "unaffordable skill cannot suppress held attacks")
	scene.model.energy = 100.0
	scene.model.cooldowns.dash = 2.0
	scene._use_skill("dash")
	check(scene.pending_skill.is_empty(), "cooldown skill is not buffered")
	scene._use_skill("burst")
	scene.model._damage_player(20.0)
	scene._process(0.01)
	check(scene.pending_skill.is_empty() and casts == ["burst"], "attack interrupted by damage cancels queued skill")
	prepare()
	scene._pointer(11, scene.ATTACK_CENTER, true)
	scene._use_skill("burst")
	scene._menu_action("menu")
	check(scene.pending_skill.is_empty(), "return to menu clears queue")
	prepare()
	scene._pointer(8, scene.ATTACK_CENTER, true)
	scene._use_skill("burst")
	check(scene.store.abandon_run(), "Restart abandons the previous saved run")
	scene._start("outskirts")
	check(scene.pending_skill.is_empty(), "new round clears queue")
	prepare()
	scene._pointer(9, scene.ATTACK_CENTER, true)
	scene._use_skill("burst")
	scene._on_finished(false, 0)
	check(scene.pending_skill.is_empty(), "result clears queue")
	cleanup_progress()
	scene.queue_free()
	print("SKILL BUFFER CHECKS: %d / FAILED: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func prepare() -> void:
	check(scene.store.abandon_run(), "Previous buffer test run is safely abandoned")
	scene._start("outskirts")
	check(scene.mode == "play" and scene.model.has_skill("ultimate"), "Buffer arena starts with all legacy skills")
	scene.model.wave = scene.model.total_waves
	var target := Fighter.new()
	target.pos = scene.model.player.pos + Vector2(80, 0)
	target.hp = 2000.0
	target.max_hp = 2000.0
	target.speed = 0.0
	target.attack_clock = 100.0
	scene.model.enemies.append(target)

func advance(frames: int) -> void:
	for index in range(frames):
		scene._process(0.01)

func cleanup_progress() -> void:
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROGRESS + suffix))
