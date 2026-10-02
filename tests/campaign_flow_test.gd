extends SceneTree

## Integration checks exercise the real scene and its UI action router. Enemy HP
## is cleared under test control: this validates flow/persistence, not player AI
## or the difficulty of legitimately beating an encounter.
const Store := preload("res://scripts/save_store.gd")
const Content := preload("res://scripts/game_content.gd")
var checks := 0
var failures := 0
var test_directory := ""
var scenes: Array[Node2D] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func run() -> void:
	test_directory = "user://campaign-flow-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(test_directory))
	var scene := _scene("chapter")
	_test_chapter(scene)
	_test_pause_and_failure_retry(scene)
	_test_quit_and_reload()
	_test_pending_settlement()
	_test_checkpoint_write_failure()
	_test_pending_loss()
	_cleanup()
	print("CAMPAIGN FLOW CHECKS: %d / FAILED: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _scene(name: String) -> Node2D:
	var scene: Node2D = load("res://scenes/main.tscn").instantiate()
	# Inject the test path before _ready loads anything. Production progress never
	# participates in these checks, including when a failed save is simulated.
	scene.store.storage_path = test_directory + "/" + name + ".json"
	root.add_child(scene)
	scene.set_process(false)
	scenes.append(scene)
	return scene

func _advance(scene: Node2D, seconds: float) -> void:
	for index in range(int(ceil(seconds / 0.02))):
		scene._process(0.02)

func _reach_wave(scene: Node2D, desired_wave: int) -> bool:
	for index in range(1000):
		if scene.mode != "play":
			return false
		if scene.model.wave >= desired_wave and not scene.model.enemies.is_empty():
			return true
		for enemy in scene.model.enemies:
			enemy.hp = 0.0
		scene._process(0.02)
	return false

func _finish(scene: Node2D) -> bool:
	for index in range(1200):
		if scene.mode == "result":
			return true
		if scene.mode != "play":
			return false
		for enemy in scene.model.enemies:
			enemy.hp = 0.0
		scene._process(0.02)
	return false

func _test_chapter(scene: Node2D) -> void:
	check(scene.mode == "menu" and not scene.store.has_progress, "actual scene opens menu without auto-creating a save")
	scene._ui_action("begin")
	check(scene.mode == "prepare" and scene.store.has_progress, "begin action creates progress and opens preparation")
	scene._ui_action("page", {"page": "stages"})
	check(scene.mode == "stages" and scene.campaign_ui.page == "stages", "preparation routes to the actual stage screen")
	scene._ui_action("start_stage", {"stage": "outskirts"})
	check(scene.mode == "play" and scene.model.stage_id == "outskirts" and scene.store.active_run.stage == "outskirts", "stage action starts battle only after saved run exists")
	check(not scene.campaign_ui._root.visible, "start-stage hides the interactive campaign overlay")
	check(not scene.model.has_skill("ultimate") and scene.model.player.max_hp == scene.store.combat_config().health, "actual battle uses initial unlocks and equipped attributes")
	for stage_id in Content.STAGE_IDS:
		check(scene.model.stage_id == stage_id and _finish(scene), "controlled encounter completion reaches result for " + stage_id)
		check(scene.won and scene.settlement.ok and scene.settlement.first_clear and not scene.settlement_pending, "result displays confirmed first-clear transaction for " + stage_id)
		var stage_data: Dictionary = Content.stage(stage_id)
		check(scene.reward == int(stage_data.coins) + int(stage_data.first_coins), "result reward equals actually banked stage reward for " + stage_id)
		var saved := Store.new()
		saved.load_progress(scene.store.storage_path)
		check(saved.coins == scene.store.coins and saved.first_clears.has(stage_id) and saved.active_run.is_empty(), "displayed result is already durable for " + stage_id)
		var before_coins: int = scene.store.coins
		var before_clears: int = scene.store.clears
		scene._on_finished(true, 9999)
		scene._ui_action("retry_settlement")
		check(scene.store.coins == before_coins and scene.store.clears == before_clears, "repeat finish and claim actions cannot duplicate " + stage_id)
		if stage_id == "outskirts":
			check(scene.store.unlocked_stages.has("corridor") and scene.store.unlocked_skills().has("ultimate") and scene.store.level > 0, "first result unlocks next encounter ultimate and earned level")
		if not str(stage_data.first_unlock).is_empty():
			scene._ui_action("next_stage")
			check(scene.mode == "play" and scene.model.has_skill("ultimate"), "next-stage action uses newly unlocked loadout")
			check(not scene.campaign_ui._root.visible, "next-stage keeps battle visible and unobstructed")
	check(scene.store.first_clears.size() == 3 and scene.store.inventory.size() == 9 and scene.store.clears == 3, "one full actual-scene chapter owns all three deterministic rewards")
	scene._ui_action("page", {"page": "prepare"})
	scene._ui_action("equip", {"uid": "starter_cautious_blade"})
	check(scene.mode == "prepare" and scene.store.equipped_item("weapon").id == "cautious_blade", "result can return to preparation and change actual equipment")
	var coins_before_practice: int = scene.store.coins
	scene._ui_action("practice")
	check(scene.mode == "play" and not scene.campaign_ui._root.visible and scene.store.active_run.is_empty(), "practice hides the campaign overlay without creating a reward-bearing run")
	scene._on_finished(false, 0)
	check(scene.mode == "prepare" and scene.store.coins == coins_before_practice, "leaving practice returns to preparation without rewards")

func _test_pause_and_failure_retry(scene: Node2D) -> void:
	scene._ui_action("start_stage", {"stage": "core"})
	check(_reach_wave(scene, 2) and scene.store.active_run.wave == 1, "last encounter has a persisted safe checkpoint")
	var touch := InputEventScreenTouch.new()
	touch.index = 7
	touch.position = scene.ATTACK_CENTER
	touch.pressed = true
	scene._unhandled_input(touch)
	var emulated_mouse := InputEventMouseButton.new()
	emulated_mouse.device = InputEvent.DEVICE_ID_EMULATION
	emulated_mouse.button_index = MOUSE_BUTTON_LEFT
	emulated_mouse.position = scene.ATTACK_CENTER
	emulated_mouse.pressed = true
	scene._unhandled_input(emulated_mouse)
	check(scene.touch_actions.has(7) and not scene.touch_actions.has(-1), "touch-generated mouse events cannot create a second held attack")
	scene.model.energy = 51.0
	scene.model.cooldowns.burst = 4.0
	scene.model.attack()
	scene.touch_actions[7] = "attack"
	scene.stick = Vector2.ONE
	scene.pending_skill = "dash"
	scene.pending_skill_time = 0.5
	scene.model.hitstop = 0.4
	var elapsed: float = scene.model.elapsed
	var combat_time: float = scene.combat_time
	var wave_wait: float = scene.model.wave_wait
	var hazard_clock: float = scene.model.hazard_clock
	var cooldowns: Dictionary = scene.model.cooldowns.duplicate(true)
	var pending_hits: Array = scene.model.pending_hits.duplicate(true)
	var player_pose_time: float = scene.model.player.pose_time
	scene._pause()
	check(scene.mode == "pause" and scene.touch_actions.is_empty() and scene.stick == Vector2.ZERO and scene.pending_skill.is_empty(), "pause clears held touches movement and buffered actions")
	_advance(scene, 3.0)
	check(scene.model.elapsed == elapsed and scene.combat_time == combat_time and scene.model.energy == 51.0 and scene.model.cooldowns == cooldowns, "pause freezes elapsed combat time energy and cooldowns")
	check(scene.model.pending_hits == pending_hits and scene.model.hitstop == 0.4 and scene.model.wave_wait == wave_wait and scene.model.hazard_clock == hazard_clock and scene.model.player.pose_time == player_pose_time, "pause freezes queued impacts hitstop encounter hazard and pose clocks")
	scene._ui_action("resume")
	check(scene.mode == "play" and scene.pending_skill.is_empty() and scene.touch_actions.is_empty(), "resume continues without replaying stale touches")
	check(not scene.campaign_ui._root.visible, "resume hides the campaign overlay")
	scene.touch_actions[8] = "attack"
	scene.stick = Vector2.RIGHT
	scene.pending_skill = "burst"
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	elapsed = scene.model.elapsed
	_advance(scene, 2.0)
	check(scene.mode == "pause" and scene.model.elapsed == elapsed and scene.touch_actions.is_empty() and scene.stick == Vector2.ZERO and scene.pending_skill.is_empty(), "application focus loss pauses and clears old input")
	scene._ui_action("resume")
	var run_id: String = scene.store.active_run.id
	var run_seed: int = scene.store.active_run.seed
	var coins_before: int = scene.store.coins
	var inventory_before: Array = scene.store.inventory.duplicate(true)
	scene.model.hitstop = 0.0
	scene.model.player.hp = 0.0
	scene._process(0.02)
	check(scene.mode == "result" and not scene.won and scene.settlement.ok and scene.reward == 0, "actual death opens a zero-reward confirmed failure result")
	check(scene.store.coins == coins_before and scene.store.inventory == inventory_before and scene.last_run.wave == 1 and scene.store.active_run.is_empty(), "failure retains earned equipment money and checkpoint for retry")
	scene._ui_action("retry_checkpoint")
	check(scene.mode == "play" and scene.model.stage_id == "core" and scene.model.wave == 1 and scene.store.active_run.wave == 1, "failure retry reconstructs the saved encounter")
	check(not scene.campaign_ui._root.visible, "checkpoint retry does not obscure running battle")
	check(scene.store.active_run.id != run_id and scene.store.active_run.seed == run_seed and scene.model.run_seed == run_seed, "failure retry uses the same seed with a fresh settlement identity")
	check(scene.model.player.hp == scene.model.player.max_hp and scene.model.energy == 100.0 and scene.model.cooldowns.ultimate == 0 and scene.model.pending_hits.is_empty(), "checkpoint retry restores full resources and clears previous combat objects")
	scene._ui_action("abandon")
	check(scene.mode == "prepare" and scene.store.active_run.is_empty() and scene.store.coins == coins_before, "confirmed abandon returns to preparation and banks no room rewards")

func _test_quit_and_reload() -> void:
	var original := _scene("resume")
	original._ui_action("begin")
	original._ui_action("start_stage", {"stage": "outskirts"})
	check(_reach_wave(original, 2) and original.store.active_run.wave == 1, "reload test reaches and saves second encounter")
	var run_before: Dictionary = original.store.active_run.duplicate(true)
	var previous_store: SaveStore = original.store
	original.model.player.hp = 10.0
	original.model.energy = 4.0
	# Destroy the scene without settlement, as on an application close or crash.
	scenes.erase(original)
	original.free()
	var restored := _scene("resume")
	var recovered_run: Dictionary = restored.store.active_run
	check(restored.store != previous_store and recovered_run.id == run_before.id and recovered_run.stage == run_before.stage and int(recovered_run.seed) == int(run_before.seed) and int(recovered_run.wave) == int(run_before.wave) and restored.mode == "menu", "independent scene/store reopens the durable active run")
	restored._ui_action("continue")
	check(restored.mode == "play" and restored.model.stage_id == "outskirts" and restored.model.wave == 1 and restored.model.run_seed == int(run_before.seed), "continue restores stage seed and safe encounter")
	check(not restored.campaign_ui._root.visible, "continue hides the campaign overlay")
	check(restored.store.active_run.id == run_before.id and restored.model.player.hp == restored.model.player.max_hp and restored.model.energy == 100.0 and restored.model.bonus_coins == 0, "crash recovery retains transaction ID and rebuilds resources and unbanked room loot together")
	check(_finish(restored) and restored.settlement.ok and restored.store.clears == 1, "recovered encounter can finish and bank exactly one clear")

func _test_pending_settlement() -> void:
	var scene := _scene("pending")
	scene._ui_action("begin")
	scene._ui_action("start_stage", {"stage": "outskirts"})
	check(_reach_wave(scene, 2), "save-failure test reaches final encounter with valid checkpoint")
	var run_before: Dictionary = scene.store.active_run.duplicate(true)
	var valid_path: String = scene.store.storage_path
	scene.store.storage_path = test_directory + "/missing-parent/progress.json"
	check(_finish(scene) and scene.mode == "result" and scene.settlement_pending and not scene.settlement.ok, "failed filesystem write leaves result explicitly pending")
	check(scene.store.coins == 0 and scene.store.level == 0 and scene.store.inventory.size() == 6 and scene.store.active_run == run_before and scene.reward == 0, "pending result never presents or banks unconfirmed rewards")
	for action in ["page", "abandon", "start_stage", "continue"]:
		var payload := {"page": "prepare", "stage": "outskirts"}
		scene._ui_action(action, payload)
		check(scene.mode == "result" and scene.settlement_pending and scene.store.active_run == run_before, "pending reward cannot be abandoned through " + action)
	scene.store.storage_path = valid_path
	scene._ui_action("retry_settlement")
	check(scene.mode == "result" and not scene.settlement_pending and scene.settlement.ok and scene.store.coins == 105 and scene.store.level == 1 and scene.store.active_run.is_empty(), "retry after storage recovery commits pending reward atomically")
	var coins_before: int = scene.store.coins
	scene._ui_action("retry_settlement")
	scene._on_finished(true, 9999)
	check(scene.store.coins == coins_before and scene.store.inventory.size() == 7 and scene.store.clears == 1, "repeat callbacks after recovered settlement remain exactly once")
	var confirmed := Store.new()
	confirmed.load_progress(valid_path)
	check(confirmed.coins == 105 and confirmed.first_clears.has("outskirts") and confirmed.active_run.is_empty(), "recovered pending result was actually saved before display")

func _test_checkpoint_write_failure() -> void:
	var scene := _scene("checkpoint-failure")
	scene._ui_action("begin")
	scene._ui_action("start_stage", {"stage": "outskirts"})
	check(_reach_wave(scene, 1), "checkpoint-failure test starts first encounter")
	var valid_path: String = scene.store.storage_path
	scene.store.storage_path = test_directory + "/missing-parent/progress.json"
	for index in range(300):
		for enemy in scene.model.enemies:
			enemy.hp = 0.0
		scene._process(0.02)
		if scene.mode == "pause":
			break
	check(scene.mode == "pause" and scene.pending_checkpoint == 1 and scene.store.active_run.wave == 0 and scene.model.wave == 2, "failed upcoming checkpoint pauses and remembers the unsaved encounter index")
	var elapsed: float = scene.model.elapsed
	scene._ui_action("resume")
	_advance(scene, 1.0)
	check(scene.mode == "pause" and scene.pending_checkpoint == 1 and scene.model.elapsed == elapsed, "failed checkpoint retry cannot resume combat or advance clocks")
	scene.store.storage_path = valid_path
	scene._ui_action("resume")
	check(scene.mode == "play" and scene.pending_checkpoint == -1 and scene.store.active_run.wave == 1 and not scene.campaign_ui._root.visible, "storage recovery saves the upcoming checkpoint before resume")
	var readback := Store.new()
	readback.load_progress(valid_path)
	check(int(readback.active_run.wave) == 1, "resumed checkpoint is actually durable")
	scene._ui_action("abandon")

func _test_pending_loss() -> void:
	var scene := _scene("pending-loss")
	scene._ui_action("begin")
	scene._ui_action("start_stage", {"stage": "outskirts"})
	var valid_path: String = scene.store.storage_path
	scene.store.storage_path = test_directory + "/missing-parent/progress.json"
	scene.model.player.hp = 0.0
	scene._process(0.02)
	check(scene.mode == "result" and not scene.won and scene.settlement_pending and scene.store.coins == 0, "failure-result write error remains pending without losing prior resources")
	var controls: Dictionary = scene.campaign_ui.action_controls
	check(controls.has("retry_settlement") and not controls.retry_settlement.disabled and controls.prepare.disabled, "pending failure exposes a usable save-retry action and disables leaving")
	scene._ui_action("abandon")
	check(scene.mode == "result" and scene.settlement_pending, "unsaved failure cannot bypass its settlement transaction")
	scene.store.storage_path = valid_path
	scene._ui_action("retry_settlement")
	check(scene.mode == "result" and not scene.settlement_pending and scene.settlement.ok and scene.store.active_run.is_empty() and scene.store.coins == 0, "storage recovery confirms failure outcome and closes run without rewards")
	scene._ui_action("retry_checkpoint")
	check(scene.mode == "play" and scene.model.energy == 100.0 and not scene.campaign_ui._root.visible, "confirmed recovered failure permits a full-resource retry")

func _cleanup() -> void:
	for scene in scenes:
		if is_instance_valid(scene):
			scene.free()
	scenes.clear()
	var directory := DirAccess.open(test_directory)
	for filename in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory + "/" + filename))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_directory))
