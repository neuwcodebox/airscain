class_name HighEnergyLaserDefinition
extends DefenseDefinition

@export var attack_range: float = 260.0
@export var pulse_interval: float = 0.25
@export var pulse_damage: float = 18.0
@export var energy_capacity: float = 48.0
@export var energy_per_pulse: float = 8.0
@export var recharge_rate: float = 10.0
@export var power_demand: float = 12.0
@export var heat_capacity: float = 42.0
@export var heat_per_pulse: float = 14.0
@export var cooling_rate: float = 12.0
@export var hit_tolerance: float = 16.0
@export var c2_range: float = 520.0

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or pulse_interval <= 0.0 or pulse_damage <= 0.0 or energy_capacity <= 0.0 or energy_per_pulse <= 0.0 or energy_per_pulse > energy_capacity or recharge_rate <= 0.0 or power_demand <= 0.0 or heat_capacity <= 0.0 or heat_per_pulse <= 0.0 or cooling_rate <= 0.0 or hit_tolerance <= 0.0 or c2_range <= 0.0:
		return "고출력 레이저 설정값이 올바르지 않습니다"
	return ""
