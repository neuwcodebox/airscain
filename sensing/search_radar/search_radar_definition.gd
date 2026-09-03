class_name SearchRadarDefinition
extends DefenseDefinition

@export var detection_range: float = 700.0
@export var scan_interval: float = 0.4
@export var sensor_quality: float = 0.9
@export var range_exponent: float = 4.0
@export var c2_range: float = 700.0
@export var minimum_detection_altitude: float = 0.0
@export var maximum_detection_altitude: float = 260.0

func placement_c2_roles() -> int:
	return DefenseUnit.C2Role.SENSOR

func placement_c2_range() -> float:
	return c2_range

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if detection_range <= 0.0 or scan_interval <= 0.0:
		return "탐색 레이더 거리와 탐색 주기는 0보다 커야 합니다"
	if sensor_quality <= 0.0 or sensor_quality > 1.0 or range_exponent <= 0.0 or c2_range <= 0.0 or minimum_detection_altitude < 0.0 or maximum_detection_altitude <= minimum_detection_altitude:
		return "탐색 레이더 품질 설정이 올바르지 않습니다"
	return ""
