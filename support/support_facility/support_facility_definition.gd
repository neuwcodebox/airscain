class_name SupportFacilityDefinition
extends DefenseDefinition

@export var work_capacity: float = 4.0
@export var concurrent_tasks: int = 2

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if work_capacity <= 0.0 or concurrent_tasks < 1:
		return "군수지원시설 처리량이 올바르지 않습니다"
	return ""
