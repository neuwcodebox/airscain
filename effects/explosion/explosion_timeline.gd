class_name ExplosionTimeline
extends RefCounted

const CORE_DURATION := 0.52
const HALO_DURATION := 0.9
const PRESSURE_DELAY := 0.05
const PRESSURE_DURATION := 1.2
const GROUND_WAVE_DURATION := 1.35
const GLOW_DURATION := 1.0
const TOTAL_DURATION := 4.0

class State:
	extends RefCounted

	var core_scale: float
	var core_alpha: float
	var halo_scale: float
	var halo_alpha: float
	var pressure_scale: float
	var pressure_alpha: float
	var ground_wave_scale: float
	var ground_wave_alpha: float
	var glow_scale: float
	var glow_alpha: float

static func sample(elapsed: float, radius: float) -> State:
	var state := State.new()
	var core_progress := _progress(elapsed, 0.0, CORE_DURATION)
	state.core_scale = radius * lerpf(0.16, 1.05, smoothstep(0.0, 1.0, core_progress))
	state.core_alpha = 1.0 - smoothstep(0.12, 1.0, core_progress)

	var halo_progress := _progress(elapsed, 0.0, HALO_DURATION)
	state.halo_scale = radius * lerpf(0.32, 1.65, smoothstep(0.0, 1.0, halo_progress))
	state.halo_alpha = 0.5 * (1.0 - smoothstep(0.08, 1.0, halo_progress))

	var pressure_progress := _progress(elapsed, PRESSURE_DELAY, PRESSURE_DURATION)
	state.pressure_scale = radius * lerpf(0.22, 2.05, smoothstep(0.0, 1.0, pressure_progress))
	state.pressure_alpha = 0.68 * _ring_alpha(pressure_progress)

	var ground_progress := _progress(elapsed, 0.0, GROUND_WAVE_DURATION)
	state.ground_wave_scale = radius * lerpf(0.16, 2.35, smoothstep(0.0, 1.0, ground_progress))
	state.ground_wave_alpha = 0.82 * (1.0 - smoothstep(0.06, 1.0, ground_progress))

	var glow_progress := _progress(elapsed, 0.0, GLOW_DURATION)
	state.glow_scale = radius * lerpf(0.7, 2.4, smoothstep(0.0, 1.0, glow_progress))
	state.glow_alpha = 0.34 * (1.0 - smoothstep(0.0, 1.0, glow_progress))
	return state

static func _progress(elapsed: float, delay: float, duration: float) -> float:
	return clampf((elapsed - delay) / duration, 0.0, 1.0)

static func _ring_alpha(progress: float) -> float:
	var fade_in := smoothstep(0.0, 0.08, progress)
	var fade_out := 1.0 - smoothstep(0.18, 1.0, progress)
	return fade_in * fade_out
