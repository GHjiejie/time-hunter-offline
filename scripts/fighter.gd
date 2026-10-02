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
var velocity := Vector2.ZERO
# Renderer-facing state. pose_time is elapsed time in the current action.
var pose := "idle"
var pose_time := 0.0
var pose_duration := 0.0
var moving := 0.0
var action_lock := 0.0

func set_pose(name: String, duration: float) -> void:
	pose = name
	pose_time = 0.0
	pose_duration = duration
	action_lock = duration

func tick(delta: float) -> void:
	invincible = maxf(0.0, invincible - delta)
	stun = maxf(0.0, stun - delta)
	attack_clock = maxf(0.0, attack_clock - delta)
	action_lock = maxf(0.0, action_lock - delta)
	if pose_duration > 0.0:
		pose_time = minf(pose_duration, pose_time + delta)
		if action_lock <= 0.0:
			pose = "run" if moving > 0.08 else "idle"
			pose_time = 0.0
			pose_duration = 0.0
	else:
		# Idle and locomotion clips also need a clock, even without an action lock.
		pose_time += delta
	pos += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, 1450.0 * delta)
	if height > 0.0 or vertical_speed > 0.0:
		height = maxf(0.0, height + vertical_speed * delta)
		vertical_speed -= 1450.0 * delta
		if height <= 0.0:
			vertical_speed = 0.0
