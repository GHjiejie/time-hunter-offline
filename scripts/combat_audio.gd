class_name CombatAudio
extends RefCounted

## Cached offline synthesis. Charge, release and confirmed contact have separate
## voices, so a miss still has a blade sound without a false impact transient.
static func make_sound(kind: String) -> AudioStreamWAV:
	var duration := 0.12
	match kind:
		"slash": duration = 0.18
		"heavy": duration = 0.23
		"dash": duration = 0.26
		"burst": duration = 0.24
		"ultimate": duration = 0.28
		"charge": duration = 0.43
		"finisher": duration = 0.48
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 80137
	var low_noise := 0.0
	var soft_noise := 0.0
	for index in range(count):
		var t := float(index) / rate
		var progress := float(index) / count
		var noise := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.055)
		soft_noise = lerpf(soft_noise, noise, 0.28)
		var air := soft_noise - low_noise
		var value := 0.0
		match kind:
			"hit":
				var body := sin(TAU * (185.0 * t - 190.0 * t * t)) * exp(-t * 36.0)
				var edge := sin(TAU * 2140.0 * t) * exp(-t * 73.0)
				var ring := sin(TAU * 3420.0 * t) * exp(-t * 56.0)
				value = body * 0.26 + edge * 0.14 + ring * 0.055 + air * 0.62 * exp(-t * 48.0)
			"heavy":
				var body := sin(TAU * (118.0 * t - 120.0 * t * t)) * exp(-t * 16.0)
				var edge := sin(TAU * 1840.0 * t) * exp(-t * 65.0)
				value = body * 0.47 + edge * 0.11 + air * 0.63 * exp(-t * 30.0)
			"slash":
				var sweep := pow(sin(progress * PI), 1.35) * exp(-progress * 1.7)
				var edge := sin(TAU * (1780.0 * t - 2900.0 * t * t))
				value = (air * 0.79 + edge * 0.075) * sweep
			"dash":
				var sweep := sin(progress * PI) * exp(-progress * 1.1)
				var blade := sin(TAU * (1340.0 * t - 1550.0 * t * t))
				var undertone := sin(TAU * (180.0 * t - 95.0 * t * t))
				value = (air * 0.76 + blade * 0.10 + undertone * 0.14) * sweep
			"burst":
				var slice := sin(progress * PI) * exp(-progress * 2.4)
				var crystal := sin(TAU * (1180.0 * t - 950.0 * t * t)) + sin(TAU * 1770.0 * t) * 0.38
				value = air * 0.74 * slice + crystal * 0.115 * exp(-t * 14.0)
			"ultimate":
				var slice := sin(progress * PI) * exp(-progress * 1.8)
				var crystal := sin(TAU * (1460.0 * t - 1700.0 * t * t)) + sin(TAU * 2190.0 * t) * 0.32
				var body := sin(TAU * (185.0 * t - 135.0 * t * t))
				value = (air * 0.74 + body * 0.16) * slice + crystal * 0.10 * exp(-t * 13.0)
			"charge":
				var rise := pow(sin(progress * PI), 0.75)
				var hum := sin(TAU * (285.0 * t + 440.0 * t * t))
				var overtone := sin(TAU * (570.0 * t + 880.0 * t * t))
				value = (hum * 0.16 + overtone * 0.06 + air * 0.28) * rise
			"finisher":
				var body := sin(TAU * (96.0 * t - 58.0 * t * t)) * exp(-t * 10.0)
				var crack := air * exp(-t * 28.0)
				var chime := (sin(TAU * 1320.0 * t) + sin(TAU * 1980.0 * t) * 0.38) * exp(-t * 11.0)
				var tail := air * sin(progress * PI) * exp(-progress * 3.1)
				value = body * 0.44 + crack * 0.62 + chime * 0.095 + tail * 0.20
		# A short ramp and final fade prevent clicks when a cached voice starts or
		# is reclaimed; no runtime synthesis is needed for a crowded encounter.
		var attack := minf(1.0, t / 0.0025)
		var fade := minf(1.0, (duration - t) / 0.015)
		value *= attack * fade
		bytes.encode_s16(index * 2, int(clampf(value, -0.88, 0.88) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
