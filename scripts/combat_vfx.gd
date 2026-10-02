class_name CombatVFX
extends RefCounted

const ICE := Color("b9faff")
const CRESCENT := preload("res://assets/effects/energy-crescent.png")

static func draw_effect(canvas: Node2D, effect: Dictionary, clock: float, offset: Vector2) -> void:
	var ratio := clampf(float(effect.life) / float(effect.max), 0.0, 1.0)
	var progress := 1.0 - ratio
	var color: Color = effect.color
	color.a = ratio
	var pos: Vector2 = effect.pos
	var height: float = effect.get("height", 0.0)
	var face: float = effect.get("face", 1.0)
	var size: float = effect.get("size", 125.0)
	var stage: int = effect.get("stage", 1)
	match effect.kind:
		"slash":
			canvas.draw_set_transform(pos - Vector2(0, 76 + height) + offset, -0.32 if stage == 3 else 0.0, Vector2(face, 0.72))
			var radius := size * (0.66 + progress * 0.22)
			var tilt := -0.45 if stage == 2 else 0.18
			_texture_crescent(canvas, radius, ratio * 0.66, Color.WHITE)
			_crescent(canvas, radius, tilt - 1.25, tilt + 1.25, 19.0 * ratio + 2.0, color)
			canvas.draw_arc(Vector2.ZERO, radius * 0.93, tilt - 1.08, tilt + 1.08, 40, Color(0.88, 1, 1, ratio), 2.5, true)
			if stage == 3:
				_crescent(canvas, radius * 0.82, -1.9, 1.0, 11.0 * ratio, Color(0.65, 0.75, 1, ratio * 0.5))
		"dash":
			var end: Vector2 = effect.end
			var travel := clampf((float(effect.max) - float(effect.life)) / float(effect.get("duration", 0.30)), 0.0, 1.0)
			end = pos.lerp(end, 1.0 - pow(1.0 - travel, 2.0))
			var origin := pos - Vector2(0, 68 + height)
			var target := end - Vector2(0, 68 + height)
			canvas.draw_set_transform(offset)
			canvas.draw_line(origin, target, Color(color.r, color.g, color.b, ratio * 0.14), 43.0 * ratio, true)
			canvas.draw_line(origin, target, Color(color.r, color.g, color.b, ratio * 0.75), 9.0 * ratio + 1.0, true)
			canvas.draw_line(origin, target, Color(0.88, 1, 1, ratio), 2.0, true)
			for index in range(8):
				var p := origin.lerp(target, float(index) / 8.0)
				var y := sin(index * 1.9) * 30.0
				canvas.draw_line(p + Vector2(-face * 32, y), p + Vector2(face * 12, y), Color(color.r, color.g, color.b, ratio * 0.55), 1.3, true)
		"rift_charge", "ultimate_charge":
			var ultimate: bool = effect.kind == "ultimate_charge"
			canvas.draw_set_transform(pos + offset, 0, Vector2(1, 0.28))
			var radius := (110.0 if ultimate else 75.0) * (1.1 - progress * 0.45)
			_rune_ring(canvas, radius, clock * 2.0, color, progress)
			canvas.draw_set_transform(pos - Vector2(0, 84 + height) + offset)
			for index in range(9):
				var a := index * TAU / 9.0 + clock
				var outer := Vector2.from_angle(a) * (105.0 * (1.0 - progress) + 14.0)
				canvas.draw_line(outer, outer * 0.7, Color(color.r, color.g, color.b, progress * 0.8), 2.0, true)
			canvas.draw_circle(Vector2.ZERO, 6.0 + progress * 13.0, Color(1, 0.9, 0.65, progress * 0.7))
		"rift":
			canvas.draw_set_transform(pos + offset, 0, Vector2(1, 0.29))
			_rune_ring(canvas, size * (0.45 + progress * 0.5), clock * 0.8, Color(color.r, color.g, color.b, ratio * 0.65), 1.0)
			canvas.draw_set_transform(pos - Vector2(0, 83 + height) + offset, (-0.45 if stage % 2 == 0 else 0.35) * face, Vector2(face, 0.62))
			var radius := size * (0.55 + progress * 0.36)
			_texture_crescent(canvas, radius, ratio * (0.7 if stage == 3 else 0.44), Color(0.94, 0.75, 1.0))
			_crescent(canvas, radius, -2.5, 1.2, (26.0 if stage == 3 else 17.0) * ratio, color)
			_crescent(canvas, radius * 0.81, -2.3, 1.0, 8.0 * ratio, Color(0.75, 0.95, 1, ratio * 0.7))
			if stage == 3:
				canvas.draw_line(Vector2(-radius, 0), Vector2(radius, 0), Color(0.92, 0.87, 1, ratio), 4.0 * ratio, true)
		"ultimate":
			var heavy := stage == 4
			canvas.draw_set_transform(pos - Vector2(0, 89 + height) + offset)
			var radius := size * (0.77 + progress * 0.28)
			var angle := (-0.25 if stage % 2 == 0 else 0.25) * face
			var direction := Vector2.from_angle(angle)
			var line_start := -direction * radius
			var line_end := direction * radius
			canvas.draw_line(line_start, line_end, Color(color.r, color.g, color.b, ratio * 0.13), (64.0 if heavy else 30.0) * ratio, true)
			canvas.draw_line(line_start, line_end, color, (17.0 if heavy else 8.0) * ratio + 1.0, true)
			canvas.draw_line(line_start, line_end, Color(1, 1, 0.92, ratio), 3.5 * ratio, true)
			if heavy:
				canvas.draw_set_transform(pos - Vector2(0, 89 + height) + offset, angle, Vector2(face, 0.65))
				_texture_crescent(canvas, radius * 0.85, ratio * 0.48, Color(1, 0.92, 0.72))
				canvas.draw_set_transform(pos - Vector2(0, 89 + height) + offset)
				var cross := Vector2.from_angle(-angle - 0.35)
				canvas.draw_line(-cross * radius * 0.8, cross * radius * 0.8, Color(0.55, 0.9, 1, ratio * 0.6), 10.0 * ratio, true)
				canvas.draw_set_transform(pos + offset, 0, Vector2(1, 0.32))
				_rune_ring(canvas, size * (0.25 + progress * 0.7), clock, color, 1.0)
		"hit":
			canvas.draw_set_transform(pos + offset, progress * 0.12)
			var radius := size * (0.3 + progress * 0.65)
			canvas.draw_arc(Vector2.ZERO, radius, 0, TAU, 30, Color(color.r, color.g, color.b, ratio * 0.7), 2.0, true)
			for index in range(8):
				var direction := Vector2.from_angle(index * TAU / 8.0 + 0.18)
				canvas.draw_line(direction * radius * 0.25, direction * radius, Color(1, 0.98, 0.84, ratio), (3.0 if index % 2 == 0 else 1.5) * ratio, true)
			canvas.draw_circle(Vector2.ZERO, 5.0 * ratio, Color(1, 1, 1, ratio))
		"shock":
			canvas.draw_set_transform(pos + offset, 0, Vector2(1, 0.45))
			canvas.draw_arc(Vector2.ZERO, 125.0 * (0.3 + progress * 0.7), 0, TAU, 48, color, 7.0 * ratio + 1.0, true)
	canvas.draw_set_transform(offset)

static func _texture_crescent(canvas: Node2D, radius: float, opacity: float, tint: Color) -> void:
	var extent := radius * 2.6
	tint.a = opacity
	canvas.draw_texture_rect(CRESCENT, Rect2(Vector2.ONE * -extent * 0.5, Vector2.ONE * extent), false, tint)

static func _crescent(canvas: Node2D, radius: float, first: float, last: float, thickness: float, color: Color) -> void:
	# Small convex strips stay valid as a tapered crescent fades to nothing.
	# A single long, thin concave polygon can fail the renderer triangulator.
	if thickness > 0.5:
		for index in range(24):
			var t0 := float(index) / 24.0
			var t1 := float(index + 1) / 24.0
			var a0 := Vector2.from_angle(lerpf(first, last, t0))
			var a1 := Vector2.from_angle(lerpf(first, last, t1))
			var width0 := maxf(0.35, thickness * sin(t0 * PI))
			var width1 := maxf(0.35, thickness * sin(t1 * PI))
			canvas.draw_colored_polygon(PackedVector2Array([a0 * radius, a1 * radius, a1 * (radius - width1), a0 * (radius - width0)]), Color(color.r, color.g, color.b, color.a * 0.26))
	canvas.draw_arc(Vector2.ZERO, radius, first, last, 40, color, maxf(1.0, thickness * 0.38), true)
	canvas.draw_arc(Vector2.ZERO, radius + 4.0, first + 0.15, last - 0.15, 40, Color(color.r, color.g, color.b, color.a * 0.35), 2, true)

static func _rune_ring(canvas: Node2D, radius: float, angle: float, color: Color, strength: float) -> void:
	canvas.draw_arc(Vector2.ZERO, radius, 0, TAU, 64, color, 3.0, true)
	canvas.draw_arc(Vector2.ZERO, radius * 0.82, angle, angle + PI * 1.6, 56, Color(color.r, color.g, color.b, color.a * 0.4), 2, true)
	for index in range(12):
		var direction := Vector2.from_angle(index * TAU / 12.0 + angle)
		canvas.draw_line(direction * radius * 0.87, direction * radius * (1.02 + strength * 0.05), color, 2, true)
