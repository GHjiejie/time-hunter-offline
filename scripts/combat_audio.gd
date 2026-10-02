class_name CombatAudio
extends RefCounted

## Offline, cached synthesis: broadband blade hiss, metallic strike and low
## transient weight. No per-hit sample generation on a phone.
static func make_sound(kind: String) -> AudioStreamWAV:
	var duration := 0.12
	match kind:
		"heavy": duration = 0.30
		"dash": duration = 0.22
		"burst": duration = 0.35
		"ultimate": duration = 0.50
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 80137
	var low_noise := 0.0
	for index in range(count):
		var t := float(index) / rate
		var progress := float(index) / count
		var noise := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.12)
		var value := 0.0
		match kind:
			"hit", "heavy":
				var envelope := exp(-t * (19.0 if kind == "hit" else 12.0))
				var bass := sin(TAU * (125.0 * t - 95.0 * t * t))
				var metal := sin(TAU * 1670.0 * t) * exp(-t * 45.0)
				value = (bass * 0.34 + low_noise * 0.55 + noise * 0.22 + metal * 0.19) * envelope
			"dash":
				value = (noise * 0.34 + sin(TAU * (950.0 * t - 1500.0 * t * t)) * 0.12) * sin(progress * PI) * (1.0 - progress)
			"burst", "ultimate":
				var ramp := sin(progress * PI) * 0.7
				value = (sin(TAU * (85.0 * t + 620.0 * t * t)) * 0.32 + low_noise * 0.65 + noise * 0.12) * ramp
		bytes.encode_s16(index * 2, int(clampf(value, -0.95, 0.95) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = bytes
	return stream
