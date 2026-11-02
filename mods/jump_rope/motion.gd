extends RefCounted
# Orientation-independent magnitude detector. No raw sensor samples leave the phone.
var threshold := 2.6
var release_threshold := 1.0
var cooldown_ms := 350
var baseline := 9.81
var samples := 0
var elapsed := 0.0
var available := false
var calibrated := false
var armed := true
var last_jump := -10000
var strength := 0.0
var total := 0.0
var square_total := 0.0
var calibration_seconds := 1.2

func reset() -> void:
	samples = 0
	elapsed = 0.0
	available = false
	calibrated = false
	armed = true
	last_jump = -10000
	total = 0.0
	square_total = 0.0
	strength = 0.0

func sample(acceleration: Vector3, delta: float, now_ms: int) -> bool:
	elapsed += clampf(delta, 0.0, 0.1)
	var magnitude := acceleration.length()
	if not is_finite(magnitude) or magnitude < 0.1:
		return false
	available = true
	if not calibrated:
		samples += 1
		total += magnitude
		square_total += magnitude * magnitude
		if samples >= 30 and elapsed >= calibration_seconds:
			baseline = total / samples
			var variance := maxf(0, square_total / samples - baseline * baseline)
			if variance > 1.0:
				reset() # Ask user to hold still, never calibrate against active shaking.
				return false
			calibrated = true
		return false
	strength = absf(magnitude - baseline)
	if strength < release_threshold:
		armed = true
		baseline = lerpf(baseline, magnitude, 0.01)
	if armed and strength >= threshold and now_ms - last_jump >= cooldown_ms:
		armed = false
		last_jump = now_ms
		return true
	return false
