class_name CombatVFX
extends RefCounted

## Presentation only. Events own their world origin and lifetime.
## These shapes never change damage, collision, or skill timing.
const CRESCENT := preload("res://assets/effects/refraction-crescent.png")
const SILVER := Color("e5fcff")
const CYAN := Color("79e4f5")
const VIOLET := Color("bfa1f4")
const GOLD := Color("ffe3a6")
const PROFILES := {
	"slash": {"radius": [112.0, 128.0, 164.0], "angle": [-0.28, 0.28, -0.68], "flatness": [0.60, 0.62, 0.78]},
	"rift": {"radius": [228.0, 250.0, 282.0], "angle": [-0.32, 0.30, -0.18], "flatness": [0.48, 0.46, 0.52]},
}

static func draw_ground(canvas: Node2D, effect: Dictionary, offset: Vector2) -> void:
	if effect.kind not in ["rift_charge", "ultimate_charge", "rift", "ultimate"]:
		return
	var age := float(effect.max) - float(effect.life)
	var p := clampf(age / float(effect.max), 0.0, 1.0)
	var gold: bool = effect.kind == "ultimate_charge" or effect.kind == "ultimate"
	var color := GOLD if gold else VIOLET
	var release: bool = effect.kind == "rift" or effect.kind == "ultimate"
	var opacity := pow(1.0 - p, 2.0) * 0.36 if release else sin(p * PI) * 0.42
	var radius := (155.0 if gold else 95.0) * (0.76 + p * 0.35)
	canvas.draw_set_transform(effect.pos + offset, 0, Vector2(1.0, 0.22))
	# Broken perimeter stays below the fighters instead of over their bodies.
	for index in range(3):
		var start := index * TAU / 3.0 + p * 0.28
		canvas.draw_arc(Vector2.ZERO, radius, start, start + 1.28, 20, _alpha(color, opacity), 1.4, true)
		canvas.draw_arc(Vector2.ZERO, radius * 0.85, start + 0.3, start + 1.0, 14, _alpha(color, opacity * 0.35), 1.0, true)
	canvas.draw_set_transform(offset)

static func draw_effect(canvas: Node2D, effect: Dictionary, _clock: float, offset: Vector2) -> void:
	var age := maxf(0.0, float(effect.max) - float(effect.life))
	var p := clampf(age / float(effect.max), 0.0, 1.0)
	var fade := pow(1.0 - p, 1.65)
	var pos: Vector2 = effect.pos
	var height: float = effect.get("height", 0.0)
	var face: float = effect.get("face", 1.0)
	var stage: int = effect.get("stage", 1)
	var origin := pos - Vector2(0, 76 + height) + offset
	match effect.kind:
		"slash":
			var index := clampi(stage - 1, 0, 2)
			var profile: Dictionary = PROFILES.slash
			var radius: float = profile.radius[index]
			var angle: float = profile.angle[index] + (1.0 - exp(-age * 28.0)) * 0.22
			canvas.draw_set_transform(origin + Vector2(face * 10, -7), angle * face, Vector2(face, profile.flatness[index]))
			_sweep(canvas, radius * (0.83 + minf(age * 5.0, 0.19)), fade, Color.WHITE)
			_arc_filaments(canvas, radius, p, fade * 0.6, CYAN, 3 if stage == 3 else 2)
			_shards(canvas, radius, p, fade * 0.65, CYAN, 5 if stage == 3 else 3)
		"dash":
			_draw_dash(canvas, effect, age, p, fade, offset)
		"rift_charge", "ultimate_charge":
			_draw_charge(canvas, effect, p, offset)
		"rift":
			var index := clampi(stage - 1, 0, 2)
			var profile: Dictionary = PROFILES.rift
			var radius: float = profile.radius[index]
			var angle: float = profile.angle[index]
			var expand := 0.86 + minf(age * 4.0, 0.16)
			# Opposing crescents describe the existing two-sided ellipse attack.
			canvas.draw_set_transform(origin, angle * face, Vector2(face, profile.flatness[index]))
			_sweep(canvas, radius * expand, fade * 0.9, Color("d9bcff"))
			_arc_filaments(canvas, radius, p, fade * 0.55, VIOLET, 3)
			_shards(canvas, radius, p, fade * 0.85, VIOLET, 7)
			canvas.draw_set_transform(origin, -angle * face, Vector2(-face, profile.flatness[index] * 0.86))
			_sweep(canvas, radius * expand * 0.90, fade * 0.52, Color("aacfff"))
			if stage == 3:
				canvas.draw_set_transform(origin, -0.12 * face)
				_spatial_cut(canvas, radius * 1.02, 12.0, p, fade * 0.65, SILVER)
		"ultimate":
			_draw_ultimate(canvas, effect, origin, age, p, fade)
		"hit":
			_draw_hit(canvas, effect, p, fade, offset)
		"shock":
			canvas.draw_set_transform(pos + offset, 0, Vector2(1, 0.45))
			canvas.draw_arc(Vector2.ZERO, 125.0 * (0.3 + p * 0.7), 0, TAU, 48, _alpha(effect.color, fade), 7.0 * fade + 1.0, true)
	canvas.draw_set_transform(offset)

static func draw_blade_aura(canvas: Node2D, anchors: Dictionary, strength: float, color: Color, offset: Vector2) -> void:
	if strength <= 0.0:
		return
	var blade_root: Vector2 = anchors.root + offset
	var tip: Vector2 = anchors.tip + offset
	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_line(blade_root, tip, _alpha(color, strength * 0.10), 12.0, true)
	canvas.draw_line(blade_root, tip, _alpha(color, strength * 0.50), 3.0, true)
	canvas.draw_line(blade_root, tip, _alpha(SILVER, strength * 0.85), 1.0, true)
	_glint(canvas, tip, 6.0 + strength * 4.0, strength, color)
	canvas.draw_set_transform(offset)

static func draw_blade_trail(canvas: Node2D, samples: Array[Dictionary], clock: float, offset: Vector2) -> void:
	canvas.draw_set_transform(offset)
	for index in range(1, samples.size()):
		var previous: Dictionary = samples[index - 1]
		var sample: Dictionary = samples[index]
		var age := clock - float(sample.time)
		var alpha := clampf(1.0 - age / 0.10, 0.0, 1.0) * 0.12
		if alpha <= 0.0 or previous.tip.distance_to(sample.tip) < 0.3:
			continue
		# Two triangles remain valid even when the ribbon twists across a pose.
		canvas.draw_colored_polygon(PackedVector2Array([previous.root, previous.tip, sample.tip]), _alpha(CYAN, alpha))
		canvas.draw_colored_polygon(PackedVector2Array([previous.root, sample.tip, sample.root]), _alpha(CYAN, alpha))
		canvas.draw_line(previous.tip, sample.tip, _alpha(SILVER, alpha * 2.0), 1.1, true)

static func _draw_dash(canvas: Node2D, effect: Dictionary, age: float, p: float, fade: float, offset: Vector2) -> void:
	var face: float = effect.face
	var travel := clampf(age / float(effect.get("duration", 0.30)), 0.0, 1.0)
	var start: Vector2 = effect.pos - Vector2(0, 64 + effect.get("height", 0.0))
	var target: Vector2 = effect.pos.lerp(effect.end, 1.0 - pow(1.0 - travel, 2.0)) - Vector2(0, 64 + effect.get("height", 0.0))
	var length := start.distance_to(target)
	canvas.draw_set_transform(target + offset, 0, Vector2(face, 1.0))
	if length > 2.0:
		_lance(canvas, Vector2(-length, -5), Vector2(28, -5), 14.0 * fade, _alpha(CYAN, fade * 0.16))
		_lance(canvas, Vector2(-length * 0.90, -5), Vector2(22, -5), 4.5 * fade, _alpha(SILVER, fade * 0.8))
		for index in range(5):
			var x := -length * (0.2 + index * 0.16)
			var y := (index % 2 * 2.0 - 1.0) * (12.0 + index * 5.0)
			_lance(canvas, Vector2(x - 29, y), Vector2(x + 12, y - 3), 1.7, _alpha(CYAN, fade * 0.5))
	canvas.draw_set_transform(target + offset, -0.16 * face, Vector2(face, 0.72))
	_sweep(canvas, 68.0 + p * 12.0, fade * 0.75, Color.WHITE)

static func _draw_charge(canvas: Node2D, effect: Dictionary, p: float, offset: Vector2) -> void:
	var ultimate: bool = effect.kind == "ultimate_charge"
	var color := GOLD if ultimate else VIOLET
	var face: float = effect.face
	var center: Vector2 = effect.pos - Vector2(0, 104 + effect.get("height", 0.0)) + offset
	canvas.draw_set_transform(center, 0, Vector2(face, 1))
	var strength := smoothstep(0.0, 0.75, p)
	for index in range(7 if ultimate else 4):
		var a := index * 2.399 + 0.4
		var distance := lerpf(95.0 if ultimate else 58.0, 9.0, p)
		var point := Vector2.from_angle(a) * distance
		var direction := -point.normalized()
		_lance(canvas, point - direction * 7.0, point + direction * 4.0, 1.8, _alpha(color, strength * 0.8))
	_glint(canvas, Vector2(12, -14), 8.0 + strength * 12.0, strength * 0.75, color)
	if ultimate:
		_lance(canvas, Vector2(-75 * strength, -14), Vector2(95 * strength, -14), 2.0, _alpha(GOLD, strength * 0.35))

static func _draw_ultimate(canvas: Node2D, effect: Dictionary, origin: Vector2, age: float, p: float, fade: float) -> void:
	var stage: int = effect.stage
	var face: float = effect.face
	var heavy := stage == 4
	var radius: float = minf(effect.get("size", 470.0), 485.0)
	var angle := [-0.15, 0.13, -0.06, -0.10][clampi(stage - 1, 0, 3)] as float
	var color := GOLD if heavy else (CYAN if stage != 2 else VIOLET)
	canvas.draw_set_transform(origin, angle * face)
	_spatial_cut(canvas, radius * (0.78 + minf(age * 3.5, 0.22)), 24.0 if heavy else 10.0, p, fade, color)
	if heavy:
		# Two low wings leave the fighter silhouette and HUD visible.
		for side in [-1.0, 1.0]:
			var wing := origin + Vector2(side * 155.0, 0)
			canvas.draw_set_transform(wing, -0.12 * side, Vector2(side, 0.45))
			_sweep(canvas, 205.0 * (0.88 + minf(age * 2.0, 0.18)), fade * 0.80, Color("fff0cc"))
			_shards(canvas, 230.0, p, fade * 0.8, GOLD, 7)
		canvas.draw_set_transform(origin)
		_glint(canvas, Vector2.ZERO, 26.0 * (1.0 - p), fade * 0.8, GOLD)
	else:
		canvas.draw_set_transform(origin, angle * face)
		_shards(canvas, radius * 0.65, p, fade * 0.6, color, 5)

static func _draw_hit(canvas: Node2D, effect: Dictionary, p: float, fade: float, offset: Vector2) -> void:
	var radius: float = effect.get("size", 38.0)
	var face: float = effect.get("face", 1.0)
	var direction: Vector2 = effect.get("direction", Vector2(face, -0.16))
	var color: Color = effect.color
	canvas.draw_set_transform(effect.pos + offset, direction.angle(), Vector2.ONE)
	_glint(canvas, Vector2.ZERO, radius * 0.45 * (1.0 - p), fade, color)
	for index in range(6):
		var angle := -1.1 + index * 0.43
		var ray := Vector2.from_angle(angle)
		var distance := radius * (0.25 + p * 0.95)
		_lance(canvas, ray * distance * 0.42, ray * distance, (2.5 if index % 2 == 0 else 1.4) * fade, _alpha(SILVER if index % 2 == 0 else color, fade))

static func _sweep(canvas: Node2D, radius: float, opacity: float, tint: Color) -> void:
	var extent := radius * 2.25
	tint.a = clampf(opacity, 0.0, 1.0)
	canvas.draw_texture_rect(CRESCENT, Rect2(Vector2.ONE * -extent * 0.5, Vector2.ONE * extent), false, tint)

static func _arc_filaments(canvas: Node2D, radius: float, p: float, opacity: float, color: Color, count: int) -> void:
	for index in range(count):
		var first := -1.42 + index * 0.18 + p * 0.24
		var last := 0.92 + index * 0.14 - p * 0.40
		canvas.draw_arc(Vector2.ZERO, radius * (0.94 + index * 0.065), first, last, 34, _alpha(color, opacity / (index + 1.0)), 1.0, true)

static func _spatial_cut(canvas: Node2D, radius: float, width: float, p: float, fade: float, color: Color) -> void:
	var start := Vector2(-radius, 0)
	var end := Vector2(radius, 0)
	_lance(canvas, start, end, width * 1.8, _alpha(color, fade * 0.09))
	_lance(canvas, start, end, width * 0.66, _alpha(color, fade * 0.26))
	_lance(canvas, start * 0.98, end * 0.98, width * 0.24, _alpha(SILVER, fade * 0.92))
	for index in range(5):
		var x := radius * (-0.76 + index * 0.36)
		var side := -1.0 if index % 2 else 1.0
		var drift := side * (9.0 + p * 29.0)
		_lance(canvas, Vector2(x - 30, drift), Vector2(x + 46, drift - side * 5), 2.0 * (1.0 - p), _alpha(color, fade * 0.43))

static func _shards(canvas: Node2D, radius: float, p: float, opacity: float, color: Color, count: int) -> void:
	for index in range(count):
		var angle := lerpf(-1.3, 1.2, float(index) / maxf(count - 1.0, 1.0)) + sin(index * 7.7) * 0.08
		var dir := Vector2.from_angle(angle)
		var distance := radius * (0.94 + p * (0.17 + fmod(index * 0.37, 0.24)))
		var pos := dir * distance
		var tangent := Vector2(-dir.y, dir.x)
		_lance(canvas, pos - tangent * (4.0 + index % 3 * 2.0), pos + tangent * 3.0, 1.6, _alpha(color, opacity * (0.55 + index % 2 * 0.3)))

static func _lance(canvas: Node2D, start: Vector2, end: Vector2, width: float, color: Color) -> void:
	if width <= 0.05 or color.a <= 0.001 or start.distance_squared_to(end) < 0.01:
		return
	var normal := (end - start).normalized().orthogonal() * width * 0.5
	var middle := start.lerp(end, 0.55)
	canvas.draw_colored_polygon(PackedVector2Array([start, middle + normal, end, middle - normal]), color)

static func _glint(canvas: Node2D, pos: Vector2, size: float, opacity: float, color: Color) -> void:
	_lance(canvas, pos - Vector2(size, 0), pos + Vector2(size, 0), size * 0.22, _alpha(color, opacity * 0.65))
	_lance(canvas, pos - Vector2(0, size * 0.65), pos + Vector2(0, size * 0.65), size * 0.12, _alpha(SILVER, opacity))
	canvas.draw_circle(pos, maxf(0.2, size * 0.08), _alpha(SILVER, opacity))

static func _alpha(color: Color, opacity: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(opacity, 0.0, 1.0))
