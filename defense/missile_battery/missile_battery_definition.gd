class_name MissileBatteryDefinition
extends DefenseDefinition

@export var attack_range: float = 300.0
@export var fire_interval: float = 2.2
@export var engagement_channels: int = 2
@export var maximum_interceptors_per_track: int = 2
@export var c2_range: float = 600.0
@export var minimum_engagement_altitude: float = 0.0
@export var maximum_engagement_altitude: float = 450.0
@export var munitions: Array[MissileMunitionDefinition] = []

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if attack_range <= 0.0 or fire_interval <= 0.0 or engagement_channels < 1 or maximum_interceptors_per_track < 1 or maximum_interceptors_per_track > engagement_channels or c2_range <= 0.0 or minimum_engagement_altitude < 0.0 or maximum_engagement_altitude <= minimum_engagement_altitude or munitions.is_empty():
		return "미사일 포대 설정값은 0보다 커야 합니다"
	var ids: Dictionary[StringName, bool] = {}
	for munition: MissileMunitionDefinition in munitions:
		if munition == null or ids.has(munition.id):
			return "미사일 탄종이 없거나 ID가 중복됩니다"
		var munition_error := munition.validation_error()
		if not munition_error.is_empty():
			return munition_error
		ids[munition.id] = true
	return ""
