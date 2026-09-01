class_name MissileBatteryDefinition
extends DefenseDefinition

@export var attack_range: float = 300.0
@export var fire_interval: float = 2.2
@export var interceptor_speed: float = 180.0
@export var interceptor_turn_rate_degrees: float = 240.0
@export var interceptor_lifetime: float = 5.0
@export var interceptor_damage: float = 100.0

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or fire_interval <= 0.0 or interceptor_speed <= 0.0 or interceptor_turn_rate_degrees <= 0.0 or interceptor_lifetime <= 0.0 or interceptor_damage <= 0.0:
		return "미사일 포대 설정값은 0보다 커야 합니다"
	return ""
