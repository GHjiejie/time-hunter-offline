extends SceneTree

const Model := preload("res://scripts/arena_model.gd")
const TEST_PROGRESS := "user://skill-vfx-test-progress.json"

var checks := 0
var failures := 0
var scene: Node2D


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)


func target_at(model: ArenaModel, pos: Vector2) -> Fighter:
	var target := Fighter.new()
	target.id = model.enemies.size()
	target.kind = "boss"
	target.pos = pos
	target.hp = 10000.0
	target.max_hp = target.hp
	target.speed = 0.0
	target.attack_clock = 100.0
	model.enemies.append(target)
	return target


func fresh_model() -> ArenaModel:
	var model := Model.new()
	model.start(0, 8217)
	model.wave = Model.MAX_WAVES
	model.player.pos = Vector2(640, 420)
	return model


func run() -> void:
	test_visual_effects_are_harmless()
	test_events_at_low_frame_rates()
	test_whiff_feedback()
	test_dash_sweeps_both_facings()
	test_effect_expiry_and_reset()
	test_presentation_freezes()
	print("SKILL VFX CHECKS: %d / FAILED: %d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func test_visual_effects_are_harmless() -> void:
	var model := fresh_model()
	var target := target_at(model, model.player.pos)
	# Effect dictionaries are presentation data; they never open hit detection.
	for kind in ["slash", "dash", "rift_charge", "rift", "ultimate_charge", "ultimate", "hit", "shock"]:
		model._add_effect(kind, target.pos, 1.0, Color.WHITE, {"end": target.pos + Vector2(285, 0), "size": 470.0, "stage": 4})
	var health := target.hp
	var player_health: float = model.player.hp
	model.step(0.2, Vector2.ZERO)
	check(target.hp == health and model.player.hp == player_health, "rendered skill and impact effects do not cause damage")
	check(model.score == 0 and model.streak == 0 and model.pending_hits.is_empty(), "visual effects do not create gameplay events")
	check(model.effects.size() == 8, "unexpired presentation effects remain available to renderer")


func test_events_at_low_frame_rates() -> void:
	for skill_name in ["burst", "ultimate"]:
		for frame_delta in [1.0 / 60.0, 0.2, 1.7]:
			var model := fresh_model()
			var target := target_at(model, model.player.pos)
			var casts: Array[String] = []
			var target_hits: Array[float] = []
			var released_stages: Array[int] = []
			model.skill_cast.connect(func(name): casts.append(name))
			model.skill_released.connect(func(name, stage):
				if name == skill_name:
					released_stages.append(stage))
			model.impact.connect(func(_pos, _color, strength):
				if is_equal_approx(strength, 0.42) or is_equal_approx(strength, 0.9):
					target_hits.append(strength))
			check(model.skill(skill_name), "%s can be cast at test rate %.3f" % [skill_name, frame_delta])
			check(not model.skill(skill_name), "%s cannot charge resources twice in same action" % skill_name)
			check(model.energy == 100.0 - Model.SKILL_COST[skill_name], "%s charges the cost once" % skill_name)
			var run_time := 0.0
			while run_time < 2.6:
				# Keep a training target in reach; test stage scheduling, not knockback.
				target.pos = model.player.pos
				target.velocity = Vector2.ZERO
				model.step(frame_delta, Vector2.ZERO)
				run_time += frame_delta
			var expected_damage := 99.0 if skill_name == "burst" else 213.0
			var expected_hits := 3 if skill_name == "burst" else 4
			check(target.hp == 10000.0 - expected_damage, "%s events deal exact damage at %.3f s steps" % [skill_name, frame_delta])
			check(target_hits.size() == expected_hits, "%s each stage hits once at %.3f s steps" % [skill_name, frame_delta])
			check(model.pending_hits.is_empty() and casts == [skill_name], "%s resolves all crossed events once" % skill_name)
			var expected_stages := [1, 2, 3] if skill_name == "burst" else [1, 2, 3, 4]
			check(released_stages == expected_stages, "%s emits each release stage once in order at %.3f s steps" % [skill_name, frame_delta])
			var health := target.hp
			model.step(0.5, Vector2.ZERO)
			check(target.hp == health, "%s residual VFX never repeat damage" % skill_name)


func test_whiff_feedback() -> void:
	for skill_name in ["burst", "ultimate"]:
		var model := fresh_model()
		target_at(model, Vector2(Model.BOUNDS.end.x, model.player.pos.y))
		var impacts: Array[float] = []
		var releases: Array[int] = []
		model.impact.connect(func(_pos, _color, strength): impacts.append(strength))
		model.skill_released.connect(func(_name, stage): releases.append(stage))
		model.skill(skill_name)
		for frame in range(100):
			model.step(1.0 / 60.0, Vector2.ZERO)
		check(not releases.is_empty(), "%s whiff still plays scheduled release feedback" % skill_name)
		check(impacts.is_empty() and model.hitstop == 0.0 and model.score == 0, "%s whiff has no hit sparks, camera impact or hitstop" % skill_name)


func test_dash_sweeps_both_facings() -> void:
	for facing in [1.0, -1.0]:
		var model := fresh_model()
		model.player.facing = facing
		var start: Vector2 = model.player.pos
		var front := target_at(model, start + Vector2(facing * 160.0, 0))
		var behind := target_at(model, start - Vector2(facing * 90.0, 0))
		var wrong_lane := target_at(model, start + Vector2(facing * 160.0, -80.0))
		check(model.skill("dash"), "dash facing %.0f activates" % facing)
		model.step(0.30, Vector2.ZERO)
		check(is_equal_approx(model.player.pos.x, start.x + facing * 285.0) and model.player.pos.y == start.y, "dash facing %.0f sweeps full distance in one coarse step" % facing)
		check(front.hp == 9954.0 and behind.hp == 10000.0 and wrong_lane.hp == 10000.0, "dash facing %.0f hits crossed target once within lane" % facing)
		check((front.pos.x - start.x - facing * 160.0) * facing > 0.0, "dash facing %.0f knocks target along travel direction" % facing)
		for frame in range(60):
			model.step(1.0 / 60.0, Vector2.ZERO)
		check(front.hp == 9954.0 and model.active_dash.is_empty(), "dash facing %.0f finishes without residual collision damage" % facing)


func test_effect_expiry_and_reset() -> void:
	var model := fresh_model()
	target_at(model, model.player.pos + Vector2(500, 0))
	model._add_effect("rift", model.player.pos, 0.25, Color.WHITE, {"stage": 3})
	model.step(0.20, Vector2.ZERO)
	check(model.effects.size() == 1 and is_equal_approx(model.effects[0].life, 0.05), "effect lifetime uses simulation time")
	model.step(0.05, Vector2.ZERO)
	check(model.effects.is_empty(), "effect expires at the end of its lifetime")
	model.skill("ultimate")
	check(not model.effects.is_empty() and not model.pending_hits.is_empty(), "new cast owns telegraph and pending stages")
	model.start(0, 8217)
	check(model.effects.is_empty() and model.pending_hits.is_empty() and model.active_dash.is_empty() and model.dash_targets.is_empty(), "restart clears effects and hit bookkeeping")
	check(model.hitstop == 0.0 and model.player.pose == "idle", "restart resets animation and hitstop")


func test_presentation_freezes() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	scene.store.storage_path = TEST_PROGRESS
	scene.store.muted = true
	root.add_child(scene)
	scene.set_process(false)
	scene._start()
	scene.store.muted = true
	scene.model.wave = Model.MAX_WAVES
	target_at(scene.model, scene.model.player.pos + Vector2(500, 0))
	scene.model.skill("ultimate")
	scene.particles.append({"pos": Vector2(620, 330), "velocity": Vector2(80, -50), "life": 0.4, "color": Color.WHITE})
	scene.flash = 0.12
	scene.shake = 3.0
	var effects: Array[Dictionary] = scene.model.effects.duplicate(true)
	var particles: Array[Dictionary] = scene.particles.duplicate(true)
	var pose_time: float = scene.model.player.pose_time
	var clock: float = scene.combat_time
	var flash: float = scene.flash
	var shake: float = scene.shake
	scene._pause()
	for frame in range(12):
		scene._process(1.0 / 60.0)
	check(scene.model.effects == effects and scene.model.player.pose_time == pose_time and scene.combat_time == clock, "pause freezes effects and action clocks")
	check(scene.particles == particles and scene.flash == flash and scene.shake == shake, "pause freezes impact particles, flash and camera feedback")
	scene._menu_action("resume")
	scene.model.hitstop = 0.12
	scene._process(0.05)
	check(scene.model.effects == effects and scene.model.player.pose_time == pose_time and scene.combat_time == clock, "hitstop freezes effects and action clocks")
	check(scene.particles == particles and scene.flash == flash and scene.shake == shake, "hitstop freezes particles and camera feedback")
	scene.model.hitstop = 0.0
	scene._process(1.0 / 60.0)
	check(scene.model.player.pose_time > pose_time and scene.model.effects[0].life < effects[0].life, "resume continues cast from frozen phase")
	check(scene.particles[0].life < particles[0].life, "resume advances particle lifetime")
	scene._start()
	check(scene.particles.is_empty() and scene.flash == 0.0 and scene.shake == 0.0 and scene.combat_time == 0.0, "scene restart clears all presentation remnants")
	DirAccess.remove_absolute(TEST_PROGRESS)
	scene.queue_free()
