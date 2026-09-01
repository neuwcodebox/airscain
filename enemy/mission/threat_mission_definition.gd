class_name ThreatMissionDefinition
extends Resource

enum Type { IMPACT, RECONNAISSANCE, STRIKE_AND_EXIT }
enum TargetRole { CITY, SENSOR, COMMAND, SUPPORT }

@export var type := Type.IMPACT
@export var target_role := TargetRole.CITY
@export var damage: float = 10.0
@export var action_distance: float = 5.0
@export var action_duration: float = 0.0

func validation_error() -> String:
	if damage < 0.0 or action_distance <= 0.0 or action_duration < 0.0:
		return "위협 임무 프로필이 올바르지 않습니다"
	if type == Type.IMPACT and damage <= 0.0:
		return "충돌 임무 피해량이 올바르지 않습니다"
	return ""
