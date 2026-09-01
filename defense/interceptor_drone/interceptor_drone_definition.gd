class_name InterceptorDroneDefenseDefinition
extends DefenseDefinition

@export var attack_range: float = 280.0
@export var launch_interval: float = 1.5
@export var drone_speed: float = 95.0
@export var drone_turn_rate_degrees: float = 150.0
@export var drone_endurance: float = 14.0
@export var drone_damage: float = 58.0
@export var proximity_radius: float = 12.0
@export var drone_count: int = 3
@export var engagement_channels: int = 2
@export var recharge_duration: float = 16.0
@export var c2_range: float = 540.0

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or launch_interval <= 0.0 or drone_speed <= 0.0 or drone_turn_rate_degrees <= 0.0 or drone_endurance <= 0.0 or drone_damage <= 0.0 or proximity_radius <= 0.0 or drone_count < 1 or engagement_channels < 1 or engagement_channels > drone_count or recharge_duration <= 0.0 or c2_range <= 0.0:
		return "요격드론 설정값이 올바르지 않습니다"
	return ""
