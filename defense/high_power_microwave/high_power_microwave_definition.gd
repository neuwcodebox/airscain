class_name HighPowerMicrowaveDefinition
extends DefenseDefinition

@export var attack_range: float = 210.0
@export var effect_radius: float = 72.0
@export var pulse_interval: float = 3.5
@export var electronic_damage: float = 48.0
@export var energy_capacity: float = 70.0
@export var energy_per_pulse: float = 35.0
@export var recharge_rate: float = 12.0
@export var power_demand: float = 18.0
@export var c2_range: float = 520.0

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or effect_radius <= 0.0 or pulse_interval <= 0.0 or electronic_damage <= 0.0 or energy_capacity <= 0.0 or energy_per_pulse <= 0.0 or energy_per_pulse > energy_capacity or recharge_rate <= 0.0 or power_demand <= 0.0 or c2_range <= 0.0:
		return "고출력 마이크로파 설정값이 올바르지 않습니다"
	return ""
