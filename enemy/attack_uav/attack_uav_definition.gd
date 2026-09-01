class_name AttackUavDefinition
extends ThreatDefinition

@export var maximum_health: float = 100.0
@export var movement: ThreatMovementDefinition
@export var mission: ThreatMissionDefinition
@export var visual_color: Color = Color(0.72, 0.18, 0.12, 1.0)

func validation_error() -> String:
	var base_error := super.validation_error()
	if not base_error.is_empty():
		return base_error
	if maximum_health <= 0.0 or movement == null or mission == null:
		return "공격 UAV 구성 참조가 올바르지 않습니다"
	var movement_error := movement.validation_error()
	if not movement_error.is_empty():
		return movement_error
	var mission_error := mission.validation_error()
	if not mission_error.is_empty():
		return mission_error
	return ""
