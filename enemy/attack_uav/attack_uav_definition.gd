class_name AttackUavDefinition
extends ThreatDefinition

@export var maximum_health: float = 100.0
@export var base_speed: float = 30.0
@export var cruise_altitude: float = 70.0
@export var terminal_distance: float = 120.0
@export var mission_damage: int = 10

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if maximum_health <= 0.0 or base_speed <= 0.0 or cruise_altitude <= 0.0 or terminal_distance <= 0.0 or mission_damage <= 0:
		return "공격 UAV 설정값은 0보다 커야 합니다"
	return ""
