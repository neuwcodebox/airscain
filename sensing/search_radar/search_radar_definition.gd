class_name SearchRadarDefinition
extends DefenseDefinition

@export var detection_range: float = 520.0
@export var scan_interval: float = 0.8
@export var sensor_quality: float = 0.9
@export var range_exponent: float = 4.0

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if detection_range <= 0.0 or scan_interval <= 0.0:
		return "탐색 레이더 거리와 탐색 주기는 0보다 커야 합니다"
	if sensor_quality <= 0.0 or sensor_quality > 1.0 or range_exponent <= 0.0:
		return "탐색 레이더 품질 설정이 올바르지 않습니다"
	return ""
