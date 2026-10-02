class_name Fighter
extends RefCounted

var pos := Vector2.ZERO
var hp := 100.0
var max_hp := 100.0
var facing := 1.0
var height := 0.0
var vertical_speed := 0.0
var invincible := 0.0
var stun := 0.0
var attack_clock := 0.0
var windup := 0.0
var target := Vector2.ZERO
var kind := "drone"
var speed := 100.0
var tint := Color("f58a75")
var id := 0

func tick(delta: float) -> void:
	invincible = maxf(0.0, invincible - delta)
	stun = maxf(0.0, stun - delta)
	attack_clock = maxf(0.0, attack_clock - delta)
	if height > 0.0 or vertical_speed > 0.0:
		height = maxf(0.0, height + vertical_speed * delta)
		vertical_speed -= 1450.0 * delta
		if height <= 0.0:
			vertical_speed = 0.0
