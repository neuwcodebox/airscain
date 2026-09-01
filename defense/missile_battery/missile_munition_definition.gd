class_name MissileMunitionDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var interceptor_speed: float = 200.0
@export var interceptor_turn_rate_degrees: float = 240.0
@export var interceptor_lifetime: float = 5.0
@export var interceptor_damage: float = 100.0
@export var proximity_radius: float = 15.0
@export_range(0.0, 1.0) var infrared_sensitivity: float = 0.65
@export_range(0.0, 1.0) var radar_sensitivity: float = 0.65
@export var preferred_classes: Array[StringName] = []
@export var minimum_preferred_speed: float = 0.0
@export_range(0.0, 1.0) var other_target_match: float = 1.0
@export_range(0.0, 1.0) var small_target_match: float = 0.22
@export var high_cost: bool = false
@export var salvo_size: int = 1
@export var magazine_capacity: int = 12
@export var reserve_ammunition: int = 12
@export var reload_duration: float = 5.0
@export var resupply_cost: int = 8
@export var resupply_work: float = 8.0

func match_for(classification: StringName, estimated_speed: float = 0.0) -> float:
	var result := small_target_match if classification == &"small_uav" else 1.0
	var constrained := not preferred_classes.is_empty() or minimum_preferred_speed > 0.0
	return result if not constrained or is_preferred(classification, estimated_speed) else result * other_target_match

func is_preferred(classification: StringName, estimated_speed: float) -> bool:
	return preferred_classes.has(classification) or minimum_preferred_speed > 0.0 and estimated_speed >= minimum_preferred_speed

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or interceptor_speed <= 0.0 or interceptor_turn_rate_degrees <= 0.0 or interceptor_lifetime <= 0.0 or interceptor_damage <= 0.0 or proximity_radius <= 0.0 or infrared_sensitivity < 0.0 or infrared_sensitivity > 1.0 or radar_sensitivity < 0.0 or radar_sensitivity > 1.0 or minimum_preferred_speed < 0.0 or other_target_match < 0.0 or other_target_match > 1.0 or small_target_match < 0.0 or small_target_match > 1.0 or salvo_size < 1 or magazine_capacity < 1 or reserve_ammunition < 0 or reload_duration <= 0.0 or resupply_cost < 0 or resupply_work <= 0.0:
		return "미사일 탄종 설정값이 올바르지 않습니다"
	return ""
