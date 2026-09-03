class_name CommandPostDefinition
extends DefenseDefinition

@export var link_range: float = 700.0

func placement_c2_roles() -> int:
	return DefenseUnit.C2Role.COMMAND

func placement_c2_range() -> float:
	return link_range

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if link_range <= 0.0:
		return "지휘시설 연결 범위는 0보다 커야 합니다"
	return ""
