class_name HeroRenderer
extends RefCounted

## The atlas is drawn around the feet, so jumps and mirrored poses keep the
## same ground contact point. Per-frame feet can be tuned without editing art.
const ATLAS_PATH := "res://assets/characters/renfeng-combat-atlas.png"
const DEFAULT_BODY_HEIGHT := 420.0
const FRAME_COUNT := 8
const FRAME_REGIONS := [
	Rect2(0, 0, 384, 512), Rect2(384, 0, 384, 512),
	Rect2(768, 0, 372, 512), Rect2(1140, 0, 396, 512),
	Rect2(0, 512, 384, 512), Rect2(384, 512, 372, 512),
	Rect2(756, 512, 396, 512), Rect2(1152, 512, 384, 512),
]
const FRAME_FEET := [
	Vector2(174, 501), Vector2(200, 501),
	Vector2(196, 493), Vector2(221, 488),
	Vector2(187, 454), Vector2(188, 453),
	Vector2(162, 440), Vector2(202, 454),
]
# Atlas-local grip, blade root and tip positions. These stay attached to the
# painted weapon through feet alignment, facing, body recoil and camera motion.
const FRAME_HANDS := [
	Vector2(80, 295), Vector2(101, 307),
	Vector2(87, 257), Vector2(90, 260),
	Vector2(219, 158), Vector2(112, 112),
	Vector2(307, 286), Vector2(146, 52),
]
const FRAME_BLADE_ROOTS := [
	Vector2(106, 309), Vector2(126, 322),
	Vector2(79, 277), Vector2(88, 278),
	Vector2(241, 151), Vector2(137, 99),
	Vector2(326, 301), Vector2(167, 57),
]
const FRAME_BLADE_TIPS := [
	Vector2(237, 430), Vector2(255, 444),
	Vector2(14, 332), Vector2(20, 335),
	Vector2(347, 95), Vector2(293, 37),
	Vector2(389, 447), Vector2(352, 125),
]
# Seconds from action start, matching ArenaModel's queued damage events. The
# renderer never creates hits; this table only aligns pose changes and VFX.
const RELEASE_TIMES := {
	"slash_1": [0.055], "slash_2": [0.075], "slash_3": [0.13],
	"burst": [0.16, 0.38, 0.68],
	"ultimate": [0.44, 0.66, 0.90, 1.28],
}

static var _atlas: Texture2D
static var _reported_missing := false


static func draw_hero(canvas: Node2D, fighter: Fighter, clock: float, options: Dictionary = {}) -> void:
	if fighter.hp <= 0.0:
		return
	var texture := _get_atlas()
	if texture == null:
		return
	var base_offset: Vector2 = options.get("base_offset", Vector2.ZERO)
	var size: float = options.get("height_pixels", 154.0)
	if options.get("draw_shadow", true):
		var shadow_size := maxf(0.58, 1.0 - fighter.height / 420.0)
		canvas.draw_set_transform(fighter.pos + base_offset, 0.0, Vector2(shadow_size, shadow_size * 0.28))
		canvas.draw_circle(Vector2.ZERO, size * 0.21, Color(0.01, 0.02, 0.035, 0.34))
		canvas.draw_circle(Vector2.ZERO, size * 0.12, Color(0.01, 0.02, 0.035, 0.12))
	var pose: String = fighter.pose
	var state := _pose_state(fighter, clock, options)
	var modulate := Color.WHITE
	if fighter.invincible > 0.0:
		modulate.a = 0.68 + 0.32 * absf(sin(clock * 35.0))
	if pose == "hurt":
		modulate = Color(1.0, 0.72, 0.74, modulate.a)
	_draw_frame(canvas, texture, state.frame, state.origin, fighter.facing, state.rotation, state.stretch, size, modulate, options)
	canvas.draw_set_transform(base_offset)


static func blade_anchors(fighter: Fighter, clock: float, options: Dictionary = {}) -> Dictionary:
	var state := _pose_state(fighter, clock, options)
	var frame: int = state.frame
	var geometry := _frame_geometry(frame, options)
	var feet: Vector2 = geometry.feet
	var size: float = options.get("height_pixels", 154.0)
	var body_height: float = options.get("source_body_height", DEFAULT_BODY_HEIGHT)
	var scale := size / maxf(body_height, 1.0)
	var mirror := Vector2(-1.0 if fighter.facing < 0.0 else 1.0, 1.0)
	var transform_scale: Vector2 = mirror * state.stretch
	var hand_local: Vector2 = (FRAME_HANDS[frame] - feet) * scale * transform_scale
	var root_local: Vector2 = (FRAME_BLADE_ROOTS[frame] - feet) * scale * transform_scale
	var tip_local: Vector2 = (FRAME_BLADE_TIPS[frame] - feet) * scale * transform_scale
	return {
		"hand": state.origin + hand_local.rotated(state.rotation),
		"root": state.origin + root_local.rotated(state.rotation),
		"tip": state.origin + tip_local.rotated(state.rotation),
		"frame": frame,
	}


static func draw_ghost(canvas: Node2D, world_pos: Vector2, facing: float, clock: float, opacity: float = 0.28, options: Dictionary = {}) -> void:
	var texture := _get_atlas()
	if texture == null or opacity <= 0.0:
		return
	var base_offset: Vector2 = options.get("base_offset", Vector2.ZERO)
	var frame: int = options.get("frame", 6)
	var airborne_height: float = options.get("height", 0.0)
	var color: Color = options.get("color", Color(0.46, 0.9, 1.0))
	color.a = clampf(opacity, 0.0, 1.0)
	var size: float = options.get("height_pixels", 154.0)
	var ghost_tilt: float = options.get("tilt", 0.025 * sin(clock * 13.0))
	_draw_frame(canvas, texture, frame, world_pos - Vector2(0.0, airborne_height) + base_offset, facing, ghost_tilt * facing, Vector2.ONE, size, color, options)
	canvas.draw_set_transform(base_offset)


static func frame_for_pose(pose: String, pose_time: float, clock: float, progress: float = 0.0) -> int:
	match pose:
		"run":
			return 2 + (int(pose_time * 11.0) % 2)
		"slash_1":
			if progress > 0.84:
				return 1
			return 5 if pose_time < RELEASE_TIMES.slash_1[0] else 4
		"slash_2":
			if progress > 0.84:
				return 1
			return 4 if pose_time < RELEASE_TIMES.slash_2[0] else 5
		"slash_3":
			if progress > 0.86:
				return 1
			return 7 if pose_time < RELEASE_TIMES.slash_3[0] else 4
		"dash":
			return 6
		"burst":
			if pose_time < RELEASE_TIMES.burst[0]:
				return 7
			if pose_time < RELEASE_TIMES.burst[1]:
				return 4
			if pose_time < 0.58:
				return 5
			if pose_time < RELEASE_TIMES.burst[2]:
				return 7
			return 4 if pose_time < 0.82 else 1
		"ultimate":
			if pose_time < RELEASE_TIMES.ultimate[0]:
				return 7
			if pose_time < RELEASE_TIMES.ultimate[1]:
				return 4
			if pose_time < RELEASE_TIMES.ultimate[2]:
				return 5
			if pose_time < 1.08:
				return 4
			if pose_time < RELEASE_TIMES.ultimate[3]:
				return 7
			return 6 if pose_time < 1.50 else 1
		"hurt":
			return 1
	return int(clock * 1.6) % 2


static func _pose_state(fighter: Fighter, clock: float, options: Dictionary) -> Dictionary:
	var progress := clampf(fighter.pose_time / maxf(fighter.pose_duration, 0.001), 0.0, 1.0)
	var frame := frame_for_pose(fighter.pose, fighter.pose_time, clock, progress)
	var motion := _pose_motion(fighter.pose, fighter.pose_time, fighter.pose_duration, progress, clock, fighter.moving)
	var base_offset: Vector2 = options.get("base_offset", Vector2.ZERO)
	var origin := fighter.pos - Vector2(0.0, fighter.height) + base_offset
	origin += Vector2(motion.x * fighter.facing, motion.y)
	return {"frame": frame, "origin": origin, "rotation": motion.z * fighter.facing, "stretch": Vector2(motion.w, 2.0 - motion.w)}


static func _pose_motion(pose: String, pose_time: float, duration: float, progress: float, clock: float, moving: float) -> Vector4:
	# x/y are foot offsets, z is rotation, w is horizontal squash.
	var idle_breath := sin(clock * 2.6)
	var result := Vector4(0.0, -idle_breath * 0.6, idle_breath * 0.003, 1.0 + idle_breath * 0.002)
	match pose:
		"run":
			var stride := sin(clock * 22.0)
			result = Vector4(stride * 0.9 * moving, -absf(stride) * 2.0 * moving, 0.025 + stride * 0.012, 1.0)
		"slash_1", "slash_2", "slash_3":
			var contact: float = RELEASE_TIMES[pose][0]
			var heavy := pose == "slash_3"
			var turn := -1.0 if pose == "slash_2" else 1.0
			result = _strike_motion(pose_time, 0.0, contact, duration * 0.86,
				Vector4(-4.0 if heavy else -2.6, 1.8, -0.028 * turn, 0.985),
				Vector4(10.0 if heavy else 7.0, -2.0, 0.055 * turn, 1.018))
		"dash":
			var glide := 1.0 - smoothstep(0.08, 0.30, pose_time)
			result = Vector4(5.0 * glide, -1.5 * glide, 0.024 * glide, 1.0 + 0.025 * glide)
		"burst":
			if pose_time < 0.30:
				result = _strike_motion(pose_time, 0.0, RELEASE_TIMES.burst[0], 0.30,
					Vector4(-2.5, 2.0, -0.025, 0.985), Vector4(6.0, -3.0, 0.045, 1.018))
			elif pose_time < 0.58:
				result = _strike_motion(pose_time, 0.30, RELEASE_TIMES.burst[1], 0.58,
					Vector4(-2.0, 1.0, 0.022, 0.99), Vector4(5.0, -4.0, -0.045, 1.015))
			else:
				result = _strike_motion(pose_time, 0.58, RELEASE_TIMES.burst[2], 0.86,
					Vector4(-4.0, 2.6, -0.04, 0.98), Vector4(9.0, -2.0, 0.065, 1.025))
		"ultimate":
			if pose_time < 0.56:
				result = _strike_motion(pose_time, 0.0, RELEASE_TIMES.ultimate[0], 0.56,
					Vector4(-3.0, 2.0, -0.025, 0.982), Vector4(6.0, -3.0, 0.04, 1.016))
			elif pose_time < 0.80:
				result = _strike_motion(pose_time, 0.56, RELEASE_TIMES.ultimate[1], 0.80,
					Vector4(-2.0, 1.0, 0.02, 0.99), Vector4(6.0, -4.0, -0.045, 1.018))
			elif pose_time < 1.08:
				result = _strike_motion(pose_time, 0.80, RELEASE_TIMES.ultimate[2], 1.08,
					Vector4(-2.0, 1.0, -0.02, 0.99), Vector4(7.0, -3.0, 0.045, 1.018))
			else:
				result = _strike_motion(pose_time, 1.08, RELEASE_TIMES.ultimate[3], 1.54,
					Vector4(-4.0, 3.0, -0.04, 0.975), Vector4(10.0, 1.0, 0.045, 1.03))
		"hurt":
			result = Vector4(-sin(progress * PI) * 4.0, 0.0, -sin(progress * PI) * 0.05, 0.98)
	return result


static func _strike_motion(time: float, start: float, contact: float, settle: float, windup: Vector4, release: Vector4) -> Vector4:
	var neutral := Vector4(0.0, 0.0, 0.0, 1.0)
	if time < contact:
		return neutral.lerp(windup, smoothstep(start, contact, time))
	# Release is sharp on the damage event, then settles with a soft tail. A
	# short hold preserves the silhouette during the confirmed-hit freeze.
	return release.lerp(neutral, smoothstep(contact + 0.028, settle, time))


static func _draw_frame(canvas: Node2D, texture: Texture2D, frame: int, origin: Vector2, facing: float, rotation: float, stretch: Vector2, height_pixels: float, modulate: Color, options: Dictionary) -> void:
	frame = clampi(frame, 0, FRAME_COUNT - 1)
	var geometry := _frame_geometry(frame, options)
	var rect: Rect2 = geometry.rect
	var feet: Vector2 = geometry.feet
	var body_height: float = options.get("source_body_height", DEFAULT_BODY_HEIGHT)
	var scale := height_pixels / maxf(body_height, 1.0)
	canvas.draw_set_transform(origin, rotation, Vector2(-1.0 if facing < 0.0 else 1.0, 1.0) * stretch)
	canvas.draw_texture_rect_region(texture, Rect2(-feet * scale, rect.size * scale), rect, modulate, false)


static func _frame_geometry(frame: int, options: Dictionary) -> Dictionary:
	var rect: Rect2 = FRAME_REGIONS[frame]
	var feet: Vector2 = FRAME_FEET[frame]
	var frame_rects = options.get("frame_rects", {})
	var frame_feet = options.get("frame_feet", {})
	if frame_rects is Dictionary and frame_rects.has(frame):
		rect = frame_rects[frame]
	elif frame_rects is Array and frame < frame_rects.size():
		rect = frame_rects[frame]
	if frame_feet is Dictionary and frame_feet.has(frame):
		feet = frame_feet[frame]
	elif frame_feet is Array and frame < frame_feet.size():
		feet = frame_feet[frame]
	return {"rect": rect, "feet": feet}


static func _get_atlas() -> Texture2D:
	if _atlas != null:
		return _atlas
	if ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH) as Texture2D
	if _atlas == null and not _reported_missing:
		push_warning("刃锋角色图集未找到：" + ATLAS_PATH)
		_reported_missing = true
	return _atlas
