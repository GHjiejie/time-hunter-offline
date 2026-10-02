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
	var progress := clampf(fighter.pose_time / maxf(fighter.pose_duration, 0.001), 0.0, 1.0)
	var frame := frame_for_pose(pose, fighter.pose_time, clock, progress)
	var motion := _pose_motion(pose, progress, clock, fighter.moving)
	var modulate := Color.WHITE
	if fighter.invincible > 0.0:
		modulate.a = 0.68 + 0.32 * absf(sin(clock * 35.0))
	if pose == "hurt":
		modulate = Color(1.0, 0.72, 0.74, modulate.a)
	var origin := fighter.pos - Vector2(0.0, fighter.height) + base_offset
	origin += Vector2(motion.x * fighter.facing, motion.y)
	_draw_frame(canvas, texture, frame, origin, fighter.facing, motion.z * fighter.facing, Vector2(motion.w, 2.0 - motion.w), size, modulate, options)
	canvas.draw_set_transform(base_offset)


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
			return 4 if progress < 0.38 else 5
		"slash_2":
			return 5 if progress < 0.4 else 4
		"slash_3":
			return 4 if progress < 0.26 else 5
		"dash":
			return 6
		"burst":
			if pose_time < 0.16:
				return 7
			if pose_time < 0.38:
				return 4
			if pose_time < 0.68:
				return 5
			return 4
		"ultimate":
			if pose_time < 0.44:
				return 7
			if pose_time < 0.66:
				return 4
			if pose_time < 0.9:
				return 5
			if pose_time < 1.28:
				return 4
			return 5
		"hurt":
			return 1
	return int(clock * 1.6) % 2


static func _pose_motion(pose: String, progress: float, clock: float, moving: float) -> Vector4:
	# x/y are foot offsets, z is rotation, w is horizontal squash.
	var idle_breath := sin(clock * 2.6)
	var result := Vector4(0.0, -idle_breath * 0.6, idle_breath * 0.003, 1.0 + idle_breath * 0.002)
	match pose:
		"run":
			var stride := sin(clock * 22.0)
			result = Vector4(stride * 0.9 * moving, -absf(stride) * 2.0 * moving, 0.025 + stride * 0.012, 1.0)
		"slash_1", "slash_2", "slash_3":
			var force := sin(clampf((progress - 0.15) * 1.25, 0.0, 1.0) * PI)
			var anticipation := maxf(0.0, 1.0 - progress / 0.2)
			result = Vector4(force * 7.0 - anticipation * 3.0, anticipation * 1.0, force * 0.045 - anticipation * 0.025, 1.0 + force * 0.025)
		"dash":
			result = Vector4(4.0, -1.0, 0.018, 1.035)
		"burst":
			result = Vector4(0.0, -sin(progress * PI) * 4.0, sin(progress * TAU) * 0.015, 1.0)
		"ultimate":
			result = Vector4(0.0, -sin(progress * PI) * 7.0, sin(progress * TAU) * 0.015, 1.0)
		"hurt":
			result = Vector4(-sin(progress * PI) * 4.0, 0.0, -sin(progress * PI) * 0.05, 0.98)
	return result


static func _draw_frame(canvas: Node2D, texture: Texture2D, frame: int, origin: Vector2, facing: float, rotation: float, stretch: Vector2, height_pixels: float, modulate: Color, options: Dictionary) -> void:
	frame = clampi(frame, 0, FRAME_COUNT - 1)
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
	var body_height: float = options.get("source_body_height", DEFAULT_BODY_HEIGHT)
	var scale := height_pixels / maxf(body_height, 1.0)
	canvas.draw_set_transform(origin, rotation, Vector2(-1.0 if facing < 0.0 else 1.0, 1.0) * stretch)
	canvas.draw_texture_rect_region(texture, Rect2(-feet * scale, rect.size * scale), rect, modulate, false)


static func _get_atlas() -> Texture2D:
	if _atlas != null:
		return _atlas
	if ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH) as Texture2D
	if _atlas == null and not _reported_missing:
		push_warning("刃锋角色图集未找到：" + ATLAS_PATH)
		_reported_missing = true
	return _atlas
