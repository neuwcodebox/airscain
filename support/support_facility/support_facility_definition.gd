class_name SupportFacilityDefinition
extends DefenseDefinition

@export var work_capacity: float = 4.0
@export var concurrent_tasks: int = 2
@export var power_capacity: float = 20.0

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if work_capacity <= 0.0 or concurrent_tasks < 1 or power_capacity < 0.0:
		return "통합 지원기지 처리량이 올바르지 않습니다"
	return ""
