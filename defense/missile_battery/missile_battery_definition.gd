class_name MissileBatteryDefinition
extends DefenseDefinition

@export var attack_range: float = 300.0
@export var fire_interval: float = 2.2
@export var interceptor_speed: float = 200.0
@export var interceptor_turn_rate_degrees: float = 240.0
@export var interceptor_lifetime: float = 5.0
@export var interceptor_damage: float = 100.0
@export var proximity_radius: float = 15.0
@export_range(0.0, 1.0) var infrared_sensitivity: float = 0.65
@export_range(0.0, 1.0) var radar_sensitivity: float = 0.65
@export var engagement_channels: int = 2
@export var c2_range: float = 600.0
@export var small_target_match: float = 0.22
@export var magazine_capacity: int = 12
@export var reserve_ammunition: int = 12
@export var reload_duration: float = 5.0
@export var resupply_cost: int = 8
@export var resupply_work: float = 8.0

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or fire_interval <= 0.0 or interceptor_speed <= 0.0 or interceptor_turn_rate_degrees <= 0.0 or interceptor_lifetime <= 0.0 or interceptor_damage <= 0.0 or proximity_radius <= 0.0 or infrared_sensitivity < 0.0 or infrared_sensitivity > 1.0 or radar_sensitivity < 0.0 or radar_sensitivity > 1.0 or engagement_channels < 1 or c2_range <= 0.0 or small_target_match < 0.0 or small_target_match > 1.0 or magazine_capacity < 1 or reserve_ammunition < 0 or reload_duration <= 0.0 or resupply_cost < 0 or resupply_work <= 0.0:
		return "미사일 포대 설정값은 0보다 커야 합니다"
	return ""
