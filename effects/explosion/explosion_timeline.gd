class_name ExplosionTimeline
extends RefCounted

const FLASH_DURATION := 0.20
const LIGHT_DURATION := 0.28
const TOTAL_DURATION := 4.0

class State:
	extends RefCounted
	var core_scale: float
	var core_alpha: float
	var light_energy: float

static func sample(elapsed: float, radius: float, ground: bool = false, previous_elapsed: float = -1.0) -> State:
	var state := State.new()
	state.core_scale = radius * (0.17 + 0.18 * (1.0 - exp(-elapsed / 0.075)))
	state.core_alpha = _frame_average(previous_elapsed, elapsed, false) if previous_elapsed >= 0.0 else _pulse(elapsed, false)
	var peak := 22.0 if ground else 13.0
	state.light_energy = peak * (_frame_average(previous_elapsed, elapsed, true) if previous_elapsed >= 0.0 else _pulse(elapsed, true))
	return state

static func _pulse(t: float, light: bool) -> float:
	var duration := LIGHT_DURATION if light else FLASH_DURATION
	if t >= duration:
		return 0.0
	var decay := 0.085 if light else 0.060
	var fade := 0.18 if light else 0.13
	return exp(-maxf(t, 0.0) / decay) * (1.0 - smoothstep(fade, duration, t))

static func _frame_average(previous: float, current: float, light: bool) -> float:
	# Approximate exposure across a slow frame so the brief peak is still visible.
	if current <= previous:
		return _pulse(current, light)
	var total := 0.0
	for index: int in 6:
		var t := lerpf(previous, current, (float(index) + 0.5) / 6.0)
		total += _pulse(t, light)
	return total / 6.0
