class_name CityDamageVignette
extends ColorRect

const FADE_DURATION := 0.75
const STRENGTH_PARAMETER := &"strength"

var elapsed: float = FADE_DURATION

func _ready() -> void:
	_set_strength(0.0)
	hide()
	set_process(false)

func show_damage(amount: int) -> void:
	if amount <= 0:
		return
	elapsed = 0.0
	show()
	_set_strength(1.0)
	set_process(true)

func _process(delta: float) -> void:
	elapsed = minf(FADE_DURATION, elapsed + maxf(0.0, delta))
	var remaining := 1.0 - elapsed / FADE_DURATION
	_set_strength(smoothstep(0.0, 1.0, remaining))
	if elapsed >= FADE_DURATION:
		hide()
		set_process(false)

func _set_strength(value: float) -> void:
	(material as ShaderMaterial).set_shader_parameter(STRENGTH_PARAMETER, value)
